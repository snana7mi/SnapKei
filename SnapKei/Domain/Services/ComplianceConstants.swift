import Foundation

public enum ComplianceConstants {
    public nonisolated static let smallDepreciableAssetThreshold = 400_000
    public nonisolated static let smallDepreciableAnnualCap = 3_000_000
    public nonisolated static let smallDepreciableExpiry = parseISO("2029-03-31")
    public nonisolated static let lumpSumDepreciationThreshold = 200_000
    public nonisolated static let scanDeadlineMonths = 2
    public nonisolated static let scanDeadlineExtraBusinessDays = 7
    public nonisolated static let defaultLateEntryThresholdDays = 14
    public nonisolated static let transitionalRateSchedule: [(until: Date, rate: Double)] = [
        (parseISO("2026-09-30"), 0.80),
        (parseISO("2028-09-30"), 0.70),
        (parseISO("2030-09-30"), 0.50),
        (parseISO("2031-09-30"), 0.30),
    ]
    public nonisolated static let transitionalRateAfterAll: Double = 0.00
    public nonisolated static let minResolutionPixels = 3_870_000

    private nonisolated static func parseISO(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }
}
