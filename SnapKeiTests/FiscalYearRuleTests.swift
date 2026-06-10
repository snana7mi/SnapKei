import Foundation
import Testing
@testable import SnapKei

@Suite("FiscalYearRule")
struct FiscalYearRuleTests {

    @Test func usesCalendarYear() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        #expect(FiscalYearRule.year(for: formatter.date(from: "2026-06-15")!) == 2026)
        #expect(FiscalYearRule.year(for: formatter.date(from: "2026-12-31")!) == 2026)
        #expect(FiscalYearRule.year(for: formatter.date(from: "2027-01-01")!) == 2027)
    }

    @Test func yearBoundaryIsJudgedInJST() {
        // 2025-12-31T15:30Z == 2026-01-01 00:30 JST → 報告サービスと同じ JST 基準で 2026 年。
        let utc = ISO8601DateFormatter().date(from: "2025-12-31T15:30:00Z")!
        #expect(FiscalYearRule.year(for: utc) == 2026)
    }
}

@Suite("YenFormat")
struct YenFormatTests {

    @Test func formatsWithGroupingAndSymbol() {
        #expect(YenFormat.string(110_000) == "¥110,000")
        #expect(YenFormat.string(0) == "¥0")
    }

    @Test func formatsNegativeAmounts() {
        #expect(YenFormat.string(-5_000) == "-¥5,000")
    }
}
