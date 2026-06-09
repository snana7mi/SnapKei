import Foundation
import Testing
@testable import SnapKei

@Suite("TrialBalanceService")
struct TrialBalanceServiceTests {

    private func account(_ code: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: "科目\(code)", nameZh: code, accountType: type)
    }

    private func entry(number: Int, debit: String, credit: String, amount: Int, voided: Bool = false, fiscalYear: Int = 2026) -> JournalEntry {
        JournalEntry(
            entryNumber: number,
            fiscalYear: fiscalYear,
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

    @Test func report_balancedTotals_andClosingBalances() {
        let accounts = [
            account("1110", .asset), account("1610", .asset),
            account("3210", .equity), account("3110", .equity),
            account("4110", .revenue), account("5110", .expense),
        ]
        let entries = [
            entry(number: 1, debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, debit: "5110", credit: "1110", amount: 9_999, voided: true),
        ]
        let openings = ["1110": 100_000, "3110": -100_000]

        let report = TrialBalanceService.report(fiscalYear: 2026, entries: entries, openingBalances: openings, accounts: accounts)

        #expect(report.totalDebit == 361_000)
        #expect(report.totalCredit == 361_000)
        #expect(report.openingImbalance == 0)
        #expect(report.isBalanced)
        #expect(report.rows.first { $0.accountCode == "1110" }?.closingBalance == 210_000)
        #expect(report.rows.first { $0.accountCode == "3210" }?.closingBalance == -251_000)
    }

    @Test func report_unbalancedOpenings_flagged() {
        let accounts = [account("1110", .asset)]
        let report = TrialBalanceService.report(fiscalYear: 2026, entries: [], openingBalances: ["1110": 5_000], accounts: accounts)
        #expect(report.openingImbalance == 5_000)
        #expect(!report.isBalanced)
    }

    @Test func report_excludesOtherFiscalYears() {
        // Prior year (2025) activity is already embedded in 2026 openings via rollover,
        // so the 2026 trial balance must count only 2026 entries on top of 2026 openings.
        let accounts = [account("1110", .asset), account("4110", .revenue), account("3110", .equity)]
        let entries = [
            entry(number: 9, debit: "1110", credit: "4110", amount: 110_000, fiscalYear: 2025),
            entry(number: 1, debit: "1110", credit: "4110", amount: 50_000, fiscalYear: 2026),
        ]
        let openings = ["1110": 210_000, "3110": -210_000] // rolled forward from 2025

        let report = TrialBalanceService.report(fiscalYear: 2026, entries: entries, openingBalances: openings, accounts: accounts)

        // 現金: 210,000 opening + 50,000 (2026 only) = 260,000 — NOT 370,000
        #expect(report.rows.first { $0.accountCode == "1110" }?.closingBalance == 260_000)
        #expect(report.rows.first { $0.accountCode == "1110" }?.debitTotal == 50_000)
    }
}
