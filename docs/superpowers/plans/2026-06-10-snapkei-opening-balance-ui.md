# SnapKei 期首残高 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 期首残高の閲覧・編集 UI（帳簿タブ）を追加し、初年度/移行ユーザーと引継ぎ固定資産の B/S 計上を可能にする。

**Architecture:** 符号規約と編集可否は `OpeningBalanceRules`（nonisolated, TDD）に単一定義。`OpeningBalanceStore` に `rows(fiscalYear:)` を追加（isAutoRolled 判定用）。`OpeningBalanceView` は編集コミットごとに `set` → `adjustCapitalToBalance`（元入金自動調整、既存）。締め済み年度は読み取り専用。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing。

**Spec reference:** `docs/superpowers/specs/2026-06-10-snapkei-opening-balance-design.md`

**Branch:** `opening-balance-ui`（作成済み）

**User preferences carried forward:** Do NOT push. Do NOT commit without explicit user confirmation. コード変更タスクの最後にフルテスト実行。

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Baseline: `** TEST SUCCEEDED **`, 216 tests / 43 suites（main = ec590f1）。

---

## File Structure

```
SnapKei/Domain/Services/OpeningBalanceRules.swift      [CREATE — 編集可否 + 符号変換]
SnapKei/Data/Persistence/OpeningBalanceStore.swift     [MODIFY — rows(fiscalYear:) 追加]
SnapKei/Presentation/Reports/OpeningBalanceView.swift  [CREATE]
SnapKei/Presentation/Reports/BooksView.swift           [MODIFY — NavigationLink 追加]
SnapKeiTests/OpeningBalanceRulesTests.swift            [CREATE]
SnapKeiTests/OpeningBalanceStoreTests.swift            [MODIFY — rows テスト追加]
```

---

## Task 1: OpeningBalanceRules

**Files:**
- Create: `SnapKei/Domain/Services/OpeningBalanceRules.swift`
- Test: `SnapKeiTests/OpeningBalanceRulesTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SnapKei

@Suite("OpeningBalanceRules")
struct OpeningBalanceRulesTests {

    @Test func editable_balanceSheetAccountsOnly() {
        #expect(OpeningBalanceRules.isEditable(code: "1110", type: .asset))
        #expect(OpeningBalanceRules.isEditable(code: "1710", type: .asset))
        #expect(OpeningBalanceRules.isEditable(code: "2310", type: .liability))
        #expect(!OpeningBalanceRules.isEditable(code: "4110", type: .revenue))
        #expect(!OpeningBalanceRules.isEditable(code: "5110", type: .expense))
    }

    @Test func editable_excludesCapitalAndOwnerAccounts() {
        // 元入金は自動調整、事業主貸/借は年度境界で元入金へ集約されるため期首は常に0。
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.capital, type: .equity))
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.ownerLoan, type: .equity))
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.ownerDraw, type: .equity))
    }

    @Test func storedAmount_signByAccountSide() {
        // ストレージは借方プラス: 資産 +、負債/資本 −。
        #expect(OpeningBalanceRules.storedAmount(entered: 100_000, code: "1110", type: .asset) == 100_000)
        #expect(OpeningBalanceRules.storedAmount(entered: 300_000, code: "2310", type: .liability) == -300_000)
        #expect(OpeningBalanceRules.storedAmount(entered: 50_000, code: "3110", type: .equity) == -50_000)
    }

    @Test func storedAmount_contraAsset1710_isNegative() {
        // 減価償却累計額は資産型だが貸方性質（コントラ）。正の入力を負で保存する。
        #expect(OpeningBalanceRules.storedAmount(entered: 120_000, code: "1710", type: .asset) == -120_000)
    }

    @Test func displayAmount_roundTripsStoredAmount() {
        let cases: [(Int, String, AccountType)] = [
            (250_000, "1110", .asset),
            (120_000, "1710", .asset),
            (300_000, "2310", .liability),
        ]
        for (entered, code, type) in cases {
            let stored = OpeningBalanceRules.storedAmount(entered: entered, code: code, type: type)
            #expect(OpeningBalanceRules.displayAmount(stored: stored, code: code, type: type) == entered)
        }
    }
}
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/OpeningBalanceRulesTests test 2>&1 | grep -E "error:|TEST FAILED" | head -4
```

