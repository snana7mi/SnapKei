import Foundation
import SwiftData

/// 固定資産の登記・処分・削除。仕訳は ExpenseRepository 経由（採番・監査ログ・同期通知込み）。
@MainActor
public final class FixedAssetService {
    public struct RegistrationInput {
        public var name: String
        public var categoryCode: String
        public var acquisitionDate: Date
        public var serviceStartDate: Date
        public var acquisitionAmount: Int
        public var usefulLifeYears: Int
        public var treatment: AssetTreatment
        public var businessAllocationRate: Double
        public var paymentMethod: PaymentMethod
        public var taxCategory: TaxCategory
        public var isCarriedOver: Bool
        public var accumulatedDepreciation: Int

        public init(
            name: String,
            categoryCode: String,
            acquisitionDate: Date,
            serviceStartDate: Date,
            acquisitionAmount: Int,
            usefulLifeYears: Int,
            treatment: AssetTreatment,
            businessAllocationRate: Double,
            paymentMethod: PaymentMethod,
            taxCategory: TaxCategory,
            isCarriedOver: Bool,
            accumulatedDepreciation: Int
        ) {
            self.name = name
            self.categoryCode = categoryCode
            self.acquisitionDate = acquisitionDate
            self.serviceStartDate = serviceStartDate
            self.acquisitionAmount = acquisitionAmount
            self.usefulLifeYears = usefulLifeYears
            self.treatment = treatment
            self.businessAllocationRate = businessAllocationRate
            self.paymentMethod = paymentMethod
            self.taxCategory = taxCategory
            self.isCarriedOver = isCarriedOver
            self.accumulatedDepreciation = accumulatedDepreciation
        }
    }

    nonisolated public enum ServiceError: Error, Equatable, LocalizedError {
        case validationFailed([FixedAssetRules.Issue])
        case alreadyDisposed
        case hasDepreciationEntries
        case invalidDisposalDate
        case smallAmountAnnualCapExceeded

        public var errorDescription: String? {
            switch self {
            case .validationFailed: "入力内容を確認してください。"
            case .alreadyDisposed: "この資産は処分済みです。"
            case .hasDepreciationEntries: "償却仕訳が存在する資産は削除できません。処分を記録してください。"
            case .invalidDisposalDate: "処分日は取得日以降の日付を指定してください。"
            case .smallAmountAnnualCapExceeded: "少額減価償却資産の特例は年間合計300万円までです。定額法または一括償却を選択してください。"
            }
        }
    }

    private let context: ModelContext
    private let deviceId: String
    private let repository: SwiftDataExpenseRepository

    public init(context: ModelContext, deviceId: String) {
        self.context = context
        self.deviceId = deviceId
        self.repository = SwiftDataExpenseRepository(context: context, deviceId: deviceId)
    }

