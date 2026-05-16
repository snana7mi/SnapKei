import Foundation

public struct OpenAIFormatStrategy: AIFormatStrategy {
    public let format: APIFormat = .openAI

    public init() {}

    public func makeRequest(config: AIRequestConfig, apiKey: String, imageData: Data, mimeType: String) throws -> URLRequest {
        throw AIServiceError.invalidResponse("OpenAI format is reserved for a future provider")
    }

    public func parseResponse(data: Data) throws -> ReceiptDraft {
        throw AIServiceError.invalidResponse("OpenAI format is reserved for a future provider")
    }
}
