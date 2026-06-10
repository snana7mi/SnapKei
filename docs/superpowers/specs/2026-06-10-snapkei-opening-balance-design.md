# SnapKei — 期首残高 UI 設計スペック

**Date:** 2026-06-10
**Status:** Approved（ユーザー承認済み: 自動繰越値は編集可+警告）

## 背景 / 目的

`OpeningBalance` は年次締めの自動繰越と同期でしか作られず、初年度ユーザー・アプリ導入前から事業を行うユーザー・引継ぎ固定資産（1610/1710）の B/S 計上に入力手段が無い。P1 計画の OpeningBalanceView 未実装項目を解消する。

## ドメイン層（TDD 対象）

### `OpeningBalanceRules`（新規, Domain/Services, nonisolated）

- `isEditable(code:type:) -> Bool` — 資産/負債/資本のみ。除外: `3110 元入金`（自動調整）、`3210 事業主借`・`3220 事業主貸`（年度境界で元入金へ集約、期首は常に0）。収益/費用は対象外。
- 符号規約の単一定義（ストレージは借方プラス）:
  - `storedAmount(entered:code:type:)` — 資産 → `+entered`、負債/資本 → `-entered`、**`1710 減価償却累計額`（資産型の貸方性質・コントラ）→ `-entered`**。
  - `displayAmount(stored:code:type:)` — 逆変換（常に正の表示値）。
- `contraAssetCodes = ["1710"]`。

### `OpeningBalanceStore.rows(fiscalYear:)`（追加）

`[OpeningBalance]`（deletedAt == nil）を返す。UI が `isAutoRolled` を判定するために必要（既存 `balances()` は dict のみ）。

## UI — `OpeningBalanceView(fiscalYear:)`（Presentation/Reports）

- 入口: `BooksView` 帳簿セクション「残高試算表」の後に `NavigationLink("期首残高")`。
- 資産 / 負債 / 資本 のセクションに編集可能行（科目名 + 右寄せ数字 TextField、ASCII 数字フィルタ、フォーカス喪失/onSubmit でコミット）。コミットごとに `store.set(..., isAutoRolled: false)` → `adjustCapitalToBalance(fiscalYear:)` → 再読込。
- `1710` は「減価償却累計額（控除・プラス入力）」と表示。
- サマリーセクション: 資産合計 / 負債合計 / **元入金（自動調整・編集不可）**。元入金がマイナス（債務超過）のときオレンジで注意表示。
- 自動繰越バナー: いずれかの行が `isAutoRolled` のとき「前年の年次締めから自動繰越された値です。編集すると手動値になり、前年を再締めすると上書きされます。」
- **対象年度が締め済みのときは全行読み取り専用** + 「締め済みの年度です。年次締めから再オープンすると編集できます。」バナー（仕訳と同じ年度ロック語義）。
- footer: 「開業初年度は通常入力不要です。アプリ導入前から事業を行っている場合は前年末時点の残高を入力してください。引継ぎ固定資産は取得価額を 工具器具備品、償却累計額を 減価償却累計額 に入力します。」
- 行の表示値は `displayAmount`、保存は `storedAmount`（ユーザーは常に正数で入力）。

## テスト

`OpeningBalanceRulesTests`（editable 判定・符号変換・1710 コントラ・往復）+ `OpeningBalanceStoreTests` に `rows(fiscalYear:)` を追加（TDD）。View は build + スモーク。

## Out of scope

科目のカスタム追加 / 期中の残高修正（振替仕訳で行う）/ ウィザード型オンボーディング / 期首残高の年度間整合チェック（前年締めとの突合は年次締め側の責務）。