Expected: compile failure — `OpeningBalanceRules` 不存在。

- [ ] **Step 3: Implement OpeningBalanceRules.swift**

```swift
import Foundation

/// 期首残高の編集可否と符号規約の単一定義。
/// ストレージは借方プラス（資産 +、負債/資本 −）。UI は常に正数で入出力する。
nonisolated public enum OpeningBalanceRules {
    /// 資産型だが貸方性質（コントラ）の科目。正の入力を負で保存する。
    public static let contraAssetCodes: Set<String> = [AccountCode.accumulatedDepreciation]

    /// 編集対象外: 元入金（adjustCapitalToBalance が自動調整）、
    /// 事業主貸/借（年度境界で元入金へ集約され期首は常に0）。
    private static let excludedCodes: Set<String> = [
        AccountCode.capital, AccountCode.ownerLoan, AccountCode.ownerDraw,
    ]

    public static func isEditable(code: String, type: AccountType) -> Bool {
        guard [.asset, .liability, .equity].contains(type) else { return false }
        return !excludedCodes.contains(code)
    }

    public static func storedAmount(entered: Int, code: String, type: AccountType) -> Int {
        storedSign(code: code, type: type) * entered
    }

    public static func displayAmount(stored: Int, code: String, type: AccountType) -> Int {
        storedSign(code: code, type: type) * stored
    }

    private static func storedSign(code: String, type: AccountType) -> Int {
        if contraAssetCodes.contains(code) { return -1 }
        return type == .asset ? 1 : -1
    }
}
```

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/OpeningBalanceRules.swift SnapKeiTests/OpeningBalanceRulesTests.swift
git commit -m "feat: opening-balance editability and sign rules"
```

---

## Task 2: OpeningBalanceStore.rows(fiscalYear:)

**Files:**
- Modify: `SnapKei/Data/Persistence/OpeningBalanceStore.swift`
- Test: `SnapKeiTests/OpeningBalanceStoreTests.swift`

- [ ] **Step 1: Write the failing test（既存スイートに追加。既存の makeStore/コンテナ取得ヘルパーの命名を確認してそれに合わせる）**

```swift
    @MainActor
    @Test func rows_returnsLiveRowsWithAutoRolledFlag() throws {
        let store = try makeStore() // 既存ヘルパー名に合わせる
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000, isAutoRolled: true)
        try store.set(fiscalYear: 2026, accountCode: "2310", amount: -300_000)
        try store.set(fiscalYear: 2026, accountCode: "1210", amount: 50_000)
        try store.set(fiscalYear: 2026, accountCode: "1210", amount: 0) // 0 → soft delete
        try store.set(fiscalYear: 2025, accountCode: "1110", amount: 1) // 他年度

        let rows = try store.rows(fiscalYear: 2026)

        #expect(rows.map(\.accountCode).sorted() == ["1110", "2310"])
        #expect(rows.first { $0.accountCode == "1110" }?.isAutoRolled == true)
        #expect(rows.first { $0.accountCode == "2310" }?.isAutoRolled == false)
    }
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/OpeningBalanceStoreTests test 2>&1 | grep -E "error:|TEST FAILED" | head -4
```

Expected: compile failure — `rows` 不存在。

- [ ] **Step 3: Implement rows(fiscalYear:)（balances の直後に追加）**

```swift
    /// 生の行（isAutoRolled 含む）。UI が自動繰越バナーを出すために使う。
    public func rows(fiscalYear: Int) throws -> [OpeningBalance] {
        try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        ))
    }
