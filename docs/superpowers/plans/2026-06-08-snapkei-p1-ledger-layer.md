# SnapKei P1: Ledger Layer (帳簿層) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give SnapKei real books and a year-end closing MVP: 仕訳帳 (journal book), 総勘定元帳 (general ledger with running balances), 残高試算表 (trial balance), 貸借対照表 (balance sheet with 期首残高 and 元入金 rollover), and a year-end closing flow (減価償却 auto-posting → 連番/残高 validation → fiscal-year lock → rollover). These outputs support self-filing preparation; they do **not** guarantee 55万/65万円 青色申告特別控除 eligibility or constitute tax advice.

**Architecture:** Pure-function reporting services in `Domain/Services` (`LedgerService`, `TrialBalanceService`, `ProfitAndLossService`, `BalanceSheetService`) operate on `[JournalEntry]` + opening-balance dictionaries so they are trivially testable. Two new SwiftData entities (`OpeningBalance`, `FiscalYearClosure`) carry year-boundary state. A stateful `YearEndClosingService` orchestrates depreciation posting (through the existing repository so numbering/audit/sync all apply) and the close/reopen lifecycle. New screens live under `Presentation/Ledger/` and hang off the Home tab's 帳簿・レポート section.

**Sign convention (used everywhere internally):** balances are **debit-signed** integers — assets/expenses positive, liabilities/equity/revenue negative. Views convert to display sign per section. A balanced book ⇔ Σ(all debit-signed balances incl. opening) = 0.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing. Source files under `SnapKei/` are auto-included (`PBXFileSystemSynchronizedRootGroup`) — **no** `project.pbxproj` edits in this plan.

**Prerequisite:** P0 plan (`2026-06-08-snapkei-p0-launch-hardening.md`) Task 0 baseline checkpoint. Before exposing P1 screens to cloud-sync accounts, P0 onboarding/disclaimer, privacy docs, and account-boundary sync hardening must also be complete.

**Working directory:** `/Users/lee/workspace/SnapKei/`.

**User preferences (carried over):**
- Do NOT `git push`.
- **Ask for explicit confirmation before every `git commit`.**
- Build verification at the end of every task.

**Execution amendments from plan review (must apply before implementation):**
- Respect the existing configurable fiscal year (`AppSettings.fiscalYearStartMonth`) everywhere. Add a shared fiscal calendar helper before services use fiscal-year dates, or explicitly remove/lock the setting to January for v1. Do not hardcode Dec 31/current calendar year in production code without that decision.
- `OpeningBalance` and `FiscalYearClosure` must be included in cloud sync (`SnapKeiChangeCollector`/`SnapKeiMerger`) with tests, or P1 screens must be explicitly local-only and hidden for cloud-sync accounts. The preferred fix is to sync these entities.
- `close(fiscalYear:)` must not allow users to skip depreciation. It should either call `runDepreciation()` internally before validation or fail with a clear unposted-depreciation error. Tests must cover this.
- Depreciation posting must be idempotent at the expected-posting level, not merely “any depreciation entry exists for this asset/year.” A partial crash after one entry must not permanently skip the missing owner/business split entry or the asset update.
- Repository lock errors (`RepositoryError.fiscalYearClosed`) must be surfaced in Capture/edit/void UI, with a user-readable message.
- Reopen audit must be service-enforced: non-empty reason, actor device/account recorded, and append-only activity logs retained.

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | tail -10
```

**Convention note:** pure SwiftUI views follow the existing repo convention of no view tests; all services/entities get swift-testing coverage.

---

## File Structure (created/modified by this plan)

```
SnapKei/
├── Domain/
│   ├── Entities/
│   │   ├── Enums.swift                       [MODIFY: remove decliningBalance]
│   │   ├── OpeningBalance.swift              [CREATE — @Model 期首残高]
│   │   └── FiscalYearClosure.swift           [CREATE — @Model 年度締め]
│   └── Services/
│       ├── AccountCode.swift                 [CREATE — well-known 科目コード]
│       ├── DepreciationService.swift         [MODIFY: full/deductible split]
│       ├── LedgerService.swift               [CREATE — postings/元帳/連番検証]
│       ├── TrialBalanceService.swift         [CREATE]
│       ├── ProfitAndLossService.swift        [CREATE — extracted from PDF]
│       ├── BalanceSheetService.swift         [CREATE]
│       ├── YearEndClosingService.swift       [CREATE]
│       ├── LedgerCSVExportService.swift      [CREATE]
│       ├── CSVExportService.swift            [MODIFY: escape → internal]
│       └── PDFReportService.swift            [MODIFY: use PL service; add B/S render]
├── Data/Persistence/
│   ├── ModelContainer+SnapKei.swift          [MODIFY: schema += 2 models]
│   ├── ExpenseRepository.swift               [MODIFY: fiscal-year lock guards]
│   └── OpeningBalanceStore.swift             [CREATE]
└── Presentation/
    ├── Home/HomeView.swift                   [MODIFY: 帳簿・レポート section + year picker]
    └── Ledger/
        ├── JournalBookView.swift             [CREATE]
        ├── GeneralLedgerView.swift           [CREATE]
        ├── TrialBalanceView.swift            [CREATE]
        ├── BalanceSheetView.swift            [CREATE]
        ├── OpeningBalanceView.swift          [CREATE]
        └── YearEndClosingView.swift          [CREATE]
SnapKeiTests/
├── EnumsTests.swift                          [MODIFY]
├── DepreciationServiceTests.swift            [MODIFY: add full/deductible tests]
├── LedgerServiceTests.swift                  [CREATE]
├── TrialBalanceServiceTests.swift            [CREATE]
├── ProfitAndLossServiceTests.swift           [CREATE]
├── BalanceSheetServiceTests.swift            [CREATE]
├── OpeningBalanceStoreTests.swift            [CREATE]
├── YearEndClosingServiceTests.swift          [CREATE]
├── LedgerCSVExportServiceTests.swift         [CREATE]
└── ExpenseRepositoryTests.swift              [MODIFY: lock-guard tests]
```

**Out of scope for P1** (P2+): 青色申告決算書の法定様式 (4-page NTA form), 確定申告書 第一表/第二表, 所得控除/税額計算, 消費税申告, e-Tax/.xtx 出力, 棚卸 (期首/期末商品 — the seed has no 仕入 account yet), 家事按分の年末レビュー画面, 貸倒引当金, custom account UI.

---

## Shared worked example (used by multiple test suites)

Fiscal year 2026, JST. Opening balances (debit-signed): 現金 `1110` = +100,000; 元入金 `3110` = −100,000.

| # | 取引 | 借方 | 貸方 | 金額 |
|---|---|---|---|---|
| 1 | 売上入金 | 1110 現金 | 4110 売上高 | 110,000 |
| 2 | 通信費 (事業主借払い) | 5110 通信費 | 3210 事業主借 | 11,000 |
| 3 | PC 購入 240,000 (事業主借払い) | 1610 工具器具備品 | 3210 事業主借 | 240,000 |
| 4 | (取消済み) 雑費 | 5290 | 1110 | 5,000 — `isVoided = true` |

FixedAsset: PC, acquisition 240,000, life 4 years, serviceStart 2026-07-01, businessAllocationRate 0.8 → year-2026 depreciation full = 240,000/4 × 6/12 = **30,000**; deductible = 30,000 × 0.8 = **24,000**; owner portion = **6,000**. After `runDepreciation` two more entries exist:

| # | 借方 | 貸方 | 金額 |
|---|---|---|---|
| 5 | 5230 減価償却費 | 1710 減価償却累計額 | 24,000 |
| 6 | 3220 事業主貸 | 1710 減価償却累計額 | 6,000 |

Expected results (excluding voided #4):
- 現金 ledger closing: 100,000 + 110,000 = **210,000**
- P/L: revenue 110,000 − expenses (11,000 + 24,000) = net income **75,000**
- Trial balance: total debits = total credits = **391,000** (110,000+11,000+240,000+24,000+6,000)
- B/S 資産: 現金 210,000 + 工具器具備品 240,000 + 減価償却累計額 ▲30,000 + 事業主貸 6,000 = **426,000**
- B/S 負債・資本: 事業主借 251,000 + 元入金 100,000 + 所得 75,000 = **426,000** ✓
- Rollover 元入金 (2027): 100,000 + 75,000 + 251,000 − 6,000 = **420,000**; carried assets 420,000 ⇒ 2027 openings sum to 0 ✓

---

### Task 1: Remove the unimplemented 定率法 (`decliningBalance`)

**Background:** `DepreciationMethod.decliningBalance` silently computes 定額法 (`DepreciationService.swift:19`) — a wrong number presented as right. No UI ever sets it; 個人事業主 default by law is 定額法 (定率法 requires a 届出). Pre-launch, with no persisted user data, removing the case is safe: `SnapKeiMerger.applyFixedAsset` already `guard`s on `DepreciationMethod(rawValue:)` and skips unknown values from sync.

**Files:**
- Modify: `SnapKei/Domain/Entities/Enums.swift:47-50`
- Modify: `SnapKei/Domain/Services/DepreciationService.swift:17-22`
- Modify: `SnapKeiTests/EnumsTests.swift:33-36`

- [ ] **Step 1: Update the test first**

In `SnapKeiTests/EnumsTests.swift` replace the `depreciationMethodRawValues` test (lines 33–36):

```swift
    @Test func depreciationMethodRawValues() {
        #expect(DepreciationMethod.straightLine.rawValue == "straightLine")
        #expect(DepreciationMethod.allCases == [.straightLine])
    }
```

- [ ] **Step 2: Run tests — expect FAIL** (`allCases` still contains `.decliningBalance`).

- [ ] **Step 3: Remove the case**

In `Enums.swift` replace:

```swift
public enum DepreciationMethod: String, Codable, Sendable, CaseIterable {
    case straightLine
    case decliningBalance
}
```

with:

```swift
public enum DepreciationMethod: String, Codable, Sendable, CaseIterable {
    case straightLine
    // NOTE: 定率法 (decliningBalance) was removed pre-launch — it was silently computing 定額法.
    // Reintroduce only with a correct 200%定率法 implementation (償却率/改定償却率/保証率).
}
```

In `DepreciationService.swift` replace the inner switch (lines 17–21):

```swift
        case .normalDepreciation:
            return straightLineAnnual(asset: asset, fiscalYear: fiscalYear, calendar: calendar)
```

(Delete the now-redundant `switch asset.depreciationMethod`.)

- [ ] **Step 4: Run full tests — expect PASS.**

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Entities/Enums.swift SnapKei/Domain/Services/DepreciationService.swift SnapKeiTests/EnumsTests.swift
git commit -m "fix: remove unimplemented declining-balance depreciation method"
```

---

### Task 2: DepreciationService — full vs. deductible amounts

**Background:** The 決算書's 減価償却費の計算 table and correct journalization need **both** the full depreciation (本年分の償却費合計 — reduces book value) and the business-deductible portion (必要経費算入額 = full × 事業専用割合). The current API returns only the allocated amount.

