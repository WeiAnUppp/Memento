//
//  SettingsView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

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

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var apiKey: String = ""
    @State private var showingSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("MiMo API") {
                    SecureField("API Key", text: $apiKey)
                        .onSubmit { saveAPIKey() }

                    Button("保存") { saveAPIKey() }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("系统", value: "iOS 26")
                }
            }
            .navigationTitle("设置")
            .alert("已保存", isPresented: $showingSaved) {
                Button("好") { }
            }
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        // TODO: Keychain 存储
        showingSaved = true
    }
}
