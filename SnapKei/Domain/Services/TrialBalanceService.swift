import Foundation

public struct TrialBalanceRow: Identifiable, Equatable, Sendable {
    public var id: String { accountCode }
    public let accountCode: String
    public let accountName: String
    public let openingBalance: Int
    public let debitTotal: Int
    public let creditTotal: Int
    public let closingBalance: Int
}

public struct TrialBalanceReport: Equatable, Sendable {
    public let rows: [TrialBalanceRow]
    public let totalDebit: Int
    public let totalCredit: Int
    public let openingImbalance: Int
    public var isBalanced: Bool { totalDebit == totalCredit && openingImbalance == 0 }
}

public enum TrialBalanceService {
    public static func report(
        fiscalYear: Int,
        entries: [JournalEntry],
        openingBalances: [String: Int],
        accounts: [Account]
    ) -> TrialBalanceReport {
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var debitTotals: [String: Int] = [:]
        var creditTotals: [String: Int] = [:]

        for entry in entries where !entry.isVoided && entry.fiscalYear == fiscalYear {
            debitTotals[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            creditTotals[entry.creditAccountCode, default: 0] += entry.amountIncludingTax
        }

        let codes = Set(debitTotals.keys).union(creditTotals.keys).union(openingBalances.keys)
        let rows = codes.sorted().map { code in
            let opening = openingBalances[code] ?? 0
            let debit = debitTotals[code] ?? 0
            let credit = creditTotals[code] ?? 0
            return TrialBalanceRow(
                accountCode: code,
                accountName: accountByCode[code]?.nameJa ?? code,
                openingBalance: opening,
                debitTotal: debit,
                creditTotal: credit,
                closingBalance: opening + debit - credit
            )
        }

        return TrialBalanceReport(
            rows: rows,
            totalDebit: rows.reduce(0) { $0 + $1.debitTotal },
            totalCredit: rows.reduce(0) { $0 + $1.creditTotal },
            openingImbalance: openingBalances.values.reduce(0, +)
        )
    }
}
