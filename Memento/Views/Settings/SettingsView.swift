//
//  SettingsView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Settings Navigation

enum SettingsPage: Hashable {
    case provider
    case url
    case key
    case model
}

// MARK: - SettingsView

struct SettingsView: View {
    @Binding var selectedPage: AppPage
    @Binding var navigationDepth: Int

    /// 直接读取共享实例，避免 @State + @Observable class 组合
    /// 在 NavigationStack push/pop 时变更传播不可靠的问题
    private var config: APIConfig { APIConfig.shared }
    @State private var path = NavigationPath()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        NavigationStack(path: $path) {
            List {
                appearanceSection
                apiSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                settingsTopBar
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .provider:
                    ProviderPickerView(config: config)
                case .url:
                    URLEditView(config: config)
                case .key:
                    KeyEditView(config: config)
                case .model:
                    ModelPickerView(config: config)
                }
            }
        }
        .onChange(of: path.count) { _, newCount in
            navigationDepth = newCount
        }
    }

    // MARK: - 顶栏

    private var settingsTopBar: some View {
        HStack(alignment: .center) {
            Spacer()

            Menu {
                Picker("视图", selection: $selectedPage) {
                    ForEach(AppPage.allCases, id: \.self) { page in
                        Label(page.rawValue, systemImage: page.icon)
                            .tag(page)
                    }
                }
            } label: {
                Image(systemName: "line.horizontal.3.decrease")
                    .font(.title2)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 0)
    }

    // MARK: - 外观 Section

    private var appearanceSection: some View {
        Section {
            HStack {
                Text("主题")
                Spacer()
                Picker("主题", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        } header: {
            Text("外观")
        }
    }

    // MARK: - API 配置 Section

    private var apiSection: some View {
        Section {
            NavigationLink(value: SettingsPage.provider) {
                LabeledContent("服务商") {
                    Text(config.selectedProvider.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink(value: SettingsPage.url) {
                LabeledContent("API 地址") {
                    Text(displayURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            NavigationLink(value: SettingsPage.key) {
                LabeledContent("API Key") {
                    Text(config.apiKey.isEmpty ? "未设置" : maskAPIKey(config.apiKey))
                        .foregroundStyle(config.apiKey.isEmpty ? .red : .secondary)
                        .font(config.apiKey.isEmpty ? .body : .callout)
                }
            }
            NavigationLink(value: SettingsPage.model) {
                LabeledContent("模型") {
                    Text(config.modelName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("API 配置")
        } footer: {
            Text("支持任何 OpenAI 兼容的 API 服务。")
        }
    }

    // MARK: - 关于 Section

    private var aboutSection: some View {
        Section {
            LabeledContent("版本") {
                Text("1.0.0").foregroundStyle(.secondary)
            }
            LabeledContent("系统要求") {
                Text("iOS 26").foregroundStyle(.secondary)
            }
            LabeledContent("App 名称") {
                Text("忆物 · Memento").foregroundStyle(.secondary)
            }
        } header: {
            Text("关于")
        }
    }

    // MARK: - Helpers

    private var displayURL: String {
        let url = config.apiBaseURL
        if url.isEmpty { return "未设置" }
        if url.count > 30 { return String(url.prefix(30)) + "..." }
        return url
    }

    private func maskAPIKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))••••••\(key.suffix(4))"
    }
}

// MARK: - Provider Picker

private struct ProviderPickerView: View {
    @Bindable var config: APIConfig
    @Environment(\.dismiss) private var dismiss
    @State private var previousProvider: APIProvider

    init(config: APIConfig) {
        self.config = config
        self._previousProvider = State(initialValue: config.selectedProvider)
    }

    var body: some View {
        List {
            Section {
                ForEach(APIProvider.allCases, id: \.self) { provider in
                    Button {
                        let wasDifferent = previousProvider != provider
                        config.applyProvider(provider)
                        // 切换到不同服务商时，提示用户更新 API Key
                        if wasDifferent && !config.apiKey.isEmpty {
                            dismiss()
                            // 短暂延迟后弹出提示
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                showKeyReminder = true
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.rawValue).foregroundStyle(.primary)
                                if !provider.defaultModel.isEmpty {
                                    Text(provider.defaultModel)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if config.selectedProvider == provider {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue).font(.body.weight(.semibold))
                            }
                        }
                    }
                }
            } footer: {
                Text("选择后将自动填入默认的 API 地址和推荐模型。\n⚠️ 切换服务商后请确认 API Key 是否正确。")
            }
        }
        .settingsNavBar(title: "服务商")
        .alert("确认 API Key", isPresented: $showKeyReminder) {
            Button("去设置") { dismiss() }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("已切换到「\(config.selectedProvider.rawValue)」。请确认 API Key 是否匹配该服务商，否则请求将失败。")
        }
    }

    @State private var showKeyReminder = false
}

// MARK: - API URL Edit

private struct URLEditView: View {
    @Bindable var config: APIConfig
    @Environment(\.dismiss) private var dismiss
    @State private var tempURL: String = ""

    var body: some View {
        List {
            Section {
                TextField("https://api.openai.com/v1", text: $tempURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } footer: {
                Text("输入 OpenAI 兼容的 Chat Completions 端点地址。")
            }
            Section {
                ForEach(APIProvider.allCases.filter { !$0.defaultURL.isEmpty }, id: \.self) { provider in
                    Button { tempURL = provider.defaultURL } label: {
                        HStack {
                            Text(provider.rawValue)
                            Spacer()
                            Text(provider.defaultURL)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            } header: { Text("快捷填入") }
        }
        .settingsNavBar(title: "API 地址")
        .onAppear { tempURL = config.apiBaseURL }
        .onChange(of: tempURL) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if config.apiBaseURL != trimmed {
                config.apiBaseURL = trimmed
            }
        }
        .onDisappear {
            let trimmed = tempURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if config.apiBaseURL != trimmed {
                config.apiBaseURL = trimmed
            }
        }
    }
}

// MARK: - API Key Edit

private struct KeyEditView: View {
    @Bindable var config: APIConfig
    @Environment(\.dismiss) private var dismiss
    @State private var tempKey: String = ""
    @State private var showKey = false

    var body: some View {
        List {
            Section {
                HStack {
                    if showKey {
                        TextField("sk-...", text: $tempKey)
                            .autocapitalization(.none).disableAutocorrection(true)
                    } else {
                        SecureField("sk-...", text: $tempKey)
                            .autocapitalization(.none).disableAutocorrection(true)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("API Key 仅存储在你的设备中，用于向 API 服务发送请求。")
            }
            Section {
                Button(role: .destructive) { tempKey = "" } label: {
                    HStack { Spacer(); Text("清除 Key"); Spacer() }
                }
                .disabled(tempKey.isEmpty)
            }
        }
        .settingsNavBar(title: "API Key")
        .onAppear { tempKey = config.apiKey }
        .onChange(of: tempKey) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if config.apiKey != trimmed {
                config.apiKey = trimmed
            }
        }
        .onDisappear {
            let trimmed = tempKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if config.apiKey != trimmed {
                config.apiKey = trimmed
            }
        }
    }
}

// MARK: - Model Picker

private struct ModelPickerView: View {
    @Bindable var config: APIConfig
    @Environment(\.dismiss) private var dismiss
    @State private var customModel: String = ""
    @State private var showCustomField = false

    var body: some View {
        List {
            Section {
                ForEach(ModelPreset.allCases, id: \.self) { preset in
                    Button {
                        if preset == .custom {
                            showCustomField = true
                            customModel = config.modelName
                        } else {
                            config.modelName = preset.rawValue
                            showCustomField = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(preset.displayName).foregroundStyle(.primary)
                            Spacer()
                            if !showCustomField && config.modelName == preset.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue).font(.body.weight(.semibold))
                            }
                        }
                    }
                }
            } footer: {
                Text("请确认所选模型支持视觉识别，否则物品识别可能无法正常工作。")
            }
            if showCustomField {
                Section {
                    TextField("输入模型名称", text: $customModel)
                        .autocapitalization(.none).disableAutocorrection(true)
                        .onSubmit {
                            config.modelName = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                            dismiss()
                        }
                } footer: { Text("按换行键确认") }
            }
        }
        .settingsNavBar(title: "模型")
        .onDisappear {
            if showCustomField && !customModel.isEmpty {
                config.modelName = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

// MARK: - iOS 26 导航栏风格

private struct SettingsNavBarStyle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }
}

private extension View {
    func settingsNavBar(title: String) -> some View {
        modifier(SettingsNavBarStyle(title: title))
    }
}

#Preview {
    NavigationStack {
        SettingsView(selectedPage: .constant(.settings), navigationDepth: .constant(0))
    }
}
