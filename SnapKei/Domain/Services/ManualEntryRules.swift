import Foundation

/// 手動仕訳の三モード。
public enum ManualEntryKind: String, CaseIterable, Sendable {
    case income
    case expense
    case transfer
}

/// 手動仕訳のモード別科目制約と入力検証の単一定義（View から分離してテスト可能に）。
public enum ManualEntryRules {
    public enum Issue: Equatable, Sendable {
        case invalidAmount
        case missingCounterparty
        case missingDescription
        case sameAccount
        case debitTypeNotAllowed
        case creditTypeNotAllowed
        case invalidAllocation
        case capitalAccountNotAllowed
        case equityPairNotAllowed
    }

    /// 仕訳の分類（集計画面が 収入/支出/振替 を区別するための単一定義）。
    /// 収益科目が絡めば収入（借方側は値引・返品）、費用科目が絡めば支出、それ以外は振替。
    public static func kind(debitType: AccountType?, creditType: AccountType?) -> ManualEntryKind {
        if debitType == .revenue || creditType == .revenue { return .income }
        if debitType == .expense || creditType == .expense { return .expense }
        return .transfer
    }

    public static func allowedDebitTypes(for kind: ManualEntryKind) -> Set<AccountType> {
        switch kind {
        case .income: [.asset]
        case .expense: [.expense]
        case .transfer: Set(AccountType.allCases)
        }
    }

    public static func allowedCreditTypes(for kind: ManualEntryKind) -> Set<AccountType> {
        switch kind {
        case .income: [.revenue]
        case .expense: [.asset, .liability, .equity]
        case .transfer: Set(AccountType.allCases)
        }
    }

    public static func validate(
        kind: ManualEntryKind,
        debitCode: String,
        debitType: AccountType?,
        creditCode: String,
        creditType: AccountType?,
        amount: Int,
        counterparty: String,
        description: String,
        allocationRate: Double = 1.0
    ) -> [Issue] {
        var issues: [Issue] = []
        if amount <= 0 { issues.append(.invalidAmount) }
        if counterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingCounterparty)
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingDescription)
        }
        if debitCode == creditCode { issues.append(.sameAccount) }
        if debitType.map({ !allowedDebitTypes(for: kind).contains($0) }) ?? true {
            issues.append(.debitTypeNotAllowed)
        }
        if creditType.map({ !allowedCreditTypes(for: kind).contains($0) }) ?? true {
            issues.append(.creditTypeNotAllowed)
        }
        if kind == .expense, allocationRate <= 0 {
            // 業務割合 0% の経費は計上対象外（¥0 仕訳を作らせない）。
            issues.append(.invalidAllocation)
        }
        if debitCode == AccountCode.capital || creditCode == AccountCode.capital {
            // 元入金は期中に動かさない（年次締めの繰越のみが触る）。
            issues.append(.capitalAccountNotAllowed)
        }
        if kind == .transfer, debitType == .equity, creditType == .equity {
            // 事業主貸/借同士の振替は実取引が無く、貸借対照表を両建てで膨らませるだけ。
            issues.append(.equityPairNotAllowed)
        }
        return issues
    }

    /// 収入モードの入金先科目から支払方法を導出する。
    public static func paymentMethod(forIncomeDebit code: String) -> PaymentMethod {
        switch code {
        case AccountCode.cash: .cash
        case AccountCode.bankDeposit, AccountCode.checkingDeposit: .bankTransfer
        default: .other
        }
    }
}
