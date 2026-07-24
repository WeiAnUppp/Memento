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
        let hasMultipleImages = base64Images.count > 1

        let systemPrompt = """
        你是一个专业的物品记录助手。用户正在用「忆物」App 记录自己的个人物品，以便日后通过自然语言搜索快速找到它们。
        你的任务：用户会上传 1 张或多张图片。你的职责是仔细查看【每一张】图片，综合所有图中的信息，对物品做【极其详尽、全面】的记录分析。
        请假设这些记录是未来搜索的唯一依据——描述越详细，未来找到的概率越高。
        如果用户描述与图片内容不符，以图片为准。

        \(hasMultipleImages ? """
        ═══════════════════════════════════════
        ⭐ 多图分析策略（极其重要）：
        ═══════════════════════════════════════
        用户上传了多张图片。通常第一张是物品近照，后续是环境全景。你需要：
        1. 从【所有图片中】找出要记录的主要物品（通常在第一张中最突出）
        2. 仔细观察【每一张图片】，不要跳过任何一张
        3. 物品的外观细节可能分散在不同图片中（比如第一张看到正面logo，第二张看到侧面纹理），全部整合进 description
        4. 环境信息可能分布在多张图中，把所有图中看到的空间信息综合进 scene
        5. 遍历每一张图，把你看到的所有其它物品/家具/收纳容器，全部写进 nearby_objects
        ═══════════════════════════════════════
        """ : "")
        ═══════════════════════════════════════

        ═══════════════════════════════════════
        返回 JSON 格式（必须使用英文 key），每个字段都要尽可能详尽：
        ═══════════════════════════════════════

        {
          "name": "物品简短名称（2-6字，如"黑色折叠伞"）",

          "description": "【重点】物品的完整外观描述，至少500字。请像亲眼看到一样写下来，越详细越好。包含以下所有你能观察到的维度：
            · 颜色/配色：主色、辅色、图案、渐变色、花纹
            · 形状/结构：整体轮廓（方的/圆的/长条/异形）、边角特征、折叠/展开状态
            · 材质/质感：塑料/金属/木质/布料/皮革/玻璃/陶瓷等，光泽度（哑光/亮面/磨砂）
            · 尺寸估计：小巧（掌心大小）/中等（书本大小）/较大（背包大小）/大型
            · 品牌/标识：任何可见的 logo、文字、标签、型号，原文照录
            · 细节特征：按钮、接口、拉链、缝线、纹理、磨损痕迹、污渍、贴纸
            · 状态/新旧：全新/轻微使用痕迹/明显磨损/有破损
            · 数量：画面中有几个该物品
            请用连贯的段落（而非分点）写出，保留所有你能看到的细节。\(hasMultipleImages ? "如有物品出现在多张图中，综合所有角度的信息。" : "")",

          "scene": "【重点】物品所在场景的完整描述，至少\(hasMultipleImages ? "500" : "200")字。包含：
            · 房间/场所类型（客厅/卧室/厨房/办公室/车内/户外等）
            · 物品放置的表面（桌上/地上/架上/床上/抽屉里/柜子里/手上）
            · 周围家具和环境（描述可见的家具、墙面颜色、地板材质、窗帘等）
            · 光线条件（自然光/室内灯光/昏暗/明亮）
            · 空间氛围（整洁/凌乱/温馨/简约/商务等）\(hasMultipleImages ? "\n            · 综合所有图片中出现的空间信息，场景描述要覆盖所有图中看到的环境" : "")
            请用连贯的段落写出完整的空间信息。",

          "keywords": {
            "颜色": "具体颜色（如：深蓝色、米白色、银灰色）",
            "品类": "物品大类（如：数码配件、衣物、文具、工具）",
            "材质": "主体材质（如：铝合金、帆布、ABS塑料）",
            "位置": "场景关键词（如：卧室、书桌上、抽屉里）",
            "品牌": "品牌名（如有的话，如：小米、无印良品）",
            "形状": "形状描述（如：长方形、圆形、不规则）",
            "用途": "功能用途（如：充电、收纳、装饰、办公）",
            "特征": "最显著的1-2个特征（如：折叠式、防水、带密码锁）"
          },
          注意：keywords 的 key 和 value 都用中文。每个 key 的 value 尽量具体，不要用笼统词。
          如果某个维度无法判断（如品牌看不见），可以不填该项。

          "nearby_objects": ["主物品周围/相邻真实可见的所有其它物品或环境参照物"],
          ⭐ nearby_objects 极其重要（决定"键盘旁边的""抽屉里的"这类空间关系查询能否找到）：
          - 遍历【每一张图片】中可见的所有其它物品，一个一个列出来，用通用中文名词。
          - 至少要列出 5 个以上（如果画面中确实有那么多），越多越好。
          \(hasMultipleImages ? "- 环境全景图中通常能看到更多物品和家具，一定要把这些全部列出来\n" : "")
          - 例：拍鼠标 → ["键盘","27寸显示器","黑色鼠标垫","木质桌面","台灯","水杯","手机支架","笔筒"]
          - 例：拍钥匙 → ["玄关柜","白色鞋架","门垫","拖鞋","雨伞","墙壁挂钩"]
          - 只写画面里【确实看得到】的，不要臆想编造。看不到任何参照物时返回 []。
          - 用通用名词（"键盘"而非"罗技G913键盘"），方便日后自然语言匹配。
          - 不要把主物品自己重复写进 nearby_objects。

          "emoji": "最贴切的单个 emoji 字符（如 📱、🔑、👟、💊、📦、💻、👕、🎧、💍、👜、📷、📚、🧸、⌚、🕶️、💄、☂️、🔦、💳 等）"
        }

        ═══════════════════════════════════════
        核心原则：
        1. 宁可冗余，不可遗漏——你今天多写一个细节，未来就多一分找到的可能
        2. description 和 scene 必须用流畅的自然段落，而非简单的分点罗列
        3. 所有中文描述保持口语化和自然，就像你正在跟朋友描述你看到的东西
        4. 只返回 JSON，不要任何额外解释文字\(hasMultipleImages ? "\n        5. ⚠️ 认真查看每一张图片，不要只盯着第一张！每张图都要分析" : "")
        ═══════════════════════════════════════
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
        let contextText: String
        if hasMultipleImages {
            contextText = """
            用户描述：\(userContext)

            你面前有 \(base64Images.count) 张图片，它们从不同距离和角度记录了同一个物品。
            请逐一仔细观察每一张图：

            📷 近景图（通常是第 1 张）：识别物品的细节——颜色、材质、形状、品牌logo、特征
            🏠 全景图（通常是后面的图）：观察物品放在哪里、周围有什么家具和物品、房间是什么样的

            把你从【每一张图】中看到的所有信息，融合成一份完整记录。
            不要只盯着第一张！后面的全景图里可能有更多场景信息和周围物品，一定要全部写进 scene 和 nearby_objects。
            """
        } else {
            contextText = "用户描述：\(userContext)\n\n请对这张图片中的物品做极其详尽的记录分析。记住：你看到的所有细节——颜色、材质、形状、品牌logo、周围物品、场景光线、摆放位置——全部写进 description、scene、keywords 和 nearby_objects。不漏掉任何东西。"
        }

        userContent.append(["type": "text", "text": contextText])

        return try await chatCompletion(
            systemPrompt: systemPrompt,
            userContent: userContent,
            maxTokens: 8192
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

### 3a′. 场景域查询 ⚠️ 重要 — "家里的东西"、"公司的物品"、"办公室有什么"、"宿舍里的"、"学校的东西"
→ 场景域词（家/家里/公司/办公室/单位/学校/宿舍/教室/店里/车里）表示【一类场所】，是【场景过滤条件】，不是浏览！
→ keywords: {"位置":"家"}（把场景域词放进 keywords["位置"]，即使后面跟着"东西/物品"这类泛词也要提取）
→ searchText: ""（只有场景域、没有具体物品时留空，靠场景过滤）
→ queryIntent: "find_item"（绝不是 browse_recent！用户要的是"某场所里的物品"，不是"列出所有最近记录"）
→ 例："家里的东西" → keywords={"位置":"家"}, searchText="", queryIntent="find_item"
→ 例："公司的充电器" → keywords={"位置":"公司","物品":"充电器"}, searchText="充电器"

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

### 4. 时间查询 — "昨天放的"、"上周记录的"、"今天拍的"、"最近三天"
→ 时间映射规则（精确优先）：
  - "今天" → value:"today"
  - "昨天" → value:"yesterday"
  - "前天" → value:"specific_day", daysAgo:2
  - "大前天" → value:"specific_day", daysAgo:3
  - "3天前"/"三天前" → value:"specific_day", daysAgo:3
  - "4天前"/"四天前" → value:"specific_day", daysAgo:4（以此类推，N天前用 daysAgo:N）
  - "上周/这周" → value:"this_week"
  - "最近三天/近三天" → value:"recent_3d"（区间，非单日）
  - "最近一周/近一周" → value:"recent_7d"
  - "这个月" → value:"this_month"
  - "最近一个月" → value:"recent_30d"
→ 输出格式示例：
  - "前天的东西" → timeFilter: {"type":"relative","value":"specific_day","daysAgo":2}
  - "昨天放的" → timeFilter: {"type":"relative","value":"yesterday"}
  - "三天前的" → timeFilter: {"type":"relative","value":"specific_day","daysAgo":3}
→ 时间词不放入keywords，不放入searchText

### 5. 空间关系 ⚠️ 重要 — "键盘旁边的"、"抽屉里面的"、"跟耳机一起放的"、"桌子上面那个"
→ spatialAnchor: "键盘"（提取【参照物】本身，室内物品，绝不是城市地名）
→ keywords: {}（不要把参照物塞进 keywords["位置"]，那会让它被当地名地理编码）
→ searchText: 只填【推测的目标物品类型】，绝不含"旁边""里面""附近""上面"这类关系词，也不含"东西""物品"这类泛词
→ expandedQueries: 推测可能与参照物在一起的物品类型（如键盘旁 → ["鼠标","U盘","手机","数据线"]）
→ 例："键盘旁边的东西" → spatialAnchor="键盘", keywords={}, searchText="鼠标 数据线", expandedQueries=["鼠标","U盘","手机","充电线"]

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
→ ⚠️ 严格限定：只有【纯列举、没有任何场景域/地点/物品限定】才算浏览。
  "家里的东西""公司的物品""上海的东西"都【不是】浏览 —— 它们带场景/地点限定，走 3a′/3b/3c。
  判断法：去掉"有哪些/看看/都记录了什么"后若还剩场景词或物品词，就不是浏览。

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
  "spatialAnchor": null,
  "timeFilter": null,
  "negativeKeywords": null,
  "sortHint": null,
  "queryIntent": "find_item",
  "expandedQueries": null,
  "fuzzyDescription": null
}

timeFilter 格式示例：
- 不涉及时间 → null
- 今天 → {"type":"relative","value":"today"}
- 昨天 → {"type":"relative","value":"yesterday"}
- 前天 → {"type":"relative","value":"specific_day","daysAgo":2}
- 三天前 → {"type":"relative","value":"specific_day","daysAgo":3}

## 规则总结
- 城市/省份/区县 → locationName（不放入keywords）
- 空间参照物（键盘/抽屉/桌子/床头，室内）→ spatialAnchor（不放入 keywords，不做地理编码）⚠️
- 室内场景（卧室/厨房/客厅这类【房间】）→ keywords["位置"]
- 场景域词（家/家里/公司/办公室/单位/学校/宿舍/店里/车里）→ keywords["位置"]，queryIntent=find_item，【绝不是 browse】⚠️
- "家里的东西/公司的物品"这类【场景域+泛词】→ 提取场景域到 keywords["位置"]，不要因为"东西/物品"就判成浏览 ⚠️
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
        userContent: [[String: Any]],
        maxTokens: Int = 1024
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
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "max_tokens": maxTokens
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
