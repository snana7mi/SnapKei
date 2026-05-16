# SnapKei Foundation (Phase 0 + 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data foundation for SnapKei iOS app — scaffold the Xcode project, then implement the SwiftData entities, compliance services, repository layer, depreciation logic, and seed data that the rest of MVP will depend on.

**Architecture:** SwiftUI + SwiftData + iOS 18.5+ Clean Architecture (`App/Domain/Data/Presentation`). This plan covers the data + compliance layer only — no AI integration, no real UI beyond placeholder views. The placeholder `RootView` is a 4-tab skeleton that proves the app boots and the ModelContainer attaches. Subsequent plans (`Plan 2: AI Layer`, `Plan 3: UI + Worker`) build on top.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / `swift-testing` framework / Xcode 26+ with `PBXFileSystemSynchronizedRootGroup` (avoid manual `.pbxproj` file-reference edits — files under synchronized source folders are picked up automatically; build setting and test-target project edits are intentional when automated).

**Spec reference:** `/Users/lee/workspace/SnapKei/docs/superpowers/specs/2026-05-16-snapkei-mvp-design.md`

**Working directory:** `/Users/lee/workspace/SnapKei/`. **All file paths in this plan are absolute** and use the repository's actual casing.

**User preferences:**
- Do NOT `git push` to remote at any point in this plan
- Commit steps are checkpoints only; the executing agent must ask for explicit confirmation before running `git commit`
- Build verification (`xcodebuild build`) required at the end of every Phase

**Execution corrections from review:**
- Prefer automated project edits for `SnapKeiTests`; only pause for the Xcode UI flow if automated test-target creation fails.
- Treat shell snippets as intent, not mandatory mechanics. In assistant environments, use safer file/edit/search tools instead of destructive/read-oriented shell commands where required.
- Verify any legal/compliance constants against cited sources before broadening beyond this MVP assumption set.

---

## File Structure (created/modified by this plan)

```
/Users/lee/workspace/SnapKei/
├── SnapKei.xcodeproj/
│   └── project.pbxproj             [MODIFY: deployment target 18.5, Swift 6]
├── Secrets.xcconfig                 [CREATE]
├── SnapKei/                         (existing folder, PBXFileSystemSynchronizedRootGroup)
│   ├── App/
│   │   └── SnapKeiApp.swift         [MOVE from SnapKei/SnapKeiApp.swift, modify body]
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── Enums.swift          [CREATE — 9 enums]
│   │   │   ├── Account.swift        [CREATE — @Model 勘定科目]
│   │   │   ├── AssetUsefulLife.swift[CREATE — @Model 耐用年数 master]
│   │   │   ├── JournalEntry.swift   [CREATE — @Model 仕訳]
│   │   │   ├── SystemActivityLog.swift [CREATE — @Model 履歴]
│   │   │   └── FixedAsset.swift     [CREATE — @Model 固定資産]
│   │   └── Services/
│   │       ├── ComplianceConstants.swift [CREATE]
│   │       ├── ComplianceService.swift   [CREATE]
│   │       └── DepreciationService.swift [CREATE]
│   ├── Data/
│   │   ├── Persistence/
│   │   │   ├── ModelContainer+SnapKei.swift [CREATE]
│   │   │   └── ExpenseRepository.swift      [CREATE]
│   │   ├── Settings/
│   │   │   └── AppSettings.swift            [CREATE]
│   │   └── Seed/
│   │       ├── AccountSeeder.swift          [CREATE]
│   │       ├── AssetUsefulLifeSeeder.swift  [CREATE]
│   │       ├── accounts_seed.json           [CREATE — 33 科目]
│   │       └── asset_useful_life_seed.json  [CREATE — 7 種]
│   ├── Presentation/
│   │   └── RootView.swift           [CREATE — 4 タブ placeholder]
│   ├── Resources/
│   │   └── Localizable.xcstrings    [CREATE — zh + ja]
│   ├── Assets.xcassets/             (existing, unchanged)
│   └── ContentView.swift            [DELETE]
└── SnapKeiTests/                    (created automatically if possible; Xcode UI fallback in Task 0.6)
    ├── EnumsTests.swift             [CREATE]
    ├── ComplianceServiceTests.swift [CREATE]
    ├── DepreciationServiceTests.swift [CREATE]
    ├── ExpenseRepositoryTests.swift [CREATE]
    ├── SeederTests.swift            [CREATE]
    └── AppSettingsTests.swift       [CREATE]
```

**One-time test target prerequisite (Task 0.6):** create a Unit Test Target automatically if possible; otherwise add it via Xcode UI. The rest of this plan is fully automatable.

---

# Phase 0: Scaffold

## Task 0.1: Verify baseline + remove starter template

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/ContentView.swift` (delete)

- [ ] **Step 1: Verify project state**

Run:
```bash
ls -la /Users/lee/workspace/SnapKei/ && \
ls -la /Users/lee/workspace/SnapKei/SnapKei/ && \
test -d /Users/lee/workspace/SnapKei/.git && echo "git OK"
```
Expected: see `SnapKei.xcodeproj`, `SnapKei/`, `.git/`. `SnapKei/` contains `SnapKeiApp.swift`, `ContentView.swift`, `Assets.xcassets`.

- [ ] **Step 2: Delete ContentView.swift**

Run:
```bash
rm /Users/lee/workspace/SnapKei/SnapKei/ContentView.swift
```

- [ ] **Step 3: Confirm clean**

Run:
```bash
ls /Users/lee/workspace/SnapKei/SnapKei/
```
Expected output:
```
Assets.xcassets
SnapKeiApp.swift
```

---

## Task 0.2: Configure deployment target (18.5) + Swift version (6.0)

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei.xcodeproj/project.pbxproj`

- [ ] **Step 1: Patch deployment target**

Run:
```bash
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.5;/IPHONEOS_DEPLOYMENT_TARGET = 18.5;/g' \
  /Users/lee/workspace/SnapKei/SnapKei.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Patch Swift version**

Run:
```bash
sed -i '' 's/SWIFT_VERSION = 5.0;/SWIFT_VERSION = 6.0;/g' \
  /Users/lee/workspace/SnapKei/SnapKei.xcodeproj/project.pbxproj
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -E "(IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION)" \
  /Users/lee/workspace/SnapKei/SnapKei.xcodeproj/project.pbxproj | sort -u
```
Expected:
```
				IPHONEOS_DEPLOYMENT_TARGET = 18.5;
				SWIFT_VERSION = 6.0;
```

- [ ] **Step 4: Build sanity-check**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED`. If it fails because iPhone 17 Pro simulator missing, replace with any available iOS 18.5+ simulator name (`xcrun simctl list devices available | head`).

---

## Task 0.3: Create directory structure + move SnapKeiApp.swift

**Files:**
- Move: `/Users/lee/workspace/SnapKei/SnapKei/SnapKeiApp.swift` → `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`
- Create: empty directory tree under `/Users/lee/workspace/SnapKei/SnapKei/`

- [ ] **Step 1: Create directories**

Run:
```bash
cd /Users/lee/workspace/SnapKei/SnapKei && \
mkdir -p App Domain/Entities Domain/Services \
         Data/Persistence Data/Settings Data/Seed \
         Presentation Resources
```

- [ ] **Step 2: Move SnapKeiApp.swift**

Run:
```bash
mv /Users/lee/workspace/SnapKei/SnapKei/SnapKeiApp.swift \
   /Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift
```

- [ ] **Step 3: Verify**

Run:
```bash
find /Users/lee/workspace/SnapKei/SnapKei -type d | sort
```
Expected:
```
/Users/lee/workspace/SnapKei/SnapKei
/Users/lee/workspace/SnapKei/SnapKei/App
/Users/lee/workspace/SnapKei/SnapKei/Assets.xcassets
... (Assets subdirs)
/Users/lee/workspace/SnapKei/SnapKei/Data
/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence
/Users/lee/workspace/SnapKei/SnapKei/Data/Seed
/Users/lee/workspace/SnapKei/SnapKei/Data/Settings
/Users/lee/workspace/SnapKei/SnapKei/Domain
/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities
/Users/lee/workspace/SnapKei/SnapKei/Domain/Services
/Users/lee/workspace/SnapKei/SnapKei/Presentation
/Users/lee/workspace/SnapKei/SnapKei/Resources
```

---

## Task 0.4: Create Secrets.xcconfig

**Files:**
- Create: `/Users/lee/workspace/SnapKei/Secrets.xcconfig`

- [ ] **Step 1: Write Secrets.xcconfig**

Write to `/Users/lee/workspace/SnapKei/Secrets.xcconfig`:
```
// SnapKei Secrets / Build Settings
// PROXY_BASE_URL is used by AIProxyService (Plan 2).
// In xcconfig, the '//' inside URLs must be escaped as '/$()/' to avoid the parser treating it as a comment.

PROXY_BASE_URL = https:/$()/snapkei-ai.example.com
```

- [ ] **Step 2: Verify file**

Run:
```bash
cat /Users/lee/workspace/SnapKei/Secrets.xcconfig
```
Expected: see the contents above.

> **Note:** Linking the xcconfig into the Xcode project's build configurations is done in Plan 2 when AIProxyService consumes it. Plan 1 only creates the file.

---

## Task 0.5: Create empty Localizable.xcstrings (zh + ja)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Resources/Localizable.xcstrings`

