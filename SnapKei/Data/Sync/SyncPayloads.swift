import Foundation

struct JournalEntryPayload: Codable {
    let syncId: UUID
    let entryNumber: Int
    let fiscalYear: Int
    let transactionDate: Date
    let inputDate: Date
    let isLateEntry: Bool
    let debitAccountCode: String
    let creditAccountCode: String
    let amountIncludingTax: Int
    let amountExcludingTax: Int
    let consumptionTax: Int
    let taxCategoryRaw: String
    let priceEntryModeRaw: String
    let paymentMethodRaw: String
    let counterpartyName: String
    let invoiceRegistrationNumber: String?
    let invoiceQualified: Bool
    let transitionalMeasureRate: Double
    let transactionDescription: String
    let memo: String?
    let businessAllocationRate: Double
    let originalAmountIncludingTax: Int?
    let relatedFixedAssetId: UUID?
    let receiptImageHash: String?
    let sourceTypeRaw: String
    let createdAt: Date
    let updatedAt: Date
    let isVoided: Bool
    let deletedAt: Date?

    init(from entry: JournalEntry) {
        syncId = entry.syncId
        entryNumber = entry.entryNumber
        fiscalYear = entry.fiscalYear
        transactionDate = entry.transactionDate
        inputDate = entry.inputDate
        isLateEntry = entry.isLateEntry
        debitAccountCode = entry.debitAccountCode
        creditAccountCode = entry.creditAccountCode
        amountIncludingTax = entry.amountIncludingTax
        amountExcludingTax = entry.amountExcludingTax
        consumptionTax = entry.consumptionTax
        taxCategoryRaw = entry.taxCategoryRaw
        priceEntryModeRaw = entry.priceEntryModeRaw
        paymentMethodRaw = entry.paymentMethodRaw
        counterpartyName = entry.counterpartyName
        invoiceRegistrationNumber = entry.invoiceRegistrationNumber
        invoiceQualified = entry.invoiceQualified
        transitionalMeasureRate = entry.transitionalMeasureRate
        transactionDescription = entry.transactionDescription
        memo = entry.memo
        businessAllocationRate = entry.businessAllocationRate
        originalAmountIncludingTax = entry.originalAmountIncludingTax
        relatedFixedAssetId = entry.relatedFixedAssetId
        receiptImageHash = entry.receiptImageHash
        sourceTypeRaw = entry.sourceTypeRaw
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        isVoided = entry.isVoided
        deletedAt = entry.isVoided ? entry.updatedAt : nil
    }
}

struct FixedAssetPayload: Codable {
    let syncId: UUID
    let assetName: String
    let assetCategoryCode: String
    let acquisitionDate: Date
    let serviceStartDate: Date
    let acquisitionAmount: Int
    let usefulLifeYears: Int
    let depreciationMethodRaw: String
    let treatmentRaw: String
    let businessAllocationRate: Double
    let acquisitionJournalEntryId: UUID?
    let accumulatedDepreciation: Int
    let bookValue: Int
    let disposalDate: Date?
    let disposalAmount: Int?
    let updatedAt: Date
    let deletedAt: Date?

    init(from asset: FixedAsset) {
        syncId = asset.syncId
        assetName = asset.assetName
        assetCategoryCode = asset.assetCategoryCode
        acquisitionDate = asset.acquisitionDate
        serviceStartDate = asset.serviceStartDate
        acquisitionAmount = asset.acquisitionAmount
        usefulLifeYears = asset.usefulLifeYears
        depreciationMethodRaw = asset.depreciationMethodRaw
        treatmentRaw = asset.treatmentRaw
        businessAllocationRate = asset.businessAllocationRate
        acquisitionJournalEntryId = asset.acquisitionJournalEntryId
        accumulatedDepreciation = asset.accumulatedDepreciation
        bookValue = asset.bookValue
        disposalDate = asset.disposalDate
        disposalAmount = asset.disposalAmount
        updatedAt = asset.updatedAt
        deletedAt = asset.deletedAt
    }
}

struct OpeningBalancePayload: Codable {
    let syncId: UUID
    let fiscalYear: Int
    let accountCode: String
    let amount: Int
    let isAutoRolled: Bool
    let updatedAt: Date
    let deletedAt: Date?

    init(from opening: OpeningBalance) {
        syncId = opening.syncId
        fiscalYear = opening.fiscalYear
        accountCode = opening.accountCode
        amount = opening.amount
        isAutoRolled = opening.isAutoRolled
        updatedAt = opening.updatedAt
        deletedAt = opening.deletedAt
    }
}

struct FiscalYearClosurePayload: Codable {
    let syncId: UUID
    let fiscalYear: Int
    let closedAt: Date
    let netIncomeAtClosing: Int
    let closedByDeviceId: String
    let updatedAt: Date
    let deletedAt: Date?

    init(from closure: FiscalYearClosure) {
        syncId = closure.syncId
        fiscalYear = closure.fiscalYear
        closedAt = closure.closedAt
        netIncomeAtClosing = closure.netIncomeAtClosing
        closedByDeviceId = closure.closedByDeviceId
        updatedAt = closure.updatedAt
        deletedAt = closure.deletedAt
    }
}
