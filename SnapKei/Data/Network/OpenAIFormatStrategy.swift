import Foundation

public struct OpenAIFormatStrategy: AIFormatStrategy {
    public let format: APIFormat = .openAI

    public nonisolated init() {}

    public func makeRequest(config: AIRequestConfig, apiKey: String, imageData: Data, mimeType: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint, timeoutInterval: config.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let prompt = """
        You are parsing Japanese receipt images for bookkeeping. Return only JSON matching this schema:
        {"amountIncludingTax":1100,"amountExcludingTax":1000,"consumptionTax":100,"taxCategory":"standard10","priceEntryMode":"taxIncluded","paymentMethod":"ownerLoan","counterpartyName":"店名","invoiceRegistrationNumber":null,"invoiceQualified":false,"transactionDescription":"説明","suggestedDebitAccountCode":"5110","confidence":0.9,"rawText":"OCR text"}
        """

        let dataURI = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURI]]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func parseResponse(data: Data) throws -> ReceiptDraft {
        let root = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = root.choices.first?.message.content else {
            throw AIServiceError.invalidResponse("missing message content")
        }
        let json = try JSONExtractor.extractJSONObject(from: content)
        return try ReceiptDraftDecoder.decode(json)
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
