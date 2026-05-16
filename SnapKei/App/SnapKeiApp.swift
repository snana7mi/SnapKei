import SwiftData
import SwiftUI
import UIKit

@main
struct SnapKeiApp: App {
    @MainActor
    private var captureViewModel: CaptureViewModel = {
        let proxyService = AIProxyService(
            proxyBaseURLProvider: {
                let configured = AISettings.load().proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return configured.isEmpty ? "https://api.conch-talk.com" : configured
            },
            tokenStore: AuthTokenStore(),
            signIn: AppleSignInService()
        )
        let directService = ClaudeVisionService(apiKeyProvider: { "" })
        let router = AIRouter(
            settingsProvider: { AISettings.load() },
            directParser: directService,
            proxyParser: proxyService
        )
        let context = SnapKeiModelContainer.shared.mainContext
        let repository = SwiftDataExpenseRepository(
            context: context,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )
        return CaptureViewModel(
            aiRouter: router,
            repository: repository,
            appSettings: { AppSettings.load() },
            aiSettings: { AISettings.load() }
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.captureViewModel, captureViewModel)
        }
        .modelContainer(SnapKeiModelContainer.shared)
    }
}
