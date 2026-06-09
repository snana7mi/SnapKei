import Foundation
import SwiftData

@MainActor
public final class OpeningBalanceStore {
    private let context: ModelContext
    private let notifier: SyncChangeNotifier

    public init(context: ModelContext, notifier: SyncChangeNotifier = .shared) {
        self.context = context
        self.notifier = notifier
    }

    public func balances(fiscalYear: Int) throws -> [String: Int] {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        ))
        return Dictionary(rows.map { ($0.accountCode, $0.amount) }, uniquingKeysWith: { first, _ in first })
    }

    public func set(fiscalYear: Int, accountCode: String, amount: Int, isAutoRolled: Bool = false) throws {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate {
                $0.fiscalYear == fiscalYear && $0.accountCode == accountCode
            }
        ))
        let now = Date()
        if let existing = rows.first {
            if amount == 0 {
                existing.deletedAt = now
                existing.updatedAt = now
            } else {
                existing.amount = amount
                existing.isAutoRolled = isAutoRolled
                existing.deletedAt = nil
                existing.updatedAt = now
            }
        } else if amount != 0 {
            context.insert(OpeningBalance(
                fiscalYear: fiscalYear,
                accountCode: accountCode,
                amount: amount,
                isAutoRolled: isAutoRolled,
                syncId: OpeningBalance.deterministicSyncId(fiscalYear: fiscalYear, accountCode: accountCode)
            ))
        }
        try context.save()
        notifier.notify()
    }

    public func adjustCapitalToBalance(fiscalYear: Int) throws {
        let all = try balances(fiscalYear: fiscalYear)
        let nonCapitalSum = all.filter { $0.key != AccountCode.capital }.values.reduce(0, +)
        try set(fiscalYear: fiscalYear, accountCode: AccountCode.capital, amount: -nonCapitalSum)
    }

    public func deleteAutoRolled(fiscalYear: Int) throws {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.isAutoRolled && $0.deletedAt == nil }
        ))
        let now = Date()
        for row in rows {
            row.deletedAt = now
            row.updatedAt = now
        }
        try context.save()
        notifier.notify()
    }
}
