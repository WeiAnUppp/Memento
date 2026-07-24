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
            var spatialAnchor: String? = nil

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
                    spatialAnchor = parsed.spatialAnchor?.trimmingCharacters(in: .whitespaces)
                    await MainActor.run { parsedKeywords = aiKeywords }
                } catch {
                    print("[SearchViewModel] AI 解析失败，降级: \(error)")
                }
            }
            // 无 API 时的空间关系兜底：从原句里抽取"X + 关系词"的参照物 X
            if spatialAnchor == nil {
                spatialAnchor = Self.extractSpatialAnchor(from: query)
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
            print("[SearchViewModel] spatialAnchor: \(spatialAnchor ?? "nil")")
            print("[SearchViewModel] ================")

            // ── 阶段 2：地理编码 ──
            // 只对城市/区县级 locationName 做地理编码。
            // 室内参照物（键盘/抽屉/桌上）走 spatialAnchor，绝不送 CLGeocoder：
            // 它们不是地名，编码要么浪费一次网络请求，要么误配到某个真实坐标污染排序。
            let locationTarget: CLLocationCoordinate2D?
            if let name = locationName, !name.isEmpty {
                locationTarget = await geocodeLocation(name)
            } else {
                locationTarget = nil
            }

            // ── 阶段 3：向量化 ──
            // 使用 AI 扩展后的文本做 embedding（包含原始 searchText + expandedQueries + fuzzyDescription）
            let textForEmbedding: String
            if parsedKeywords != nil, !searchText.isEmpty {
                // 有 AI 解析 → 使用 embeddingText（合并所有扩展词）
                let sq = SearchQuery(
                    keywords: aiKeywords, searchText: searchText, locationName: locationName,
                    spatialAnchor: spatialAnchor,
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

            // ── 阶段 5：时间预过滤 ──
            let timeRange = timeFilter?.dateRange()
            let candidateItems: [(Item, [Float]?)]
            if let range = timeRange {
                candidateItems = itemsWithEmbeddings.filter { item, _ in
                    item.createdAt >= range.start && item.createdAt <= range.end
                }
                if candidateItems.isEmpty {
                    print("[SearchViewModel] 时间过滤后无结果")
                    await MainActor.run { results = []; isSearching = false }
                    return
                }
            } else {
                candidateItems = itemsWithEmbeddings
            }

            // ── 阶段 6：混合排序 ──
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

            // 关键净化：把空间关系词（旁边/附近/里面…）和泛指词（东西/物品…）踢出 coreTerms。
            // 它们无区分度：要么永远匹配不上（拖低正确项覆盖率），要么误命中无关物品描述。
            // 参照物本身走 spatialAnchor 的共位匹配，也从普通词里剔除，避免"键盘"把键盘本体顶到最前。
            coreTerms = Self.stripNonDiscriminative(coreTerms, anchor: spatialAnchor)
            expansionTerms = Self.stripNonDiscriminative(expansionTerms, anchor: spatialAnchor)

            // 场景域兜底：查询含"家/公司/办公室…"但 AI 没提取进 coreTerms 时，主动注入，
            // 保证"家里的东西"能靠场景过滤命中家中物品，而不是退化成向量全量匹配。
            // 只注入【最长的一个】场景域词（避免"家/家里/家中"同时进入稀释覆盖率）；
            // 且仅当 coreTerms 里还没有任何场景域词时才补。
            let alreadyHasScope = coreTerms.contains { Self.sceneScopeWords.contains($0) }
            if !alreadyHasScope,
               let longest = Self.sceneScopeWords
                   .filter({ query.contains($0) })
                   .max(by: { $0.count < $1.count }) {
                coreTerms.append(longest)
            }

            // 本地同义词兜底扩展
            let localSyn = localSynonyms(for: coreTerms)
            expansionTerms = Array(Set(expansionTerms).union(localSyn).subtracting(coreTerms))

            let ranked = rankItems(
                itemsWithEmbeddings: candidateItems,
                queryEmbedding: queryEmbedding,
                coreTerms: coreTerms,
                expansionTerms: expansionTerms,
                aiKeywords: aiKeywords,
                rawQuery: query,
                locationTarget: locationTarget,
                spatialAnchor: spatialAnchor,
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
        spatialAnchor: String?,
        timeFilter: TimeFilter?,
        negativeKeywords: [String]?,
        sortHint: String?,
        queryIntent: String?
    ) -> [SearchResult] {
        let hasVector = queryEmbedding != nil
        let hasAPI = APIConfig().isConfigured
        let queryChars = Set(rawQuery)

        // 时间过滤已在 doSearch 中完成，此处直接使用传入的候选列表
        let candidateItems = itemsWithEmbeddings

        // 提前计算 AI 输出特征，用于模式判断
        let aiHasKeywords = !aiKeywords.isEmpty
        let aiHasLocation = locationTarget != nil
        let hasAnchor = (spatialAnchor?.isEmpty == false)

        // 场景域词兜底：查询里出现"家/公司/办公室…"就【绝不进浏览】——
        // 它是场景过滤条件，不是"列出全部"。防 AI 把"家里的东西"误判成 browse_recent。
        let queryHasSceneScope = Self.sceneScopeWords.contains { rawQuery.contains($0) }

        // 浏览模式：显式意图 OR 纯时间查询（无物品关键词、无地点，仅时间过滤）；有场景域词则一律排除
        let isBrowseMode = !queryHasSceneScope
            && (queryIntent == "browse_recent"
                || (timeFilter != nil && !aiHasKeywords && !aiHasLocation))

        if isBrowseMode {
            let browsed = candidateItems.map { entry in
                SearchResult(item: entry.0, score: 1.0, isBrowse: true,
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
            let textScore: Double      // 文本匹配分 [0, 1]
            let coverageScore: Double  // 查询字符覆盖率 [0, 1]（弱 tiebreaker）
            var vectorScore: Double    // 对比归一化后的向量分 [0, 1]
            let colocationScore: Double // 空间共位分 [0, 1]（参照物命中 nearbyObjects/scene）
            let matchedFields: [String]
            let matchedKeywords: [String]
            let nameMatched: Bool
        }

        // 有意义的查询字符（去停用字），用于覆盖率兜底
        let meaningfulQueryChars = queryChars.filter { ch in
            let s = String(ch)
            return !Self.chineseStopWords.contains(s) && ch != " "
        }

        // 第一遍：文本 / 覆盖 / 共位 / 原始余弦
        var rawCosines: [Double] = []
        var partials: [(item: Item, t: Double, c: Double, coloc: Double,
                        fields: [String], kw: [String], nameHit: Bool)] = []
        for (item, embedding) in candidateItems {
            let (tScore, fields, keywords, nameHit) = multiFieldTextScore(
                item: item, coreTerms: coreTerms, expansionTerms: expansionTerms
            )
            let cScore = charCoverage(queryChars: meaningfulQueryChars, item: item)
            let coloc = colocationScore(anchor: spatialAnchor, item: item)

            var rawCos = 0.0
            if hasVector, let qEmb = queryEmbedding, let iEmb = embedding {
                let sim = Double(cosineSimilarity(qEmb, iEmb))
                rawCos = sim > 0 ? sim : 0
            }
            rawCosines.append(rawCos)
            partials.append((item, tScore, cScore, coloc, fields, keywords, nameHit))
        }

        // 向量对比归一化：把候选集内的余弦拉开差距 + 绝对语义地板。
        // 解决"无关项靠 0.55 余弦混到 40%"的压缩问题。
        let normCosines = normalizeVectorScores(rawCosines)

        var entries: [RankEntry] = []
        for (i, p) in partials.enumerated() {
            entries.append(RankEntry(
                item: p.item, textScore: p.t, coverageScore: p.c,
                vectorScore: normCosines[i], colocationScore: p.coloc,
                matchedFields: p.fields, matchedKeywords: p.kw, nameMatched: p.nameHit
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

            if hasAnchor && !aiHasLocation {
                // ⭐ 空间关系查询（"键盘旁边的东西"）— 共位分绝对主导。
                // 参照物命中物品的 nearbyObjects/scene = 强证据；文本(目标类型)与向量为辅。
                // 没有共位证据的物品(如雨伞)拿不到主导分，自然被拉开。
                let coloc = e.colocationScore
                finalScore = (coloc * 0.60 + e.textScore * 0.18 + e.vectorScore * 0.17 + e.coverageScore * 0.05) * penalty
            } else if aiHasLocation && !aiHasKeywords {
                // ⭐ 纯位置查询（"在上海记录的"）— 位置绝对主导
                let loc = locationRanks[itemId]?.score ?? 0
                // 文本和向量仅作微弱 tiebreaker
                finalScore = (loc * 0.80 + e.textScore * 0.10 + e.coverageScore * 0.05 + e.vectorScore * 0.05) * penalty
            } else if aiHasLocation && aiHasKeywords {
                // ⭐ 位置+物品混合查询（"上海家里的钥匙"）— 位置重要但物品为主
                let loc = locationRanks[itemId]?.score ?? 0
                let coloc = e.colocationScore * 0.10  // 共位小幅加分
                finalScore = (e.textScore * 0.42 + e.vectorScore * 0.15 + loc * 0.33 + e.coverageScore * 0.05 + coloc) * penalty
            } else if aiHasKeywords || hasCore {
                // ⭐ 物品查询（"黑色的钥匙"）— 文本主导，向量补语义，覆盖率兜底，共位小幅加分
                let coloc = e.colocationScore * 0.10
                finalScore = min(1.0, e.textScore * 0.60 + e.vectorScore * 0.28 + e.coverageScore * 0.08 + coloc) * penalty
            } else if hasVector {
                // ⭐ 模糊/无核心词 — 向量主导（已对比归一化），覆盖率兜底
                finalScore = (e.vectorScore * 0.72 + e.coverageScore * 0.28) * penalty
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

        // ── ⑦ 置信度门控（严格展示）→ sortHint → Top-N ──
        scored.sort { $0.score > $1.score }

        // 绝对下限：低于此分基本是噪声，直接丢弃（不进"可能相关"）
        let absoluteFloor = 0.12
        scored = scored.filter { $0.score >= absoluteFloor }
        guard let topScore = scored.first?.score, topScore > 0 else { return [] }

        // 强/弱分界：与最高分的相对差距 + 一个绝对强线。
        // 满足任一即"弱"：分数 < 最高分×0.55，或 分数 < 0.30 绝对强线。
        // → 正确项(如共位 0.72)为强；无关项(如 0.24)被判弱、折叠。
        let strongCutoff = max(topScore * 0.55, 0.30)
        scored = scored.map { r in
            var m = r
            m.isStrong = r.score >= strongCutoff
            return m
        }

        // 若没有任何强结果（最高分本身就低于强线）→ 至少把 top1 提为强，避免"全折叠"观感
        if !scored.contains(where: { $0.isStrong }), var top = scored.first {
            top.isStrong = true
            scored[0] = top
        }

        let final = applySortHint(scored, hint: sortHint)
        // 强结果最多 10 条，弱结果最多再留 5 条供"可能相关"展开
        let strong = final.filter { $0.isStrong }.prefix(10)
        let weak = final.filter { !$0.isStrong }.prefix(5)
        return Array(strong) + Array(weak)
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

    // MARK: ── Co-location Score（空间共位） ──

    /// 空间关系查询的核心：参照物 anchor 是否出现在物品的 nearbyObjects / scene 里。
    /// 命中 nearbyObjects = 强证据（1.0）；仅命中 scene = 中等（0.7）；都没有 = 0。
    /// 只走 nearbyObjects/scene，绝不看 name/description —— 否则"键盘旁边的"会把键盘本体顶上来。
    private func colocationScore(anchor: String?, item: Item) -> Double {
        guard let anchor, !anchor.isEmpty else { return 0 }
        let nearby = item.nearbyObjects ?? ""
        if !nearby.isEmpty, termMatches(anchor, in: nearby) { return 1.0 }
        let scene = item.scene ?? ""
        if !scene.isEmpty, termMatches(anchor, in: scene) { return 0.7 }
        return 0
    }

    // MARK: ── Vector Contrast Normalization（向量对比归一化） ──

    /// 把候选集内的原始余弦相似度重标定，解决 Apple 中文短文本"全挤在 0.5–0.7"的压缩问题。
    /// 策略：
    /// ① 绝对语义地板：最高余弦都低于 floor(0.30) → 语义通道整体不可信，全部衰减到接近 0。
    /// ② 对比拉伸：以中位数为支点，中位数以下压向 0，以上按 (v−median)/(max−median) 拉向 1。
    /// ③ 差距过小（max−median < 0.04）→ 说明大家都差不多，向量无区分力，整体压低当弱 tiebreaker。
    /// 返回与输入等长、[0,1] 的归一化分。
    private func normalizeVectorScores(_ raw: [Double]) -> [Double] {
        guard !raw.isEmpty else { return [] }
        let maxV = raw.max() ?? 0
        // ① 绝对地板：最高都太低 → 没有可信语义证据
        let semanticFloor = 0.30
        if maxV < semanticFloor {
            // 轻微保留排序信息，但压到很低，避免混入高置信
            return raw.map { min(0.15, $0 * 0.3) }
        }
        let sorted = raw.sorted()
        let median = sorted[sorted.count / 2]
        let span = maxV - median
        // ③ 差距过小：向量没有区分力
        if span < 0.04 {
            return raw.map { _ in 0.10 }
        }
        // ② 对比拉伸
        return raw.map { v in
            if v <= median { return 0 }
            return min(1.0, (v - median) / span)
        }
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
                item.scene ?? "", item.nearbyObjects ?? "", item.userNote ?? ""]
            .joined(separator: " ")
    }

    // MARK: ── Spatial Relation / Generic Word Filtering ──

    /// 空间关系词：只表达"在哪儿附近"，本身无区分度，必须踢出匹配词。
    static let spatialRelationWords: Set<String> = [
        "旁边", "旁", "边上", "附近", "周围", "四周", "一旁", "身边",
        "里面", "里边", "里", "内", "中", "当中",
        "上面", "上边", "上", "下面", "下边", "下", "底下",
        "前面", "前", "后面", "后", "左边", "右边", "左", "右",
        "隔壁", "对面", "中间", "之间", "一起", "旁侧", "紧挨", "挨着", "靠近",
    ]

    /// 泛指词：太宽泛，命中等于没命中，还会误配无关物品。
    static let genericItemWords: Set<String> = [
        "东西", "物品", "物件", "玩意", "玩意儿", "家伙", "那个", "这个",
        "东东", "东西们", "物事", "货", "件", "样东西", "个东西",
    ]

    /// 场景域词：表示"一类场所"的场景过滤条件（区别于可地理编码的城市名）。
    /// 出现即禁止进入浏览模式，并作为 scene 过滤词参与匹配。
    static let sceneScopeWords: Set<String> = [
        "家", "家里", "家中", "公司", "办公室", "单位", "工位",
        "学校", "教室", "宿舍", "寝室", "店里", "店", "车里", "车上",
    ]

    /// 从核心/扩展词里剔除关系词、泛指词，以及参照物本身（走共位匹配，不做普通命中）。
    static func stripNonDiscriminative(_ terms: [String], anchor: String?) -> [String] {
        let anchorTrim = anchor?.trimmingCharacters(in: .whitespaces)
        return terms.filter { t in
            let s = t.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return false }
            if spatialRelationWords.contains(s) { return false }
            if genericItemWords.contains(s) { return false }
            if let a = anchorTrim, !a.isEmpty, s == a { return false }
            return true
        }
    }

    /// 无 API 兜底：从原句里抽"参照物 + 关系词"结构的参照物。
    /// 如"键盘旁边的" → "键盘"；"抽屉里的" → "抽屉"。找不到返回 nil。
    static func extractSpatialAnchor(from query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        // 按关系词切分，取关系词【之前】紧邻的 2-4 个 CJK 字作为参照物
        for rel in spatialRelationWords.sorted(by: { $0.count > $1.count }) {
            guard let range = q.range(of: rel) else { continue }
            let before = String(q[q.startIndex..<range.lowerBound])
            // 取 before 末尾连续 CJK 字符
            let cjkTail = before.reversed().prefix { ch in
                ch.unicodeScalars.first.map { $0.value >= 0x4E00 && $0.value <= 0x9FFF } ?? false
            }
            let anchor = String(cjkTail.reversed())
            // 去掉可能粘连的"的""在"等
            let cleaned = anchor.trimmingCharacters(in: CharacterSet(charactersIn: "的在放着搁"))
            if cleaned.count >= 2 { return String(cleaned.suffix(4)) }
        }
        return nil
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
        // 只用高置信结果播报，避免把"可能相关"的弱项也算进"找到 N 个"
        let strong = results.filter { $0.isStrong }
        guard !strong.isEmpty else {
            return results.isEmpty ? nil : "没有很确定的匹配，下面是几个可能相关的"
        }
        let top = strong.prefix(3)
        let names = top.map(\.item.name)
        if strong.count == 1 {
            if let scene = strong[0].item.scene, !scene.isEmpty {
                return "找到「\(names[0])」，在\(scene)"
            }
            return "找到「\(names[0])」"
        }
        return "找到\(strong.count)个相关物品：\(names.joined(separator: "、"))"
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
