import Foundation
import Testing
@testable import SnapKei

private final class MockAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
    let result: AppleSignInResult

    init(result: AppleSignInResult) {
        self.result = result
    }

    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        result
    }
}

private final class GatewayURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    nonisolated override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: AIServiceError.invalidResponse("missing handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}
}

@Suite("AIProxyService — llm-gateway-back")
struct AIProxyServiceTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GatewayURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func authenticatesWithAppleThenCallsSnapKeiGatewayApp() async throws {
        let tokenStore = AuthTokenStore(keychain: MemorySecretStore())
        let session = makeSession()
        var paths: [String] = []

        GatewayURLProtocol.handler = { request in
            let path = request.url!.path
            paths.append(path)
            if path == "/auth/apple" {
                let body = requestBodyString(request)
                #expect(body.contains("apple-token"))
                #expect(body.contains("\"nonce\""))
                return jsonResponse(for: request, status: 200, body: """
                {"accessToken":"access-1","refreshToken":"refresh-1","user":{"id":"user-1","tier":"free"}}
                """)
            }
            if path == "/api/snapkei" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
                let body = requestBodyString(request)
                #expect(body.contains("data:image\\/jpeg;base64,AQID") || body.contains("data:image/jpeg;base64,AQID"))
                #expect(body.contains("Return only JSON"))
                return openAIReceiptResponse(for: request)
            }
            return jsonResponse(for: request, status: 404, body: "{}")
        }

        let service = AIProxyService(
            proxyBaseURLProvider: { "https://api.conch-talk.com" },
            tokenStore: tokenStore,
            signIn: MockAppleSignIn(result: AppleSignInResult(identityToken: "apple-token", appleUserId: "apple-user")),
            session: session
        )

        let draft = try await service.parseReceipt(imageData: Data([1, 2, 3]), mimeType: "image/jpeg")
        #expect(draft.amountIncludingTax == 1100)
        #expect(draft.counterpartyName == "店")
        #expect(paths == ["/auth/apple", "/api/snapkei"])
        #expect(try tokenStore.load()?.refreshToken == "refresh-1")
    }

    @Test func refreshesAccessTokenOnGateway401ThenRetries() async throws {
        let tokenStore = AuthTokenStore(keychain: MemorySecretStore())
        try tokenStore.save(accessToken: "expired", refreshToken: "refresh-old", appleUserId: "apple-user")
        let session = makeSession()
        var apiCalls = 0
        var refreshCalls = 0

        GatewayURLProtocol.handler = { request in
            let path = request.url!.path
            if path == "/api/snapkei" {
                apiCalls += 1
                if apiCalls == 1 {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer expired")
                    return jsonResponse(for: request, status: 401, body: "{\"error\":\"Token expired\"}")
                }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-new")
                return openAIReceiptResponse(for: request)
            }
            if path == "/auth/refresh" {
                refreshCalls += 1
                let body = requestBodyString(request)
                #expect(body.contains("refresh-old"))
                return jsonResponse(for: request, status: 200, body: """
                {"accessToken":"access-new","refreshToken":"refresh-new"}
                """)
            }
            return jsonResponse(for: request, status: 404, body: "{}")
        }

        let service = AIProxyService(
            proxyBaseURLProvider: { "https://api.conch-talk.com" },
            tokenStore: tokenStore,
            signIn: MockAppleSignIn(result: AppleSignInResult(identityToken: "apple-token", appleUserId: "apple-user")),
            session: session
        )

        let draft = try await service.parseReceipt(imageData: Data([1]), mimeType: "image/jpeg")
        #expect(draft.amountIncludingTax == 1100)
        #expect(apiCalls == 2)
        #expect(refreshCalls == 1)
        #expect(try tokenStore.load()?.accessToken == "access-new")
        #expect(try tokenStore.load()?.refreshToken == "refresh-new")
    }
}

private func jsonResponse(for request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (response, Data(body.utf8))
}

private func openAIReceiptResponse(for request: URLRequest) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    let content = #"{"amountIncludingTax":1100,"taxCategory":"standard10","priceEntryMode":"taxIncluded","paymentMethod":"ownerLoan","counterpartyName":"店","invoiceQualified":false,"transactionDescription":"通信費","confidence":0.9}"#
    let payload: [String: Any] = [
        "choices": [["message": ["content": content]]],
        "usage": ["prompt_tokens": 10, "completion_tokens": 10],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return (response, data)
}

private func requestBodyString(_ request: URLRequest) -> String {
    if let httpBody = request.httpBody {
        return String(data: httpBody, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}
