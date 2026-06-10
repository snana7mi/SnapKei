# SnapKei 手動仕訳入力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** レシートなしの手動仕訳入力（収入/支出/振替の三モード誘導型）を追加し、売上記録を解禁する。

**Architecture:** ドメイン層に `ManualEntryRules`（モード別科目制約＋検証）と `TaxSplit`（ConfirmationForm から抽出する税分解の単一定義）を TDD で追加。`ManualEntryView` は SwiftUI Form で、保存は既存 `SwiftDataExpenseRepository.create`（年度ロック・連番・監査ログ・同期通知込み）。入口は撮影タブの「手動入力」ボタンと一覧タブの「+」の2箇所。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing（`import Testing`, `#expect`）。`SnapKei/` 配下は自動インクルード（pbxproj 編集不要）。

**Spec reference:** `docs/superpowers/specs/2026-06-10-snapkei-manual-entry-design.md`

**User preferences carried forward:**
- Do NOT `git push`. Do NOT `git commit` without explicit user confirmation（コミット手順は checkpoint 提案のみ）。
- コード変更タスクの最後に必ずフルテストを実行。

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Baseline before this plan: `** TEST SUCCEEDED **`, 169 tests / 39 suites.

---

## File Structure

```
SnapKei/
├── Domain/Services/
│   ├── TaxSplit.swift               [CREATE — 税込/税抜分解 + TaxCategory.taxRate 共有化]
│   ├── ManualEntryRules.swift       [CREATE — モード・科目制約・検証]
│   └── AccountCode.swift            [MODIFY — checkingDeposit/salesRevenue 追加]
├── Data/Settings/
│   └── DeviceID.swift               [CREATE — deviceID() 重複2箇所の共有化]
└── Presentation/
    ├── ManualEntry/ManualEntryView.swift  [CREATE]
    ├── Capture/CaptureView.swift          [MODIFY — 手動入力ボタン]
    ├── Capture/ConfirmationForm.swift     [MODIFY — TaxSplit へ差し替え]
    ├── ExpenseList/ExpenseListView.swift  [MODIFY — toolbar「+」, DeviceID]
    └── Home/HomeView.swift                [MODIFY — DeviceID]
SnapKeiTests/
├── TaxSplitTests.swift              [CREATE]
└── ManualEntryRulesTests.swift      [CREATE]
```

---

## Task 1: TaxSplit（税分解の単一定義）

**Files:**
- Create: `SnapKei/Domain/Services/TaxSplit.swift`
- Modify: `SnapKei/Presentation/Capture/ConfirmationForm.swift`（save() の分解ロジックと private TaxCategory extension を置換）
- Test: `SnapKeiTests/TaxSplitTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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

    @Test func taxRate_perCategory() {
        #expect(TaxCategory.standard10.taxRate == 0.10)
        #expect(TaxCategory.reduced8.taxRate == 0.08)
        #expect(TaxCategory.nonTaxable.taxRate == 0)
        #expect(TaxCategory.outOfScope.taxRate == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild ... -only-testing:SnapKeiTests/TaxSplitTests test`（standard command の派生）
Expected: compile failure — `TaxSplit` 不存在、`TaxCategory.taxRate` はテストターゲットから不可視（ConfirmationForm 内 private extension のため）。

- [ ] **Step 3: Implement TaxSplit.swift**

```swift
import Foundation

/// 税込/税抜入力から (総額, 税抜額, 消費税) を導く単一定義。
/// ConfirmationForm（レシート確認）と ManualEntryView（手動仕訳）が共用する。
public enum TaxSplit {
    public static func split(
        amount: Int,
        mode: PriceEntryMode,
        rate: Double
    ) -> (total: Int, excludingTax: Int, tax: Int) {
        if mode == .taxIncluded {
            let excludingTax = Int((Double(amount) / (1 + rate)).rounded(.down))
            return (amount, excludingTax, amount - excludingTax)
        } else {
            let tax = Int((Double(amount) * rate).rounded(.down))
            return (amount + tax, amount, tax)
        }
    }
}

public extension TaxCategory {
    /// 税区分の税率。TaxSplit と組で使う。
    var taxRate: Double {
        switch self {
        case .standard10: 0.10
        case .reduced8: 0.08
        case .nonTaxable, .outOfScope: 0
        }
    }
}
```

