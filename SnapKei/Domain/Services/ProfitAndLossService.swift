import Foundation

public struct PLSummary: Equatable, Sendable {
    public let revenueByCode: [String: Int]
    public let expenseByCode: [String: Int]

    public var revenueTotal: Int { revenueByCode.values.reduce(0, +) }
    public var expenseTotal: Int { expenseByCode.values.reduce(0, +) }
    public var netIncome: Int { revenueTotal - expenseTotal }
}

public enum ProfitAndLossService {
    public static func summary(entries: [JournalEntry], accounts: [Account]) -> PLSummary {
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var revenueByCode: [String: Int] = [:]
        var expenseByCode: [String: Int] = [:]

        for entry in entries where !entry.isVoided {
            if accountByCode[entry.debitAccountCode]?.accountType == .expense {
                expenseByCode[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            }
            if accountByCode[entry.creditAccountCode]?.accountType == .revenue {
                revenueByCode[entry.creditAccountCode, default: 0] += entry.amountIncludingTax
            }
            if accountByCode[entry.debitAccountCode]?.accountType == .revenue {
                revenueByCode[entry.debitAccountCode, default: 0] -= entry.amountIncludingTax
            }
            if accountByCode[entry.creditAccountCode]?.accountType == .expense {
                expenseByCode[entry.creditAccountCode, default: 0] -= entry.amountIncludingTax
            }
        }

        return PLSummary(revenueByCode: revenueByCode, expenseByCode: expenseByCode)
    }
}
