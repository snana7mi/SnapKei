import Testing
import Foundation
@testable import SnapKei

@Suite("DepreciationService")
struct DepreciationServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @Test func straightLine_acquisitionYear_monthlyProrated() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 60_000)
    }

    @Test func straightLine_followingYear_fullAmount() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2027) == 120_000)
    }

    @Test func straightLine_yearBeforeAcquisition_isZero() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2025) == 0)
    }

    @Test func straightLine_withBusinessAllocation_50pct() {
        let asset = FixedAsset(
            assetName: "在宅事務所モニター",
            assetCategoryCode: "OTHER",
            acquisitionDate: date("2026-01-01"),
            serviceStartDate: date("2026-01-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 5,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.5
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 24_000)
    }

    @Test func lumpSum_third_of_amount() {
        let asset = FixedAsset(
            assetName: "事務机",
            assetCategoryCode: "FURNITURE",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 150_000,
            usefulLifeYears: 8,
            treatment: .lumpSumDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 50_000)
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2027) == 50_000)
    }

    @Test func smallAmount_alreadyExpensed_returnsZero() {
        let asset = FixedAsset(
            assetName: "カメラ",
            assetCategoryCode: "CAMERA",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 280_000,
            usefulLifeYears: 5,
            treatment: .smallAmountFullExpense
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 0)
    }

    @Test func annualAmount_splitsFullAndDeductible_byBusinessRate() {
        let asset = FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.8
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 30_000)
        #expect(amount.deductible == 24_000)
        #expect(amount.ownerPortion == 6_000)
    }

    @Test func annualAmount_fullAllocation_hasNoOwnerPortion() {
        let asset = FixedAsset(
            assetName: "サーバー",
            assetCategoryCode: "SERVER",
            acquisitionDate: date("2026-01-01"),
            serviceStartDate: date("2026-01-01"),
            acquisitionAmount: 500_000,
            usefulLifeYears: 5,
            treatment: .normalDepreciation
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 100_000)
        #expect(amount.deductible == 100_000)
        #expect(amount.ownerPortion == 0)
    }

    @Test func annualAmount_lumpSum_splitsToo() {
        let asset = FixedAsset(
            assetName: "事務机",
            assetCategoryCode: "FURNITURE",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 150_000,
            usefulLifeYears: 8,
            treatment: .lumpSumDepreciation,
            businessAllocationRate: 0.5
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 50_000)
        #expect(amount.deductible == 25_000)
    }
}
