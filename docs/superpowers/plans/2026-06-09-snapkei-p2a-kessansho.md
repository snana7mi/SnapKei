# SnapKei P2a — 青色申告決算書 Review/PDF Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a 青色申告決算書-oriented review screen and structured PDF summary for a fiscal year by mapping existing journal entries, fixed assets, and balances onto the form's legal line-item concepts. This is **not** a pixel-faithful official government form; it is a review/export worksheet that helps users confirm values before filing.

**Architecture:** `KessanshoService.build(...)` is a pure service that composes a `KessanshoReport` from existing value inputs and P1 services (`ProfitAndLossService`, `BalanceSheetService`, `DepreciationService`). `KessanshoView` loads opening balances through `OpeningBalanceStore`, derives an estimated deduction route from `ControlRouteStatus`, asks the user to confirm the deduction amount, then passes plain values into `KessanshoService.build(...)`. `KessanshoLineMapping` maps the 33-account chart onto legal expense rows (standard rows + 5 blank 空欄 + 雑費 overflow). `PDFReportService.renderKessansho(report:)` renders the structured PDF.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing (`import Testing`, `#expect`) / UIKit (`UIGraphicsPDFRenderer`). Source files under `SnapKei/` are auto-included (`PBXFileSystemSynchronizedRootGroup`) — no `project.pbxproj` edits.

**Spec reference:** `docs/superpowers/specs/2026-06-09-snapkei-p2a-kessansho-design.md`

**Working directory:** `/Users/lee/workspace/SnapKei/`. All paths are repo-relative.

**User preferences carried forward:**
- Do NOT `git push`.
- Do NOT `git commit` without explicit user confirmation. Commit snippets below are checkpoint suggestions only.
- Run the full test suite at the end of every task that changes code.

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Baseline before this plan: `** TEST SUCCEEDED **`, 137 tests.

**Review fixes applied to this plan:**
- The output is described as a structured review/PDF summary, not a pixel-faithful official form.
- `KessanshoReport.ProfitAndLoss.expenseRows` uses top-level `KessanshoExpenseLine` for testability.
- All computations exclude voided entries consistently.
- Monthly revenue and rent details use the same debit/credit sign conventions as `ProfitAndLossService`.
- Depreciation rows prefer posted depreciation journal entries for the fiscal year and compute year-end balance from posted depreciation through that year, avoiding double-counting after year-end depreciation has run.
- 青色申告特別控除額 is treated as a user-confirmed selection; `ControlRouteStatus.estimatedDeduction` is only the default suggestion.
- UI includes pre-export checks, empty/error states, accessible amount rows, Japanese number formatting, and export confirmation warnings.
- Mapping tests cover every seed expense code, not only a sample.

---

## File Structure

```
SnapKei/
├── Domain/Services/
│   ├── KessanshoLineMapping.swift   [CREATE]
│   ├── KessanshoService.swift       [CREATE]
│   ├── AccountCode.swift            [MODIFY — add rent]
│   └── PDFReportService.swift       [MODIFY — add renderKessansho(report:)]
└── Presentation/Reports/
    ├── KessanshoView.swift          [CREATE]
    └── BooksView.swift              [MODIFY — add 青色申告決算書 link + guidance]
SnapKeiTests/
├── KessanshoLineMappingTests.swift  [CREATE]
└── KessanshoServiceTests.swift      [CREATE]
```

---

## Task 1: KessanshoLineMapping (account → legal expense row)

**Files:**
- Create: `SnapKei/Domain/Services/KessanshoLineMapping.swift`
- Test: `SnapKeiTests/KessanshoLineMappingTests.swift`

- [ ] **Step 1: Write failing tests first**

Create `KessanshoLineMappingTests` with these test cases:

1. `mapsAllSeedExpenseCodesToExpectedRows_tableDriven`
   - Input every seed expense code from the spec table: `5100, 5110, 5120, 5130, 5140, 5150, 5160, 5170, 5180, 5190, 5200, 5210, 5220, 5230, 5290`.
   - Expected output order:
     `租税公課`, `水道光熱費`, `旅費交通費`, `通信費`, `接待交際費`, `修繕費`, `消耗品費`, `減価償却費`, `外注工賃`, `地代家賃`, then custom rows `会議費`, `事務用品費`, `新聞図書費`, `支払手数料`, then `雑費`.
   - Each row amount should equal its account amount; use distinct small amounts so wrong aggregation is obvious.

2. `customAccountsBecomeBlankRows_orderedByCode`
   - Four non-standard accounts become 空欄 rows labeled by `accountNameByCode`, sorted by ascending code.