**Files:**
- Modify: `SnapKei/Domain/Services/DepreciationService.swift`
- Modify: `SnapKeiTests/DepreciationServiceTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

Append to the existing suite in `SnapKeiTests/DepreciationServiceTests.swift`:

```swift
    @Test func annualAmount_splitsFullAndDeductible_byBusinessRate() {
        let asset = FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.8
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 30_000)        // 240000/4 × 6/12
        #expect(amount.deductible == 24_000)  // × 0.8
        #expect(amount.ownerPortion == 6_000)
    }

    @Test func annualAmount_fullAllocation_hasNoOwnerPortion() {
        let asset = FixedAsset(
            assetName: "サーバー",
            assetCategoryCode: "SERVER",
            acquisitionDate: date("2026-01-01"),
            serviceStartDate: date("2026-01-01"),
            acquisitionAmount: 500_000,
            usefulLifeYears: 5,
            treatment: .normalDepreciation
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 100_000)
        #expect(amount.deductible == 100_000)
        #expect(amount.ownerPortion == 0)
    }

    @Test func annualAmount_lumpSum_splitsToo() {
        let asset = FixedAsset(
            assetName: "事務机",
            assetCategoryCode: "FURNITURE",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 150_000,
            usefulLifeYears: 8,
            treatment: .lumpSumDepreciation,
            businessAllocationRate: 0.5
        )
        let amount = DepreciationService.annualAmount(for: asset, fiscalYear: 2026)
        #expect(amount.full == 50_000)
        #expect(amount.deductible == 25_000)
    }
```

- [ ] **Step 2: Run — expect compile failure** (`annualAmount` undefined).

- [ ] **Step 3: Implement**

Replace the full contents of `SnapKei/Domain/Services/DepreciationService.swift`:

```swift
import Foundation

public struct DepreciationAmount: Equatable, Sendable {
    /// 本年分の償却費合計 — reduces the asset's book value regardless of 家事按分.
    public let full: Int
    /// 必要経費算入額 = full × 事業専用割合 (rounded down).
    public let deductible: Int
    /// 家事分 (事業主貸で処理する部分).
    public var ownerPortion: Int { full - deductible }

    public init(full: Int, deductible: Int) {
        self.full = full
        self.deductible = deductible
    }
}

public enum DepreciationService {
    public static func annualAmount(for asset: FixedAsset, fiscalYear: Int) -> DepreciationAmount {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        if fiscalYear < acquisitionYear { return DepreciationAmount(full: 0, deductible: 0) }
        if asset.accumulatedDepreciation >= asset.acquisitionAmount { return DepreciationAmount(full: 0, deductible: 0) }

        let fullBase: Double
        switch asset.treatment {
        case .smallAmountFullExpense:
            return DepreciationAmount(full: 0, deductible: 0)
        case .lumpSumDepreciation:
            fullBase = Double(asset.acquisitionAmount) / 3.0
        case .normalDepreciation:
            let baseAnnual = Double(asset.acquisitionAmount) / Double(asset.usefulLifeYears)
            let acquisitionMonth = calendar.component(.month, from: asset.serviceStartDate)
            if fiscalYear == acquisitionYear {
                let monthsInUse = max(0, 13 - acquisitionMonth)
                fullBase = baseAnnual * Double(monthsInUse) / 12.0
            } else {
                fullBase = baseAnnual
            }
        }

        let remaining = asset.acquisitionAmount - asset.accumulatedDepreciation
        let full = min(Int(fullBase.rounded(.down)), remaining)
        let deductible = Int((Double(full) * asset.businessAllocationRate).rounded(.down))
        return DepreciationAmount(full: full, deductible: deductible)
    }

    /// Legacy API — business-deductible portion only.
    public static func annualDepreciation(for asset: FixedAsset, fiscalYear: Int) -> Int {
        annualAmount(for: asset, fiscalYear: fiscalYear).deductible
    }

    public static func suggestTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate)
    }
}
```

**Rounding note:** the old code floored once after multiplying the fractional base by the rate; the new code floors `full` first, then the rate product. For every existing test fixture the results are identical (verified: 480,000/4 prorated, 240,000/5 ×0.5, 150,000/3). If any existing test fails on an off-by-one, the new behavior is the correct 決算書-style one — update the fixture, not the implementation.

- [ ] **Step 4: Run full tests — expect PASS** (existing 6 + new 3).

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/DepreciationService.swift SnapKeiTests/DepreciationServiceTests.swift
git commit -m "feat: depreciation returns full + deductible split for kessansho and journalization"
```

---

### Task 3: Well-known account codes + LedgerService (postings, 元帳 lines, 連番検証)

**Files:**
- Create: `SnapKei/Domain/Services/AccountCode.swift`
- Create: `SnapKei/Domain/Services/LedgerService.swift`
- Test: `SnapKeiTests/LedgerServiceTests.swift`

- [ ] **Step 1: Create AccountCode constants** (no test needed — constants only)

Create `SnapKei/Domain/Services/AccountCode.swift`:

```swift
import Foundation

/// Well-known codes from accounts_seed.json used by services.
public enum AccountCode {
    public static let cash = "1110"                      // 現金
    public static let equipment = "1610"                 // 工具器具備品
    public static let accumulatedDepreciation = "1710"   // 減価償却累計額 (contra-asset)
    public static let capital = "3110"                   // 元入金
    public static let ownerLoan = "3210"                 // 事業主借
    public static let ownerDraw = "3220"                 // 事業主貸
    public static let depreciationExpense = "5230"       // 減価償却費
}
```

- [ ] **Step 2: Write the failing tests**

Create `SnapKeiTests/LedgerServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("LedgerService")
struct LedgerServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    private func entry(number: Int, day: String, debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number, fiscalYear: 2026, transactionDate: date(day),
            debitAccountCode: debit, creditAccountCode: credit,
            amountIncludingTax: amount, amountExcludingTax: amount, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "相手\(number)", transactionDescription: "取引\(number)",
            sourceType: .manual, isVoided: voided
        )
    }

    private var fixture: [JournalEntry] {
        [
            entry(number: 1, day: "2026-01-10", debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, day: "2026-02-05", debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, day: "2026-03-01", debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, day: "2026-03-15", debit: "5290", credit: "1110", amount: 5_000, voided: true),
        ]
    }

    @Test func postings_twoPerEntry_balanced() {
        let postings = LedgerService.postings(from: fixture)
        #expect(postings.count == 8)
        let totalDebit = postings.reduce(0) { $0 + $1.debit }
        let totalCredit = postings.reduce(0) { $0 + $1.credit }
        #expect(totalDebit == totalCredit)
    }

    @Test func ledgerLines_runningBalance_debitSigned_excludesVoided() {
        let lines = LedgerService.ledgerLines(accountCode: "1110", openingBalance: 100_000, entries: fixture)
        #expect(lines.count == 1)                        // voided #4 excluded
        #expect(lines[0].debit == 110_000)
        #expect(lines[0].runningBalance == 210_000)
    }

    @Test func ledgerLines_creditAccount_negativeRunningBalance() {
        let lines = LedgerService.ledgerLines(accountCode: "3210", openingBalance: 0, entries: fixture)
        #expect(lines.count == 2)
        #expect(lines[0].credit == 11_000)
        #expect(lines[0].runningBalance == -11_000)
        #expect(lines[1].runningBalance == -251_000)
    }

    @Test func missingEntryNumbers_detectsGaps() {
        let entries = [
            entry(number: 1, day: "2026-01-01", debit: "1110", credit: "4110", amount: 1),
            entry(number: 3, day: "2026-01-02", debit: "1110", credit: "4110", amount: 1),
            entry(number: 5, day: "2026-01-03", debit: "1110", credit: "4110", amount: 1),
        ]
        #expect(LedgerService.missingEntryNumbers(entries: entries) == [2, 4])
        #expect(LedgerService.missingEntryNumbers(entries: fixture) == [])
        #expect(LedgerService.missingEntryNumbers(entries: []) == [])
    }
}
```

- [ ] **Step 3: Run — expect compile failure.**

- [ ] **Step 4: Implement LedgerService**

Create `SnapKei/Domain/Services/LedgerService.swift`:

```swift
import Foundation

/// One side of a journal entry posted to one account.
public struct LedgerPosting: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryId: UUID
    public let entryNumber: Int
    public let transactionDate: Date
    public let accountCode: String
    public let counterAccountCode: String
    public let debit: Int
    public let credit: Int
    public let summary: String
    public let isVoided: Bool
}

/// 総勘定元帳 line with running balance (debit-signed: assets/expenses positive).
public struct LedgerLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryNumber: Int
    public let transactionDate: Date
    public let counterAccountCode: String
    public let summary: String
    public let debit: Int
    public let credit: Int
    public let runningBalance: Int
}

public enum LedgerService {
    /// Expand entries into per-account postings (two per entry), sorted by (date, entryNumber).
    public static func postings(from entries: [JournalEntry]) -> [LedgerPosting] {
        entries
            .sorted { ($0.transactionDate, $0.entryNumber) < ($1.transactionDate, $1.entryNumber) }
            .flatMap { entry -> [LedgerPosting] in
                let summary = "\(entry.counterpartyName) \(entry.transactionDescription)"
                return [
                    LedgerPosting(
                        id: "\(entry.id)-d", entryId: entry.id, entryNumber: entry.entryNumber,
                        transactionDate: entry.transactionDate,
                        accountCode: entry.debitAccountCode, counterAccountCode: entry.creditAccountCode,
                        debit: entry.amountIncludingTax, credit: 0,
                        summary: summary, isVoided: entry.isVoided
                    ),
                    LedgerPosting(
                        id: "\(entry.id)-c", entryId: entry.id, entryNumber: entry.entryNumber,
                        transactionDate: entry.transactionDate,
                        accountCode: entry.creditAccountCode, counterAccountCode: entry.debitAccountCode,
                        debit: 0, credit: entry.amountIncludingTax,
                        summary: summary, isVoided: entry.isVoided
                    ),
                ]
            }
    }

    /// 総勘定元帳 for one account. `openingBalance` is debit-signed. Voided entries are excluded.
    public static func ledgerLines(accountCode: String, openingBalance: Int, entries: [JournalEntry]) -> [LedgerLine] {
        var balance = openingBalance
        return postings(from: entries)
            .filter { $0.accountCode == accountCode && !$0.isVoided }
            .map { posting in
                balance += posting.debit - posting.credit
                return LedgerLine(
                    id: posting.id,
                    entryNumber: posting.entryNumber,
                    transactionDate: posting.transactionDate,
                    counterAccountCode: posting.counterAccountCode,
                    summary: posting.summary,
                    debit: posting.debit,
                    credit: posting.credit,
                    runningBalance: balance
                )
            }
    }

    /// 青色申告 requires gapless entry numbering [1...max] per fiscal year (voided entries keep their number).
    public static func missingEntryNumbers(entries: [JournalEntry]) -> [Int] {
        let numbers = Set(entries.map(\.entryNumber))
        guard let maxNumber = numbers.max(), maxNumber >= 1 else { return [] }
        return (1...maxNumber).filter { !numbers.contains($0) }
    }
}
```

(Tuple `<` comparison on `(Date, Int)` requires no extension — both are `Comparable`.)

- [ ] **Step 5: Run full tests — expect PASS.**

- [ ] **Step 6: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/AccountCode.swift SnapKei/Domain/Services/LedgerService.swift SnapKeiTests/LedgerServiceTests.swift
git commit -m "feat: ledger postings, general-ledger lines with running balance, entry-sequence validation"
```

---

### Task 4: ProfitAndLossService (extracted) + PDFReportService refactor

**Files:**
- Create: `SnapKei/Domain/Services/ProfitAndLossService.swift`
- Test: `SnapKeiTests/ProfitAndLossServiceTests.swift`
- Modify: `SnapKei/Domain/Services/PDFReportService.swift:13-33`

- [ ] **Step 1: Write the failing test**

Create `SnapKeiTests/ProfitAndLossServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("ProfitAndLossService")
struct ProfitAndLossServiceTests {