- [ ] **Step 1: Write Localizable.xcstrings**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Resources/Localizable.xcstrings`:
```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "snapkei.app.placeholder.welcome" : {
      "localizations" : {
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "SnapKei へようこそ"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "欢迎使用 SnapKei"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 2: Verify JSON**

Run:
```bash
python3 -c "import json; json.load(open('/Users/lee/workspace/SnapKei/SnapKei/Resources/Localizable.xcstrings'))" && echo "valid"
```
Expected: `valid`

---

## Task 0.6: Add Unit Test Target (automated first, Xcode UI fallback)

> **Agentic workers:** first try to create `SnapKeiTests` programmatically in the Xcode project. If the project edit is not reliable, pause here and surface the Xcode UI fallback to the user.

- [ ] **Step 1: Create or verify `SnapKeiTests` target**

Preferred automated outcome:
- `xcodebuild -list -project /Users/lee/workspace/SnapKei/SnapKei.xcodeproj` shows both `SnapKei` and `SnapKeiTests`.
- `/Users/lee/workspace/SnapKei/SnapKeiTests/` exists.
- The test target uses Swift Testing and targets `SnapKei`.

If automation is not feasible, use the manual fallback:

User instructions:
1. Open `/Users/lee/workspace/SnapKei/SnapKei.xcodeproj` in Xcode
2. Menu: **File → New → Target...**
3. Select **iOS → Test → Unit Testing Bundle**, click **Next**
4. Product Name: **`SnapKeiTests`**
5. Testing System: **`Swift Testing`** (not XCTest)
6. Target to be Tested: **SnapKei**
7. Click **Finish** (if prompted to activate scheme, click **Activate**)
8. In the new `SnapKeiTests/SnapKeiTests.swift` file Xcode generates, leave it as-is for now
9. Verify the SnapKeiTests folder exists on disk:

- [ ] **Step 2: Agent verifies**

Run:
```bash
ls /Users/lee/workspace/SnapKei/SnapKeiTests/
```
Expected: at minimum `SnapKeiTests.swift` is present. If the directory does not exist, the user has not completed Step 1 — stop and ask.

- [ ] **Step 3: Build + run the empty test target**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED` with 1 trivial test passing (Xcode's auto-generated example). If swift-testing example is not present, that's OK — the goal is just confirming the test target exists and compiles.

---

## Task 0.7: Placeholder RootView + wire into SnapKeiApp

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/RootView.swift`
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`

- [ ] **Step 1: Write RootView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "ホーム", systemImage: "house")
                .tabItem { Label("ホーム", systemImage: "house") }

            PlaceholderTab(title: "撮影", systemImage: "camera")
                .tabItem { Label("撮影", systemImage: "camera") }

            PlaceholderTab(title: "一覧", systemImage: "list.bullet.rectangle")
                .tabItem { Label("一覧", systemImage: "list.bullet.rectangle") }

            PlaceholderTab(title: "設定", systemImage: "gearshape")
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .font(.largeTitle)
            Text(title).font(.title2)
            Text("Plan 1 placeholder").foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 2: Update SnapKeiApp.swift (no ModelContainer yet — added in Task 1.13b)**

Rewrite `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`:
```swift
import SwiftUI

@main
struct SnapKeiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

> **Why no `.modelContainer` here?** `SnapKeiModelContainer.shared` doesn't exist until Task 1.13. Phase 0 must build green on its own — we wire the container in Task 1.13b.

- [ ] **Step 3: Build Phase 0 to confirm green**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`.

---

## Task 0.8: Phase 0 commit checkpoint

- [ ] **Step 1: Stage Phase 0 changes**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei.xcodeproj/project.pbxproj \
        Secrets.xcconfig \
        SnapKei/ \
        SnapKeiTests/
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git commit -m "$(cat <<'EOF'
feat: scaffold Phase 0 — Clean Architecture directories, target 18.5/Swift 6

- Set IPHONEOS_DEPLOYMENT_TARGET = 18.5, SWIFT_VERSION = 6.0
- Reorganize into App/Domain/Data/Presentation/Resources
- Create Secrets.xcconfig (PROXY_BASE_URL placeholder)
- Initialize Localizable.xcstrings with zh-Hans + ja
- Add SnapKeiTests target (Swift Testing)
- Placeholder RootView with 4-tab skeleton

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Do NOT push to remote**

(User preference. Skip any `git push`.)

---

# Phase 1: Data + Compliance Layer

## Task 1.1: Domain/Entities/Enums.swift — all 9 enums in one file

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/Enums.swift`

- [ ] **Step 1: Write Enums.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/Enums.swift`:
```swift
import Foundation

// MARK: - 税

public enum TaxCategory: String, Codable, Sendable, CaseIterable {
    case standard10
    case reduced8
    case nonTaxable
    case outOfScope
}

public enum PriceEntryMode: String, Codable, Sendable, CaseIterable {
    case taxIncluded
    case taxExcluded
}

// MARK: - 仕訳

public enum PaymentMethod: String, Codable, Sendable, CaseIterable {
    case cash
    case creditCard
    case bankTransfer
    case ownerLoan          // 事業主借
    case ownerWithdraw      // 事業主貸
    case accountsPayable    // 未払金
    case other
}

public enum RecordSource: String, Codable, Sendable, CaseIterable {
    case aiParsed
    case electronicTransaction
    case manual
    case imported
    case depreciation
}

// MARK: - 勘定科目

public enum AccountType: String, Codable, Sendable, CaseIterable {
    case asset
    case liability
    case equity
    case revenue
    case expense
}

// MARK: - 固定資産

public enum AssetTreatment: String, Codable, Sendable, CaseIterable {
    case normalDepreciation       // 通常減価償却
    case lumpSumDepreciation      // 一括償却（20万円未満、3年均等）
    case smallAmountFullExpense   // 少額減価償却特例（青色限定）
}

public enum DepreciationMethod: String, Codable, Sendable, CaseIterable {
    case straightLine    // 定額法
    case decliningBalance // 定率法
}

// MARK: - AI

public enum AIChannel: String, Codable, Sendable, CaseIterable {
    case directApiKey
    case builtInProxy
}

public enum APIFormat: String, Codable, Sendable, CaseIterable {
    case openAI
    case anthropic
}
```

---

## Task 1.2: Enums tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/EnumsTests.swift`

- [ ] **Step 1: Write EnumsTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/EnumsTests.swift`:
```swift
import Testing
@testable import SnapKei

@Suite("Enums raw values are stable (persistence keys)")
struct EnumsTests {

    @Test func taxCategoryRawValues() {
        #expect(TaxCategory.standard10.rawValue == "standard10")
        #expect(TaxCategory.reduced8.rawValue == "reduced8")
        #expect(TaxCategory.nonTaxable.rawValue == "nonTaxable")
        #expect(TaxCategory.outOfScope.rawValue == "outOfScope")
    }

    @Test func paymentMethodRawValues() {
        #expect(PaymentMethod.cash.rawValue == "cash")
        #expect(PaymentMethod.ownerLoan.rawValue == "ownerLoan")
        #expect(PaymentMethod.ownerWithdraw.rawValue == "ownerWithdraw")
        #expect(PaymentMethod.accountsPayable.rawValue == "accountsPayable")
    }

    @Test func recordSourceRawValues() {
        #expect(RecordSource.aiParsed.rawValue == "aiParsed")
        #expect(RecordSource.electronicTransaction.rawValue == "electronicTransaction")
        #expect(RecordSource.depreciation.rawValue == "depreciation")
    }

    @Test func assetTreatmentRawValues() {
        #expect(AssetTreatment.normalDepreciation.rawValue == "normalDepreciation")
        #expect(AssetTreatment.lumpSumDepreciation.rawValue == "lumpSumDepreciation")
        #expect(AssetTreatment.smallAmountFullExpense.rawValue == "smallAmountFullExpense")
    }

    @Test func depreciationMethodRawValues() {
        #expect(DepreciationMethod.straightLine.rawValue == "straightLine")
        #expect(DepreciationMethod.decliningBalance.rawValue == "decliningBalance")
    }

    @Test func aiChannelRawValues() {
        #expect(AIChannel.directApiKey.rawValue == "directApiKey")
        #expect(AIChannel.builtInProxy.rawValue == "builtInProxy")
    }

    @Test func apiFormatRawValues() {
        #expect(APIFormat.openAI.rawValue == "openAI")
        #expect(APIFormat.anthropic.rawValue == "anthropic")
    }

    @Test func accountTypeRawValues() {
        #expect(AccountType.asset.rawValue == "asset")
        #expect(AccountType.expense.rawValue == "expense")
    }
}
```

> **Why test raw values?** Raw strings are persistence keys (stored in SwiftData / JSON). Renaming a case must be an intentional decision visible in a diff.

---

## Task 1.3: Account @Model

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/Account.swift`

- [ ] **Step 1: Write Account.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/Account.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class Account {
    /// 4 桁の勘定科目コード（例 "5110" = 通信費）。Primary key.
    @Attribute(.unique) public var code: String

    public var nameJa: String
    public var nameZh: String

    /// raw value of AccountType
    public var accountTypeRaw: String

    public var isBuiltin: Bool
    public var isActive: Bool

    /// 0.0–1.0、新仕訳作成時のデフォルト事業按分率（家事按分）。
    public var defaultBusinessAllocationRate: Double

    public init(
        code: String,
        nameJa: String,
        nameZh: String,
        accountType: AccountType,
        isBuiltin: Bool = true,
        isActive: Bool = true,
        defaultBusinessAllocationRate: Double = 1.0
    ) {
        self.code = code
        self.nameJa = nameJa
        self.nameZh = nameZh
        self.accountTypeRaw = accountType.rawValue
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.defaultBusinessAllocationRate = defaultBusinessAllocationRate
    }

    public var accountType: AccountType {
        AccountType(rawValue: accountTypeRaw) ?? .expense
    }
}
```

> **Why store raw String for enum?** SwiftData enum support is workable but raw String is the lowest-friction approach across Swift versions / schema migrations.

---

## Task 1.4: AssetUsefulLife @Model

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/AssetUsefulLife.swift`

- [ ] **Step 1: Write AssetUsefulLife.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/AssetUsefulLife.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class AssetUsefulLife {
    /// 識別子（例 "PC", "SOFTWARE_INTERNAL"）
    @Attribute(.unique) public var code: String

    public var nameJa: String
    public var nameZh: String
    public var years: Int
    public var isBuiltin: Bool

    public init(
        code: String,
        nameJa: String,
        nameZh: String,
        years: Int,
        isBuiltin: Bool = true
    ) {
        self.code = code
        self.nameJa = nameJa
        self.nameZh = nameZh
        self.years = years
        self.isBuiltin = isBuiltin
    }
}
```

---

## Task 1.5: JournalEntry @Model

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/JournalEntry.swift`

- [ ] **Step 1: Write JournalEntry.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/JournalEntry.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class JournalEntry {
    @Attribute(.unique) public var id: UUID
    public var entryNumber: Int
    public var fiscalYear: Int
    public var transactionDate: Date
    public var inputDate: Date
    public var isLateEntry: Bool

    public var debitAccountCode: String
    public var creditAccountCode: String

    public var amountIncludingTax: Int
    public var amountExcludingTax: Int
    public var consumptionTax: Int

    public var taxCategoryRaw: String
    public var priceEntryModeRaw: String
    public var paymentMethodRaw: String

    public var counterpartyName: String
    public var invoiceRegistrationNumber: String?
    public var invoiceQualified: Bool
    public var transitionalMeasureRate: Double

    public var transactionDescription: String
    public var memo: String?

    public var businessAllocationRate: Double
    public var originalAmountIncludingTax: Int?
    public var relatedFixedAssetId: UUID?

    public var receiptImagePath: String?
    public var receiptImageHash: String?

    public var sourceTypeRaw: String

    public var createdAt: Date
    public var updatedAt: Date

    public var syncId: UUID
    public var isVoided: Bool

    public init(
        id: UUID = UUID(),
        entryNumber: Int,
        fiscalYear: Int,
        transactionDate: Date,
        inputDate: Date = Date(),
        isLateEntry: Bool = false,
        debitAccountCode: String,
        creditAccountCode: String,
        amountIncludingTax: Int,
        amountExcludingTax: Int,
        consumptionTax: Int,
        taxCategory: TaxCategory,
        priceEntryMode: PriceEntryMode,
        paymentMethod: PaymentMethod,
        counterpartyName: String,
        invoiceRegistrationNumber: String? = nil,
        invoiceQualified: Bool = false,
        transitionalMeasureRate: Double = 1.0,
        transactionDescription: String,
        memo: String? = nil,
        businessAllocationRate: Double = 1.0,
        originalAmountIncludingTax: Int? = nil,
        relatedFixedAssetId: UUID? = nil,
        receiptImagePath: String? = nil,
        receiptImageHash: String? = nil,
        sourceType: RecordSource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncId: UUID = UUID(),
        isVoided: Bool = false
    ) {
        self.id = id
        self.entryNumber = entryNumber
        self.fiscalYear = fiscalYear
        self.transactionDate = transactionDate
        self.inputDate = inputDate
        self.isLateEntry = isLateEntry
        self.debitAccountCode = debitAccountCode
        self.creditAccountCode = creditAccountCode
        self.amountIncludingTax = amountIncludingTax
        self.amountExcludingTax = amountExcludingTax
        self.consumptionTax = consumptionTax
        self.taxCategoryRaw = taxCategory.rawValue
        self.priceEntryModeRaw = priceEntryMode.rawValue
        self.paymentMethodRaw = paymentMethod.rawValue
        self.counterpartyName = counterpartyName
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceQualified = invoiceQualified
        self.transitionalMeasureRate = transitionalMeasureRate
        self.transactionDescription = transactionDescription
        self.memo = memo
        self.businessAllocationRate = businessAllocationRate
        self.originalAmountIncludingTax = originalAmountIncludingTax
        self.relatedFixedAssetId = relatedFixedAssetId
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.sourceTypeRaw = sourceType.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncId = syncId
        self.isVoided = isVoided
    }

    public var taxCategory: TaxCategory { TaxCategory(rawValue: taxCategoryRaw) ?? .standard10 }
    public var priceEntryMode: PriceEntryMode { PriceEntryMode(rawValue: priceEntryModeRaw) ?? .taxIncluded }
    public var paymentMethod: PaymentMethod { PaymentMethod(rawValue: paymentMethodRaw) ?? .other }
    public var sourceType: RecordSource { RecordSource(rawValue: sourceTypeRaw) ?? .manual }
}
```

---

## Task 1.6: SystemActivityLog @Model

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/SystemActivityLog.swift`

> **法定対応**：優良電子帳簿要件①「訂正・削除履歴の確保」を承載。**通常業務処理期間（約 2 ヶ月）経過後の入力履歴**もこの要件①に含まれるため、`JournalEntry.isLateEntry=true` のエントリ作成時もここに記録する。

- [ ] **Step 1: Write SystemActivityLog.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/SystemActivityLog.swift`:
```swift
import Foundation
import SwiftData

public enum ActivityType: String, Codable, Sendable, CaseIterable {
    case createEntry
    case editEntry
    case voidEntry
    case unlockPeriod
    case fiscalYearTransition
    case aiParsing
}

@Model
public final class SystemActivityLog {
    @Attribute(.unique) public var id: UUID
    public var occurredAt: Date
    public var actorDeviceId: String
    public var activityTypeRaw: String
    public var targetEntryId: UUID?

    /// JSON snapshot of JournalEntry before the change. nil for createEntry.
    public var beforeSnapshot: Data?
    /// JSON snapshot after the change. nil for voidEntry where nothing meaningful follows.
    public var afterSnapshot: Data?
    public var reason: String?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        actorDeviceId: String,
        activityType: ActivityType,
        targetEntryId: UUID? = nil,
        beforeSnapshot: Data? = nil,
        afterSnapshot: Data? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.actorDeviceId = actorDeviceId
        self.activityTypeRaw = activityType.rawValue
        self.targetEntryId = targetEntryId
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
        self.reason = reason
    }

    public var activityType: ActivityType {
        ActivityType(rawValue: activityTypeRaw) ?? .editEntry
    }
}
```

---

## Task 1.7: FixedAsset @Model

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/FixedAsset.swift`

- [ ] **Step 1: Write FixedAsset.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Entities/FixedAsset.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class FixedAsset {
    @Attribute(.unique) public var id: UUID
    public var assetName: String
    public var assetCategoryCode: String   // FK → AssetUsefulLife.code
    public var acquisitionDate: Date
    public var serviceStartDate: Date
    public var acquisitionAmount: Int
    public var usefulLifeYears: Int
    public var depreciationMethodRaw: String
    public var treatmentRaw: String
    public var businessAllocationRate: Double

    public var acquisitionJournalEntryId: UUID?
    public var accumulatedDepreciation: Int
    public var bookValue: Int
    public var disposalDate: Date?
    public var disposalAmount: Int?
    public var syncId: UUID

    public init(
        id: UUID = UUID(),
        assetName: String,
        assetCategoryCode: String,
        acquisitionDate: Date,
        serviceStartDate: Date,
        acquisitionAmount: Int,
        usefulLifeYears: Int,
        depreciationMethod: DepreciationMethod = .straightLine,
        treatment: AssetTreatment,
        businessAllocationRate: Double = 1.0,
        acquisitionJournalEntryId: UUID? = nil,
        accumulatedDepreciation: Int = 0,
        bookValue: Int? = nil,
        disposalDate: Date? = nil,
        disposalAmount: Int? = nil,
        syncId: UUID = UUID()
    ) {
        self.id = id
        self.assetName = assetName
        self.assetCategoryCode = assetCategoryCode
        self.acquisitionDate = acquisitionDate
        self.serviceStartDate = serviceStartDate
        self.acquisitionAmount = acquisitionAmount
        self.usefulLifeYears = usefulLifeYears
        self.depreciationMethodRaw = depreciationMethod.rawValue
        self.treatmentRaw = treatment.rawValue
        self.businessAllocationRate = businessAllocationRate
        self.acquisitionJournalEntryId = acquisitionJournalEntryId
        self.accumulatedDepreciation = accumulatedDepreciation
        self.bookValue = bookValue ?? acquisitionAmount
        self.disposalDate = disposalDate
        self.disposalAmount = disposalAmount
        self.syncId = syncId
    }

    public var depreciationMethod: DepreciationMethod {
        DepreciationMethod(rawValue: depreciationMethodRaw) ?? .straightLine
    }
    public var treatment: AssetTreatment {
        AssetTreatment(rawValue: treatmentRaw) ?? .normalDepreciation
    }
}
```

---

## Task 1.8: ComplianceConstants.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ComplianceConstants.swift`

- [ ] **Step 1: Write ComplianceConstants.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ComplianceConstants.swift`:
```swift
import Foundation

/// 法定 / 制度由来の閾値・スケジュールを 1 箇所に集約。
/// 改正があればここを書き換える。
public enum ComplianceConstants {

    // MARK: - 少額減価償却資産特例（青色限定、常時使用従業員 400 人以下）

    /// 2026.4.1 以降取得分は 40万円未満（それ以前は 30万円未満）。
    /// MVP では 2026.4 以降のみ想定するため一律 400_000 を採用。
    public static let smallDepreciableAssetThreshold = 400_000

    /// 年間 300万円上限。
    public static let smallDepreciableAnnualCap = 3_000_000

    /// 適用期限：令和11年3月31日（= 令和10年度末）。
    /// 改正前は令和8年3月31日だったが、令和8年度改正で 3 年延長。
    public static let smallDepreciableExpiry = parseISO("2029-03-31")

    // MARK: - 一括償却資産（3 年均等償却）

    public static let lumpSumDepreciationThreshold = 200_000

    // MARK: - スキャナ保存

    public static let scanDeadlineMonths = 2
    public static let scanDeadlineExtraBusinessDays = 7

    // MARK: - 入力期限（"通常業務以外" 判定）

    /// 標準の "late entry" 閾値日数。AppSettings から上書き可能。
    public static let defaultLateEntryThresholdDays = 14

    // MARK: - インボイス制度 経過措置（令和8年度改正後、5段階）

    /// (until: 適用末日, rate: 仕入税額控除割合)
    public static let transitionalRateSchedule: [(until: Date, rate: Double)] = [
        (parseISO("2026-09-30"), 0.80),
        (parseISO("2028-09-30"), 0.70),
        (parseISO("2030-09-30"), 0.50),
        (parseISO("2031-09-30"), 0.30),
    ]
    /// 上記スケジュールの全期間経過後の控除割合。
    public static let transitionalRateAfterAll: Double = 0.00

    // MARK: - 解像度（スキャナ保存要件）

    /// 200dpi 相当（A4 で約 387 万画素）。
    public static let minResolutionPixels = 3_870_000

    // MARK: - 内部ヘルパ

    private static func parseISO(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!  // crash-on-misconfig is fine; 静的定数
    }
}
```

---

## Task 1.9: ComplianceService.swift — public surface

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ComplianceService.swift`

- [ ] **Step 1: Write ComplianceService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ComplianceService.swift`:
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum ComplianceService {

    /// スキャナ保存「入力期限」までの残日数（≒ 受領日 + 2ヶ月 + 7 営業日 − 今日）。
    /// 営業日換算は土日のみスキップ（祝日は MVP では考慮しない）。
    /// マイナスは期限切れを示す。
    public static func daysUntilScanDeadline(receiptDate: Date, today: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let twoMonthsLater = cal.date(byAdding: .month, value: ComplianceConstants.scanDeadlineMonths, to: receiptDate)!
        let deadline = addBusinessDays(twoMonthsLater, days: ComplianceConstants.scanDeadlineExtraBusinessDays, calendar: cal)

        let todayStart = cal.startOfDay(for: today)
        let deadlineStart = cal.startOfDay(for: deadline)
        let comps = cal.dateComponents([.day], from: todayStart, to: deadlineStart)
        return comps.day ?? 0
    }

    /// 「通常業務処理期間経過後の入力」判定（優良電子帳簿要件①「訂正・削除履歴の確保」に内包される）。
    public static func isLateEntry(transactionDate: Date, inputDate: Date, thresholdDays: Int = ComplianceConstants.defaultLateEntryThresholdDays) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: transactionDate), to: cal.startOfDay(for: inputDate))
        let diff = comps.day ?? 0
        return diff > thresholdDays
    }

    /// 解像度チェック（スキャナ保存要件: A4 200dpi ≒ 約 387 万画素）。
    #if canImport(UIKit)
    public static func validateImageResolution(_ image: UIImage) -> Bool {
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return pixels >= ComplianceConstants.minResolutionPixels
    }
    #endif

    /// インボイス経過措置率算出。
    /// - 適格事業者なら 1.0（全額控除）
    /// - 不適格なら取引日に応じて 0.80 / 0.70 / 0.50 / 0.30 / 0.00 を返す（5 段階）
    public static func transitionalRate(qualified: Bool, transactionDate: Date) -> Double {
        if qualified { return 1.0 }
        for entry in ComplianceConstants.transitionalRateSchedule {
            if transactionDate <= entry.until { return entry.rate }
        }
        return ComplianceConstants.transitionalRateAfterAll
    }

    /// 取得金額・取得日から固定資産 treatment の推奨値を返す。
    /// nil は「即時経費（通常仕訳のみ、FixedAsset 不要）」を意味する。
    ///
    /// **前提**：個人事業主・常時使用従業員 400 人以下を仮定（令和8年度改正後、少額減価償却特例の対象法人要件）。
    /// 法人や大規模事業者の判定にはこのメソッドを使用しない。
    public static func suggestAssetTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        // < 10 万円 → FixedAsset 不要、通常経費
        if amount < 100_000 { return nil }

        // 10 万 ≤ x < 20 万 → 一括償却資産（3 年均等）
        if amount < ComplianceConstants.lumpSumDepreciationThreshold {
            return .lumpSumDepreciation
        }

        // 20 万 ≤ x < 40 万、かつ 2029-03-31 までの取得 → 少額減価償却特例
        if amount < ComplianceConstants.smallDepreciableAssetThreshold,
           acquisitionDate <= ComplianceConstants.smallDepreciableExpiry {
            return .smallAmountFullExpense
        }

        // ≥ 40 万円、または特例期限切れ → 通常減価償却
        return .normalDepreciation
    }

    // MARK: - 内部

    /// 営業日（土日のみスキップ、祝日非対応）を足す。
    private static func addBusinessDays(_ date: Date, days: Int, calendar: Calendar) -> Date {
        var current = date
        var remaining = days
        while remaining > 0 {
            current = calendar.date(byAdding: .day, value: 1, to: current)!
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 { // 1=Sun, 7=Sat
                remaining -= 1
            }
        }
        return current
    }
}
```

---

## Task 1.10: ComplianceService tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/ComplianceServiceTests.swift`

- [ ] **Step 1: Write ComplianceServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/ComplianceServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("ComplianceService")
struct ComplianceServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    // MARK: - 経過措置 5 段階

    @Test func transitionalRate_qualifiedAlwaysFull() {
        for ds in ["2026-01-01", "2026-10-01", "2030-01-01", "2032-01-01"] {
            #expect(ComplianceService.transitionalRate(qualified: true, transactionDate: date(ds)) == 1.0)
        }
    }

    @Test func transitionalRate_unqualified_2026_09_30_boundary_isStillEightyPercent() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2026-09-30")) == 0.80)
    }

    @Test func transitionalRate_unqualified_2026_10_01_drops_to_70() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2026-10-01")) == 0.70)
    }

    @Test func transitionalRate_unqualified_2028_10_01_drops_to_50() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2028-10-01")) == 0.50)
    }

    @Test func transitionalRate_unqualified_2030_10_01_drops_to_30() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2030-10-01")) == 0.30)
    }

    @Test func transitionalRate_unqualified_2031_10_01_drops_to_zero() {
        #expect(ComplianceService.transitionalRate(qualified: false, transactionDate: date("2031-10-01")) == 0.0)
    }

    // MARK: - スキャナ保存期限

    @Test func daysUntilScanDeadline_today_returns_positive() {
        let today = date("2026-05-16")
        let result = ComplianceService.daysUntilScanDeadline(receiptDate: today, today: today)
        // 2 ヶ月 + 約 7 営業日 ≒ 70 日強
        #expect(result > 60 && result < 80)
    }

    @Test func daysUntilScanDeadline_threeMonthsAgo_returns_negative() {
        let receipt = date("2026-02-16")
        let today   = date("2026-05-16")
        #expect(ComplianceService.daysUntilScanDeadline(receiptDate: receipt, today: today) < 0)
    }

    // MARK: - late entry

    @Test func isLateEntry_within_threshold_false() {
        let tx    = date("2026-05-01")
        let input = date("2026-05-10")
        #expect(!ComplianceService.isLateEntry(transactionDate: tx, inputDate: input))
    }

    @Test func isLateEntry_beyond_threshold_true() {
        let tx    = date("2026-04-01")
        let input = date("2026-05-01")
        #expect(ComplianceService.isLateEntry(transactionDate: tx, inputDate: input))
    }

    // MARK: - asset treatment 提案

    @Test func suggestAssetTreatment_under100k_isNil() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 99_999, acquisitionDate: date("2026-05-16")) == nil)
    }

    @Test func suggestAssetTreatment_150k_is_lumpSum() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 150_000, acquisitionDate: date("2026-05-16")) == .lumpSumDepreciation)
    }

    @Test func suggestAssetTreatment_280k_within_expiry_is_smallAmount() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 280_000, acquisitionDate: date("2026-05-16")) == .smallAmountFullExpense)
    }

    @Test func suggestAssetTreatment_280k_after_expiry_is_normal() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 280_000, acquisitionDate: date("2029-04-01")) == .normalDepreciation)
    }

    @Test func suggestAssetTreatment_500k_is_normal() {
        #expect(ComplianceService.suggestAssetTreatment(amount: 500_000, acquisitionDate: date("2026-05-16")) == .normalDepreciation)
    }

    @Test func suggestAssetTreatment_400k_boundary_is_normal() {
        // 40 万円「未満」が特例 → 40 万円ジャストは normal
        #expect(ComplianceService.suggestAssetTreatment(amount: 400_000, acquisitionDate: date("2026-05-16")) == .normalDepreciation)
    }
}
```

---

## Task 1.11: DepreciationService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/DepreciationService.swift`

