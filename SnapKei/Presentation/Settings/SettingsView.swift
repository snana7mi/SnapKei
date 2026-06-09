import SwiftUI
import LLMGatewayKit

public struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.llmGatewayKitConfig) private var config
    @Environment(\.snapKeiSyncEngine) private var syncEngine

    @State private var viewModel = SettingsViewModel()
    @State private var statusMessage = ""
    @State private var showProfile = false
    @State private var showPaywall = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                AccountHeaderSection(authService: authService) {
                    showProfile = true
                }

                if let syncEngine {
                    CloudSyncSection(authService: authService, syncEngine: syncEngine) {
                        showPaywall = true
                    }
                }

                BusinessInfoSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveAll() }
                )

                AISettingsSection(
                    ai: Binding(get: { viewModel.aiSettings }, set: { viewModel.aiSettings = $0 }),
                    onCommit: { viewModel.saveAll() },
                    onTestConnection: { await testConnection() },
                    authService: authService,
                    onRequestSignIn: { showProfile = true }
                )

                FixedAssetSection()
                HouseholdAllocationSection()
                ComplianceSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveAll() }
                )

                SaveButtonSection(
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    onSave: viewModel.saveAll,
                    onDiscard: viewModel.discard
                )

                if !statusMessage.isEmpty {
                    Section { Text(statusMessage).font(.caption) }
                }

                Section("アプリ情報") {
                    Text("SnapKei v0.1.0")
                    Text("青色申告対応 仕訳作成アプリ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink(LegalTexts.disclaimerTitle) { DisclaimerView() }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showProfile) {
                if let config {
                    ProfileView(
                        config: config,
                        authService: authService,
                        subscriptionService: subscriptionService,
                        onRequestUpgrade: { showPaywall = true }
                    )
                }
            }
            .sheet(isPresented: $showPaywall) {
                if let config {
                    PaywallView(
                        config: config,
                        viewModel: PaywallViewModel(subscriptionService: subscriptionService)
                    )
                }
            }
        }
    }

    private func testConnection() async {
        viewModel.saveAll()
        if viewModel.aiSettings.aiChannel == .builtInProxy {
            statusMessage = viewModel.aiSettings.proxyBaseURL.isEmpty ? "Gateway URL を設定してください" : "Gateway URL 設定済み"
        } else {
            statusMessage = "BYOK は Capture 画面で実呼び出し確認します"
        }
    }
}
