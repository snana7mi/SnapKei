import Foundation
import Testing
@testable import SnapKei

@Suite("OpenAIFormatStrategy")
struct OpenAIFormatStrategyTests {
    private var config: AIRequestConfig {
        AIRequestConfig(endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!, model: "gpt-4o-mini")
    }

    @Test func requestContainsBearerAuthAndImageDataURI() throws {
        let request = try OpenAIFormatStrategy().makeRequest(
            config: config,
            apiKey: "sk-openai-test",
            imageData: Data([1, 2, 3]),
            mimeType: "image/jpeg"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openai-test")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("AQID"))                       // base64 of [1,2,3]
        #expect(body.contains("image_url"))
        #expect(body.contains("data:image\\/jpeg;base64"))
        #expect(body.contains("gpt-4o-mini"))
    }

    @Test func parsesChoicesJSONResponse() throws {
        let json = """
        {"choices":[{"message":{"content":"{\\\"amountIncludingTax\\\":1100,\\\"taxCategory\\\":\\\"standard10\\\",\\\"priceEntryMode\\\":\\\"taxIncluded\\\",\\\"paymentMethod\\\":\\\"ownerLoan\\\",\\\"counterpartyName\\\":\\\"店\\\",\\\"invoiceQualified\\\":false,\\\"transactionDescription\\\":\\\"通信費\\\",\\\"confidence\\\":0.9}"}}]}
        """
        let draft = try OpenAIFormatStrategy().parseResponse(data: Data(json.utf8))
        #expect(draft.amountIncludingTax == 1100)
        #expect(draft.counterpartyName == "店")
    }
}
