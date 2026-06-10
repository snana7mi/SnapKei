import Foundation
import SwiftData
import Testing
@testable import SnapKei

@MainActor
private enum FixedAssetTestContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}

@Suite("FixedAssetService", .serialized)
struct FixedAssetServiceTests {

    @MainActor
    private func makeService() throws -> (FixedAssetService, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        FixedAssetTestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let service = FixedAssetService(context: container.mainContext, deviceId: "test-device")
        return (service, container.mainContext)
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    private func purchaseInput(
        amount: Int = 480_000,
        treatment: AssetTreatment = .normalDepreciation,
        allocation: Double = 1.0
    ) -> FixedAssetService.RegistrationInput {
        FixedAssetService.RegistrationInput(
            name: "MacBook Pro",
            categoryCode: "PC",
            acquisitionDate: date("2026-05-16"),
            serviceStartDate: date("2026-05-16"),
            acquisitionAmount: amount,
            usefulLifeYears: 4,
            treatment: treatment,
            businessAllocationRate: allocation,
            paymentMethod: .bankTransfer,
            taxCategory: .standard10,
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
    }

    @MainActor
    @Test func register_purchase_createsAssetAndAcquisitionEntry() throws {
        let (service, context) = try makeService()

        let asset = try service.register(purchaseInput())

        #expect(asset.bookValue == 480_000)
        #expect(asset.accumulatedDepreciation == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.debitAccountCode == AccountCode.equipment)
        #expect(entry.creditAccountCode == AccountCode.bankDeposit)
        #expect(entry.amountIncludingTax == 480_000)
        #expect(entry.relatedFixedAssetId == asset.syncId)
        #expect(asset.acquisitionJournalEntryId == entry.id)
        #expect(entry.fiscalYear == 2026)
        #expect(entry.sourceTypeRaw == RecordSource.manual.rawValue)
    }

    @MainActor
    @Test func register_smallAmountFullExpense_postsImmediateDepreciation() throws {
        let (service, context) = try makeService()

        // 250,000 円・事業割合 80% の少額特例（即時償却）。
        let asset = try service.register(purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense, allocation: 0.8))

        #expect(asset.accumulatedDepreciation == 250_000)
        #expect(asset.bookValue == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 3) // 取得 + 償却(経費分) + 償却(家事分)
        let depreciation = entries.filter { $0.sourceTypeRaw == RecordSource.depreciation.rawValue }
        #expect(depreciation.count == 2)
        let deductible = depreciation.first { $0.debitAccountCode == AccountCode.depreciationExpense }
        let owner = depreciation.first { $0.debitAccountCode == AccountCode.ownerDraw }
        #expect(deductible?.amountIncludingTax == 200_000)
        #expect(owner?.amountIncludingTax == 50_000)
        #expect(deductible?.creditAccountCode == AccountCode.accumulatedDepreciation)
    }

    @MainActor
    @Test func register_carriedOver_createsNoEntries() throws {
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 200_000)
        input.isCarriedOver = true
        input.accumulatedDepreciation = 100_000
        input.acquisitionDate = date("2024-05-16") // 引継ぎは前年以前の取得のみ
        input.serviceStartDate = date("2024-05-16")

        let asset = try service.register(input)

        #expect(asset.bookValue == 100_000)
        #expect(asset.accumulatedDepreciation == 100_000)
        #expect(asset.acquisitionJournalEntryId == nil)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func register_invalidInput_throwsValidationError() throws {
        let (service, context) = try makeService()
        let input = purchaseInput(amount: 50_000) // 10万円未満は登記不可

        #expect(throws: FixedAssetService.ServiceError.self) {
            try service.register(input)
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func dispose_postsTransferOutEntriesAndMarksAsset() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput()) // 480,000 / 簿価480,000
        asset.accumulatedDepreciation = 120_000
        asset.bookValue = 360_000
        try context.save()

        try service.dispose(asset, on: date("2026-09-30"), proceeds: 200_000)

