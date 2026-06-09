import Foundation
import Testing
@testable import SnapKei

@Suite("LedgerService")
struct LedgerServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    private func entry(number: Int, day: String, debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number,
            fiscalYear: 2026,
            transactionDate: date(day),
            debitAccountCode: debit,
            creditAccountCode: credit,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: "相手\(number)",
            transactionDescription: "取引\(number)",
            sourceType: .manual,
            isVoided: voided
        )
    }

    private var fixture: [JournalEntry] {
        [
            entry(number: 1, day: "2026-01-10", debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, day: "2026-02-05", debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, day: "2026-03-01", debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, day: "2026-03-15", debit: "5290", credit: "1110", amount: 5_000, voided: true),
        ]
    }

    @Test func postings_twoPerEntry_balanced() {
        let postings = LedgerService.postings(from: fixture)
        #expect(postings.count == 8)
        let totalDebit = postings.reduce(0) { $0 + $1.debit }
        let totalCredit = postings.reduce(0) { $0 + $1.credit }
        #expect(totalDebit == totalCredit)
    }

    @Test func ledgerLines_runningBalance_debitSigned_excludesVoided() {
        let lines = LedgerService.ledgerLines(accountCode: "1110", fiscalYear: 2026, openingBalance: 100_000, entries: fixture)
        #expect(lines.count == 1)
        #expect(lines[0].debit == 110_000)
        #expect(lines[0].runningBalance == 210_000)
    }

    @Test func ledgerLines_creditAccount_negativeRunningBalance() {
        let lines = LedgerService.ledgerLines(accountCode: "3210", fiscalYear: 2026, openingBalance: 0, entries: fixture)
        #expect(lines.count == 2)
        #expect(lines[0].credit == 11_000)
        #expect(lines[0].runningBalance == -11_000)
        #expect(lines[1].runningBalance == -251_000)
    }

    @Test func ledgerLines_excludesOtherFiscalYears() {
        // 2025 cash entry already rolled into the 2026 opening; the 2026 ledger must not re-add it.
        let entries = [
            entry(number: 9, day: "2025-06-01", debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 1, day: "2026-02-01", debit: "1110", credit: "4110", amount: 50_000),
        ]
        // entry #9 is fiscalYear 2026 via the helper default, so force its year explicitly:
        entries[0].fiscalYear = 2025
        let lines = LedgerService.ledgerLines(accountCode: "1110", fiscalYear: 2026, openingBalance: 210_000, entries: entries)
        #expect(lines.count == 1)
        #expect(lines[0].runningBalance == 260_000) // 210,000 opening + 50,000 (2026 only)
    }

    @Test func missingEntryNumbers_detectsGaps() {
        let entries = [
            entry(number: 1, day: "2026-01-01", debit: "1110", credit: "4110", amount: 1),
            entry(number: 3, day: "2026-01-02", debit: "1110", credit: "4110", amount: 1),
            entry(number: 5, day: "2026-01-03", debit: "1110", credit: "4110", amount: 1),
        ]
        #expect(LedgerService.missingEntryNumbers(entries: entries) == [2, 4])
        #expect(LedgerService.missingEntryNumbers(entries: fixture) == [])
        #expect(LedgerService.missingEntryNumbers(entries: []) == [])
    }
}