- [ ] **Step 4: Switch ConfirmationForm to TaxSplit**

`ConfirmationForm.save()` の分解ブロックを置換:

```swift
    private func save() {
        commitAllocationPercent()
        guard let amount = Int(amountIncludingTaxText) else { return }
        let split = TaxSplit.split(amount: amount, mode: priceEntryMode, rate: taxCategory.taxRate)
        let amountExcludingTax = split.excludingTax
        let consumptionTax = split.tax
        let total = split.total
```

（元の `if priceEntryMode == .taxIncluded { ... } else { ... }` ブロックを削除。）

ファイル末尾の private extension を削除:

```swift
private extension TaxCategory {
    var taxRate: Double { ... }
}
```

- [ ] **Step 5: Run tests to verify GREEN**

Run standard test command. Expected: `** TEST SUCCEEDED **`、新規 5 テスト、既存テスト無傷。

- [ ] **Step 6: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/TaxSplit.swift SnapKei/Presentation/Capture/ConfirmationForm.swift SnapKeiTests/TaxSplitTests.swift
git commit -m "refactor: extract TaxSplit as single tax-decomposition rule"
```

---

## Task 2: ManualEntryRules + AccountCode 定数

**Files:**
- Create: `SnapKei/Domain/Services/ManualEntryRules.swift`
- Modify: `SnapKei/Domain/Services/AccountCode.swift`
- Test: `SnapKeiTests/ManualEntryRulesTests.swift`

- [ ] **Step 1: Add account code constants**

`AccountCode` に追加（`bankDeposit` の直後・`payable` の前後関係はコード順）:

```swift
    public static let checkingDeposit = "1220"
    public static let salesRevenue = "4110"
```

- [ ] **Step 2: Write the failing tests**

```swift
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

    @Test func paymentMethod_derivedFromIncomeDebitAccount() {
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.cash) == .cash)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.bankDeposit) == .bankTransfer)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: AccountCode.checkingDeposit) == .bankTransfer)
        #expect(ManualEntryRules.paymentMethod(forIncomeDebit: "1310") == .other)
    }
}
```

- [ ] **Step 3: Run tests to verify RED**

Expected: compile failure — `ManualEntryRules` / `ManualEntryKind` 不存在。

- [ ] **Step 4: Implement ManualEntryRules.swift**

```swift
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
        description: String
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
```

- [ ] **Step 5: Run tests to verify GREEN**

Run standard test command. Expected: `** TEST SUCCEEDED **`、新規 7 テスト。

- [ ] **Step 6: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/ManualEntryRules.swift SnapKei/Domain/Services/AccountCode.swift SnapKeiTests/ManualEntryRulesTests.swift
git commit -m "feat: manual-entry mode rules and validation"
```

---

## Task 3: DeviceID 共有化 + ManualEntryView

**Files:**
- Create: `SnapKei/Data/Settings/DeviceID.swift`
- Create: `SnapKei/Presentation/ManualEntry/ManualEntryView.swift`
- Modify: `SnapKei/Presentation/ExpenseList/ExpenseListView.swift:97-99`（private deviceID() 削除）
- Modify: `SnapKei/Presentation/Home/HomeView.swift:127-129`（同上）

View のため単体テストなし（リポジトリ慣例: build + smoke）。

- [ ] **Step 1: Create DeviceID.swift**

```swift
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 監査ログ・同期で使う端末識別子の単一定義（View ごとの私有コピーを置換）。
public enum DeviceID {
    public static var current: String {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        "unknown"
        #endif
    }
}
```

- [ ] **Step 2: Replace the two private copies**

`ExpenseListView` / `HomeView` の `private func deviceID() -> String { ... }` を削除し、呼び出し箇所 `deviceID()` を `DeviceID.current` に置換（ExpenseListView は 2 箇所、HomeView は使用箇所を grep で確認して置換）。

- [ ] **Step 3: Create ManualEntryView.swift**

