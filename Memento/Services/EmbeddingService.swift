//
//  EmbeddingService.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation
import NaturalLanguage

// MARK: - Embedding Service

/// 使用 Apple NaturalLanguage 框架进行文本向量化
/// 端侧运行，无需网络，向量存入 SQLite BLOB
struct EmbeddingService {

    /// 加载中文 sentence embedding 模型
    /// 优先简体中文，回退英文，都不可用则为 nil
    private let embedding: NLEmbedding? = {
        if let chinese = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) {
            return chinese
        }
        if let english = NLEmbedding.sentenceEmbedding(for: .english) {
            return english
        }
        return nil
    }()

    /// 向量维度（运行时确定）
    var dimension: Int {
        embedding?.dimension ?? 0
    }

    /// 模型是否可用
    var isAvailable: Bool {
        embedding != nil
    }

    // MARK: - Vector Generation

    /// 将文本转为 [Float] 向量
    func vector(for text: String) -> [Float]? {
        guard let embedding, !text.isEmpty else { return nil }
        guard let doubleVector = embedding.vector(for: text) else { return nil }
        return doubleVector.map { Float($0) }
    }

    /// 组合多条信息生成用于 embedding 的文本
    func embeddingText(from name: String, description: String, keywords: String?, scene: String?) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if !description.isEmpty { parts.append(description) }
        if let scene, !scene.isEmpty { parts.append(scene) }
        if let keywords, !keywords.isEmpty { parts.append(keywords) }
        return parts.joined(separator: " ")
    }
}
