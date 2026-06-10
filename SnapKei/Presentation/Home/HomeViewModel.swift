import Foundation
import Observation

public struct ControlRouteStatus: Sendable, Equatable {
    public var hasFiledOptimalBookNotification: Bool
    public var willUseEtax: Bool
    public var doubleEntryBookkeeping: Bool
    public var amendmentHistoryEnabled: Bool
    public var searchableLedger: Bool

    public var estimatedDeduction: Int {
        if doubleEntryBookkeeping && amendmentHistoryEnabled && searchableLedger && (hasFiledOptimalBookNotification || willUseEtax) {
            return 650_000
        }
        if doubleEntryBookkeeping && amendmentHistoryEnabled && searchableLedger {
            return 550_000
        }
        if doubleEntryBookkeeping {
            return 100_000
        }
        return 0
    }

    private enum Keys {
        static let filed = "controlRoute.hasFiledOptimalBookNotification"
        static let etax = "controlRoute.willUseEtax"
    }

    public static func load(
        defaults: UserDefaults = .standard,
        hasEntries: Bool,
        hasAuditLog: Bool
    ) -> ControlRouteStatus {
        ControlRouteStatus(
            hasFiledOptimalBookNotification: defaults.bool(forKey: Keys.filed),
            willUseEtax: defaults.bool(forKey: Keys.etax),
            doubleEntryBookkeeping: hasEntries,
            amendmentHistoryEnabled: hasAuditLog,
            searchableLedger: hasEntries
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(hasFiledOptimalBookNotification, forKey: Keys.filed)
        defaults.set(willUseEtax, forKey: Keys.etax)
    }
}

@MainActor
@Observable
public final class HomeViewModel {
    public struct MonthlySummary: Sendable, Equatable {
        public let entryCount: Int
        public let incomeTotal: Int
        public let expenseTotal: Int
        /// 支出仕訳の消費税（仕入税額）のみ。収入側の仮受消費税とは合算しない。
        public let expenseConsumptionTax: Int
    }

    public struct AccountTotal: Identifiable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let amount: Int
    }

    private let repository: ExpenseRepository

    public init(repository: ExpenseRepository) {
        self.repository = repository
    }

    public func controlRouteStatus(defaults: UserDefaults = .standard) throws -> ControlRouteStatus {
        let entries = try repository.search(criteria: ExpenseSearchCriteria())
        let auditLogCount = try repository.auditLogCount()
        return ControlRouteStatus.load(
            defaults: defaults,
            hasEntries: !entries.isEmpty,
            hasAuditLog: auditLogCount > 0
        )
    }

    /// 仕訳を 収入/支出/振替 に分類して集計する（手動仕訳の導入で支出以外の仕訳が存在する）。
    /// 振替は資金移動なので合計に含めない。
    public func monthlySummary(
        year: Int,
        month: Int,
        accountTypes: (String) -> AccountType?
    ) throws -> MonthlySummary {
        let entries = try entriesInMonth(year: year, month: month)
        var income = 0
        var expense = 0
        var expenseTax = 0
        for entry in entries {
            let debitType = accountTypes(entry.debitAccountCode)
            let creditType = accountTypes(entry.creditAccountCode)
            switch ManualEntryRules.kind(debitType: debitType, creditType: creditType) {
            case .income:
                income += creditType == .revenue ? entry.amountIncludingTax : -entry.amountIncludingTax
            case .expense:
                let sign = debitType == .expense ? 1 : -1
                expense += sign * entry.amountIncludingTax
                expenseTax += sign * entry.consumptionTax
            case .transfer:
                break
            }
        }
        return MonthlySummary(
            entryCount: entries.count,
            incomeTotal: income,
            expenseTotal: expense,
            expenseConsumptionTax: expenseTax
        )
    }

    /// 科目別チャートは費用科目のみ（収入・振替の借方科目を「支出カテゴリ」として描かない）。
    public func byDebitAccount(
        year: Int,
        month: Int,
        accountLookup: (String) -> String,
        accountTypes: (String) -> AccountType?
    ) throws -> [AccountTotal] {
        var totals: [String: Int] = [:]
        for entry in try entriesInMonth(year: year, month: month) {
            if accountTypes(entry.debitAccountCode) == .expense {
                totals[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            }
            if accountTypes(entry.creditAccountCode) == .expense {
                totals[entry.creditAccountCode, default: 0] -= entry.amountIncludingTax
            }
        }
        return totals
            .filter { $0.value > 0 }
            .map { AccountTotal(id: $0.key, name: accountLookup($0.key), amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// スキャナ保存期限の警告はレシート画像のある仕訳にのみ意味がある。
    /// 手動仕訳（書類なし）を期限切れ扱いにしない。
    public func overdueEntries(today: Date = Date()) throws -> [JournalEntry] {
        try repository.search(criteria: ExpenseSearchCriteria()).filter {
            $0.receiptImagePath != nil &&
                ComplianceService.daysUntilScanDeadline(receiptDate: $0.transactionDate, today: today) < 14
        }
    }

    public func recentEntries(limit: Int = 5) throws -> [JournalEntry] {
        Array(try repository.search(criteria: ExpenseSearchCriteria()).prefix(limit))
    }

    private func entriesInMonth(year: Int, month: Int) throws -> [JournalEntry] {
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let to = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: from)!
        return try repository.search(criteria: ExpenseSearchCriteria(dateFrom: from, dateTo: to))
    }
}
