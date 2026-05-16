import Foundation

public final class ClaudeVisionService: ReceiptParser, @unchecked Sendable {
    private let apiKeyProvider: @Sendable () throws -> String
    private let configProvider: @Sendable () -> AIRequestConfig
    private let strategy: AIFormatStrategy
    private let session: URLSession

    public init(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        configProvider: @escaping @Sendable () -> AIRequestConfig = { .anthropicDefault },
        strategy: AIFormatStrategy = AnthropicFormatStrategy(),
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.configProvider = configProvider
        self.strategy = strategy
        self.session = session
    }

    public func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        let apiKey = try apiKeyProvider()
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        let request = try strategy.makeRequest(config: configProvider(), apiKey: apiKey, imageData: imageData, mimeType: mimeType)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse("missing HTTP response") }
        switch http.statusCode {
        case 200:
            return try strategy.parseResponse(data: data)
        case 429:
            throw AIServiceError.rateLimited(retryAfter: nil)
        case 529, 503:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(http.statusCode)")
        }
    }
}
