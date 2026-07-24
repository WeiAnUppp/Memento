//
//  SearchResult.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

// MARK: - Search Result

struct SearchResult: Identifiable {
    let item: Item
    let score: Double
    var id: Int64 { item.id ?? 0 }

    /// 是否高置信结果。false = 弱相关，UI 折叠进"可能相关"区。
    /// 由排序引擎按"与最高分的差距 + 绝对下限"判定。
    var isStrong: Bool = true

    /// 是否浏览模式结果（"有哪些东西""最近记录的"）。
    /// 浏览是"列举"而非"匹配"，UI 不应展示匹配度百分比（否则全部 100% 误导）。
    var isBrowse: Bool = false

    /// 匹配详情，解释为什么这个物品被匹配到
    var matchDetails: MatchDetails?

    // MARK: - Match Details

    struct MatchDetails {
        /// 命中的字段：如 ["name", "description"]
        let matchedFields: [String]
        /// 命中的关键词：如 ["黑色", "手机"]
        let matchedKeywords: [String]
        /// 名称是否命中
        let nameMatched: Bool
        /// 与目标位置的距离（公里），仅位置搜索时有值
        let locationDistance: Double?
        /// 时间相关性标签：如 "今天"、"本周"、nil
        let timeRelevance: String?
    }
}
