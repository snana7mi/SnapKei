import Foundation
import Testing
@testable import SnapKei

@Suite("AnthropicFormatStrategy")
struct AnthropicFormatStrategyTests {
    @Test func requestContainsAnthropicHeadersAndImage() throws {
        let strategy = AnthropicFormatStrategy()
        let request = try strategy.makeRequest(
            config: .anthropicDefault,
            apiKey: "sk-test",
            imageData: Data([1, 2, 3]),
            mimeType: "image/jpeg"
        )
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("AQID"))
        #expect(body.contains("image\\/jpeg"))
    }

    @Test func parsesTextJSONResponse() throws {
        let json = """
        {"content":[{"type":"text","text":"{\\\"amountIncludingTax\\\":1100,\\\"taxCategory\\\":\\\"standard10\\\",\\\"priceEntryMode\\\":\\\"taxIncluded\\\",\\\"paymentMethod\\\":\\\"ownerLoan\\\",\\\"counterpartyName\\\":\\\"店\\\",\\\"invoiceQualified\\\":false,\\\"transactionDescription\\\":\\\"通信費\\\",\\\"confidence\\\":0.9}"}]}
        """
        let draft = try AnthropicFormatStrategy().parseResponse(data: Data(json.utf8))
        #expect(draft.amountIncludingTax == 1100)
        #expect(draft.counterpartyName == "店")
    }
}
