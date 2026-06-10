import Testing
@testable import SnapKei

@Suite("ManualEntryRules")
struct ManualEntryRulesTests {

    @Test func allowedTypes_income() {
        #expect(ManualEntryRules.allowedDebitTypes(for: .income) == [.asset])
        #expect(ManualEntryRules.allowedCreditTypes(for: .income) == [.revenue])
    }

    @Test func allowedTypes_expense_matchConfirmationFormSemantics() {
        #expect(ManualEntryRules.allowedDebitTypes(for: .expense) == [.expense])
        #expect(ManualEntryRules.allowedCreditTypes(for: .expense) == [.asset, .liability, .equity])
    }

    @Test func allowedTypes_transfer_allowEverything() {
        #expect(ManualEntryRules.allowedDebitTypes(for: .transfer) == Set(AccountType.allCases))
        #expect(ManualEntryRules.allowedCreditTypes(for: .transfer) == Set(AccountType.allCases))
    }

    @Test func validate_passesForValidIncome() {
        let issues = ManualEntryRules.validate(
            kind: .income,
            debitCode: "1210", debitType: .asset,
            creditCode: "4110", creditType: .revenue,
            amount: 330_000, counterparty: "クライアントA", description: "Web制作費"
        )
        #expect(issues.isEmpty)
    }

    @Test func validate_collectsAllIssues() {
        let issues = ManualEntryRules.validate(
            kind: .income,
            debitCode: "4110", debitType: .revenue,
            creditCode: "4110", creditType: .revenue,
            amount: 0, counterparty: " ", description: ""
        )
        #expect(issues.contains(.invalidAmount))
        #expect(issues.contains(.missingCounterparty))
        #expect(issues.contains(.missingDescription))
        #expect(issues.contains(.sameAccount))
        #expect(issues.contains(.debitTypeNotAllowed))
    }

    @Test func validate_unknownAccountTypeIsNotAllowed() {
        let issues = ManualEntryRules.validate(
            kind: .transfer,
            debitCode: "9999", debitType: nil,
            creditCode: "1110", creditType: .asset,
            amount: 100, counterparty: "x", description: "y"
        )
        #expect(issues.contains(.debitTypeNotAllowed))
        #expect(!issues.contains(.creditTypeNotAllowed))
    }

    @Test func kind_classifiesEntriesByAccountTypes() {
        // 集計画面（ホーム/一覧）が仕訳を 収入/支出/振替 に分類するための単一定義。
        #expect(ManualEntryRules.kind(debitType: .asset, creditType: .revenue) == .income)
        #expect(ManualEntryRules.kind(debitType: .revenue, creditType: .asset) == .income)
        #expect(ManualEntryRules.kind(debitType: .expense, creditType: .equity) == .expense)
        #expect(ManualEntryRules.kind(debitType: .asset, creditType: .expense) == .expense)
        #expect(ManualEntryRules.kind(debitType: .asset, creditType: .asset) == .transfer)
        #expect(ManualEntryRules.kind(debitType: nil, creditType: .asset) == .transfer)
    }

    @Test func validate_zeroAllocationIsInvalidForExpense() {
        let issues = ManualEntryRules.validate(
            kind: .expense,
            debitCode: "5110", debitType: .expense,
            creditCode: "3210", creditType: .equity,
            amount: 1_000, counterparty: "x", description: "y",
            allocationRate: 0
        )
        #expect(issues.contains(.invalidAllocation))

        let incomeIssues = ManualEntryRules.validate(
            kind: .income,
            debitCode: "1210", debitType: .asset,
            creditCode: "4110", creditType: .revenue,
            amount: 1_000, counterparty: "x", description: "y",
            allocationRate: 0
        )
        #expect(!incomeIssues.contains(.invalidAllocation))
    }

    @Test func validate_transferBlocksCapitalAndEquityPair() {
        // 元入金は期中に動かさない（年次締めの繰越のみ）。事業主貸/借同士の振替も実取引が無い。
        let capital = ManualEntryRules.validate(
            kind: .transfer,
            debitCode: AccountCode.capital, debitType: .equity,
            creditCode: "1110", creditType: .asset,
            amount: 1_000, counterparty: "x", description: "y"
        )
        #expect(capital.contains(.capitalAccountNotAllowed))

        let equityPair = ManualEntryRules.validate(
            kind: .transfer,
            debitCode: AccountCode.ownerDraw, debitType: .equity,
            creditCode: AccountCode.ownerLoan, creditType: .equity,
            amount: 1_000, counterparty: "x", description: "y"
        )
        #expect(equityPair.contains(.equityPairNotAllowed))

        let ownerLoanToCash = ManualEntryRules.validate(
            kind: .transfer,
            debitCode: "1110", debitType: .asset,
            creditCode: AccountCode.ownerLoan, creditType: .equity,
            amount: 1_000, counterparty: "x", description: "y"
        )
        #expect(ownerLoanToCash.isEmpty)
    }

    @Test func paymentMethod_derivedFromIncomeDebitAccount() {
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.cash) == .cash)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.bankDeposit) == .bankTransfer)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.checkingDeposit) == .bankTransfer)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: "1310") == .other)
    }
}
