import Foundation
import Testing
@testable import SnapKei

@Suite("EntryChangeDiff")
struct EntryChangeDiffTests {

    private func makeEntry() -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: Date(timeIntervalSince1970: 1_770_000_000),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 880,
            amountExcludingTax: 800,
            consumptionTax: 80,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "コンビニ",
            transactionDescription: "消耗品",
            sourceType: .manual
        )
    }

    private func snapshot(_ entry: JournalEntry) -> JournalEntrySnapshot {
        JournalEntrySnapshot(from: entry)
    }

    private let noName: (String) -> String? = { _ in nil }

    @Test func noChange_returnsEmpty() {
        let entry = makeEntry()
        let changes = EntryChangeDiff.changes(before: snapshot(entry), after: snapshot(entry), accountName: noName)
        #expect(changes.isEmpty)
    }

    @Test func amountChange_reportsYenFormat() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.amountIncludingTax = 980
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes == [EntryChangeDiff.FieldChange(label: "税込金額", old: "¥880", new: "¥980")])
    }

    @Test func accountChange_resolvesName_orFallsBackToCode() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.debitAccountCode = "5180"
        let resolved = EntryChangeDiff.changes(before: before, after: snapshot(entry)) { code in
            code == "5180" ? "地代家賃" : nil
        }
        #expect(resolved.contains(EntryChangeDiff.FieldChange(label: "借方", old: "5110", new: "5180 地代家賃")))
    }

    @Test func enumChange_usesJapaneseLabels() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.taxCategoryRaw = TaxCategory.reduced8.rawValue
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "税区分", old: "10%", new: "8% 軽減")))
    }

    @Test func unknownEnumRaw_fallsBackToRawString() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.taxCategoryRaw = "bogus"
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "税区分", old: "10%", new: "bogus")))
    }

    @Test func memoNilToValue_showsPlaceholder() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.memo = "領収書あり"
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "メモ", old: "（なし）", new: "領収書あり")))
    }

    @Test func allocationChange_reportsPercentAndOriginalAmount() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.businessAllocationRate = 0.5
        entry.originalAmountIncludingTax = 880
        entry.amountIncludingTax = 440
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "事業割合", old: "100%", new: "50%")))
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "按分前金額", old: "（なし）", new: "¥880")))
    }

    // MARK: - Data 入口（SystemActivityLog 由来）

    @Test func dataRoundTrip_decodesAndDiffs() throws {
        let entry = makeEntry()
        let beforeData = try JSONEncoder().encode(snapshot(entry))
        entry.counterpartyName = "スーパー"
        let afterData = try JSONEncoder().encode(snapshot(entry))
        let changes = EntryChangeDiff.changes(beforeData: beforeData, afterData: afterData, accountName: noName)
        #expect(changes == [EntryChangeDiff.FieldChange(label: "取引先", old: "コンビニ", new: "スーパー")])
    }

    @Test func missingOrCorruptData_returnsNil() throws {
        let valid = try JSONEncoder().encode(snapshot(makeEntry()))
        #expect(EntryChangeDiff.changes(beforeData: nil, afterData: valid, accountName: noName) == nil)
        #expect(EntryChangeDiff.changes(beforeData: valid, afterData: Data("x".utf8), accountName: noName) == nil)
    }
}