- [ ] **Step 1: Write DepreciationService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/DepreciationService.swift`:
```swift
import Foundation

public enum DepreciationService {

    /// 単資産の単年度償却額を返す（取得年は月割、それ以降は満額）。
    /// - Parameters:
    ///   - asset: 対象資産
    ///   - fiscalYear: 計算対象の事業年度（西暦）
    /// - Returns: 償却額（円、按分後）
    public static func annualDepreciation(for asset: FixedAsset, fiscalYear: Int) -> Int {
        // 取得年より前 → 0
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        if fiscalYear < acquisitionYear { return 0 }

        // すでに完全償却済 → 0
        if asset.accumulatedDepreciation >= asset.acquisitionAmount { return 0 }

        switch asset.treatment {
        case .smallAmountFullExpense:
            // 取得時に全額費用化済（仕訳でカバー）→ ここでは追加償却なし
            return 0

        case .lumpSumDepreciation:
            // 一括償却資産は取得価額の 1/3 × 3 年（按分後）。月割は不要（個人事業主・年単位）。
            let baseAmount = Double(asset.acquisitionAmount) / 3.0
            let allocated = baseAmount * asset.businessAllocationRate
            return Int(allocated.rounded(.down))

        case .normalDepreciation:
            switch asset.depreciationMethod {
            case .straightLine:
                return straightLineAnnual(asset: asset, fiscalYear: fiscalYear, calendar: calendar)
            case .decliningBalance:
                // MVP では定額法のみサポート。定率法は v2。落ちないよう定額法にフォールバック。
                return straightLineAnnual(asset: asset, fiscalYear: fiscalYear, calendar: calendar)
            }
        }
    }

