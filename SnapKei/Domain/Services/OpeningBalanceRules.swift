import Foundation

/// 期首残高の編集可否と符号規約の単一定義。
/// ストレージは借方プラス（資産 +、負債/資本 −）。UI は常に正数で入出力する。
nonisolated public enum OpeningBalanceRules {
    /// 資産型だが貸方性質（コントラ）の科目。正の入力を負で保存する。
    public static let contraAssetCodes: Set<String> = [AccountCode.accumulatedDepreciation]

    /// 編集対象外: 元入金（adjustCapitalToBalance が自動調整）、
    /// 事業主貸/借（年度境界で元入金へ集約され期首は常に0）。
    private static let excludedCodes: Set<String> = [
        AccountCode.capital, AccountCode.ownerLoan, AccountCode.ownerDraw,
    ]

    public static func isEditable(code: String, type: AccountType) -> Bool {
        guard [.asset, .liability, .equity].contains(type) else { return false }
        return !excludedCodes.contains(code)
    }

    public static func storedAmount(entered: Int, code: String, type: AccountType) -> Int {
        storedSign(code: code, type: type) * entered
    }

    public static func displayAmount(stored: Int, code: String, type: AccountType) -> Int {
        storedSign(code: code, type: type) * stored
    }

    private static func storedSign(code: String, type: AccountType) -> Int {
        if contraAssetCodes.contains(code) { return -1 }
        return type == .asset ? 1 : -1
    }
}
