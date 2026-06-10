# SnapKei 固定資産登記 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 固定資産の登記（取得仕訳自動生成＋引継ぎ）・処分（転出仕訳自動生成）・削除 UI を追加し、既存の減価償却機構を解放する。

**Architecture:** `FixedAssetRules`（償却区分の選択可否＋検証）と `FixedAssetService`（登記/処分/削除のオーケストレーション、仕訳は `SwiftDataExpenseRepository.create` 経由）を TDD で追加。UI は Settings 内の `FixedAssetSection` を起点に Form/Detail を sheet 表示。少額特例の法定閾値 40万→**30万円未満**（措置法28条の2）の修正を含む。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing。`SnapKei/` 配下は自動インクルード。

**Spec reference:** `docs/superpowers/specs/2026-06-10-snapkei-fixed-asset-registration-design.md`

**Branch:** `fixed-asset-registration`（作成済み）

**User preferences carried forward:** Do NOT push. Do NOT commit without explicit user confirmation（コミット手順は checkpoint 提案のみ）。コード変更タスクの最後にフルテスト実行。

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Baseline: `** TEST SUCCEEDED **`, 189 tests / 41 suites（main = dbcaf3d）。

---

## File Structure

```
SnapKei/Domain/Services/
  ComplianceConstants.swift        [MODIFY — smallDepreciableAssetThreshold 400_000→300_000]
  FixedAssetRules.swift            [CREATE — availableTreatments + validate]
  FixedAssetService.swift          [CREATE — register/dispose/delete]
SnapKei/Presentation/Capture/
  TreatmentSuggestionBanner.swift  [MODIFY — 文言 40万→30万]
SnapKei/Presentation/Settings/
  FixedAssetSection.swift          [MODIFY — 登録ボタン + 行タップ + バッジ]
  FixedAssetFormView.swift         [CREATE]
  FixedAssetDetailView.swift       [CREATE]
SnapKeiTests/
  ComplianceServiceTests.swift     [MODIFY — 30万境界ピン追加]
  FixedAssetRulesTests.swift       [CREATE]
  FixedAssetServiceTests.swift     [CREATE]
```

---

## Task 1: 少額特例閾値の法定修正（40万→30万）

**Files:**
- Modify: `SnapKei/Domain/Services/ComplianceConstants.swift:4`
- Modify: `SnapKei/Presentation/Capture/TreatmentSuggestionBanner.swift:39,41`
- Test: `SnapKeiTests/ComplianceServiceTests.swift`

- [ ] **Step 1: Write the failing boundary tests**

`ComplianceServiceTests.swift` の `suggestAssetTreatment_400k_boundary_is_normal` の直後に追加:

```swift
    @Test func suggestAssetTreatment_300k_boundary_is_normal() {
        // 少額減価償却資産の特例は取得価額30万円未満（措置法28条の2）。
        #expect(ComplianceService.suggestAssetTreatment(amount: 300_000, acquisitionDate: date("2026-05-16")) == .normalDepreciation)
    }

    @Test func suggestAssetTreatment_299999_within_expiry_is_smallAmount() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 299_999, acquisitionDate: date("2026-05-16")) == .smallAmountFullExpense)
    }
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/ComplianceServiceTests test 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED|failed on" | sort -u | head
```

Expected: `suggestAssetTreatment_300k_boundary_is_normal` FAILS（現状 400_000 のため 300k は smallAmount になる）。

- [ ] **Step 3: Fix constant and banner copy**

`ComplianceConstants.swift`:

```swift
    public nonisolated static let smallDepreciableAssetThreshold = 300_000
```

`TreatmentSuggestionBanner.swift` detail 文言:

```swift
        case .smallAmountFullExpense:
            "20-30万円未満の固定資産は青色申告者の特例で一括費用化できます。"
        case .normalDepreciation:
            "取得価額30万円以上は耐用年数に応じた減価償却が必要です。"
```