    private func account(_ code: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: code, nameZh: code, accountType: type)
    }

    private func entry(debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: debit, creditAccountCode: credit,
            amountIncludingTax: amount, amountExcludingTax: amount, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "x", transactionDescription: "y",
            sourceType: .manual, isVoided: voided
        )
    }

    @Test func summary_taxInclusiveRevenueAndExpenses_excludesVoided() {
        let accounts = [
            account("1110", .asset), account("4110", .revenue),
            account("5110", .expense), account("5230", .expense), account("3210", .equity),
        ]
        let entries = [
            entry(debit: "1110", credit: "4110", amount: 110_000),
            entry(debit: "5110", credit: "3210", amount: 11_000),
            entry(debit: "5230", credit: "3210", amount: 24_000),
            entry(debit: "5110", credit: "1110", amount: 99_999, voided: true),
        ]
        let summary = ProfitAndLossService.summary(entries: entries, accounts: accounts)
        #expect(summary.revenueTotal == 110_000)
        #expect(summary.expenseTotal == 35_000)
        #expect(summary.netIncome == 75_000)
        #expect(summary.expenseByCode["5110"] == 11_000)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement**

Create `SnapKei/Domain/Services/ProfitAndLossService.swift`:

```swift
import Foundation

/// 税込経理方式: amounts are tax-inclusive, matching the rest of the app.
public struct PLSummary: Equatable, Sendable {
    public let revenueByCode: [String: Int]
    public let expenseByCode: [String: Int]

    public var revenueTotal: Int { revenueByCode.values.reduce(0, +) }
    public var expenseTotal: Int { expenseByCode.values.reduce(0, +) }
    public var netIncome: Int { revenueTotal - expenseTotal }
}

public enum ProfitAndLossService {
    public static func summary(entries: [JournalEntry], accounts: [Account]) -> PLSummary {
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var revenueByCode: [String: Int] = [:]
        var expenseByCode: [String: Int] = [:]

        for entry in entries where !entry.isVoided {
            if accountByCode[entry.debitAccountCode]?.accountType == .expense {
                expenseByCode[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            }
            if accountByCode[entry.creditAccountCode]?.accountType == .revenue {
                revenueByCode[entry.creditAccountCode, default: 0] += entry.amountIncludingTax
            }
            // Contra postings (revenue debited / expense credited, e.g. 返金) subtract:
            if accountByCode[entry.debitAccountCode]?.accountType == .revenue {
                revenueByCode[entry.debitAccountCode, default: 0] -= entry.amountIncludingTax
            }
            if accountByCode[entry.creditAccountCode]?.accountType == .expense {
                expenseByCode[entry.creditAccountCode, default: 0] -= entry.amountIncludingTax
            }
        }
        return PLSummary(revenueByCode: revenueByCode, expenseByCode: expenseByCode)
    }
}
```

- [ ] **Step 4: Refactor PDFReportService to delegate**

In `SnapKei/Domain/Services/PDFReportService.swift`, replace lines 13–33 (the fetch + aggregation + totals block) with:

```swift
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && !$0.isVoided }
        ))
        let accounts = try context.fetch(FetchDescriptor<Account>())

        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        let summary = ProfitAndLossService.summary(entries: entries, accounts: accounts)
        let revenueByCode = summary.revenueByCode
        let expenseByCode = summary.expenseByCode
        let revenueTotal = summary.revenueTotal
        let expenseTotal = summary.expenseTotal
        let netIncome = summary.netIncome
```

- [ ] **Step 5: Run full tests — expect PASS.**

- [ ] **Step 6: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/ProfitAndLossService.swift SnapKeiTests/ProfitAndLossServiceTests.swift SnapKei/Domain/Services/PDFReportService.swift
git commit -m "refactor: extract ProfitAndLossService from PDF renderer"
```

---

### Task 5: OpeningBalance entity + OpeningBalanceStore

**Files:**
- Create: `SnapKei/Domain/Entities/OpeningBalance.swift`
- Modify: `SnapKei/Data/Persistence/ModelContainer+SnapKei.swift:28-34`
- Create: `SnapKei/Data/Persistence/OpeningBalanceStore.swift`
- Test: `SnapKeiTests/OpeningBalanceStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SnapKeiTests/OpeningBalanceStoreTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import SnapKei

@Suite("OpeningBalanceStore", .serialized)
struct OpeningBalanceStoreTests {

    @MainActor
    private func makeStore() throws -> OpeningBalanceStore {
        let container = try SnapKeiModelContainer.inMemory()
        TestOpeningContainerRetainer.retain(container)
        return OpeningBalanceStore(context: container.mainContext)
    }

    @MainActor
    @Test func set_and_balances_roundTrip() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)
        let balances = try store.balances(fiscalYear: 2026)
        #expect(balances["1110"] == 100_000)
        #expect(balances["3110"] == -100_000)
        #expect(try store.balances(fiscalYear: 2027).isEmpty)
    }

    @MainActor
    @Test func set_zero_removesRow() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 0)
        #expect(try store.balances(fiscalYear: 2026)["1110"] == nil)
    }

    @MainActor
    @Test func adjustCapitalToBalance_makesSumZero() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2026, accountCode: "1110", amount: 300_000)
        try store.set(fiscalYear: 2026, accountCode: "2310", amount: -50_000)   // 借入金
        try store.adjustCapitalToBalance(fiscalYear: 2026)
        let balances = try store.balances(fiscalYear: 2026)
        #expect(balances[AccountCode.capital] == -250_000)
        #expect(balances.values.reduce(0, +) == 0)
    }

    @MainActor
    @Test func deleteAutoRolled_removesOnlyAutoRows() throws {
        let store = try makeStore()
        try store.set(fiscalYear: 2027, accountCode: "1110", amount: 1_000, isAutoRolled: true)
        try store.set(fiscalYear: 2027, accountCode: "2310", amount: -500, isAutoRolled: false)
        try store.deleteAutoRolled(fiscalYear: 2027)
        let balances = try store.balances(fiscalYear: 2027)
        #expect(balances["1110"] == nil)
        #expect(balances["2310"] == -500)
    }
}

@MainActor
private enum TestOpeningContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Create the entity**

Create `SnapKei/Domain/Entities/OpeningBalance.swift`:

```swift
import Foundation
import SwiftData

/// 期首残高 — debit-signed (資産プラス / 負債・元入金マイナス).
@Model
public final class OpeningBalance {
    @Attribute(.unique) public var id: UUID
    public var fiscalYear: Int
    public var accountCode: String
    public var amount: Int
    /// true when created by the year-end rollover (deleted on reopen).
    public var isAutoRolled: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        fiscalYear: Int,
        accountCode: String,
        amount: Int,
        isAutoRolled: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fiscalYear = fiscalYear
        self.accountCode = accountCode
        self.amount = amount
        self.isAutoRolled = isAutoRolled
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Register in the schema**

In `SnapKei/Data/Persistence/ModelContainer+SnapKei.swift` replace the schema list (lines 28–34):

```swift
    private static let schema = Schema([
        Account.self,
        AssetUsefulLife.self,
        JournalEntry.self,
        SystemActivityLog.self,
        FixedAsset.self,
        OpeningBalance.self
    ])
```

**Note:** `FiscalYearClosure` does not exist until Task 6 — to keep this task compiling on its own, add only `OpeningBalance.self` now and add `FiscalYearClosure.self` in Task 6.

- [ ] **Step 5: Create the store**

Create `SnapKei/Data/Persistence/OpeningBalanceStore.swift`:

```swift
import Foundation
import SwiftData

@MainActor
public final class OpeningBalanceStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func balances(fiscalYear: Int) throws -> [String: Int] {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        ))
        return Dictionary(rows.map { ($0.accountCode, $0.amount) }, uniquingKeysWith: { first, _ in first })
    }

    public func set(fiscalYear: Int, accountCode: String, amount: Int, isAutoRolled: Bool = false) throws {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.accountCode == accountCode }
        ))
        if let existing = rows.first {
            if amount == 0 {
                context.delete(existing)
            } else {
                existing.amount = amount
                existing.isAutoRolled = isAutoRolled
                existing.updatedAt = Date()
            }
        } else if amount != 0 {
            context.insert(OpeningBalance(fiscalYear: fiscalYear, accountCode: accountCode, amount: amount, isAutoRolled: isAutoRolled))
        }
        try context.save()
    }

    /// Set 元入金 so that all opening balances sum to zero (balanced opening B/S).
    public func adjustCapitalToBalance(fiscalYear: Int) throws {
        let all = try balances(fiscalYear: fiscalYear)
        let nonCapitalSum = all.filter { $0.key != AccountCode.capital }.values.reduce(0, +)
        try set(fiscalYear: fiscalYear, accountCode: AccountCode.capital, amount: -nonCapitalSum)
    }

    public func deleteAutoRolled(fiscalYear: Int) throws {
        let rows = try context.fetch(FetchDescriptor<OpeningBalance>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.isAutoRolled }
        ))
        rows.forEach(context.delete)
        try context.save()
    }
}
```

- [ ] **Step 6: Run full tests — expect PASS.**

- [ ] **Step 7: Commit (ask user first)**

```bash
git add SnapKei/Domain/Entities/OpeningBalance.swift SnapKei/Data/Persistence/ SnapKeiTests/OpeningBalanceStoreTests.swift
git commit -m "feat: opening balance entity and store with capital auto-adjust"
```

---### Task 6: TrialBalanceService + FiscalYearClosure + repository lock guards

**Files:**
- Create: `SnapKei/Domain/Services/TrialBalanceService.swift`
- Test: `SnapKeiTests/TrialBalanceServiceTests.swift`
- Create: `SnapKei/Domain/Entities/FiscalYearClosure.swift`
- Modify: `SnapKei/Data/Persistence/ModelContainer+SnapKei.swift` (schema += `FiscalYearClosure.self`)
- Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift`
- Test: `SnapKeiTests/ExpenseRepositoryTests.swift` (append suite)

- [ ] **Step 1: Write the failing TrialBalance test**

Create `SnapKeiTests/TrialBalanceServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("TrialBalanceService")
struct TrialBalanceServiceTests {

    private func account(_ code: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: "科目\(code)", nameZh: code, accountType: type)
    }

    private func entry(number: Int, debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: debit, creditAccountCode: credit,
            amountIncludingTax: amount, amountExcludingTax: amount, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "x", transactionDescription: "y", sourceType: .manual, isVoided: voided
        )
    }

    @Test func report_balancedTotals_andClosingBalances() {
        let accounts = [
            account("1110", .asset), account("1610", .asset),
            account("3210", .equity), account("3110", .equity),
            account("4110", .revenue), account("5110", .expense),
        ]
        let entries = [
            entry(number: 1, debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, debit: "5110", credit: "1110", amount: 9_999, voided: true),
        ]
        let openings = ["1110": 100_000, "3110": -100_000]

        let report = TrialBalanceService.report(entries: entries, openingBalances: openings, accounts: accounts)

        #expect(report.totalDebit == 361_000)
        #expect(report.totalCredit == 361_000)
        #expect(report.openingImbalance == 0)
        #expect(report.isBalanced)

        let cash = report.rows.first { $0.accountCode == "1110" }
        #expect(cash?.openingBalance == 100_000)
        #expect(cash?.debitTotal == 110_000)
        #expect(cash?.closingBalance == 210_000)

        let ownerLoan = report.rows.first { $0.accountCode == "3210" }
        #expect(ownerLoan?.closingBalance == -251_000)
    }

    @Test func report_unbalancedOpenings_flagged() {
        let accounts = [account("1110", .asset)]
        let report = TrialBalanceService.report(entries: [], openingBalances: ["1110": 5_000], accounts: accounts)
        #expect(report.openingImbalance == 5_000)
        #expect(!report.isBalanced)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement TrialBalanceService**

Create `SnapKei/Domain/Services/TrialBalanceService.swift`:

```swift
import Foundation

