import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum ComplianceService {
    public static func daysUntilScanDeadline(receiptDate: Date, today: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let twoMonthsLater = cal.date(byAdding: .month, value: ComplianceConstants.scanDeadlineMonths, to: receiptDate)!
        let deadline = addBusinessDays(twoMonthsLater, days: ComplianceConstants.scanDeadlineExtraBusinessDays, calendar: cal)

        let todayStart = cal.startOfDay(for: today)
        let deadlineStart = cal.startOfDay(for: deadline)
        let comps = cal.dateComponents([.day], from: todayStart, to: deadlineStart)
        return comps.day ?? 0
    }

    public static func isLateEntry(transactionDate: Date, inputDate: Date, thresholdDays: Int = ComplianceConstants.defaultLateEntryThresholdDays) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: transactionDate), to: cal.startOfDay(for: inputDate))
        let diff = comps.day ?? 0
        return diff > thresholdDays
    }

    #if canImport(UIKit)
    public static func validateImageResolution(_ image: UIImage) -> Bool {
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return pixels >= ComplianceConstants.minResolutionPixels
    }
    #endif

    public static func transitionalRate(qualified: Bool, transactionDate: Date) -> Double {
        if qualified { return 1.0 }
        for entry in ComplianceConstants.transitionalRateSchedule {
            if transactionDate <= entry.until { return entry.rate }
        }
        return ComplianceConstants.transitionalRateAfterAll
    }

    public static func suggestAssetTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        if amount < 100_000 { return nil }
        if amount < ComplianceConstants.lumpSumDepreciationThreshold {
            return .lumpSumDepreciation
        }
        if amount < ComplianceConstants.smallDepreciableAssetThreshold,
           acquisitionDate <= ComplianceConstants.smallDepreciableExpiry {
            return .smallAmountFullExpense
        }
        return .normalDepreciation
    }

    private static func addBusinessDays(_ date: Date, days: Int, calendar: Calendar) -> Date {
        var current = date
        var remaining = days
        while remaining > 0 {
            current = calendar.date(byAdding: .day, value: 1, to: current)!
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 {
                remaining -= 1
            }
        }
        return current
    }
}
