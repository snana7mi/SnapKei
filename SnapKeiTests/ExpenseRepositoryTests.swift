import Testing
import Foundation
import SwiftData
@testable import SnapKei

@MainActor
private enum TestContainerRetainer {
    static var containers: [ModelContainer] = []

    static func retain(_ container: ModelContainer) {
        containers.append(container)
    }
}

@Suite("ExpenseRepository — create / entryNumber", .serialized)
struct ExpenseRepositoryCreateTests {

    @MainActor
    private func makeRepo() throws -> (SwiftDataExpenseRepository, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        return (repo, container.mainContext)
    }

    private func makeEntry(year: Int, amount: Int = 1100) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: year,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: amount,
            amountExcludingTax: 1000,
            consumptionTax: 100,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店",
            transactionDescription: "テスト取引",
            sourceType: .manual
        )
    }

    @MainActor
    @Test func nextEntryNumber_emptyFiscalYear_returns1() throws {
        let (repo, _) = try makeRepo()
        #expect(try repo.nextEntryNumber(for: 2026) == 1)
    }

    @MainActor
    @Test func create_assignsEntryNumber1_2_3_inOrder() throws {
        let (repo, ctx) = try makeRepo()
        let e1 = makeEntry(year: 2026)
        let e2 = makeEntry(year: 2026)
        let e3 = makeEntry(year: 2026)
        try repo.create(e1, reason: nil)
        try repo.create(e2, reason: nil)
        try repo.create(e3, reason: nil)

        let all = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.entryNumber)]))
        #expect(all.map(\.entryNumber) == [1, 2, 3])
    }

    @MainActor
    @Test func create_isolatesFiscalYears() throws {
        let (repo, _) = try makeRepo()
        let a = makeEntry(year: 2025)
        let b = makeEntry(year: 2026)
        try repo.create(a, reason: nil)
        try repo.create(b, reason: nil)
        #expect(a.entryNumber == 1)
        #expect(b.entryNumber == 1)
    }

    @MainActor
    @Test func create_writesSystemActivityLog() throws {
        let (repo, ctx) = try makeRepo()
        let e = makeEntry(year: 2026)
        try repo.create(e, reason: nil)
        let logs = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.activityType == .createEntry)
        #expect(logs.first?.targetEntryId == e.id)
        #expect(logs.first?.beforeSnapshot == nil)
        #expect(logs.first?.afterSnapshot != nil)
    }
}

@Suite("ExpenseRepository — edit", .serialized)
struct ExpenseRepositoryEditTests {

    @MainActor
    private func makeSeeded() throws -> (SwiftDataExpenseRepository, ModelContext, JournalEntry) {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        let e = JournalEntry(
            entryNumber: 0,
            fiscalYear: 2026,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 1100,
            amountExcludingTax: 1000,
            consumptionTax: 100,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店",
            transactionDescription: "編集前",
            sourceType: .manual
        )
        try repo.create(e, reason: nil)
        return (repo, container.mainContext, e)
    }

    @MainActor
    @Test func edit_writesEditLogWithBeforeAndAfter() throws {
        let (repo, ctx, e) = try makeSeeded()
        try repo.edit(e, applying: { e.transactionDescription = "編集後" }, reason: "誤記訂正")

        let editLogs = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .editEntry }
        #expect(editLogs.count == 1)
        #expect(editLogs.first?.beforeSnapshot != nil)
        #expect(editLogs.first?.afterSnapshot != nil)
        #expect(editLogs.first?.reason == "誤記訂正")
    }

    @MainActor
    @Test func edit_beforeSnapshot_capturesOldDescription() throws {
        let (repo, ctx, e) = try makeSeeded()
        try repo.edit(e, applying: { e.transactionDescription = "編集後" }, reason: nil)

        let log = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
            .first(where: { $0.activityType == .editEntry })!
        let before = try JSONDecoder().decode(JournalEntrySnapshot.self, from: log.beforeSnapshot!)
        #expect(before.transactionDescription == "編集前")
    }

    @MainActor
    @Test func edit_updatesUpdatedAt_butPreservesCreatedAt() async throws {
        let (repo, _, e) = try makeSeeded()
        let originalCreatedAt = e.createdAt
        let originalUpdatedAt = e.updatedAt
        try await Task.sleep(nanoseconds: 10_000_000)
        try repo.edit(e, applying: { e.memo = "メモ" }, reason: nil)
        #expect(e.createdAt == originalCreatedAt)
        #expect(e.updatedAt > originalUpdatedAt)
    }
}

