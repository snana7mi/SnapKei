import SwiftUI
import LLMGatewayKit

public struct AISettingsSection: View {
    @Binding private var ai: AISettings
    private let onCommit: () -> Void
    private let onTestConnection: () async -> Void
    private let authService: AuthService
    private let onRequestSignIn: () -> Void
    @State private var testResult: String?
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyStatusMessage: String?
    private let keyStore: ByokKeyStore

    public init(
        ai: Binding<AISettings>,
        onCommit: @escaping () -> Void,
        onTestConnection: @escaping () async -> Void,
        authService: AuthService,
        onRequestSignIn: @escaping () -> Void,
        keyStore: ByokKeyStore = ByokKeyStore()
    ) {
        self._ai = ai
        self.onCommit = onCommit
        self.onTestConnection = onTestConnection
        self.authService = authService
        self.onRequestSignIn = onRequestSignIn
        self.keyStore = keyStore
    }

    public var body: some View {
        Section("AI 設定") {
            Picker("チャネル", selection: $ai.aiChannel) {
                Text("自前 API Key").tag(AIChannel.directApiKey)
                Text("内蔵 AI").tag(AIChannel.builtInProxy)
            }
            .onChange(of: ai.aiChannel) { _, _ in onCommit() }

            if ai.aiChannel == .directApiKey {
                Picker("フォーマット", selection: $ai.preferredFormat) {
                    Text("Anthropic").tag(APIFormat.anthropic)
                    Text("OpenAI").tag(APIFormat.openAI)
                }
                .onChange(of: ai.preferredFormat) { _, _ in
                    onCommit()
                    apiKeyInput = ""
                    keyStatusMessage = nil
                    refreshStoredKeyState()
                }

                if ai.preferredFormat == .anthropic {
                    TextField("Anthropic model", text: $ai.anthropicModel).onSubmit(onCommit)
                } else {
                    TextField("OpenAI model", text: $ai.openAIModel).onSubmit(onCommit)
                }

                SecureField(keyPlaceholder, text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(hasStoredKey ? "API Key を更新" : "API Key を保存") {
                    do {
                        try keyStore.saveKey(apiKeyInput, for: ai.preferredFormat)
                        apiKeyInput = ""
                        refreshStoredKeyState()
                        keyStatusMessage = "Keychain に保存しました"
                    } catch {
                        keyStatusMessage = "保存に失敗しました"
                    }
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasStoredKey {
                    HStack {
                        Label("API Key 保存済み", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("削除", role: .destructive) {
                            try? keyStore.deleteKey(for: ai.preferredFormat)
                            refreshStoredKeyState()
                            keyStatusMessage = "API Key を削除しました"
                        }
                        .font(.caption)
                    }
                }
                if let keyStatusMessage {
                    Text(keyStatusMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if !authService.isLoggedIn {
                    Button("ログインして有効化", action: onRequestSignIn)
                    Text("内蔵 AI を使用するにはサインインが必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("接続テスト") {
                Task {
                    await onTestConnection()
                    testResult = "確認しました"
                }
            }
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshStoredKeyState() }
        .onChange(of: ai.aiChannel) { _, _ in refreshStoredKeyState() }
    }

    private var keyPlaceholder: String {
        ai.preferredFormat == .anthropic ? "Anthropic API Key (sk-ant-...)" : "OpenAI API Key (sk-...)"
    }

    private func refreshStoredKeyState() {
        hasStoredKey = keyStore.hasKey(for: ai.preferredFormat)
    }
}
