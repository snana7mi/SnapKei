import Foundation
import Testing
@testable import SnapKei

private final class StaticStrategy: AIFormatStrategy, @unchecked Sendable {
    let format: APIFormat = .anthropic
    func makeRequest(config: AIRequestConfig, apiKey: String, imageData: Data, mimeType: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        return request
    }
    func parseResponse(data: Data) throws -> ReceiptDraft {
        ReceiptDraft(amountIncludingTax: 1_100, counterpartyName: "店", transactionDescription: "通信費")
    }
}

@Suite("ClaudeVisionService")
struct ClaudeVisionServiceTests {
    @Test func missingApiKeyThrows() async throws {
        let service = ClaudeVisionService(apiKeyProvider: { "" }, strategy: StaticStrategy())
        await #expect(throws: AIServiceError.missingAPIKey) {
            try await service.parseReceipt(imageData: Data(), mimeType: "image/jpeg")
        }
    }
}
