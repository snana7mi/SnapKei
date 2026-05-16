import Foundation
import Observation

public struct ControlRouteStatus: Sendable, Equatable {
    public var hasFiledOptimalBookNotification: Bool
    public var willUseEtax: Bool
    public var doubleEntryBookkeeping: Bool
    public var amendmentHistoryEnabled: Bool
    public var searchableLedger: Bool

    public var estimatedDeduction: Int {
        if doubleEntryBookkeeping && amendmentHistoryEnabled && searchableLedger && hasFiledOptimalBookNotification && willUseEtax {
            return 750_000
        }
        if doubleEntryBookkeeping && willUseEtax {
            return 650_000
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

    public static func load(defaults: UserDefaults = .standard, hasEntries: Bool) -> ControlRouteStatus {
        ControlRouteStatus(
            hasFiledOptimalBookNotification: defaults.bool(forKey: Keys.filed),
            willUseEtax: defaults.bool(forKey: Keys.etax),
            doubleEntryBookkeeping: hasEntries,
            amendmentHistoryEnabled: true,
            searchableLedger: true
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
        public let totalIncludingTax: Int
        public let totalConsumptionTax: Int
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
        return ControlRouteStatus.load(defaults: defaults, hasEntries: !entries.isEmpty)
    }

    public func monthlySummary(year: Int, month: Int) throws -> MonthlySummary {
        let entries = try entriesInMonth(year: year, month: month)
        return MonthlySummary(
            entryCount: entries.count,
            totalIncludingTax: entries.reduce(0) { $0 + $1.amountIncludingTax },
            totalConsumptionTax: entries.reduce(0) { $0 + $1.consumptionTax }
        )
    }

    public func byDebitAccount(year: Int, month: Int, accountLookup: (String) -> String) throws -> [AccountTotal] {
        let grouped = Dictionary(grouping: try entriesInMonth(year: year, month: month), by: \.debitAccountCode)
        return grouped.map { code, entries in
            AccountTotal(id: code, name: accountLookup(code), amount: entries.reduce(0) { $0 + $1.amountIncludingTax })
        }
        .sorted { $0.amount > $1.amount }
    }

    public func overdueEntries(today: Date = Date()) throws -> [JournalEntry] {
        try repository.search(criteria: ExpenseSearchCriteria()).filter {
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
