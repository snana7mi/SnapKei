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

    /// 年度内の日付範囲（JST、1/1 00:00:00 〜 12/31 23:59:59）。
    /// 編集フォームの DatePicker が跨年変更を物理的に禁止するために使う。
    public static func dateRange(for year: Int) -> ClosedRange<Date> {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(
            from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
        return start...end
    }
}
