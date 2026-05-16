import Foundation
import Testing
@testable import SnapKei

private final class StubParser: ReceiptParser, @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
    func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        ReceiptDraft(amountIncludingTax: name == "direct" ? 1 : 2, counterpartyName: name, transactionDescription: name)
    }
}

@Suite("AIRouter")
struct AIRouterTests {
    @Test func routesToDirectParser() async throws {
        let router = AIRouter(
            settingsProvider: { AISettings(aiChannel: .directApiKey, preferredFormat: .anthropic, proxyBaseURL: "", anthropicModel: "m") },
            directParser: StubParser(name: "direct"),
            proxyParser: StubParser(name: "proxy")
        )
        let result = try await router.parseReceipt(imageData: Data(), mimeType: "image/jpeg")
        #expect(result.counterpartyName == "direct")
    }

    @Test func routesToProxyParser() async throws {
        let router = AIRouter(
            settingsProvider: { AISettings(aiChannel: .builtInProxy, preferredFormat: .anthropic, proxyBaseURL: "", anthropicModel: "m") },
            directParser: StubParser(name: "direct"),
            proxyParser: StubParser(name: "proxy")
        )
        let result = try await router.parseReceipt(imageData: Data(), mimeType: "image/jpeg")
        #expect(result.counterpartyName == "proxy")
    }
}
