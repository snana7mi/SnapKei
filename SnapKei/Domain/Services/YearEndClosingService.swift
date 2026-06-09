import Foundation
import SwiftData

@MainActor
public final class YearEndClosingService {
    public enum ClosingError: Error, Equatable {
        case alreadyClosed(Int)
        case notClosed(Int)
        case missingReopenReason
    }

    private let context: ModelContext
    private let deviceId: String
    private let notifier: SyncChangeNotifier

    public init(context: ModelContext, deviceId: String, notifier: SyncChangeNotifier = .shared) {
        self.context = context
        self.deviceId = deviceId
        self.notifier = notifier
    }

    public func runDepreciation(fiscalYear: Int) throws {
        if try closure(for: fiscalYear) != nil {
            throw RepositoryError.fiscalYearClosed(fiscalYear)
        }
        let assets = try context.fetch(FetchDescriptor<FixedAsset>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        for asset in assets {
            let assetId = asset.syncId
            let existing = try context.fetch(FetchDescriptor<JournalEntry>(
                predicate: #Predicate {
                    $0.fiscalYear == fiscalYear
                    && $0.sourceTypeRaw == "depreciation"
                    && $0.relatedFixedAssetId == assetId
                    && !$0.isVoided
                }
            ))
            if !existing.isEmpty { continue }

            let amount = DepreciationService.annualAmount(for: asset, fiscalYear: fiscalYear)
            guard amount.full > 0 else { continue }
            let transactionDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: fiscalYear, month: 12, day: 31)) ?? Date()

            if amount.deductible > 0 {
                context.insert(depreciationEntry(
                    fiscalYear: fiscalYear,
                    transactionDate: transactionDate,
                    asset: asset,
                    debit: AccountCode.depreciationExpense,
                    amount: amount.deductible,
                    description: "\(asset.assetName) 減価償却"
                ))
            }
            if amount.ownerPortion > 0 {
                context.insert(depreciationEntry(
                    fiscalYear: fiscalYear,
                    transactionDate: transactionDate,
                    asset: asset,
                    debit: AccountCode.ownerDraw,
                    amount: amount.ownerPortion,
                    description: "\(asset.assetName) 減価償却（家事分）"
                ))
            }
            asset.accumulatedDepreciation += amount.full
            asset.bookValue = max(0, asset.bookValue - amount.full)
            asset.updatedAt = Date()
        }
        try context.save()
        notifier.notify()
    }

    public func close(fiscalYear: Int) throws {
        if try closure(for: fiscalYear) != nil {
            throw ClosingError.alreadyClosed(fiscalYear)
        }
        try runDepreciation(fiscalYear: fiscalYear)

        let entries = try entries(for: fiscalYear)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let openingStore = OpeningBalanceStore(context: context)
        let openings = try openingStore.balances(fiscalYear: fiscalYear)
        let pl = ProfitAndLossService.summary(entries: entries, accounts: accounts)

        if let tombstone = try anyClosure(for: fiscalYear) {
            tombstone.closedAt = Date()
            tombstone.netIncomeAtClosing = pl.netIncome
            tombstone.closedByDeviceId = deviceId
            tombstone.updatedAt = Date()
            tombstone.deletedAt = nil
        } else {
            context.insert(FiscalYearClosure(
                fiscalYear: fiscalYear,
                netIncomeAtClosing: pl.netIncome,
                closedByDeviceId: deviceId
            ))
        }

        try rollForward(
            fiscalYear: fiscalYear,
            entries: entries,
            openings: openings,
            accounts: accounts,
            store: openingStore
        )
        try context.save()
        notifier.notify()
    }

    public func reopen(fiscalYear: Int, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClosingError.missingReopenReason
        }
        guard let closure = try closure(for: fiscalYear) else {
            throw ClosingError.notClosed(fiscalYear)
        }
        let now = Date()
        closure.deletedAt = now
        closure.updatedAt = now
        try OpeningBalanceStore(context: context).deleteAutoRolled(fiscalYear: fiscalYear + 1)
        context.insert(SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .editEntry,
            targetEntryId: nil,
            beforeSnapshot: nil,
            afterSnapshot: nil,
            reason: reason
        ))
        try context.save()
        notifier.notify()
    }

    private func depreciationEntry(
        fiscalYear: Int,
        transactionDate: Date,
        asset: FixedAsset,
        debit: String,
        amount: Int,
        description: String
    ) -> JournalEntry {
        JournalEntry(
            entryNumber: (try? nextEntryNumber(fiscalYear: fiscalYear)) ?? 1,
            fiscalYear: fiscalYear,
            transactionDate: transactionDate,
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

    private func rollForward(
        fiscalYear: Int,
        entries: [JournalEntry],
        openings: [String: Int],
        accounts: [Account],
        store: OpeningBalanceStore
    ) throws {
        try store.deleteAutoRolled(fiscalYear: fiscalYear + 1)
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var closing = openings
        for entry in entries where !entry.isVoided {
            closing[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            closing[entry.creditAccountCode, default: 0] -= entry.amountIncludingTax
        }

        var rolled: [String: Int] = [:]
        for (code, amount) in closing {
            guard let type = accountByCode[code]?.accountType else { continue }
            if type == .asset || type == .liability || type == .equity {
                rolled[code] = amount
            }
        }

        let netIncome = ProfitAndLossService.summary(entries: entries, accounts: accounts).netIncome
        rolled[AccountCode.capital, default: 0] -= netIncome
        rolled[AccountCode.ownerLoan] = nil
        rolled[AccountCode.ownerDraw] = nil

        for (code, amount) in rolled where amount != 0 {
            try store.set(fiscalYear: fiscalYear + 1, accountCode: code, amount: amount, isAutoRolled: true)
        }
        try store.adjustCapitalToBalance(fiscalYear: fiscalYear + 1)
    }

    private func entries(for fiscalYear: Int) throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        ))
    }

    private func nextEntryNumber(fiscalYear: Int) throws -> Int {
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.fiscalYear == fiscalYear })
        descriptor.sortBy = [SortDescriptor(\.entryNumber, order: .reverse)]
        descriptor.fetchLimit = 1
        return ((try context.fetch(descriptor).first?.entryNumber) ?? 0) + 1
    }

    private func closure(for fiscalYear: Int) throws -> FiscalYearClosure? {
        try context.fetch(FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        )).first
    }

    private func anyClosure(for fiscalYear: Int) throws -> FiscalYearClosure? {
        try context.fetch(FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )).first
    }
}