    /// 取得金額閾値と取得日から treatment 推奨を返す（ComplianceService の薄いラッパ）。
    public static func suggestTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate)
    }

    // MARK: - 内部

    private static func straightLineAnnual(asset: FixedAsset, fiscalYear: Int, calendar: Calendar) -> Int {
        let baseAnnual = Double(asset.acquisitionAmount) / Double(asset.usefulLifeYears)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        let acquisitionMonth = calendar.component(.month, from: asset.serviceStartDate)

        var amount: Double
        if fiscalYear == acquisitionYear {
            // 月割（取得月含む）
            let monthsInUse = max(0, 13 - acquisitionMonth)
            amount = baseAnnual * Double(monthsInUse) / 12.0
        } else {
            amount = baseAnnual
        }

        // 簿価 < 償却額 の場合は簿価まで
        let remaining = asset.acquisitionAmount - asset.accumulatedDepreciation
        amount = min(amount, Double(remaining))

        // 事業按分後
        let allocated = amount * asset.businessAllocationRate
        return Int(allocated.rounded(.down))
    }
}
```

---

## Task 1.12: DepreciationService tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/DepreciationServiceTests.swift`

- [ ] **Step 1: Write DepreciationServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/DepreciationServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("DepreciationService")
struct DepreciationServiceTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    // MARK: - 定額法 取得年度（月割）

    @Test func straightLine_acquisitionYear_monthlyProrated() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        // 年額 = 480000 / 4 = 120000
        // 取得月 7 月、使用月数 = 13 − 7 = 6 ヶ月
        // 120000 * 6/12 = 60000、按分 1.0
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 60_000)
    }

    @Test func straightLine_followingYear_fullAmount() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2027) == 120_000)
    }

    @Test func straightLine_yearBeforeAcquisition_isZero() {
        let asset = FixedAsset(
            assetName: "MacBook Pro M5",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 480_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2025) == 0)
    }

    @Test func straightLine_withBusinessAllocation_50pct() {
        // 年額 = 240_000 / 5 = 48_000
        // 取得月 = 1 → 使用月数 = 13 - 1 = 12 ヶ月 → 48_000 × 12/12 = 48_000
        // 事業按分 0.5 → 24_000
        let asset = FixedAsset(
            assetName: "在宅事務所モニター",
            assetCategoryCode: "OTHER",
            acquisitionDate: date("2026-01-01"),
            serviceStartDate: date("2026-01-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 5,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.5
        )
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 24_000)
    }

    // MARK: - 一括償却資産

    @Test func lumpSum_third_of_amount() {
        let asset = FixedAsset(
            assetName: "事務机",
            assetCategoryCode: "FURNITURE",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 150_000,
            usefulLifeYears: 8,  // master 値、実際の償却計算には使われない
            treatment: .lumpSumDepreciation
        )
        // 150000 / 3 = 50000
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 50_000)
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2027) == 50_000)
    }

    // MARK: - 少額減価償却特例

    @Test func smallAmount_alreadyExpensed_returnsZero() {
        let asset = FixedAsset(
            assetName: "カメラ",
            assetCategoryCode: "CAMERA",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 280_000,
            usefulLifeYears: 5,
            treatment: .smallAmountFullExpense
        )
        // 取得時に費用化済 → 期末償却 0
        #expect(DepreciationService.annualDepreciation(for: asset, fiscalYear: 2026) == 0)
    }
}
```

> **Note on the duplicated test name:** Task 1.12 includes two test functions on the same asset (`straightLine_withBusinessAllocation_50pct` and `_resultIs24000`) to make the inline comment correction explicit. Delete the first one before committing if you prefer — both yield the same answer 24000. (The doc-style comment in the first one helps reviewers see the math.)

---

## Task 1.13a: ModelContainer+SnapKei.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ModelContainer+SnapKei.swift`

