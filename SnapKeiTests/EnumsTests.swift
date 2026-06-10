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
        #expect(DepreciationMethod.allCases == [.straightLine])
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

@Suite("PaymentMethod → 貸方科目デフォルト")
struct PaymentMethodCreditAccountTests {

    @Test func mapsEachPaymentMethodToSeededCreditAccount() {
        #expect(PaymentMethod.cash.defaultCreditAccountCode == AccountCode.cash)
        #expect(PaymentMethod.creditCard.defaultCreditAccountCode == AccountCode.payable)
        #expect(PaymentMethod.bankTransfer.defaultCreditAccountCode == AccountCode.bankDeposit)
        #expect(PaymentMethod.ownerLoan.defaultCreditAccountCode == AccountCode.ownerLoan)
        #expect(PaymentMethod.accountsPayable.defaultCreditAccountCode == AccountCode.payable)
    }

    @Test func ambiguousMethodsHaveNoDefault() {
        // 事業主貸・その他は経費の貸方として一意に決まらないため、選択中の科目を維持する。
        #expect(PaymentMethod.ownerWithdraw.defaultCreditAccountCode == nil)
        #expect(PaymentMethod.other.defaultCreditAccountCode == nil)
    }
}