（注: `.normalDepreciation` の文言は 30万円以上に変更。一括償却対象の 10-20万 文言は変更なし。既存テスト 280k→smallAmount / 400k→normal は新閾値でも GREEN のまま。）

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/ComplianceConstants.swift SnapKei/Presentation/Capture/TreatmentSuggestionBanner.swift SnapKeiTests/ComplianceServiceTests.swift
git commit -m "fix: 少額減価償却資産の特例 threshold is 300k (措置法28条の2)"
```

---

## Task 2: FixedAssetRules

**Files:**
- Create: `SnapKei/Domain/Services/FixedAssetRules.swift`
- Test: `SnapKeiTests/FixedAssetRulesTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("FixedAssetRules")
struct FixedAssetRulesTests {
    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @Test func availableTreatments_byAmountBands() {
        let d = date("2026-05-16")
        #expect(FixedAssetRules.availableTreatments(amount: 99_999, acquisitionDate: d) == [])
        #expect(FixedAssetRules.availableTreatments(amount: 150_000, acquisitionDate: d)
            == [.normalDepreciation, .lumpSumDepreciation, .smallAmountFullExpense])
        #expect(FixedAssetRules.availableTreatments(amount: 250_000, acquisitionDate: d)
            == [.normalDepreciation, .smallAmountFullExpense])
        #expect(FixedAssetRules.availableTreatments(amount: 300_000, acquisitionDate: d)
            == [.normalDepreciation])
    }

    @Test func availableTreatments_smallAmountExpiresWithDeadline() {
        let afterExpiry = date("2029-04-01")
        #expect(FixedAssetRules.availableTreatments(amount: 150_000, acquisitionDate: afterExpiry)
            == [.normalDepreciation, .lumpSumDepreciation])
    }

    @Test func validate_passesForValidInput() {
        let issues = FixedAssetRules.validate(
            name: "MacBook Pro",
            amount: 480_000,
            usefulLifeYears: 4,
            allocationRate: 1.0,
            treatment: .normalDepreciation,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.isEmpty)
    }

    @Test func validate_collectsIssues() {
        let issues = FixedAssetRules.validate(
            name: " ",
            amount: 0,
            usefulLifeYears: 1,
            allocationRate: 0,
            treatment: .normalDepreciation,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.contains(.missingName))
        #expect(issues.contains(.invalidAmount))
        #expect(issues.contains(.invalidUsefulLife))
        #expect(issues.contains(.invalidAllocation))
    }

    @Test func validate_treatmentMustBeAvailableForAmount() {
        // 350,000 円に少額特例は選べない（30万円以上）。
        let issues = FixedAssetRules.validate(
            name: "カメラ",
            amount: 350_000,
            usefulLifeYears: 5,
            allocationRate: 1.0,
            treatment: .smallAmountFullExpense,
            acquisitionDate: date("2026-05-16"),
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
        #expect(issues.contains(.treatmentNotAvailable))
    }

    @Test func validate_carriedOverAccumulatedBounds() {
        let over = FixedAssetRules.validate(
            name: "旧PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2024-01-01"),
            isCarriedOver: true, accumulatedDepreciation: 250_000
        )
        #expect(over.contains(.invalidAccumulated))

        let ok = FixedAssetRules.validate(
            name: "旧PC", amount: 200_000, usefulLifeYears: 4, allocationRate: 1.0,
            treatment: .normalDepreciation, acquisitionDate: date("2024-01-01"),
            isCarriedOver: true, accumulatedDepreciation: 100_000
        )
        #expect(ok.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/FixedAssetRulesTests test 2>&1 | grep -E "error:|TEST FAILED" | head -5
```

Expected: compile failure — `FixedAssetRules` 不存在。

- [ ] **Step 3: Implement FixedAssetRules.swift**

```swift
import Foundation

/// 固定資産登記の検証と償却区分の選択可否（View から分離してテスト可能に）。
public enum FixedAssetRules {
    public enum Issue: Equatable, Sendable {
        case missingName
        case invalidAmount
        case invalidUsefulLife
        case invalidAllocation
        case treatmentNotAvailable
        case invalidAccumulated
    }

    /// 金額・取得日から法的に選択可能な償却区分。10万円未満は資産計上対象外（空配列）。
    /// 先頭は常に定額法（恒久的に選択可能）。
    public static func availableTreatments(amount: Int, acquisitionDate: Date) -> [AssetTreatment] {
        guard amount >= 100_000 else { return [] }
        var treatments: [AssetTreatment] = [.normalDepreciation]
        if amount < ComplianceConstants.lumpSumDepreciationThreshold {
            treatments.append(.lumpSumDepreciation)
        }
        if amount < ComplianceConstants.smallDepreciableAssetThreshold,
           acquisitionDate <= ComplianceConstants.smallDepreciableExpiry {
            treatments.append(.smallAmountFullExpense)
        }
        return treatments
    }

    public static func validate(
        name: String,
        amount: Int,
        usefulLifeYears: Int,
        allocationRate: Double,
        treatment: AssetTreatment,
        acquisitionDate: Date,
        isCarriedOver: Bool,
        accumulatedDepreciation: Int
    ) -> [Issue] {
        var issues: [Issue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.missingName) }
        if amount <= 0 { issues.append(.invalidAmount) }
        if !(2...50).contains(usefulLifeYears) { issues.append(.invalidUsefulLife) }
        if allocationRate <= 0 || allocationRate > 1 { issues.append(.invalidAllocation) }
        if amount > 0, !availableTreatments(amount: amount, acquisitionDate: acquisitionDate).contains(treatment) {
            issues.append(.treatmentNotAvailable)
        }
        if isCarriedOver, !(0...max(amount, 0)).contains(accumulatedDepreciation) {
            issues.append(.invalidAccumulated)
        }
        return issues
    }
}
```

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/FixedAssetRules.swift SnapKeiTests/FixedAssetRulesTests.swift
git commit -m "feat: fixed-asset registration rules"
```

---

## Task 3: FixedAssetService — register（新規購入 / 少額特例即時償却 / 引継ぎ）

