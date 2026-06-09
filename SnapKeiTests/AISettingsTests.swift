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
        let settings = AISettings(aiChannel: .builtInProxy, preferredFormat: .anthropic, proxyBaseURL: "https://worker.example", anthropicModel: "claude-test", openAIModel: "gpt-test")
        settings.save(defaults: defaults)
        #expect(AISettings.load(defaults: defaults) == settings)
    }

    @Test func openAIModelDefaultsToOpenAIDefault() {
        #expect(AISettings.default.openAIModel == AIRequestConfig.openAIDefault.model)
    }

    @Test func openAIModelRoundTrips() {
        let defaults = defaults()
        var settings = AISettings.default
        settings.openAIModel = "gpt-4o"
        settings.save(defaults: defaults)
        #expect(AISettings.load(defaults: defaults).openAIModel == "gpt-4o")
    }
}