- [ ] **Step 1: Write ModelContainer+SnapKei.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ModelContainer+SnapKei.swift`:
```swift
import Foundation
import SwiftData

public enum SnapKeiModelContainer {

    /// アプリ全体で共有する本番用 ModelContainer。Crash on misconfig is intentional.
    public static let shared: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration("SnapKei.sqlite")
            )
            // 初回起動時に master データを seed
            Task { @MainActor in
                AccountSeeder.seedIfNeeded(context: container.mainContext)
                AssetUsefulLifeSeeder.seedIfNeeded(context: container.mainContext)
            }
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// テスト用 in-memory コンテナ。
    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let schema = Schema([
        Account.self,
        AssetUsefulLife.self,
        JournalEntry.self,
        SystemActivityLog.self,
        FixedAsset.self
    ])
}
```

---

## Task 1.13b: Wire ModelContainer into SnapKeiApp

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`

- [ ] **Step 1: Add modelContainer modifier**

Rewrite `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`:
```swift
import SwiftUI
import SwiftData

@main
struct SnapKeiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(SnapKeiModelContainer.shared)
    }
}
```

> **Note:** the seeders are referenced inside `SnapKeiModelContainer.shared` but their types (`AccountSeeder`, `AssetUsefulLifeSeeder`) are created in Tasks 1.16 and 1.17. Build at this point is expected to fail; it'll go green again after Task 1.17.

---

## Task 1.14: accounts_seed.json (33 標準科目)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/accounts_seed.json`

- [ ] **Step 1: Write accounts_seed.json**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/accounts_seed.json`:
```json
[
  { "code": "1110", "nameJa": "現金",             "nameZh": "现金",           "accountType": "asset" },
  { "code": "1210", "nameJa": "普通預金",         "nameZh": "活期存款",       "accountType": "asset" },
  { "code": "1220", "nameJa": "当座預金",         "nameZh": "支票账户",       "accountType": "asset" },
  { "code": "1310", "nameJa": "売掛金",           "nameZh": "应收账款",       "accountType": "asset" },
  { "code": "1410", "nameJa": "棚卸資産",         "nameZh": "存货",           "accountType": "asset" },
  { "code": "1510", "nameJa": "前払金",           "nameZh": "预付款",         "accountType": "asset" },
  { "code": "1610", "nameJa": "工具器具備品",     "nameZh": "工具器具备品",   "accountType": "asset" },
  { "code": "1620", "nameJa": "車両運搬具",       "nameZh": "车辆运输工具",   "accountType": "asset" },
  { "code": "1710", "nameJa": "減価償却累計額",   "nameZh": "累计折旧",       "accountType": "asset" },

  { "code": "2210", "nameJa": "未払金",           "nameZh": "应付款",         "accountType": "liability" },
  { "code": "2220", "nameJa": "未払費用",         "nameZh": "应付费用",       "accountType": "liability" },
  { "code": "2310", "nameJa": "借入金",           "nameZh": "借款",           "accountType": "liability" },
  { "code": "2410", "nameJa": "預り金",           "nameZh": "代收款",         "accountType": "liability" },

  { "code": "3110", "nameJa": "元入金",           "nameZh": "投入资本",       "accountType": "equity" },
  { "code": "3210", "nameJa": "事業主借",         "nameZh": "业主借款",       "accountType": "equity" },
  { "code": "3220", "nameJa": "事業主貸",         "nameZh": "业主取款",       "accountType": "equity" },

  { "code": "4110", "nameJa": "売上高",           "nameZh": "销售收入",       "accountType": "revenue" },
  { "code": "4910", "nameJa": "雑収入",           "nameZh": "杂项收入",       "accountType": "revenue" },

  { "code": "5100", "nameJa": "旅費交通費",       "nameZh": "差旅交通费",     "accountType": "expense" },
  { "code": "5110", "nameJa": "通信費",           "nameZh": "通信费",         "accountType": "expense", "defaultBusinessAllocationRate": 0.7 },
  { "code": "5120", "nameJa": "接待交際費",       "nameZh": "招待交际费",     "accountType": "expense" },
  { "code": "5130", "nameJa": "会議費",           "nameZh": "会议费",         "accountType": "expense" },
  { "code": "5140", "nameJa": "消耗品費",         "nameZh": "消耗品费",       "accountType": "expense" },
  { "code": "5150", "nameJa": "事務用品費",       "nameZh": "办公用品费",     "accountType": "expense" },
  { "code": "5160", "nameJa": "新聞図書費",       "nameZh": "报刊图书费",     "accountType": "expense" },
  { "code": "5170", "nameJa": "水道光熱費",       "nameZh": "水电费",         "accountType": "expense", "defaultBusinessAllocationRate": 0.3 },
  { "code": "5180", "nameJa": "地代家賃",         "nameZh": "地租房租",       "accountType": "expense", "defaultBusinessAllocationRate": 0.3 },
  { "code": "5190", "nameJa": "外注工賃",         "nameZh": "外包工资",       "accountType": "expense" },
  { "code": "5200", "nameJa": "支払手数料",       "nameZh": "支付手续费",     "accountType": "expense" },
  { "code": "5210", "nameJa": "修繕費",           "nameZh": "修缮费",         "accountType": "expense" },
  { "code": "5220", "nameJa": "租税公課",         "nameZh": "税金公课",       "accountType": "expense" },
  { "code": "5230", "nameJa": "減価償却費",       "nameZh": "折旧费",         "accountType": "expense" },
  { "code": "5290", "nameJa": "雑費",             "nameZh": "杂费",           "accountType": "expense" }
]
```

> **Note:** 通信費 / 水道光熱費 / 地代家賃 に居宅事務所デフォルトの 70% / 30% / 30% を設定。これは個人事業主の標準的な按分例。Settings から後で変更可。

---

## Task 1.15: asset_useful_life_seed.json (7 種)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/asset_useful_life_seed.json`

