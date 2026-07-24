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
/// 策略：优先句向量；句向量不可用/返回空时，回退为「词向量平均」，
///       保证中文场景下语义通道不会整条静默失效。
struct EmbeddingService {

    /// 句向量模型（简体中文优先，回退英文）
    private static let sentence: NLEmbedding? = {
        NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
    }()

    /// 词向量模型（句向量不可用时的回退）
    private static let word: NLEmbedding? = {
        NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)
    }()

    /// 向量维度（运行时确定）
    var dimension: Int {
        Self.sentence?.dimension ?? Self.word?.dimension ?? 0
    }

    /// 模型是否可用
    var isAvailable: Bool {
        Self.sentence != nil || Self.word != nil
    }

    // MARK: - Vector Generation

    /// 将文本转为 [Float] 向量。句向量失败时回退词向量平均。
    func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) 句向量
        if let sentence = Self.sentence, let vec = sentence.vector(for: trimmed) {
            return vec.map { Float($0) }
        }

        // 2) 回退：分词后取词向量平均
        if let word = Self.word {
            var sum: [Double] = []
            var count = 0
            for token in Self.tokenize(trimmed) {
                guard let wv = word.vector(for: token) else { continue }
                if sum.isEmpty {
                    sum = wv
                } else {
                    let n = min(sum.count, wv.count)
                    for i in 0..<n { sum[i] += wv[i] }
                }
                count += 1
            }
            if count > 0 {
                return sum.map { Float($0 / Double(count)) }
            }
        }

        return nil
    }

    /// 词单元分词（用于词向量回退）
    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let t = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { tokens.append(t) }
            return true
        }
        return tokens
    }

    // MARK: - Embedding Text

    /// 组合多条信息生成用于 embedding 的文本。
    /// 关键词只取「值」，剥离 JSON 结构与中文键名（如 {"颜色":"黑"} → "黑"），
    /// 避免向量被 JSON 符号污染，与查询侧的自然语言对齐。
    func embeddingText(from name: String, description: String, keywords: String?,
                       scene: String?, nearbyObjects: String? = nil) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if !description.isEmpty { parts.append(description) }
        if let scene, !scene.isEmpty { parts.append(scene) }
        if let keywords, !keywords.isEmpty {
            let values = EmbeddingService.keywordValues(from: keywords)
            parts.append(values.isEmpty ? keywords : values.joined(separator: " "))
        }
        // 周围物品纳入向量文本：让"键盘旁边的鼠标"在语义通道也能被参照物带出。
        // 顿号在向量语义里无意义，替换为空格。
        if let nearby = nearbyObjects, !nearby.isEmpty {
            let cleaned = nearby.replacingOccurrences(of: "、", with: " ")
            parts.append(cleaned)
        }
        return parts.joined(separator: " ")
    }

    /// 从关键词字段解析出「值」列表。
    /// 支持 {"颜色":"黑","品类":"手机"} JSON；非 JSON 时原样返回。
    static func keywordValues(from jsonOrText: String) -> [String] {
        let trimmed = jsonOrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("{"),
           let dict = try? JSONDecoder().decode([String: String].self, from: Data(trimmed.utf8)) {
            return dict.values
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return [trimmed]
    }
}
