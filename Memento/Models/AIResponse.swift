//
//  AIResponse.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

// MARK: - AI Image Analysis Response

struct AIResponse: Codable, Equatable {
    let name: String
    let description: String
    let scene: String
    let keywords: [String: String]
    let emoji: String?
    /// 画面中相邻/周围可见的物品与环境（如 ["键盘","显示器","鼠标垫"]）。
    /// 用于支撑"键盘旁边的""抽屉里的"这类空间关系查询。Optional 向后兼容旧响应。
    let nearbyObjects: [String]?

    enum CodingKeys: String, CodingKey {
        case name, description, scene, keywords, emoji
        case nearbyObjects = "nearby_objects"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        scene = (try? c.decode(String.self, forKey: .scene)) ?? ""
        keywords = (try? c.decode([String: String].self, forKey: .keywords)) ?? [:]
        emoji = try? c.decode(String.self, forKey: .emoji)
        // nearby_objects 可能是数组或缺失；容错解析
        nearbyObjects = try? c.decode([String].self, forKey: .nearbyObjects)
    }

    init(name: String, description: String, scene: String,
         keywords: [String: String], emoji: String?, nearbyObjects: [String]? = nil) {
        self.name = name
        self.description = description
        self.scene = scene
        self.keywords = keywords
        self.emoji = emoji
        self.nearbyObjects = nearbyObjects
    }
}

// MARK: - Search Query (AI-parsed)

struct SearchQuery: Codable {
    /// 结构化关键词：{"颜色":"黑", "物品":"手机"}
    let keywords: [String: String]
    /// 用于向量搜索的核心文本
    let searchText: String
    /// AI 识别出的城市/区县级地名（如"上海""北京"），用于地理编码
    let locationName: String?

    /// 空间关系查询的参照物（室内，如"键盘""抽屉""桌子"）。
    /// 与 locationName 严格区分：spatialAnchor 匹配物品的 nearbyObjects/scene，绝不做地理编码。
    /// 例："键盘旁边的" → spatialAnchor="键盘"；"抽屉里的" → spatialAnchor="抽屉"。
    let spatialAnchor: String?

    // MARK: 新增字段（全部 Optional，向后兼容旧版 AI 响应）

    /// 时间过滤条件（昨天/上周/最近3天等）
    let timeFilter: TimeFilter?
    /// 排除词列表（如["黑色","卧室"]），匹配这些词的物品会被降权或排除
    let negativeKeywords: [String]?
    /// 排序提示：largest / smallest / newest / oldest
    let sortHint: String?
    /// 查询意图分类：find_item / browse_recent / count_items / follow_up
    let queryIntent: String?
    /// AI 推测的同义词/相关词，用于扩展文本匹配和向量搜索
    let expandedQueries: [String]?
    /// 模糊查询的 AI 改写（如"就是那个红色的" → "红色物品")
    let fuzzyDescription: String?

    // MARK: Computed

    /// 用于 embedding 向量化的合并文本（原始 + 扩展词 + 模糊改写）
    var embeddingText: String {
        var parts: [String] = []
        if !searchText.isEmpty { parts.append(searchText) }
        if let expanded = expandedQueries {
            parts.append(contentsOf: expanded)
        }
        if let fuzzy = fuzzyDescription, !fuzzy.isEmpty {
            parts.append(fuzzy)
        }
        // 空间参照物也进语义通道："键盘"能把物品向量里含"键盘"周围环境的项拉近。
        if let anchor = spatialAnchor, !anchor.isEmpty {
            parts.append(anchor)
        }
        return parts.joined(separator: " ")
    }

    /// 所有可用于文本匹配的查询词集合
    var allQueryTerms: [String] {
        var terms: [String] = []
        for (_, value) in keywords where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            terms.append(value)
        }
        if let expanded = expandedQueries {
            terms.append(contentsOf: expanded)
        }
        return terms
    }
}

// MARK: - Time Filter

struct TimeFilter: Codable {
    /// 类型：目前仅支持 "relative"
    let type: String
    /// 值：today / yesterday / this_week / this_month / recent_3d / recent_7d / recent_30d / specific_day
    let value: String
    /// 精确偏移天数：value="specific_day" 时使用，如 2=前天, 3=大前天/三天前
    let daysAgo: Int?

    /// 将时间过滤转换为日期范围
    func dateRange(now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current

        // 精确偏移天数优先（"前天"/"N天前"）
        if let days = daysAgo, days > 0 {
            guard let target = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
            let start = calendar.startOfDay(for: target)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }

        switch value {
        case "today":
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case "yesterday":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.startOfDay(for: now)
            return (start, end)
        case "this_week":
            let weekday = calendar.component(.weekday, from: now)
            // 周日=1，周一=2，计算到本周一的天数
            let daysToMonday = weekday == 1 ? 6 : weekday - 2
            guard let monday = calendar.date(byAdding: .day, value: -daysToMonday, to: now) else { return nil }
            let start = calendar.startOfDay(for: monday)
            return (start, now)
        case "this_month":
            let components = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: components) else { return nil }
            return (start, now)
        case "recent_3d":
            guard let start = calendar.date(byAdding: .day, value: -3, to: now) else { return nil }
            return (start, now)
        case "recent_7d":
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return (start, now)
        case "recent_30d":
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            return (start, now)
        default:
            return nil
        }
    }
}