3. `sixthCustomFoldsIntoMisc`
   - First five custom rows remain custom; the sixth and later custom rows are summed into `雑費`.

4. `zeroAmountRowsAreOmitted`
   - Standard and custom rows with zero amount are omitted.

5. `miscAccountAndOverflowCombine`
   - Seed `5290` plus overflow custom amounts combine into one `雑費` line.

- [ ] **Step 2: Run tests to verify RED**

Run the standard test command. Expected: compile failure because `KessanshoLineMapping` and `KessanshoExpenseLine` do not exist.

- [ ] **Step 3: Implement mapping**

Create `KessanshoLineMapping.swift`:

- `public struct KessanshoExpenseLine: Equatable, Sendable, Identifiable`
  - `id` is `label`.
  - `label: String`, `amount: Int`.
- `public enum KessanshoLineMapping`
  - `legalRows` in official expense-row order, excluding `雑費` so misc can always be last.
  - `miscRow = "雑費"`, `blankRowLimit = 5`.
  - `standardRowByCode` for all standard seed mappings:
    - `5100 -> 旅費交通費`
    - `5110 -> 通信費`
    - `5120 -> 接待交際費`
    - `5140 -> 消耗品費`
    - `5170 -> 水道光熱費`
    - `5180 -> 地代家賃`
    - `5190 -> 外注工賃`
    - `5210 -> 修繕費`
    - `5220 -> 租税公課`
    - `5230 -> 減価償却費`
    - `5290 -> 雑費`
  - Unknown/non-standard codes become custom rows by ascending account code; after 5 custom rows, overflow folds into `雑費`.
  - Omit zero-amount rows.

- [ ] **Step 4: Run tests to verify GREEN**

Run the standard test command. Expected: `** TEST SUCCEEDED **` and 5 new tests.

- [ ] **Step 5: Checkpoint**

If the user explicitly asks to commit, use:

```bash
git add SnapKei/Domain/Services/KessanshoLineMapping.swift SnapKeiTests/KessanshoLineMappingTests.swift
git commit -m "feat: map accounts to kessansho expense rows"
```

---

## Task 2: KessanshoReport value model + KessanshoService.build

**Files:**
- Create: `SnapKei/Domain/Services/KessanshoService.swift`
- Modify: `SnapKei/Domain/Services/AccountCode.swift`
- Test: `SnapKeiTests/KessanshoServiceTests.swift`

- [ ] **Step 1: Add account code constant**

In `AccountCode`, add:

```swift
public static let rent = "5180"                      // 地代家賃
```

- [ ] **Step 2: Write failing tests first**

Create `KessanshoServiceTests` covering:

1. `profitAndLoss_workedExample`
   - FY2026 sample with opening 現金 100,000 / 元入金 -100,000.
   - Entries: sale 110,000; communication expense 11,000; asset acquisition 240,000; posted depreciation expense 24,000; posted owner portion 6,000.
   - Assert sales 110,000, expenses `[通信費 11,000, 減価償却費 24,000]`, expenseTotal 35,000, netBeforeDeduction 75,000, blueDeduction capped to 75,000, income 0.

2. `blueDeduction_zeroRoute_givesFullIncome`
   - With confirmed max deduction 0, income remains 75,000.

3. `voidedEntriesExcludedEverywhere`
   - Voided sale/expense/depreciation/rent entries must not affect P/L, monthly, depreciation rows, rent details, or balance sheet inputs.

4. `monthlyRevenue_usesProfitAndLossSignRules`
   - Credit revenue increases month sales.
   - Debit revenue decreases month sales.
   - Monthly sum equals `profitAndLoss.salesRevenue`.

5. `depreciation_prefersPostedEntriesAndAvoidsDoubleCounting`
   - Asset has `accumulatedDepreciation = 30_000` and `bookValue = 210_000` after `runDepreciation`.
   - FY2026 depreciation journal entries total 30,000 (`5230` 24,000 + `3220` 6,000) with `sourceType: .depreciation` and `relatedFixedAssetId`.
   - Assert one row: `yearDepreciation = 30_000`, `deductibleAmount = 24_000`, `yearEndBalance = 210_000`.
   - This protects against subtracting the same year depreciation twice.

6. `depreciation_projectedWhenNotPosted`
   - If no FY depreciation entries exist, use `DepreciationService.annualAmount` as projected values and compute year-end balance from current accumulated + projected full amount.

7. `rentDetails_groupedByPayee_usesDebitCreditSignsAndOriginalAmount`
   - Debit rent adds to annual/deductible.
   - Credit rent subtracts from annual/deductible.
   - `originalAmountIncludingTax` is used for annual rent with the same sign.

8. `rentDetails_emptyWhenNoRent`

