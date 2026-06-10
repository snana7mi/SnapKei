import Foundation

/// 税込/税抜入力から (総額, 税抜額, 消費税) を導く単一定義。
/// ConfirmationForm（レシート確認）と ManualEntryView（手動仕訳）が共用する。
public enum TaxSplit {
    public static func split(
        amount: Int,
        mode: PriceEntryMode,
        rate: Double
    ) -> (total: Int, excludingTax: Int, tax: Int) {
        // 浮動小数の除算は 110,000/1.1 = 99,999.99… のような ¥1 ズレを生むため整数演算で行う。
        let ratePercent = Int((rate * 100).rounded())
        if mode == .taxIncluded {
            let excludingTax = amount * 100 / (100 + ratePercent)
            return (amount, excludingTax, amount - excludingTax)
        } else {
            let tax = amount * ratePercent / 100
            return (amount + tax, amount, tax)
        }
    }
}

public extension TaxCategory {
    /// 税区分の税率。TaxSplit と組で使う。
    var taxRate: Double {
        switch self {
        case .standard10: 0.10
        case .reduced8: 0.08
        case .nonTaxable, .outOfScope: 0
        }
    }
}
