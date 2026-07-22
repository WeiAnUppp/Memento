//
//  AIService.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

// MARK: - AI Service

/// 通用的 OpenAI 兼容 API 服务
/// 支持图片理解（图片→物品描述）和查询解析（自然语言→结构化关键词）
struct AIService {
    private let config: APIConfig

    init(config: APIConfig = APIConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// 分析图片中的物品，返回结构化描述
    func analyzeImage(base64Image: String, mimeType: String = "image/jpeg") async throws -> AIResponse {
        let systemPrompt = """
        你是一个物品识别助手。分析图片中的主要物品，返回 JSON 格式的结果。
        请仔细观察物品的名称、外观特征（颜色、形状、材质）和所在场景。
        """

        let userContent: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(base64Image)"]],
            ["type": "text", "text": "请识别这张图片中的主要物品，返回物品名称、外观特征描述（颜色/形状/材质/大小）、所在场景描述，以及 3-5 个关键词（颜色、品类、位置等）用于后续搜索。"]
        ]

        return try await chatCompletion(
            systemPrompt: systemPrompt,
            userContent: userContent
        )
    }

    /// 将自然语言查询解析为结构化关键词
    func parseQuery(_ query: String) async throws -> SearchQuery {
        let systemPrompt = """
        你是一个搜索查询解析助手。将用户的模糊查询转化为结构化关键词，方便检索。
        提取颜色、物品类别、位置、品牌、材质等维度的关键词。
        """

        let userContent: [[String: Any]] = [
            ["type": "text", "text": "用户搜索: \"\(query)\"\n\n请解析这个搜索查询，提取结构化关键词（颜色、物品、位置、品牌等维度），以及一个适合向量检索的搜索文本。"]
        ]

        let response: SearchQuery = try await chatCompletion(
            systemPrompt: systemPrompt,
            userContent: userContent
        )
        return response
    }

    // MARK: - Core API Call

    /// 通用 OpenAI 兼容 Chat Completions 调用
    private func chatCompletion<T: Decodable>(
        systemPrompt: String,
        userContent: [[String: Any]]
    ) async throws -> T {
        guard config.isConfigured else {
            throw AIServiceError.notConfigured
        }

        let endpoint = config.apiBaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3,
            "max_tokens": 1024
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorBody(data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    /// 解析 OpenAI Chat Completions 响应
    private func parseResponse<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()

        // 先解析外层 OpenAI 响应格式
        let outer = try decoder.decode(OpenAIResponse.self, from: data)

        guard let content = outer.choices.first?.message.content else {
            throw AIServiceError.emptyResponse
        }

        // 解析内层 JSON（AI 返回的结构化数据）
        guard let contentData = content.data(using: .utf8) else {
            throw AIServiceError.invalidJSON
        }

        return try decoder.decode(T.self, from: contentData)
    }

    /// 解析错误响应体
    private func parseErrorBody(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}

// MARK: - OpenAI 响应模型

private struct OpenAIResponse: Decodable {
    let id: String
    let choices: [Choice]
    let model: String

    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }
}

// MARK: - 错误类型

enum AIServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case emptyResponse
    case invalidJSON
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API 未配置，请在设置中填写 API 地址和 Key"
        case .invalidURL:
            return "API 地址格式无效"
        case .invalidResponse:
            return "服务器响应异常"
        case .emptyResponse:
            return "API 返回为空"
        case .invalidJSON:
            return "API 返回格式异常"
        case .apiError(let code, let message):
            return "API 错误 (\(code)): \(message)"
        }
    }
}
