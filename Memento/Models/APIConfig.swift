//
//  APIConfig.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/22.
//

import SwiftUI

/// API 提供商预设，方便用户快速选择
enum APIProvider: String, CaseIterable {
    case custom = "自定义"
    case openAI = "OpenAI"
    case azure = "Azure OpenAI"
    case mimo = "MiMo AI"
    case deepseek = "DeepSeek"
    case moonshot = "Moonshot"
    case zhipu = "智谱 GLM"
    case qwen = "通义千问"

    var defaultURL: String {
        switch self {
        case .custom:    return ""
        case .openAI:    return "https://api.openai.com/v1"
        case .azure:     return "https://YOUR_RESOURCE.openai.azure.com"
        case .mimo:      return "https://api.xiaomimimo.com/v1"
        case .deepseek:  return "https://api.deepseek.com/v1"
        case .moonshot:  return "https://api.moonshot.cn/v1"
        case .zhipu:     return "https://open.bigmodel.cn/api/paas/v4"
        case .qwen:      return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .custom:    return ""
        case .openAI:    return "gpt-4o"
        case .azure:     return "gpt-4o"
        case .mimo:      return "mimo-v2.5"
        case .deepseek:  return "deepseek-chat"
        case .moonshot:  return "moonshot-v1-8k"
        case .zhipu:     return "glm-4-flash"
        case .qwen:      return "qwen-vl-plus"
        }
    }
}

/// 常用模型预设
enum ModelPreset: String, CaseIterable {
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4Turbo = "gpt-4-turbo"
    case gpt35Turbo = "gpt-3.5-turbo"
    case deepseekChat = "deepseek-chat"
    case deepseekReasoner = "deepseek-reasoner"
    case moonshotV1 = "moonshot-v1-8k"
    case glm4Flash = "glm-4-flash"
    case glm4V = "glm-4v"
    case qwenVLPlus = "qwen-vl-plus"
    case qwenVLMax = "qwen-vl-max"
    case mimoV25 = "mimo-v2.5"
    case custom = "自定义..."

    var displayName: String {
        switch self {
        case .gpt4o:           return "GPT-4o"
        case .gpt4oMini:       return "GPT-4o Mini"
        case .gpt4Turbo:       return "GPT-4 Turbo"
        case .gpt35Turbo:      return "GPT-3.5 Turbo"
        case .deepseekChat:    return "DeepSeek-Chat"
        case .deepseekReasoner: return "DeepSeek-Reasoner"
        case .moonshotV1:      return "Moonshot v1"
        case .glm4Flash:       return "GLM-4 Flash"
        case .glm4V:           return "GLM-4V"
        case .qwenVLPlus:      return "Qwen-VL Plus"
        case .qwenVLMax:       return "Qwen-VL Max"
        case .mimoV25:         return "MiMo v2.5"
        case .custom:          return "自定义..."
        }
    }
}

/// 全局 API 配置，通过 UserDefaults 持久化
/// （后续 API Key 应迁移到 Keychain）
@Observable
class APIConfig {
    var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: keyAPIBaseURL) }
    }
    var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: keyAPIKey) }
    }
    var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: keyModelName) }
    }
    var selectedProvider: APIProvider {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: keyProvider) }
    }

    init() {
        self.apiBaseURL = UserDefaults.standard.string(forKey: keyAPIBaseURL) ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: keyAPIKey) ?? ""
        self.modelName = UserDefaults.standard.string(forKey: keyModelName) ?? "gpt-4o"
        let raw = UserDefaults.standard.string(forKey: keyProvider) ?? ""
        self.selectedProvider = APIProvider(rawValue: raw) ?? .custom
    }

    /// 是否已配置完成（URL + Key 均非空）
    var isConfigured: Bool {
        !apiBaseURL.isEmpty && !apiKey.isEmpty && !modelName.isEmpty
    }

    /// 选中预设提供商时自动填入默认 URL 和模型
    func applyProvider(_ provider: APIProvider) {
        selectedProvider = provider
        if !provider.defaultURL.isEmpty {
            apiBaseURL = provider.defaultURL
        }
        if !provider.defaultModel.isEmpty {
            modelName = provider.defaultModel
        }
    }
}

// MARK: - UserDefaults Keys

private let keyAPIBaseURL = "apiBaseURL"
private let keyAPIKey = "apiKey"
private let keyModelName = "modelName"
private let keyProvider = "apiProvider"
