# 仕訳編集 + 訂正履歴 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保存済み仕訳の直接編集（全業務フィールド、同一年度内）と、訂正・削除履歴の閲覧 UI（仕訳内タイムライン + 設定の全体ログ）を追加する。

**Architecture:** 既存 `SwiftDataExpenseRepository.edit()`（before/after スナップショット付き監査ログ、呼び出し元ゼロ）にガード 2 件を追加して唯一の編集経路にする。新規 `EntryEditView` は @Model を直接バインドせず @State に複製し、保存時の `applying` クロージャ内でのみ書き戻す。履歴表示は新規 Domain 純関数 `EntryChangeDiff`（スナップショット → フィールド級差分）を `EntryDetailView` と新規 `ActivityLogView` が共用する。同期層は変更ゼロ（編集で `updatedAt` が進み既存 LWW がそのまま機能）。

**Tech Stack:** SwiftUI / SwiftData / Swift Testing（`import Testing`）。Swift 6 default MainActor isolation のため Domain の純型は `nonisolated` を付ける（FixedAssetRules と同じ流儀）。

**Spec:** `docs/superpowers/specs/2026-06-11-snapkei-entry-editing-design.md`

**テスト実行コマンド（全タスク共通）:**

```bash
# 単一スイート
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/<SuiteStructName> test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -20

# 全量（最終確認用）
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

---

## File Structure

| ファイル | 役割 |
|---|---|
| Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift` | `RepositoryError` に 2 ケース追加、`edit()` にガード 2 件追加 |
| Create: `SnapKei/Domain/Services/EnumDisplayJa.swift` | 列挙の日本語表示名の単一定義（詳細・編集・履歴で共用） |
| Create: `SnapKei/Domain/Services/EntryChangeDiff.swift` | スナップショット → フィールド級差分（純関数） |
| Modify: `SnapKei/Domain/Services/FiscalYearRule.swift` | `dateRange(for:)` 追加（DatePicker の年度内制限） |
| Create: `SnapKei/Presentation/ExpenseList/EntryEditView.swift` | 編集フォーム |
| Modify: `SnapKei/Presentation/ExpenseList/EntryDetailView.swift` | 「編集」入口 + 「変更履歴」セクション + ラベルの共通化 |
| Create: `SnapKei/Presentation/History/ActivityLogRowView.swift` | 履歴 1 行（diff 表示、二画面共用） |
| Create: `SnapKei/Presentation/History/ActivityLogView.swift` | 全体ログ（設定→コンプライアンス） |
| Modify: `SnapKei/Presentation/Settings/ComplianceSection.swift` | 「訂正・削除履歴」NavigationLink 追加 |
| Test: `SnapKeiTests/ExpenseRepositoryTests.swift` | edit ガード + スナップショット正確性のスイート追加 |
| Test: `SnapKeiTests/EnumDisplayJaTests.swift` | ラベルのテスト |
| Test: `SnapKeiTests/EntryChangeDiffTests.swift` | diff のテスト |
| Test: `SnapKeiTests/FiscalYearRuleTests.swift` | `dateRange` のスイート追加 |

---

### Task 1: Repository `edit()` ガード（取消済み・資産関連の拒否）

**Files:**
- Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift:44-53`（RepositoryError）, `:96-97`（edit ガード）
- Test: `SnapKeiTests/ExpenseRepositoryTests.swift`（ファイル末尾にスイート追加）

- [ ] **Step 1: 失敗するテストを書く**

`SnapKeiTests/ExpenseRepositoryTests.swift` の末尾に追加:

```swift
@Suite("ExpenseRepository — edit", .serialized)
struct ExpenseRepositoryEditTests {

    @MainActor
    private func makeRepo() throws -> (SwiftDataExpenseRepository, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        return (repo, container.mainContext)
    }