@Suite("ExpenseRepository — void", .serialized)
struct ExpenseRepositoryVoidTests {

    @MainActor
    @Test func void_marksIsVoided_butDoesNotDelete() throws {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let e = JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店", transactionDescription: "取消対象", sourceType: .manual
        )
        try repo.create(e, reason: nil)
        try repo.void(e, reason: "誤記")

        #expect(e.isVoided == true)
        let all = try container.mainContext.fetch(FetchDescriptor<JournalEntry>())
        #expect(all.count == 1)
    }

    @MainActor
    @Test func void_writesVoidLogWithBefore() throws {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let e = JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店", transactionDescription: "取消対象", sourceType: .manual
        )
        try repo.create(e, reason: nil)
        try repo.void(e, reason: "誤記")

        let voidLogs = try container.mainContext.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .voidEntry }
        #expect(voidLogs.count == 1)
        #expect(voidLogs.first?.beforeSnapshot != nil)
        #expect(voidLogs.first?.reason == "誤記")
    }
}

@Suite("ExpenseRepository — search", .serialized)
struct ExpenseRepositorySearchTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @MainActor
    private func setupFixture() throws -> SwiftDataExpenseRepository {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let make: (String, String, Int, Bool) -> JournalEntry = { dt, debit, amt, qualified in
            JournalEntry(
                entryNumber: 0, fiscalYear: 2026, transactionDate: self.date(dt),
                debitAccountCode: debit, creditAccountCode: "3210",
                amountIncludingTax: amt, amountExcludingTax: amt * 10 / 11, consumptionTax: amt - amt * 10 / 11,
                taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
                counterpartyName: "店\(amt)", invoiceQualified: qualified,
                transactionDescription: "取引\(amt)", sourceType: .manual
            )
        }

        try repo.create(make("2026-01-15", "5110", 1_100, true), reason: nil)
        try repo.create(make("2026-03-20", "5100", 5_500, false), reason: nil)
        try repo.create(make("2026-04-10", "5110", 11_000, true), reason: nil)
        try repo.create(make("2026-05-01", "5120", 22_000, false), reason: nil)
        return repo
    }

    @MainActor
    @Test func search_dateRange() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(
            dateFrom: date("2026-03-01"), dateTo: date("2026-04-30")
        ))
        #expect(res.count == 2)
    }

    @MainActor
    @Test func search_debitAccount() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(debitAccountCodes: ["5110"]))
        #expect(res.count == 2)
        #expect(res.allSatisfy { $0.debitAccountCode == "5110" })
    }

    @MainActor
    @Test func search_amountRange() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(amountMin: 5_000, amountMax: 15_000))
        #expect(res.count == 2)
    }

    @MainActor
    @Test func search_threeConditionsCombined() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(
            dateFrom: date("2026-01-01"), dateTo: date("2026-12-31"),
            debitAccountCodes: ["5110"],
            amountMin: 10_000, amountMax: 100_000
        ))
        #expect(res.count == 1)
        #expect(res.first?.amountIncludingTax == 11_000)
    }

    @MainActor
    @Test func search_qualifiedOnly_filtersUnqualified() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(qualifiedOnly: true))
        let unqualified = res.filter { !$0.invoiceQualified }
        #expect(res.count == 2)
        #expect(unqualified.isEmpty)
    }

    @MainActor
    @Test func search_excludesVoidedByDefault() throws {
        let repo = try setupFixture()
        let all = try repo.search(criteria: ExpenseSearchCriteria())
        let first = all.first!
        try repo.void(first, reason: nil)
        let afterVoid = try repo.search(criteria: ExpenseSearchCriteria())
        #expect(afterVoid.count == all.count - 1)
        #expect(!afterVoid.contains(where: { $0.id == first.id }))
    }

    @MainActor
    @Test func search_includeVoided_returnsAll() throws {
        let repo = try setupFixture()
        let all = try repo.search(criteria: ExpenseSearchCriteria())
        try repo.void(all.first!, reason: nil)
        let withVoided = try repo.search(criteria: ExpenseSearchCriteria(includeVoided: true))
        #expect(withVoided.count == all.count)
    }
}
