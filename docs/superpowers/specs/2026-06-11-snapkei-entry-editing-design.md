# SnapKei — 仕訳編集 + 訂正履歴 設計スペック

**Date:** 2026-06-11
**Status:** Approved（ユーザー承認済み: 直接編集+履歴・独立 EntryEditView・履歴二入口）

## 背景 / 目的

現状、保存済み仕訳の修正手段は「取消（void）→ 再入力」しかない。AI 読取の金額誤認識という最高頻度の修正シナリオで体験が悪く、製品ループ最後の断絶点。また `SystemActivityLog` は作成・編集・取消を before/after スナップショット付きで記録する設計だが、**閲覧 UI が一切存在しない**——電子帳簿保存法の優良電子帳簿要件（訂正・削除の事実と内容が確認できること）は「記録して見せられる」ことで満たすため、閲覧導線は必須。

本機能は (1) 直接編集 + 履歴記録方式の仕訳編集、(2) 訂正・削除履歴の閲覧 UI（仕訳内 + 全体）を追加する。

## 決定事項（ユーザー承認済み）

| 論点 | 決定 |
|---|---|
| 訂正方式 | **直接編集 + 履歴**（freee/MF 方式）。紅字反対仕訳は不採用（帳簿膨張・UX 過重）。既存 `ExpenseRepository.edit()` がこの方式を前提に予埋済み |
| 編集範囲 | **全業務フィールド編集可**。取引日は同一会計年度内のみ（跨年は取消→再入力に誘導）。AI/手動/PDF 由来を問わない |
| 履歴 UI | **仕訳内タイムライン + 全体ログの二入口**、diff エンジン共用 |
| フォーム | **独立 `EntryEditView`**。ManualEntryView は触らない(作成フロー無リスク)、Domain 規則のみ共用 |
| 訂正理由 | 任意入力。空なら「ユーザー操作」（void と同一規約） |

## 編集ガード（Repository 層で強制、UI は入口を隠すのみ)

`SwiftDataExpenseRepository.edit()` に以下を追加（既存テスト 237 件は維持）:

1. **取消済み拒否**: `entry.isVoided == true` → throw（現状チェックなし。要追加）
2. **資産関連拒否**: `entry.relatedFixedAssetId != nil` → throw。取得・減価償却・転出仕訳は FixedAssetService が全権管理（void は UI 層でのみブロック中だが、編集は repository 層で強制する）
3. **閉鎖年度拒否**: `ensureFiscalYearOpen`（既存）

エラーは `LocalizedError`（ja メッセージ）で UI に表面化。

## EntryEditView（Presentation 層）

入口: `EntryDetailView` の toolbar に「編集」ボタン → sheet で `EntryEditView(entry)`。編集不可の仕訳（取消済み / 資産関連 / 閉鎖年度）ではボタン非表示。

### 重要実装制約: @Model を直接バインドしない

SwiftData の @Model 変更は即時反映のため、フォームが `entry.xxx` を直接バインドすると (a) キャンセルしてもモデルが汚染される、(b) `edit()` の before スナップショットが「変更後」を撮ってしまい diff が空になる。よって:

- init 時に entry の値を `@State` ローカル変数へコピー
- 保存時に `repository.edit(entry, applying: { /* ローカル値を entry へ書き戻し */ }, reason:)` — スナップショット・rollback・キャンセルの三者が正しく機能する

### フィールド全集