**Files:**
- Create: `SnapKei/Domain/Services/FixedAssetService.swift`
- Test: `SnapKeiTests/FixedAssetServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import SnapKei

@MainActor
private enum FixedAssetTestContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}

@Suite("FixedAssetService", .serialized)
struct FixedAssetServiceTests {

    @MainActor
    private func makeService() throws -> (FixedAssetService, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        FixedAssetTestContainerRetainer.retain(container)
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let service = FixedAssetService(context: container.mainContext, deviceId: "test-device")
        return (service, container.mainContext)
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    private func purchaseInput(
        amount: Int = 480_000,
        treatment: AssetTreatment = .normalDepreciation,
        allocation: Double = 1.0
    ) -> FixedAssetService.RegistrationInput {
        FixedAssetService.RegistrationInput(
            name: "MacBook Pro",
            categoryCode: "PC",
            acquisitionDate: date("2026-05-16"),
            serviceStartDate: date("2026-05-16"),
            acquisitionAmount: amount,
            usefulLifeYears: 4,
            treatment: treatment,
            businessAllocationRate: allocation,
            paymentMethod: .bankTransfer,
            taxCategory: .standard10,
            isCarriedOver: false,
            accumulatedDepreciation: 0
        )
    }

    @MainActor
    @Test func register_purchase_createsAssetAndAcquisitionEntry() throws {
        let (service, context) = try makeService()

        let asset = try service.register(purchaseInput())

        #expect(asset.bookValue == 480_000)
        #expect(asset.accumulatedDepreciation == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.debitAccountCode == AccountCode.equipment)
        #expect(entry.creditAccountCode == AccountCode.bankDeposit)
        #expect(entry.amountIncludingTax == 480_000)
        #expect(entry.relatedFixedAssetId == asset.syncId)
        #expect(asset.acquisitionJournalEntryId == entry.id)
        #expect(entry.fiscalYear == 2026)
        #expect(entry.sourceTypeRaw == RecordSource.manual.rawValue)
    }

    @MainActor
    @Test func register_smallAmountFullExpense_postsImmediateDepreciation() throws {
        let (service, context) = try makeService()

        // 250,000 円・事業割合 80% の少額特例（即時償却）。
        let asset = try service.register(purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense, allocation: 0.8))

        #expect(asset.accumulatedDepreciation == 250_000)
        #expect(asset.bookValue == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 3) // 取得 + 償却(経費分) + 償却(家事分)
        let depreciation = entries.filter { $0.sourceTypeRaw == RecordSource.depreciation.rawValue }
        #expect(depreciation.count == 2)
        let deductible = depreciation.first { $0.debitAccountCode == AccountCode.depreciationExpense }
        let owner = depreciation.first { $0.debitAccountCode == AccountCode.ownerDraw }
        #expect(deductible?.amountIncludingTax == 200_000)
        #expect(owner?.amountIncludingTax == 50_000)
        #expect(deductible?.creditAccountCode == AccountCode.accumulatedDepreciation)
    }

    @MainActor
    @Test func register_carriedOver_createsNoEntries() throws {
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 200_000)
        input.isCarriedOver = true
        input.accumulatedDepreciation = 100_000

        let asset = try service.register(input)

        #expect(asset.bookValue == 100_000)
        #expect(asset.accumulatedDepreciation == 100_000)
        #expect(asset.acquisitionJournalEntryId == nil)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }

    @MainActor
    @Test func register_invalidInput_throwsValidationError() throws {
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 50_000) // 10万円未満は登記不可

        #expect(throws: FixedAssetService.ServiceError.self) {
            try service.register(input)
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
        _ = input
    }

    @MainActor
    @Test func register_closedFiscalYear_throwsAndLeavesNothing() throws {
        let (service, context) = try makeService()
        context.insert(FiscalYearClosure(fiscalYear: 2026, netIncomeAtClosing: 0, closedByDeviceId: "x"))
        try context.save()

        #expect(throws: RepositoryError.fiscalYearClosed(2026)) {
            try service.register(purchaseInput())
        }
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/FixedAssetServiceTests test 2>&1 | grep -E "error:|TEST FAILED" | head -5
```

Expected: compile failure — `FixedAssetService` 不存在。

- [ ] **Step 3: Implement FixedAssetService.swift（register まで）**

