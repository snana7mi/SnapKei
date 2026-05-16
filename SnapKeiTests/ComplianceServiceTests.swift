import Testing
import Foundation
@testable import SnapKei

@Suite("ComplianceService")
struct ComplianceServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @Test func transitionalRate_qualifiedAlwaysFull() {
        for ds in ["2026-01-01", "2026-10-01", "2030-01-01", "2032-01-01"] {
            #expect(ComplianceService.transitionalRate(qualified: true, transactionDate: date(ds)) == 1.0)
        }
    }

    @Test func transitionalRate_unqualified_2026_09_30_boundary_isStillEightyPercent() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2026-09-30")) == 0.80)
    }

    @Test func transitionalRate_unqualified_2026_10_01_drops_to_70() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2026-10-01")) == 0.70)
    }

    @Test func transitionalRate_unqualified_2028_10_01_drops_to_50() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2028-10-01")) == 0.50)
    }

    @Test func transitionalRate_unqualified_2030_10_01_drops_to_30() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2030-10-01")) == 0.30)
    }

    @Test func transitionalRate_unqualified_2031_10_01_drops_to_zero() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2031-10-01")) == 0.0)
    }

    @Test func daysUntilScanDeadline_today_returns_positive() {
        let today = date("2026-05-16")
        let result = ComplianceService.daysUntilScanDeadline(receiptDate: today, today: today)
        #expect(result > 60 && result < 80)
    }

    @Test func daysUntilScanDeadline_threeMonthsAgo_returns_negative() {
        let receipt = date("2026-02-16")
        let today = date("2026-05-16")
        #expect(ComplianceService.daysUntilScanDeadline(receiptDate: receipt, today: today) < 0)
    }

    @Test func isLateEntry_within_threshold_false() {
        let tx = date("2026-05-01")
        let input = date("2026-05-10")
        #expect(!ComplianceService.isLateEntry(transactionDate: tx, inputDate: input))
    }

    @Test func isLateEntry_beyond_threshold_true() {
        let tx = date("2026-04-01")
        let input = date("2026-05-01")
        #expect(ComplianceService.isLateEntry(transactionDate: tx, inputDate: input))
    }

    @Test func suggestAssetTreatment_under100k_isNil() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 99_999, acquisitionDate: date("2026-05-16")) == nil)
    }

    @Test func suggestAssetTreatment_150k_is_lumpSum() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 150_000, acquisitionDate: date("2026-05-16")) == .lumpSumDepreciation)
    }

    @Test func suggestAssetTreatment_280k_within_expiry_is_smallAmount() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 280_000, acquisitionDate: date("2026-05-16")) == .smallAmountFullExpense)
    }

    @Test func suggestAssetTreatment_280k_after_expiry_is_normal() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 280_000, acquisitionDate: date("2029-04-01")) == .normalDepreciation)
    }

    @Test func suggestAssetTreatment_500k_is_normal() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 500_000, acquisitionDate: date("2026-05-16")) == .normalDepreciation)
    }

    @Test func suggestAssetTreatment_400k_boundary_is_normal() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 400_000, acquisitionDate: date("2026-05-16")) == .normalDepreciation)
    }
}
