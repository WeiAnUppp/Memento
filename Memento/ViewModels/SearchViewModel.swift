//
//  SearchViewModel.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import Accelerate
import NaturalLanguage
import CoreLocation

// MARK: - Search ViewModel

@Observable
final class SearchViewModel {
    var queryText: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false
    var searchError: String?
    var hasSearched: Bool = false

    /// AI 解析后的结构化关键词（UI 展示用）
    var parsedKeywords: [String: String]?

    let speechService = SpeechService()
    var showVoiceError: String?

    private let aiService = AIService()
    private let dbService = DatabaseService.shared
    private let embeddingService = EmbeddingService()

    var suggestionText: String?

    // MARK: - Location Search

    private let geocoder = CLGeocoder()
    private var geocodeCache: [String: CLLocationCoordinate2D] = [:]

    private let chineseTokenizer: NSLinguisticTagger = {
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        return tagger
    }()

    init() {
        Task { await speechService.requestAuthorization() }
    }

    // MARK: - Voice Input

    func startVoiceInput() {
        showVoiceError = nil
        do {
            try speechService.startRecording()
        } catch {
            showVoiceError = error.localizedDescription
        }
    }

    func stopVoiceInput() {
        speechService.stopRecording()
        let cleaned = speechService.cleanedTranscript
        if !cleaned.isEmpty {
            queryText = cleaned
        }
        if !cleaned.isEmpty {
            performSearch()
        }
    }

    // MARK: - Search

    func performSearch() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        searchError = nil
        hasSearched = true
        parsedKeywords = nil
        suggestionText = nil

