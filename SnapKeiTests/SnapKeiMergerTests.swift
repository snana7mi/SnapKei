import Foundation
import LLMGatewayKit
import SwiftData
import Testing
@testable import SnapKei

@Suite("SnapKeiMerger", .serialized)
struct SnapKeiMergerTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try SnapKeiModelContainer.inMemory()
        TestMergerContainerRetainer.retain(container)
        return container.mainContext
    }

    private func entryPayloadData(syncId: UUID, updatedAt: Date, isVoided: Bool = false, amount: Int = 1_100) throws -> Data {
        let entry = JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: Date(timeIntervalSince1970: 0),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "リモート商店",
            transactionDescription: "クラウド由来",
            sourceType: .manual,
            updatedAt: updatedAt,
            syncId: syncId,
            isVoided: isVoided
        )
        return try JSONEncoder.snapkeiSync.encode(JournalEntryPayload(from: entry))
    }

    @MainActor
    @Test func apply_insertsNewJournalEntry() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()

        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: Date(),
            data: try entryPayloadData(syncId: syncId, updatedAt: Date())
        ))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.syncId == syncId)
        #expect(fetched.first?.counterpartyName == "リモート商店")
    }

    @MainActor
    @Test func apply_olderPayload_doesNotOverwriteNewerLocal() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let newer = Date()
        let older = newer.addingTimeInterval(-3_600)

        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: newer,
            data: try entryPayloadData(syncId: syncId, updatedAt: newer, amount: 2_200)
        ))
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: older,
            data: try entryPayloadData(syncId: syncId, updatedAt: older, amount: 1_100)
        ))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.amountIncludingTax == 2_200)
    }

    @MainActor
    @Test func apply_journalEntry_syncsReceiptImagePath() async throws {
        // 証憑のパスが同期されないと、他端末の詳細画面が「証憑なし」と誤表示する。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        var json = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: Date())
            ) as? [String: Any]
        )
        json["receiptImagePath"] = "receipts/2026/x.jpg"
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: Date(),
            data: try JSONSerialization.data(withJSONObject: json)
        ))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.first?.receiptImagePath == "receipts/2026/x.jpg")
    }

    @MainActor
    @Test func apply_journalEntry_oldPayloadWithoutPath_keepsLocalPath() async throws {
        // 旧バージョン端末の payload（receiptImagePath キーなし）でローカルのパスを消さない。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        var insertJson = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: t0)
            ) as? [String: Any]
        )
        insertJson["receiptImagePath"] = "receipts/2026/local.jpg"
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: t0,
            data: try JSONSerialization.data(withJSONObject: insertJson)
        ))

        var updateJson = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: t0.addingTimeInterval(60), amount: 2_200)
            ) as? [String: Any]
        )
        updateJson.removeValue(forKey: "receiptImagePath")
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: t0.addingTimeInterval(60),
            data: try JSONSerialization.data(withJSONObject: updateJson)
        ))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.first?.amountIncludingTax == 2_200)
        #expect(fetched.first?.receiptImagePath == "receipts/2026/local.jpg")
    }

    @MainActor
    @Test func apply_journalEntry_unknownEnumRaw_throwsInsteadOfSilentDrop() async throws {
        // 未知の enum rawValue（将来バージョンが追加したケース等）を黙って捨てると、
        // カーソルだけ進んで記録が永久に失われる。throw して再試行に回すこと。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        var json = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: Date())
            ) as? [String: Any]
        )
        json["taxCategoryRaw"] = "futureTaxCategory"
        let data = try JSONSerialization.data(withJSONObject: json)

        await #expect(throws: (any Error).self) {
            try await merger.apply(SyncEnvelope(
                entityType: "JournalEntry",
                entityID: syncId.uuidString,
                modifiedAt: Date(),
                data: data
            ))
        }
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func apply_fixedAsset_unknownEnumRaw_throwsInsteadOfSilentDrop() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        let asset = FixedAsset(
            assetName: "将来資産",
            assetCategoryCode: "PC",
            acquisitionDate: t0,
            serviceStartDate: t0,
            acquisitionAmount: 300_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            syncId: syncId,
            updatedAt: t0
        )
        var json = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
            ) as? [String: Any]
        )
        json["treatmentRaw"] = "futureTreatment"
        let data = try JSONSerialization.data(withJSONObject: json)

        await #expect(throws: (any Error).self) {
            try await merger.apply(SyncEnvelope(
                entityType: "FixedAsset",
                entityID: syncId.uuidString,
                modifiedAt: t0,
                data: data
            ))
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
    }

    @MainActor
    @Test func apply_journalEntry_unknownEnumRawOnUpdate_throwsAndKeepsLocal() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: t0,
            data: try entryPayloadData(syncId: syncId, updatedAt: t0, amount: 1_100)
        ))

        var json = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: t0.addingTimeInterval(60), amount: 2_200)
            ) as? [String: Any]
        )
        json["paymentMethodRaw"] = "futurePaymentMethod"
        let data = try JSONSerialization.data(withJSONObject: json)

        await #expect(throws: MergeError.self) {
            try await merger.apply(SyncEnvelope(
                entityType: "JournalEntry",
                entityID: syncId.uuidString,
                modifiedAt: t0.addingTimeInterval(60),
                data: data
            ))
        }
        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.amountIncludingTax == 1_100)
        #expect(fetched.first?.paymentMethodRaw == PaymentMethod.ownerLoan.rawValue)
    }

    @MainActor
    @Test func apply_fixedAsset_unknownEnumRawOnUpdate_throwsAndKeepsLocal() async throws {
        // 未知 treatment を保存すると fallback (.normalDepreciation) で誤った償却仕訳を
        // 生成して同期で拡散しかねないため、update でも拒否する。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        let asset = FixedAsset(
            assetName: "リモートPC",
            assetCategoryCode: "PC",
            acquisitionDate: t0,
            serviceStartDate: t0,
            acquisitionAmount: 300_000,
            usefulLifeYears: 4,
            treatment: .lumpSumDepreciation,
            syncId: syncId,
            updatedAt: t0
        )
        try await merger.apply(SyncEnvelope(
            entityType: "FixedAsset",
            entityID: syncId.uuidString,
            modifiedAt: t0,
            data: try JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
        ))

        asset.updatedAt = t0.addingTimeInterval(60)
        var json = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
            ) as? [String: Any]
        )
        json["treatmentRaw"] = "futureTreatment"
        let data = try JSONSerialization.data(withJSONObject: json)

        await #expect(throws: MergeError.self) {
            try await merger.apply(SyncEnvelope(
                entityType: "FixedAsset",
                entityID: syncId.uuidString,
                modifiedAt: asset.updatedAt,
                data: data
            ))
        }
        let fetched = try context.fetch(FetchDescriptor<FixedAsset>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.treatmentRaw == AssetTreatment.lumpSumDepreciation.rawValue)
    }

    @MainActor
    @Test func apply_staleJournalEntryWithUnknownEnum_isIgnoredWithoutError() async throws {
        // 古い payload は updatedAt ガードで捨てられるだけ。未知 enum でも throw して
        // カーソルを止めてはいけない（実体化しない envelope は無害）。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let newer = Date()
        let older = newer.addingTimeInterval(-3_600)
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: newer,
            data: try entryPayloadData(syncId: syncId, updatedAt: newer, amount: 2_200)
        ))

        var json = try #require(
            JSONSerialization.jsonObject(
                with: entryPayloadData(syncId: syncId, updatedAt: older, amount: 1_100)
            ) as? [String: Any]
        )
        json["taxCategoryRaw"] = "futureTaxCategory"
        try await merger.apply(SyncEnvelope(
            entityType: "JournalEntry",
            entityID: syncId.uuidString,
            modifiedAt: older,
            data: try JSONSerialization.data(withJSONObject: json)
        ))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.amountIncludingTax == 2_200)
    }

    @MainActor
    @Test func apply_fixedAssetTombstoneWithUnknownEnum_isIgnoredWithoutError() async throws {
        // ローカルに存在しない削除済み資産の tombstone は no-op。未知 enum でも
        // throw せず捨てられること（存在しないレコードで同期が永久に詰まるのを防ぐ）。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        let asset = FixedAsset(
            assetName: "削除済み将来資産",
            assetCategoryCode: "PC",
            acquisitionDate: t0,
            serviceStartDate: t0,
            acquisitionAmount: 300_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            syncId: syncId,
            updatedAt: t0,
            deletedAt: t0
        )
        var json = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
            ) as? [String: Any]
        )
        json["treatmentRaw"] = "futureTreatment"
        try await merger.apply(SyncEnvelope(
            entityType: "FixedAsset",
            entityID: syncId.uuidString,
            modifiedAt: t0,
            data: try JSONSerialization.data(withJSONObject: json)
        ))

        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
    }

    @MainActor
    @Test func apply_fixedAsset_insertAndTombstoneUpdate() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        let asset = FixedAsset(
            assetName: "リモートPC",
            assetCategoryCode: "PC",
            acquisitionDate: t0,
            serviceStartDate: t0,
            acquisitionAmount: 300_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            syncId: syncId,
            updatedAt: t0
        )
        try await merger.apply(SyncEnvelope(
            entityType: "FixedAsset",
            entityID: syncId.uuidString,
            modifiedAt: t0,
            data: try JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
        ))
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).count == 1)

        asset.deletedAt = t0.addingTimeInterval(60)
        asset.updatedAt = t0.addingTimeInterval(60)
        try await merger.apply(SyncEnvelope(
            entityType: "FixedAsset",
            entityID: syncId.uuidString,
            modifiedAt: asset.updatedAt,
            data: try JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
        ))

        let fetched = try context.fetch(FetchDescriptor<FixedAsset>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.deletedAt != nil)
    }

    @MainActor
    @Test func apply_openingBalance_insertAndNewerWins() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let newer = Date()
        let older = newer.addingTimeInterval(-3_600)

        let initial = OpeningBalance(fiscalYear: 2026, accountCode: "1110", amount: 100_000, syncId: syncId, updatedAt: newer)
        try await merger.apply(SyncEnvelope(
            entityType: "OpeningBalance",
            entityID: syncId.uuidString,
            modifiedAt: newer,
            data: try JSONEncoder.snapkeiSync.encode(OpeningBalancePayload(from: initial))
        ))

        let stale = OpeningBalance(fiscalYear: 2026, accountCode: "1110", amount: 1, syncId: syncId, updatedAt: older)
        try await merger.apply(SyncEnvelope(
            entityType: "OpeningBalance",
            entityID: syncId.uuidString,
            modifiedAt: older,
            data: try JSONEncoder.snapkeiSync.encode(OpeningBalancePayload(from: stale))
        ))

        let fetched = try context.fetch(FetchDescriptor<OpeningBalance>())
            .filter { $0.accountCode == "1110" && $0.deletedAt == nil }
        #expect(fetched.count == 1)
        #expect(fetched.first?.amount == 100_000)
    }

    @MainActor
    @Test func apply_openingBalance_rederivesCapitalLocally() async throws {
        // 元入金は導出行: 非元入金の期首を受信したらローカルで再導出する。
        // LWW のままでは2台が別科目を編集すると元入金が永久に不整合になる。
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let opening = OpeningBalance(
            fiscalYear: 2026, accountCode: "1110", amount: 100_000,
            syncId: OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
        )
        try await merger.apply(SyncEnvelope(
            entityType: "OpeningBalance",
            entityID: opening.syncId.uuidString,
            modifiedAt: opening.updatedAt,
            data: try JSONEncoder.snapkeiSync.encode(OpeningBalancePayload(from: opening))
        ))

        let balances = try OpeningBalanceStore(context: context).balances(fiscalYear: 2026)
        #expect(balances["1110"] == 100_000)
        #expect(balances[AccountCode.capital] == -100_000)
    }

    @MainActor
    @Test func apply_openingBalance_capitalPayloadIsIgnoredAndRederived() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let store = OpeningBalanceStore(context: context)
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.adjustCapitalToBalance(fiscalYear: 2026)

        // 他デバイス由来の（古い残高に基づく）元入金値はそのまま適用しない。
        let staleCapital = OpeningBalance(
            fiscalYear: 2026, accountCode: AccountCode.capital, amount: -999,
            syncId: OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: AccountCode.capital),
            updatedAt: Date().addingTimeInterval(3_600)
        )
        try await merger.apply(SyncEnvelope(
            entityType: "OpeningBalance",
            entityID: staleCapital.syncId.uuidString,
            modifiedAt: staleCapital.updatedAt,
            data: try JSONEncoder.snapkeiSync.encode(OpeningBalancePayload(from: staleCapital))
        ))

        let balances = try store.balances(fiscalYear: 2026)
        #expect(balances[AccountCode.capital] == -100_000)
    }

    @MainActor
    @Test func apply_openingBalance_twoDevicesSameNaturalKey_mergeToOneRow() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let older = Date()
        let newer = older.addingTimeInterval(60)

        // Two devices independently create the FY2026/1110 opening — both derive the SAME syncId,
        // so the merge collapses to a single row (no orphan).
        let syncId = OpeningBalance.deterministicSyncId(fiscalYear: 2026, accountCode: "1110")
        let first = OpeningBalance(fiscalYear: 2026, accountCode: "1110", amount: 1, syncId: syncId, updatedAt: older)
        let second = OpeningBalance(fiscalYear: 2026, accountCode: "1110", amount: 2, syncId: syncId, updatedAt: newer)
        for opening in [first, second] {
            try await merger.apply(SyncEnvelope(
                entityType: "OpeningBalance",
                entityID: opening.syncId.uuidString,
                modifiedAt: opening.updatedAt,
                data: try JSONEncoder.snapkeiSync.encode(OpeningBalancePayload(from: opening))
            ))
        }

        let fetched = try context.fetch(FetchDescriptor<OpeningBalance>())
            .filter { $0.accountCode == "1110" && $0.deletedAt == nil }
        #expect(fetched.count == 1)
        #expect(fetched.first?.amount == 2)
    }

    @MainActor
    @Test func apply_fiscalYearClosure_insert() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let closure = FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 75_000, closedByDeviceId: "remote")

        try await merger.apply(SyncEnvelope(
            entityType: "FiscalYearClosure",
            entityID: closure.syncId.uuidString,
            modifiedAt: closure.updatedAt,
            data: try JSONEncoder.snapkeiSync.encode(FiscalYearClosurePayload(from: closure))
        ))

        let fetched = try context.fetch(FetchDescriptor<FiscalYearClosure>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.fiscalYear == 2026)
        #expect(fetched.first?.netIncomeAtClosing == 75_000)
    }

    @MainActor
    @Test func apply_fiscalYearClosure_twoDevicesSameYear_mergeToOneRow() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        // Both devices derive the same deterministic syncId for FY2026, so the newer one wins
        // in place rather than orphaning a second server row.
        let syncId = FiscalYearClosure.deterministicSyncId(fiscalYear: 2026)
        let older = FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 1, closedByDeviceId: "a", syncId: syncId, updatedAt: Date())
        let newer = FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 2, closedByDeviceId: "b", syncId: syncId, updatedAt: older.updatedAt.addingTimeInterval(60))
        for closure in [older, newer] {
            try await merger.apply(SyncEnvelope(
                entityType: "FiscalYearClosure",
                entityID: closure.syncId.uuidString,
                modifiedAt: closure.updatedAt,
                data: try JSONEncoder.snapkeiSync.encode(FiscalYearClosurePayload(from: closure))
            ))
        }

        let fetched = try context.fetch(FetchDescriptor<FiscalYearClosure>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.netIncomeAtClosing == 2)
        #expect(fetched.first?.closedByDeviceId == "b")
    }
}

@MainActor
private enum TestMergerContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
