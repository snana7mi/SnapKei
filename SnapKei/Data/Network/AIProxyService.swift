import Foundation

public final class AIProxyService: ReceiptParser, @unchecked Sendable {
    private static let appId = "snapkei"

    private let proxyBaseURLProvider: @Sendable () -> String
    private let tokenStore: AuthTokenStore
    private let signIn: AppleSignInAuthenticating
    private let session: URLSession

    public init(
        proxyBaseURLProvider: @escaping @Sendable () -> String,
        tokenStore: AuthTokenStore = AuthTokenStore(),
        signIn: AppleSignInAuthenticating,
        session: URLSession = .shared
    ) {
        self.proxyBaseURLProvider = proxyBaseURLProvider
        self.tokenStore = tokenStore
        self.signIn = signIn
        self.session = session
    }

    public func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: false)
    }

    private func callGateway(imageData: Data, mimeType: String, isRetry: Bool) async throws -> ReceiptDraft {
        let accessToken = try await validAccessToken()
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
            if try await refreshAccessToken() {
                return try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: true)
            }
            try tokenStore.clearSession()
            try await authenticateWithApple()
            return try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: true)
        case 429:
            return try throwRateLimited(data: data)
        case 503:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    private func validAccessToken() async throws -> String {
        if let stored = try tokenStore.load() {
            return stored.accessToken
        }
        try await authenticateWithApple()
        guard let stored = try tokenStore.load() else { throw AIServiceError.proxyAuthRequired }
        return stored.accessToken
    }

    private func authenticateWithApple() async throws {
        let nonce = NonceGenerator.makePair()
        let result = try await signIn.authenticate(nonceRaw: nonce.raw, hashedNonce: nonce.hashedSHA256)
        var request = try makeRequest(path: "/auth/apple")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AppleAuthRequest(identityToken: result.identityToken, nonce: nonce.raw, deviceName: "SnapKei iOS"))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIServiceError.proxyAuthRequired }
        let auth = try JSONDecoder().decode(AppleAuthResponse.self, from: data)
        try tokenStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken, appleUserId: result.appleUserId)
    }

    private func refreshAccessToken() async throws -> Bool {
        guard let stored = try tokenStore.load() else { return false }
        var request = try makeRequest(path: "/auth/refresh")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: stored.refreshToken, deviceName: "SnapKei iOS"))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        try tokenStore.updateAccessToken(refreshed.accessToken, refreshToken: refreshed.refreshToken)
        return true
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

private struct AppleAuthRequest: Encodable {
    let identityToken: String
    let nonce: String
    let deviceName: String
}

private struct AppleAuthResponse: Decodable {
    struct User: Decodable {
        let id: String
        let tier: String?
    }
    let accessToken: String
    let refreshToken: String
    let user: User
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
    let deviceName: String
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}