- [ ] **Step 1: Write asset_useful_life_seed.json**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/asset_useful_life_seed.json`:
```json
[
  { "code": "PC",                "nameJa": "電子計算機（PC）",               "nameZh": "电脑（PC）",     "years": 4 },
  { "code": "SERVER",            "nameJa": "サーバー",                       "nameZh": "服务器",         "years": 5 },
  { "code": "SOFTWARE_INTERNAL", "nameJa": "ソフトウェア（自社利用）",       "nameZh": "软件（自用）",   "years": 5 },
  { "code": "CAMERA",            "nameJa": "カメラ",                         "nameZh": "相机",           "years": 5 },
  { "code": "FURNITURE",         "nameJa": "事務机・椅子",                   "nameZh": "办公桌椅",       "years": 8 },
  { "code": "VEHICLE",           "nameJa": "自動車（営業用以外）",           "nameZh": "汽车（非营业）", "years": 6 },
  { "code": "OTHER",             "nameJa": "その他工具器具備品",             "nameZh": "其他工具器具",   "years": 5 }
]
```

---

## Task 1.16: AccountSeeder.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/AccountSeeder.swift`

- [ ] **Step 1: Write AccountSeeder.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/AccountSeeder.swift`:
```swift
import Foundation
import SwiftData

public enum AccountSeeder {

    private struct Row: Decodable {
        let code: String
        let nameJa: String
        let nameZh: String
        let accountType: String
        let defaultBusinessAllocationRate: Double?
    }

    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        guard existing == 0 else { return }
        seed(context: context)
    }

    /// テスト用：既存件数を問わず seed を実行。
    public static func seed(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "accounts_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else {
            assertionFailure("accounts_seed.json missing or invalid")
            return
        }

        for row in rows {
            guard let type = AccountType(rawValue: row.accountType) else { continue }
            let account = Account(
                code: row.code,
                nameJa: row.nameJa,
                nameZh: row.nameZh,
                accountType: type,
                isBuiltin: true,
                isActive: true,
                defaultBusinessAllocationRate: row.defaultBusinessAllocationRate ?? 1.0
            )
            context.insert(account)
        }
        try? context.save()
    }
}
```

> **Note for build:** the JSON files in `SnapKei/Data/Seed/` are added to the app target via `PBXFileSystemSynchronizedRootGroup` automatically as resources because they're inside the synchronized folder. Verify by running Task 1.30 (seeder test) — if not found, mark the file as a target member in Xcode UI.

---

## Task 1.17: AssetUsefulLifeSeeder.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/AssetUsefulLifeSeeder.swift`

- [ ] **Step 1: Write AssetUsefulLifeSeeder.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Seed/AssetUsefulLifeSeeder.swift`:
```swift
import Foundation
import SwiftData

public enum AssetUsefulLifeSeeder {

    private struct Row: Decodable {
        let code: String
        let nameJa: String
        let nameZh: String
        let years: Int
    }

    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<AssetUsefulLife>())) ?? 0
        guard existing == 0 else { return }
        seed(context: context)
    }

    public static func seed(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "asset_useful_life_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else {
            assertionFailure("asset_useful_life_seed.json missing or invalid")
            return
        }

        for row in rows {
            let entry = AssetUsefulLife(
                code: row.code,
                nameJa: row.nameJa,
                nameZh: row.nameZh,
                years: row.years,
                isBuiltin: true
            )
            context.insert(entry)
        }
        try? context.save()
    }
}
```

---

## Task 1.18: Seeder tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/SeederTests.swift`

- [ ] **Step 1: Write SeederTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/SeederTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SnapKei

@Suite("Seeders")
struct SeederTests {

    @MainActor
    @Test func accountSeeder_seedsExpected33Accounts() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)

        let all = try ctx.fetch(FetchDescriptor<Account>())
        #expect(all.count == 33)
    }

    @MainActor
    @Test func accountSeeder_isIdempotent() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)
        AccountSeeder.seedIfNeeded(context: ctx) // 2 度呼ぶ
        #expect(try ctx.fetchCount(FetchDescriptor<Account>()) == 33)
    }

    @MainActor
    @Test func accountSeeder_expenseAccountsHaveNonNilAllocation() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)

        let utilities = try ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.code == "5170" })).first
        #expect(utilities?.defaultBusinessAllocationRate == 0.3)
    }

    @MainActor
    @Test func assetUsefulLifeSeeder_seeds7() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AssetUsefulLifeSeeder.seedIfNeeded(context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<AssetUsefulLife>()) == 7)
    }

    @MainActor
    @Test func assetUsefulLifeSeeder_pcIs4Years() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AssetUsefulLifeSeeder.seedIfNeeded(context: ctx)

        let pc = try ctx.fetch(FetchDescriptor<AssetUsefulLife>(predicate: #Predicate { $0.code == "PC" })).first
        #expect(pc?.years == 4)
    }
}
```

---

## Task 1.19: ExpenseRepository.swift — `create`

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`

- [ ] **Step 1: Write ExpenseRepository.swift (initial version with create only)**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`:
```swift
import Foundation
import SwiftData

public protocol ExpenseRepository: Sendable {
    func create(_ entry: JournalEntry, reason: String?) throws
    func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws
    func void(_ entry: JournalEntry, reason: String?) throws
    func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry]
    func nextEntryNumber(for fiscalYear: Int) throws -> Int
}

public struct ExpenseSearchCriteria: Sendable {
    public var dateFrom: Date?
    public var dateTo: Date?
    public var debitAccountCodes: [String]?
    public var amountMin: Int?
    public var amountMax: Int?
    public var qualifiedOnly: Bool?
    public var lateEntryOnly: Bool?
    public var includeVoided: Bool

    public init(
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        debitAccountCodes: [String]? = nil,
        amountMin: Int? = nil,
        amountMax: Int? = nil,
        qualifiedOnly: Bool? = nil,
        lateEntryOnly: Bool? = nil,
        includeVoided: Bool = false
    ) {
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.debitAccountCodes = debitAccountCodes
        self.amountMin = amountMin
        self.amountMax = amountMax
        self.qualifiedOnly = qualifiedOnly
        self.lateEntryOnly = lateEntryOnly
        self.includeVoided = includeVoided
    }
}

public final class SwiftDataExpenseRepository: ExpenseRepository, @unchecked Sendable {
    private let context: ModelContext
    private let deviceId: String

    public init(context: ModelContext, deviceId: String) {
        self.context = context
        self.deviceId = deviceId
    }

    // MARK: - create

    public func create(_ entry: JournalEntry, reason: String? = nil) throws {
        // entryNumber を末尾追加で確定（空洞なし、青色申告要件）
        let assigned = try nextEntryNumber(for: entry.fiscalYear)
        entry.entryNumber = assigned
        entry.createdAt = Date()
        entry.updatedAt = entry.createdAt

        context.insert(entry)

        let after = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .createEntry,
            targetEntryId: entry.id,
            beforeSnapshot: nil,
            afterSnapshot: after,
            reason: reason
        )
        context.insert(log)

        try context.save()
    }

    // MARK: - edit / void / search / nextEntryNumber — implemented in Tasks 1.21 / 1.23 / 1.25 / right below

    public func nextEntryNumber(for fiscalYear: Int) throws -> Int {
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )
        descriptor.sortBy = [SortDescriptor(\.entryNumber, order: .reverse)]
        descriptor.fetchLimit = 1
        let last = try context.fetch(descriptor).first
        return (last?.entryNumber ?? 0) + 1
    }

    public func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        fatalError("Implemented in Task 1.21")
    }
    public func void(_ entry: JournalEntry, reason: String?) throws {
        fatalError("Implemented in Task 1.22")
    }
    public func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry] {
        fatalError("Implemented in Task 1.24")
    }
}

// MARK: - Snapshot DTO

struct JournalEntrySnapshot: Codable {
    let id: UUID
    let entryNumber: Int
    let fiscalYear: Int
    let transactionDate: Date
    let inputDate: Date
    let isLateEntry: Bool
    let debitAccountCode: String
    let creditAccountCode: String
    let amountIncludingTax: Int
    let amountExcludingTax: Int
    let consumptionTax: Int
    let taxCategoryRaw: String
    let priceEntryModeRaw: String
    let paymentMethodRaw: String
    let counterpartyName: String
    let invoiceRegistrationNumber: String?
    let invoiceQualified: Bool
    let transitionalMeasureRate: Double
    let transactionDescription: String
    let memo: String?
    let businessAllocationRate: Double
    let originalAmountIncludingTax: Int?
    let relatedFixedAssetId: UUID?
    let receiptImagePath: String?
    let receiptImageHash: String?
    let sourceTypeRaw: String
    let createdAt: Date
    let updatedAt: Date
    let syncId: UUID
    let isVoided: Bool

    init(from e: JournalEntry) {
        self.id = e.id
        self.entryNumber = e.entryNumber
        self.fiscalYear = e.fiscalYear
        self.transactionDate = e.transactionDate
        self.inputDate = e.inputDate
        self.isLateEntry = e.isLateEntry
        self.debitAccountCode = e.debitAccountCode
        self.creditAccountCode = e.creditAccountCode
        self.amountIncludingTax = e.amountIncludingTax
        self.amountExcludingTax = e.amountExcludingTax
        self.consumptionTax = e.consumptionTax
        self.taxCategoryRaw = e.taxCategoryRaw
        self.priceEntryModeRaw = e.priceEntryModeRaw
        self.paymentMethodRaw = e.paymentMethodRaw
        self.counterpartyName = e.counterpartyName
        self.invoiceRegistrationNumber = e.invoiceRegistrationNumber
        self.invoiceQualified = e.invoiceQualified
        self.transitionalMeasureRate = e.transitionalMeasureRate
        self.transactionDescription = e.transactionDescription
        self.memo = e.memo
        self.businessAllocationRate = e.businessAllocationRate
        self.originalAmountIncludingTax = e.originalAmountIncludingTax
        self.relatedFixedAssetId = e.relatedFixedAssetId
        self.receiptImagePath = e.receiptImagePath
        self.receiptImageHash = e.receiptImageHash
        self.sourceTypeRaw = e.sourceTypeRaw
        self.createdAt = e.createdAt
        self.updatedAt = e.updatedAt
        self.syncId = e.syncId
        self.isVoided = e.isVoided
    }
}
```

> **Note:** `edit` / `void` / `search` are stubbed `fatalError` here — they're implemented in the next 3 tasks. Tests for `create` + `nextEntryNumber` are in Task 1.20.

---

## Task 1.20: ExpenseRepository.create + nextEntryNumber tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`

