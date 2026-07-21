import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showingSaved = false

    var body: some View {
        NavigationStack {
            Form {
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
