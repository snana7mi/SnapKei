import SwiftUI

public struct AISettingsSection: View {
    @Binding private var ai: AISettings
    private let onCommit: () -> Void
    private let onSignInWithApple: () async -> Void
    private let onTestConnection: () async -> Void
    @State private var testResult: String?

    public init(
        ai: Binding<AISettings>,
        onCommit: @escaping () -> Void,
        onSignInWithApple: @escaping () async -> Void,
        onTestConnection: @escaping () async -> Void
    ) {
        self._ai = ai
        self.onCommit = onCommit
        self.onSignInWithApple = onSignInWithApple
        self.onTestConnection = onTestConnection
    }

    public var body: some View {
        Section("AI 設定") {
            Picker("チャネル", selection: $ai.aiChannel) {
                Text("自前 API Key").tag(AIChannel.directApiKey)
                Text("内蔵 AI").tag(AIChannel.builtInProxy)
            }
            .onChange(of: ai.aiChannel) { _, _ in onCommit() }

            Picker("フォーマット", selection: $ai.preferredFormat) {
                Text("Anthropic").tag(APIFormat.anthropic)
                Text("OpenAI").tag(APIFormat.openAI)
            }
            .onChange(of: ai.preferredFormat) { _, _ in onCommit() }

            if ai.aiChannel == .directApiKey {
                TextField("Anthropic model", text: $ai.anthropicModel).onSubmit(onCommit)
                Text("API Key は今後の BYOK 画面で Keychain 保存します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Gateway URL", text: $ai.proxyBaseURL).onSubmit(onCommit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Apple でサインイン") { Task { await onSignInWithApple() } }
                Text("初回解析時にも Apple サインインが要求されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }
}