- [ ] **Step 1: Write ExpenseRepositoryTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SnapKei

@Suite("ExpenseRepository — create / entryNumber")
struct ExpenseRepositoryCreateTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @MainActor
    private func makeRepo() throws -> (SwiftDataExpenseRepository, ModelContext) {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        return (repo, container.mainContext)
    }

    private func makeEntry(year: Int, amount: Int = 1100) -> JournalEntry {
        JournalEntry(
            entryNumber: 0, // 後で repo が上書き
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
    @Test func nextEntryNumber_emptyFiscalYear_returns1() throws {
        let (repo, _) = try makeRepo()
        #expect(try repo.nextEntryNumber(for: 2026) == 1)
    }

    @MainActor
    @Test func create_assignsEntryNumber1_2_3_inOrder() throws {
        let (repo, ctx) = try makeRepo()
        let e1 = makeEntry(year: 2026)
        let e2 = makeEntry(year: 2026)
        let e3 = makeEntry(year: 2026)
        try repo.create(e1, reason: nil)
        try repo.create(e2, reason: nil)
        try repo.create(e3, reason: nil)

        let all = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.entryNumber)]))
        #expect(all.map(\.entryNumber) == [1, 2, 3])
    }

    @MainActor
    @Test func create_isolatesFiscalYears() throws {
        let (repo, _) = try makeRepo()
        let a = makeEntry(year: 2025)
        let b = makeEntry(year: 2026)
        try repo.create(a, reason: nil)
        try repo.create(b, reason: nil)
        #expect(a.entryNumber == 1)
        #expect(b.entryNumber == 1)
    }

    @MainActor
    @Test func create_writesSystemActivityLog() throws {
        let (repo, ctx) = try makeRepo()
        let e = makeEntry(year: 2026)
        try repo.create(e, reason: nil)
        let logs = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.activityType == .createEntry)
        #expect(logs.first?.targetEntryId == e.id)
        #expect(logs.first?.beforeSnapshot == nil)
        #expect(logs.first?.afterSnapshot != nil)
    }
}
```

---

## Task 1.21: ExpenseRepository.edit + tests

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`
- Modify: `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`

- [ ] **Step 1: Replace the `edit` stub**

In `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`, replace:
```swift
    public func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        fatalError("Implemented in Task 1.21")
    }
```
with:
```swift
    public func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        let before = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        change()
        entry.updatedAt = Date()
        let after  = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))

        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .editEntry,
            targetEntryId: entry.id,
            beforeSnapshot: before,
            afterSnapshot: after,
            reason: reason
        )
        context.insert(log)
        try context.save()
    }
```

- [ ] **Step 2: Append edit tests**

Append to `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`:
```swift

@Suite("ExpenseRepository — edit")
struct ExpenseRepositoryEditTests {

    @MainActor
    private func makeSeeded() throws -> (SwiftDataExpenseRepository, ModelContext, JournalEntry) {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")
        let e = JournalEntry(
            entryNumber: 0,
            fiscalYear: 2026,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 1100,
            amountExcludingTax: 1000,
            consumptionTax: 100,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店",
            transactionDescription: "編集前",
            sourceType: .manual
        )
        try repo.create(e, reason: nil)
        return (repo, container.mainContext, e)
    }

    @MainActor
    @Test func edit_writesEditLogWithBeforeAndAfter() throws {
        let (repo, ctx, e) = try makeSeeded()
        try repo.edit(e, applying: { e.transactionDescription = "編集後" }, reason: "誤記訂正")

        let editLogs = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .editEntry }
        #expect(editLogs.count == 1)
        #expect(editLogs.first?.beforeSnapshot != nil)
        #expect(editLogs.first?.afterSnapshot != nil)
        #expect(editLogs.first?.reason == "誤記訂正")
    }

    @MainActor
    @Test func edit_beforeSnapshot_capturesOldDescription() throws {
        let (repo, ctx, e) = try makeSeeded()
        try repo.edit(e, applying: { e.transactionDescription = "編集後" }, reason: nil)

        let log = try ctx.fetch(FetchDescriptor<SystemActivityLog>())
            .first(where: { $0.activityType == .editEntry })!
        let before = try JSONDecoder().decode(JournalEntrySnapshot.self, from: log.beforeSnapshot!)
        #expect(before.transactionDescription == "編集前")
    }

    @MainActor
    @Test func edit_updatesUpdatedAt_butPreservesCreatedAt() async throws {
        let (repo, _, e) = try makeSeeded()
        let originalCreatedAt = e.createdAt
        let originalUpdatedAt = e.updatedAt
        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms 待って updatedAt との差を作る
        try repo.edit(e, applying: { e.memo = "メモ" }, reason: nil)
        #expect(e.createdAt == originalCreatedAt)
        #expect(e.updatedAt > originalUpdatedAt)
    }
}
```

---

## Task 1.22: ExpenseRepository.void + tests

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`
- Modify: `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`

- [ ] **Step 1: Replace the `void` stub**

In `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`, replace:
```swift
    public func void(_ entry: JournalEntry, reason: String?) throws {
        fatalError("Implemented in Task 1.22")
    }
```
with:
```swift
    public func void(_ entry: JournalEntry, reason: String?) throws {
        let before = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        entry.isVoided = true
        entry.updatedAt = Date()

        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .voidEntry,
            targetEntryId: entry.id,
            beforeSnapshot: before,
            afterSnapshot: nil,
            reason: reason
        )
        context.insert(log)
        try context.save()
    }
```

- [ ] **Step 2: Append void tests**

Append to `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`:
```swift

@Suite("ExpenseRepository — void")
struct ExpenseRepositoryVoidTests {

    @MainActor
    @Test func void_marksIsVoided_butDoesNotDelete() throws {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let e = JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店", transactionDescription: "取消対象", sourceType: .manual
        )
        try repo.create(e, reason: nil)
        try repo.void(e, reason: "誤記")

        #expect(e.isVoided == true)
        let all = try container.mainContext.fetch(FetchDescriptor<JournalEntry>())
        #expect(all.count == 1) // 物理削除なし
    }

    @MainActor
    @Test func void_writesVoidLogWithBefore() throws {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let e = JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト商店", transactionDescription: "取消対象", sourceType: .manual
        )
        try repo.create(e, reason: nil)
        try repo.void(e, reason: "誤記")

        let voidLogs = try container.mainContext.fetch(FetchDescriptor<SystemActivityLog>())
            .filter { $0.activityType == .voidEntry }
        #expect(voidLogs.count == 1)
        #expect(voidLogs.first?.beforeSnapshot != nil)
        #expect(voidLogs.first?.reason == "誤記")
    }
}
```

---

## Task 1.23: ExpenseRepository.search

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`

- [ ] **Step 1: Replace the `search` stub**

In `/Users/lee/workspace/SnapKei/SnapKei/Data/Persistence/ExpenseRepository.swift`, replace:
```swift
    public func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry] {
        fatalError("Implemented in Task 1.24")
    }
```
with:
```swift
    public func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry] {
        // SwiftData の Predicate は複雑な合成（オプショナル + 配列 contains + ブール）に
        // バージョン依存の制約があるため、widest fetch を行い in-memory で絞る方が安全。
        // データ規模は個人事業主・年数千件レベルなので問題なし。
        var descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse), SortDescriptor(\.entryNumber, order: .reverse)]
        )
        descriptor.fetchLimit = nil
        var results = try context.fetch(descriptor)

        if !criteria.includeVoided {
            results = results.filter { !$0.isVoided }
        }
        if let from = criteria.dateFrom {
            results = results.filter { $0.transactionDate >= from }
        }
        if let to = criteria.dateTo {
            results = results.filter { $0.transactionDate <= to }
        }
        if let codes = criteria.debitAccountCodes, !codes.isEmpty {
            let set = Set(codes)
            results = results.filter { set.contains($0.debitAccountCode) }
        }
        if let minA = criteria.amountMin {
            results = results.filter { $0.amountIncludingTax >= minA }
        }
        if let maxA = criteria.amountMax {
            results = results.filter { $0.amountIncludingTax <= maxA }
        }
        if let q = criteria.qualifiedOnly {
            results = results.filter { $0.invoiceQualified == q }
        }
        if let l = criteria.lateEntryOnly, l {
            results = results.filter { $0.isLateEntry }
        }
        return results
    }
```

- [ ] **Step 2: Append search tests**

