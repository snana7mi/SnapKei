import Foundation
import LLMGatewayKit
import SwiftData
import Testing
@testable import SnapKei

@Suite("SnapKeiChangeCollector", .serialized)
struct SnapKeiChangeCollectorTests {

    @MainActor
    private func makeFixture() throws -> (ModelContext, SyncCursorStore, SnapKeiChangeCollector) {
        let container = try SnapKeiModelContainer.inMemory()
        TestCollectorContainerRetainer.retain(container)
        let suite = UserDefaults(suiteName: "CollectorTests-\(UUID().uuidString)")!
        let cursor = SyncCursorStore(suite: suite, userIDProvider: { "test-user" })
        let collector = SnapKeiChangeCollector(context: container.mainContext, cursor: cursor)
        return (container.mainContext, cursor, collector)
    }

    private func insertEntry(_ context: ModelContext, updatedAt: Date) {
        context.insert(JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 1_100,
            amountExcludingTax: 1_000,
            consumptionTax: 100,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "店",
            transactionDescription: "件",
            sourceType: .manual,
            updatedAt: updatedAt
        ))
    }

    @MainActor
    @Test func collectPending_returnsOnlyChangesAfterCursor() async throws {
        let (context, cursor, collector) = try makeFixture()
        let cutoff = Date()
        insertEntry(context, updatedAt: cutoff.addingTimeInterval(-60))
        insertEntry(context, updatedAt: cutoff.addingTimeInterval(60))
        try context.save()

        cursor.lastPushedAt = cutoff
        let envelopes = try await collector.collectPending()
        #expect(envelopes.count == 1)
        #expect(envelopes.first?.entityType == "JournalEntry")
    }

    @MainActor
    @Test func markSynced_advancesCursorToLatestModifiedAt() async throws {
        let (context, cursor, collector) = try makeFixture()
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        insertEntry(context, updatedAt: t1)
        insertEntry(context, updatedAt: t2)
        try context.save()

        let envelopes = try await collector.collectPending()
        try await collector.markSynced(envelopes)
        #expect(cursor.lastPushedAt == t2)
    }

    @MainActor
    @Test func collectPending_includesLedgerState() async throws {
        let (context, _, collector) = try makeFixture()
        context.insert(OpeningBalance(fiscalYear: 2026, accountCode: "1110", amount: 100_000))
        context.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 75_000, closedByDeviceId: "test"))
        try context.save()

        let envelopes = try await collector.collectPending()
        #expect(envelopes.contains { $0.entityType == "OpeningBalance" })
        #expect(envelopes.contains { $0.entityType == "FiscalYearClosure" })
    }
}

@MainActor
private enum TestCollectorContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
