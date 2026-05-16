import SwiftUI

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var statusMessage = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                BusinessInfoSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveApp() }
                )

                AISettingsSection(
                    ai: Binding(get: { viewModel.aiSettings }, set: { viewModel.aiSettings = $0 }),
                    onCommit: { viewModel.saveAI() },
                    onSignInWithApple: { await performSIWAHint() },
                    onTestConnection: { await testConnection() }
                )

                FixedAssetSection()
                HouseholdAllocationSection()
                ComplianceSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveApp() }
                )

                if !statusMessage.isEmpty {
                    Section { Text(statusMessage).font(.caption) }
                }

                Section("アプリ情報") {
                    Text("SnapKei v0.1.0")
                    Text("青色申告対応 仕訳作成アプリ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }

    private func performSIWAHint() async {
        viewModel.saveAI()
        statusMessage = "内蔵AIは初回解析時にAppleサインインします。"
    }

    private func testConnection() async {
        viewModel.saveAI()
        if viewModel.aiSettings.aiChannel == .builtInProxy {
            statusMessage = viewModel.aiSettings.proxyBaseURL.isEmpty ? "Gateway URL を設定してください" : "Gateway URL 設定済み"
        } else {
            statusMessage = "BYOK は Capture 画面で実呼び出し確認します"
        }
    }
}
