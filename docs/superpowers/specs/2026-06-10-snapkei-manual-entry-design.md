# SnapKei — 手動仕訳入力 設計スペック

**Date:** 2026-06-10
**Status:** Approved（ユーザー承認済み: 三モード誘導型・入口2箇所）

## 背景 / 目的

現状、仕訳の作成経路はレシート撮影（AI解析）と PDF 取込のみで、**借方 Picker が費用科目限定のため売上（収入）を記録する手段が存在しない**。固定資産・期首残高とならぶ「製品ループ断絶」の最優先項目。本機能はレシートなしの手動仕訳入力を追加し、収入記録を解禁する。

## UX 設計

### 形態: 三モード誘導型フォーム

`ManualEntryView`（sheet 表示）。頂部に分段控件 `[収入 | 支出 | 振替]`。

**共通フィールド**: 取引日（DatePicker、既存 `InputDeadlineWarning` を表示）/ 取引先 / 内容 / 金額 / 税区分 / 入力方式（税込/税抜）。

**モード別**:

| | 借方 Picker | 貸方 Picker | デフォルト | 追加フィールド |
|---|---|---|---|---|
| 収入 | 入金先 = 資産科目 | 科目 = 収入科目 | 借方 1210 普通預金 / 貸方 4110 売上高 / 税区分 10% | なし |
| 支出 | 費用科目 | 支払方法から連動（`PaymentMethod.defaultCreditAccountCode`、手動変更後は上書きしない） | ConfirmationForm と同じ（借方 5110、支払方法 事業主借） | 適格番号 / 家事按分 |
| 振替 | 全有効科目 | 全有効科目 | 税区分 対象外 | なし。フッターに用例（売掛金の回収・借入・事業主貸/借の振替） |

- 収入モードの `paymentMethod` は入金先から導出: 1110→`.cash`、1210/1220→`.bankTransfer`、その他→`.other`。
- 振替モードは `taxCategory = .outOfScope` 固定（消費税 0）、`paymentMethod = .other`、家事按分なし。
- `isLateEntry` は全モードで既存規則（`ComplianceService.daysUntilScanDeadline < 0`）。
- 家事按分は支出モードのみ（他モードは rate 1.0、`originalAmountIncludingTax = nil`）。
- バリデーション: 金額 > 0 / 取引先・内容必須（既存フォームと同基準）/ 借方 ≠ 貸方 / モード別科目種別の制約。保存ボタンは不正時 disabled。

### 入口（2箇所）

1. 撮影タブ: `ImageSourcePicker` の下に「手動入力」ボタン（`square.and.pencil`）。
2. 一覧タブ: toolbar に「+」。

どちらも同一の `ManualEntryView` を sheet で開く。保存後 dismiss（一覧は @Query で自動反映）。

## ドメイン層（TDD 対象）

### `ManualEntryRules`（新規, Domain/Services）

```swift
public enum ManualEntryKind: CaseIterable { case income, expense, transfer }
public enum ManualEntryRules {
    static func allowedDebitTypes(for kind) -> Set<AccountType>
    // income: [.asset] / expense: [.expense] / transfer: 全種別
    static func allowedCreditTypes(for kind) -> Set<AccountType>
    // income: [.revenue] / expense: [.asset,.liability,.equity] / transfer: 全種別
    static func validate(kind:debitType:creditType:debitCode:creditCode:amount:counterparty:description:) -> [Issue]
    // Issue: Equatable enum（invalidAmount / missingCounterparty / missingDescription /
    //         sameAccount / debitTypeNotAllowed / creditTypeNotAllowed）
}
```

### `TaxSplit`（新規, Domain/Services — 既存ロジックの抽出）

`ConfirmationForm.save()` 内の税込/税抜 → (税抜額, 消費税) 分解を共有純関数に抽出:

```swift
public enum TaxSplit {
    // taxIncluded: excl = floor(amount/(1+rate)), tax = amount - excl, total = amount
    // taxExcluded: excl = amount, tax = floor(amount*rate), total = amount + tax
    static func split(amount: Int, mode: PriceEntryMode, rate: Double) -> (total: Int, excludingTax: Int, tax: Int)
}
```

`ConfirmationForm` も同関数に差し替え（挙動不変）。`TaxCategory.taxRate` は ConfirmationForm の private extension から共有スコープへ移動。

## 保存経路

既存 `SwiftDataExpenseRepository.create(_:reason:)` を使用（年度ロック検査・連番採番・監査ログ・同期通知が自動で付く）。`sourceType: .manual`、`fiscalYear: FiscalYearRule.year(for: transactionDate)`、レシート画像なし。

## テスト

- `ManualEntryRulesTests` / `TaxSplitTests`（swift-testing、RED→GREEN）。
- フォーム/入口はリポジトリ慣例どおり build + 手動スモーク。

## Out of scope

- 既存仕訳の編集（別機能）/ 定期仕訳テンプレート / 売掛・請求書管理（発生主義ワークフロー）/ 複合仕訳（1:N 行）。