    private func makeEntry(year: Int = 2026, amount: Int = 1100) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: year,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: amount,
            amountExcludingTax: 1000,
            consumptionTax: 100,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店",
            transactionDescription: "テスト取引",
            sourceType: .manual
        )
    }

    @MainActor
    @Test func edit_voidedEntry_throwsEntryVoided() throws {
        let (repo, _) = try makeRepo()
        let entry = makeEntry()
        try repo.create(entry, reason: nil)
        try repo.void(entry, reason: nil)

        #expect(throws: RepositoryError.entryVoided) {
            try repo.edit(entry, applying: { entry.counterpartyName = "変更" }, reason: nil)
        }
        // ガードで弾かれた場合 applying は実行されないこと
        #expect(entry.counterpartyName == "テスト商店")
    }

    @MainActor
    @Test func edit_assetLinkedEntry_throwsAssetLinked() throws {
        let (repo, _) = try makeRepo()
        let entry = makeEntry()
        entry.relatedFixedAssetId = UUID()
        try repo.create(entry, reason: nil)

        #expect(throws: RepositoryError.assetLinked) {
            try repo.edit(entry, applying: { entry.counterpartyName = "変更" }, reason: nil)
        }
    }

    @MainActor
    @Test func edit_closedFiscalYear_throwsFiscalYearClosed() throws {
        let (repo, ctx) = try makeRepo()
        let entry = makeEntry(year: 2026)
        try repo.create(entry, reason: nil)
        ctx.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "test-device"))
        try ctx.save()

        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try repo.edit(entry, applying: { entry.counterpartyName = "変更" }, reason: nil)
        }
    }

    @MainActor
    @Test func edit_recordsBeforeAndAfterSnapshots_withReason() throws {
        let (repo, ctx) = try makeRepo()
        let entry = makeEntry(amount: 880)
        try repo.create(entry, reason: nil)
        let beforeUpdatedAt = entry.updatedAt

        try repo.edit(entry, applying: {
            entry.amountIncludingTax = 980
            entry.counterpartyName = "コンビニ"
        }, reason: "金額誤記")

        let logs = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
        let editLog = try #require(logs.first { $0.activityType == .editEntry })
        #expect(editLog.targetEntryId == entry.id)
        #expect(editLog.reason == "金額誤記")

        let before = try JSONDecoder().decode(
            JournalEntrySnapshot.self, from: try #require(editLog.beforeSnapshot))
        let after = try JSONDecoder().decode(
            JournalEntrySnapshot.self, from: try #require(editLog.afterSnapshot))
        #expect(before.amountIncludingTax == 880)
        #expect(before.counterpartyName == "テスト商店")
        #expect(after.amountIncludingTax == 980)
        #expect(after.counterpartyName == "コンビニ")
        #expect(entry.updatedAt > beforeUpdatedAt)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/ExpenseRepositoryEditTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -20
```

Expected: コンパイルエラー `type 'RepositoryError' has no member 'entryVoided'`（テストが新ケースを参照するため）。

- [ ] **Step 3: 最小実装**

`SnapKei/Data/Persistence/ExpenseRepository.swift` の `RepositoryError` を置き換え:

```swift
public enum RepositoryError: Error, Equatable, LocalizedError {
    case fiscalYearClosed(Int)
    case entryVoided
    case assetLinked

    public var errorDescription: String? {
        switch self {
        case .fiscalYearClosed(let year):
            "\(year)年度は締め済みのため記帳できません。設定の年度管理から再開後にやり直してください。"
        case .entryVoided:
            "取消済の仕訳は編集できません。"
        case .assetLinked:
            "固定資産に関連する仕訳は編集できません。設定の固定資産台帳から資産の削除・処分を行ってください。"
        }
    }
}
```

`edit()` の先頭（`try ensureFiscalYearOpen` の直後）にガードを追加:

```swift
    public func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        try ensureFiscalYearOpen(entry.fiscalYear)
        // 取消済みは編集不可（取消の取り消しは別概念）。資産関連仕訳は
        // FixedAssetService が全権管理する（取得・償却・転出の整合が崩れるため）。
        guard !entry.isVoided else { throw RepositoryError.entryVoided }
        guard entry.relatedFixedAssetId == nil else { throw RepositoryError.assetLinked }
        let before = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        // …以下既存のまま
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/ExpenseRepositoryEditTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -20
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 5: 既存の ExpenseRepository スイートも通ることを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests test 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED" | head -3
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add SnapKei/Data/Persistence/ExpenseRepository.swift SnapKeiTests/ExpenseRepositoryTests.swift
git commit -m "feat: edit() に取消済み・資産関連ガードを追加"
```

---

### Task 2: 列挙の日本語表示名の単一定義（EnumDisplayJa）

**Files:**
- Create: `SnapKei/Domain/Services/EnumDisplayJa.swift`
- Modify: `SnapKei/Presentation/ExpenseList/EntryDetailView.swift:254-284`（private ラベルを共通定義に差し替え）
- Test: `SnapKeiTests/EnumDisplayJaTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`SnapKeiTests/EnumDisplayJaTests.swift` を新規作成:

```swift
import Testing
@testable import SnapKei

@Suite("EnumDisplayJa")
struct EnumDisplayJaTests {

    @Test func taxCategoryLabels() {
        #expect(TaxCategory.standard10.labelJa == "10%")
        #expect(TaxCategory.reduced8.labelJa == "8% 軽減")
        #expect(TaxCategory.nonTaxable.labelJa == "非課税")
        #expect(TaxCategory.outOfScope.labelJa == "対象外")
    }

    @Test func priceEntryModeLabels() {
        #expect(PriceEntryMode.taxIncluded.labelJa == "税込")
        #expect(PriceEntryMode.taxExcluded.labelJa == "税抜")
    }

    @Test func paymentMethodLabels_allCasesCovered() {
        // 全ケースに非空ラベルがあること（新ケース追加時の落とし穴防止）
        for method in PaymentMethod.allCases {
            #expect(!method.labelJa.isEmpty)
        }
        #expect(PaymentMethod.ownerLoan.labelJa == "事業主借")
        #expect(PaymentMethod.ownerWithdraw.labelJa == "事業主貸")
        #expect(PaymentMethod.accountsPayable.labelJa == "未払金")
    }

    @Test func recordSourceLabels_allCasesCovered() {
        for source in RecordSource.allCases {
            #expect(!source.labelJa.isEmpty)
        }
        #expect(RecordSource.aiParsed.labelJa == "AI解析（レシート撮影）")
    }

    @Test func activityTypeLabels_allCasesCovered() {
        for type in ActivityType.allCases {
            #expect(!type.labelJa.isEmpty)
        }
        #expect(ActivityType.createEntry.labelJa == "作成")
        #expect(ActivityType.editEntry.labelJa == "編集")
        #expect(ActivityType.voidEntry.labelJa == "取消")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/EnumDisplayJaTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: コンパイルエラー `value of type 'TaxCategory' has no member 'labelJa'`

- [ ] **Step 3: 実装**

`SnapKei/Domain/Services/EnumDisplayJa.swift` を新規作成。Swift 6 default MainActor isolation のため `nonisolated` を付ける（nonisolated な EntryChangeDiff から呼ぶ）:

```swift
import Foundation

/// 列挙の日本語表示名の単一定義。
/// EntryDetailView（詳細）・EntryEditView（編集フォーム）・訂正履歴 diff が共用する。

nonisolated public extension TaxCategory {
    var labelJa: String {
        switch self {
        case .standard10: "10%"
        case .reduced8: "8% 軽減"
        case .nonTaxable: "非課税"
        case .outOfScope: "対象外"
        }
    }
}

nonisolated public extension PriceEntryMode {
    var labelJa: String {
        switch self {
        case .taxIncluded: "税込"
        case .taxExcluded: "税抜"
        }
    }
}

nonisolated public extension PaymentMethod {
    var labelJa: String {
        switch self {
        case .cash: "現金"
        case .creditCard: "クレジット"
        case .bankTransfer: "銀行振込"
        case .ownerLoan: "事業主借"
        case .ownerWithdraw: "事業主貸"
        case .accountsPayable: "未払金"
        case .other: "その他"
        }
    }
}

nonisolated public extension RecordSource {
    var labelJa: String {
        switch self {
        case .aiParsed: "AI解析（レシート撮影）"
        case .electronicTransaction: "電子取引（PDF取込）"
        case .manual: "手動入力"
        case .imported: "インポート"
        case .depreciation: "減価償却（自動）"
        }
    }
}

nonisolated public extension ActivityType {
    var labelJa: String {
        switch self {
        case .createEntry: "作成"
        case .editEntry: "編集"
        case .voidEntry: "取消"
        case .unlockPeriod: "年度再開"
        case .fiscalYearTransition: "年度締め"
        case .aiParsing: "AI解析"
        case .depreciationPosting: "減価償却計上"
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/EnumDisplayJaTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 5: EntryDetailView のラベルを共通定義に差し替え**

`SnapKei/Presentation/ExpenseList/EntryDetailView.swift` で:

1. `taxCategoryLabel` / `paymentMethodLabel` / `sourceTypeLabel` の 3 つの private 計算プロパティを**削除**し、利用箇所を差し替え:
   - `row("税区分", taxCategoryLabel)` → `row("税区分", entry.taxCategory.labelJa)`
   - `row("支払方法", paymentMethodLabel)` → `row("支払方法", entry.paymentMethod.labelJa)`
   - `row("記帳種別", sourceTypeLabel)` → `row("記帳種別", entry.sourceType.labelJa)`
2. 入力方式の行を差し替え:
   - `row("入力方式", entry.priceEntryModeRaw == PriceEntryMode.taxExcluded.rawValue ? "税抜" : "税込")` → `row("入力方式", entry.priceEntryMode.labelJa)`

（`entry.taxCategory` 等の computed は JournalEntry.swift:101-104 に既存。未知 raw はフォールバック値になるが従来の表示と同等。）

- [ ] **Step 6: ビルド確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add SnapKei/Domain/Services/EnumDisplayJa.swift SnapKei/Presentation/ExpenseList/EntryDetailView.swift SnapKeiTests/EnumDisplayJaTests.swift
git commit -m "feat: 列挙の日本語表示名を単一定義に集約"
```

---

### Task 3: EntryChangeDiff（スナップショット → フィールド級差分）

**Files:**
- Create: `SnapKei/Domain/Services/EntryChangeDiff.swift`
- Test: `SnapKeiTests/EntryChangeDiffTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`SnapKeiTests/EntryChangeDiffTests.swift` を新規作成:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("EntryChangeDiff")
struct EntryChangeDiffTests {

    private func makeEntry() -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
            fiscalYear: 2026,
            transactionDate: Date(timeIntervalSince1970: 1_770_000_000),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 880,
            amountExcludingTax: 800,
            consumptionTax: 80,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "コンビニ",
            transactionDescription: "消耗品",
            sourceType: .manual
        )
    }

    private func snapshot(_ entry: JournalEntry) -> JournalEntrySnapshot {
        JournalEntrySnapshot(from: entry)
    }

    private let noName: (String) -> String? = { _ in nil }

    @Test func noChange_returnsEmpty() {
        let entry = makeEntry()
        let changes = EntryChangeDiff.changes(before: snapshot(entry), after: snapshot(entry), accountName: noName)
        #expect(changes.isEmpty)
    }

    @Test func amountChange_reportsYenFormat() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.amountIncludingTax = 980
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes == [EntryChangeDiff.FieldChange(label: "税込金額", old: "¥880", new: "¥980")])
    }

    @Test func accountChange_resolvesName_orFallsBackToCode() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.debitAccountCode = "5180"
        let resolved = EntryChangeDiff.changes(before: before, after: snapshot(entry)) { code in
            code == "5180" ? "地代家賃" : nil
        }
        #expect(resolved.contains(EntryChangeDiff.FieldChange(label: "借方", old: "5110", new: "5180 地代家賃")))
    }

    @Test func enumChange_usesJapaneseLabels() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.taxCategoryRaw = TaxCategory.reduced8.rawValue
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "税区分", old: "10%", new: "8% 軽減")))
    }

    @Test func unknownEnumRaw_fallsBackToRawString() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.taxCategoryRaw = "bogus"
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "税区分", old: "10%", new: "bogus")))
    }

    @Test func memoNilToValue_showsPlaceholder() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.memo = "領収書あり"
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "メモ", old: "（なし）", new: "領収書あり")))
    }

    @Test func allocationChange_reportsPercentAndOriginalAmount() {
        let entry = makeEntry()
        let before = snapshot(entry)
        entry.businessAllocationRate = 0.5
        entry.originalAmountIncludingTax = 880
        entry.amountIncludingTax = 440
        let changes = EntryChangeDiff.changes(before: before, after: snapshot(entry), accountName: noName)
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "事業割合", old: "100%", new: "50%")))
        #expect(changes.contains(EntryChangeDiff.FieldChange(label: "按分前金額", old: "（なし）", new: "¥880")))
    }

    // MARK: - Data 入口（SystemActivityLog 由来）

    @Test func dataRoundTrip_decodesAndDiffs() throws {
        let entry = makeEntry()
        let beforeData = try JSONEncoder().encode(snapshot(entry))
        entry.counterpartyName = "スーパー"
        let afterData = try JSONEncoder().encode(snapshot(entry))
        let changes = EntryChangeDiff.changes(beforeData: beforeData, afterData: afterData, accountName: noName)
        #expect(changes == [EntryChangeDiff.FieldChange(label: "取引先", old: "コンビニ", new: "スーパー")])
    }

    @Test func missingOrCorruptData_returnsNil() throws {
        let valid = try JSONEncoder().encode(snapshot(makeEntry()))
        #expect(EntryChangeDiff.changes(beforeData: nil, afterData: valid, accountName: noName) == nil)
        #expect(EntryChangeDiff.changes(beforeData: valid, afterData: Data("x".utf8), accountName: noName) == nil)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/EntryChangeDiffTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: コンパイルエラー `cannot find 'EntryChangeDiff' in scope`

- [ ] **Step 3: 実装**

`SnapKei/Domain/Services/EntryChangeDiff.swift` を新規作成:

```swift
import Foundation

/// 訂正履歴の before/after スナップショットからフィールド級の差分を導く純関数。
/// EntryDetailView（変更履歴）と ActivityLogView（訂正・削除履歴）が共用する。
/// 優良電子帳簿の「訂正・削除の事実と内容が確認できること」の表示部分を担う。
nonisolated public enum EntryChangeDiff {
    public struct FieldChange: Equatable, Sendable {
        public let label: String
        public let old: String
        public let new: String

        public init(label: String, old: String, new: String) {
            self.label = label
            self.old = old
            self.new = new
        }
    }

    /// SystemActivityLog の Data 入口。デコード不能（欠損・破損）は nil を返し、
    /// 呼び出し側が「詳細を表示できません」と降級表示する。クラッシュ禁止。
    public static func changes(
        beforeData: Data?,
        afterData: Data?,
        accountName: (String) -> String?
    ) -> [FieldChange]? {
        guard let beforeData, let afterData,
              let before = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: beforeData),
              let after = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: afterData) else {
            return nil
        }
        return changes(before: before, after: after, accountName: accountName)
    }

    public static func changes(
        before: JournalEntrySnapshot,
        after: JournalEntrySnapshot,
        accountName: (String) -> String?
    ) -> [FieldChange] {
        var result: [FieldChange] = []
        func add(_ label: String, _ old: String, _ new: String) {
            if old != new { result.append(FieldChange(label: label, old: old, new: new)) }
        }
        func account(_ code: String) -> String {
            accountName(code).map { "\(code) \($0)" } ?? code
        }
        let none = "（なし）"

        add("取引日", dateString(before.transactionDate), dateString(after.transactionDate))
        add("取引先", before.counterpartyName, after.counterpartyName)
        add("内容", before.transactionDescription, after.transactionDescription)
        add("メモ", before.memo ?? none, after.memo ?? none)
        add("借方", account(before.debitAccountCode), account(after.debitAccountCode))
        add("貸方", account(before.creditAccountCode), account(after.creditAccountCode))
        add("税込金額", YenFormat.string(before.amountIncludingTax), YenFormat.string(after.amountIncludingTax))
        add("税抜金額", YenFormat.string(before.amountExcludingTax), YenFormat.string(after.amountExcludingTax))
        add("消費税", YenFormat.string(before.consumptionTax), YenFormat.string(after.consumptionTax))
        add("税区分", taxLabel(before.taxCategoryRaw), taxLabel(after.taxCategoryRaw))
        add("入力方式", modeLabel(before.priceEntryModeRaw), modeLabel(after.priceEntryModeRaw))
        add("支払方法", paymentLabel(before.paymentMethodRaw), paymentLabel(after.paymentMethodRaw))
        add("適格番号", before.invoiceRegistrationNumber ?? none, after.invoiceRegistrationNumber ?? none)
        add("適格請求書", qualifiedLabel(before.invoiceQualified), qualifiedLabel(after.invoiceQualified))
        add("事業割合", percentString(before.businessAllocationRate), percentString(after.businessAllocationRate))
        add(
            "按分前金額",
            before.originalAmountIncludingTax.map(YenFormat.string) ?? none,
            after.originalAmountIncludingTax.map(YenFormat.string) ?? none
        )
        add("状態", voidedLabel(before.isVoided), voidedLabel(after.isVoided))
        return result
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
    private static func percentString(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }
    private static func qualifiedLabel(_ qualified: Bool) -> String { qualified ? "適格" : "非適格" }
    private static func voidedLabel(_ voided: Bool) -> String { voided ? "取消済" : "有効" }
    private static func taxLabel(_ raw: String) -> String { TaxCategory(rawValue: raw)?.labelJa ?? raw }
    private static func modeLabel(_ raw: String) -> String { PriceEntryMode(rawValue: raw)?.labelJa ?? raw }
    private static func paymentLabel(_ raw: String) -> String { PaymentMethod(rawValue: raw)?.labelJa ?? raw }
}
```

注: `JournalEntrySnapshot` は `ExpenseRepository.swift` 定義の Codable 構造体（同一モジュールなので参照可。テストは `@testable`）。`YenFormat.string(880)` は `"¥880"`。

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/EntryChangeDiffTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SnapKei/Domain/Services/EntryChangeDiff.swift SnapKeiTests/EntryChangeDiffTests.swift
git commit -m "feat: EntryChangeDiff — 訂正履歴のフィールド級差分"
```

---

### Task 4: FiscalYearRule.dateRange（DatePicker の年度内制限）

**Files:**
- Modify: `SnapKei/Domain/Services/FiscalYearRule.swift`
- Test: `SnapKeiTests/FiscalYearRuleTests.swift`(スイート追加)

- [ ] **Step 1: 失敗するテストを書く**

`SnapKeiTests/FiscalYearRuleTests.swift` の末尾に追加:

```swift
@Suite("FiscalYearRule — dateRange")
struct FiscalYearRuleDateRangeTests {

    @Test func rangeBoundsBelongToTheYear() {
        let range = FiscalYearRule.dateRange(for: 2026)
        #expect(FiscalYearRule.year(for: range.lowerBound) == 2026)
        #expect(FiscalYearRule.year(for: range.upperBound) == 2026)
    }

    @Test func justOutsideBounds_belongToAdjacentYears() {
        let range = FiscalYearRule.dateRange(for: 2026)
        #expect(FiscalYearRule.year(for: range.lowerBound.addingTimeInterval(-1)) == 2025)
        #expect(FiscalYearRule.year(for: range.upperBound.addingTimeInterval(1)) == 2027)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/FiscalYearRuleDateRangeTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: コンパイルエラー `type 'FiscalYearRule' has no member 'dateRange'`

- [ ] **Step 3: 実装**

`SnapKei/Domain/Services/FiscalYearRule.swift` の enum 内に追加:

```swift
    /// 年度内の日付範囲（JST、1/1 00:00:00 〜 12/31 23:59:59）。
    /// 編集フォームの DatePicker が跨年変更を物理的に禁止するために使う。
    public static func dateRange(for year: Int) -> ClosedRange<Date> {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(
            from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
        return start...end
    }
```

- [ ] **Step 4: テストが通ることを確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/FiscalYearRuleDateRangeTests test 2>&1 | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED" | head -10
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SnapKei/Domain/Services/FiscalYearRule.swift SnapKeiTests/FiscalYearRuleTests.swift
git commit -m "feat: FiscalYearRule.dateRange — 年度内日付範囲"
```

---

### Task 5: EntryEditView（編集フォーム）

**Files:**
- Create: `SnapKei/Presentation/ExpenseList/EntryEditView.swift`

UI のため単体テストなし（ロジックは Task 1-4 でテスト済みの Domain/Repository に全て委譲）。ビルド確認 + 後続の全量テストで担保。

- [ ] **Step 1: 実装**

`SnapKei/Presentation/ExpenseList/EntryEditView.swift` を新規作成:

```swift
import SwiftData
import SwiftUI

/// 保存済み仕訳の直接編集フォーム。保存は repository.edit() 経由で、
/// SystemActivityLog に before/after スナップショットと理由が記録される（電帳法の訂正履歴）。
///
/// 重要: @Model を直接バインドしない。SwiftData の変更は即時反映のため、
/// 直接バインドすると (a) キャンセルしてもモデルが汚染される、
/// (b) edit() の before スナップショットが「変更後」を撮って diff が空になる。
/// よって @State に複製し、保存時の applying クロージャ内でのみ書き戻す。
struct EntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]

    let entry: JournalEntry

    @State private var transactionDate: Date
    @State private var counterpartyName: String
    @State private var transactionDescription: String
    @State private var memo: String
    @State private var amountText: String
    @State private var taxCategory: TaxCategory
    @State private var priceEntryMode: PriceEntryMode
    @State private var debitAccountCode: String
    @State private var creditAccountCode: String
    @State private var paymentMethod: PaymentMethod
    @State private var invoiceRegistrationNumber: String
    @State private var businessAllocationRate: Double
    @State private var businessAllocationPercentText: String
    @State private var editReason = ""
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var showCancelConfirm = false
    @FocusState private var allocationFieldFocused: Bool

    /// キャンセル確認・保存ボタン活性の基準となる初期値（@State と同じ導出で固定）。
    private let initialValues: InitialValues

    private struct InitialValues {
        let transactionDate: Date
        let counterpartyName: String
        let transactionDescription: String
        let memo: String
        let amountText: String
        let taxCategory: TaxCategory
        let priceEntryMode: PriceEntryMode
        let debitAccountCode: String
        let creditAccountCode: String
        let paymentMethod: PaymentMethod
        let invoiceRegistrationNumber: String
        let businessAllocationPercentText: String
    }

    init(entry: JournalEntry) {
        self.entry = entry

        // 金額欄は按分前の数値を編集する（保存時に TaxSplit→TaxAllocation で再計算）。
        // 税抜入力かつ按分ありの場合のみ按分前税抜額が保存されていないため整数式で逆算する
        // （保存時の再丸めで ±1円 揺れうるが、按分+税抜入力は稀でありこの誤差を受容する）。
        let preTotal = entry.originalAmountIncludingTax ?? entry.amountIncludingTax
        let initialAmount: Int
        if entry.priceEntryMode == .taxExcluded {
            if entry.businessAllocationRate < 1 {
                let ratePercent = Int((entry.taxCategory.taxRate * 100).rounded())
                initialAmount = preTotal * 100 / (100 + ratePercent)
            } else {
                initialAmount = entry.amountExcludingTax
            }
        } else {
            initialAmount = preTotal
        }

        let initial = InitialValues(
            transactionDate: entry.transactionDate,
            counterpartyName: entry.counterpartyName,
            transactionDescription: entry.transactionDescription,
            memo: entry.memo ?? "",
            amountText: String(initialAmount),
            taxCategory: entry.taxCategory,
            priceEntryMode: entry.priceEntryMode,
            debitAccountCode: entry.debitAccountCode,
            creditAccountCode: entry.creditAccountCode,
            paymentMethod: entry.paymentMethod,
            invoiceRegistrationNumber: entry.invoiceRegistrationNumber ?? "",
            businessAllocationPercentText: String(Int((entry.businessAllocationRate * 100).rounded()))
        )
        self.initialValues = initial

        _transactionDate = State(initialValue: initial.transactionDate)
        _counterpartyName = State(initialValue: initial.counterpartyName)
        _transactionDescription = State(initialValue: initial.transactionDescription)
        _memo = State(initialValue: initial.memo)
        _amountText = State(initialValue: initial.amountText)
        _taxCategory = State(initialValue: initial.taxCategory)
        _priceEntryMode = State(initialValue: initial.priceEntryMode)
        _debitAccountCode = State(initialValue: initial.debitAccountCode)
        _creditAccountCode = State(initialValue: initial.creditAccountCode)
        _paymentMethod = State(initialValue: initial.paymentMethod)
        _invoiceRegistrationNumber = State(initialValue: initial.invoiceRegistrationNumber)
        _businessAllocationRate = State(initialValue: entry.businessAllocationRate)
        _businessAllocationPercentText = State(initialValue: initial.businessAllocationPercentText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("取引") {
                    DatePicker(
                        "取引日",
                        selection: $transactionDate,
                        in: FiscalYearRule.dateRange(for: entry.fiscalYear),
                        displayedComponents: .date
                    )
                    TextField("取引先", text: $counterpartyName)
                    TextField("内容", text: $transactionDescription)
                    TextField("メモ", text: $memo)
                } footer: {
                    Text("取引日は \(String(entry.fiscalYear)) 年度内でのみ変更できます。年度をまたぐ場合は取消して再入力してください。")
                }

                Section("金額") {
                    TextField("金額(税込/税抜)", text: $amountText)
                        .keyboardType(.numberPad)
                    Picker("税区分", selection: $taxCategory) {
                        ForEach(TaxCategory.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                    }
                    Picker("入力方式", selection: $priceEntryMode) {
                        ForEach(PriceEntryMode.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                    }
                }

                Section("仕訳") {
                    Picker("借方科目", selection: $debitAccountCode) {
                        ForEach(choices(current: debitAccountCode)) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    Picker("貸方科目", selection: $creditAccountCode) {
                        ForEach(choices(current: creditAccountCode)) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    if derivedKind == .expense {
                        Picker("支払方法", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                        }
                    }
                }

                if derivedKind == .expense {
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
                    }
                }

                Section {
                    TextField("訂正理由（任意）", text: $editReason)
                } footer: {
                    Text("編集は記録を残したまま内容を修正します（電帳法の訂正・削除履歴）。")
                }

                Section {
                    Button("保存") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid || !hasChanges || isSaving)
                }
            }
            .navigationTitle("仕訳を編集")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasChanges { showCancelConfirm = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("変更を破棄しますか？", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("破棄する", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
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

    /// 全有効科目（元入金除く）。ただし現在選択中のコードは無効化済みでも残す
    /// （同期で科目がカスタム化されていても Picker の選択が壊れない）。
    private func choices(current: String) -> [Account] {
        accounts.filter { ($0.isActive && $0.code != AccountCode.capital) || $0.code == current }
    }

    /// 現在の借方/貸方から仕訳の種別を導出（ManualEntryRules.kind が単一定義）。
    private var derivedKind: ManualEntryKind {
        ManualEntryRules.kind(
            debitType: accountType(of: debitAccountCode),
            creditType: accountType(of: creditAccountCode)
        )
    }

    private var isValid: Bool {
        ManualEntryRules.validate(
            kind: derivedKind,
            debitCode: debitAccountCode,
            debitType: accountType(of: debitAccountCode),
            creditCode: creditAccountCode,
            creditType: accountType(of: creditAccountCode),
            amount: Int(amountText) ?? 0,
            counterparty: counterpartyName,
            description: transactionDescription,
            allocationRate: derivedKind == .expense ? businessAllocationRate : 1.0
        ).isEmpty
    }

    private var hasChanges: Bool {
        transactionDate != initialValues.transactionDate
            || counterpartyName != initialValues.counterpartyName
            || transactionDescription != initialValues.transactionDescription
            || memo != initialValues.memo
            || amountText != initialValues.amountText
            || taxCategory != initialValues.taxCategory
            || priceEntryMode != initialValues.priceEntryMode
            || debitAccountCode != initialValues.debitAccountCode
            || creditAccountCode != initialValues.creditAccountCode
            || paymentMethod != initialValues.paymentMethod
            || invoiceRegistrationNumber != initialValues.invoiceRegistrationNumber
            || businessAllocationPercentText != initialValues.businessAllocationPercentText
    }

    private func accountType(of code: String) -> AccountType? {
        accounts.first { $0.code == code }?.accountType
    }

    private func commitAllocationPercent() {
        let clamped = max(0, min(100, Int(businessAllocationPercentText) ?? 0))
        businessAllocationPercentText = String(clamped)
        businessAllocationRate = Double(clamped) / 100.0
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        commitAllocationPercent()
        guard let amount = Int(amountText), amount > 0 else { return }
        isSaving = true

        let kind = derivedKind
        let split = TaxSplit.split(amount: amount, mode: priceEntryMode, rate: taxCategory.taxRate)
        let allocationRate = kind == .expense ? businessAllocationRate : 1.0
        let allocation = TaxAllocation.allocate(
            total: split.total, excludingTax: split.excludingTax, rate: allocationRate)

        let invoice = invoiceRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = kind == .expense && invoice.hasPrefix("T") && invoice.count == 14
        let memoTrimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = editReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMethod: PaymentMethod = switch kind {
        case .income: ManualEntryRules.paymentMethod(forIncomeDebit: debitAccountCode)
        case .expense: paymentMethod
        case .transfer: .other
        }

        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.edit(entry, applying: {
                entry.transactionDate = transactionDate
                entry.counterpartyName = counterpartyName
                entry.transactionDescription = transactionDescription
                entry.memo = memoTrimmed.isEmpty ? nil : memoTrimmed
                entry.debitAccountCode = debitAccountCode
                entry.creditAccountCode = creditAccountCode
                entry.amountIncludingTax = allocation.total
                entry.amountExcludingTax = allocation.excludingTax
                entry.consumptionTax = allocation.tax
                entry.taxCategoryRaw = taxCategory.rawValue
                entry.priceEntryModeRaw = priceEntryMode.rawValue
                entry.paymentMethodRaw = effectiveMethod.rawValue
                entry.invoiceRegistrationNumber = kind == .expense && !invoice.isEmpty ? invoice : nil
                entry.invoiceQualified = qualified
                entry.transitionalMeasureRate = kind == .expense
                    ? ComplianceService.transitionalRate(qualified: qualified, transactionDate: transactionDate)
                    : 1.0
                entry.businessAllocationRate = allocationRate
                entry.originalAmountIncludingTax = allocationRate < 1 ? split.total : nil
            }, reason: reason.isEmpty ? "ユーザー操作" : reason)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
```

不変フィールド（意図的に applying で触らない）: `entryNumber` / `fiscalYear` / `inputDate` / `isLateEntry` / `receiptImagePath` / `receiptImageHash` / `sourceTypeRaw` / `syncId` / `relatedFixedAssetId` / `isVoided`。

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SnapKei/Presentation/ExpenseList/EntryEditView.swift
git commit -m "feat: EntryEditView — 仕訳の直接編集フォーム"
```

---

### Task 6: 履歴行ビュー（ActivityLogRowView、二画面共用）

**Files:**
- Create: `SnapKei/Presentation/History/ActivityLogRowView.swift`

- [ ] **Step 1: 実装**

`SnapKei/Presentation/History/ActivityLogRowView.swift` を新規作成（ディレクトリも新規。プロジェクトは filesystem-synchronized group なので Xcode 操作不要）:

```swift
import SwiftData
import SwiftUI

/// 訂正・削除履歴の 1 行。編集はフィールド級 diff を、取消は理由を表示する。
/// EntryDetailView（変更履歴）と ActivityLogView（全体ログ）が共用する。
struct ActivityLogRowView: View {
    let log: SystemActivityLog
    let accountName: (String) -> String?
    var showsEntryHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.activityType.labelJa)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(log.occurredAt.formatted(date: .numeric, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsEntryHeader, let header = entryHeader {
                Text(header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let reason = log.reason, !reason.isEmpty {
                Text("理由: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if log.activityType == .editEntry {
                editDiff
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var editDiff: some View {
        if let changes = EntryChangeDiff.changes(
            beforeData: log.beforeSnapshot,
            afterData: log.afterSnapshot,
            accountName: accountName
        ) {
            ForEach(changes, id: \.label) { change in
                Text("\(change.label): \(change.old) → \(change.new)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            // スナップショット欠損・デコード不能（旧バージョン由来など）の降級表示。
            Text("詳細を表示できません")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    /// 全体ログで「どの仕訳の操作か」を示すヘッダ（after 優先、無ければ before）。
    private var entryHeader: String? {
        guard let data = log.afterSnapshot ?? log.beforeSnapshot,
              let snapshot = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: data) else {
            return nil
        }
        return "#\(snapshot.entryNumber)（\(String(snapshot.fiscalYear))年度） \(snapshot.counterpartyName)"
    }
}
```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SnapKei/Presentation/History/ActivityLogRowView.swift
git commit -m "feat: ActivityLogRowView — 履歴行の共用ビュー"
```

---

### Task 7: EntryDetailView に「編集」入口 + 「変更履歴」セクション

**Files:**
- Modify: `SnapKei/Presentation/ExpenseList/EntryDetailView.swift`

- [ ] **Step 1: 実装**

1. プロパティ追加（`let entry: JournalEntry` の下）:

```swift
    @State private var showEdit = false
    @Query private var logs: [SystemActivityLog]
    @Query private var closures: [FiscalYearClosure]
```

2. 明示 init を追加（@Query の述語は init 時にしか固定できないため）:

```swift
    init(entry: JournalEntry) {
        self.entry = entry
        let entryId = entry.id
        _logs = Query(FetchDescriptor<SystemActivityLog>(
            predicate: #Predicate { $0.targetEntryId == entryId },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        ))
        let year = entry.fiscalYear
        _closures = Query(FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == year && $0.deletedAt == nil }
        ))
    }
```

3. 編集可否（取消セクションの近くに置く）:

```swift
    /// 編集ガードは repository 層が強制する。UI は入口を隠すのみ。
    private var canEdit: Bool {
        !entry.isVoided && entry.relatedFixedAssetId == nil && closures.isEmpty
    }
```

4. toolbar に追加（既存の「閉じる」ToolbarItem の隣）:

```swift
                ToolbarItem(placement: .primaryAction) {
                    if canEdit {
                        Button("編集") { showEdit = true }
                    }
                }
```

5. sheet を追加（既存 `.fullScreenCover` の後ろ）:

```swift
            .sheet(isPresented: $showEdit) {
                EntryEditView(entry: entry)
            }
```

6. 「変更履歴」セクションを List 内の最後（取消ボタンのセクションの後）に追加:

```swift
                if !logs.isEmpty {
                    Section("変更履歴") {
                        ForEach(logs) { log in
                            ActivityLogRowView(log: log, accountName: lookupAccountName)
                        }
                    }
                }
```

7. ヘルパ追加（`accountLabel` の近く）:

```swift
    private func lookupAccountName(_ code: String) -> String? {
        let name = accounts.first { $0.code == code }?.nameJa
        return (name?.isEmpty ?? true) ? nil : name
    }
```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SnapKei/Presentation/ExpenseList/EntryDetailView.swift
git commit -m "feat: 仕訳詳細に編集入口と変更履歴セクションを追加"
```

---

### Task 8: ActivityLogView（全体ログ）+ ComplianceSection 導線

**Files:**
- Create: `SnapKei/Presentation/History/ActivityLogView.swift`
- Modify: `SnapKei/Presentation/Settings/ComplianceSection.swift`

- [ ] **Step 1: ActivityLogView 実装**

`SnapKei/Presentation/History/ActivityLogView.swift` を新規作成:

```swift
import SwiftData
import SwiftUI

/// 訂正・削除履歴の全体ログ（設定 → コンプライアンス）。
/// 優良電子帳簿の「訂正・削除の事実と内容が確認できること」の提示画面。
struct ActivityLogView: View {
    @Query(sort: \SystemActivityLog.occurredAt, order: .reverse)
    private var logs: [SystemActivityLog]
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var typeFilter: ActivityType?
    @State private var yearFilter: Int?

    var body: some View {
        List {
            Section {
                Picker("種別", selection: $typeFilter) {
                    Text("すべて").tag(ActivityType?.none)
                    ForEach(ActivityType.allCases, id: \.self) { type in
                        Text(type.labelJa).tag(Optional(type))
                    }
                }
                Picker("操作年", selection: $yearFilter) {
                    Text("すべて").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text("\(String(year))年").tag(Optional(year))
                    }
                }
            }

            Section {
                if filteredLogs.isEmpty {
                    Text("履歴がありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLogs) { log in
                        ActivityLogRowView(log: log, accountName: lookupAccountName, showsEntryHeader: true)
                    }
                }
            } footer: {
                Text("履歴は本端末で行った操作の記録です（端末間では同期されません）。")
            }
        }
        .navigationTitle("訂正・削除履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableYears: [Int] {
        Array(Set(logs.map { FiscalYearRule.year(for: $0.occurredAt) })).sorted(by: >)
    }

    private var filteredLogs: [SystemActivityLog] {
        logs.filter { log in
            (typeFilter == nil || log.activityType == typeFilter)
                && (yearFilter == nil || FiscalYearRule.year(for: log.occurredAt) == yearFilter)
        }
    }

    private func lookupAccountName(_ code: String) -> String? {
        let name = accounts.first { $0.code == code }?.nameJa
        return (name?.isEmpty ?? true) ? nil : name
    }
}
```

- [ ] **Step 2: ComplianceSection に導線を追加**

`SnapKei/Presentation/Settings/ComplianceSection.swift` の `Section("コンプライアンス") { ... }` 内、最後の Toggle の後に追加:

```swift
            NavigationLink("訂正・削除履歴") { ActivityLogView() }
```

- [ ] **Step 3: ビルド確認**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add SnapKei/Presentation/History/ActivityLogView.swift SnapKei/Presentation/Settings/ComplianceSection.swift
git commit -m "feat: 訂正・削除履歴の全体ログ画面と設定導線"
```

---

### Task 9: 全量テスト + 仕上げ

- [ ] **Step 1: 全テストスイートを実行**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Expected: `TEST SUCCEEDED`、既存 237 + 新規（edit 4 / labels 5 / diff 9 / dateRange 2 = 約 20 件）全緑。

- [ ] **Step 2: 失敗があれば修正してから再実行**（superpowers:systematic-debugging に従う。テストを弱めて通すのは禁止）

- [ ] **Step 3: シミュレータでの手動確認（5 分）**

1. 一覧 → 仕訳タップ → 「編集」→ 金額変更 → 保存 → 詳細の「変更履歴」に diff が出ること
2. 取消済み仕訳・固定資産関連仕訳で「編集」ボタンが出ないこと
3. 設定 → コンプライアンス → 訂正・削除履歴 に全操作が出ること、フィルタが効くこと
4. 編集フォームで取引日が年度外に選べないこと
5. キャンセル時に変更があると確認ダイアログが出ること

- [ ] **Step 4: 仕上げ commit（残変更があれば）**

```bash
git status --short
# 本機能のファイルのみステージして commit（AppIcon / Localizable.xcstrings の既存未コミット変更は含めない）
```

---

## Self-Review 結果（plan 作成時に実施済み）

- スペック全要件にタスクが対応: ガード(T1)・diff(T3)・フォーム(T5)・詳細入口+仕訳内履歴(T7)・全体ログ+導線(T8)・年度内日付制限(T4)・ラベル共通化(T2)
- 型整合: `EntryChangeDiff.FieldChange` / `labelJa` / `dateRange(for:)` / `RepositoryError.entryVoided/.assetLinked` は全タスクで同名
- 既知の受容事項: 税抜入力+按分ありの金額初期値は ±1円 揺れうる（T5 コメントに明記)、全体ログの年フィルタは操作年基準（仕訳の年度ではない）、SystemActivityLog は同期対象外
