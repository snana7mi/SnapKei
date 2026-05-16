import Foundation
import Testing
@testable import SnapKei

@Suite("AISettings")
struct AISettingsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    @Test func defaultUsesDirectAnthropic() {
        #expect(AISettings.default.aiChannel == .directApiKey)
        #expect(AISettings.default.preferredFormat == .anthropic)
    }

    @Test func roundTripPersistsSettings() {
        let defaults = defaults()
        let settings = AISettings(aiChannel: .builtInProxy, preferredFormat: .anthropic, proxyBaseURL: "https://worker.example", anthropicModel: "claude-test")
        settings.save(defaults: defaults)
        #expect(AISettings.load(defaults: defaults) == settings)
    }
}
