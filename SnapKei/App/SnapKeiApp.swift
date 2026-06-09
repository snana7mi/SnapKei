import SwiftData
import SwiftUI
import LLMGatewayKit
import UIKit

@main
struct SnapKeiApp: App {
    @State private var authService: AuthService
    @State private var subscriptionService: SubscriptionService
    @State private var syncStatusObserver: SyncStatusObserver
    @State private var captureViewModel: CaptureViewModel

    private let modelContainer: ModelContainer
    private let config: LLMGatewayKitConfig
    private let syncEngine: SyncEngine

    @MainActor
    init() {
        let gatewayURLString = (Bundle.main.object(forInfoDictionaryKey: "GATEWAY_BASE_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.conch-talk.com"
        let revenueCatAPIKey = (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: gatewayURLString)!,
            entitlementID: "pro",
            appDisplayName: "SnapKei",
            companionAppNames: ["ConchTalk"],
            revenueCatAPIKey: revenueCatAPIKey,
            paywallFeatures: [
                PaywallFeature(id: "ai-quota", icon: "doc.text.magnifyingglass", title: "AI 解析回数の増加", subtitle: nil),
                PaywallFeature(id: "cloud-sync", icon: "icloud.fill", title: "R1 クラウド自動バックアップ", subtitle: nil),
                PaywallFeature(id: "reports", icon: "chart.bar.fill", title: "詳細レポート", subtitle: nil),
            ],
            deviceName: UIDevice.current.name
        )
        self.config = config

        let auth = AuthService(config: config)
        auth.restoreSession()
        self._authService = State(initialValue: auth)

        let subscription = SubscriptionService(authService: auth, config: config)
        subscription.startListening()
        self._subscriptionService = State(initialValue: subscription)

        let container = SnapKeiModelContainer.shared
        self.modelContainer = container
        let context = container.mainContext
        let repository = SwiftDataExpenseRepository(
            context: context,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )

        let cursor = SyncCursorStore()
        let engine = SyncEngine(
            apiClient: SyncAPIClient(config: config, auth: auth),
            codec: IdentityPayloadCodec(),
            collector: SnapKeiChangeCollector(context: context, cursor: cursor),
            merger: SnapKeiMerger(context: context),
            state: SyncState.shared,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device",
            isEligible: { [weak auth] in
                guard let auth else { return false }
                return await MainActor.run {
                    auth.isLoggedIn && auth.currentUser?.tier == "paid" && SyncState.shared.isEnabled
                }
            }
        )
        self.syncEngine = engine
        self._syncStatusObserver = State(initialValue: SyncStatusObserver(engine: engine))

        let syncChanges = AsyncStream<Void> { continuation in
            let repoTask = Task {
                for await _ in repository.changes {
                    continuation.yield()
                }
            }
            let notifierTask = Task {
                for await _ in SyncChangeNotifier.shared.changes {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in
                repoTask.cancel()
                notifierTask.cancel()
            }
        }
        Task {
            await engine.startAutoSync(repoChanges: syncChanges)
        }

        let proxyService = AIProxyService(
            proxyBaseURLProvider: {
                let configured = AISettings.load().proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return configured.isEmpty ? "https://api.conch-talk.com" : configured
            },
            authService: auth
        )
        let directService = ClaudeVisionService(
            apiKeyProvider: {
                try ByokKeyStore().loadKey(for: AISettings.load().preferredFormat) ?? ""
            },
            configProvider: {
                let settings = AISettings.load()
                return settings.preferredFormat == .openAI
                    ? .openAI(model: settings.openAIModel)
                    : .anthropic(model: settings.anthropicModel)
            },
            strategyProvider: { () -> AIFormatStrategy in
                AISettings.load().preferredFormat == .openAI
                    ? OpenAIFormatStrategy()
                    : AnthropicFormatStrategy()
            }
        )
        let router = AIRouter(
            settingsProvider: { AISettings.load() },
            directParser: directService,
            proxyParser: proxyService
        )
        self._captureViewModel = State(initialValue: CaptureViewModel(
            aiRouter: router,
            repository: repository,
            appSettings: { AppSettings.load() },
            aiSettings: { AISettings.load() }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.captureViewModel, captureViewModel)
                .environment(authService)
                .environment(subscriptionService)
                .environment(syncStatusObserver)
                .environment(\.llmGatewayKitConfig, config)
                .environment(\.snapKeiSyncEngine, syncEngine)
                .modelContainer(modelContainer)
        }
    }
}

private struct LLMGatewayKitConfigKey: EnvironmentKey {
    static let defaultValue: LLMGatewayKitConfig? = nil
}

private struct SnapKeiSyncEngineKey: EnvironmentKey {
    static let defaultValue: SyncEngine? = nil
}

extension EnvironmentValues {
    public var llmGatewayKitConfig: LLMGatewayKitConfig? {
        get { self[LLMGatewayKitConfigKey.self] }
        set { self[LLMGatewayKitConfigKey.self] = newValue }
    }

    public var snapKeiSyncEngine: SyncEngine? {
        get { self[SnapKeiSyncEngineKey.self] }
        set { self[SnapKeiSyncEngineKey.self] = newValue }
    }
}
