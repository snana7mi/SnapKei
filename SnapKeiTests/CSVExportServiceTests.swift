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
}
