# SnapKei — 固定資産登記 UI 設計スペック

**Date:** 2026-06-10
**Status:** Approved（ユーザー承認済み: 取得仕訳自動生成+引継ぎモード / 処分は記録+自動転出仕訳）

## 背景 / 目的

`FixedAsset` は同期マージでしか生成できず、減価償却・年次締め・決算書の償却計算が**ユーザーから到達不能**。`FixedAssetSection` は読み取り専用。処分停止ガード（前回追加）も disposalDate を設定する UI が無く死機能。本機能で登記・引継ぎ・処分・削除を提供し、償却機構を解放する。

## ドメイン層（TDD 対象）

### `FixedAssetRules`（新規, Domain/Services）

```swift
public enum FixedAssetRules {
    public enum Issue: Equatable, Sendable {
        case missingName, invalidAmount, invalidUsefulLife,
             invalidAllocation, treatmentNotAvailable, invalidAccumulated
    }
    // 金額・日付から選択可能な償却区分:
    //   amount < 100_000            → []（資産計上対象外。登記不可）
    //   100_000..<200_000           → [一括償却, 少額特例*, 定額法]
    //   200_000..<300_000           → [少額特例*, 定額法]   * 期限内のみ (ComplianceConstants.smallDepreciableExpiry)
    //   300_000...                  → [定額法]
    static func availableTreatments(amount: Int, acquisitionDate: Date) -> [AssetTreatment]
    static func validate(name:amount:usefulLifeYears:allocationRate:treatment:acquisitionDate:
                         isCarriedOver:accumulatedDepreciation:) -> [Issue]
    // usefulLifeYears 2...50、allocationRate 0<rate<=1、
    // 引継ぎ時 0 <= accumulated <= amount。
}
```

### `FixedAssetService`（新規, Domain/Services — @MainActor, context+deviceId, YearEndClosingService と同型）

**register（新規購入）:**
- `FixedAsset` 作成（bookValue = 取得価額, accumulated = 0）
- 取得仕訳を `ExpenseRepository.create` 経由で自動生成: 借方 `1610 工具器具備品` / 貸方 支払方法から `PaymentMethod.defaultCreditAccountCode`（デフォルト 事業主借）。金額 = 税込取得価額**全額**（家事按分は償却側で行い、取得仕訳は分割しない）。taxCategory 選択可（デフォルト 10%、TaxSplit で消費税内訳）。`sourceType: .manual`、`relatedFixedAssetId = asset.syncId`、`asset.acquisitionJournalEntryId = entry.id`。
- **少額特例（smallAmountFullExpense）= 即時償却**: `DepreciationService` は本区分に 0 を返すため、登記時に償却仕訳も同時生成する: `5230 減価償却費 ×事業割合 / 1710` + 家事分 `3220 / 1710`（`sourceType: .depreciation`、年末締めの償却仕訳と同形）。`accumulated = 取得価額`, `bookValue = 0`。
- 年度は `FiscalYearRule.year(for: acquisitionDate)`。締め済み年度なら `RepositoryError.fiscalYearClosed` がそのまま伝播。

**register（引継ぎモード）:**
- 仕訳を一切生成しない。`accumulatedDepreciation` 入力可、`bookValue = 取得価額 − accumulated`。
- 既知の限界: 引継ぎ資産の B/S 表示は期首残高（次フィーチャー）に依存。台帳と今後の償却は機能する。

**dispose(asset, disposalDate, disposalAmount?):**
- ガード: 未処分であること。処分年度が締め済みなら不可。
- 転出仕訳を自動生成（いずれも 対象外/税0、`relatedFixedAssetId` 設定）:
  1. `1710 減価償却累計額 / 1610` — accumulated 分（> 0 のとき）
  2. `3220 事業主貸 / 1610` — bookValue 分（> 0 のとき）
- 個人事業主の事業用資産売却は譲渡所得（事業損益外）のため事業主貸転出が標準処理。売却代金は台帳に記録のみ（事業口座に入金した場合は振替「普通預金/事業主借」を案内する footer）。
- `disposalDate`/`disposalAmount` 設定、`bookValue = 0`、updatedAt 更新。
- 既知の限界: 処分年度の月割償却は未対応（現行の年額モデルのまま）。

**delete(asset):**
- ソフト削除（deletedAt、同期に乗る）。
- 償却仕訳（sourceType .depreciation で relatedFixedAssetId 一致, 非取消）が存在する場合は**削除不可**（処分を案内）。
- 取得仕訳が存在すれば自動で void（理由付き）してから削除 — 誤登記の取り消しに対応。

## UI（Settings 内）

- `FixedAssetSection`: 「資産を登録」ボタン行（sheet で `FixedAssetFormView`）+ 資産行タップで `FixedAssetDetailView`（sheet）。行に簿価と「処分済」バッジ。
- **FixedAssetFormView**: 資産名 / カテゴリ Picker（AssetUsefulLife 7種 → 耐用年数自動入力・編集可）/ 取得日・使用開始日（デフォルト同日）/ 取得価額(税込) / 税区分 / 償却区分（`availableTreatments` で絞り込み、`suggestAssetTreatment` の結果を「推奨」表示）/ 事業割合 % / 支払方法 /「既存資産の引継ぎ」Toggle（ON: 支払方法・税区分を隠し、償却累計額入力を表示）。10万円未満は登記不可の案内（経費計上を促す）。保存ボタンは validate で disable。二重保存ガード。
- **FixedAssetDetailView**: 全項目表示 + 「処分する」（処分日 + 売却代金(任意) + 生成される転出仕訳のプレビュー付き confirmationDialog）+「削除」(削除可能な場合のみ表示、取得仕訳が void される旨を確認)。

## テスト

`FixedAssetRulesTests` + `FixedAssetServiceTests`（in-memory ModelContainer、ExpenseRepositoryTests と同パターン）: 取得仕訳の双方向リンク・金額・科目 / 少額特例の即時償却2仕訳と簿価0 / 引継ぎの無仕訳 / 処分の2仕訳と禁則（二重処分・締め年度）/ 削除ガードと取得仕訳 void / validate 各則 / availableTreatments 境界（10万/20万/30万/期限）。View は build + スモーク。

## Out of scope

処分年度の月割償却 / 財務項目（取得価額・耐用年数・償却区分・取得日）の登記後編集（誤登記は削除→再登記）/ 車両運搬具 1620 等の科目振り分け（一律 1610）/ 期首残高 UI（次フィーチャー）。