9. `balanceSheet_balances_workedExample`

- [ ] **Step 3: Run tests to verify RED**

Run the standard test command. Expected: compile failure because `KessanshoService`, `KessanshoReport`, and `AccountCode.rent` do not exist.

- [ ] **Step 4: Implement KessanshoReport + build**

Create `KessanshoService.swift` with:

- `public struct KessanshoReport: Equatable, Sendable`
  - `Header(fiscalYear, ownerName, businessName)`
  - `ProfitAndLoss(salesRevenue, costOfGoodsSold, grossProfit, expenseRows: [KessanshoExpenseLine], expenseTotal, netBeforeDeduction, blueDeduction, income)`
  - `MonthlyRow(month, sales, purchases)`
  - `DepreciationRow(assetId, assetName, acquisitionYearMonth, acquisitionAmount, method, usefulLifeYears, yearDepreciation, businessRatePercent, deductibleAmount, yearEndBalance, isPosted)`
  - `RentRow(payee, annualRent, deductibleAmount)`
  - `balanceSheet: BalanceSheetReport`

`KessanshoService.build(...)` rules:

- Define both `targetYearEntries = entries.filter { $0.fiscalYear == fiscalYear && !$0.isVoided }` and `nonVoidedEntriesThroughFiscalYear = entries.filter { $0.fiscalYear <= fiscalYear && !$0.isVoided }`.
- Use `ProfitAndLossService.summary(entries: targetYearEntries, accounts: accounts)` for annual revenue/expense totals.
- `blueDeduction = min(maxBlueDeduction, max(0, netBeforeDeduction))`; caller is responsible for making `maxBlueDeduction` a user-confirmed amount.
- Monthly revenue uses P/L sign rules:
  - If credit account is revenue: add amount to that month.
  - If debit account is revenue: subtract amount from that month.
- Depreciation rows:
  - For each non-deleted asset whose service start year is <= fiscal year, inspect non-voided depreciation entries with `entry.relatedFixedAssetId == asset.syncId`. Existing year-end depreciation postings use `FixedAsset.syncId`, not `FixedAsset.id`.
  - `DepreciationRow.assetId` should use `asset.syncId` so it is stable across the reporting row and posted journal-entry relation.
  - If entries exist for the target fiscal year, use posted values: `yearDepreciation` is all matching depreciation-entry amounts for the year; `deductibleAmount` is matching entries with debit `AccountCode.depreciationExpense`; `yearEndBalance` is `acquisitionAmount - posted depreciation total through fiscalYear`, clamped >= 0; `isPosted = true`.
  - If no posted entries exist for the target fiscal year, use `DepreciationService.annualAmount(for:fiscalYear:)`; omit rows where projected full amount is 0; `isPosted = false`.
- Rent details:
  - Debit `AccountCode.rent` adds; credit `AccountCode.rent` subtracts.
  - `annualRent` uses `originalAmountIncludingTax ?? amountIncludingTax` with the same sign.
  - `deductibleAmount` uses `amountIncludingTax` with the same sign.
  - Group by `counterpartyName`, sorted by payee; omit zero rows.
- Balance sheet uses `BalanceSheetService.report(fiscalYear: entries: targetYearEntries, openingBalances: openingBalances, accounts: accounts)`.

- [ ] **Step 5: Run tests to verify GREEN**

Run the standard test command. Expected: `** TEST SUCCEEDED **` and the new service tests pass.

- [ ] **Step 6: Checkpoint**

If the user explicitly asks to commit, use:

```bash
git add SnapKei/Domain/Services/KessanshoService.swift SnapKei/Domain/Services/AccountCode.swift SnapKeiTests/KessanshoServiceTests.swift
git commit -m "feat: build kessansho report model"
```

---

## Task 3: PDF renderer

**Files:**
- Modify: `SnapKei/Domain/Services/PDFReportService.swift`

No unit test; verified by build + final smoke because the repo's PDF/view convention is build/manual verification.

- [ ] **Step 1: Add renderKessansho**

Add `public static func renderKessansho(report: KessanshoReport) -> Data` inside `PDFReportService`'s UIKit implementation.

Requirements:

- Use `UIGraphicsPDFRenderer` with readable multi-page layout.
- Render sections: overview checks, 損益計算書, 月別売上, 減価償却費の計算, 地代家賃の内訳 when non-empty, 貸借対照表 summary.
- Use a local Japanese number formatter so amounts render like `¥110,000`, not `¥110000`.
- Include an explicit note near the title: `申告内容の確認用サマリーです。国税庁の公式様式そのものではありません。`
- Show depreciation rows as `計上済` or `未計上見込` based on `isPosted`.
- Do not silently omit warnings: if balance sheet is not balanced, render a visible warning line.

