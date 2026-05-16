import Foundation
import SwiftData

@Model
public final class JournalEntry {
    @Attribute(.unique) public var id: UUID
    public var entryNumber: Int
    public var fiscalYear: Int
    public var transactionDate: Date
    public var inputDate: Date
    public var isLateEntry: Bool
    public var debitAccountCode: String
    public var creditAccountCode: String
    public var amountIncludingTax: Int
    public var amountExcludingTax: Int
    public var consumptionTax: Int
    public var taxCategoryRaw: String
    public var priceEntryModeRaw: String
    public var paymentMethodRaw: String
    public var counterpartyName: String
    public var invoiceRegistrationNumber: String?
    public var invoiceQualified: Bool
    public var transitionalMeasureRate: Double
    public var transactionDescription: String
    public var memo: String?
    public var businessAllocationRate: Double
    public var originalAmountIncludingTax: Int?
    public var relatedFixedAssetId: UUID?
    public var receiptImagePath: String?
    public var receiptImageHash: String?
    public var sourceTypeRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var syncId: UUID
    public var isVoided: Bool

    public init(
        id: UUID = UUID(),
        entryNumber: Int,
        fiscalYear: Int,
        transactionDate: Date,
        inputDate: Date = Date(),
        isLateEntry: Bool = false,
        debitAccountCode: String,
        creditAccountCode: String,
        amountIncludingTax: Int,
        amountExcludingTax: Int,
        consumptionTax: Int,
        taxCategory: TaxCategory,
        priceEntryMode: PriceEntryMode,
        paymentMethod: PaymentMethod,
        counterpartyName: String,
        invoiceRegistrationNumber: String? = nil,
        invoiceQualified: Bool = false,
        transitionalMeasureRate: Double = 1.0,
        transactionDescription: String,
        memo: String? = nil,
        businessAllocationRate: Double = 1.0,
        originalAmountIncludingTax: Int? = nil,
        relatedFixedAssetId: UUID? = nil,
        receiptImagePath: String? = nil,
        receiptImageHash: String? = nil,
        sourceType: RecordSource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncId: UUID = UUID(),
        isVoided: Bool = false
    ) {
        self.id = id
        self.entryNumber = entryNumber
        self.fiscalYear = fiscalYear
        self.transactionDate = transactionDate
        self.inputDate = inputDate
        self.isLateEntry = isLateEntry
        self.debitAccountCode = debitAccountCode
        self.creditAccountCode = creditAccountCode
        self.amountIncludingTax = amountIncludingTax
        self.amountExcludingTax = amountExcludingTax
        self.consumptionTax = consumptionTax
        self.taxCategoryRaw = taxCategory.rawValue
        self.priceEntryModeRaw = priceEntryMode.rawValue
        self.paymentMethodRaw = paymentMethod.rawValue
        self.counterpartyName = counterpartyName
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceQualified = invoiceQualified
        self.transitionalMeasureRate = transitionalMeasureRate
        self.transactionDescription = transactionDescription
        self.memo = memo
        self.businessAllocationRate = businessAllocationRate
        self.originalAmountIncludingTax = originalAmountIncludingTax
        self.relatedFixedAssetId = relatedFixedAssetId
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.sourceTypeRaw = sourceType.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncId = syncId
        self.isVoided = isVoided
    }

    public var taxCategory: TaxCategory { TaxCategory(rawValue: taxCategoryRaw) ?? .standard10 }
    public var priceEntryMode: PriceEntryMode { PriceEntryMode(rawValue: priceEntryModeRaw) ?? .taxIncluded }
    public var paymentMethod: PaymentMethod { PaymentMethod(rawValue: paymentMethodRaw) ?? .other }
    public var sourceType: RecordSource { RecordSource(rawValue: sourceTypeRaw) ?? .manual }
}
