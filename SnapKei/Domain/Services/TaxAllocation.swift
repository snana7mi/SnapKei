import Foundation

/// 家事按分: scales a tax-inclusive amount by the business-use rate while preserving the
/// bookkeeping invariant `total == excludingTax + tax`. The consumption-tax portion is the
/// residual of the two independently-floored figures so rounding can never break the identity.
public enum TaxAllocation {
    public struct Result: Equatable, Sendable {
        public let total: Int
        public let excludingTax: Int
        public let tax: Int
    }

    public static func allocate(total: Int, excludingTax: Int, rate: Double) -> Result {
        let allocatedTotal = Int((Double(total) * rate).rounded(.down))
        let allocatedExcludingTax = Int((Double(excludingTax) * rate).rounded(.down))
        return Result(
            total: allocatedTotal,
            excludingTax: allocatedExcludingTax,
            tax: allocatedTotal - allocatedExcludingTax
        )
    }
}