public struct TrialBalanceRow: Identifiable, Equatable, Sendable {
    public var id: String { accountCode }
    public let accountCode: String
    public let accountName: String
    public let openingBalance: Int   // debit-signed
    public let debitTotal: Int
    public let creditTotal: Int
    public let closingBalance: Int   // debit-signed
}

public struct TrialBalanceReport: Equatable, Sendable {
    public let rows: [TrialBalanceRow]
    public let totalDebit: Int
    public let totalCredit: Int
    public let openingImbalance: Int
    public var isBalanced: Bool { totalDebit == totalCredit && openingImbalance == 0 }
}

public enum TrialBalanceService {
    public static func report(
        entries: [JournalEntry],
        openingBalances: [String: Int],
        accounts: [Account]
    ) -> TrialBalanceReport {
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var debitTotals: [String: Int] = [:]
        var creditTotals: [String: Int] = [:]

        for entry in entries where !entry.isVoided {
            debitTotals[entry.debitAccountCode, default: 0] += entry.amountIncludingTax
            creditTotals[entry.creditAccountCode, default: 0] += entry.amountIncludingTax
        }

        let codes = Set(debitTotals.keys)
            .union(creditTotals.keys)
            .union(openingBalances.keys)

        let rows = codes.sorted().map { code -> TrialBalanceRow in
            let opening = openingBalances[code] ?? 0
            let debit = debitTotals[code] ?? 0
            let credit = creditTotals[code] ?? 0
            return TrialBalanceRow(
                accountCode: code,
                accountName: accountByCode[code]?.nameJa ?? code,
                openingBalance: opening,
                debitTotal: debit,
                creditTotal: credit,
                closingBalance: opening + debit - credit
            )
        }

        return TrialBalanceReport(
            rows: rows,
            totalDebit: rows.reduce(0) { $0 + $1.debitTotal },
            totalCredit: rows.reduce(0) { $0 + $1.creditTotal },
            openingImbalance: openingBalances.values.reduce(0, +)
        )
    }
}
```

- [ ] **Step 4: Run — TrialBalance tests PASS.**

- [ ] **Step 5: Create FiscalYearClosure and register it**

Create `SnapKei/Domain/Entities/FiscalYearClosure.swift`:

```swift
import Foundation
import SwiftData

/// Marks a fiscal year as closed (申告準備完了). Existence of a row = year is locked.
@Model
public final class FiscalYearClosure {
    @Attribute(.unique) public var fiscalYear: Int
    public var closedAt: Date
    public var netIncomeAtClosing: Int
    public var closedByDeviceId: String

    public init(fiscalYear: Int, closedAt: Date = Date(), netIncomeAtClosing: Int, closedByDeviceId: String) {
        self.fiscalYear = fiscalYear
        self.closedAt = closedAt
        self.netIncomeAtClosing = netIncomeAtClosing
        self.closedByDeviceId = closedByDeviceId
    }
}
```

Add `FiscalYearClosure.self` to the schema list in `ModelContainer+SnapKei.swift` (completing the Task 5 note).

- [ ] **Step 6: Write the failing lock-guard tests**

Append a new suite to `SnapKeiTests/ExpenseRepositoryTests.swift`:

```swift
@Suite("ExpenseRepository — fiscal year lock", .serialized)
struct ExpenseRepositoryLockTests {

    @MainActor
    private func makeRepo() throws -> (SwiftDataExpenseRepository, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        TestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        return (repo, container.mainContext)
    }

    private func makeEntry(year: Int) -> JournalEntry {
        JournalEntry(
            entryNumber: 0, fiscalYear: year, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店", transactionDescription: "テスト取引", sourceType: .manual
        )
    }

    @MainActor
    @Test func create_inClosedYear_throws() throws {
        let (repo, ctx) = try makeRepo()
        ctx.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "test"))
        try ctx.save()
        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try repo.create(makeEntry(year: 2026), reason: nil)
        }
        // Other years unaffected:
        try repo.create(makeEntry(year: 2027), reason: nil)
    }

    @MainActor
    @Test func editAndVoid_inClosedYear_throw() throws {
        let (repo, ctx) = try makeRepo()
        let entry = makeEntry(year: 2026)
        try repo.create(entry, reason: nil)
        ctx.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "test"))
        try ctx.save()

        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try repo.edit(entry, applying: { entry.memo = "x" }, reason: nil)
        }
        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try repo.void(entry, reason: nil)
        }
    }
}
```

(`TestContainerRetainer` already exists at the top of this file — reuse it.)

- [ ] **Step 7: Run — expect compile failure** (`RepositoryError` undefined).

- [ ] **Step 8: Add the guards**

In `SnapKei/Data/Persistence/ExpenseRepository.swift`:

(a) Below the `ExpenseSearchCriteria` struct, add:

```swift
public enum RepositoryError: Error, Equatable {
    case fiscalYearClosed(Int)
}
```

(b) In `SwiftDataExpenseRepository`, add a private helper:

```swift
    private func ensureFiscalYearOpen(_ fiscalYear: Int) throws {
        let descriptor = FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )
        if try context.fetchCount(descriptor) > 0 {
            throw RepositoryError.fiscalYearClosed(fiscalYear)
        }
    }
```

(c) First line of `create(_:reason:)`: `try ensureFiscalYearOpen(entry.fiscalYear)`
First line of `edit(_:applying:reason:)`: `try ensureFiscalYearOpen(entry.fiscalYear)`
First line of `void(_:reason:)`: `try ensureFiscalYearOpen(entry.fiscalYear)`

- [ ] **Step 9: Run full tests — expect PASS** (existing repository suites untouched — no closures exist in their fixtures).

- [ ] **Step 10: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/TrialBalanceService.swift SnapKei/Domain/Entities/FiscalYearClosure.swift SnapKei/Data/Persistence/ SnapKeiTests/TrialBalanceServiceTests.swift SnapKeiTests/ExpenseRepositoryTests.swift
git commit -m "feat: trial balance report, fiscal-year closure entity, repository edit locks"
```

---

### Task 6A: Sync OpeningBalance and FiscalYearClosure state

**Background:** P1 introduces persistent ledger state that changes the meaning of reports and edit locks. If cloud sync only moves `JournalEntry` and `FixedAsset`, two devices can show different opening balances or disagree about whether a fiscal year is locked.

**Files:**
- Modify: `SnapKei/Domain/Entities/OpeningBalance.swift` (`syncId`, `updatedAt`, optional tombstone if needed)
- Modify: `SnapKei/Domain/Entities/FiscalYearClosure.swift` (`syncId`, `updatedAt`, reopen/delete semantics)
- Modify: `SnapKei/Data/Sync/SnapKeiChangeCollector.swift`
- Modify: `SnapKei/Data/Sync/SnapKeiMerger.swift`
- Test: add collector/merger coverage for both entity types

- [ ] **Step 1: Write failing sync tests**

Add tests proving:
- changed `OpeningBalance` rows are collected after the sync cursor and merge by `syncId`
- `FiscalYearClosure` rows are collected/merged so edit locks converge across devices
- reopen/delete semantics remove or mark the synced closure consistently
- remote older payloads do not overwrite newer local state

- [ ] **Step 2: Implement payloads and collector support**

Follow the existing `JournalEntryPayload` / `FixedAssetPayload` shape. Include enough fields to reconstruct all user-visible ledger state and update timestamps used for conflict resolution.

- [ ] **Step 3: Implement merger support**

Handle `entityType == "OpeningBalance"` and `entityType == "FiscalYearClosure"` in `SnapKeiMerger`, matching existing newer-wins behavior. If reopen is represented as deletion/tombstone, test that it clears the local lock and auto-rolled openings safely.

- [ ] **Step 4: Run full tests**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Entities/OpeningBalance.swift SnapKei/Domain/Entities/FiscalYearClosure.swift SnapKei/Data/Sync/ SnapKeiTests/
git commit -m "feat: sync opening balances and fiscal-year closure state"
```

---

### Task 7: BalanceSheetService

**Files:**
- Create: `SnapKei/Domain/Services/BalanceSheetService.swift`
- Test: `SnapKeiTests/BalanceSheetServiceTests.swift`

- [ ] **Step 1: Write the failing test (shared worked example)**

Create `SnapKeiTests/BalanceSheetServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("BalanceSheetService")
struct BalanceSheetServiceTests {

