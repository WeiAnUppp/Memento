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
}

// MARK: - Search Query (AI-parsed)

struct SearchQuery: Codable {
    /// 结构化关键词：{"颜色":"黑", "物品":"手机"}
    let keywords: [String: String]
    /// 用于向量搜索的核心文本
    let searchText: String
    /// AI 识别出的城市/区县级地名（如"上海""北京"），用于地理编码
    let locationName: String?

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
    /// 值：today / yesterday / this_week / this_month / recent_3d / recent_7d / recent_30d
    let value: String

    /// 将时间过滤转换为日期范围
    func dateRange(now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
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