```swift
import Foundation
import SwiftData

/// 固定資産の登記・処分・削除。仕訳は ExpenseRepository 経由（採番・監査ログ・同期通知込み）。
@MainActor
public final class FixedAssetService {
    public struct RegistrationInput {
        public var name: String
        public var categoryCode: String
        public var acquisitionDate: Date
        public var serviceStartDate: Date
        public var acquisitionAmount: Int
        public var usefulLifeYears: Int
        public var treatment: AssetTreatment
        public var businessAllocationRate: Double
        public var paymentMethod: PaymentMethod
        public var taxCategory: TaxCategory
        public var isCarriedOver: Bool
        public var accumulatedDepreciation: Int

        public init(
            name: String,
            categoryCode: String,
            acquisitionDate: Date,
            serviceStartDate: Date,
            acquisitionAmount: Int,
            usefulLifeYears: Int,
            treatment: AssetTreatment,
            businessAllocationRate: Double,
            paymentMethod: PaymentMethod,
            taxCategory: TaxCategory,
            isCarriedOver: Bool,
            accumulatedDepreciation: Int
        ) {
            self.name = name
            self.categoryCode = categoryCode
            self.acquisitionDate = acquisitionDate
            self.serviceStartDate = serviceStartDate
            self.acquisitionAmount = acquisitionAmount
            self.usefulLifeYears = usefulLifeYears
            self.treatment = treatment
            self.businessAllocationRate = businessAllocationRate
            self.paymentMethod = paymentMethod
            self.taxCategory = taxCategory
            self.isCarriedOver = isCarriedOver
            self.accumulatedDepreciation = accumulatedDepreciation
        }
    }

    public enum ServiceError: Error, Equatable, LocalizedError {
        case validationFailed([FixedAssetRules.Issue])
        case alreadyDisposed
        case hasDepreciationEntries

        public var errorDescription: String? {
            switch self {
            case .validationFailed: "入力内容を確認してください。"
            case .alreadyDisposed: "この資産は処分済みです。"
            case .hasDepreciationEntries: "償却仕訳が存在する資産は削除できません。処分を記録してください。"
            }
        }
    }

    private let context: ModelContext
    private let deviceId: String
    private let repository: SwiftDataExpenseRepository

    public init(context: ModelContext, deviceId: String) {
        self.context = context
        self.deviceId = deviceId
        self.repository = SwiftDataExpenseRepository(context: context, deviceId: deviceId)
    }

    @discardableResult
    public func register(_ input: RegistrationInput) throws -> FixedAsset {
        let issues = FixedAssetRules.validate(
            name: input.name,
            amount: input.acquisitionAmount,
            usefulLifeYears: input.usefulLifeYears,
            allocationRate: input.businessAllocationRate,
            treatment: input.treatment,
            acquisitionDate: input.acquisitionDate,
            isCarriedOver: input.isCarriedOver,
            accumulatedDepreciation: input.accumulatedDepreciation
        )
        guard issues.isEmpty else { throw ServiceError.validationFailed(issues) }

        let accumulated = input.isCarriedOver ? input.accumulatedDepreciation : 0
        let asset = FixedAsset(
            assetName: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            assetCategoryCode: input.categoryCode,
            acquisitionDate: input.acquisitionDate,
            serviceStartDate: input.serviceStartDate,
            acquisitionAmount: input.acquisitionAmount,
            usefulLifeYears: input.usefulLifeYears,
            treatment: input.treatment,
            businessAllocationRate: input.businessAllocationRate,
            accumulatedDepreciation: accumulated,
            bookValue: input.acquisitionAmount - accumulated
        )

        if input.isCarriedOver {
            // 引継ぎ: 仕訳なしで台帳にのみ載せる（B/S 表示は期首残高に依存）。
            context.insert(asset)
            try context.save()
            SyncChangeNotifier.shared.notify()
            return asset
        }

        try ensureFiscalYearOpen(FiscalYearRule.year(for: input.acquisitionDate))
        context.insert(asset)
        do {
            let split = TaxSplit.split(amount: input.acquisitionAmount, mode: .taxIncluded, rate: input.taxCategory.taxRate)
            let acquisition = JournalEntry(
                entryNumber: 0,
                fiscalYear: FiscalYearRule.year(for: input.acquisitionDate),
                transactionDate: input.acquisitionDate,
                debitAccountCode: AccountCode.equipment,
                creditAccountCode: input.paymentMethod.defaultCreditAccountCode ?? AccountCode.ownerLoan,
                amountIncludingTax: split.total,
                amountExcludingTax: split.excludingTax,
                consumptionTax: split.tax,
                taxCategory: input.taxCategory,
                priceEntryMode: .taxIncluded,
                paymentMethod: input.paymentMethod,
                counterpartyName: asset.assetName,
                transactionDescription: "\(asset.assetName) 取得",
                relatedFixedAssetId: asset.syncId,
                sourceType: .manual
            )
            try repository.create(acquisition, reason: "固定資産登記")
            asset.acquisitionJournalEntryId = acquisition.id

            if input.treatment == .smallAmountFullExpense {
                try postImmediateExpensing(for: asset)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
        return asset
    }

    /// 少額特例 = 即時償却。DepreciationService は本区分に 0 を返すため登記時に全額を償却計上する。
    private func postImmediateExpensing(for asset: FixedAsset) throws {
        let full = asset.acquisitionAmount
        let deductible = Int((Double(full) * asset.businessAllocationRate).rounded(.down))
        let ownerPortion = full - deductible
        if deductible > 0 {
            try repository.create(depreciationEntry(
                asset: asset, debit: AccountCode.depreciationExpense, amount: deductible,
                description: "\(asset.assetName) 即時償却（少額特例）"
            ), reason: "少額特例即時償却")
        }
        if ownerPortion > 0 {
            try repository.create(depreciationEntry(
                asset: asset, debit: AccountCode.ownerDraw, amount: ownerPortion,
                description: "\(asset.assetName) 即時償却（家事分）"
            ), reason: "少額特例即時償却")
        }
        asset.accumulatedDepreciation = full
        asset.bookValue = 0
    }

    private func depreciationEntry(asset: FixedAsset, debit: String, amount: Int, description: String) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: asset.acquisitionDate),
            transactionDate: asset.acquisitionDate,
            debitAccountCode: debit,
            creditAccountCode: AccountCode.accumulatedDepreciation,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: asset.assetName,
            transactionDescription: description,
            relatedFixedAssetId: asset.syncId,
            sourceType: .depreciation
        )
    }

    private func ensureFiscalYearOpen(_ fiscalYear: Int) throws {
        let descriptor = FetchDescriptor<FiscalYearClosure>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
        )
        if try context.fetchCount(descriptor) > 0 {
            throw RepositoryError.fiscalYearClosed(fiscalYear)
        }
    }
}
```

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/FixedAssetService.swift SnapKeiTests/FixedAssetServiceTests.swift
git commit -m "feat: fixed-asset registration service (purchase/carried-over/immediate expensing)"
```

---

## Task 4: FixedAssetService — dispose / delete

**Files:**
- Modify: `SnapKei/Domain/Services/FixedAssetService.swift`
- Test: `SnapKeiTests/FixedAssetServiceTests.swift`

- [ ] **Step 1: Write the failing tests（FixedAssetServiceTests に追加）**

```swift
    @MainActor
    @Test func dispose_postsTransferOutEntriesAndMarksAsset() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput()) // 480,000 / 簿価480,000
        asset.accumulatedDepreciation = 120_000
        asset.bookValue = 360_000
        try context.save()

        try service.dispose(asset, on: date("2026-09-30"), proceeds: 200_000)

        #expect(asset.disposalDate == date("2026-09-30"))
        #expect(asset.disposalAmount == 200_000)
        #expect(asset.bookValue == 0)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
            .filter { $0.sourceTypeRaw == RecordSource.manual.rawValue && $0.transactionDescription.contains("処分") }
        #expect(entries.count == 2)
        let accumulated = entries.first { $0.debitAccountCode == AccountCode.accumulatedDepreciation }
        let ownerOut = entries.first { $0.debitAccountCode == AccountCode.ownerDraw }
        #expect(accumulated?.amountIncludingTax == 120_000)
        #expect(accumulated?.creditAccountCode == AccountCode.equipment)
        #expect(ownerOut?.amountIncludingTax == 360_000)
        #expect(ownerOut?.creditAccountCode == AccountCode.equipment)
    }

    @MainActor
    @Test func dispose_zeroAccumulated_postsSingleEntry() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput())

        try service.dispose(asset, on: date("2026-09-30"), proceeds: nil)

        let disposals = try context.fetch(FetchDescriptor<JournalEntry>())
            .filter { $0.transactionDescription.contains("処分") }
        #expect(disposals.count == 1)
        #expect(disposals.first?.amountIncludingTax == 480_000)
    }

    @MainActor
    @Test func dispose_twice_throws() throws {
        let (service, _) = try makeService()
        let asset = try service.register(purchaseInput())
        try service.dispose(asset, on: date("2026-09-30"), proceeds: nil)

        #expect(throws: FixedAssetService.ServiceError.alreadyDisposed) {
            try service.dispose(asset, on: date("2026-10-01"), proceeds: nil)
        }
    }

    @MainActor
    @Test func delete_withDepreciationEntries_throws() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput(amount: 250_000, treatment: .smallAmountFullExpense))
        _ = context // 即時償却仕訳が存在する

        #expect(throws: FixedAssetService.ServiceError.hasDepreciationEntries) {
            try service.delete(asset)
        }
        #expect(asset.deletedAt == nil)
    }

    @MainActor
    @Test func delete_voidsAcquisitionEntryAndSoftDeletes() throws {
        let (service, context) = try makeService()
        let asset = try service.register(purchaseInput())

        try service.delete(asset)

        #expect(asset.deletedAt != nil)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.isVoided == true)
    }

    @MainActor
    @Test func delete_carriedOver_noEntries_softDeletes() throws {
        let (service, context) = try makeService()
        var input = purchaseInput(amount: 200_000)
        input.isCarriedOver = true
        input.accumulatedDepreciation = 50_000
        let asset = try service.register(input)

        try service.delete(asset)

        #expect(asset.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
    }
