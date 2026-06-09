import Foundation
import SwiftData
import Testing
@testable import SnapKei

@Suite("OpeningBalanceStore", .serialized)
struct OpeningBalanceStoreTests {

    @MainActor
    private func makeFixture() throws -> (OpeningBalanceStore, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        TestOpeningContainerRetainer.retain(container)
        return (OpeningBalanceStore(context: container.mainContext), container.mainContext)
    }

    @MainActor
    private func makeStore() throws -> OpeningBalanceStore {
        try makeFixture().0
    }

    @MainActor
    @Test func set_and_balances_roundTrip() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)
        let balances = try store.balances(fiscalYear: 2026)
        #expect(balances["1110"] == 100_000)
        #expect(balances["3110"] == -100_000)
        #expect(try store.balances(fiscalYear: 2027).isEmpty)
    }

    @MainActor
    @Test func set_zero_removesRow() throws {
        let (store, context) = try makeFixture()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 0)
        #expect(try store.balances(fiscalYear: 2026)["1110"] == nil)
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>())
        #expect(rows.count == 1)
        #expect(rows.first?.deletedAt != nil)
    }

    @MainActor
    @Test func adjustCapitalToBalance_makesSumZero() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 300_000)
        try store.set(fiscalYear: 2026, accountCode: "2310", amount: -50_000)
        try store.adjustCapitalToBalance(fiscalYear: 2026)
        let balances = try store.balances(fiscalYear: 2026)
        #expect(balances[AccountCode.capital] == -250_000)
        #expect(balances.values.reduce(0, +) == 0)
    }

    @MainActor
    @Test func deleteAutoRolled_removesOnlyAutoRows() throws {
        let (store, context) = try makeFixture()
        try store.set(fiscalYear: 2027, accountCode: "1110", amount: 1_000, isAutoRolled: true)
        try store.set(fiscalYear: 2027, accountCode: "2310", amount: -500, isAutoRolled: false)
        try store.deleteAutoRolled(fiscalYear: 2027)
        let balances = try store.balances(fiscalYear: 2027)
        #expect(balances["1110"] == nil)
        #expect(balances["2310"] == -500)
        let tombstones = try context.fetch(FetchDescriptor<OpeningBalance>()).filter { $0.accountCode == "1110" }
        #expect(tombstones.first?.deletedAt != nil)
    }
}

@MainActor
private enum TestOpeningContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
