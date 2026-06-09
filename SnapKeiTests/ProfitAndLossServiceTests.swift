import Foundation
import Testing
@testable import SnapKei

@Suite("ProfitAndLossService")
struct ProfitAndLossServiceTests {

    private func account(_ code: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: code, nameZh: code, accountType: type)
    }

    private func entry(debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
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

    @Test func summary_taxInclusiveRevenueAndExpenses_excludesVoided() {
        let accounts = [
            account("1110", .asset), account("4110", .revenue),
            account("5110", .expense), account("5230", .expense), account("3210", .equity),
        ]
        let entries = [
            entry(debit: "1110", credit: "4110", amount: 110_000),
            entry(debit: "5110", credit: "3210", amount: 11_000),
            entry(debit: "5230", credit: "3210", amount: 24_000),
            entry(debit: "5110", credit: "1110", amount: 99_999, voided: true),
        ]
        let summary = ProfitAndLossService.summary(entries: entries, accounts: accounts)
        #expect(summary.revenueTotal == 110_000)
        #expect(summary.expenseTotal == 35_000)
        #expect(summary.netIncome == 75_000)
        #expect(summary.expenseByCode["5110"] == 11_000)
    }
}