        Task {
            await doSearch(query: query)
        }
    }

    private func doSearch(query: String) async {
        do {
            // ── 阶段 1：AI 解析 ──
            var searchText = query
            var aiKeywords: [String: String] = [:]
            var locationName: String? = nil
            var timeFilter: TimeFilter? = nil
            var negativeKeywords: [String]? = nil
            var sortHint: String? = nil
            var expandedQueries: [String]? = nil
            var fuzzyDescription: String? = nil
            var queryIntent: String? = nil

            if APIConfig().isConfigured {
                do {
                    let parsed = try await aiService.parseQuery(query)
                    aiKeywords = parsed.keywords
                    if !parsed.searchText.isEmpty { searchText = parsed.searchText }
                    locationName = parsed.locationName
                    timeFilter = parsed.timeFilter
                    negativeKeywords = parsed.negativeKeywords
                    sortHint = parsed.sortHint
                    expandedQueries = parsed.expandedQueries
                    fuzzyDescription = parsed.fuzzyDescription
                    queryIntent = parsed.queryIntent
                    await MainActor.run { parsedKeywords = aiKeywords }
                } catch {
                    print("[SearchViewModel] AI 解析失败，降级: \(error)")
                }
            }

            // 调试：打印 AI 解析结果
            print("[SearchViewModel] === AI解析结果 ===")
            print("[SearchViewModel] 原始查询: '\(query)'")
            print("[SearchViewModel] keywords: \(aiKeywords)")
            print("[SearchViewModel] searchText: '\(searchText)'")
            print("[SearchViewModel] locationName: \(locationName ?? "nil")")
            print("[SearchViewModel] timeFilter: \(timeFilter?.value ?? "nil")")
            print("[SearchViewModel] negativeKeywords: \(negativeKeywords ?? [])")
            print("[SearchViewModel] sortHint: \(sortHint ?? "nil")")
            print("[SearchViewModel] expandedQueries: \(expandedQueries ?? [])")
            print("[SearchViewModel] ================")

            // ── 阶段 2：地理编码（如有地名） ──
            let locationTarget: CLLocationCoordinate2D?
            if let name = locationName, !name.isEmpty {
                locationTarget = await geocodeLocation(name)
            } else {
                let locValue = aiKeywords["位置"] ?? aiKeywords["地点"] ?? ""
                locationTarget = locValue.isEmpty ? nil : await geocodeLocation(locValue)
            }

            // ── 阶段 3：向量化 ──
            // 使用 AI 扩展后的文本做 embedding（包含原始 searchText + expandedQueries + fuzzyDescription）
            let textForEmbedding: String
            if parsedKeywords != nil, !searchText.isEmpty {
                // 有 AI 解析 → 使用 embeddingText（合并所有扩展词）
                let sq = SearchQuery(
                    keywords: aiKeywords, searchText: searchText, locationName: locationName,
                    timeFilter: timeFilter, negativeKeywords: negativeKeywords,
                    sortHint: sortHint, queryIntent: queryIntent,
                    expandedQueries: expandedQueries, fuzzyDescription: fuzzyDescription
                )
                textForEmbedding = sq.embeddingText
            } else {
                textForEmbedding = query
            }
            let queryEmbedding = embeddingService.vector(for: textForEmbedding)

            // ── 阶段 4：获取数据 ──
            let itemsWithEmbeddings = try dbService.fetchAllWithEmbeddings()
            guard !itemsWithEmbeddings.isEmpty else {
                await MainActor.run { results = []; isSearching = false }
                return
            }

            // ── 阶段 5：混合排序 ──
            // coreTerms：用户真正想找的（AI 关键词值 + searchText 分词）→ 必须命中
            // expansionTerms：同义/相关词（AI expandedQueries + fuzzy + 本地词典）→ 命中加分
            var coreTerms: [String]
            var expansionTerms: [String]
            if APIConfig().isConfigured {
                var core = Set<String>()
                for (_, value) in aiKeywords {
                    let v = value.trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { core.insert(v) }
                }
                for t in tokenizeChinese(searchText) { core.insert(t) }
                coreTerms = Array(core)

                var exp = Set<String>()
                for q in (expandedQueries ?? []) {
                    let v = q.trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { exp.insert(v) }
                }
                if let fuzzy = fuzzyDescription {
                    for t in tokenizeChinese(fuzzy) { exp.insert(t) }
                }
                exp.subtract(core)
                expansionTerms = Array(exp)
            } else {
                coreTerms = tokenizeChinese(query)
                expansionTerms = []
            }
            // 本地同义词兜底扩展
            let localSyn = localSynonyms(for: coreTerms)
            expansionTerms = Array(Set(expansionTerms).union(localSyn).subtracting(coreTerms))

            let ranked = rankItems(
                itemsWithEmbeddings: itemsWithEmbeddings,
                queryEmbedding: queryEmbedding,
                coreTerms: coreTerms,
                expansionTerms: expansionTerms,
                aiKeywords: aiKeywords,
                rawQuery: query,
                locationTarget: locationTarget,
                timeFilter: timeFilter,
                negativeKeywords: negativeKeywords,
                sortHint: sortHint,
                queryIntent: queryIntent
            )

            await MainActor.run {
                results = ranked
                isSearching = false
                suggestionText = makeSuggestion(results: ranked)
            }

        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    // MARK: ── Geocoding ──

    private func geocodeLocation(_ name: String) async -> CLLocationCoordinate2D? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let cached = geocodeCache[trimmed] { return cached }

        return await withCheckedContinuation { continuation in
            geocoder.geocodeAddressString(trimmed) { placemarks, error in
                if let coord = placemarks?.first?.location?.coordinate {
                    self.geocodeCache[trimmed] = coord
                    continuation.resume(returning: coord)
                } else {
                    print("[SearchViewModel] 地理编码失败: \(trimmed) — \(error?.localizedDescription ?? "")")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: ── Ranking Engine ──

    /// 新流程：
    /// ① 时间预过滤 → ② 多字段加权文本匹配（核心词覆盖率 + 扩展词加分）
    /// → ③ 向量相似度 → ④ 位置 → ⑤ 加权融合 + 排除词惩罚 → ⑥ 动态阈值 → ⑦ sortHint → Top-10
    private func rankItems(
        itemsWithEmbeddings: [(Item, [Float]?)],
        queryEmbedding: [Float]?,
        coreTerms: [String],
        expansionTerms: [String],
        aiKeywords: [String: String],
        rawQuery: String,
        locationTarget: CLLocationCoordinate2D?,
        timeFilter: TimeFilter?,
        negativeKeywords: [String]?,
        sortHint: String?,
        queryIntent: String?
    ) -> [SearchResult] {
        let hasVector = queryEmbedding != nil
        let hasAPI = APIConfig().isConfigured
        let queryChars = Set(rawQuery)

        // ── ① 时间预过滤 ──
        let timeRange = timeFilter?.dateRange()
        var candidateItems: [(Item, [Float]?)]
        if let range = timeRange {
            candidateItems = itemsWithEmbeddings.filter { item, _ in
                item.createdAt >= range.start && item.createdAt <= range.end
            }
            // 时间过滤后无结果 → 降级为不过滤（宽容策略）
            if candidateItems.isEmpty {
                print("[SearchViewModel] 时间过滤后无结果，降级为全量搜索")
                candidateItems = itemsWithEmbeddings
            }
        } else {
            candidateItems = itemsWithEmbeddings
        }

        // 提前计算 AI 输出特征，用于模式判断
        let aiHasKeywords = !aiKeywords.isEmpty
        let aiHasLocation = locationTarget != nil

        // 浏览模式：显式意图 OR 纯时间查询（无物品关键词、无地点，仅时间过滤）
        let isBrowseMode = queryIntent == "browse_recent"
            || (timeFilter != nil && !aiHasKeywords && !aiHasLocation)

        if isBrowseMode {
            let browsed = candidateItems.map { entry in
                SearchResult(item: entry.0, score: 1.0,
                    matchDetails: SearchResult.MatchDetails(
                        matchedFields: [], matchedKeywords: [],
                        nameMatched: false, locationDistance: nil,
                        timeRelevance: timeRelevanceLabel(for: entry.0.createdAt)
                    ))
            }
            let sorted = applySortHint(browsed, hint: sortHint ?? "newest")
            return Array(sorted.prefix(10))
        }

        // ── ② 文本排名 ──
        struct RankEntry {
            let item: Item
            let embedding: [Float]?
            let textScore: Double      // 文本匹配分 [0, 1]
            let coverageScore: Double  // 查询字符覆盖率 [0, 1]（弱 tiebreaker）
            let vectorScore: Double    // 余弦相似度 [0, 1]
            let matchedFields: [String]
            let matchedKeywords: [String]
            let nameMatched: Bool
        }

        // 有意义的查询字符（去停用字），用于覆盖率兜底
        let meaningfulQueryChars = queryChars.filter { ch in
            let s = String(ch)
            return !Self.chineseStopWords.contains(s) && ch != " "
        }

        var entries: [RankEntry] = []
        for (item, embedding) in candidateItems {
            let (tScore, fields, keywords, nameHit) = multiFieldTextScore(
                item: item, coreTerms: coreTerms, expansionTerms: expansionTerms
            )
            let cScore = charCoverage(queryChars: meaningfulQueryChars, item: item)

            var vScore: Double = 0
            if hasVector, let qEmb = queryEmbedding, let iEmb = embedding {
                let sim = cosineSimilarity(qEmb, iEmb)
                vScore = sim > 0 ? Double(sim) : 0
            }

            entries.append(RankEntry(
                item: item, embedding: embedding,
                textScore: tScore, coverageScore: cScore, vectorScore: vScore,
                matchedFields: fields, matchedKeywords: keywords, nameMatched: nameHit
            ))
        }

        // ── ③ 位置排名（如有地理目标） ──
        var locationRanks: [Int64: (score: Double, distance: Double)] = [:]
        if let target = locationTarget {
            for e in entries {
                let dist = haversineDistance(
                    lat1: e.item.latitude, lon1: e.item.longitude,
                    lat2: target.latitude, lon2: target.longitude
                )
                // dist 单位为【公里】。城市级半衰减：15km → 0.5，同城内高分、跨城快速衰减
                let locScore = 1.0 / (1.0 + dist / 15.0)
                locationRanks[e.item.id ?? 0] = (locScore, dist)
            }
        }

        // ── ④ 自适应模式判断（基于 AI 输出，而非计算分数） ──
        // aiHasKeywords / aiHasLocation 已在上方提前计算

        // 调试日志
        print("[SearchViewModel] 模式判断 — aiHasKeywords:\(aiHasKeywords) aiHasLocation:\(aiHasLocation)")

        // ── ⑤ 融合排序（权重基于查询类型，而非计算分数） ──
        var scored: [SearchResult] = []

        for e in entries {
            let itemId = e.item.id ?? 0

            // 排除词惩罚
            var penalty: Double = 1.0
            if let negWords = negativeKeywords, !negWords.isEmpty {
                let corpus = searchableCorpus(e.item)
                for neg in negWords {
                    let trimmedNeg = neg.trimmingCharacters(in: .whitespaces)
                    if trimmedNeg.count >= 1, corpus.localizedCaseInsensitiveContains(trimmedNeg) {
                        penalty *= 0.3
                    }
                }
            }

            let finalScore: Double
            let hasCore = !coreTerms.isEmpty

            if aiHasLocation && !aiHasKeywords {
                // ⭐ 纯位置查询（"在上海记录的"）— 位置绝对主导
                let loc = locationRanks[itemId]?.score ?? 0
                // 文本和向量仅作微弱 tiebreaker
                finalScore = (loc * 0.80 + e.textScore * 0.10 + e.coverageScore * 0.05 + e.vectorScore * 0.05) * penalty
            } else if aiHasLocation && aiHasKeywords {
                // ⭐ 位置+物品混合查询（"上海家里的钥匙"）— 位置重要但物品为主
                let loc = locationRanks[itemId]?.score ?? 0
                finalScore = (e.textScore * 0.45 + e.vectorScore * 0.15 + loc * 0.35 + e.coverageScore * 0.05) * penalty
            } else if aiHasKeywords || hasCore {
                // ⭐ 物品查询（"黑色的钥匙"）— 文本主导，向量补语义，覆盖率兜底
                finalScore = (e.textScore * 0.62 + e.vectorScore * 0.28 + e.coverageScore * 0.10) * penalty
            } else if hasVector {
                // ⭐ 模糊/无核心词 — 向量主导，覆盖率兜底
                finalScore = (e.vectorScore * 0.70 + e.coverageScore * 0.30) * penalty
            } else {
                // ⭐ 纯文本兜底（无API、无向量）
                finalScore = (e.textScore * 0.70 + e.coverageScore * 0.30) * penalty
            }

            let threshold: Double
            if aiHasLocation && !aiHasKeywords {
                threshold = 0.03  // 纯位置：极低门槛，让所有地理相关物品通过
            } else {
                threshold = hasAPI ? 0.06 : 0.04
            }

            if finalScore >= threshold {
                scored.append(SearchResult(
                    item: e.item,
                    score: finalScore,
                    matchDetails: SearchResult.MatchDetails(
                        matchedFields: e.matchedFields,
                        matchedKeywords: e.matchedKeywords,
                        nameMatched: e.nameMatched,
                        locationDistance: locationRanks[itemId]?.distance,
                        timeRelevance: timeRelevanceLabel(for: e.item.createdAt)
                    )
                ))
            }
        }

        // ── ⑦ 按融合分排序 → 应用 sortHint → 截取 Top-10 ──
        scored.sort { $0.score > $1.score }

        // 动态阈值：取最高分的 20%，但不低于最低门槛
        if let topScore = scored.first?.score, topScore > 0 {
            let dynThreshold = max(topScore * 0.20, 0.06)
            scored = scored.filter { $0.score >= dynThreshold }
        }

        let final = applySortHint(scored, hint: sortHint)
        return Array(final.prefix(10))
    }

    // MARK: ── Multi-Field Weighted Text Matching ──

    /// 分字段权重：name×3, description×2, keywords×1.5, scene×1, userNote×0.5
    ///
    /// 核心思路（修复旧版「稀释」与「归一化抵消」两个 bug）：
    /// - 对每个核心词，在所有字段里找到它命中的「最高权重字段」，记该词得分 = 字段权重/最高权重(3)。
    /// - 总分 = 命中核心词的平均字段权重分 × 核心词覆盖率（命中数/核心词数）。
    ///   → 命中越多、命中在越重要的字段，分越高；漏词直接压低覆盖率。
    /// - 扩展词（同义/相关）只贡献小幅加分（≤0.25），命中不到不惩罚。
    /// 返回：(总分[0,1], 命中字段, 命中词, 名称是否命中)
    private func multiFieldTextScore(
        item: Item,
        coreTerms: [String],
        expansionTerms: [String]
    ) -> (score: Double, fields: [String], keywords: [String], nameMatched: Bool) {
        // 字段文本（keywords 取值，剥离 JSON）
        let kwValues = EmbeddingService.keywordValues(from: item.keywords ?? "")
        let fieldTexts: [(name: String, text: String, weight: Double)] = [
            ("name", item.name, 3.0),
            ("description", item.itemDescription, 2.0),
            ("keywords", kwValues.joined(separator: " "), 1.5),
            ("scene", item.scene ?? "", 1.0),
            ("userNote", item.userNote ?? "", 0.5)
        ]
        let maxWeight = 3.0

        var hitFields = Set<String>()
        var hitKeywords: [String] = []
        var nameMatched = false

        // ── 核心词：覆盖率 + 平均字段权重 ──
        var coreHitCount = 0
        var weightAccum = 0.0
        let core = coreTerms.filter { !$0.isEmpty }
        for term in core {
            var bestWeight = 0.0
            var bestField = ""
            for f in fieldTexts where termMatches(term, in: f.text) {
                if f.weight > bestWeight { bestWeight = f.weight; bestField = f.name }
            }
            if bestWeight > 0 {
                coreHitCount += 1
                weightAccum += bestWeight / maxWeight
                hitFields.insert(bestField)
                hitKeywords.append(term)
                if bestField == "name" { nameMatched = true }
            }
        }

        var coreScore = 0.0
        if !core.isEmpty && coreHitCount > 0 {
            let coverage = Double(coreHitCount) / Double(core.count)     // [0,1]
            let avgFieldWeight = weightAccum / Double(coreHitCount)      // [0,1]
            // 覆盖率为主(权重更高)，字段权重为辅
            coreScore = coverage * (0.55 + 0.45 * avgFieldWeight)
        }

        // ── 扩展词：小幅加分（仅在未被核心词覆盖时）──
        var expBonus = 0.0
        let exp = expansionTerms.filter { !$0.isEmpty }
        if !exp.isEmpty {
            var expHit = 0
            for term in exp {
                var best = 0.0
                var bestField = ""
                for f in fieldTexts where termMatches(term, in: f.text) {
                    if f.weight > best { best = f.weight; bestField = f.name }
                }
                if best > 0 {
                    expHit += 1
                    hitFields.insert(bestField)
                }
            }
            if expHit > 0 {
                // 命中比例 → 最多 0.25 加分
                expBonus = min(0.25, 0.25 * Double(expHit) / Double(exp.count) + 0.08)
            }
        }

        // 无核心词（纯模糊/无 API 且分词为空）→ 扩展词升级为主信号
        let finalScore: Double
        if core.isEmpty {
            finalScore = min(1.0, expBonus > 0 ? min(0.7, expBonus * 2.5) : 0)
        } else {
            finalScore = min(1.0, coreScore + (coreScore > 0 ? expBonus : expBonus * 0.5))
        }

        return (finalScore, Array(hitFields), Array(Set(hitKeywords)), nameMatched)
    }

    /// 单词命中判定：精确子串（双向），拒绝旧版危险的「字符重叠」近似。
    private func termMatches(_ term: String, in text: String) -> Bool {
        guard !text.isEmpty, !term.isEmpty else { return false }
        if text.localizedCaseInsensitiveContains(term) { return true }
        // 反向：term 更长且包含字段短词（如 term="蓝牙耳机" 命中 field 里的 "耳机"）
        if term.count > text.count, term.localizedCaseInsensitiveContains(text), text.count >= 2 {
            return true
        }
        return false
    }

    // MARK: ── Character Coverage ──

    /// 有意义查询字符在物品文本中的覆盖率（查询侧为分母，不惩罚描述丰富的物品）。
    /// 仅作弱 tiebreaker，权重很低。
    private func charCoverage(queryChars: Set<Character>, item: Item) -> Double {
        guard !queryChars.isEmpty else { return 0 }
        let corpus = searchableCorpus(item)
        guard !corpus.isEmpty else { return 0 }
        let itemChars = Set(corpus)
        let hit = queryChars.intersection(itemChars).count
        return Double(hit) / Double(queryChars.count)
    }

    // MARK: ── Local Synonym Expansion ──

    /// 基于本地词典为核心词生成同义/相关词（AI expandedQueries 的兜底）
    private func localSynonyms(for terms: [String]) -> [String] {
        var out = Set<String>()
        for term in terms {
            if let synonyms = chineseSynonymDict[term] {
                out.formUnion(synonyms)
            }
            // 反向查找：term 是否是某个根词的近义词
            for (root, syns) in chineseSynonymDict where syns.contains(term) {
                out.insert(root)
                out.formUnion(syns)
            }
        }
        return Array(out)
    }

    // MARK: ── Sort Hint ──

    private func applySortHint(_ results: [SearchResult], hint: String?) -> [SearchResult] {
        guard let hint else { return results }
        switch hint {
        case "newest":
            return results.sorted { ($0.item.createdAt) > ($1.item.createdAt) }
        case "oldest":
            return results.sorted { ($0.item.createdAt) < ($1.item.createdAt) }
        case "largest":
            // 无尺寸数据，按名称长度倒序作为近似的"重要性"代理
            return results.sorted { ($0.item.name.count) > ($1.item.name.count) }
        case "smallest":
            return results.sorted { ($0.item.name.count) < ($1.item.name.count) }
        default:
            return results
        }
    }

    // MARK: ── Time Relevance ──

    private func timeRelevanceLabel(for date: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { return "本周" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) { return "本月" }
        return nil
    }

    // MARK: ── Haversine Distance ──

    private func haversineDistance(lat1: Double, lon1: Double,
                                   lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
              * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: ── Chinese Stop Words ──

    /// 中文停用词：这些高频词不应参与文本匹配，以免虚高所有物品的文本分
    private static let chineseStopWords: Set<String> = [
        "的", "了", "在", "是", "我", "有", "和", "就", "不", "人", "都",
        "一", "上", "也", "很", "到", "说", "要", "去", "你", "会", "着",
        "没有", "看", "好", "自己", "这", "那", "吗", "吧", "呢", "啊",
        "哦", "嗯", "哈", "呀", "哇", "唉", "嘿", "呵", "嘛", "呗", "啦",
        "个", "把", "被", "让", "给", "对", "从", "比", "向", "跟", "为",
        "什么", "怎么", "哪", "哪个", "哪里", "谁", "怎么样", "为什么",
        "还", "可以", "应该", "能", "会", "可能", "一定", "必须",
        "已经", "正在", "一直", "总是", "经常", "偶尔",
        "些", "每", "各", "某", "另", "其他", "别的",
        "叫", "做", "搞", "弄", "干", "来", "去", "回", "进", "出",
        "那个", "这个", "那些", "这些", "那种", "这种",
        "一下", "一点", "一些", "有点", "一点儿",
        // 搜索常用语气/连接词
        "找", "找找", "帮我", "请问", "看看", "查查", "搜", "搜索",
        "记录", "记录下", "拍", "拍的", "放", "放的", "存放", "搁",
    ]

    private func filterStopWords(_ tokens: [String]) -> [String] {
        tokens.filter { token in
            guard !Self.chineseStopWords.contains(token) else { return false }
            // 单字：仅保留 CJK 单字（"伞""书""笔"有意义），丢弃单个字母/数字
            if token.count == 1 {
                return token.unicodeScalars.first.map { $0.value >= 0x4E00 && $0.value <= 0x9FFF } ?? false
            }
            return true
        }
    }

    // MARK: ── Chinese Tokenization ──

    /// 分词 + 相邻 CJK bigram（无 API 时让"黑色手机"能命中"手机"这类词典词）
    private func tokenizeChinese(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        chineseTokenizer.string = trimmed
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        var tokens: [String] = []
        chineseTokenizer.enumerateTags(
            in: range, scheme: .tokenType,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { _, tokenRange, _, _ in
            let token = (trimmed as NSString).substring(with: tokenRange)
            if !token.isEmpty { tokens.append(token) }
        }
        if tokens.isEmpty { tokens = trimmed.map { String($0) } }

        var result = Set(filterStopWords(tokens))

        // 补充 CJK 相邻 bigram（跳过含停用字的组合）
        let cjkChars = trimmed.filter { ch in
            ch.unicodeScalars.first.map { $0.value >= 0x4E00 && $0.value <= 0x9FFF } ?? false
        }
        let arr = Array(cjkChars)
        if arr.count >= 2 {
            for i in 0..<(arr.count - 1) {
                let a = String(arr[i]), b = String(arr[i + 1])
                if Self.chineseStopWords.contains(a) || Self.chineseStopWords.contains(b) { continue }
                result.insert(a + b)
            }
        }
        return Array(result)
    }

    // MARK: ── Helpers ──

    private func searchableCorpus(_ item: Item) -> String {
        let kw = EmbeddingService.keywordValues(from: item.keywords ?? "").joined(separator: " ")
        return [item.name, item.itemDescription, kw,
                item.scene ?? "", item.userNote ?? ""].joined(separator: " ")
    }

    // MARK: ── Cosine Similarity (Accelerate) ──

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        a.withUnsafeBufferPointer { aPtr in
            b.withUnsafeBufferPointer { bPtr in
                vDSP_dotpr(aPtr.baseAddress!, 1, bPtr.baseAddress!, 1, &dot, vDSP_Length(count))
                vDSP_dotpr(aPtr.baseAddress!, 1, aPtr.baseAddress!, 1, &normA, vDSP_Length(count))
                vDSP_dotpr(bPtr.baseAddress!, 1, bPtr.baseAddress!, 1, &normB, vDSP_Length(count))
            }
        }
        let mag = sqrt(normA) * sqrt(normB)
        return mag > 0 ? dot / mag : 0
    }

    // MARK: ── Suggestion ──

    private func makeSuggestion(results: [SearchResult]) -> String? {
        guard !results.isEmpty else { return nil }
        let top = results.prefix(3)
        let names = top.map(\.item.name)
        if results.count == 1 {
            if let scene = results[0].item.scene, !scene.isEmpty {
                return "找到「\(names[0])」，在\(scene)"
            }
            return "找到「\(names[0])」"
        }
        return "找到\(results.count)个相关物品：\(names.joined(separator: "、"))"
    }
}

// MARK: ── Chinese Synonym Dictionary ──

/// 常用中文物品同义词词典（本地兜底，AI expandedQueries 优先）
private let chineseSynonymDict: [String: [String]] = [
    // 电子设备
    "手机": ["电话", "智能手机", "iPhone", "华为手机", "小米手机", "移动电话"],
    "电脑": ["笔记本", "笔记本电脑", "计算机", "MacBook", "台式机", "主机", "平板"],
    "充电器": ["充电线", "数据线", "充电宝", "电源", "适配器", "插头", "移动电源"],
    "耳机": ["耳塞", "耳麦", "听筒", "AirPods", "蓝牙耳机", "头戴式耳机"],
    "手表": ["腕表", "手环", "智能手表", "Apple Watch", "电子表"],
    "遥控器": ["遥控", "空调遥控", "电视遥控", "机顶盒遥控"],
    "相机": ["照相机", "单反", "微单", "拍立得", "摄影机"],

    // 日常用品
    "钥匙": ["锁匙", "门卡", "门禁", "车钥匙", "门禁卡"],
    "眼镜": ["墨镜", "太阳镜", "近视镜", "老花镜", "眼镜框"],
    "钱包": ["皮夹", "卡包", "钱夹", "零钱包"],
    "杯子": ["水杯", "保温杯", "马克杯", "茶杯", "咖啡杯", "玻璃杯"],
    "雨伞": ["伞", "遮阳伞", "折叠伞", "太阳伞"],
    "梳子": ["梳", "发梳", "头梳"],
    "剪刀": ["剪子", "美工刀", "裁纸刀"],
    "胶带": ["透明胶", "双面胶", "胶布", "胶纸"],

    // 衣物
    "衣服": ["外套", "夹克", "衬衫", "T恤", "上衣", "卫衣", "毛衣"],
    "裤子": ["长裤", "短裤", "牛仔裤", "西裤", "运动裤"],
    "鞋子": ["鞋", "运动鞋", "球鞋", "皮鞋", "拖鞋", "凉鞋", "帆布鞋"],
    "帽子": ["帽", "鸭舌帽", "棒球帽", "渔夫帽", "遮阳帽"],
    "围巾": ["丝巾", "披肩", "方巾"],
    "手套": ["手袜", "保暖手套"],

    // 文具 & 书籍
    "书": ["书籍", "笔记本", "记事本", "手册", "杂志"],
    "笔": ["钢笔", "圆珠笔", "铅笔", "签字笔", "水性笔", "马克笔"],

    // 收纳
    "盒子": ["收纳盒", "箱子", "纸盒", "整理箱", "储物箱"],
    "包": ["背包", "书包", "挎包", "手提包", "双肩包", "腰包", "公文包"],
    "袋子": ["塑料袋", "布袋", "环保袋", "纸袋", "收纳袋"],

    // 证件
    "证件": ["身份证", "护照", "驾照", "学生证", "卡", "银行卡", "信用卡", "会员卡"],

    // 药品 & 健康
    "药品": ["药", "药片", "胶囊", "药丸", "维生素", "感冒药", "创可贴"],
    "口罩": ["面罩", "防护口罩", "N95"],

    // 化妆品
    "化妆品": ["口红", "唇膏", "粉底", "护肤品", "面霜", "防晒", "香水", "眼影"],

    // 食物 & 饮料
    "零食": ["饼干", "薯片", "糖果", "巧克力", "坚果"],
    "饮料": ["水", "矿泉水", "可乐", "果汁", "茶", "咖啡"],

    // 工具
    "工具": ["螺丝刀", "扳手", "钳子", "锤子", "卷尺", "电钻"],
]
