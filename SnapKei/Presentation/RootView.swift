import SwiftUI

public struct RootView: View {
    @Environment(\.captureViewModel) private var captureViewModel

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

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
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
    RootView()
}
