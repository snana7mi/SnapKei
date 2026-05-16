import Foundation

public final class AIRouter: ReceiptParser, @unchecked Sendable {
    private let settingsProvider: @Sendable () -> AISettings
    private let directParser: ReceiptParser
    private let proxyParser: ReceiptParser

    public init(
        settingsProvider: @escaping @Sendable () -> AISettings,
        directParser: ReceiptParser,
        proxyParser: ReceiptParser
    ) {
        self.settingsProvider = settingsProvider
        self.directParser = directParser
        self.proxyParser = proxyParser
    }

    public func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        switch settingsProvider().aiChannel {
        case .directApiKey:
            return try await directParser.parseReceipt(imageData: imageData, mimeType: mimeType)
        case .builtInProxy:
            return try await proxyParser.parseReceipt(imageData: imageData, mimeType: mimeType)
        }
    }
}
