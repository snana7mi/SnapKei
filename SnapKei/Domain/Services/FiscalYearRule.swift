import Foundation

/// 仕訳の年度判定の単一定義。個人事業主の会計期間は暦年固定（所得税法）。
/// 月次集計・決算書（KessanshoService 等）と同じ JST 基準で年を決める。
nonisolated public enum FiscalYearRule {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    public static func year(for date: Date) -> Int {
        calendar.component(.year, from: date)
    }
}
