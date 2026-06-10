import Foundation
import LLMGatewayKit
import SwiftData

/// Thrown when a pulled record cannot be applied. Propagating (instead of silently
/// skipping) keeps the sync cursor from advancing, so the batch is retried on later
/// syncs — and succeeds once the app updates to a version that knows the value.
/// Note this blocks the whole pull stream until then; that is preferred over silently
/// losing a bookkeeping record or materializing it with fallback enum semantics
/// (a wrong FixedAsset.treatment would post incorrect depreciation that syncs back out).
public enum MergeError: Error, Equatable, LocalizedError {
    case unknownEnumValue(entity: String, field: String, rawValue: String)

    public var errorDescription: String? {
        switch self {
        case let .unknownEnumValue(entity, field, rawValue):
            "新しいバージョンのアプリで作成されたデータ（\(entity).\(field)=\(rawValue)）を読み込めません。アプリを最新版に更新してください。"
        }
    }
}

@MainActor
public final class SnapKeiMerger: SyncMerging, @unchecked Sendable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func apply(_ envelope: SyncEnvelope) async throws {
        switch envelope.entityType {
        case "JournalEntry":
            let payload = try JSONDecoder.snapkeiSync.decode(JournalEntryPayload.self, from: envelope.data)
            try applyJournalEntry(payload)
        case "FixedAsset":
            let payload = try JSONDecoder.snapkeiSync.decode(FixedAssetPayload.self, from: envelope.data)
            try applyFixedAsset(payload)
        case "OpeningBalance":
            let payload = try JSONDecoder.snapkeiSync.decode(OpeningBalancePayload.self, from: envelope.data)
            try applyOpeningBalance(payload)
        case "FiscalYearClosure":
            let payload = try JSONDecoder.snapkeiSync.decode(FiscalYearClosurePayload.self, from: envelope.data)
            try applyFiscalYearClosure(payload)
        default:
            return
        }
    }

    /// Rejects payloads carrying enum raw values this app version does not know
    /// (e.g. produced by a future version). Called only on the branches that
    /// materialize data — stale payloads and no-op tombstones are discarded without
    /// validation so an unapplicable record cannot wedge the cursor needlessly.
    private func decodeEnums(
        _ payload: JournalEntryPayload
    ) throws -> (taxCategory: TaxCategory, priceEntryMode: PriceEntryMode, paymentMethod: PaymentMethod, sourceType: RecordSource) {
        guard let taxCategory = TaxCategory(rawValue: payload.taxCategoryRaw) else {
            throw MergeError.unknownEnumValue(entity: "JournalEntry", field: "taxCategory", rawValue: payload.taxCategoryRaw)
        }
        guard let priceEntryMode = PriceEntryMode(rawValue: payload.priceEntryModeRaw) else {
            throw MergeError.unknownEnumValue(entity: "JournalEntry", field: "priceEntryMode", rawValue: payload.priceEntryModeRaw)
        }
        guard let paymentMethod = PaymentMethod(rawValue: payload.paymentMethodRaw) else {
            throw MergeError.unknownEnumValue(entity: "JournalEntry", field: "paymentMethod", rawValue: payload.paymentMethodRaw)
        }
        guard let sourceType = RecordSource(rawValue: payload.sourceTypeRaw) else {
            throw MergeError.unknownEnumValue(entity: "JournalEntry", field: "sourceType", rawValue: payload.sourceTypeRaw)
        }
        return (taxCategory, priceEntryMode, paymentMethod, sourceType)
    }

    private func applyJournalEntry(_ payload: JournalEntryPayload) throws {
        let syncId = payload.syncId
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.syncId == syncId })
        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= payload.updatedAt else { return }
            // update() stores raw strings, but unknown enums are still rejected:
            // fallback accessors would mis-handle the record (see MergeError).
            _ = try decodeEnums(payload)
            update(existing, from: payload)
        } else {
            let (taxCategory, priceEntryMode, paymentMethod, sourceType) = try decodeEnums(payload)
            let entry = JournalEntry(
                entryNumber: payload.entryNumber,
                fiscalYear: payload.fiscalYear,
                transactionDate: payload.transactionDate,
                inputDate: payload.inputDate,
                isLateEntry: payload.isLateEntry,
                debitAccountCode: payload.debitAccountCode,
                creditAccountCode: payload.creditAccountCode,
                amountIncludingTax: payload.amountIncludingTax,
                amountExcludingTax: payload.amountExcludingTax,
                consumptionTax: payload.consumptionTax,
                taxCategory: taxCategory,
                priceEntryMode: priceEntryMode,
                paymentMethod: paymentMethod,
                counterpartyName: payload.counterpartyName,
                invoiceRegistrationNumber: payload.invoiceRegistrationNumber,
                invoiceQualified: payload.invoiceQualified,
                transitionalMeasureRate: payload.transitionalMeasureRate,
                transactionDescription: payload.transactionDescription,
                memo: payload.memo,
                businessAllocationRate: payload.businessAllocationRate,
                originalAmountIncludingTax: payload.originalAmountIncludingTax,
                relatedFixedAssetId: payload.relatedFixedAssetId,
                receiptImageHash: payload.receiptImageHash,
                sourceType: sourceType,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt,
                syncId: payload.syncId,
                isVoided: payload.isVoided || payload.deletedAt != nil
            )
            context.insert(entry)
        }
        try context.save()
    }

    private func update(_ entry: JournalEntry, from payload: JournalEntryPayload) {
        entry.entryNumber = payload.entryNumber
        entry.fiscalYear = payload.fiscalYear
        entry.transactionDate = payload.transactionDate
        entry.inputDate = payload.inputDate
        entry.isLateEntry = payload.isLateEntry
        entry.debitAccountCode = payload.debitAccountCode
        entry.creditAccountCode = payload.creditAccountCode
        entry.amountIncludingTax = payload.amountIncludingTax
        entry.amountExcludingTax = payload.amountExcludingTax
        entry.consumptionTax = payload.consumptionTax
        entry.taxCategoryRaw = payload.taxCategoryRaw
        entry.priceEntryModeRaw = payload.priceEntryModeRaw
        entry.paymentMethodRaw = payload.paymentMethodRaw
        entry.counterpartyName = payload.counterpartyName
        entry.invoiceRegistrationNumber = payload.invoiceRegistrationNumber
        entry.invoiceQualified = payload.invoiceQualified
        entry.transitionalMeasureRate = payload.transitionalMeasureRate
        entry.transactionDescription = payload.transactionDescription
        entry.memo = payload.memo
        entry.businessAllocationRate = payload.businessAllocationRate
        entry.originalAmountIncludingTax = payload.originalAmountIncludingTax
        entry.relatedFixedAssetId = payload.relatedFixedAssetId
        entry.receiptImageHash = payload.receiptImageHash
        entry.sourceTypeRaw = payload.sourceTypeRaw
        entry.updatedAt = payload.updatedAt
        entry.isVoided = payload.isVoided || payload.deletedAt != nil
    }

    private func decodeEnums(
        _ payload: FixedAssetPayload
    ) throws -> (depreciationMethod: DepreciationMethod, treatment: AssetTreatment) {
        guard let depreciationMethod = DepreciationMethod(rawValue: payload.depreciationMethodRaw) else {
            throw MergeError.unknownEnumValue(entity: "FixedAsset", field: "depreciationMethod", rawValue: payload.depreciationMethodRaw)
        }
        guard let treatment = AssetTreatment(rawValue: payload.treatmentRaw) else {
            throw MergeError.unknownEnumValue(entity: "FixedAsset", field: "treatment", rawValue: payload.treatmentRaw)
        }
        return (depreciationMethod, treatment)
    }

    private func applyFixedAsset(_ payload: FixedAssetPayload) throws {
        let syncId = payload.syncId
        let descriptor = FetchDescriptor<FixedAsset>(predicate: #Predicate { $0.syncId == syncId })
        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= payload.updatedAt else { return }
            _ = try decodeEnums(payload)
            update(existing, from: payload)
        } else if payload.deletedAt == nil {
            let (depreciationMethod, treatment) = try decodeEnums(payload)
            let asset = FixedAsset(
                assetName: payload.assetName,
                assetCategoryCode: payload.assetCategoryCode,
                acquisitionDate: payload.acquisitionDate,
                serviceStartDate: payload.serviceStartDate,
                acquisitionAmount: payload.acquisitionAmount,
                usefulLifeYears: payload.usefulLifeYears,
                depreciationMethod: depreciationMethod,
                treatment: treatment,
                businessAllocationRate: payload.businessAllocationRate,
                acquisitionJournalEntryId: payload.acquisitionJournalEntryId,
                accumulatedDepreciation: payload.accumulatedDepreciation,
                bookValue: payload.bookValue,
                disposalDate: payload.disposalDate,
                disposalAmount: payload.disposalAmount,
                syncId: payload.syncId,
                updatedAt: payload.updatedAt,
                deletedAt: payload.deletedAt
            )
            context.insert(asset)
        }
        try context.save()
    }

    private func update(_ asset: FixedAsset, from payload: FixedAssetPayload) {
        asset.assetName = payload.assetName
        asset.assetCategoryCode = payload.assetCategoryCode
        asset.acquisitionDate = payload.acquisitionDate
        asset.serviceStartDate = payload.serviceStartDate
        asset.acquisitionAmount = payload.acquisitionAmount
        asset.usefulLifeYears = payload.usefulLifeYears
        asset.depreciationMethodRaw = payload.depreciationMethodRaw
        asset.treatmentRaw = payload.treatmentRaw
        asset.businessAllocationRate = payload.businessAllocationRate
        asset.acquisitionJournalEntryId = payload.acquisitionJournalEntryId
        asset.accumulatedDepreciation = payload.accumulatedDepreciation
        asset.bookValue = payload.bookValue
        asset.disposalDate = payload.disposalDate
        asset.disposalAmount = payload.disposalAmount
        asset.updatedAt = payload.updatedAt
        asset.deletedAt = payload.deletedAt
    }

    private func applyOpeningBalance(_ payload: OpeningBalancePayload) throws {
        // Match on syncId only: syncId is derived deterministically from (fiscalYear, accountCode),
        // so every device agrees on it. Never rewrite an existing row's identity (that would orphan
        // a server row); the natural key is already encoded in the shared syncId.
        let syncId = payload.syncId
        let descriptor = FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.syncId == syncId }
        )
        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= payload.updatedAt else { return }
            existing.fiscalYear = payload.fiscalYear
            existing.accountCode = payload.accountCode
            existing.amount = payload.amount
            existing.isAutoRolled = payload.isAutoRolled
            existing.updatedAt = payload.updatedAt
            existing.deletedAt = payload.deletedAt
        } else if payload.deletedAt == nil {
            context.insert(OpeningBalance(
                fiscalYear: payload.fiscalYear,
                accountCode: payload.accountCode,
                amount: payload.amount,
                isAutoRolled: payload.isAutoRolled,
                syncId: payload.syncId,
                updatedAt: payload.updatedAt,
                deletedAt: payload.deletedAt
            ))
        }
        try context.save()
    }

    private func applyFiscalYearClosure(_ payload: FiscalYearClosurePayload) throws {
        // syncId is deterministic from fiscalYear, so all devices agree; match on it alone and
        // never rewrite identity. (fiscalYear is also @Attribute(.unique) locally.)
        let syncId = payload.syncId
        let descriptor = FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.syncId == syncId }
        )
        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= payload.updatedAt else { return }
            existing.fiscalYear = payload.fiscalYear
            existing.closedAt = payload.closedAt
            existing.netIncomeAtClosing = payload.netIncomeAtClosing
            existing.closedByDeviceId = payload.closedByDeviceId
            existing.updatedAt = payload.updatedAt
            existing.deletedAt = payload.deletedAt
        } else if payload.deletedAt == nil {
            context.insert(FiscalYearClosure(
                fiscalYear: payload.fiscalYear,
                closedAt: payload.closedAt,
                netIncomeAtClosing: payload.netIncomeAtClosing,
                closedByDeviceId: payload.closedByDeviceId,
                syncId: payload.syncId,
                updatedAt: payload.updatedAt,
                deletedAt: payload.deletedAt
            ))
        }
        try context.save()
    }
}
