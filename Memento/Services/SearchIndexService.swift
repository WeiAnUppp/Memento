//
//  SearchIndexService.swift
//  Memento
//
//  一次性重建物品 embedding 索引。
//  旧版本在向量化时把关键词以原始 JSON（含 { } 与中文键名）拼进文本，
//  与查询侧的自然语言不对齐，导致语义召回失效。此服务用与查询一致的
//  「干净文本」重新生成全部向量，仅在版本升级时执行一次。
//

import Foundation

enum SearchIndexService {

    /// 当前索引版本。修改 embedding 文本构造逻辑时递增，触发重建。
    /// v3：embedding 文本纳入 nearbyObjects（周围物品），支撑空间关系查询。
    private static let currentVersion = 3
    private static let versionKey = "searchIndexVersion"

    /// 若本地索引版本落后则重建（后台线程，best-effort，失败不影响使用）
    static func reindexIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: versionKey)
        guard stored < currentVersion else { return }

        DispatchQueue.global(qos: .utility).async {
            let db = DatabaseService.shared
            let embedder = EmbeddingService()
            guard embedder.isAvailable else {
                // 模型不可用，标记完成避免每次启动重试
                UserDefaults.standard.set(currentVersion, forKey: versionKey)
                return
            }

            do {
                let items = try db.fetchAll()
                var updated = 0
                for item in items {
                    guard let id = item.id else { continue }
                    let text = embedder.embeddingText(
                        from: item.name,
                        description: item.itemDescription,
                        keywords: item.keywords,
                        scene: item.scene,
                        nearbyObjects: item.nearbyObjects
                    )
                    let vector = embedder.vector(for: text)
                    try? db.updateEmbedding(id: id, embedding: vector)
                    updated += 1
                }
                print("[SearchIndexService] 重建索引完成，共 \(updated) 项")
                UserDefaults.standard.set(currentVersion, forKey: versionKey)
            } catch {
                print("[SearchIndexService] 重建索引失败: \(error)")
            }
        }
    }
}
