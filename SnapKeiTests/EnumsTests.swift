import Testing
@testable import SnapKei

@Suite("Enums raw values are stable (persistence keys)")
struct EnumsTests {

    @Test func taxCategoryRawValues() {
        #expect(TaxCategory.standard10.rawValue == "standard10")
        #expect(TaxCategory.reduced8.rawValue == "reduced8")
        #expect(TaxCategory.nonTaxable.rawValue == "nonTaxable")
        #expect(TaxCategory.outOfScope.rawValue == "outOfScope")
    }

    @Test func paymentMethodRawValues() {
        #expect(PaymentMethod.cash.rawValue == "cash")
        #expect(PaymentMethod.ownerLoan.rawValue == "ownerLoan")
        #expect(PaymentMethod.ownerWithdraw.rawValue == "ownerWithdraw")
        #expect(PaymentMethod.accountsPayable.rawValue == "accountsPayable")
    }

    @Test func recordSourceRawValues() {
        #expect(RecordSource.aiParsed.rawValue == "aiParsed")
        #expect(RecordSource.electronicTransaction.rawValue == "electronicTransaction")
        #expect(RecordSource.depreciation.rawValue == "depreciation")
    }

    @Test func assetTreatmentRawValues() {
        #expect(AssetTreatment.normalDepreciation.rawValue == "normalDepreciation")
        #expect(AssetTreatment.lumpSumDepreciation.rawValue == "lumpSumDepreciation")
        #expect(AssetTreatment.smallAmountFullExpense.rawValue == "smallAmountFullExpense")
    }

    @Test func depreciationMethodRawValues() {
        #expect(DepreciationMethod.straightLine.rawValue == "straightLine")
        #expect(DepreciationMethod.decliningBalance.rawValue == "decliningBalance")
    }

    @Test func aiChannelRawValues() {
        #expect(AIChannel.directApiKey.rawValue == "directApiKey")
        #expect(AIChannel.builtInProxy.rawValue == "builtInProxy")
    }

    @Test func apiFormatRawValues() {
        #expect(APIFormat.openAI.rawValue == "openAI")
        #expect(APIFormat.anthropic.rawValue == "anthropic")
    }

    @Test func accountTypeRawValues() {
        #expect(AccountType.asset.rawValue == "asset")
        #expect(AccountType.expense.rawValue == "expense")
    }
}
