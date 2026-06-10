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

    func auditLogCount() throws -> Int { created.count + voided.count }
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

    /// 集計テスト用の科目種別: 1=資産, 2=負債, 3=資本, 4=収益, 5=費用（シード表の番台規則）。
    private func accountType(_ code: String) -> AccountType? {
        switch code.first {
        case "1": .asset
        case "2": .liability
        case "3": .equity
        case "4": .revenue
        case "5": .expense
        default: nil
        }
    }

    @MainActor
    @Test func homeSummarySeparatesIncomeExpenseAndIgnoresTransfers() throws {
        let cal = Calendar(identifier: .gregorian)
        let may = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let mayEnd = cal.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12))!
        let june = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let vm = HomeViewModel(repository: MemoryExpenseRepository(entries: [
            entry(amount: 1100, date: may),
            entry(amount: 2200, date: may),
            entry(amount: 3300, date: mayEnd),
            entry(amount: 11_000, date: may, debit: "1210", credit: "4110"),
            entry(amount: 50_000, date: may, debit: "1110", credit: "1210"),
            entry(amount: 999, date: june),
        ]))

        let summary = try vm.monthlySummary(year: 2026, month: 5, accountTypes: accountType)

        #expect(summary.entryCount == 5)
        #expect(summary.expenseTotal == 6600)
        #expect(summary.incomeTotal == 11_000)
        #expect(summary.expenseConsumptionTax == 600)
    }

    @MainActor
    @Test func homeByAccountChartShowsOnlyExpenseEntries() throws {
        let cal = Calendar(identifier: .gregorian)
        let may = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let vm = HomeViewModel(repository: MemoryExpenseRepository(entries: [
            entry(amount: 1100, date: may),
            entry(amount: 11_000, date: may, debit: "1210", credit: "4110"),
            entry(amount: 50_000, date: may, debit: "1110", credit: "1210"),
        ]))

        let byAccount = try vm.byDebitAccount(
            year: 2026, month: 5,
            accountLookup: { $0 },
            accountTypes: accountType
        )

        #expect(byAccount.map(\.id) == ["5110"])
        #expect(byAccount.first?.amount == 1100)
    }

    @MainActor
    @Test func overdueWarningsOnlyApplyToReceiptBackedEntries() throws {
        let cal = Calendar(identifier: .gregorian)
        let old = cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let receiptEntry = entry(date: old)
        receiptEntry.receiptImagePath = "2026/receipt.jpg"
        let manualEntry = entry(date: old)
        let vm = HomeViewModel(repository: MemoryExpenseRepository(entries: [receiptEntry, manualEntry]))

        let overdue = try vm.overdueEntries(today: today)

        #expect(overdue.map(\.receiptImagePath) == ["2026/receipt.jpg"])
    }

    @MainActor
    @Test func expenseListFiltersBySearchTextAndComputesTotals() {
        let vm = ExpenseListViewModel(repository: MemoryExpenseRepository(entries: [
            entry(counterparty: "Apple", desc: "Cloud"),
            entry(counterparty: "Amazon", desc: "Office", amount: 550),
        ]))
        vm.searchText = "cloud"

        vm.refresh()

        #expect(vm.entries.map(\.counterpartyName) == ["Apple"])
        let totals = vm.totals(accountTypes: accountType)
        #expect(totals.expense == 1100)
        #expect(totals.income == 0)
    }

    @MainActor
    @Test func expenseListTotalsSeparateIncome() {
        let vm = ExpenseListViewModel(repository: MemoryExpenseRepository(entries: [
            entry(counterparty: "Apple", desc: "Cloud"),
            entry(counterparty: "クライアントA", desc: "売上", amount: 110_000, debit: "1210", credit: "4110"),
            entry(counterparty: "自分", desc: "資金移動", amount: 50_000, debit: "1110", credit: "1210"),
        ]))

        vm.refresh()

        let totals = vm.totals(accountTypes: accountType)
        #expect(totals.expense == 1100)
        #expect(totals.income == 110_000)
    }

    @MainActor
    @Test func controlRouteDeductionReflectsEtaxAndNotificationSettings() {
        let suite = UserDefaults(suiteName: "snapkei.control.test.\(UUID().uuidString)")!
        suite.set(true, forKey: "controlRoute.hasFiledOptimalBookNotification")
        suite.set(true, forKey: "controlRoute.willUseEtax")

        let top = ControlRouteStatus.load(defaults: suite, hasEntries: true, hasAuditLog: true)
        #expect(top.estimatedDeduction == 650_000)

        let middle = ControlRouteStatus.load(defaults: UserDefaults(suiteName: "snapkei.control.test.\(UUID().uuidString)")!, hasEntries: true, hasAuditLog: true)
        #expect(middle.estimatedDeduction == 550_000)

        let low = ControlRouteStatus.load(defaults: UserDefaults(suiteName: "snapkei.control.test.\(UUID().uuidString)")!, hasEntries: true, hasAuditLog: false)
        #expect(low.estimatedDeduction == 100_000)

        let empty = ControlRouteStatus.load(defaults: UserDefaults(suiteName: "snapkei.control.test.\(UUID().uuidString)")!, hasEntries: false, hasAuditLog: false)
        #expect(empty.estimatedDeduction == 0)
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

    @MainActor
    @Test func balanceSheetPdfRendersValidPdfData() throws {
        let container = try SnapKeiModelContainer.inMemory()
        UIServiceTestContainerRetainer.retain(container)
        let context = container.mainContext
        AccountSeeder.seedIfNeeded(context: context)
        try OpeningBalanceStore(context: context).set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try OpeningBalanceStore(context: context).set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)
        context.insert(entry(amount: 1100, debit: "1110", credit: "4110"))
        try context.save()

        let data = try PDFReportService.renderBalanceSheet(fiscalYear: 2026, context: context)

        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
        #expect(data.count > 1000)
    }
}