```

- [ ] **Step 2: Run to verify RED**

Expected: compile failure — `dispose`/`delete` 不存在。

- [ ] **Step 3: Implement dispose / delete（FixedAssetService に追加）**

```swift
    /// 処分（売却/除却）。個人事業主の事業用資産売却は譲渡所得（事業損益外）のため
    /// 帳簿からは事業主貸で転出する。売却代金は台帳に記録のみ。
    public func dispose(_ asset: FixedAsset, on disposalDate: Date, proceeds: Int?) throws {
        guard asset.disposalDate == nil else { throw ServiceError.alreadyDisposed }
        try ensureFiscalYearOpen(FiscalYearRule.year(for: disposalDate))

        do {
            if asset.accumulatedDepreciation > 0 {
                try repository.create(disposalEntry(
                    asset: asset, date: disposalDate,
                    debit: AccountCode.accumulatedDepreciation,
                    amount: asset.accumulatedDepreciation,
                    description: "\(asset.assetName) 処分（償却累計の振替）"
                ), reason: "固定資産処分")
            }
            if asset.bookValue > 0 {
                try repository.create(disposalEntry(
                    asset: asset, date: disposalDate,
                    debit: AccountCode.ownerDraw,
                    amount: asset.bookValue,
                    description: "\(asset.assetName) 処分（簿価の事業主貸転出）"
                ), reason: "固定資産処分")
            }
            asset.disposalDate = disposalDate
            asset.disposalAmount = proceeds
            asset.bookValue = 0
            asset.updatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
    }

    private func disposalEntry(asset: FixedAsset, date: Date, debit: String, amount: Int, description: String) -> JournalEntry {
        JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: date),
            transactionDate: date,
            debitAccountCode: debit,
            creditAccountCode: AccountCode.equipment,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: asset.assetName,
            transactionDescription: description,
            relatedFixedAssetId: asset.syncId,
            sourceType: .manual
        )
    }

    /// 償却仕訳が無い資産のみ削除可（誤登記の取り消し）。取得仕訳は自動 void。
    public func canDelete(_ asset: FixedAsset) -> Bool {
        ((try? depreciationEntryCount(for: asset)) ?? 1) == 0
    }

    public func delete(_ asset: FixedAsset) throws {
        guard try depreciationEntryCount(for: asset) == 0 else {
            throw ServiceError.hasDepreciationEntries
        }
        do {
            if let entryId = asset.acquisitionJournalEntryId {
                let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == entryId })
                if let acquisition = try context.fetch(descriptor).first, !acquisition.isVoided {
                    try repository.void(acquisition, reason: "資産登記の取消")
                }
            }
            asset.deletedAt = Date()
            asset.updatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        SyncChangeNotifier.shared.notify()
    }

    private func depreciationEntryCount(for asset: FixedAsset) throws -> Int {
        let assetId = asset.syncId
        let raw = RecordSource.depreciation.rawValue
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.relatedFixedAssetId == assetId && $0.sourceTypeRaw == raw && !$0.isVoided }
        )
        return try context.fetchCount(descriptor)
    }