    private func account(_ code: String, _ name: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: name, nameZh: name, accountType: type)
    }

    private var accounts: [Account] {
        [
            account("1110", "現金", .asset),
            account("1610", "工具器具備品", .asset),
            account("1710", "減価償却累計額", .asset),
            account("3110", "元入金", .equity),
            account("3210", "事業主借", .equity),
            account("3220", "事業主貸", .equity),
            account("4110", "売上高", .revenue),
            account("5110", "通信費", .expense),
            account("5230", "減価償却費", .expense),
            account("5290", "雑費", .expense),
        ]
    }

    private func entry(number: Int, debit: String, credit: String, amount: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: debit, creditAccountCode: credit,
            amountIncludingTax: amount, amountExcludingTax: amount, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "x", transactionDescription: "y", sourceType: .manual, isVoided: voided
        )
    }

    @Test func report_workedExample_balances() {
        let entries = [
            entry(number: 1, debit: "1110", credit: "4110", amount: 110_000),
            entry(number: 2, debit: "5110", credit: "3210", amount: 11_000),
            entry(number: 3, debit: "1610", credit: "3210", amount: 240_000),
            entry(number: 4, debit: "5290", credit: "1110", amount: 5_000, voided: true),
            entry(number: 5, debit: "5230", credit: "1710", amount: 24_000),
            entry(number: 6, debit: "3220", credit: "1710", amount: 6_000),
        ]
        let openings = ["1110": 100_000, "3110": -100_000]

        let report = BalanceSheetService.report(
            fiscalYear: 2026, entries: entries, openingBalances: openings, accounts: accounts
        )

        #expect(report.assetLines.first { $0.accountCode == "1110" }?.closing == 210_000)
        #expect(report.assetLines.first { $0.accountCode == "1610" }?.closing == 240_000)
        #expect(report.assetLines.first { $0.accountCode == "1710" }?.closing == -30_000)
        #expect(report.ownerDrawClosing == 6_000)
        #expect(report.ownerLoanClosing == 251_000)
        #expect(report.capitalOpening == 100_000)
        #expect(report.netIncome == 75_000)
        #expect(report.assetTotal == 426_000)
        #expect(report.liabilityEquityTotal == 426_000)
        #expect(report.isBalanced)
    }

    @Test func report_unbalancedOpening_notBalanced() {
        let report = BalanceSheetService.report(
            fiscalYear: 2026, entries: [], openingBalances: ["1110": 1_000], accounts: accounts
        )
        #expect(report.openingImbalance == 1_000)
        #expect(!report.isBalanced)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement**

Create `SnapKei/Domain/Services/BalanceSheetService.swift`:

```swift
import Foundation

public struct BalanceSheetLine: Identifiable, Equatable, Sendable {
    public var id: String { accountCode }
    public let accountCode: String
    public let accountName: String
    public let opening: Int   // debit-signed for assets / display-positive for liabilities
    public let closing: Int
}

/// Mirrors the official 青色申告決算書 B/S layout: 事業主貸 sits on the asset side,
/// 事業主借・元入金・青色申告特別控除前の所得金額 on the liability/equity side.
public struct BalanceSheetReport: Equatable, Sendable {
    public let fiscalYear: Int
    public let assetLines: [BalanceSheetLine]        // debit-signed (1710 shows negative)
    public let liabilityLines: [BalanceSheetLine]    // display-positive
    public let ownerDrawClosing: Int                 // 事業主貸 (asset side)
    public let ownerLoanClosing: Int                 // 事業主借 (display-positive)
    public let capitalOpening: Int                   // 元入金 (display-positive)
    public let netIncome: Int                        // 青色申告特別控除前の所得金額
    public let assetTotal: Int
    public let liabilityEquityTotal: Int
    public let openingImbalance: Int
    public var isBalanced: Bool { assetTotal == liabilityEquityTotal && openingImbalance == 0 }
}

public enum BalanceSheetService {
    public static func report(
        fiscalYear: Int,
        entries: [JournalEntry],
        openingBalances: [String: Int],
        accounts: [Account]
    ) -> BalanceSheetReport {
        let active = entries.filter { !$0.isVoided && $0.fiscalYear == fiscalYear }
        var movement: [String: Int] = [:]   // debit-signed
        for e in active {
            movement[e.debitAccountCode, default: 0] += e.amountIncludingTax
            movement[e.creditAccountCode, default: 0] -= e.amountIncludingTax
        }
        func closing(_ code: String) -> Int {
            (openingBalances[code] ?? 0) + (movement[code] ?? 0)
        }

        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        let pl = ProfitAndLossService.summary(entries: active, accounts: accounts)

        var assetLines: [BalanceSheetLine] = []
        var liabilityLines: [BalanceSheetLine] = []
        let relevantCodes = Set(openingBalances.keys).union(movement.keys)
        for code in relevantCodes.sorted() {
            guard let account = accountByCode[code] else { continue }
            let open = openingBalances[code] ?? 0
            let close = closing(code)
            if open == 0 && close == 0 { continue }
            switch account.accountType {
            case .asset:
                assetLines.append(BalanceSheetLine(accountCode: code, accountName: account.nameJa, opening: open, closing: close))
            case .liability:
                liabilityLines.append(BalanceSheetLine(accountCode: code, accountName: account.nameJa, opening: -open, closing: -close))
            case .equity, .revenue, .expense:
                break   // equity handled below; revenue/expense flow through netIncome
            }
        }

        let ownerDrawClosing = closing(AccountCode.ownerDraw)
        let ownerLoanClosing = -closing(AccountCode.ownerLoan)
        let capitalOpening = -closing(AccountCode.capital)
        let assetTotal = assetLines.reduce(0) { $0 + $1.closing } + ownerDrawClosing
        let liabilityEquityTotal = liabilityLines.reduce(0) { $0 + $1.closing }
            + ownerLoanClosing + capitalOpening + pl.netIncome

        return BalanceSheetReport(
            fiscalYear: fiscalYear,
            assetLines: assetLines,
            liabilityLines: liabilityLines,
            ownerDrawClosing: ownerDrawClosing,
            ownerLoanClosing: ownerLoanClosing,
            capitalOpening: capitalOpening,
            netIncome: pl.netIncome,
            assetTotal: assetTotal,
            liabilityEquityTotal: liabilityEquityTotal,
            openingImbalance: openingBalances.values.reduce(0, +)
        )
    }
}
```

- [ ] **Step 4: Run full tests — expect PASS.**

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/BalanceSheetService.swift SnapKeiTests/BalanceSheetServiceTests.swift
git commit -m "feat: balance sheet computation with opening balances and owner accounts"
```

---

### Task 8: YearEndClosingService (減価償却 posting → validation → close → rollover → reopen)

**Files:**
- Create: `SnapKei/Domain/Services/YearEndClosingService.swift`
- Test: `SnapKeiTests/YearEndClosingServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SnapKeiTests/YearEndClosingServiceTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import SnapKei

@Suite("YearEndClosingService", .serialized)
struct YearEndClosingServiceTests {

    @MainActor
    private func makeFixture() throws -> (YearEndClosingService, SwiftDataExpenseRepository, ModelContext, OpeningBalanceStore) {
        let container = try SnapKeiModelContainer.inMemory()
        TestClosingContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        let service = YearEndClosingService(context: container.mainContext, repository: repo)
        let openings = OpeningBalanceStore(context: container.mainContext)
        return (service, repo, container.mainContext, openings)
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    private func entry(debit: String, credit: String, amount: Int, day: String) -> JournalEntry {
        JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: date(day),
            debitAccountCode: debit, creditAccountCode: credit,
            amountIncludingTax: amount, amountExcludingTax: amount, consumptionTax: 0,
            taxCategory: .outOfScope, priceEntryMode: .taxIncluded, paymentMethod: .other,
            counterpartyName: "店", transactionDescription: "件", sourceType: .manual
        )
    }

    @MainActor
    private func seedWorkedExample(_ repo: SwiftDataExpenseRepository, _ ctx: ModelContext, _ openings: OpeningBalanceStore) throws -> FixedAsset {
        try openings.set(fiscalYear: 2026, accountCode: "1110", amount: 100_000)
        try openings.set(fiscalYear: 2026, accountCode: "3110", amount: -100_000)
        try repo.create(entry(debit: "1110", credit: "4110", amount: 110_000, day: "2026-01-10"), reason: nil)
        try repo.create(entry(debit: "5110", credit: "3210", amount: 11_000, day: "2026-02-05"), reason: nil)
        try repo.create(entry(debit: "1610", credit: "3210", amount: 240_000, day: "2026-03-01"), reason: nil)
        let asset = FixedAsset(
            assetName: "PC", assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"), serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000, usefulLifeYears: 4,
            treatment: .normalDepreciation, businessAllocationRate: 0.8
        )
        ctx.insert(asset)
        try ctx.save()
        return asset
    }

    @MainActor
    @Test func runDepreciation_postsSplitEntries_updatesAsset_isIdempotent() throws {
        let (service, repo, ctx, openings) = try makeFixture()
        let asset = try seedWorkedExample(repo, ctx, openings)

        let posted = try service.runDepreciation(fiscalYear: 2026)
        #expect(posted == 2)   // deductible entry + owner-portion entry
        #expect(asset.accumulatedDepreciation == 30_000)
        #expect(asset.bookValue == 210_000)

        let entries = try ctx.fetch(FetchDescriptor<JournalEntry>())
        let depreciationEntries = entries.filter { $0.sourceType == .depreciation }
        #expect(depreciationEntries.count == 2)
        #expect(depreciationEntries.contains { $0.debitAccountCode == "5230" && $0.amountIncludingTax == 24_000 })
        #expect(depreciationEntries.contains { $0.debitAccountCode == "3220" && $0.amountIncludingTax == 6_000 })
        #expect(depreciationEntries.allSatisfy { $0.creditAccountCode == "1710" && $0.relatedFixedAssetId == asset.id })

        // Idempotent: second run posts nothing.
        #expect(try service.runDepreciation(fiscalYear: 2026) == 0)
        #expect(asset.accumulatedDepreciation == 30_000)
    }

    @MainActor
    @Test func close_locksYear_andRollsOverOpenings() throws {
        let (service, repo, ctx, openings) = try makeFixture()
        _ = try seedWorkedExample(repo, ctx, openings)
        _ = try service.runDepreciation(fiscalYear: 2026)

        try service.close(fiscalYear: 2026, deviceId: "test-device")

        #expect(try service.isClosed(fiscalYear: 2026))
        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try repo.create(self.entry(debit: "5110", credit: "3210", amount: 1, day: "2026-12-30"), reason: nil)
        }

        let next = try openings.balances(fiscalYear: 2027)
        #expect(next["1110"] == 210_000)
        #expect(next["1610"] == 240_000)
        #expect(next["1710"] == -30_000)
        #expect(next[AccountCode.capital] == -420_000)
        #expect(next[AccountCode.ownerLoan] == nil)   // 事業主借/貸 reset
        #expect(next[AccountCode.ownerDraw] == nil)
        #expect(next.values.reduce(0, +) == 0)
    }

    @MainActor
    @Test func close_alreadyClosed_throws() throws {
        let (service, repo, ctx, openings) = try makeFixture()
        _ = try seedWorkedExample(repo, ctx, openings)
        try service.close(fiscalYear: 2026, deviceId: "test-device")
        #expect(throws: YearEndClosingService.ClosingError.alreadyClosed) {
            try service.close(fiscalYear: 2026, deviceId: "test-device")
        }
    }

    @MainActor
    @Test func reopen_unlocks_andRemovesAutoRolledOpenings() throws {
        let (service, repo, ctx, openings) = try makeFixture()
        _ = try seedWorkedExample(repo, ctx, openings)
        try service.close(fiscalYear: 2026, deviceId: "test-device")

        try service.reopen(fiscalYear: 2026, reason: "入力漏れの追加", deviceId: "test-device")

        #expect(!(try service.isClosed(fiscalYear: 2026)))
        #expect(try openings.balances(fiscalYear: 2027).isEmpty)
        try repo.create(entry(debit: "5110", credit: "3210", amount: 1_000, day: "2026-12-30"), reason: nil)
    }
}

@MainActor
private enum TestClosingContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement**

Create `SnapKei/Domain/Services/YearEndClosingService.swift`:

