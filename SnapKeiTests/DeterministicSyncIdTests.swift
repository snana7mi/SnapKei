import Foundation
import SwiftData
import Testing
import LLMGatewayKit
@testable import SnapKei

@Suite("Deterministic sync identity")
struct DeterministicSyncIdTests {

    @Test func deterministicID_sameInput_sameUUID() {
        #expect(DeterministicID.uuid(for: "x") == DeterministicID.uuid(for: "x"))
        #expect(DeterministicID.uuid(for: "x") != DeterministicID.uuid(for: "y"))
    }

    @Test func openingBalance_syncId_isStableForNaturalKey() {
        #expect(
            OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
                == OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
        )
        #expect(
            OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
                != OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1210")
        )
        #expect(
            OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
                != OpeningBalance.deterministicSyncId(fiscalYear: 2027, accountCode: "1110")
        )
    }

    @Test func fiscalYearClosure_syncId_isStableForYear() {
        #expect(
            FiscalYearClosure.deterministicSyncId(fiscalYear: 2026)
                == FiscalYearClosure.deterministicSyncId(fiscalYear: 2026)
        )
        #expect(
            FiscalYearClosure.deterministicSyncId(fiscalYear: 2026)
                != FiscalYearClosure.deterministicSyncId(fiscalYear: 2027)
        )
    }

    @MainActor
    @Test func merger_remoteClosure_withSameDeterministicId_updatesInPlace_noDuplicate_noIdentityRewrite() async throws {
        let container = try SnapKeiModelContainer.inMemory()
        TestDetContainerRetainer.retain(container)
        let context = container.mainContext

        // Local device created the FY2026 closure (deterministic syncId).
        let local = FiscalYearClosure(
            fiscalYear: 2026,
            netIncomeAtClosing: 100,
            closedByDeviceId: "device-A",
            syncId: FiscalYearClosure.deterministicSyncId(fiscalYear: 2026),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        context.insert(local)
        try context.save()

        // A second device independently closed FY2026 — it derives the SAME syncId.
        let remote = FiscalYearClosure(
            fiscalYear: 2026,
            netIncomeAtClosing: 200,
            closedByDeviceId: "device-B",
            syncId: FiscalYearClosure.deterministicSyncId(fiscalYear: 2026),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let payload = try JSONEncoder.snapkeiSync.encode(FiscalYearClosurePayload(from: remote))
        try await SnapKeiMerger(context: context).apply(
            SyncEnvelope(entityType: "FiscalYearClosure", entityID: remote.syncId.uuidString, modifiedAt: remote.updatedAt, data: payload)
        )

        let rows = try context.fetch(FetchDescriptor<FiscalYearClosure>())
        #expect(rows.count == 1)
        #expect(rows.first?.syncId == FiscalYearClosure.deterministicSyncId(fiscalYear: 2026))
        #expect(rows.first?.netIncomeAtClosing == 200) // newer remote wins
    }
}

@MainActor
private enum TestDetContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
