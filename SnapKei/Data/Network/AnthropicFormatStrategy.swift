import Foundation

public struct AnthropicFormatStrategy: AIFormatStrategy {
    public let format: APIFormat = .anthropic

    public nonisolated init() {}

    public func makeRequest(config: AIRequestConfig, apiKey: String, imageData: Data, mimeType: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint, timeoutInterval: config.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = """
        You are parsing Japanese receipt images for bookkeeping. Return only JSON matching this schema:
        {"amountIncludingTax":1100,"amountExcludingTax":1000,"consumptionTax":100,"taxCategory":"standard10","priceEntryMode":"taxIncluded","paymentMethod":"ownerLoan","counterpartyName":"店名","invoiceRegistrationNumber":null,"invoiceQualified":false,"transactionDescription":"説明","suggestedDebitAccountCode":"5110","confidence":0.9,"rawText":"OCR text"}
        """

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image", "source": [
                        "type": "base64",
                        "media_type": mimeType,
                        "data": imageData.base64EncodedString()
                    ]]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func parseResponse(data: Data) throws -> ReceiptDraft {
        let root = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let text = root.content.first(where: { $0.type == "text" })?.text else {
            throw AIServiceError.invalidResponse("missing text content")
        }
        let json = try JSONExtractor.extractJSONObject(from: text)
        return try ReceiptDraftDecoder.decode(json)
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }
    let content: [Content]
}