    @discardableResult
    public func register(_ input: RegistrationInput) throws -> FixedAsset {
        let issues = FixedAssetRules.validate(
            name: input.name,
            amount: input.acquisitionAmount,
            usefulLifeYears: input.usefulLifeYears,
            allocationRate: input.businessAllocationRate,
            treatment: input.treatment,
            acquisitionDate: input.acquisitionDate,
            isCarriedOver: input.isCarriedOver,
            accumulatedDepreciation: input.accumulatedDepreciation
        )
        guard issues.isEmpty else { throw ServiceError.validationFailed(issues) }

        let accumulated = input.isCarriedOver ? input.accumulatedDepreciation : 0
        let asset = FixedAsset(
            assetName: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            assetCategoryCode: input.categoryCode,
            acquisitionDate: input.acquisitionDate,
            serviceStartDate: input.serviceStartDate,
            acquisitionAmount: input.acquisitionAmount,
            usefulLifeYears: input.usefulLifeYears,
            treatment: input.treatment,
            businessAllocationRate: input.businessAllocationRate,
            accumulatedDepreciation: accumulated,
            bookValue: input.acquisitionAmount - accumulated
        )

        if input.isCarriedOver {
            // 引継ぎ: 仕訳なしで台帳にのみ載せる（B/S 表示は期首残高に依存）。
            context.insert(asset)
            try context.save()
            SyncChangeNotifier.shared.notify()
            return asset
        }

        // 仕訳を伴う登記の前提条件はすべて先に検査し、途中失敗による部分コミットを防ぐ。
        let acquisitionYear = FiscalYearRule.year(for: input.acquisitionDate)
        try ensureFiscalYearOpen(acquisitionYear)
        if input.treatment == .smallAmountFullExpense {
            let serviceYear = FiscalYearRule.year(for: input.serviceStartDate)
            if serviceYear != acquisitionYear {
                try ensureFiscalYearOpen(serviceYear)
            }
            try ensureSmallAmountAnnualCap(input)
        }
        context.insert(asset)
        do {
            let split = TaxSplit.split(amount: input.acquisitionAmount, mode: .taxIncluded, rate: input.taxCategory.taxRate)
            let acquisition = JournalEntry(
                entryNumber: 0,
                fiscalYear: FiscalYearRule.year(for: input.acquisitionDate),
                transactionDate: input.acquisitionDate,
                debitAccountCode: AccountCode.equipment,
                creditAccountCode: input.paymentMethod.defaultCreditAccountCode ?? AccountCode.ownerLoan,
                amountIncludingTax: split.total,
                amountExcludingTax: split.excludingTax,
                consumptionTax: split.tax,
                taxCategory: input.taxCategory,
                priceEntryMode: .taxIncluded,
                paymentMethod: input.paymentMethod,
                counterpartyName: asset.assetName,
                transactionDescription: "\(asset.assetName) 取得",
                relatedFixedAssetId: asset.syncId,
                sourceType: .manual
            )
            try repository.create(acquisition, reason: "固定資産登記")
            asset.acquisitionJournalEntryId = acquisition.id

            if input.treatment == .smallAmountFullExpense {
                try postImmediateExpensing(for: asset)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
        return asset
    }

    /// 少額特例 = 即時償却。DepreciationService は本区分に 0 を返すため登記時に全額を償却計上する。
    /// 経費化は「事業の用に供した年」= serviceStartDate の年度に入れる。
    private func postImmediateExpensing(for asset: FixedAsset) throws {
        let full = asset.acquisitionAmount
        let deductible = Int((Double(full) * asset.businessAllocationRate).rounded(.down))
        let ownerPortion = full - deductible
        if deductible > 0 {
            try repository.create(depreciationEntry(
                asset: asset, date: asset.serviceStartDate,
                debit: AccountCode.depreciationExpense, amount: deductible,
                description: "\(asset.assetName) 即時償却（少額特例）"
            ), reason: "少額特例即時償却")
        }
        if ownerPortion > 0 {
            try repository.create(depreciationEntry(
                asset: asset, date: asset.serviceStartDate,
                debit: AccountCode.ownerDraw, amount: ownerPortion,
                description: "\(asset.assetName) 即時償却（家事分）"
            ), reason: "少額特例即時償却")
        }
        asset.accumulatedDepreciation = full
        asset.bookValue = 0
    }

    /// 少額特例の年間合計は取得価額 300 万円が上限（措置法28条の2）。供用年ベースで集計する。
    private func ensureSmallAmountAnnualCap(_ input: RegistrationInput) throws {
        let serviceYear = FiscalYearRule.year(for: input.serviceStartDate)
        let raw = AssetTreatment.smallAmountFullExpense.rawValue
        let existing = try context.fetch(FetchDescriptor<FixedAsset>(
            predicate: #Predicate { $0.treatmentRaw == raw && $0.deletedAt == nil }
        ))
        let usedThisYear = existing
            .filter { FiscalYearRule.year(for: $0.serviceStartDate) == serviceYear }
            .reduce(0) { $0 + $1.acquisitionAmount }
        if usedThisYear + input.acquisitionAmount > ComplianceConstants.smallDepreciableAnnualCap {
            throw ServiceError.smallAmountAnnualCapExceeded
        }
    }

    private func depreciationEntry(asset: FixedAsset, date: Date, debit: String, amount: Int, description: String) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: date),
            transactionDate: date,
            debitAccountCode: debit,
            creditAccountCode: AccountCode.accumulatedDepreciation,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: asset.assetName,
            transactionDescription: description,
            relatedFixedAssetId: asset.syncId,
            sourceType: .depreciation
        )
    }

    /// 処分（売却/除却）。個人事業主の事業用資産売却は譲渡所得（事業損益外）のため
    /// 帳簿からは事業主貸で転出する。売却代金は台帳に記録のみ。
    /// 処分年度以降の償却は DepreciationService 側で停止する（転出と二重計上しない）。
    /// 一括償却資産は処分後も3年均等償却を継続する（令139条）ため転出仕訳を生成しない。
    public func dispose(_ asset: FixedAsset, on disposalDate: Date, proceeds: Int?) throws {
        guard asset.disposalDate == nil else { throw ServiceError.alreadyDisposed }
        guard disposalDate >= asset.acquisitionDate else { throw ServiceError.invalidDisposalDate }
        try ensureFiscalYearOpen(FiscalYearRule.year(for: disposalDate))

        if asset.treatment == .lumpSumDepreciation {
            asset.disposalDate = disposalDate
            asset.disposalAmount = proceeds
            asset.updatedAt = Date()
            try context.save()
            SyncChangeNotifier.shared.notify()
            return
        }

        do {
            if asset.accumulatedDepreciation > 0 {
                try repository.create(disposalEntry(
                    asset: asset, date: disposalDate,
                    debit: AccountCode.accumulatedDepreciation,
                    amount: asset.accumulatedDepreciation,
                    description: "\(asset.assetName) 処分（償却累計の振替）"
                ), reason: "固定資産処分")
            }
            if asset.bookValue > 0 {
                try repository.create(disposalEntry(
                    asset: asset, date: disposalDate,
                    debit: AccountCode.ownerDraw,
                    amount: asset.bookValue,
                    description: "\(asset.assetName) 処分（簿価の事業主貸転出）"
                ), reason: "固定資産処分")
            }
            asset.disposalDate = disposalDate
            asset.disposalAmount = proceeds
            asset.bookValue = 0
            asset.updatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
    }

    private func disposalEntry(asset: FixedAsset, date: Date, debit: String, amount: Int, description: String) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: date),
            transactionDate: date,
            debitAccountCode: debit,
            creditAccountCode: AccountCode.equipment,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: asset.assetName,
            transactionDescription: description,
            relatedFixedAssetId: asset.syncId,
            sourceType: .manual
        )
    }

    /// 償却仕訳が無い資産のみ削除可（誤登記の取り消し）。取得仕訳は自動 void。
    public func canDelete(_ asset: FixedAsset) -> Bool {
        ((try? depreciationEntryCount(for: asset)) ?? 1) == 0
    }

    public func delete(_ asset: FixedAsset) throws {
        guard try depreciationEntryCount(for: asset) == 0 else {
            throw ServiceError.hasDepreciationEntries
        }
        do {
            if let entryId = asset.acquisitionJournalEntryId {
                let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == entryId })
                if let acquisition = try context.fetch(descriptor).first, !acquisition.isVoided {
                    try repository.void(acquisition, reason: "資産登記の取消")
                }
            }
            asset.deletedAt = Date()
            asset.updatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
    }

    private func depreciationEntryCount(for asset: FixedAsset) throws -> Int {
        let assetId = asset.syncId
        let raw = RecordSource.depreciation.rawValue
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.relatedFixedAssetId == assetId && $0.sourceTypeRaw == raw && !$0.isVoided }
        )
        return try context.fetchCount(descriptor)
    }

    private func ensureFiscalYearOpen(_ fiscalYear: Int) throws {
        let descriptor = FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        )
        if try context.fetchCount(descriptor) > 0 {
            throw RepositoryError.fiscalYearClosed(fiscalYear)
        }
    }
}
