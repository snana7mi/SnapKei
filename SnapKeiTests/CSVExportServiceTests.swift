import Foundation
import Testing
@testable import SnapKei

@Suite("CSVExportService")
struct CSVExportServiceTests {
    private func makeEntry(counterparty: String = "セブン", desc: String = "コーヒー", memo: String? = nil) -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: Date(timeIntervalSince1970: 1_778_371_200),
            debitAccountCode: "5140",
            creditAccountCode: "1110",
            amountIncludingTax: 220,
            amountExcludingTax: 200,
            consumptionTax: 20,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .cash,
            counterpartyName: counterparty,
            transactionDescription: desc,
            memo: memo,
            sourceType: .manual
        )
    }

    private let lookup: (String) -> String = { code in
        switch code {
        case "5140": "消耗品費"
        case "1110": "現金"
        default: code
        }
    }

    @Test func exportEmptyEntriesReturnsBomAndHeaderOnly() {
        let data = CSVExportService.export([], accountNameLookup: lookup)
        let output = String(data: data, encoding: .utf8)!

        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        #expect(output.contains("日付,借方科目,貸方科目"))
        #expect(output.components(separatedBy: "\n").count == 2)
    }

    @Test func exportUsesAccountNamesAndEscapesCsvSpecialCharacters() {
        let entry = makeEntry(counterparty: "Store, A", desc: #"He said "hello""#)
        let output = String(data: CSVExportService.export([entry], accountNameLookup: lookup), encoding: .utf8)!

        #expect(output.contains("消耗品費"))
        #expect(output.contains("現金"))
        #expect(!output.contains(",5140,"))
        #expect(output.contains(#""Store, A""#))
        #expect(output.contains(#""He said ""hello""""#))
    }

    @Test func exportTrialBalance_includesTotals() {
        let report = TrialBalanceReport(
            rows: [TrialBalanceRow(accountCode: "1110", accountName: "現金", openingBalance: 100, debitTotal: 20, creditTotal: 5, closingBalance: 115)],
            totalDebit: 20,
            totalCredit: 5,
            openingImbalance: 0
        )
        let output = String(data: CSVExportService.exportTrialBalance(report), encoding: .utf8)!
        #expect(output.contains("勘定科目コード,勘定科目名"))
        #expect(output.contains("合計,,20,5"))
    }

    @Test func exportBalanceSheet_includesTotals() {
        let report = BalanceSheetReport(
            fiscalYear: 2026,
            assetLines: [BalanceSheetLine(accountCode: "1110", accountName: "現金", opening: 100, closing: 200)],
            liabilityLines: [],
            ownerDrawClosing: 0,
            ownerLoanClosing: 0,
            capitalOpening: 200,
            netIncome: 0,
            assetTotal: 200,
            liabilityEquityTotal: 200,
            openingImbalance: 0
        )
        let output = String(data: CSVExportService.exportBalanceSheet(report), encoding: .utf8)!
        #expect(output.contains("貸借対照表,2026"))
        #expect(output.contains("資産合計,200"))
        #expect(output.contains("負債・純資産合計,200"))
    }
}