```swift
import SwiftData
import SwiftUI

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var kind: ManualEntryKind = .income
    @State private var transactionDate = Date()
    @State private var counterpartyName = ""
    @State private var transactionDescription = ""
    @State private var amountText = ""
    @State private var taxCategory = TaxCategory.standard10
    @State private var priceEntryMode = PriceEntryMode.taxIncluded
    @State private var debitAccountCode = AccountCode.bankDeposit
    @State private var creditAccountCode = AccountCode.salesRevenue
    @State private var paymentMethod = PaymentMethod.ownerLoan
    @State private var userEditedCreditAccount = false
    @State private var invoiceRegistrationNumber = ""
    @State private var businessAllocationRate = 1.0
    @State private var businessAllocationPercentText = "100"
    @FocusState private var allocationFieldFocused: Bool
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種別", selection: $kind) {
                        Text("収入").tag(ManualEntryKind.income)
                        Text("支出").tag(ManualEntryKind.expense)
                        Text("振替").tag(ManualEntryKind.transfer)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if kind == .transfer {
                        Text("売掛金の回収・借入・事業主貸/借の振替など、収入・支出以外の仕訳に使います。")
                    }
                }

                InputDeadlineWarning(transactionDate: transactionDate)

                Section("取引") {
                    DatePicker("取引日", selection: $transactionDate, displayedComponents: .date)
                    TextField("取引先", text: $counterpartyName)
                    TextField("内容", text: $transactionDescription)
                }

                Section("金額") {
                    TextField(kind == .transfer ? "金額" : "金額(税込/税抜)", text: $amountText)
                        .keyboardType(.numberPad)
                    if kind != .transfer {
                        Picker("税区分", selection: $taxCategory) {
                            Text("10%").tag(TaxCategory.standard10)
                            Text("8% 軽減").tag(TaxCategory.reduced8)
                            Text("非課税").tag(TaxCategory.nonTaxable)
                            Text("対象外").tag(TaxCategory.outOfScope)
                        }
                        Picker("入力方式", selection: $priceEntryMode) {
                            Text("税込").tag(PriceEntryMode.taxIncluded)
                            Text("税抜").tag(PriceEntryMode.taxExcluded)
                        }
                    }
                }

                Section("仕訳") {
                    Picker(kind == .income ? "入金先" : "借方科目", selection: $debitAccountCode) {
                        ForEach(debitChoices) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    Picker(kind == .income ? "科目" : "貸方科目", selection: creditSelectionBinding) {
                        ForEach(creditChoices) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    if kind == .expense {
                        Picker("支払方法", selection: $paymentMethod) {
                            Text("現金").tag(PaymentMethod.cash)
                            Text("クレジット").tag(PaymentMethod.creditCard)
                            Text("銀行振込").tag(PaymentMethod.bankTransfer)
                            Text("事業主借").tag(PaymentMethod.ownerLoan)
                            Text("その他").tag(PaymentMethod.other)
                        }
                    }
                }

                if kind == .expense {
                    Section("インボイス") {
                        TextField("適格番号 (T+13桁)", text: $invoiceRegistrationNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    Section("家事按分") {
                        HStack {
                            Text("業務割合")
                            Spacer()
                            TextField("", text: $businessAllocationPercentText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($allocationFieldFocused)
                                .frame(width: 56)
                                .onChange(of: businessAllocationPercentText) { _, newValue in
                                    let filtered = newValue.filter(\.isNumber)
                                    if filtered != newValue {
                                        businessAllocationPercentText = filtered
                                    }
                                }
                                .onChange(of: allocationFieldFocused) { _, focused in
                                    if !focused { commitAllocationPercent() }
                                }
                                .onSubmit(commitAllocationPercent)
                            Text("%").foregroundStyle(.secondary)
                        }
                        if businessAllocationRate < 1, let amount = Int(amountText) {
                            Text("仕訳計上額: ¥\(Int(Double(amount) * businessAllocationRate))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("保存") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid)
                }
            }
            .navigationTitle("手動入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onChange(of: kind) { _, newKind in applyKindDefaults(newKind) }
            .onChange(of: paymentMethod) { _, newMethod in applyCreditDefault(for: newMethod) }
            .onChange(of: debitAccountCode) { _, newCode in
                if kind == .expense { applyAllocationDefault(forDebitCode: newCode) }
            }
            .alert(
                "保存できませんでした",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    // MARK: - Choices & validation

    private var debitChoices: [Account] {
        accounts.filter { $0.isActive && ManualEntryRules.allowedDebitTypes(for: kind).contains($0.accountType) }
    }

    private var creditChoices: [Account] {
        accounts.filter { $0.isActive && ManualEntryRules.allowedCreditTypes(for: kind).contains($0.accountType) }
    }

    private var isValid: Bool {
        ManualEntryRules.validate(
            kind: kind,
            debitCode: debitAccountCode,
            debitType: accountType(of: debitAccountCode),
            creditCode: creditAccountCode,
            creditType: accountType(of: creditAccountCode),
            amount: Int(amountText) ?? 0,
            counterparty: counterpartyName,
            description: transactionDescription
        ).isEmpty
    }

    private func accountType(of code: String) -> AccountType? {
        accounts.first { $0.code == code && $0.isActive }?.accountType
    }

    // MARK: - Mode defaults

    private func applyKindDefaults(_ newKind: ManualEntryKind) {
        userEditedCreditAccount = false
        switch newKind {
        case .income:
            debitAccountCode = preferredCode(AccountCode.bankDeposit, in: debitChoices)
            creditAccountCode = preferredCode(AccountCode.salesRevenue, in: creditChoices)
            taxCategory = .standard10
        case .expense:
            debitAccountCode = preferredCode("5110", in: debitChoices)
            paymentMethod = .ownerLoan
            creditAccountCode = preferredCode(AccountCode.ownerLoan, in: creditChoices)
            taxCategory = .standard10
            applyAllocationDefault(forDebitCode: debitAccountCode)
        case .transfer:
            debitAccountCode = preferredCode(AccountCode.cash, in: debitChoices)
            creditAccountCode = preferredCode(AccountCode.bankDeposit, in: creditChoices)
            taxCategory = .outOfScope
        }
    }

    /// 希望コードが選択肢に存在すればそれ、無ければ先頭（科目表が同期でカスタム化していても破綻しない）。
    private func preferredCode(_ preferred: String, in choices: [Account]) -> String {
        choices.contains { $0.code == preferred } ? preferred : (choices.first?.code ?? preferred)
    }

    /// 貸方科目 Picker の手動変更を記録し、以後 applyCreditDefault が上書きしないようにする。
    private var creditSelectionBinding: Binding<String> {
        Binding(
            get: { creditAccountCode },
            set: { newValue in
                creditAccountCode = newValue
                userEditedCreditAccount = true
            }
        )
    }

    private func applyCreditDefault(for method: PaymentMethod) {
        guard kind == .expense else { return }
        if !userEditedCreditAccount,
           let mapped = method.defaultCreditAccountCode,
           creditChoices.contains(where: { $0.code == mapped }) {
            creditAccountCode = mapped
        }
    }

    private func applyAllocationDefault(forDebitCode code: String) {
        guard let account = accounts.first(where: { $0.code == code }) else { return }
        businessAllocationRate = account.defaultBusinessAllocationRate
        businessAllocationPercentText = String(Int((account.defaultBusinessAllocationRate * 100).rounded()))
    }

    private func commitAllocationPercent() {
        let clamped = max(0, min(100, Int(businessAllocationPercentText) ?? 0))
        businessAllocationPercentText = String(clamped)
        businessAllocationRate = Double(clamped) / 100.0
    }

    // MARK: - Save

    private func save() {
        commitAllocationPercent()
        guard let amount = Int(amountText), amount > 0 else { return }
        let effectiveTaxCategory = kind == .transfer ? TaxCategory.outOfScope : taxCategory
        let split = TaxSplit.split(amount: amount, mode: priceEntryMode, rate: effectiveTaxCategory.taxRate)

        let allocationRate = kind == .expense ? businessAllocationRate : 1.0
        let allocation = TaxAllocation.allocate(total: split.total, excludingTax: split.excludingTax, rate: allocationRate)

        let invoice = invoiceRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = kind == .expense && invoice.hasPrefix("T") && invoice.count == 14

        let entry = JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: transactionDate),
            transactionDate: transactionDate,
            isLateEntry: ComplianceService.daysUntilScanDeadline(receiptDate: transactionDate) < 0,
            debitAccountCode: debitAccountCode,
            creditAccountCode: creditAccountCode,
            amountIncludingTax: allocation.total,
            amountExcludingTax: allocation.excludingTax,
            consumptionTax: allocation.tax,
            taxCategory: effectiveTaxCategory,
            priceEntryMode: priceEntryMode,
            paymentMethod: effectivePaymentMethod,
            counterpartyName: counterpartyName,
            invoiceRegistrationNumber: kind == .expense && !invoice.isEmpty ? invoice : nil,
            invoiceQualified: qualified,
            transitionalMeasureRate: kind == .expense
                ? ComplianceService.transitionalRate(qualified: qualified, transactionDate: transactionDate)
                : 1.0,
            transactionDescription: transactionDescription,
            businessAllocationRate: allocationRate,
            originalAmountIncludingTax: allocationRate < 1 ? split.total : nil,
            sourceType: .manual
        )

        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.create(entry, reason: nil)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var effectivePaymentMethod: PaymentMethod {
        switch kind {
        case .income: ManualEntryRules.paymentMethod(forIncomeDebit: debitAccountCode)
        case .expense: paymentMethod
        case .transfer: .other
        }
    }
}
```