```

- [ ] **Step 4: Run to verify GREEN**

Same command. Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Domain/Services/FixedAssetService.swift SnapKeiTests/FixedAssetServiceTests.swift
git commit -m "feat: fixed-asset disposal and deletion"
```

---

## Task 5: UI — FixedAssetFormView / FixedAssetDetailView / Section 接線

**Files:**
- Create: `SnapKei/Presentation/Settings/FixedAssetFormView.swift`
- Create: `SnapKei/Presentation/Settings/FixedAssetDetailView.swift`
- Modify: `SnapKei/Presentation/Settings/FixedAssetSection.swift`

View のため単体テストなし（build + smoke）。

- [ ] **Step 1: Create FixedAssetFormView.swift**

```swift
import SwiftData
import SwiftUI

/// 固定資産の登記フォーム。新規購入（取得仕訳自動生成）と既存資産の引継ぎに対応。
struct FixedAssetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AssetUsefulLife.code) private var categories: [AssetUsefulLife]

    @State private var name = ""
    @State private var categoryCode = "PC"
    @State private var acquisitionDate = Date()
    @State private var serviceStartDate = Date()
    @State private var amountText = ""
    @State private var usefulLifeYears = 4
    @State private var treatment = AssetTreatment.normalDepreciation
    @State private var allocationPercentText = "100"
    @State private var allocationRate = 1.0
    @FocusState private var allocationFieldFocused: Bool
    @State private var paymentMethod = PaymentMethod.ownerLoan
    @State private var taxCategory = TaxCategory.standard10
    @State private var isCarriedOver = false
    @State private var accumulatedText = "0"
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("資産") {
                    TextField("資産名", text: $name)
                    Picker("カテゴリ", selection: $categoryCode) {
                        ForEach(categories, id: \.code) { category in
                            Text(category.nameJa).tag(category.code)
                        }
                    }
                    Stepper("耐用年数: \(usefulLifeYears) 年", value: $usefulLifeYears, in: 2...50)
                    DatePicker("取得日", selection: $acquisitionDate, displayedComponents: .date)
                    DatePicker("使用開始日", selection: $serviceStartDate, displayedComponents: .date)
                }

                Section {
                    TextField("取得価額(税込)", text: $amountText).keyboardType(.numberPad)
                    if let amount = Int(amountText), amount > 0 {
                        if availableTreatments.isEmpty {
                            Label("10万円未満は固定資産ではなく消耗品費等で経費計上してください。", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else {
                            Picker("償却区分", selection: $treatment) {
                                ForEach(availableTreatments, id: \.self) { option in
                                    Text(treatmentLabel(option)).tag(option)
                                }
                            }
                            if let suggested = ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate) {
                                Text("推奨: \(treatmentLabel(suggested))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Text("事業割合")
                        Spacer()
                        TextField("", text: $allocationPercentText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($allocationFieldFocused)
                            .frame(width: 56)
                            .onChange(of: allocationPercentText) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue { allocationPercentText = filtered }
                            }
                            .onChange(of: allocationFieldFocused) { _, focused in
                                if !focused { commitAllocationPercent() }
                            }
                            .onSubmit(commitAllocationPercent)
                        Text("%").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("金額・償却")
                }

                Section {
                    Toggle("既存資産の引継ぎ", isOn: $isCarriedOver)
                    if isCarriedOver {
                        TextField("償却累計額", text: $accumulatedText).keyboardType(.numberPad)
                    } else {
                        Picker("支払方法", selection: $paymentMethod) {
                            Text("現金").tag(PaymentMethod.cash)
                            Text("クレジット").tag(PaymentMethod.creditCard)
                            Text("銀行振込").tag(PaymentMethod.bankTransfer)
                            Text("事業主借").tag(PaymentMethod.ownerLoan)
                        }
                        Picker("税区分", selection: $taxCategory) {
                            Text("10%").tag(TaxCategory.standard10)
                            Text("8% 軽減").tag(TaxCategory.reduced8)
                            Text("対象外").tag(TaxCategory.outOfScope)
                        }
                    }
                } header: {
                    Text("記帳")
                } footer: {
                    Text(isCarriedOver
                        ? "開業前・アプリ導入前から保有する資産用。仕訳は生成されません（期首残高で資産計上してください）。"
                        : "登記と同時に取得仕訳（工具器具備品/支払方法）を自動生成します。")
                }

                Section {
                    Button("登録") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("資産を登録")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!name.isEmpty || !amountText.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
            .onChange(of: categoryCode) { _, newCode in
                if let category = categories.first(where: { $0.code == newCode }) {
                    usefulLifeYears = category.years
                }
            }
            .onChange(of: amountText) { _, _ in
                // 金額帯で選択不能になった償却区分を補正する。
                if !availableTreatments.isEmpty, !availableTreatments.contains(treatment) {
                    treatment = availableTreatments[0]
                }
            }
            .alert(
                "登録できませんでした",
                isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private var availableTreatments: [AssetTreatment] {
        FixedAssetRules.availableTreatments(amount: Int(amountText) ?? 0, acquisitionDate: acquisitionDate)
    }

    private var isValid: Bool {
        FixedAssetRules.validate(
            name: name,
            amount: Int(amountText) ?? 0,
            usefulLifeYears: usefulLifeYears,
            allocationRate: allocationRate,
            treatment: treatment,
            acquisitionDate: acquisitionDate,
            isCarriedOver: isCarriedOver,
            accumulatedDepreciation: Int(accumulatedText) ?? 0
        ).isEmpty
    }

    private func treatmentLabel(_ treatment: AssetTreatment) -> String {
        switch treatment {
        case .normalDepreciation: "定額法"
        case .lumpSumDepreciation: "一括償却(3年)"
        case .smallAmountFullExpense: "少額特例(即時償却)"
        }
    }

    private func commitAllocationPercent() {
        let clamped = max(0, min(100, Int(allocationPercentText) ?? 0))
        allocationPercentText = String(clamped)
        allocationRate = Double(clamped) / 100.0
    }

    private func save() {
        guard !isSaving else { return }
        commitAllocationPercent()
        guard let amount = Int(amountText), amount > 0 else { return }
        isSaving = true
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.register(FixedAssetService.RegistrationInput(
                name: name,
                categoryCode: categoryCode,
                acquisitionDate: acquisitionDate,
                serviceStartDate: serviceStartDate,
                acquisitionAmount: amount,
                usefulLifeYears: usefulLifeYears,
                treatment: treatment,
                businessAllocationRate: allocationRate,
                paymentMethod: paymentMethod,
                taxCategory: taxCategory,
                isCarriedOver: isCarriedOver,
                accumulatedDepreciation: Int(accumulatedText) ?? 0
            ))
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
```

