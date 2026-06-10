import Foundation

/// Well-known account codes from accounts_seed.json used by reporting and closing services.
nonisolated public enum AccountCode {
    public static let cash = "1110"
    public static let bankDeposit = "1210"
    public static let checkingDeposit = "1220"
    public static let equipment = "1610"
    public static let accumulatedDepreciation = "1710"
    public static let payable = "2210"
    public static let capital = "3110"
    public static let ownerLoan = "3210"
    public static let ownerDraw = "3220"
    public static let salesRevenue = "4110"
    public static let depreciationExpense = "5230"
    public static let rent = "5180"
}

public extension PaymentMethod {
    /// 経費仕訳の貸方科目デフォルト。一意に決まらない支払方法は nil（選択中の科目を維持）。
    var defaultCreditAccountCode: String? {
        switch self {
        case .cash: AccountCode.cash
        case .creditCard: AccountCode.payable
        case .bankTransfer: AccountCode.bankDeposit
        case .ownerLoan: AccountCode.ownerLoan
        case .accountsPayable: AccountCode.payable
        case .ownerWithdraw, .other: nil
        }
    }
}
