import Foundation
import Testing
@testable import SnapKei

@Suite("BalanceSheetService")
struct BalanceSheetServiceTests {

    private func account(_ code: String, _ name: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: name, nameZh: name, accountType: type)
    }

    private var accounts: [Account] {
        [
            account("1110", "現金", .asset),
            account("1610", "工具器具備品", .asset),
            account("1710", "減価償却累計額", .asset),
            account("3110", "元入金", .equity),
            account("3210", "事業主借", .equity),
            account("3220", "事業主貸", .equity),
            account("4110", "売上高", .revenue),
            account("5110", "通信費", .expense),
            account("5230", "減価償却費", .expense),
            account("5290", "雑費", .expense),
        ]
    }

    private func entry(number: Int, debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number,
            fiscalYear: 2026,
            transactionDate: Date(),
            debitAccountCode: debit,
            creditAccountCode: credit,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: "x",
            transactionDescription: "y",
            sourceType: .manual,
            isVoided: voided
        )
    }

    @Test func report_workedExample_balances() {
        let entries = [
            entry(number: 1, debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, debit: "5290", credit: "1110", amount: 5_000, voided: true),
            entry(number: 5, debit: "5230", credit: "1710", amount: 24_000),
            entry(number: 6, debit: "3220", credit: "1710", amount: 6_000),
        ]
        let openings = ["1110": 100_000, "3110": -100_000]

        let report = BalanceSheetService.report(fiscalYear: 2026, entries: entries, openingBalances: openings, accounts: accounts)

        #expect(report.assetLines.first { $0.accountCode == "1110" }?.closing == 210_000)
        #expect(report.assetLines.first { $0.accountCode == "1610" }?.closing == 240_000)
        #expect(report.assetLines.first { $0.accountCode == "1710" }?.closing == -30_000)
        #expect(report.ownerDrawClosing == 6_000)
        #expect(report.ownerLoanClosing == 251_000)
        #expect(report.capitalClosing == 100_000)
        #expect(report.netIncome == 75_000)
        #expect(report.assetTotal == 426_000)
        #expect(report.liabilityEquityTotal == 426_000)
        #expect(report.isBalanced)
    }

    @Test func report_foldsUnknownEquityAccount_intoTotal_andStaysBalanced() {
        var accts = accounts
        accts.append(account("3310", "準備金", .equity))
        // ¥150,000 cash funded by ¥100,000 元入金 + ¥50,000 準備金 (a non-standard equity account).
        let openings = ["1110": 150_000, "3110": -100_000, "3310": -50_000]
        let report = BalanceSheetService.report(fiscalYear: 2026, entries: [], openingBalances: openings, accounts: accts)
        #expect(report.otherEquityClosing == 50_000)
        #expect(report.assetTotal == 150_000)
        #expect(report.liabilityEquityTotal == 150_000)
        #expect(report.isBalanced)
    }

    @Test func report_unbalancedOpening_notBalanced() {
        let report = BalanceSheetService.report(
            fiscalYear: 2026,
            entries: [],
            openingBalances: ["1110": 1_000],
            accounts: accounts
        )
        #expect(report.openingImbalance == 1_000)
        #expect(!report.isBalanced)
    }
}