        #expect(asset.disposalDate == date("2026-09-30"))
        #expect(asset.disposalAmount == 200_000)
        #expect(asset.bookValue == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
            .filter { $0.sourceTypeRaw == RecordSource.manual.rawValue && $0.transactionDescription.contains("処分") }
        #expect(entries.count == 2)
        let accumulated = entries.first { $0.debitAccountCode == AccountCode.accumulatedDepreciation }
        let ownerOut = entries.first { $0.debitAccountCode == AccountCode.ownerDraw }
        #expect(accumulated?.amountIncludingTax == 120_000)
        #expect(accumulated?.creditAccountCode == AccountCode.equipment)
        #expect(ownerOut?.amountIncludingTax == 360_000)
        #expect(ownerOut?.creditAccountCode == AccountCode.equipment)
    }

    @MainActor
    @Test func dispose_zeroAccumulated_postsSingleEntry() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput())

        try service.dispose(asset, on: date("2026-09-30"), proceeds: nil)

        let disposals = try context.fetch(FetchDescriptor<JournalEntry>())
            .filter { $0.transactionDescription.contains("処分") }
        #expect(disposals.count == 1)
        #expect(disposals.first?.amountIncludingTax == 480_000)
    }

    @MainActor
    @Test func dispose_lumpSum_recordsOnlyWithoutEntries() throws {
        // 一括償却資産は処分後も3年均等償却を継続する（令139条）ため、
        // 転出仕訳を生成せず記録のみ。簿価も維持する。
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput(amount: 150_000, treatment: .lumpSumDepreciation))
        let entryCountBefore = try context.fetch(FetchDescriptor<JournalEntry>()).count

        try service.dispose(asset, on: date("2026-09-30"), proceeds: 30_000)

        #expect(asset.disposalDate != nil)
        #expect(asset.disposalAmount == 30_000)
        #expect(asset.bookValue == 150_000)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == entryCountBefore)
    }

    @MainActor
    @Test func dispose_beforeAcquisitionDate_throws() throws {
        let (service, _) = try makeService()
        let asset = try service.register(purchaseInput()) // 取得 2026-05-16

        #expect(throws: FixedAssetService.ServiceError.invalidDisposalDate) {
            try service.dispose(asset, on: date("2025-12-01"), proceeds: nil)
        }
        #expect(asset.disposalDate == nil)
    }

    @MainActor
    @Test func register_smallAmount_postsExpensingInServiceStartYear() throws {
        // 少額特例は「事業の用に供した年」の経費。取得 2026-12 / 供用 2027-01 なら
        // 即時償却仕訳は FY2027 に入る（取得仕訳は FY2026）。
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense)
        input.acquisitionDate = date("2026-12-20")
        input.serviceStartDate = date("2027-01-05")

        _ = try service.register(input)

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        let acquisition = entries.first { $0.sourceTypeRaw == RecordSource.manual.rawValue }
        let expensing = entries.filter { $0.sourceTypeRaw == RecordSource.depreciation.rawValue }
        #expect(acquisition?.fiscalYear == 2026)
        #expect(expensing.allSatisfy { $0.fiscalYear == 2027 })
    }

    @MainActor
    @Test func register_smallAmount_closedServiceYear_throwsBeforeAnyWrite() throws {
        let (service, context) = try makeService()
        context.insert(FiscalYearClosure(fiscalYear: 2027, netIncomeAtClosing: 0, closedByDeviceId: "x"))
        try context.save()
        var input = purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense)
        input.acquisitionDate = date("2026-12-20")
        input.serviceStartDate = date("2027-01-05")

        #expect(throws: RepositoryError.fiscalYearClosed(2027)) {
            try service.register(input)
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func register_smallAmount_overAnnualCap_throws() throws {
        // 少額特例の年間合計は取得価額 300 万円が上限（措置法28条の2）。
        let (service, context) = try makeService()
        for index in 0..<10 {
            context.insert(FixedAsset(
                assetName: "既存少額資産\(index)",
                assetCategoryCode: "OTHER",
                acquisitionDate: date("2026-03-01"),
                serviceStartDate: date("2026-03-01"),
                acquisitionAmount: 280_000,
                usefulLifeYears: 5,
                treatment: .smallAmountFullExpense
            ))
        }
        try context.save() // 既存合計 2,800,000

        #expect(throws: FixedAssetService.ServiceError.smallAmountAnnualCapExceeded) {
            try service.register(purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense))
        }

        // 定額法なら登録できる。
        _ = try service.register(purchaseInput(amount: 250_000, treatment: .normalDepreciation))
    }

    @MainActor
    @Test func dispose_twice_throws() throws {
        let (service, _) = try makeService()
        let asset = try service.register(purchaseInput())
        try service.dispose(asset, on: date("2026-09-30"), proceeds: nil)

        #expect(throws: FixedAssetService.ServiceError.alreadyDisposed) {
            try service.dispose(asset, on: date("2026-10-01"), proceeds: nil)
        }
    }

    @MainActor
    @Test func delete_withDepreciationEntries_throws() throws {
        let (service, _) = try makeService()
        // 即時償却仕訳が存在する資産は削除不可。
        let asset = try service.register(purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense))

        #expect(throws: FixedAssetService.ServiceError.hasDepreciationEntries) {
            try service.delete(asset)
        }
        #expect(asset.deletedAt == nil)
    }

    @MainActor
    @Test func delete_voidsAcquisitionEntryAndSoftDeletes() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput())

        try service.delete(asset)

        #expect(asset.deletedAt != nil)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.isVoided == true)
    }

    @MainActor
    @Test func delete_carriedOver_noEntries_softDeletes() throws {
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 200_000)
        input.isCarriedOver = true
        input.accumulatedDepreciation = 50_000
        input.acquisitionDate = date("2024-05-16")
        input.serviceStartDate = date("2024-05-16")
        let asset = try service.register(input)

        try service.delete(asset)

        #expect(asset.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func register_closedFiscalYear_throwsAndLeavesNothing() throws {
        let (service, context) = try makeService()
        context.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "x"))
        try context.save()

        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try service.register(purchaseInput())
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }
}
