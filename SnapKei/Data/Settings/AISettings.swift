import Foundation

public struct AISettings: Sendable, Equatable {
    public var aiChannel: AIChannel
    public var preferredFormat: APIFormat
    public var proxyBaseURL: String
    public var anthropicModel: String

    public nonisolated static let `default` = AISettings(
        aiChannel: .directApiKey,
        preferredFormat: .anthropic,
        proxyBaseURL: "",
        anthropicModel: AIRequestConfig.anthropicDefault.model
    )

    public nonisolated init(aiChannel: AIChannel, preferredFormat: APIFormat, proxyBaseURL: String, anthropicModel: String) {
        self.aiChannel = aiChannel
        self.preferredFormat = preferredFormat
        self.proxyBaseURL = proxyBaseURL
        self.anthropicModel = anthropicModel
    }

    private enum Keys {
        nonisolated static let aiChannel = "ai.channel"
        nonisolated static let preferredFormat = "ai.preferredFormat"
        nonisolated static let proxyBaseURL = "ai.proxyBaseURL"
        nonisolated static let anthropicModel = "ai.anthropicModel"
    }

    public nonisolated static func load(defaults: UserDefaults = .standard) -> AISettings {
        AISettings(
            aiChannel: AIChannel(rawValue: defaults.string(forKey: Keys.aiChannel) ?? "") ?? .directApiKey,
            preferredFormat: APIFormat(rawValue: defaults.string(forKey: Keys.preferredFormat) ?? "") ?? .anthropic,
            proxyBaseURL: defaults.string(forKey: Keys.proxyBaseURL) ?? "",
            anthropicModel: defaults.string(forKey: Keys.anthropicModel) ?? AIRequestConfig.anthropicDefault.model
        )
    }

    public nonisolated func save(defaults: UserDefaults = .standard) {
        defaults.set(aiChannel.rawValue, forKey: Keys.aiChannel)
        defaults.set(preferredFormat.rawValue, forKey: Keys.preferredFormat)
        defaults.set(proxyBaseURL, forKey: Keys.proxyBaseURL)
        defaults.set(anthropicModel, forKey: Keys.anthropicModel)
    }
}
