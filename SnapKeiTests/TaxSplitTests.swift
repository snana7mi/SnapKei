import Testing
@testable import SnapKei

@Suite("TaxSplit")
struct TaxSplitTests {

    @Test func taxIncluded_10pct() {
        let r = TaxSplit.split(amount: 11_000, mode: .taxIncluded, rate: 0.10)
        #expect(r.total == 11_000)
        #expect(r.excludingTax == 10_000)
        #expect(r.tax == 1_000)
    }

    @Test func taxExcluded_10pct() {
        let r = TaxSplit.split(amount: 10_000, mode: .taxExcluded, rate: 0.10)
        #expect(r.total == 11_000)
        #expect(r.excludingTax == 10_000)
        #expect(r.tax == 1_000)
    }

    @Test func taxIncluded_roundsExclDown_inclStaysConsistent() {
        let r = TaxSplit.split(amount: 101, mode: .taxIncluded, rate: 0.10)
        #expect(r.excludingTax == 91)
        #expect(r.tax == 10)
        #expect(r.total == r.excludingTax + r.tax)
    }

    @Test func zeroRate_passesThrough() {
        let r = TaxSplit.split(amount: 5_000, mode: .taxIncluded, rate: 0)
        #expect(r.total == 5_000)
        #expect(r.excludingTax == 5_000)
        #expect(r.tax == 0)
    }

    @Test func taxIncluded_exactIntegerMath_onRoundAmounts() {
        // 浮動小数の floor(110000/1.1)=99999 のような ¥1 ズレを許さない。
        let r = TaxSplit.split(amount: 110_000, mode: .taxIncluded, rate: 0.10)
        #expect(r.excludingTax == 100_000)
        #expect(r.tax == 10_000)

        let r2 = TaxSplit.split(amount: 1_100, mode: .taxIncluded, rate: 0.10)
        #expect(r2.excludingTax == 1_000)
        #expect(r2.tax == 100)

        let r8 = TaxSplit.split(amount: 1_080, mode: .taxIncluded, rate: 0.08)
        #expect(r8.excludingTax == 1_000)
        #expect(r8.tax == 80)
    }

    @Test func taxRate_perCategory() {
        #expect(TaxCategory.standard10.taxRate == 0.10)
        #expect(TaxCategory.reduced8.taxRate == 0.08)
        #expect(TaxCategory.nonTaxable.taxRate == 0)
        #expect(TaxCategory.outOfScope.taxRate == 0)
    }
}