Append to `/Users/lee/workspace/SnapKei/SnapKeiTests/ExpenseRepositoryTests.swift`:
```swift

@Suite("ExpenseRepository — search")
struct ExpenseRepositorySearchTests {

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.date(from: s)!
    }

    @MainActor
    private func setupFixture() throws -> SwiftDataExpenseRepository {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let repo = SwiftDataExpenseRepository(context: container.mainContext, deviceId: "test-device")

        let make: (String, String, Int, Bool) -> JournalEntry = { dt, debit, amt, qualified in
            JournalEntry(
                entryNumber: 0, fiscalYear: 2026, transactionDate: self.date(dt),
                debitAccountCode: debit, creditAccountCode: "3210",
                amountIncludingTax: amt, amountExcludingTax: amt * 10 / 11, consumptionTax: amt - amt * 10 / 11,
                taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
                counterpartyName: "店\(amt)", invoiceQualified: qualified,
                transactionDescription: "取引\(amt)", sourceType: .manual
            )
        }

        try repo.create(make("2026-01-15", "5110",  1_100, true ), reason: nil)
        try repo.create(make("2026-03-20", "5100",  5_500, false), reason: nil)
        try repo.create(make("2026-04-10", "5110", 11_000, true ), reason: nil)
        try repo.create(make("2026-05-01", "5120", 22_000, false), reason: nil)
        return repo
    }

    @MainActor
    @Test func search_dateRange() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(
            dateFrom: date("2026-03-01"), dateTo: date("2026-04-30")
        ))
        #expect(res.count == 2)
    }

    @MainActor
    @Test func search_debitAccount() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(debitAccountCodes: ["5110"]))
        #expect(res.count == 2)
        #expect(res.allSatisfy { $0.debitAccountCode == "5110" })
    }

    @MainActor
    @Test func search_amountRange() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(amountMin: 5_000, amountMax: 15_000))
        #expect(res.count == 2)
    }

    @MainActor
    @Test func search_threeConditionsCombined() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(
            dateFrom: date("2026-01-01"), dateTo: date("2026-12-31"),
            debitAccountCodes: ["5110"],
            amountMin: 10_000, amountMax: 100_000
        ))
        #expect(res.count == 1)
        #expect(res.first?.amountIncludingTax == 11_000)
    }

    @MainActor
    @Test func search_qualifiedOnly_filtersUnqualified() throws {
        let repo = try setupFixture()
        let res = try repo.search(criteria: ExpenseSearchCriteria(qualifiedOnly: true))
        #expect(res.count == 2)
        #expect(res.allSatisfy(\.invoiceQualified))
    }

    @MainActor
    @Test func search_excludesVoidedByDefault() throws {
        let repo = try setupFixture()
        let all = try repo.search(criteria: ExpenseSearchCriteria())
        let first = all.first!
        try repo.void(first, reason: nil)
        let afterVoid = try repo.search(criteria: ExpenseSearchCriteria())
        #expect(afterVoid.count == all.count - 1)
        #expect(!afterVoid.contains(where: { $0.id == first.id }))
    }

    @MainActor
    @Test func search_includeVoided_returnsAll() throws {
        let repo = try setupFixture()
        let all = try repo.search(criteria: ExpenseSearchCriteria())
        try repo.void(all.first!, reason: nil)
        let withVoided = try repo.search(criteria: ExpenseSearchCriteria(includeVoided: true))
        #expect(withVoided.count == all.count)
    }
}
```

---

## Task 1.24: AppSettings.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Settings/AppSettings.swift`

- [ ] **Step 1: Write AppSettings.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Settings/AppSettings.swift`:
```swift
import Foundation

/// 事業者情報 + コンプライアンス設定の persistence wrapper。
/// API Key 等の機密情報は含まない（それは KeychainService 経由、Plan 2）。
public struct AppSettings: Sendable, Equatable {
    public var businessName: String              // 屋号
    public var ownerName: String                 // 氏名
    public var ownInvoiceRegistrationNumber: String  // 自分の T+13 桁
    public var fiscalYearStartMonth: Int         // 1–12、個人事業主は通常 1
    public var lateEntryThresholdDays: Int       // 通常業務以外の判定閾値

    public static let `default` = AppSettings(
        businessName: "",
        ownerName: "",
        ownInvoiceRegistrationNumber: "",
        fiscalYearStartMonth: 1,
        lateEntryThresholdDays: ComplianceConstants.defaultLateEntryThresholdDays
    )

    public init(
        businessName: String,
        ownerName: String,
        ownInvoiceRegistrationNumber: String,
        fiscalYearStartMonth: Int,
        lateEntryThresholdDays: Int
    ) {
        self.businessName = businessName
        self.ownerName = ownerName
        self.ownInvoiceRegistrationNumber = ownInvoiceRegistrationNumber
        self.fiscalYearStartMonth = fiscalYearStartMonth
        self.lateEntryThresholdDays = lateEntryThresholdDays
    }

    // MARK: - UserDefaults persistence

    private enum Keys {
        static let businessName = "app.businessName"
        static let ownerName = "app.ownerName"
        static let ownInvoiceRegistrationNumber = "app.ownInvoiceRegistrationNumber"
        static let fiscalYearStartMonth = "app.fiscalYearStartMonth"
        static let lateEntryThresholdDays = "app.lateEntryThresholdDays"
    }

    public static func load(defaults: UserDefaults = .standard) -> AppSettings {
        let storedFy = defaults.integer(forKey: Keys.fiscalYearStartMonth)
        let storedTh = defaults.integer(forKey: Keys.lateEntryThresholdDays)
        return AppSettings(
            businessName: defaults.string(forKey: Keys.businessName) ?? "",
            ownerName: defaults.string(forKey: Keys.ownerName) ?? "",
            ownInvoiceRegistrationNumber: defaults.string(forKey: Keys.ownInvoiceRegistrationNumber) ?? "",
            fiscalYearStartMonth: storedFy >= 1 && storedFy <= 12 ? storedFy : 1,
            lateEntryThresholdDays: storedTh > 0 ? storedTh : ComplianceConstants.defaultLateEntryThresholdDays
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(businessName, forKey: Keys.businessName)
        defaults.set(ownerName, forKey: Keys.ownerName)
        defaults.set(ownInvoiceRegistrationNumber, forKey: Keys.ownInvoiceRegistrationNumber)
        defaults.set(fiscalYearStartMonth, forKey: Keys.fiscalYearStartMonth)
        defaults.set(lateEntryThresholdDays, forKey: Keys.lateEntryThresholdDays)
    }
}
```

---

## Task 1.25: AppSettings tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AppSettingsTests.swift`

- [ ] **Step 1: Write AppSettingsTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AppSettingsTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AppSettings")
struct AppSettingsTests {

    /// 各 test 毎に独立した UserDefaults suite を使う。
    private func suiteDefaults(_ id: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: id)!
    }

    @Test func default_hasSaneInitialValues() {
        let d = AppSettings.default
        #expect(d.businessName.isEmpty)
        #expect(d.fiscalYearStartMonth == 1)
        #expect(d.lateEntryThresholdDays == ComplianceConstants.defaultLateEntryThresholdDays)
    }

    @Test func roundTrip_persistsAllFields() {
        let defaults = suiteDefaults()
        let s = AppSettings(
            businessName: "Lee 個人事業",
            ownerName: "Zhang Xiaotian",
            ownInvoiceRegistrationNumber: "T1234567890123",
            fiscalYearStartMonth: 1,
            lateEntryThresholdDays: 30
        )
        s.save(defaults: defaults)

        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded == s)
    }

    @Test func load_emptyDefaults_returnsDefault() {
        let defaults = suiteDefaults()
        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded == AppSettings.default)
    }

    @Test func load_invalidFiscalMonth_falls_back_to_1() {
        let defaults = suiteDefaults()
        defaults.set(99, forKey: "app.fiscalYearStartMonth")
        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded.fiscalYearStartMonth == 1)
    }
}
```

---

## Task 1.26: Phase 1 — full build + test

- [ ] **Step 1: Run full build**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED`.

If `iPhone 17 Pro` not available, list with `xcrun simctl list devices available | head -40` and substitute.

- [ ] **Step 2: Run full test**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test 2>&1 | tail -50
```
Expected: `TEST SUCCEEDED`, all tests passing across `EnumsTests` / `ComplianceServiceTests` / `DepreciationServiceTests` / `SeederTests` / `ExpenseRepositoryCreateTests` / `ExpenseRepositoryEditTests` / `ExpenseRepositoryVoidTests` / `ExpenseRepositorySearchTests` / `AppSettingsTests`.

If any test fails, fix it before proceeding. Common gotchas:
- Seed JSON files not bundled in app target → add them via Xcode UI (right-click in Xcode → "Add Files to Target...")
- `@MainActor` test functions need `try await` if calling async APIs (swift-testing infers)
- `try Task.sleep` in test must be in `async throws` test function

---

## Task 1.27: Phase 1 commit checkpoint

- [ ] **Step 1: Stage**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei/Domain/ SnapKei/Data/ SnapKeiTests/
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git commit -m "$(cat <<'EOF'
feat: Phase 1 — data layer + compliance services

- Entities (SwiftData @Model): Account, AssetUsefulLife, JournalEntry,
  SystemActivityLog, FixedAsset; 9 enums in Enums.swift
- Compliance: ComplianceConstants (5-stage transitional schedule,
  smallDepreciable 40 万円), ComplianceService (deadline calc,
  transitionalRate, assetTreatment suggest, isLateEntry)
- Depreciation: DepreciationService (straight-line monthly prorated,
  lump-sum 1/3, small-amount full expense returns 0)
- Persistence: SnapKeiModelContainer (shared + in-memory),
  ExpenseRepository (entryNumber 連番 / edit+void with snapshot logs /
  3-condition AND search)
- Seeders: 33 standard accounts, 7 asset useful lives, idempotent on
  first launch
- AppSettings: 屋号 / 氏名 / 適格番号 / 事業年度開始月 /
  lateEntryThresholdDays via UserDefaults
- Tests: 9 test suites, ~40 tests covering compliance edge cases
  (boundary dates, allocation rates), seeder idempotency, repository
  isolation across fiscal years, search composition

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Do NOT push**

---

# End of Plan 1

After Task 1.27 succeeds, Plan 1 is done. The app will:
- Build green on iOS 18.5+ simulator
- Show the 4-tab placeholder UI (no real functionality)
- Have all data layer entities ready, with 33 accounts + 7 asset useful lives seeded on first launch
- Pass all unit tests

**Next:** ask the user to invoke `superpowers:writing-plans` again to generate Plan 2 (AI Layer: Phase 2 + 3 + 3.5 — BYOK Anthropic + Sign in with Apple + Cloudflare Worker).

---

## Self-review summary

This plan covers spec §1 (data model), §3 (Account master + AssetUsefulLife master only — JournalEntry insert flows from §6 come in Plan 2/3), §4 (Compliance layer), and the data-persistence portions of §5. It explicitly defers §2 (architecture is set up but mostly empty until Plan 2 fills it), §5 (AI Service implementations), §6 (Capture flow needs CaptureView), §7 (Settings UI), §8 (PDF reports), §10 phases 2+.

Plan 1 produces working, testable software in the data-layer sense: app boots, container attaches, seeders run, all data operations covered by tests. No user-visible functionality beyond a placeholder tab bar — that's intentional.