- [ ] **Step 2: Build to verify compile**

Run:

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Checkpoint**

If the user explicitly asks to commit, use:

```bash
git add SnapKei/Domain/Services/PDFReportService.swift
git commit -m "feat: render kessansho PDF summary"
```

---

## Task 4: KessanshoView + BooksView link

**Files:**
- Create: `SnapKei/Presentation/Reports/KessanshoView.swift`
- Modify: `SnapKei/Presentation/Reports/BooksView.swift`

No unit test; verified by build + final smoke.

- [ ] **Step 1: Create KessanshoView**

`KessanshoView(fiscalYear:)` requirements:

- Query `JournalEntry`, `Account`, non-deleted `FixedAsset`, and `SystemActivityLog` (or otherwise obtain audit-log presence) so `ControlRouteStatus.load(hasEntries:hasAuditLog:)` can compute the estimated deduction route.
- Load opening balances through `OpeningBalanceStore`. If loading fails, display a visible warning instead of silently using `{}`.
- Derive `ControlRouteStatus.estimatedDeduction`, then expose a `Picker` or segmented selection for user-confirmed 青色申告特別控除額: `0`, `100,000`, `550,000`, `650,000`. Default to the estimate, but label it as estimated.
- Build the report from the confirmed deduction amount.
- At the top, show `申告前チェック` with at least:
  - 年度
  - 氏名/屋号 present or missing
  - 仕訳件数
  - 青色申告特別控除額
  - 減価償却 rows all posted or includes 未計上見込
  - 貸借一致 / 貸借不一致
  - 期首残高読み込み error if any
- If no entries exist for the year, show an empty-state message and keep PDF export behind confirmation.
- If owner name/business name are blank, balance sheet is not balanced, opening balance load failed, or depreciation contains projected rows, show warning copy before export.
- The on-screen review must then show the report sections in the same core order as the PDF: `損益計算書`, `月別売上`, `減価償却費の計算`, `地代家賃の内訳`, and `貸借対照表 summary`. Hide `地代家賃の内訳` when empty or show explicit empty copy; the user must be able to inspect the key values before PDF export.
- PDF button opens a confirmation dialog when warnings exist; it should not silently generate a filing-looking document.
- Amount rows use a reusable Japanese currency/decimal formatter.
- Amount rows combine label and value for VoiceOver via `.accessibilityElement(children: .combine)` and provide a PDF button hint.
- Large labels/details can wrap instead of truncating.

- [ ] **Step 2: Link from BooksView**

In `BooksView`, add `NavigationLink("青色申告決算書") { KessanshoView(fiscalYear: selectedYear) }` as the first entry in `Section("決算書")`.

Add a footer/guidance line for the section, for example:

`青色申告決算書は損益計算書・貸借対照表・減価償却の内容を申告用にまとめます。出力前に年次締めと減価償却を確認してください。`

- [ ] **Step 3: Build + full test run**

Run the standard test command. Expected: `** TEST SUCCEEDED **`, no new failures.

- [ ] **Step 4: Checkpoint**

If the user explicitly asks to commit, use:

```bash
git add SnapKei/Presentation/Reports/KessanshoView.swift SnapKei/Presentation/Reports/BooksView.swift
git commit -m "feat: add kessansho review screen"
```

---

## Task 5: Final verification

- [ ] **Step 1: Clean full test run**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO clean test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 2: Manual smoke (simulator)**

- Seed data: via Capture, add a sale and an expense for the current year; in Settings set 屋号/氏名; add a fixed asset and run 決算 → 減価償却を計上.
- 帳簿 tab → select the year → 青色申告決算書.
- Confirm:
  - 損益計算書 totals match P/L.
  - 月別売上 sum equals annual revenue.
  - 減価償却 row is `計上済` after year-end depreciation.
  - 貸借対照表 shows 一致.
  - Warnings appear for missing profile info, unbalanced B/S, opening balance load failure, or projected depreciation.
  - PDF export confirmation appears when warnings exist.
  - PDF file name is `青色申告決算書_<year>.pdf` and includes the review-summary disclaimer.

- [ ] **Step 3: Report results to the user**

List test/build output and any deviations. Do not push.

---

## Out-of-Scope / Known Limits

- Pixel-faithful official government form layout remains out of scope.
- Official filing fields not modeled by SnapKei, such as address and full rental/property details, are not invented. The UI/PDF must make this clear as a review summary.
- Historical fixed-asset accuracy depends on posted depreciation entries through the selected fiscal year. If depreciation was never posted for historical years, projected rows are shown as `未計上見込`.
- e-Tax `.xtx` export remains P3.
