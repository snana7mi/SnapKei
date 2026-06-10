import Foundation
import SwiftData
import Testing
@testable import SnapKei

@Suite("YearEndClosingService", .serialized)
struct YearEndClosingServiceTests {

    @MainActor
    private func makeFixture() throws -> (ModelContext, YearEndClosingService) {
        let container = try SnapKeiModelContainer.inMemory()
        TestClosingContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let service = YearEndClosingService(context: container.mainContext, deviceId: "test-device")
        return (container.mainContext, service)
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @MainActor
    @Test func runDepreciation_postsFullAndOwnerPortion_once() throws {
        let (context, service) = try makeFixture()
        context.insert(FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.8
        ))
        try context.save()

        try service.runDepreciation(fiscalYear: 2026)
        try service.runDepreciation(fiscalYear: 2026)

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 2)
        #expect(entries.contains { $0.debitAccountCode == AccountCode.depreciationExpense && $0.amountIncludingTax == 24_000 })
        #expect(entries.contains { $0.debitAccountCode == AccountCode.ownerDraw && $0.amountIncludingTax == 6_000 })
    }

    @MainActor
    @Test func reopen_removesAllRolledOpenings_includingDerivedCapital() throws {
        // 再オープンで翌年期首は繰越前の状態に戻る。導出行の元入金が孤児として
        // 残ると翌年が貸借不一致になる。
        let (context, service) = try makeFixture()
        context.insert(JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: date("2026-03-01"),
            debitAccountCode: "1110",
            creditAccountCode: "4110",
            amountIncludingTax: 110_000,
            amountExcludingTax: 110_000,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: "x",
            transactionDescription: "sale",
            sourceType: .manual
        ))
        try context.save()
        try service.close(fiscalYear: 2026)
        let store = OpeningBalanceStore(context: context)
        #expect(!(try store.rows(fiscalYear: 2027).isEmpty))

        try service.reopen(fiscalYear: 2026, reason: "test")

        #expect(try store.rows(fiscalYear: 2027).isEmpty)
    }

    @MainActor
    @Test func reclose_replacesManualNextYearRowsWholesale() throws {
        // 再締めは「期首 = 前期末」を全面的に作り直す。前期末に存在しない科目の
        // 手動行が生き残ると年度間の継続性が壊れる。
        let (context, service) = try makeFixture()
        context.insert(JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: date("2026-03-01"),
            debitAccountCode: "1110",
            creditAccountCode: "4110",
            amountIncludingTax: 110_000,
            amountExcludingTax: 110_000,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: "x",
            transactionDescription: "sale",
            sourceType: .manual
        ))
        try context.save()
        try service.close(fiscalYear: 2026)

        let store = OpeningBalanceStore(context: context)
        try store.set(fiscalYear: 2027, accountCode: "1510", amount: 50_000) // 締め後の手動行
        try store.adjustCapitalToBalance(fiscalYear: 2027)
        try service.reopen(fiscalYear: 2026, reason: "fix")
        try service.close(fiscalYear: 2026)

        let balances = try store.balances(fiscalYear: 2027)
        #expect(balances["1510"] == nil)
        #expect(balances["1110"] == 110_000)
        #expect(balances[AccountCode.capital] == -110_000)
    }

    @MainActor
    @Test func close_createsClosureAndNextOpeningBalances() throws {
        let (context, service) = try makeFixture()
        context.insert(JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: date("2026-01-01"),
            debitAccountCode: "1110",
            creditAccountCode: "4110",
            amountIncludingTax: 110_000,
            amountExcludingTax: 110_000,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: "x",
            transactionDescription: "y",
            sourceType: .manual
        ))
        let openingStore = OpeningBalanceStore(context: context)
        try openingStore.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try openingStore.set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)

        try service.close(fiscalYear: 2026)

        #expect(try context.fetchCount(FetchDescriptor<FiscalYearClosure>()) == 1)
        let next = try OpeningBalanceStore(context: context).balances(fiscalYear: 2027)
        #expect(next["1110"] == 210_000)
        #expect(next[AccountCode.capital] == -210_000)
    }

    @MainActor
    @Test func runDepreciation_writesSystemActivityLog() throws {
        let (context, service) = try makeFixture()
        context.insert(FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.8
        ))
        try context.save()

        try service.runDepreciation(fiscalYear: 2026)

        let logs = try context.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .depreciationPosting }
        #expect(logs.count == 2) // deductible + owner-portion postings
        #expect(logs.allSatisfy { $0.targetEntryId != nil })
    }

    @MainActor
    @Test func reopen_logsUnlockPeriod() throws {
        let (context, service) = try makeFixture()
        try service.close(fiscalYear: 2026)
        try service.reopen(fiscalYear: 2026, reason: "入力漏れ")
        let logs = try context.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .unlockPeriod }
        #expect(logs.count == 1)
        #expect(logs.first?.reason == "入力漏れ")
    }

    @MainActor
    @Test func close_foldsOwnerBalancesIntoNextCapital() throws {
        let (context, service) = try makeFixture()
        // Income 110,000; an expense paid via 事業主借 (+11,000 owner loan). Net income 99,000.
        context.insert(JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: date("2026-01-01"),
            debitAccountCode: "1110", creditAccountCode: "4110",
            amountIncludingTax: 110_000, amountExcludingTax: 110_000, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "x", transactionDescription: "売上", sourceType: .manual
        ))
        context.insert(JournalEntry(
            entryNumber: 2, fiscalYear: 2026, transactionDate: date("2026-02-01"),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 11_000, amountExcludingTax: 11_000, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "y", transactionDescription: "通信費", sourceType: .manual
        ))
        let store = OpeningBalanceStore(context: context)
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)

        try service.close(fiscalYear: 2026)

        let next = try OpeningBalanceStore(context: context).balances(fiscalYear: 2027)
        // 元入金繰越 = 100,000 prior + 99,000 所得 + 11,000 事業主借 = 210,000 (stored debit-signed)
        #expect(next["1110"] == 210_000)
        #expect(next[AccountCode.capital] == -210_000)
        #expect(next[AccountCode.ownerLoan] == nil)
        #expect(next[AccountCode.ownerDraw] == nil)
        #expect(next.values.reduce(0, +) == 0)
    }

    @MainActor
    @Test func reopen_requiresReason_andDeletesClosure() throws {
        let (context, service) = try makeFixture()
        try service.close(fiscalYear: 2026)
        #expect(throws: YearEndClosingService.ClosingError.missingReopenReason) {
            try service.reopen(fiscalYear: 2026, reason: " ")
        }
        try service.reopen(fiscalYear: 2026, reason: "修正")
        let active = try context.fetch(FetchDescriptor<FiscalYearClosure>()).filter { $0.deletedAt == nil }
        #expect(active.isEmpty)
    }

    @MainActor
    @Test func runDepreciation_closedYear_throwsAndDoesNotMutateAsset() throws {
        let (context, service) = try makeFixture()
        let asset = FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        context.insert(asset)
        context.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "test"))
        try context.save()

        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try service.runDepreciation(fiscalYear: 2026)
        }
        #expect(asset.accumulatedDepreciation == 0)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }
}

@MainActor
private enum TestClosingContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
