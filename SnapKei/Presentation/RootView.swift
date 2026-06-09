import LLMGatewayKit
import SwiftUI

public struct RootView: View {
    @Environment(\.captureViewModel) private var captureViewModel
    @Environment(SyncStatusObserver.self) private var syncObserver
    @State private var showOnboarding = !AppSettings.load().hasCompletedOnboarding

    public init() {}

    public var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("tab.home", systemImage: "house") }

            if let captureViewModel {
                CaptureView(viewModel: captureViewModel)
                    .tabItem { Label("tab.capture", systemImage: "camera") }
            } else {
                Text("Capture unavailable")
                    .tabItem { Label("tab.capture", systemImage: "camera") }
            }

            ExpenseListView()
                .tabItem { Label("tab.list", systemImage: "list.bullet.rectangle") }

            BooksView()
                .tabItem { Label("tab.books", systemImage: "books.vertical") }

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { businessName, ownerName in
                var settings = AppSettings.load()
                let trimmedBusinessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedOwnerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedBusinessName.isEmpty { settings.businessName = trimmedBusinessName }
                if !trimmedOwnerName.isEmpty { settings.ownerName = trimmedOwnerName }
                settings.hasCompletedOnboarding = true
                settings.save()
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .overlay(alignment: .top) {
            SyncToastView(observer: syncObserver)
        }
    }
}

private struct CaptureViewModelKey: EnvironmentKey {
    static let defaultValue: CaptureViewModel? = nil
}

extension EnvironmentValues {
    public var captureViewModel: CaptureViewModel? {
        get { self[CaptureViewModelKey.self] }
        set { self[CaptureViewModelKey.self] = newValue }
    }
}

#Preview {
    Text("RootView requires app environment")
}
