import Foundation

public struct ReceiptDraft: Codable, Equatable, Sendable {
    public var transactionDate: Date?
    public var amountIncludingTax: Int
    public var amountExcludingTax: Int?
    public var consumptionTax: Int?
    public var taxCategory: TaxCategory
    public var priceEntryMode: PriceEntryMode
    public var paymentMethod: PaymentMethod
    public var counterpartyName: String
    public var invoiceRegistrationNumber: String?
    public var invoiceQualified: Bool
    public var transactionDescription: String
    public var suggestedDebitAccountCode: String?
    public var confidence: Double
    public var rawText: String?

    public nonisolated init(
        transactionDate: Date? = nil,
        amountIncludingTax: Int,
        amountExcludingTax: Int? = nil,
        consumptionTax: Int? = nil,
        taxCategory: TaxCategory = .standard10,
        priceEntryMode: PriceEntryMode = .taxIncluded,
        paymentMethod: PaymentMethod = .ownerLoan,
        counterpartyName: String,
        invoiceRegistrationNumber: String? = nil,
        invoiceQualified: Bool = false,
        transactionDescription: String,
        suggestedDebitAccountCode: String? = nil,
        confidence: Double = 0,
        rawText: String? = nil
    ) {
        self.transactionDate = transactionDate
        self.amountIncludingTax = amountIncludingTax
        self.amountExcludingTax = amountExcludingTax
        self.consumptionTax = consumptionTax
        self.taxCategory = taxCategory
        self.priceEntryMode = priceEntryMode
        self.paymentMethod = paymentMethod
        self.counterpartyName = counterpartyName
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceQualified = invoiceQualified
        self.transactionDescription = transactionDescription
        self.suggestedDebitAccountCode = suggestedDebitAccountCode
        self.confidence = confidence
        self.rawText = rawText
    }
}

public protocol ReceiptParser: Sendable {
    func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft
}