| フィールド | 編集 | 備考 |
|---|---|---|
| 取引日 | ○ | DatePicker。`FiscalYearRule` で当該 `fiscalYear` の 1/1〜12/31 に制限（JST） |
| 取引先 / 摘要 / メモ | ○ | |
| 金額 + 税込/税抜 + 税区分 | ○ | `TaxSplit`（整数演算）で税額再計算 |
| 借方/貸方科目 | ○ | `ManualEntryRules.kind()` で現科目からモード導出、`validate()` で全制約検証（科目種別・同一科目・資本科目等） |
| 支払方法 | ○ | 連動デフォルト（`defaultCreditAccountCode`）は**適用しない**——編集は既存値の修正であり、作成時の誘導ロジックは持ち込まない |
| 適格請求書番号 / 適格フラグ | ○ | |
| 事業按分率 | ○ | フォームの金額欄は**按分前の総額**を表示・編集（rate < 1 なら `originalAmountIncludingTax`、それ以外は `amountIncludingTax` で初期化）。保存時 `TaxSplit` → `TaxAllocation.allocate` の順で再計算し、`originalAmountIncludingTax = rate < 1 ? 総額 : nil` の既存規約を維持（ManualEntryView:297 と同一） |
| 訂正理由 | 任意 | 空→「ユーザー操作」 |
| 証憑画像 / hash | × 不変 | 内容の訂正は証憑完全性に影響しない。バッジ継続有効 |
| `inputDate` / `isLateEntry` | × 不変 | 「いつ初回記帳したか」の記録。編集で歴史を書き換えない |
| `entryNumber` / `fiscalYear` / `syncId` / `sourceType` | × 不変 | |

- バリデーション NG 時は保存 disabled + インライン表示（ManualEntryView と同パターン）
- キャンセル時、未保存変更があれば確認ダイアログ（`hasUnsavedInput` 方式 + `interactiveDismissDisabled`）
- 保存失敗は `edit()` 既存の rollback + alert

## 訂正履歴 UI

### Domain: `EntryChangeDiff`（新規・純関数・TDD 最重点）

`(before: JournalEntrySnapshot, after: JournalEntrySnapshot) -> [FieldChange]`

- `FieldChange(label: String, old: String, new: String)` — 変化したフィールドのみ
- ラベル日本語化、金額は `YenFormat`、按分率は %、科目コードは科目名解決（未知コードはコード生表示に降級）、enum は表示名
- スナップショットのデコード失敗 → 呼び出し側が「詳細を表示できません」降級行を表示（クラッシュ禁止）

### 入口 1: 仕訳内（EntryDetailView「変更履歴」セクション）

`targetEntryId == entry.id` の `SystemActivityLog` を `occurredAt` 順に表示。行: 種別ラベル（作成/編集/取消）+ 日時 + 理由。編集行は展開で `EntryChangeDiff` のフィールド級 diff。

### 入口 2: 全体（設定 → コンプライアンス → 「訂正・削除履歴」）

`ActivityLogView`（新規画面）: 全 `SystemActivityLog` を年度・種別でフィルタ可能なリスト。タップで同じ diff 詳細。取消済み仕訳の履歴もここから到達可能（税務調査での提示シナリオ）。

フッター注記: 「履歴は本端末で行った操作の記録です」——`SystemActivityLog` は同期対象外（本期は受容、future work）。

## 同期

編集で `updatedAt` 更新 → 既存 `JournalEntryPayload`（全フィールド搬送）+ LWW merger がそのまま機能。**同期層の変更ゼロ**。`SystemActivityLog` の同期は本期スコープ外。

## テスト計画（全面 TDD）

1. `EntryChangeDiff`: 各フィールド型の diff / nil↔値 / enum ラベル / 未知科目コード降級 / 変化なし→空配列
2. Repository `edit()` ガード: 取消済み拒否 / 資産関連拒否 / 閉鎖年度拒否（既存）/ before・after スナップショットの正確性 / 失敗時 rollback
3. 取引日の年度内制限（`FiscalYearRule` 境界、JST）
4. 編集時 `TaxSplit` 再計算 / 按分整合
5. `ManualEntryRules.kind()` の既存仕訳（振替含む）に対する導出
6. 既存 237 テスト全緑維持

## スコープ外（明示)

- `SystemActivityLog` のクロスデバイス同期
- 紅字反対仕訳モード
- 跨年度の取引日変更（取消→再入力へ誘導）
- 証憑画像の差し替え
