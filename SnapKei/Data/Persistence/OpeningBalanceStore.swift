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

    /// 生の行（isAutoRolled 含む）。UI が自動繰越バナーを出すために使う。
    public func rows(fiscalYear: Int) throws -> [OpeningBalance] {
        try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        ))
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
                guard existing.deletedAt == nil else { return } // 同値（削除済み）は no-op
                existing.deletedAt = now
                existing.updatedAt = now
            } else {
                // 同値書き込みは no-op（updatedAt を進めず同期の往復を増やさない）。
                guard existing.amount != amount
                    || existing.isAutoRolled != isAutoRolled
                    || existing.deletedAt != nil else { return }
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
        } else {
            return // 行なし & 0 → no-op
        }
        try context.save()
        notifier.notify()
    }

    /// 元入金は常に導出行（−Σ非元入金）。isAutoRolled: true で書くことで
    /// 再オープン時の deleteAutoRolled が孤児として残さない。
    public func adjustCapitalToBalance(fiscalYear: Int) throws {
        let all = try balances(fiscalYear: fiscalYear)
        let nonCapitalSum = all.filter { $0.key != AccountCode.capital }.values.reduce(0, +)
        try set(fiscalYear: fiscalYear, accountCode: AccountCode.capital, amount: -nonCapitalSum, isAutoRolled: true)
    }

    /// 年度の全行をソフト削除（再締めの全面書き直し用）。
    public func clear(fiscalYear: Int) throws {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        ))
        guard !rows.isEmpty else { return }
        let now = Date()
        for row in rows {
            row.deletedAt = now
            row.updatedAt = now
        }
        try context.save()
        notifier.notify()
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
