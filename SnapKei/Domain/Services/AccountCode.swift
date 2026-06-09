import Foundation

/// Well-known account codes from accounts_seed.json used by reporting and closing services.
public enum AccountCode {
    public static let cash = "1110"
    public static let equipment = "1610"
    public static let accumulatedDepreciation = "1710"
    public static let capital = "3110"
    public static let ownerLoan = "3210"
    public static let ownerDraw = "3220"
    public static let depreciationExpense = "5230"
}
