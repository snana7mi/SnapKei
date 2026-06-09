import Foundation

public struct BalanceSheetLine: Identifiable, Equatable, Sendable {
    public var id: String { accountCode }
    public let accountCode: String
    public let accountName: String
    public let opening: Int
    public let closing: Int
}

public struct BalanceSheetReport: Equatable, Sendable {
    public let fiscalYear: Int
    public let assetLines: [BalanceSheetLine]
    public let liabilityLines: [BalanceSheetLine]
    public let ownerDrawClosing: Int
    public let ownerLoanClosing: Int
    public let capitalOpening: Int
    public let netIncome: Int
    public let assetTotal: Int
    public let liabilityEquityTotal: Int
    public let openingImbalance: Int
    public var isBalanced: Bool { assetTotal == liabilityEquityTotal && openingImbalance == 0 }
}

public enum BalanceSheetService {
    public static func report(
        fiscalYear: Int,
        entries: [JournalEntry],
        openingBalances: [String: Int],
        accounts: [Account]
    ) -> BalanceSheetReport {
        let active = entries.filter { !$0.isVoided && $0.fiscalYear == fiscalYear }
        var movement: [String: Int] = [:]
        for entry in active {
            movement[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            movement[entry.creditAccountCode, default: 0] -= entry.amountIncludingTax
        }

        func closing(_ code: String) -> Int {
            (openingBalances[code] ?? 0) + (movement[code] ?? 0)
        }

        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        let pl = ProfitAndLossService.summary(entries: active, accounts: accounts)
        let relevantCodes = Set(openingBalances.keys).union(movement.keys)
        var assetLines: [BalanceSheetLine] = []
        var liabilityLines: [BalanceSheetLine] = []

        for code in relevantCodes.sorted() {
            guard let account = accountByCode[code] else { continue }
            let open = openingBalances[code] ?? 0
            let close = closing(code)
            if open == 0 && close == 0 { continue }
            switch account.accountType {
            case .asset:
                assetLines.append(BalanceSheetLine(accountCode: code, accountName: account.nameJa, opening: open, closing: close))
            case .liability:
                liabilityLines.append(BalanceSheetLine(accountCode: code, accountName: account.nameJa, opening: -open, closing: -close))
            case .equity, .revenue, .expense:
                break
            }
        }

        let ownerDrawClosing = closing(AccountCode.ownerDraw)
        let ownerLoanClosing = -closing(AccountCode.ownerLoan)
        let capitalOpening = -closing(AccountCode.capital)
        let assetTotal = assetLines.reduce(0) { $0 + $1.closing } + ownerDrawClosing
        let liabilityEquityTotal = liabilityLines.reduce(0) { $0 + $1.closing }
            + ownerLoanClosing + capitalOpening + pl.netIncome

        return BalanceSheetReport(
            fiscalYear: fiscalYear,
            assetLines: assetLines,
            liabilityLines: liabilityLines,
            ownerDrawClosing: ownerDrawClosing,
            ownerLoanClosing: ownerLoanClosing,
            capitalOpening: capitalOpening,
            netIncome: pl.netIncome,
            assetTotal: assetTotal,
            liabilityEquityTotal: liabilityEquityTotal,
            openingImbalance: openingBalances.values.reduce(0, +)
        )
    }
}
