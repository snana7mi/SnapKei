import Foundation

public struct AIRequestConfig: Sendable, Equatable {
    public var endpoint: URL
    public var model: String
    public var maxTokens: Int
    public var temperature: Double
    public var timeoutSeconds: TimeInterval

    public nonisolated init(endpoint: URL, model: String, maxTokens: Int = 1024, temperature: Double = 0, timeoutSeconds: TimeInterval = 60) {
        self.endpoint = endpoint
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
    }

    public nonisolated static let anthropicDefault = AIRequestConfig(
        endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
        model: "claude-3-5-sonnet-latest"
    )
}