```swift
import Foundation
import SwiftData

@MainActor
public final class YearEndClosingService {
    public enum ClosingError: Error, Equatable {
        case sequenceGaps([Int])
        case openingImbalance(Int)
        case alreadyClosed
        case notClosed
        case missingReopenReason
    }

    public struct DepreciationPreviewItem: Identifiable, Sendable {
        public var id: UUID { assetId }
        public let assetId: UUID
        public let assetName: String
        public let amount: DepreciationAmount
        public let alreadyPosted: Bool
    }

    private let context: ModelContext
    private let repository: SwiftDataExpenseRepository

    public init(context: ModelContext, repository: SwiftDataExpenseRepository) {
        self.context = context
        self.repository = repository
    }

    // MARK: - Queries

    public func isClosed(fiscalYear: Int) throws -> Bool {
        try context.fetchCount(FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )) > 0
    }

    public func allEntries(fiscalYear: Int) throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear },
            sortBy: [SortDescriptor(\.entryNumber)]
        ))
    }

    public func depreciationPreview(fiscalYear: Int) throws -> [DepreciationPreviewItem] {
        try eligibleAssets(fiscalYear: fiscalYear).map { asset in
            DepreciationPreviewItem(
                assetId: asset.id,
                assetName: asset.assetName,
                amount: DepreciationService.annualAmount(for: asset, fiscalYear: fiscalYear),
                alreadyPosted: try hasPostedDepreciation(asset: asset, fiscalYear: fiscalYear)
            )
        }
    }

    // MARK: - 減価償却の自動計上

    @discardableResult
    public func runDepreciation(fiscalYear: Int) throws -> Int {
        var postedCount = 0
        for asset in try eligibleAssets(fiscalYear: fiscalYear) {
            guard !(try hasPostedDepreciation(asset: asset, fiscalYear: fiscalYear)) else { continue }
            let amount = DepreciationService.annualAmount(for: asset, fiscalYear: fiscalYear)
            guard amount.full > 0 else { continue }

            try repository.create(makeDepreciationEntry(
                fiscalYear: fiscalYear,
                debitCode: AccountCode.depreciationExpense,
                amount: amount.deductible,
                asset: asset,
                description: "減価償却費（\(fiscalYear)年分）"
            ), reason: "年末減価償却")
            postedCount += 1

            if amount.ownerPortion > 0 {
                try repository.create(makeDepreciationEntry(
                    fiscalYear: fiscalYear,
                    debitCode: AccountCode.ownerDraw,
                    amount: amount.ownerPortion,
                    asset: asset,
                    description: "減価償却費 家事分（\(fiscalYear)年分）"
                ), reason: "年末減価償却（家事按分）")
                postedCount += 1
            }

            asset.accumulatedDepreciation += amount.full
            asset.bookValue = asset.acquisitionAmount - asset.accumulatedDepreciation
            asset.updatedAt = Date()
        }
        try context.save()
        return postedCount
    }

    // MARK: - 締め / 再オープン

    public func close(fiscalYear: Int, deviceId: String) throws {
        guard !(try isClosed(fiscalYear: fiscalYear)) else { throw ClosingError.alreadyClosed }
        try runDepreciation(fiscalYear: fiscalYear)
        let entries = try allEntries(fiscalYear: fiscalYear)
        let gaps = LedgerService.missingEntryNumbers(entries: entries)
        guard gaps.isEmpty else { throw ClosingError.sequenceGaps(gaps) }

        let openings = try OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)
        let imbalance = openings.values.reduce(0, +)
        guard imbalance == 0 else { throw ClosingError.openingImbalance(imbalance) }

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let report = BalanceSheetService.report(
            fiscalYear: fiscalYear, entries: entries, openingBalances: openings, accounts: accounts
        )

        // Roll asset/liability closings into next year's openings (debit-signed).
        let store = OpeningBalanceStore(context: context)
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        var movement: [String: Int] = [:]
        for e in entries where !e.isVoided {
            movement[e.debitAccountCode, default: 0] += e.amountIncludingTax
            movement[e.creditAccountCode, default: 0] -= e.amountIncludingTax
        }
        let relevantCodes = Set(openings.keys).union(movement.keys)
        for code in relevantCodes {
            guard let type = accountByCode[code]?.accountType, type == .asset || type == .liability else { continue }
            let closing = (openings[code] ?? 0) + (movement[code] ?? 0)
            if closing != 0 {
                try store.set(fiscalYear: fiscalYear + 1, accountCode: code, amount: closing, isAutoRolled: true)
            }
        }
        // 翌期首元入金 = 元入金 + 青色申告特別控除前所得 + 事業主借 − 事業主貸
        let nextCapital = report.capitalOpening + report.netIncome + report.ownerLoanClosing - report.ownerDrawClosing
        try store.set(fiscalYear: fiscalYear + 1, accountCode: AccountCode.capital, amount: -nextCapital, isAutoRolled: true)

        context.insert(FiscalYearClosure(
            fiscalYear: fiscalYear,
            netIncomeAtClosing: report.netIncome,
            closedByDeviceId: deviceId
        ))
        context.insert(SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .fiscalYearTransition,
            reason: "\(fiscalYear)年度を締めました（所得 ¥\(report.netIncome)）"
        ))
        try context.save()
    }

    public func reopen(fiscalYear: Int, reason: String, deviceId: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClosingError.missingReopenReason }
        let closures = try context.fetch(FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        ))
        guard let closure = closures.first else { throw ClosingError.notClosed }
        context.delete(closure)
        try OpeningBalanceStore(context: context).deleteAutoRolled(fiscalYear: fiscalYear + 1)
        context.insert(SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .unlockPeriod,
            reason: reason
        ))
        try context.save()
    }

    // MARK: - Private

    private func eligibleAssets(fiscalYear: Int) throws -> [FixedAsset] {
        try context.fetch(FetchDescriptor<FixedAsset>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.acquisitionDate)]
        )).filter { asset in
            let calendar = Calendar(identifier: .gregorian)
            if let disposal = asset.disposalDate, calendar.component(.year, from: disposal) < fiscalYear { return false }
            return true
        }
    }

    private func hasPostedDepreciation(asset: FixedAsset, fiscalYear: Int) throws -> Bool {
        let assetId = asset.id
        let raw = RecordSource.depreciation.rawValue
        return try context.fetchCount(FetchDescriptor<JournalEntry>(
            predicate: #Predicate {
                $0.relatedFixedAssetId == assetId && $0.fiscalYear == fiscalYear
                    && $0.sourceTypeRaw == raw && !$0.isVoided
            }
        )) > 0
    }

    private func makeDepreciationEntry(
        fiscalYear: Int, debitCode: String, amount: Int, asset: FixedAsset, description: String
    ) -> JournalEntry {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let yearEnd = calendar.date(from: DateComponents(year: fiscalYear, month: 12, day: 31, hour: 12))!
        return JournalEntry(
            entryNumber: 0,
            fiscalYear: fiscalYear,
            transactionDate: yearEnd,
            debitAccountCode: debitCode,
            creditAccountCode: AccountCode.accumulatedDepreciation,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: asset.assetName,
            transactionDescription: description,
            relatedFixedAssetId: asset.id,
            sourceType: .depreciation
        )
    }
}
```

**Compiler note:** `depreciationPreview` uses `try` inside a `map` closure — if Swift rejects the throwing closure shape, rewrite as a `for` loop appending to an array (behavior identical).

- [ ] **Step 4: Run full tests — expect PASS.**

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/YearEndClosingService.swift SnapKeiTests/YearEndClosingServiceTests.swift
git commit -m "feat: year-end closing — depreciation posting, lock, rollover, reopen"
```

---

### Task 9: CSV exporters for 帳簿

**Files:**
- Modify: `SnapKei/Domain/Services/CSVExportService.swift:34` (`private static func escape` → `static func escape`)
- Create: `SnapKei/Domain/Services/LedgerCSVExportService.swift`
- Test: `SnapKeiTests/LedgerCSVExportServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SnapKeiTests/LedgerCSVExportServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("LedgerCSVExportService")
struct LedgerCSVExportServiceTests {

    private func entry(number: Int, voided: Bool = false) -> JournalEntry {
        JournalEntry(
            entryNumber: number, fiscalYear: 2026, transactionDate: Date(timeIntervalSince1970: 0),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 11_000, amountExcludingTax: 10_000, consumptionTax: 1_000,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト, 商店", transactionDescription: "通信費",
            sourceType: .manual, isVoided: voided
        )
    }

    @Test func journalBook_includesVoidedWithStatus_andEscapesCommas() {
        let data = LedgerCSVExportService.journalBook(
            entries: [entry(number: 1), entry(number: 2, voided: true)],
            accountNameLookup: { $0 == "5110" ? "通信費" : "事業主借" }
        )
        let text = String(data: data, encoding: .utf8)!
        #expect(text.hasPrefix("\u{FEFF}仕訳番号,"))
        #expect(text.contains("\"テスト, 商店\""))
        #expect(text.contains(",有効"))
        #expect(text.contains(",取消"))
    }

    @Test func trialBalance_rowsAndTotals() {
        let report = TrialBalanceReport(
            rows: [TrialBalanceRow(accountCode: "1110", accountName: "現金", openingBalance: 100_000, debitTotal: 110_000, creditTotal: 0, closingBalance: 210_000)],
            totalDebit: 110_000, totalCredit: 110_000, openingImbalance: 0
        )
        let text = String(data: LedgerCSVExportService.trialBalance(report: report), encoding: .utf8)!
        #expect(text.contains("1110,現金,100000,110000,0,210000"))
        #expect(text.contains("合計,,,110000,110000,"))
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement**

In `CSVExportService.swift` change `private static func escape` to `static func escape`.

Create `SnapKei/Domain/Services/LedgerCSVExportService.swift`:

```swift
import Foundation

public enum LedgerCSVExportService {
    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// 仕訳帳 — includes voided entries (marked 取消) to preserve audit continuity.
    public static func journalBook(entries: [JournalEntry], accountNameLookup: (String) -> String) -> Data {
        let formatter = dateFormatter
        var output = "\u{FEFF}仕訳番号,日付,借方科目,貸方科目,税込金額,税抜金額,消費税,取引先,摘要,状態\n"
        for entry in entries.sorted(by: { $0.entryNumber < $1.entryNumber }) {
            let row = [
                String(entry.entryNumber),
                formatter.string(from: entry.transactionDate),
                CSVExportService.escape(accountNameLookup(entry.debitAccountCode)),
                CSVExportService.escape(accountNameLookup(entry.creditAccountCode)),
                String(entry.amountIncludingTax),
                String(entry.amountExcludingTax),
                String(entry.consumptionTax),
                CSVExportService.escape(entry.counterpartyName),
                CSVExportService.escape(entry.transactionDescription),
                entry.isVoided ? "取消" : "有効",
            ].joined(separator: ",")
            output.append(row + "\n")
        }
        return Data(output.utf8)
    }

    /// 総勘定元帳 (one account).
    public static func generalLedger(accountName: String, lines: [LedgerLine], accountNameLookup: (String) -> String) -> Data {
        let formatter = dateFormatter
        var output = "\u{FEFF}科目: \(accountName)\n日付,仕訳番号,相手科目,摘要,借方,貸方,残高\n"
        for line in lines {
            let row = [
                formatter.string(from: line.transactionDate),
                String(line.entryNumber),
                CSVExportService.escape(accountNameLookup(line.counterAccountCode)),
                CSVExportService.escape(line.summary),
                String(line.debit),
                String(line.credit),
                String(line.runningBalance),
            ].joined(separator: ",")
            output.append(row + "\n")
        }
        return Data(output.utf8)
    }

    /// 残高試算表.
    public static func trialBalance(report: TrialBalanceReport) -> Data {
        var output = "\u{FEFF}科目コード,科目名,期首残高,借方合計,貸方合計,期末残高\n"
        for row in report.rows {
            output.append([
                row.accountCode,
                CSVExportService.escape(row.accountName),
                String(row.openingBalance),
                String(row.debitTotal),
                String(row.creditTotal),
                String(row.closingBalance),
            ].joined(separator: ",") + "\n")
        }
        output.append("合計,,,\(report.totalDebit),\(report.totalCredit),\n")
        return Data(output.utf8)
    }
}
```

- [ ] **Step 4: Run full tests — expect PASS.**

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/LedgerCSVExportService.swift SnapKei/Domain/Services/CSVExportService.swift SnapKeiTests/LedgerCSVExportServiceTests.swift
git commit -m "feat: CSV export for journal book, general ledger, trial balance"
```

---

### Task 10: Balance sheet PDF render

**Files:**
- Modify: `SnapKei/Domain/Services/PDFReportService.swift` (append method)

- [ ] **Step 1: Implement (render-smoke verified via UI; no unit test — UIKit drawing matches repo convention)**

Append inside `PDFReportService` (before the private `drawSection` helper):

```swift
    public static func renderBalanceSheet(report: BalanceSheetReport) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12)]

            "貸借対照表 (\(report.fiscalYear) 年 12 月 31 日現在)".draw(at: CGPoint(x: 40, y: 40), withAttributes: title)

            var y: CGFloat = 100
            "【資産の部】".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
            y += 24
            for line in report.assetLines {
                "\(line.accountCode) \(line.accountName)".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                "¥\(line.closing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
                y += 18
            }
            "事業主貸".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(report.ownerDrawClosing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 24
            "資産合計".draw(at: CGPoint(x: 60, y: y), withAttributes: bold)
            "¥\(report.assetTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
            y += 36

            "【負債・資本の部】".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
            y += 24
            for line in report.liabilityLines {
                "\(line.accountCode) \(line.accountName)".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                "¥\(line.closing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
                y += 18
            }
            for (label, value) in [("事業主借", report.ownerLoanClosing), ("元入金", report.capitalOpening), ("青色申告特別控除前の所得金額", report.netIncome)] {
                label.draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                "¥\(value)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
                y += 18
            }
            y += 6
            "負債・資本合計".draw(at: CGPoint(x: 60, y: y), withAttributes: bold)
            "¥\(report.liabilityEquityTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
        }
    }