- [ ] **Step 2: Create FixedAssetDetailView.swift**

```swift
import SwiftData
import SwiftUI

/// 資産の詳細・処分・削除。
struct FixedAssetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: FixedAsset

    @State private var disposalDate = Date()
    @State private var proceedsText = ""
    @State private var showDisposeConfirmation = false
    @State private var actionErrorMessage: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("資産") {
                    row("資産名", asset.assetName)
                    row("取得日", asset.acquisitionDate.formatted(date: .numeric, time: .omitted))
                    row("取得価額", YenFormat.string(asset.acquisitionAmount))
                    row("耐用年数", "\(asset.usefulLifeYears) 年")
                    row("償却区分", treatmentLabel(asset.treatment))
                    row("事業割合", "\(Int((asset.businessAllocationRate * 100).rounded()))%")
                    row("償却累計額", YenFormat.string(asset.accumulatedDepreciation))
                    row("簿価", YenFormat.string(asset.bookValue))
                }

                if let disposed = asset.disposalDate {
                    Section("処分") {
                        row("処分日", disposed.formatted(date: .numeric, time: .omitted))
                        if let proceeds = asset.disposalAmount {
                            row("売却代金", YenFormat.string(proceeds))
                        }
                    }
                } else {
                    Section {
                        DatePicker("処分日", selection: $disposalDate, displayedComponents: .date)
                        TextField("売却代金（任意・記録のみ）", text: $proceedsText).keyboardType(.numberPad)
                        Button("処分する", role: .destructive) { showDisposeConfirmation = true }
                    } header: {
                        Text("処分（売却・除却）")
                    } footer: {
                        Text("償却累計 \(YenFormat.string(asset.accumulatedDepreciation)) と簿価 \(YenFormat.string(asset.bookValue)) を帳簿から転出する仕訳を自動生成します。売却代金は譲渡所得（事業外）のため記帳されません。事業口座に入金した場合は手動入力の振替（普通預金/事業主借）で記帳してください。")
                    }
                }

                if asset.disposalDate == nil, canDelete {
                    Section {
                        Button("削除（誤登記の取消）", role: .destructive) { showDeleteConfirmation = true }
                    } footer: {
                        Text("台帳から削除し、取得仕訳があれば取消（void）します。")
                    }
                }
            }
            .navigationTitle("資産の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .confirmationDialog("処分を記録しますか？", isPresented: $showDisposeConfirmation, titleVisibility: .visible) {
                Button("処分する", role: .destructive) { dispose() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("転出仕訳（最大2件）を作成し、翌年以降の減価償却を停止します。")
            }
            .confirmationDialog("削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { deleteAsset() }
                Button("キャンセル", role: .cancel) {}
            }
            .alert(
                "操作できませんでした",
                isPresented: Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
        }
    }

    private var canDelete: Bool {
        FixedAssetService(context: context, deviceId: DeviceID.current).canDelete(asset)
    }

    private func dispose() {
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.dispose(asset, on: disposalDate, proceeds: Int(proceedsText))
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func deleteAsset() {
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.delete(asset)
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func treatmentLabel(_ treatment: AssetTreatment) -> String {
        switch treatment {
        case .normalDepreciation: "定額法"
        case .lumpSumDepreciation: "一括償却(3年)"
        case .smallAmountFullExpense: "少額特例(即時償却)"
        }
    }
}
```

