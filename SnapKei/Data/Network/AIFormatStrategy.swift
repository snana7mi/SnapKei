import Foundation

public protocol AIFormatStrategy: Sendable {
    var format: APIFormat { get }
    func makeRequest(config: AIRequestConfig, apiKey: String, imageData: Data, mimeType: String) throws -> URLRequest
    func parseResponse(data: Data) throws -> ReceiptDraft
}