```

- [ ] **Step 2: Build + run full tests — expect green.**

- [ ] **Step 3: Commit (ask user first)**

```bash
git add SnapKei/Domain/Services/PDFReportService.swift
git commit -m "feat: balance sheet PDF render"
```

---

### Task 11: 帳簿 screens — JournalBookView, GeneralLedgerView, TrialBalanceView

All ledger views share two small helpers — define them once in `JournalBookView.swift` and reuse.

**Files:**
- Create: `SnapKei/Presentation/Ledger/JournalBookView.swift`
- Create: `SnapKei/Presentation/Ledger/GeneralLedgerView.swift`
- Create: `SnapKei/Presentation/Ledger/TrialBalanceView.swift`

- [ ] **Step 1: JournalBookView (+ shared helpers)**

Create `SnapKei/Presentation/Ledger/JournalBookView.swift`:

```swift
import SwiftData
import SwiftUI

/// Shared helpers for the ledger screens.
@MainActor
enum LedgerScreenSupport {
    static func accountName(_ code: String, accounts: [Account]) -> String {
        accounts.first(where: { $0.code == code })?.nameJa ?? code
    }

    static func fetchEntries(fiscalYear: Int, context: ModelContext) -> [JournalEntry] {
        (try? context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear },
            sortBy: [SortDescriptor(\.entryNumber)]
        ))) ?? []
    }
}

public struct JournalBookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var entries: [JournalEntry] = []

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    public var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("仕訳がありません", systemImage: "book")
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("No.\(entry.entryNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.transactionDate, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if entry.isVoided {
                            Text("取消").font(.caption2).foregroundStyle(.red)
                        }
                        Text("¥\(entry.amountIncludingTax)")
                            .font(.subheadline.monospacedDigit())
                            .strikethrough(entry.isVoided)
                    }
                    Text("\(LedgerScreenSupport.accountName(entry.debitAccountCode, accounts: accounts)) / \(LedgerScreenSupport.accountName(entry.creditAccountCode, accounts: accounts))")
                        .font(.subheadline)
                    Text("\(entry.counterpartyName) \(entry.transactionDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("仕訳帳 \(String(fiscalYear))年")
        .toolbar {
            Button {
                let data = LedgerCSVExportService.journalBook(entries: entries) {
                    LedgerScreenSupport.accountName($0, accounts: accounts)
                }
                Task { await SharePresenter.share(data: data, filename: "仕訳帳_\(fiscalYear).csv") }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("CSV を共有")
        }
        .task { entries = LedgerScreenSupport.fetchEntries(fiscalYear: fiscalYear, context: context) }
    }
}
```

- [ ] **Step 2: GeneralLedgerView**

Create `SnapKei/Presentation/Ledger/GeneralLedgerView.swift`:

```swift
import SwiftData
import SwiftUI

