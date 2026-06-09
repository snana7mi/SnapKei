import Foundation
import LLMGatewayKit

public final class AIProxyService: ReceiptParser, @unchecked Sendable {
    private static let appId = "snapkei"

    private let proxyBaseURLProvider: @Sendable () -> String
    private let authService: AuthService
    private let session: URLSession

    public init(
        proxyBaseURLProvider: @escaping @Sendable () -> String,
        authService: AuthService,
        session: URLSession = .shared
    ) {
        self.proxyBaseURLProvider = proxyBaseURLProvider
        self.authService = authService
        self.session = session
    }

    public func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: false)
    }

    private func callGateway(imageData: Data, mimeType: String, isRetry: Bool) async throws -> ReceiptDraft {
        let accessToken: String
        do {
            accessToken = try await authService.validAccessToken()
        } catch AuthError.notLoggedIn {
            try await authService.authenticateInteractively()
            accessToken = try await authService.validAccessToken()
        }
        var request = try makeRequest(path: "/api/\(Self.appId)")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GatewayChatRequest.receipt(imageData: imageData, mimeType: mimeType))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse("missing HTTP response") }
        switch http.statusCode {
        case 200:
            return try decodeChatCompletion(data)
        case 401:
            if isRetry { throw AIServiceError.proxySessionExpired }
            try await authService.refreshAccessToken()
            return try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: true)
        case 429:
            return try throwRateLimited(data: data)
        case 503:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let baseURL = proxyBaseURLProvider().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else { throw AIServiceError.invalidEndpoint }
        return URLRequest(url: url)
    }

    private func decodeChatCompletion(_ data: Data) throws -> ReceiptDraft {
        let response = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AIServiceError.invalidResponse("missing chat completion content")
        }
        let json = try JSONExtractor.extractJSONObject(from: content)
        return try ReceiptDraftDecoder.decode(json)
    }

    private func throwRateLimited(data: Data) throws -> ReceiptDraft {
        let retryAfter = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0["retryAfter"] as? String }
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        throw AIServiceError.rateLimited(retryAfter: retryAfter)
    }
}

private struct GatewayChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String?
        let imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
    }

    struct ImageURL: Encodable {
        let url: String
    }

    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }

    static func receipt(imageData: Data, mimeType: String) -> GatewayChatRequest {
        let prompt = """
        You are parsing Japanese receipt images for bookkeeping. Return only JSON matching this schema:
        {"amountIncludingTax":1100,"amountExcludingTax":1000,"consumptionTax":100,"taxCategory":"standard10","priceEntryMode":"taxIncluded","paymentMethod":"ownerLoan","counterpartyName":"店名","invoiceRegistrationNumber":null,"invoiceQualified":false,"transactionDescription":"説明","suggestedDebitAccountCode":"5110","confidence":0.9,"rawText":"OCR text"}
        """
        return GatewayChatRequest(
            messages: [Message(role: "user", content: [
                Content(type: "text", text: prompt, imageURL: nil),
                Content(
                    type: "image_url",
                    text: nil,
                    imageURL: ImageURL(url: "data:\(mimeType);base64,\(imageData.base64EncodedString())")
                ),
            ])],
            temperature: 0,
            maxTokens: 1024
        )
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