```

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Data/Persistence/OpeningBalanceStore.swift SnapKeiTests/OpeningBalanceStoreTests.swift
git commit -m "feat: expose opening-balance rows with auto-rolled flag"
```

---

## Task 3: OpeningBalanceView + BooksView 接線

**Files:**
- Create: `SnapKei/Presentation/Reports/OpeningBalanceView.swift`
- Modify: `SnapKei/Presentation/Reports/BooksView.swift`（帳簿セクション）

View のため単体テストなし（build + smoke）。

- [ ] **Step 1: Create OpeningBalanceView.swift**

```swift
import SwiftData
import SwiftUI

/// 期首残高の閲覧・編集。コミットごとに元入金を自動調整（adjustCapitalToBalance）。
/// 締め済み年度は読み取り専用。ユーザーは常に正数で入力し、符号は OpeningBalanceRules が扱う。
struct OpeningBalanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var closures: [FiscalYearClosure]

    let fiscalYear: Int

    @State private var storedByCode: [String: Int] = [:]
    @State private var hasAutoRolled = false
    @State private var drafts: [String: String] = [:]
    @State private var errorMessage: String?
    @FocusState private var focusedCode: String?

    var body: some View {
        List {
            if isClosed {
                Section {
                    Label("締め済みの年度です。年次締めから再オープンすると編集できます。", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if hasAutoRolled {
                Section {
                    Label("前年の年次締めから自動繰越された値です。編集すると手動値になり、前年を再締めすると上書きされます。", systemImage: "arrow.uturn.forward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            summarySection
            accountSection("資産", type: .asset)
            accountSection("負債", type: .liability)
            accountSection("資本（元入金・事業主貸借を除く）", type: .equity)

            Section {
                Text("開業初年度は通常入力不要です。アプリ導入前から事業を行っている場合は前年末時点の残高を入力してください。引継ぎ固定資産は取得価額を 工具器具備品、償却累計額を 減価償却累計額（控除）に入力します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "期首残高 \(fiscalYear)年"))
        .task { reload() }
        .onChange(of: focusedCode) { previous, _ in
            if let previous { commit(code: previous) }
        }
        .alert(
            "保存できませんでした",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("サマリー") {
            row("資産合計", YenFormat.string(assetTotal))
            row("負債合計", YenFormat.string(liabilityTotal))
            HStack {
                Text("元入金（自動調整）")
                Spacer()
                Text(YenFormat.string(capitalDisplay))
                    .foregroundStyle(capitalDisplay < 0 ? .orange : .secondary)
                    .font(.body.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            if capitalDisplay < 0 {
                Label("元入金がマイナス（債務超過）です。入力値を確認してください。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func accountSection(_ title: String, type: AccountType) -> some View {
        let rows = editableAccounts(of: type)
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { account in
                    balanceRow(account)
                }
            }
        }
    }

    private func balanceRow(_ account: Account) -> some View {
        HStack {
            Text(label(for: account))
            Spacer()
            if isClosed {
                Text(YenFormat.string(displayValue(for: account)))
                    .foregroundStyle(.secondary)
                    .font(.body.monospacedDigit())
            } else {
                TextField("0", text: draftBinding(for: account.code))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .focused($focusedCode, equals: account.code)
                    .onSubmit { commit(code: account.code) }
                    .font(.body.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived values

    private var isClosed: Bool {
        closures.contains { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
    }

    private var typeByCode: [String: AccountType] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.accountType) })
    }

    private func editableAccounts(of type: AccountType) -> [Account] {
        accounts.filter { $0.isActive && $0.accountType == type && OpeningBalanceRules.isEditable(code: $0.code, type: $0.accountType) }
    }

    private func label(for account: Account) -> String {
        OpeningBalanceRules.contraAssetCodes.contains(account.code)
            ? "\(account.nameJa)（控除・プラス入力）"
            : account.nameJa
    }

    private func displayValue(for account: Account) -> Int {
        OpeningBalanceRules.displayAmount(
            stored: storedByCode[account.code] ?? 0,
            code: account.code,
            type: account.accountType
        )
    }

    private var assetTotal: Int {
        storedByCode.reduce(0) { sum, item in
            typeByCode[item.key] == .asset ? sum + item.value : sum
        }
    }

    private var liabilityTotal: Int {
        -storedByCode.reduce(0) { sum, item in
            typeByCode[item.key] == .liability ? sum + item.value : sum
        }
    }

    /// 元入金は貸方プラス表示（stored は借方プラスのため反転）。マイナス = 債務超過。
    private var capitalDisplay: Int {
        -(storedByCode[AccountCode.capital] ?? 0)
    }

    // MARK: - Editing

    private func draftBinding(for code: String) -> Binding<String> {
        Binding(
            get: { drafts[code] ?? "" },
            set: { newValue in
                drafts[code] = newValue.filter { $0.isASCII && $0.isNumber }
            }
        )
    }

    private func commit(code: String) {
        guard !isClosed, let account = accounts.first(where: { $0.code == code }) else { return }
        let entered = Int(drafts[code] ?? "") ?? 0
        let stored = OpeningBalanceRules.storedAmount(entered: entered, code: code, type: account.accountType)
        guard stored != (storedByCode[code] ?? 0) else { return }
        let store = OpeningBalanceStore(context: context)
        do {
            try store.set(fiscalYear: fiscalYear, accountCode: code, amount: stored)
            try store.adjustCapitalToBalance(fiscalYear: fiscalYear)
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    private func reload() {
        let store = OpeningBalanceStore(context: context)
        let rows = (try? store.rows(fiscalYear: fiscalYear)) ?? []
        storedByCode = Dictionary(rows.map { ($0.accountCode, $0.amount) }, uniquingKeysWith: { first, _ in first })
        hasAutoRolled = rows.contains { $0.isAutoRolled }
        var newDrafts: [String: String] = [:]
        for account in accounts where OpeningBalanceRules.isEditable(code: account.code, type: account.accountType) {
            let display = displayValue(for: account)
            newDrafts[account.code] = display == 0 ? "" : String(display)
        }
        drafts = newDrafts
    }
}
```