- [ ] **Step 4: Build to verify compile**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Data/Settings/DeviceID.swift SnapKei/Presentation/ManualEntry/ManualEntryView.swift SnapKei/Presentation/ExpenseList/ExpenseListView.swift SnapKei/Presentation/Home/HomeView.swift
git commit -m "feat: manual journal entry form (income/expense/transfer)"
```

---

## Task 4: 入口2箇所 + フルテスト

**Files:**
- Modify: `SnapKei/Presentation/Capture/CaptureView.swift`（idle ステージに手動入力ボタン）
- Modify: `SnapKei/Presentation/ExpenseList/ExpenseListView.swift`（toolbar「+」）

- [ ] **Step 1: CaptureView — 手動入力ボタン**

`@State private var showManualEntry = false` を追加し、idle ケースの `ImageSourcePicker(...)` の直後に:

```swift
                    Button { showManualEntry = true } label: {
                        Label("手動入力", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
```

外側（switch を含むコンテナ）に sheet を追加:

```swift
            .sheet(isPresented: $showManualEntry) { ManualEntryView() }
```

- [ ] **Step 2: ExpenseListView — toolbar「+」**

`@State private var showManualEntry = false` を追加し、`ToolbarItemGroup(placement: .topBarTrailing)` の先頭に:

```swift
                Button { showManualEntry = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("手動入力")
```

`listContent` の `.toolbar { ... }` の後に:

```swift
        .sheet(isPresented: $showManualEntry) { ManualEntryView() }
```

- [ ] **Step 3: Full test run**

Run standard test command. Expected: `** TEST SUCCEEDED **`, 181 tests（169 + TaxSplit 5 + ManualEntryRules 7）。

- [ ] **Step 4: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Presentation/Capture/CaptureView.swift SnapKei/Presentation/ExpenseList/ExpenseListView.swift
git commit -m "feat: manual entry entry-points (capture tab + list toolbar)"
```

---

## Task 5: Final verification

- [ ] **Step 1: Clean full test run**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 2: Manual smoke (simulator)**

- 撮影タブ →「手動入力」: 収入モードで売上 ¥330,000（税込/10%）を保存 → 一覧に出現、帳簿の損益計算書に売上反映。
- 一覧タブ「+」: 振替モードで 普通預金/売掛金 を保存 → 残高試算表で両建て確認。
- 支出モードで支払方法を切替 → 貸方科目が連動し、手動選択後は上書きされないこと。
- 閉鎖済み年度の日付で保存 → エラーアラート表示。

- [ ] **Step 3: Report results**

テスト/ビルド結果と逸脱を報告。push しない。コミットはユーザー確認後。

---

## Out-of-Scope（spec 参照）

既存仕訳の編集 / 定期仕訳 / 売掛・請求書管理 / 複合仕訳（1:N）。