public struct GeneralLedgerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var entries: [JournalEntry] = []
    @State private var openings: [String: Int] = [:]
    @State private var selectedCode = AccountCode.cash

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    private var selectedAccount: Account? {
        accounts.first { $0.code == selectedCode }
    }

    private var lines: [LedgerLine] {
        LedgerService.ledgerLines(
            accountCode: selectedCode,
            openingBalance: openings[selectedCode] ?? 0,
            entries: entries
        )
    }

    private func displayBalance(_ debitSigned: Int) -> Int {
        guard let type = selectedAccount?.accountType else { return debitSigned }
        return (type == .asset || type == .expense) ? debitSigned : -debitSigned
    }

    public var body: some View {
        List {
            Picker("勘定科目", selection: $selectedCode) {
                ForEach(accounts.filter(\.isActive)) { account in
                    Text("\(account.code) \(account.nameJa)").tag(account.code)
                }
            }

            if let opening = openings[selectedCode], opening != 0 {
                HStack {
                    Text("期首残高").font(.caption)
                    Spacer()
                    Text("¥\(displayBalance(opening))").font(.caption.monospacedDigit())
                }
            }

            if lines.isEmpty {
                ContentUnavailableView("記帳がありません", systemImage: "book.pages")
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("No.\(line.entryNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(line.transactionDate, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                        Text(LedgerScreenSupport.accountName(line.counterAccountCode, accounts: accounts)).font(.caption)
                        Spacer()
                    }
                    HStack {
                        Text(line.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if line.debit > 0 { Text("借 ¥\(line.debit)").font(.caption.monospacedDigit()) }
                        if line.credit > 0 { Text("貸 ¥\(line.credit)").font(.caption.monospacedDigit()) }
                        Text("残 ¥\(displayBalance(line.runningBalance))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("総勘定元帳 \(String(fiscalYear))年")
        .toolbar {
            Button {
                let name = selectedAccount?.nameJa ?? selectedCode
                let data = LedgerCSVExportService.generalLedger(accountName: name, lines: lines) {
                    LedgerScreenSupport.accountName($0, accounts: accounts)
                }
                Task { await SharePresenter.share(data: data, filename: "総勘定元帳_\(name)_\(fiscalYear).csv") }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("CSV を共有")
        }
        .task {
            entries = LedgerScreenSupport.fetchEntries(fiscalYear: fiscalYear, context: context)
            openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        }
    }
}
```

- [ ] **Step 3: TrialBalanceView**

Create `SnapKei/Presentation/Ledger/TrialBalanceView.swift`:

```swift
import SwiftData
import SwiftUI

public struct TrialBalanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var report: TrialBalanceReport?

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    public var body: some View {
        List {
            if let report {
                Section {
                    Label(
                        report.isBalanced ? "貸借一致" : "貸借不一致 — 期首残高または仕訳を確認してください",
                        systemImage: report.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.isBalanced ? .green : .red)
                }
                Section("科目別残高") {
                    ForEach(report.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.accountCode) \(row.accountName)").font(.subheadline)
                            HStack {
                                Text("借 ¥\(row.debitTotal)  貸 ¥\(row.creditTotal)")
                                Spacer()
                                Text("残 ¥\(row.closingBalance)")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("借方合計 ¥\(report.totalDebit)").font(.caption.monospacedDigit())
                        Spacer()
                        Text("貸方合計 ¥\(report.totalCredit)").font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle("残高試算表 \(String(fiscalYear))年")
        .toolbar {
            Button {
                guard let report else { return }
                let data = LedgerCSVExportService.trialBalance(report: report)
                Task { await SharePresenter.share(data: data, filename: "残高試算表_\(fiscalYear).csv") }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("CSV を共有")
        }
        .task {
            let entries = LedgerScreenSupport.fetchEntries(fiscalYear: fiscalYear, context: context)
            let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
            report = TrialBalanceService.report(entries: entries, openingBalances: openings, accounts: accounts)
        }
    }
}
```

- [ ] **Step 4: Build + full tests — expect green.**

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Presentation/Ledger/
git commit -m "feat: journal book, general ledger, trial balance screens with CSV export"
```

---

### Task 12: BalanceSheetView + OpeningBalanceView

**Files:**
- Create: `SnapKei/Presentation/Ledger/BalanceSheetView.swift`
- Create: `SnapKei/Presentation/Ledger/OpeningBalanceView.swift`

- [ ] **Step 1: BalanceSheetView**

Create `SnapKei/Presentation/Ledger/BalanceSheetView.swift`:

```swift
import SwiftData
import SwiftUI

public struct BalanceSheetView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var report: BalanceSheetReport?

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    public var body: some View {
        List {
            if let report {
                if !report.isBalanced {
                    Section {
                        Label(
                            report.openingImbalance != 0
                                ? "期首残高が不均衡です（差額 ¥\(report.openingImbalance)）。期首残高設定で「元入金を自動調整」を実行してください。"
                                : "貸借が一致していません。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                }
                Section("資産の部") {
                    ForEach(report.assetLines) { line in
                        row(line.accountName, line.closing)
                    }
                    row("事業主貸", report.ownerDrawClosing)
                    row("資産合計", report.assetTotal, bold: true)
                }
                Section("負債・資本の部") {
                    ForEach(report.liabilityLines) { line in
                        row(line.accountName, line.closing)
                    }
                    row("事業主借", report.ownerLoanClosing)
                    row("元入金", report.capitalOpening)
                    row("青色申告特別控除前の所得金額", report.netIncome)
                    row("負債・資本合計", report.liabilityEquityTotal, bold: true)
                }
            }
            Section {
                NavigationLink("期首残高を設定") { OpeningBalanceView(fiscalYear: fiscalYear) }
            }
        }
        .navigationTitle("貸借対照表 \(String(fiscalYear))年")
        .toolbar {
            Button {
                guard let report else { return }
                let data = PDFReportService.renderBalanceSheet(report: report)
                Task { await SharePresenter.share(data: data, filename: "貸借対照表_\(fiscalYear).pdf") }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("PDF を共有")
        }
        .task { refresh() }
    }

    private func refresh() {
        let entries = LedgerScreenSupport.fetchEntries(fiscalYear: fiscalYear, context: context)
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        report = BalanceSheetService.report(fiscalYear: fiscalYear, entries: entries, openingBalances: openings, accounts: accounts)
    }

    private func row(_ label: String, _ amount: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .subheadline.weight(.bold) : .subheadline)
            Spacer()
            Text("¥\(amount)")
                .font((bold ? Font.subheadline.weight(.bold) : .subheadline).monospacedDigit())
        }
    }
}
```

- [ ] **Step 2: OpeningBalanceView**

Create `SnapKei/Presentation/Ledger/OpeningBalanceView.swift`:

```swift
import SwiftData
import SwiftUI

public struct OpeningBalanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var amounts: [String: String] = [:]   // accountCode -> display text
    @State private var statusMessage: String?

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    private var balanceSheetAccounts: [Account] {
        accounts.filter { ($0.accountType == .asset || $0.accountType == .liability) && $0.isActive }
    }

    public var body: some View {
        Form {
            Section {
                Text("\(String(fiscalYear))年1月1日時点の残高を入力します。負債は正の数で入力してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("資産") {
                ForEach(balanceSheetAccounts.filter { $0.accountType == .asset }) { account in
                    amountRow(account)
                }
            }
            Section("負債") {
                ForEach(balanceSheetAccounts.filter { $0.accountType == .liability }) { account in
                    amountRow(account)
                }
            }
            Section("元入金") {
                Button("元入金を自動調整（資産 − 負債）") {
                    saveAll()
                    do {
                        try OpeningBalanceStore(context: context).adjustCapitalToBalance(fiscalYear: fiscalYear)
                        statusMessage = "元入金を調整しました"
                    } catch {
                        statusMessage = "調整に失敗しました"
                    }
                }
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("期首残高 \(String(fiscalYear))年")
        .task { load() }
        .onDisappear { saveAll() }
    }

    private func amountRow(_ account: Account) -> some View {
        HStack {
            Text("\(account.code) \(account.nameJa)")
            Spacer()
            TextField("0", text: Binding(
                get: { amounts[account.code] ?? "" },
                set: { amounts[account.code] = $0.filter(\.isNumber) }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 120)
        }
    }

    private func load() {
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        for account in balanceSheetAccounts {
            let raw = openings[account.code] ?? 0
            // liabilities stored negative (debit-signed) — display positive
            let display = account.accountType == .liability ? -raw : raw
            amounts[account.code] = display == 0 ? "" : String(display)
        }
    }

    private func saveAll() {
        let store = OpeningBalanceStore(context: context)
        for account in balanceSheetAccounts {
            let display = Int(amounts[account.code] ?? "") ?? 0
            let signed = account.accountType == .liability ? -display : display
            try? store.set(fiscalYear: fiscalYear, accountCode: account.code, amount: signed)
        }
    }
}
```

- [ ] **Step 3: Build + full tests — expect green.**

- [ ] **Step 4: Commit (ask user first)**

```bash
git add SnapKei/Presentation/Ledger/BalanceSheetView.swift SnapKei/Presentation/Ledger/OpeningBalanceView.swift
git commit -m "feat: balance sheet and opening balance screens"
```

---

### Task 13: YearEndClosingView + Home 帳簿・レポート hub

**Files:**
- Create: `SnapKei/Presentation/Ledger/YearEndClosingView.swift`
- Modify: `SnapKei/Presentation/Home/HomeView.swift` (レポート section, lines 73–77)

- [ ] **Step 1: YearEndClosingView**

Create `SnapKei/Presentation/Ledger/YearEndClosingView.swift`:

```swift
import SwiftData
import SwiftUI
import UIKit

public struct YearEndClosingView: View {
    @Environment(\.modelContext) private var context
    @State private var isClosed = false
    @State private var gaps: [Int] = []
    @State private var openingImbalance = 0
    @State private var preview: [YearEndClosingService.DepreciationPreviewItem] = []
    @State private var statusMessage: String?
    @State private var showCloseConfirm = false
    @State private var reopenReason = ""

    let fiscalYear: Int

    public init(fiscalYear: Int) {
        self.fiscalYear = fiscalYear
    }

    private var service: YearEndClosingService {
        YearEndClosingService(
            context: context,
            repository: SwiftDataExpenseRepository(
                context: context,
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            )
        )
    }

    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    public var body: some View {
        List {
            if isClosed {
                closedSection
            } else {
                checklistSection
                depreciationSection
                closeSection
            }
            if let statusMessage {
                Section { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("決算 \(String(fiscalYear))年")
        .task { refresh() }
        .alert("\(String(fiscalYear))年度を締めますか？", isPresented: $showCloseConfirm) {
            Button("締める", role: .destructive) { performClose() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("締めた年度の仕訳は追加・編集・取消ができなくなります。翌年の期首残高が自動作成されます。")
        }
    }

    private var checklistSection: some View {
        Section("チェック") {
            Label(
                gaps.isEmpty ? "仕訳番号は連番です" : "欠番があります: \(gaps.map(String.init).joined(separator: ", "))",
                systemImage: gaps.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(gaps.isEmpty ? .green : .red)
            Label(
                openingImbalance == 0 ? "期首残高は均衡しています" : "期首残高が不均衡です（差額 ¥\(openingImbalance)）",
                systemImage: openingImbalance == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(openingImbalance == 0 ? .green : .red)
        }
    }

    private var depreciationSection: some View {
        Section("減価償却") {
            if preview.isEmpty {
                Text("対象資産がありません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(preview) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.assetName).font(.subheadline)
                        Text("償却費 ¥\(item.amount.full)（経費算入 ¥\(item.amount.deductible)）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.alreadyPosted {
                        Text("計上済").font(.caption).foregroundStyle(.green)
                    }
                }
            }
            if preview.contains(where: { !$0.alreadyPosted && $0.amount.full > 0 }) {
                Button("減価償却を実行") {
                    do {
                        let count = try service.runDepreciation(fiscalYear: fiscalYear)
                        statusMessage = "\(count) 件の仕訳を計上しました"
                    } catch {
                        statusMessage = "計上に失敗しました"
                    }
                    refresh()
                }
            }
        }
    }

    private var closeSection: some View {
        Section {
            Button("年度を締める") { showCloseConfirm = true }
                .disabled(!gaps.isEmpty || openingImbalance != 0)
        } footer: {
            Text("締めると仕訳がロックされ、翌年期首残高（元入金の繰越を含む）が作成されます。")
        }
    }

    private var closedSection: some View {
        Section("締め済み") {
            Label("\(String(fiscalYear))年度は締め済みです", systemImage: "lock.fill")
                .foregroundStyle(.green)
            TextField("再オープンの理由（必須）", text: $reopenReason)
            Button("再オープン", role: .destructive) {
                do {
                    try service.reopen(fiscalYear: fiscalYear, reason: reopenReason, deviceId: deviceId)
                    statusMessage = "再オープンしました（翌年の自動期首残高は削除されます）"
                } catch {
                    statusMessage = "再オープンに失敗しました"
                }
                refresh()
            }
            .disabled(reopenReason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func refresh() {
        isClosed = (try? service.isClosed(fiscalYear: fiscalYear)) ?? false
        let entries = (try? service.allEntries(fiscalYear: fiscalYear)) ?? []
        gaps = LedgerService.missingEntryNumbers(entries: entries)
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        openingImbalance = openings.values.reduce(0, +)
        preview = (try? service.depreciationPreview(fiscalYear: fiscalYear)) ?? []
    }

    private func performClose() {
        do {
            try service.close(fiscalYear: fiscalYear, deviceId: deviceId)
            statusMessage = "\(String(fiscalYear))年度を締めました"
        } catch YearEndClosingService.ClosingError.sequenceGaps(let gapList) {
            statusMessage = "欠番のため締められません: \(gapList.map(String.init).joined(separator: ", "))"
        } catch YearEndClosingService.ClosingError.openingImbalance(let diff) {
            statusMessage = "期首残高が不均衡のため締められません（差額 ¥\(diff)）"
        } catch {
            statusMessage = "締め処理に失敗しました"
        }
        refresh()
    }
}
```

- [ ] **Step 2: Home 帳簿・レポート hub**

In `SnapKei/Presentation/Home/HomeView.swift`:

(a) Add state after the other `@State` properties (line 13):

```swift
    @State private var selectedYear = Calendar(identifier: .gregorian).component(.year, from: Date())
```

(b) Replace the レポート section (lines 73–77):

```swift
                Section("帳簿・レポート") {
                    Picker("年度", selection: $selectedYear) {
                        ForEach(availableYears(), id: \.self) { year in
                            Text("\(String(year))年").tag(year)
                        }
                    }
                    NavigationLink("仕訳帳") { JournalBookView(fiscalYear: selectedYear) }
                    NavigationLink("総勘定元帳") { GeneralLedgerView(fiscalYear: selectedYear) }
                    NavigationLink("残高試算表") { TrialBalanceView(fiscalYear: selectedYear) }
                    NavigationLink("貸借対照表") { BalanceSheetView(fiscalYear: selectedYear) }
                    NavigationLink("決算（年度締め）") { YearEndClosingView(fiscalYear: selectedYear) }
                    Button("損益計算書 PDF を生成") {
                        Task { await generatePnL() }
                    }
                }
```

(c) Add the helper next to `deviceID()` (line 127):

```swift
    private func availableYears() -> [Int] {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let entryYears = (try? context.fetch(FetchDescriptor<JournalEntry>()))?.map(\.fiscalYear) ?? []
        return Set(entryYears + [currentYear]).sorted(by: >)
    }
```

(d) Update `generatePnL()` (line 118) to use `selectedYear` instead of recomputing the current year:

```swift
    private func generatePnL() async {
        do {
            let data = try PDFReportService.renderProfitAndLoss(fiscalYear: selectedYear, context: context)
            await SharePresenter.share(data: data, filename: "損益計算書_\(selectedYear).pdf")
        } catch {
            print("[HomeView] PDF generation failed: \(error)")
        }
    }
```

- [ ] **Step 3: Build + full tests — expect green.**

- [ ] **Step 4: Manual smoke (simulator)**

- Home → 帳簿・レポート: create 2–3 entries via Capture, open 仕訳帳/総勘定元帳/残高試算表 — numbers match
- 貸借対照表 → 期首残高を設定 → enter 現金, run 元入金自動調整 → B/S balances
- 決算 → 減価償却を実行 (after adding an asset) → 年度を締める → Capture tab rejects new entry for that year with an error → 再オープン works

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/Presentation/Ledger/YearEndClosingView.swift SnapKei/Presentation/Home/HomeView.swift
git commit -m "feat: year-end closing screen and ledger hub on home tab"
```

---

### Task 14: Final verification sweep

- [ ] **Step 1: Full clean test run**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO clean test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`, ≥100 tests (P0 baseline + ~25 new), 0 failures.

- [ ] **Step 2: Cross-check the worked example end-to-end in the simulator** (manual): seed the worked-example transactions via Capture/manual entry, set openings (現金 100,000 / 元入金 auto-adjust), add the PC asset, run 減価償却, and confirm 貸借対照表 shows 資産合計 = 負債・資本合計.

- [ ] **Step 3: Documentation**

Append to `README.md` Features list:

```markdown
- Produce the legal books for 青色申告: 仕訳帳, 総勘定元帳, 残高試算表, and 貸借対照表 with opening balances.
- Year-end closing: automatic depreciation journalization (家事按分 split), gapless-numbering check, fiscal-year lock with audited reopen, and 元入金 rollover.
```

- [ ] **Step 4: Report results to the user** — list deviations and any deferred items. Do NOT push.

---

## Self-review notes (already applied)

- **Type consistency:** `DepreciationAmount` (Task 2) is consumed by `YearEndClosingService.runDepreciation`/`depreciationPreview` (Task 8) and `YearEndClosingView` (Task 13); `TrialBalanceReport` field names match between Task 6 service, Task 9 CSV, and Task 11 view; `BalanceSheetReport.capitalOpening`/`ownerLoanClosing`/`ownerDrawClosing` match between Task 7, Task 10 PDF, and Task 12 view.
- **Schema ordering:** `OpeningBalance` registered in Task 5; `FiscalYearClosure` in Task 6 — each task compiles standalone.
- **Repository lock vs. depreciation posting:** depreciation entries go through `repository.create` and must precede `close()`; `close()` itself inserts no `JournalEntry`, so the lock cannot deadlock the flow.
- **Worked example arithmetic** verified: trial-balance totals 391,000/391,000 in Task 8's fixture context (the standalone Task 6 fixture omits depreciation entries → 361,000/361,000); B/S 426,000 = 426,000; rollover sums to zero.
