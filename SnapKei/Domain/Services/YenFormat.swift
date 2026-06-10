import Foundation

/// 円表示の単一定義。画面（KessanshoView 等）と出力 PDF が同じ書式を共有する。
public enum YenFormat {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    public static func string(_ amount: Int) -> String {
        formatter.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }
}
