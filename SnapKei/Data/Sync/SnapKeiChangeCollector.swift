import Foundation
import LLMGatewayKit
import SwiftData

@MainActor
public final class SnapKeiChangeCollector: SyncChangeCollecting, @unchecked Sendable {
    private let context: ModelContext
    private let cursor: SyncCursorStore

    public init(context: ModelContext, cursor: SyncCursorStore) {
        self.context = context
        self.cursor = cursor
    }

    public func collectPending() async throws -> [SyncEnvelope] {
        let since = cursor.lastPushedAt ?? .distantPast
        var envelopes: [SyncEnvelope] = []

        let entriesDescriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> { $0.updatedAt > since }
        )
        for entry in try context.fetch(entriesDescriptor) {
            let payload = JournalEntryPayload(from: entry)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(
                SyncEnvelope(
                    entityType: "JournalEntry",
                    entityID: entry.syncId.uuidString,
                    modifiedAt: entry.updatedAt,
                    data: data
                )
            )
        }

        let assetsDescriptor = FetchDescriptor<FixedAsset>(
            predicate: #Predicate<FixedAsset> { $0.updatedAt > since }
        )
        for asset in try context.fetch(assetsDescriptor) {
            let payload = FixedAssetPayload(from: asset)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(
                SyncEnvelope(
                    entityType: "FixedAsset",
                    entityID: asset.syncId.uuidString,
                    modifiedAt: asset.updatedAt,
                    data: data
                )
            )
        }

        let openingDescriptor = FetchDescriptor<OpeningBalance>(
            predicate: #Predicate<OpeningBalance> { $0.updatedAt > since }
        )
        for opening in try context.fetch(openingDescriptor) {
            let payload = OpeningBalancePayload(from: opening)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(SyncEnvelope(
                entityType: "OpeningBalance",
                entityID: opening.syncId.uuidString,
                modifiedAt: opening.updatedAt,
                data: data
            ))
        }

        let closureDescriptor = FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate<FiscalYearClosure> { $0.updatedAt > since }
        )
        for closure in try context.fetch(closureDescriptor) {
            let payload = FiscalYearClosurePayload(from: closure)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(SyncEnvelope(
                entityType: "FiscalYearClosure",
                entityID: closure.syncId.uuidString,
                modifiedAt: closure.updatedAt,
                data: data
            ))
        }

        return envelopes
    }

    public func markSynced(_ envelopes: [SyncEnvelope]) async throws {
        guard let latest = envelopes.map(\.modifiedAt).max() else { return }
        cursor.lastPushedAt = latest
    }
}
