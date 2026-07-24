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

    /// 分析多张图片中的物品，结合用户描述返回结构化结果
    func analyzeImages(
        base64Images: [String],
        mimeType: String = "image/jpeg",
        userContext: String
    ) async throws -> AIResponse {
        let systemPrompt = """
        你是一个物品识别助手。用户会说一句话描述这个物品（可能包含物品名称、存放位置等）。
        请结合用户提供的信息和多张图片内容，给出更准确的分析结果。
        如果用户描述与图片内容不符，以图片为准，但在描述中礼貌地指出差异。

        返回如下 JSON 格式（必须使用英文 key）：
        {
          "name": "物品名称",
          "description": "外观特征描述（颜色、形状、材质、大小）",
          "scene": "所在场景（房间类型、周围环境、空间关系）",
          "keywords": {"颜色": "值", "品类": "值", "位置": "值"},
          "emoji": "最贴切的单个 emoji（如 📱、🔑、👟、💊、📦、💻、👕、🎧、💍、👜、📷、📚、🧸、⌚、🕶️、💄 等）"
        }
        注意：keywords 的 key 用中文，value 用中文。name、description、scene、emoji 的 value 用中文/emoji。
        emoji 必须是一个最能代表该物品的 emoji 字符。
        scene 字段请结合用户提到的位置信息。
        """

        var userContent: [[String: Any]] = []

        // 添加所有图片
        for base64 in base64Images {
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
            ])
        }

        // 用户一句话描述
        let contextText = "用户描述：\(userContext)\n\n请结合用户描述和这些图片（同一物品的不同角度），识别图片中的主要物品，返回物品名称、外观特征描述（颜色/形状/材质/大小）、所在场景描述，以及 3-5 个关键词（颜色、品类、位置等）用于后续搜索。"

        userContent.append(["type": "text", "text": contextText])

        return try await chatCompletion(
            systemPrompt: systemPrompt,
            userContent: userContent
        )
    }

    /// 将自然语言查询解析为结构化关键词
    /// 覆盖 12 类人类查询模式：直接命名、属性描述、位置、时间、空间关系、功能用途、模糊情感、比较、排除、多条件、浏览、追问
    func parseQuery(_ query: String) async throws -> SearchQuery {
        let systemPrompt = """
你是一个智能物品搜索助手。理解用户的自然语言查询，提取结构化信息用于本地物品检索。

## 你的核心任务
深度理解查询意图，生成可用于本地文本匹配和向量搜索的结构化数据。

## 12 类查询模式处理规则

### 1. 直接命名 — "手机"、"钥匙在哪"、"找充电器"
→ keywords: {"物品":"手机"}
→ searchText: "手机"
→ expandedQueries: AI推测的同义词/类别词（如["电话","智能手机"]）

### 2. 属性描述 — "黑色的钥匙"、"很大的盒子"、"红色的圆形的东西"
→ keywords: {"颜色":"黑","大小":"大","形状":"圆形"}
→ searchText: 连接核心描述词
→ expandedQueries: 推测可能的物品名

### 3a. 室内位置+物品 — "卧室的充电器"、"客厅桌上的钥匙"
→ 室内场景 → keywords: {"位置":"卧室","物品":"充电器"}
→ searchText: 物品+场景组合
→ locationName: null

### 3b. 城市+物品 — "上海家里的钥匙"、"北京办公室的电脑"
→ 城市/区县 → locationName: "上海"
→ 物品 → keywords: {"物品":"钥匙"}
→ searchText: 物品+场景组合

### 3c. 纯城市查询 ⚠️ 重要 — "在上海记录的"、"北京家里的"、"杭州买的那个"
→ 用户只提到城市名，没有具体物品名
→ keywords: {}（空对象！不要虚构物品）
→ searchText: ""（空字符串！不要填"物品""记录"等占位词）
→ locationName: "上海"
→ queryIntent: "find_item"
→ 核心：纯城市查询完全依赖GPS距离，不要给文本匹配任何权重

### 4. 时间查询 — "昨天放的"、"上周记录的"、"今天拍的"、"最近三天"、"三天前"
→ timeFilter: {"type":"relative","value":"yesterday"}
→ 可选值: today / yesterday / this_week / this_month / recent_3d / recent_7d / recent_30d
→ 时间词不放入keywords，不放入searchText

### 5. 空间关系 — "键盘旁边的"、"抽屉里面的"、"跟耳机一起放的"、"桌子上面那个"
→ keywords: {"位置":"键盘"}（提取参照物）
→ searchText: 空间关系+参照物+"物品"
→ expandedQueries: 推测可能与参照物在一起的物品类型

### 6. 功能用途 — "用来充电的"、"装药的"、"剪东西用的"、"喝水的"
→ keywords: {"用途":"充电"}
→ searchText: 功能描述
→ expandedQueries: 推测功能对应的物品（如["充电器","数据线","充电宝","电源"]）

### 7. 模糊/情感 — "就是那个...红色的"、"我妈给我的"、"你知道的，圆圆的"
→ keywords: 尽可能提取（{"颜色":"红"} 或 {}）
→ fuzzyDescription: AI改写为更精确的描述
→ searchText: 保留原始表达
→ 实在无法提取时 keywords={}，searchText=原句

### 8. 比较型 — "最大的那个"、"最新的"、"比我手机小的"、"第二新的"
→ sortHint: "largest" / "smallest" / "newest" / "oldest"
→ searchText: 核心物品描述
→ 参照物（"比我手机小"）→ 如能判断品类则放入keywords

### 9. 排除型 — "不是黑色的手机"、"除了卧室以外的"、"但不是钥匙"
→ keywords: {"物品":"手机"}
→ negativeKeywords: ["黑色"] 或 ["卧室"] 或 ["钥匙"]
→ searchText: 正常搜索文本

### 10. 多条件 — "黑色的、在客厅的、比手机大的"
→ keywords: 合并所有条件{"颜色":"黑","位置":"客厅"}
→ 比较条件 → sortHint: "largest"
→ searchText: 连接所有描述词

### 11. 浏览型 — "最近记录了哪些"、"看看今天拍的"、"有哪些东西"、"都记录了什么"
→ queryIntent: "browse_recent"
→ timeFilter: 对应时间过滤（如有）
→ keywords: {}
→ searchText: ""

### 12. 追问型 — "还有别的吗"、"不是这个"、"再找找"、"换一批"
→ queryIntent: "follow_up"
→ 尽可能提取修正信息
→ 无修正信息时 keywords={}，searchText=""

## expandedQueries 重要规则
expandedQueries 是你根据常识推测的同义词和相关词，用于扩展搜索范围：
- "手机" → ["电话","智能手机","iPhone","华为手机"]
- "充电的" → ["充电器","数据线","充电宝","电源适配器","插头"]
- "喝水的" → ["杯子","水杯","保温杯","马克杯","茶杯"]
- "穿的" → ["衣服","外套","鞋子","上衣","裤子"]
- "装东西的" → ["盒子","箱子","包","袋子","收纳盒"]
- 空间关系型 → 推测参照物旁边常见的物品

## 输出 JSON 格式（只返回 JSON）
{
  "keywords": {"颜色":"红","物品":"手机"},
  "searchText": "红色手机",
  "locationName": null,
  "timeFilter": null,
  "negativeKeywords": null,
  "sortHint": null,
  "queryIntent": "find_item",
  "expandedQueries": null,
  "fuzzyDescription": null
}

## 规则总结
- 城市/省份/区县 → locationName（不放入keywords）
- 室内场景（卧室/厨房/桌上）→ keywords["位置"]
- 纯城市查询无物品名（"在上海记录的"）→ keywords={}, searchText="" ⚠️
- 时间词 → timeFilter，不放入keywords或searchText
- "不"/"除了"/"但不是" → negativeKeywords
- "最"/"更"/"比" → sortHint
- 模糊到无法提取 → keywords={}, searchText=原句, fuzzyDescription=改写
- 只返回JSON，不要其他文字
"""

        let userContent: [[String: Any]] = [
            ["type": "text", "text": "用户搜索: \"\(query)\"\n\n请解析。只返回 JSON。"]
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
            "temperature": 0.2,
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

        let outer = try decoder.decode(OpenAIResponse.self, from: data)

        guard let content = outer.choices.first?.message.content else {
            throw AIServiceError.emptyResponse
        }

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