（注: `reload()` 内で `displayValue` は更新後の `storedByCode` を参照するため、`storedByCode` 設定後に drafts を再構築する。）

- [ ] **Step 2: BooksView に NavigationLink 追加**

`Section("帳簿")` 内、`残高試算表` の後に:

```swift
                    NavigationLink("期首残高") { OpeningBalanceView(fiscalYear: selectedYear) }
```

- [ ] **Step 3: Build to verify compile**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | sort -u | head
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Presentation/Reports/OpeningBalanceView.swift SnapKei/Presentation/Reports/BooksView.swift
git commit -m "feat: opening-balance editor in books tab"
```

---

## Task 4: Final verification

- [ ] **Step 1: Full test run**

Standard test command. Expected: `** TEST SUCCEEDED **`, 222 tests 前後（216 + Rules 5 + Store rows 1）。

- [ ] **Step 2: Manual smoke (simulator)**

- 帳簿 > 期首残高: 現金 500,000 入力 → 元入金（自動調整）が ¥500,000、貸借対照表の期首に反映。
- 引継ぎ固定資産: 工具器具備品 400,000 / 減価償却累計額 300,000 入力 → B/S 純資産整合。
- 借入金 800,000（資産ゼロ）→ 元入金 −¥800,000 と債務超過警告。
- 年次締め後に開くと読み取り専用 + 締め済みバナー。前年締め後の翌年を開くと自動繰越バナー。

- [ ] **Step 3: Report results**

テスト/ビルド結果と逸脱を報告。push しない。コミットはユーザー確認後。

---

## Out-of-Scope（spec 参照）

科目カスタム追加 / 期中残高修正 / ウィザード型オンボーディング / 前年締めとの突合チェック。
