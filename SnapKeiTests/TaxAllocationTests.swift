import Foundation
import Testing
@testable import SnapKei

@Suite("TaxAllocation")
struct TaxAllocationTests {

    @Test func allocate_preservesInclEqualsExclPlusTax() {
        // ¥1,000 tax-included @10% (excl 909), 80% business use.
        // Old code floored tax independently → 800/727/72 (727+72=799 ≠ 800). Must hold the invariant.
        let r = TaxAllocation.allocate(total: 1_000, excludingTax: 909, rate: 0.8)
        #expect(r.total == r.excludingTax + r.tax)
        #expect(r.total == 800)
        #expect(r.excludingTax == 727)
        #expect(r.tax == 73)
    }

    @Test func allocate_fullRate_unchanged() {
        let r = TaxAllocation.allocate(total: 1_100, excludingTax: 1_000, rate: 1.0)
        #expect(r.total == 1_100)
        #expect(r.excludingTax == 1_000)
        #expect(r.tax == 100)
    }

    @Test func allocate_invariantHoldsAcrossRates() {
        for percent in 1...100 {
            let r = TaxAllocation.allocate(total: 1_234, excludingTax: 1_122, rate: Double(percent) / 100.0)
            #expect(r.total == r.excludingTax + r.tax)
        }
    }
}