- [ ] **Step 3: Rewrite FixedAssetSection.swift**

```swift
import SwiftData
import SwiftUI

public struct FixedAssetSection: View {
    @Query(
        filter: #Predicate<FixedAsset> { $0.deletedAt == nil },
        sort: \FixedAsset.acquisitionDate,
        order: .reverse
    ) private var assets: [FixedAsset]

    @State private var showRegisterForm = false
    @State private var selectedAsset: FixedAsset?

    public init() {}

    public var body: some View {
        Section("固定資産台帳") {
            Button {
                showRegisterForm = true
            } label: {
                Label("資産を登録", systemImage: "plus.circle")
            }

            if assets.isEmpty {
                Text("資産が登録されていません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    Button {
                        selectedAsset = asset
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(asset.assetName).font(.subheadline.weight(.semibold))
                                if asset.disposalDate != nil {
                                    Text("処分済")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            HStack {
                                Text("取得 \(YenFormat.string(asset.acquisitionAmount))")
                                Spacer()
                                Text("簿価 \(YenFormat.string(asset.bookValue))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showRegisterForm) { FixedAssetFormView() }
        .sheet(item: $selectedAsset) { asset in FixedAssetDetailView(asset: asset) }
    }
}
```

（注: `FixedAsset` は `@Model` で `Identifiable` 準拠のため `sheet(item:)` がそのまま使える。）

- [ ] **Step 4: Build to verify compile**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | sort -u | head
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: Checkpoint（ユーザー確認後のみ）**

```bash
git add SnapKei/Presentation/Settings/FixedAssetFormView.swift SnapKei/Presentation/Settings/FixedAssetDetailView.swift SnapKei/Presentation/Settings/FixedAssetSection.swift
git commit -m "feat: fixed-asset register/detail/dispose UI"
```

---

## Task 6: Final verification

- [ ] **Step 1: Full test run**

Standard test command. Expected: `** TEST SUCCEEDED **`, 202 tests 前後（189 + Compliance 2 + Rules 6 + Service 11... 正確な本数は実行結果で報告）。

- [ ] **Step 2: Manual smoke (simulator)**

- 設定 > 固定資産台帳 > 資産を登録: 48万円 PC（銀行振込・定額法）→ 一覧に簿価 48万で出現、一覧タブに取得仕訳「工具器具備品/普通預金」。
- 25万円カメラを少額特例で登録 → 仕訳3件（取得+償却2）、簿価 0。
- 引継ぎ ON で登録 → 仕訳なし。
- 詳細 > 処分する → 転出仕訳生成・「処分済」バッジ・翌年度の帳簿で償却なし。
- 誤登記を削除 → 取得仕訳が「取消」バッジ。
- 帳簿 > 青色申告決算書: 減価償却テーブルに登録資産が出現。

- [ ] **Step 3: Report results**

テスト/ビルド結果と逸脱を報告。push しない。コミットはユーザー確認後。

---

## Out-of-Scope（spec 参照）

処分年度の月割償却 / 財務項目の登記後編集 / 車両 1620 等の科目振り分け / 期首残高 UI。
