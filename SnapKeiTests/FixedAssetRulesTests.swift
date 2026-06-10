import Foundation
import Testing
@testable import SnapKei

@Suite("FixedAssetRules")
struct FixedAssetRulesTests {
    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @Test func availableTreatments_byAmountBands() {
        let d = date("2026-05-16")
        #expect(FixedAssetRules.availableTreatments(amount: 99_999, acquisitionDate: d) == [])
        #expect(FixedAssetRules.availableTreatments(amount: 150_000, acquisitionDate: d)
            == [.normalDepreciation, .lumpSumDepreciation, .smallAmountFullExpense])
        #expect(FixedAssetRules.availableTreatments(amount: 250_000, acquisitionDate: d)
            == [.normalDepreciation, .smallAmountFullExpense])
        #expect(FixedAssetRules.availableTreatments(amount: 300_000, acquisitionDate: d)
            == [.normalDepreciation])
    }

    @Test func availableTreatments_smallAmountExpiresWithDeadline() {
        let afterExpiry = date("2029-04-01")
        #expect(FixedAssetRules.availableTreatments(amount: 150_000, acquisitionDate: afterExpiry)
            == [.normalDepreciation, .lumpSumDepreciation])
    }

    @Test func validate_passesForValidInput() {
        let issues = FixedAssetRules.validate(
            name: "MacBook Pro",
            amount: 480_000,
            usefulLifeYears: 4,
            allocationRate: 1.0,
            treatment: .normalDepreciation,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.isEmpty)
    }

    @Test func validate_collectsIssues() {
        let issues = FixedAssetRules.validate(
            name: " ",
            amount: 0,
            usefulLifeYears: 1,
            allocationRate: 0,
            treatment: .normalDepreciation,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.contains(.missingName))
        #expect(issues.contains(.invalidAmount))
        #expect(issues.contains(.invalidUsefulLife))
        #expect(issues.contains(.invalidAllocation))
    }

    @Test func validate_treatmentMustBeAvailableForAmount() {
        // 350,000 円に少額特例は選べない（30万円以上）。
        let issues = FixedAssetRules.validate(
            name: "カメラ",
            amount: 350_000,
            usefulLifeYears: 5,
            allocationRate: 1.0,
            treatment: .smallAmountFullExpense,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.contains(.treatmentNotAvailable))
    }

    @Test func validate_carriedOverMustBeAcquiredInPriorYear() {
        // 当年取得の資産を引継ぎ登録すると、月割償却と引継ぎ累計が二重計上になる。
        let sameYear = FixedAssetRules.validate(
            name: "PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2026-04-01"),
            isCarriedOver: true, accumulatedDepreciation: 30_000,
            today: date("2026-06-10")
        )
        #expect(sameYear.contains(.carriedOverMustBePriorYear))

        let priorYear = FixedAssetRules.validate(
            name: "PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2024-04-01"),
            isCarriedOver: true, accumulatedDepreciation: 100_000,
            today: date("2026-06-10")
        )
        #expect(priorYear.isEmpty)
    }

    @Test func validate_carriedOverSmallAmountMustBeFullyExpensed() {
        // 少額特例は供用年に全額経費化済みのはず。未満の累計で引き継ぐと
        // 永久に償却されない幽霊簿価が残る。
        let partial = FixedAssetRules.validate(
            name: "旧カメラ", amount: 250_000, usefulLifeYears: 5, allocationRate: 1.0,
            treatment: .smallAmountFullExpense, acquisitionDate: date("2024-04-01"),
            isCarriedOver: true, accumulatedDepreciation: 100_000,
            today: date("2026-06-10")
        )
        #expect(partial.contains(.carriedOverSmallAmountNotFullyExpensed))

        let full = FixedAssetRules.validate(
            name: "旧カメラ", amount: 250_000, usefulLifeYears: 5, allocationRate: 1.0,
            treatment: .smallAmountFullExpense, acquisitionDate: date("2024-04-01"),
            isCarriedOver: true, accumulatedDepreciation: 250_000,
            today: date("2026-06-10")
        )
        #expect(full.isEmpty)
    }

    @Test func validate_carriedOverAccumulatedBounds() {
        let over = FixedAssetRules.validate(
            name: "旧PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2024-01-01"),
            isCarriedOver: true, accumulatedDepreciation: 250_000
        )
        #expect(over.contains(.invalidAccumulated))

        let ok = FixedAssetRules.validate(
            name: "旧PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2024-01-01"),
            isCarriedOver: true, accumulatedDepreciation: 100_000
        )
        #expect(ok.isEmpty)
    }
}
