# SnapKei P2a — 青色申告決算書 (Kessansho) Design Spec

**Date:** 2026-06-09
**Status:** Approved (design), pending implementation plan
**Phase:** P2a (first sub-project of P2). Subsequent: P2b 所得税計算, P2c 確定申告書, P2d 消費税申告.

## Overview

Generate the official 青色申告決算書 (一般用) for a fiscal year by mapping SnapKei's existing journal entries, fixed assets, and balances onto the National Tax Agency (国税庁) form's legally-defined line items. Output is an on-screen review plus a structured PDF. This is the legally-required attachment that substantiates the 55万/65万円 青色申告特別控除 the app already advertises.

Builds entirely on P1 (`ProfitAndLossService`, `BalanceSheetService`, `DepreciationService`, `OpeningBalanceStore`, `ControlRouteStatus`). No new tax-law calculation (that is P2b).

## Scope

**In scope:**
- `KessanshoReport` value model (pure data tree).
- `KessanshoService.build(...)` pure function composing the report from existing services.
- Account → 決算書 legal-line-item mapping (static, deterministic, testable).
- 青色申告特別控除額 capping.
- 損益計算書 block, 月別売上(収入)金額 table (12 months), 減価償却費の計算 table, 地代家賃の内訳, and 貸借対照表 (reused).
- `KessanshoView` on-screen (reached from the existing 帳簿 tab's BooksView, per selected year).
- `PDFReportService.renderKessansho(report:)` structured multi-page PDF.

**Out of scope (future):**
- 売上原価 / 棚卸 / 仕入 (service-business assumption: 売上原価 = 0).
- 給料賃金・専従者給与・貸倒引当金・利子割引料 の内訳 (no payroll/provision/interest data model).
- Pixel-faithful reproduction of the official government form layout.
- 住所 and other header fields beyond 氏名/屋号.
- 製造原価の計算 (manufacturers).
- e-Tax / `.xtx` export (P3).

## Architecture

`KessanshoService.build(fiscalYear:entries:accounts:assets:openingBalances:maxBlueDeduction:header:) -> KessanshoReport` is a pure function. `KessanshoView` computes inputs from `@Query` + `OpeningBalanceStore` + `ControlRouteStatus.estimatedDeduction` (the caller supplies `maxBlueDeduction`) and renders the report on screen; the PDF button calls `PDFReportService.renderKessansho(report:)` and shares via the existing `SharePresenter`. Mirrors the established layering: services produce value models, views/PDF render them.

### Files

```
SnapKei/
├── Domain/Services/
│   ├── KessanshoService.swift              [CREATE — build() + report value model]
│   ├── KessanshoLineMapping.swift          [CREATE — account → legal expense row mapping]
│   └── PDFReportService.swift              [MODIFY — add renderKessansho(report:)]
└── Presentation/Reports/
    ├── BooksView.swift                     [MODIFY — add 青色申告決算書 NavigationLink in 決算書 section]
    └── KessanshoView.swift                 [CREATE — on-screen review + PDF export]
SnapKeiTests/
├── KessanshoServiceTests.swift             [CREATE]
└── KessanshoLineMappingTests.swift         [CREATE]
```

## Data model

```swift
public struct KessanshoReport: Equatable, Sendable {
    public struct Header: Equatable, Sendable {
        public let fiscalYear: Int
        public let ownerName: String
        public let businessName: String
    }
    public struct ExpenseRow: Equatable, Sendable, Identifiable {
        public var id: String { label }
        public let label: String   // legal row name, or custom 空欄 label (account nameJa)
        public let amount: Int
    }
    public struct ProfitAndLoss: Equatable, Sendable {
        public let salesRevenue: Int                  // 売上(収入)金額 (all revenue credits)
        public let costOfGoodsSold: Int               // 売上原価 (= 0 in v1)
        public let grossProfit: Int                   // 差引金額 = salesRevenue − costOfGoodsSold
        public let expenseRows: [ExpenseRow]          // 経費 (legal rows + 空欄 customs)
        public let expenseTotal: Int                  // 経費計
        public let netBeforeDeduction: Int            // 青色申告特別控除前の所得金額
        public let blueDeduction: Int                 // 青色申告特別控除額 (capped)
        public let income: Int                        // 所得金額
    }
    public struct MonthlyRow: Equatable, Sendable, Identifiable {
        public var id: Int { month }
        public let month: Int                         // 1...12
        public let sales: Int
        public let purchases: Int                     // = 0 in v1
    }
    public struct DepreciationRow: Equatable, Sendable, Identifiable {
        public var id: UUID { assetId }
        public let assetId: UUID
        public let assetName: String
        public let acquisitionYearMonth: String       // "2026-07"
        public let acquisitionAmount: Int
        public let method: String                     // "定額法"
        public let usefulLifeYears: Int
        public let yearDepreciation: Int              // 本年分の償却費合計 (full)
        public let businessRatePercent: Int           // 事業専用割合
        public let deductibleAmount: Int              // 本年分の必要経費算入額
        public let yearEndBalance: Int                // 期末残高 = acquisitionAmount − accumulatedDepreciation(after)
    }
    public struct RentRow: Equatable, Sendable, Identifiable {
        public var id: String { payee }
        public let payee: String                      // 支払先 (counterpartyName)
        public let annualRent: Int                    // 本年中の賃借料
        public let deductibleAmount: Int              // うち必要経費算入額
    }

    public let header: Header
    public let profitAndLoss: ProfitAndLoss
    public let monthly: [MonthlyRow]                  // always 12 rows
    public let depreciation: [DepreciationRow]
    public let rentDetails: [RentRow]
    public let balanceSheet: BalanceSheetReport       // reused from P1
}
```

## Computation rules (`KessanshoService.build`)

All computations exclude `isVoided` entries and filter to `fiscalYear`.

- **売上(収入)金額**: sum of `amountIncludingTax` where the credit account is `.revenue` type (4110 売上高 + 4910 雑収入). Reuse `ProfitAndLossService.summary(...).revenueTotal`.
- **売上原価 = 0**, **差引金額 = 売上 − 0**.
- **経費 (expenseRows)**: `ProfitAndLossService.summary(...).expenseByCode` mapped via `KessanshoLineMapping` (see below); standard rows aggregate multiple accounts that map to them; rows with zero amount are omitted; ordered by the legal row order, customs after, 雑費 last. **経費計** = sum.
- **青色申告特別控除前の所得金額 (netBeforeDeduction)** = 差引金額 − 経費計 = `PLSummary.netIncome` (専従者給与 = 0, 引当金 = 0 in v1).
- **青色申告特別控除額 (blueDeduction)** = `min(maxBlueDeduction, max(0, netBeforeDeduction))`. `maxBlueDeduction` is supplied by the caller from `ControlRouteStatus.estimatedDeduction` (10/55/65万).
- **所得金額 (income)** = netBeforeDeduction − blueDeduction.
- **monthly**: 12 rows; `sales[m]` = sum of revenue-credit `amountIncludingTax` for entries whose `transactionDate` month == m (gregorian, Asia/Tokyo); `purchases` = 0.
- **depreciation**: one row per `FixedAsset` with `deletedAt == nil` and `serviceStart` year ≤ fiscalYear and not fully depreciated, using `DepreciationService.annualAmount(for:fiscalYear:)`. `yearDepreciation` = `.full`, `deductibleAmount` = `.deductible`, `businessRatePercent` = `Int((businessAllocationRate*100).rounded())`, `method` = "定額法", `yearEndBalance` = `acquisitionAmount − (accumulatedDepreciation + full)` clamped ≥ 0. (Uses current accumulated value; historical-year accuracy is out of scope.)
- **rentDetails**: entries whose debit account == `5180` (地代家賃), grouped by `counterpartyName`; `annualRent` = Σ`originalAmountIncludingTax ?? amountIncludingTax`, `deductibleAmount` = Σ`amountIncludingTax` (already business-allocated). Empty when none.
- **balanceSheet**: `BalanceSheetService.report(fiscalYear:entries:openingBalances:accounts:)` verbatim.

## Account → 決算書 expense-row mapping (`KessanshoLineMapping`)

The 青色申告決算書 (一般用) 損益計算書 has these fixed 経費 rows (order preserved):
租税公課, 荷造運賃, 水道光熱費, 旅費交通費, 通信費, 広告宣伝費, 接待交際費, 損害保険料, 修繕費, 消耗品費, 減価償却費, 福利厚生費, 給料賃金, 外注工賃, 利子割引料, 地代家賃, 貸倒金, 5×空欄, 雑費.

**Rule:** each expense account maps to a standard row when one exists; otherwise it occupies a 空欄 row labeled with the account's `nameJa`. Custom (空欄) accounts are assigned in ascending account-code order; if more than 5 customs occur, the overflow accounts fold into 雑費. Output expense rows: standard rows (legal order) that have a non-zero total, then custom 空欄 rows, then 雑費 — each appearing only when its amount ≠ 0.

Seed-account mapping (33-account chart):

| Code | nameJa | 決算書 row |
|---|---|---|
| 5100 | 旅費交通費 | 旅費交通費 |
| 5110 | 通信費 | 通信費 |
| 5120 | 接待交際費 | 接待交際費 |
| 5130 | 会議費 | 空欄(会議費) |
| 5140 | 消耗品費 | 消耗品費 |
| 5150 | 事務用品費 | 空欄(事務用品費) |
| 5160 | 新聞図書費 | 空欄(新聞図書費) |
| 5170 | 水道光熱費 | 水道光熱費 |
| 5180 | 地代家賃 | 地代家賃 |
| 5190 | 外注工賃 | 外注工賃 |
| 5200 | 支払手数料 | 空欄(支払手数料) |
| 5210 | 修繕費 | 修繕費 |
| 5220 | 租税公課 | 租税公課 |
| 5230 | 減価償却費 | 減価償却費 |
| 5290 | 雑費 | 雑費 |

(The seed yields exactly 4 customs — 会議費/事務用品費/新聞図書費/支払手数料 — within the 5 空欄 limit.) Accounts not in the table (future custom accounts) are treated as customs by `nameJa`, then the overflow→雑費 rule applies.

## Views / PDF

- **`KessanshoView(fiscalYear:)`**: sections for 損益計算書 (with 青色申告特別控除前/控除額/所得金額 highlighted), 月別売上, 減価償却費の計算, 地代家賃の内訳 (hidden when empty), 貸借対照表 summary. Top-right toolbar: PDF 出力 (icon-only, `.accessibilityLabel`). Computes `maxBlueDeduction` from `ControlRouteStatus.load(...)` (hasEntries/hasAuditLog from the repository).
- **`BooksView`**: add `NavigationLink("青色申告決算書") { KessanshoView(fiscalYear: selectedYear) }` in the 決算書 section.
- **`PDFReportService.renderKessansho(report:)`**: structured multi-page PDF (損益計算書 → 月別 → 減価償却 → 地代家賃 → 貸借対照表), readable layout (not pixel-faithful), `UIGraphicsPDFRenderer`, page-break on overflow. Shared via `SharePresenter` as `青色申告決算書_<year>.pdf`.

## Testing

`KessanshoServiceTests` (worked example — FY2026: opening 現金 100,000 / 元入金 −100,000; #1 Dr1110/Cr4110 110,000; #2 Dr5110/Cr3210 11,000; #3 Dr1610/Cr3210 240,000; #5 Dr5230/Cr1710 24,000; #6 Dr3220/Cr1710 6,000; PC asset 240,000/4yr/serviceStart 2026-07/rate 0.8):
- salesRevenue 110,000; costOfGoodsSold 0; grossProfit 110,000.
- expenseRows = [通信費 11,000, 減価償却費 24,000]; expenseTotal 35,000. (事業主貸 6,000 is equity, not an expense.)
- netBeforeDeduction 75,000.
- With `maxBlueDeduction = 650,000` → blueDeduction capped to 75,000; income 0. With `maxBlueDeduction = 0` → blueDeduction 0; income 75,000.
- monthly: exactly one month = 110,000, others 0; Σ = 110,000.
- depreciation: one row — yearDepreciation 30,000, deductibleAmount 24,000, businessRatePercent 80, method "定額法", yearEndBalance 210,000.
- rentDetails empty.
- balanceSheet.isBalanced == true (assetTotal == liabilityEquityTotal == 426,000).

`KessanshoLineMappingTests`:
- Each seed expense code maps to its expected row (table above).
- The 4 custom accounts produce 空欄 rows labeled with `nameJa`, ordered by ascending code.
- Overflow: ≥6 distinct custom accounts → the 6th+ fold into 雑費 (synthetic accounts).
- Zero-amount rows are omitted from `expenseRows`.

Views follow the repo convention (no view tests).
