import Foundation
import SwiftData
import Testing
@testable import SnapKei

@MainActor
private enum UIServiceTestContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}

final class MemoryExpenseRepository: ExpenseRepository, @unchecked Sendable {
    var entries: [JournalEntry]
    var created: [JournalEntry] = []
    var voided: [JournalEntry] = []

    init(entries: [JournalEntry] = []) {
        self.entries = entries
    }

    func create(_ entry: JournalEntry, reason: String?) throws {
        created.append(entry)
        entries.insert(entry, at: 0)
    }

    func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        change()
    }

    func void(_ entry: JournalEntry, reason: String?) throws {
        entry.isVoided = true
        voided.append(entry)
    }

    func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry] {
        var result = entries
        if !criteria.includeVoided {
            result = result.filter { !$0.isVoided }
        }
        if let from = criteria.dateFrom {
            result = result.filter { $0.transactionDate >= from }
        }
        if let to = criteria.dateTo {
            let endOfDay = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: 1, to: Calendar(identifier: .gregorian).startOfDay(for: to)) ?? to
            result = result.filter { $0.transactionDate < endOfDay }
        }
        if let codes = criteria.debitAccountCodes, !codes.isEmpty {
            result = result.filter { codes.contains($0.debitAccountCode) }
        }
        return result
    }

    func nextEntryNumber(for fiscalYear: Int) throws -> Int { entries.count + 1 }
}

struct StubReceiptParser: ReceiptParser {
    let draft: ReceiptDraft

    func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        draft
    }
}

@Suite("UI service and view model behavior")
struct UIServiceViewModelTests {
    private func entry(
        counterparty: String = "テスト商店",
        desc: String = "通信費",
        amount: Int = 1100,
        date: Date = Date(),
        debit: String = "5110",
        credit: String = "3210",
        voided: Bool = false
    ) -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: date,
            debitAccountCode: debit,
            creditAccountCode: credit,
            amountIncludingTax: amount,
            amountExcludingTax: max(0, amount - amount / 11),
            consumptionTax: amount / 11,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: counterparty,
            transactionDescription: desc,
            sourceType: .manual,
            isVoided: voided
        )
    }

    @MainActor
    @Test func homeSummaryTotalsEntriesForSelectedMonth() throws {
        let cal = Calendar(identifier: .gregorian)
        let may = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let mayEnd = cal.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12))!
        let june = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let vm = HomeViewModel(repository: MemoryExpenseRepository(entries: [entry(amount: 1100, date: may), entry(amount: 2200, date: may), entry(amount: 3300, date: mayEnd), entry(amount: 999, date: june)]))

        let summary = try vm.monthlySummary(year: 2026, month: 5)

        #expect(summary.entryCount == 3)
        #expect(summary.totalIncludingTax == 6600)
    }

    @MainActor
    @Test func expenseListFiltersBySearchTextAndComputesTotal() {
        let vm = ExpenseListViewModel(repository: MemoryExpenseRepository(entries: [
            entry(counterparty: "Apple", desc: "Cloud"),
            entry(counterparty: "Amazon", desc: "Office", amount: 550),
        ]))
        vm.searchText = "cloud"

        vm.refresh()

        #expect(vm.entries.map(\.counterpartyName) == ["Apple"])
        #expect(vm.totalAmount == 1100)
    }

    @MainActor
    @Test func controlRouteDeductionReflectsEtaxAndNotificationSettings() {
        let suite = UserDefaults(suiteName: "snapkei.control.test.\(UUID().uuidString)")!
        suite.set(true, forKey: "controlRoute.hasFiledOptimalBookNotification")
        suite.set(true, forKey: "controlRoute.willUseEtax")

        let route = ControlRouteStatus.load(defaults: suite, hasEntries: true)

        #expect(route.estimatedDeduction == 750_000)
    }

    @MainActor
    @Test func pdfReportRendersValidPdfData() throws {
        let container = try SnapKeiModelContainer.inMemory()
        UIServiceTestContainerRetainer.retain(container)
        let context = container.mainContext
        AccountSeeder.seedIfNeeded(context: context)
        context.insert(entry(amount: 1100, debit: "5110", credit: "4110"))
        try context.save()

        let data = try PDFReportService.renderProfitAndLoss(fiscalYear: 2026, context: context)

        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
        #expect(data.count > 1000)
    }
}
