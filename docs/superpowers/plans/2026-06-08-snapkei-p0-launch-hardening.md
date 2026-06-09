# SnapKei P0: Launch Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the current `snapkei-foundation-ai-ui` working tree (LLMGatewayKit migration, builds green, 76 tests pass) to a TestFlight-submittable state: working BYOK, hardened sync, first-run onboarding + in-app disclaimer, app icon, privacy manifest, secrets hygiene, and store-readiness metadata.

**Architecture:** No new subsystems. This plan finishes half-done wiring (BYOK key storage via existing `KeychainService`, sync cursor multi-user keying), adds a thin onboarding/legal presentation layer, and fixes project-level configuration (`Secrets.xcconfig` attachment, privacy manifest, deployment target). Each task is independently shippable.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / swift-testing (`import Testing`, `#expect`) / Xcode 26 with `PBXFileSystemSynchronizedRootGroup` (source files under `SnapKei/` are auto-included; **only** xcconfig attachment and build settings require manual `project.pbxproj` edits — those edits are intentional).

**Working directory:** `/Users/lee/workspace/SnapKei/`. All paths below are absolute or repo-relative from there.

**User preferences (carried over from previous plans):**
- Do NOT `git push` at any point.
- Commit steps are checkpoints; **ask for explicit confirmation before every `git commit`**.
- Build verification (`xcodebuild`) at the end of every task that touches the project.

**Execution amendments from plan review (must apply before implementation):**
- Do not use broad `git add -A` during Task 0. Stage only the in-flight LLMGatewayKit migration files, and explicitly exclude `docs/superpowers/plans/` plus `Secrets.xcconfig`.
- Treat account switching as a privacy boundary, not just a sync-cursor boundary. P0 must either partition/purge local financial data on logout/account switch or clearly block cloud-sync account switching until that is implemented.
- Scope BYOK Keychain storage by signed-in account, or make it visibly device-local and clear it on logout. Do not let user B reuse user A's API key on the same device.
- Keep the privacy/support docs aligned with shipped behavior. Do not promise account deletion or server-side cloud deletion unless those flows are implemented and verified in the same launch scope.
- P1 ledger/report features must not be user-facing until this plan's disclaimer/onboarding and privacy docs are complete.

**Standard verification commands:**

```bash
# Full test suite (from repo root)
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | tail -20
# Build only
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected baseline before starting: `** TEST SUCCEEDED **`, 76 tests, 0 failures.

---

## File Structure (created/modified by this plan)

```
/Users/lee/workspace/SnapKei/
├── .gitignore                                    [MODIFY: ignore Secrets.xcconfig]
├── Secrets.xcconfig                              [MODIFY: add REVENUECAT_API_KEY; then git rm --cached]
├── Secrets.xcconfig.template                     [CREATE]
├── README.md                                     [MODIFY: setup instructions, iOS requirement]
├── tools/
│   └── generate_app_icon.swift                   [CREATE — placeholder icon generator]
│   └── check_localizations.py                    [CREATE — xcstrings completeness check]
├── docs/legal/
│   ├── privacy-policy.md                         [CREATE]
│   └── support.md                                [CREATE]
├── SnapKei.xcodeproj/project.pbxproj             [MODIFY: xcconfig attach, RC key, encryption flag, regions, deployment target]
├── SnapKei/
│   ├── PrivacyInfo.xcprivacy                     [CREATE — privacy manifest]
│   ├── Assets.xcassets/AppIcon.appiconset/
│   │   ├── Contents.json                         [MODIFY]
│   │   └── AppIcon-1024.png                      [CREATE — generated]
│   ├── App/SnapKeiApp.swift                      [MODIFY: BYOK provider, cursor provider, empty-string guards]
│   ├── Data/Settings/
│   │   ├── ByokKeyStore.swift                    [CREATE]
│   │   └── AppSettings.swift                     [MODIFY: hasCompletedOnboarding]
│   ├── Data/Sync/SyncCursorStore.swift           [MODIFY: userIDProvider]
│   ├── Presentation/RootView.swift               [MODIFY: onboarding cover, sync toast]
│   ├── Presentation/Legal/
│   │   ├── LegalTexts.swift                      [CREATE]
│   │   ├── DisclaimerView.swift                  [CREATE]
│   │   └── OnboardingView.swift                  [CREATE]
│   ├── Presentation/Settings/
│   │   ├── AISettingsSection.swift               [MODIFY: BYOK key UI]
│   │   ├── SettingsView.swift                    [MODIFY: disclaimer link, remove toast overlay]
│   │   └── FixedAssetSection.swift               [MODIFY: hide deleted assets]
│   ├── Presentation/ExpenseList/ExpenseListView.swift [MODIFY: accessibility labels]
│   └── Resources/Localizable.xcstrings           [MODIFY: complete semantic keys]
└── SnapKeiTests/
    ├── ByokKeyStoreTests.swift                   [CREATE]
    ├── SyncCursorStoreTests.swift                [CREATE]
    ├── SnapKeiMergerTests.swift                  [CREATE]
    ├── SnapKeiChangeCollectorTests.swift         [CREATE]
    └── AppSettingsTests.swift                    [MODIFY: onboarding flag roundtrip]
```

**Out of scope for P0** (deferred to P1/P2 plans): 帳簿 outputs (仕訳帳/総勘定元帳/B-S), year-end closing, 決算書/申告書 generation, e-Tax, LICENSE choice (user decision pending), real icon artwork (placeholder only), zh-Hans full translation.

---

### Task 0: Baseline commit of the in-flight LLMGatewayKit migration

The working tree contains the whole auth/sync/settings migration uncommitted. It builds and all 76 tests pass — lock it in before changing anything.

**Files:** all modified/untracked files per `git status` (including deletions of `SnapKei/Data/Auth/*` and the new `SnapKei/Data/Sync/`, `SnapKei.xcodeproj/project.xcworkspace/xcshareddata/` Package.resolved pin).

- [ ] **Step 1: Verify green baseline**

Run: `xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Review what will be committed**

Run: `git -C /Users/lee/workspace/SnapKei status --short`
Confirm the list matches the migration scope (no stray files). **Do not stage** `docs/superpowers/plans/*` or `Secrets.xcconfig` in this baseline checkpoint; Task 1 handles secrets untracking/template setup explicitly.

- [ ] **Step 3: Commit (ask user first)**

Stage the migration files explicitly (auth deletions, `Data/Sync`, app/settings/sync UI, tests, and `Package.resolved`), then ask before committing:

```bash
git add SnapKei.xcodeproj/project.pbxproj SnapKei.xcodeproj/project.xcworkspace/xcshareddata/ SnapKei/App/SnapKeiApp.swift SnapKei/Data/Auth/ SnapKei/Data/Network/ SnapKei/Data/Persistence/ SnapKei/Data/Sync/ SnapKei/Domain/Entities/FixedAsset.swift SnapKei/Presentation/Capture/ SnapKei/Presentation/Home/ SnapKei/Presentation/Settings/ SnapKei/Resources/Localizable.xcstrings SnapKeiTests/
git commit -m "feat: migrate auth/subscription/sync to LLMGatewayKit, add cloud sync layer and settings redesign"
```

---

### Task 1: Secrets hygiene — actually attach `Secrets.xcconfig`, route the RevenueCat key, template + gitignore

**Background (verified):** `Secrets.xcconfig` exists but is **not referenced anywhere in `project.pbxproj`** — the resolved `GATEWAY_BASE_URL` comes from a raw build setting at `project.pbxproj:402` and `:444`. Additionally `SnapKeiApp.swift:24` reads Info.plist key `REVENUECAT_API_KEY`, but no `INFOPLIST_KEY_REVENUECAT_API_KEY` mapping exists → RevenueCat key is always `nil` and the paywall cannot work.

**Files:**
- Modify: `SnapKei.xcodeproj/project.pbxproj`
- Modify: `Secrets.xcconfig`
- Create: `Secrets.xcconfig.template`
- Modify: `.gitignore`
- Modify: `SnapKei/App/SnapKeiApp.swift`
- Modify: `README.md`

- [ ] **Step 1: Add a PBXFileReference for Secrets.xcconfig**

Check whether the section exists: `grep -n "Begin PBXFileReference section" SnapKei.xcodeproj/project.pbxproj`

If it exists, insert inside it; if not, add the whole section right after the `/* End PBXContainerItemProxy section */` line (or after the first `objects = {` content block if no proxy section). Entry to insert:

```
/* Begin PBXFileReference section */
		AA00000000000000000000C1 /* Secrets.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */
```

(If the section already exists, add only the inner line.)

- [ ] **Step 2: Add the file to the main group (navigator visibility)**

Find the main group block: `grep -n "9BD186552FB88A3300337460 = {" SnapKei.xcodeproj/project.pbxproj`. In its `children = (` list, add as first child:

```
				AA00000000000000000000C1 /* Secrets.xcconfig */,
```

- [ ] **Step 3: Attach as base configuration to the app target's Debug and Release configs**

In the two `XCBuildConfiguration` blocks whose `buildSettings` contain `PRODUCT_BUNDLE_IDENTIFIER = com.cheung.SnapKei;` (around lines 399 and 441), insert directly after the `isa = XCBuildConfiguration;` line:

```
			baseConfigurationReference = AA00000000000000000000C1 /* Secrets.xcconfig */;
```

- [ ] **Step 4: Remove the hardcoded GATEWAY_BASE_URL build settings**

Delete these two lines (currently 402 and 444) so the xcconfig value is authoritative:

```
				GATEWAY_BASE_URL = "https:/$()/api.conch-talk.com";
```

- [ ] **Step 5: Add the RevenueCat Info.plist mapping**

Next to each of the two `INFOPLIST_KEY_GATEWAY_BASE_URL = "$(GATEWAY_BASE_URL)";` lines, add:

```
				INFOPLIST_KEY_REVENUECAT_API_KEY = "$(REVENUECAT_API_KEY)";
```

- [ ] **Step 6: Extend Secrets.xcconfig and create the template**

Append to `Secrets.xcconfig`:

```
REVENUECAT_API_KEY =
```

Create `Secrets.xcconfig.template`:

```
// SnapKei build secrets — copy this file to Secrets.xcconfig and fill in values.
// NOTE: '//' inside URLs must be escaped as '/$()/' so xcconfig does not treat it as a comment.

PROXY_BASE_URL = https:/$()/api.conch-talk.com
GATEWAY_BASE_URL = https:/$()/api.conch-talk.com

// RevenueCat public SDK key (appl_...). Leave empty to disable purchases.
REVENUECAT_API_KEY =
```

- [ ] **Step 7: Harden SnapKeiApp against empty Info.plist strings**

In `SnapKei/App/SnapKeiApp.swift` replace lines 19–24 (`let config = LLMGatewayKitConfig(` … `revenueCatAPIKey:` line):

```swift
        let gatewayURLString = (Bundle.main.object(forInfoDictionaryKey: "GATEWAY_BASE_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.conch-talk.com"
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: gatewayURLString)!,
            entitlementID: "pro",
            appDisplayName: "SnapKei",
            companionAppNames: ["ConchTalk"],
            revenueCatAPIKey: (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String)
                .flatMap { $0.isEmpty ? nil : $0 },
```

(The rest of the initializer is unchanged.)

- [ ] **Step 8: Verify build settings resolve from the xcconfig**

Run: `xcodebuild -scheme SnapKei -showBuildSettings 2>/dev/null | grep -E "GATEWAY_BASE_URL|REVENUECAT_API_KEY"`
Expected: `GATEWAY_BASE_URL = https://api.conch-talk.com` (now sourced from xcconfig) and `REVENUECAT_API_KEY = ` present.

- [ ] **Step 9: Untrack the real secrets file**

```bash
printf 'Secrets.xcconfig\n' >> .gitignore
git rm --cached Secrets.xcconfig
```

(The file stays on disk — the build needs it.)

- [ ] **Step 10: README setup section**

In `README.md`, under `## Development`, add before the "Open the project" paragraph:

```markdown
### First-time setup

The project reads build secrets from an untracked `Secrets.xcconfig`:

```bash
cp Secrets.xcconfig.template Secrets.xcconfig
# then fill in REVENUECAT_API_KEY (optional) — gateway URLs default to the public endpoint
```
```

- [ ] **Step 11: Full build + test, then commit (ask user first)**

Run the standard test command. Expected: `** TEST SUCCEEDED **`, 76 tests.

```bash
git add .gitignore Secrets.xcconfig.template SnapKei.xcodeproj/project.pbxproj SnapKei/App/SnapKeiApp.swift README.md
git commit -m "chore: attach Secrets.xcconfig as base configuration, route RevenueCat key, untrack secrets"
```

---

### Task 2: BYOK — Keychain-backed Anthropic API key (store + UI + wiring)

**Background:** `SnapKeiApp.swift:79` hardcodes `apiKeyProvider: { "" }`, so the user-selectable "自前 API Key" channel always throws `missingAPIKey`. `KeychainService`/`SecretStore` already exist (`SnapKei/Data/Security/KeychainService.swift`).

**Plan-review correction:** The Keychain account must be scoped by the current signed-in user ID (or cleared on logout) so one local user cannot reuse another user's Anthropic API key after account switching.

**Files:**
- Create: `SnapKei/Data/Settings/ByokKeyStore.swift`
- Test: `SnapKeiTests/ByokKeyStoreTests.swift`
- Modify: `SnapKei/App/SnapKeiApp.swift:79`
- Modify: `SnapKei/Presentation/Settings/AISettingsSection.swift`

- [ ] **Step 1: Write the failing test**

Create `SnapKeiTests/ByokKeyStoreTests.swift`:

```swift
import Testing
@testable import SnapKei

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var storage: [String: String] = [:]
    func save(_ value: String, account: String) throws { storage[account] = value }
    func read(account: String) throws -> String? { storage[account] }
    func delete(account: String) throws { storage[account] = nil }
}

@Suite("ByokKeyStore")
struct ByokKeyStoreTests {

    @Test func saveAndLoad_roundTrips() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveAnthropicKey("sk-ant-test-123")
        #expect(try store.loadAnthropicKey() == "sk-ant-test-123")
        #expect(store.hasAnthropicKey())
    }

    @Test func save_trimsWhitespace() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveAnthropicKey("  sk-ant-x \n")
        #expect(try store.loadAnthropicKey() == "sk-ant-x")
    }

    @Test func save_emptyString_deletesKey() throws {
        let backing = InMemorySecretStore()
        let store = ByokKeyStore(store: backing)
        try store.saveAnthropicKey("sk-ant-x")
        try store.saveAnthropicKey("   ")
        #expect(try store.loadAnthropicKey() == nil)
        #expect(!store.hasAnthropicKey())
    }

    @Test func delete_removesKey() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveAnthropicKey("sk-ant-x")
        try store.deleteAnthropicKey()
        #expect(try store.loadAnthropicKey() == nil)
    }

    @Test func keys_areScopedByCurrentUser() throws {
        let backing = InMemorySecretStore()
        nonisolated(unsafe) var currentUser = "user-a"
        let store = ByokKeyStore(store: backing, userIDProvider: { currentUser })
        try store.saveAnthropicKey("sk-ant-a")

        currentUser = "user-b"
        #expect(try store.loadAnthropicKey() == nil)
        try store.saveAnthropicKey("sk-ant-b")

        currentUser = "user-a"
        #expect(try store.loadAnthropicKey() == "sk-ant-a")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the standard test command (or just this suite via `-only-testing:SnapKeiTests/ByokKeyStoreTests`).
Expected: compile FAILURE — `cannot find 'ByokKeyStore' in scope`.

- [ ] **Step 3: Implement ByokKeyStore**

Create `SnapKei/Data/Settings/ByokKeyStore.swift`:

```swift
import Foundation

/// Stores the user's own (BYOK) Anthropic API key in the Keychain.
public struct ByokKeyStore: Sendable {
    public static let anthropicAccountPrefix = "byok.anthropic.apiKey"

    private let store: SecretStore
    private let userIDProvider: @Sendable () -> String

    public init(
        store: SecretStore = KeychainService(),
        userIDProvider: @escaping @Sendable () -> String = {
            UserDefaults.standard.string(forKey: SyncCursorStore.cachedAppleSubKey) ?? "_anonymous"
        }
    ) {
        self.store = store
        self.userIDProvider = userIDProvider
    }

    private var account: String { "\(Self.anthropicAccountPrefix).\(userIDProvider())" }

    public func saveAnthropicKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try store.delete(account: account)
        } else {
            try store.save(trimmed, account: account)
        }
    }

    public func loadAnthropicKey() throws -> String? {
        try store.read(account: account)
    }

    public func deleteAnthropicKey() throws {
        try store.delete(account: account)
    }

    public func hasAnthropicKey() -> Bool {
        ((try? store.read(account: account)) ?? nil)?.isEmpty == false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS (4 new tests).

- [ ] **Step 5: Wire the provider in SnapKeiApp**

Replace `SnapKei/App/SnapKeiApp.swift:79`:

```swift
        let directService = ClaudeVisionService(apiKeyProvider: {
            try ByokKeyStore().loadAnthropicKey() ?? ""
        })
```

(`apiKeyProvider` is `@Sendable () throws -> String`; `ClaudeVisionService` already throws `missingAPIKey` on empty — unchanged behavior when no key is stored.)

- [ ] **Step 6: BYOK entry UI in AISettingsSection**

In `SnapKei/Presentation/Settings/AISettingsSection.swift`:

(a) Add state + store after the existing `@State private var testResult: String?` (line 10):

```swift
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyStatusMessage: String?
    private let keyStore: ByokKeyStore
```

(b) Add `keyStore: ByokKeyStore = ByokKeyStore()` as the last init parameter and `self.keyStore = keyStore` in the body (existing call site in `SettingsView` needs no change thanks to the default).

(c) Replace the placeholder block (lines 41–44):

```swift
                TextField("Anthropic model", text: $ai.anthropicModel).onSubmit(onCommit)
                Text("API Key は今後の BYOK 画面で Keychain 保存します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

with:

```swift
                TextField("Anthropic model", text: $ai.anthropicModel).onSubmit(onCommit)

                SecureField("Anthropic API Key (sk-ant-…)", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(hasStoredKey ? "API Key を更新" : "API Key を保存") {
                    do {
                        try keyStore.saveAnthropicKey(apiKeyInput)
                        apiKeyInput = ""
                        hasStoredKey = keyStore.hasAnthropicKey()
                        keyStatusMessage = "Keychain に保存しました"
                    } catch {
                        keyStatusMessage = "保存に失敗しました"
                    }
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasStoredKey {
                    HStack {
                        Label("API Key 保存済み", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("削除", role: .destructive) {
                            try? keyStore.deleteAnthropicKey()
                            hasStoredKey = false
                            keyStatusMessage = "API Key を削除しました"
                        }
                        .font(.caption)
                    }
                }
                if let keyStatusMessage {
                    Text(keyStatusMessage).font(.caption).foregroundStyle(.secondary)
                }
```

(d) Add to the `Section("AI 設定") { … }` closing brace chain (after the existing content, on the Section itself):

```swift
        .onAppear { hasStoredKey = keyStore.hasAnthropicKey() }
```

- [ ] **Step 7: Build + full test run**

Expected: `** TEST SUCCEEDED **`. Manual smoke (optional but recommended): boot simulator, Settings → AI 設定 → 自前 API Key → save a dummy key → relaunch → "API Key 保存済み" persists.

- [ ] **Step 8: Commit (ask user first)**

```bash
git add SnapKei/Data/Settings/ByokKeyStore.swift SnapKeiTests/ByokKeyStoreTests.swift SnapKei/App/SnapKeiApp.swift SnapKei/Presentation/Settings/AISettingsSection.swift
git commit -m "feat: BYOK Anthropic API key storage in Keychain with settings UI"
```

---

### Task 3: Sync cursor — per-current-user keying (fixes user-switch data skip)

**Background:** `SnapKeiApp.swift:50` captures the user ID **once at app init**. If user A logs out and user B logs in within the same launch, the cursor still points at A's key → B's pulls are mis-cursored. Fix: resolve the user ID lazily on every access. `AuthService.logout()` removes the `LLMGatewayKit.cachedAppleSub` UserDefaults key, and login rewrites it — reading that key lazily is the correct, main-actor-free signal.

**Files:**
- Modify: `SnapKei/Data/Sync/SyncCursorStore.swift`
- Test: `SnapKeiTests/SyncCursorStoreTests.swift` (create)
- Modify: `SnapKei/App/SnapKeiApp.swift:50`

- [ ] **Step 1: Write the failing test**

Create `SnapKeiTests/SyncCursorStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("SyncCursorStore")
struct SyncCursorStoreTests {

    private func makeSuite() -> UserDefaults {
        let suite = UserDefaults(suiteName: "SyncCursorStoreTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func cursor_isIsolatedPerUser() {
        let suite = makeSuite()
        nonisolated(unsafe) var currentUser = "user-a"
        let store = SyncCursorStore(suite: suite, userIDProvider: { currentUser })

        let dateA = Date(timeIntervalSince1970: 1_000)
        store.lastPushedAt = dateA
        #expect(store.lastPushedAt == dateA)

        currentUser = "user-b"
        #expect(store.lastPushedAt == nil)   // user B starts fresh

        currentUser = "user-a"
        #expect(store.lastPushedAt == dateA) // user A's cursor survives
    }

    @Test func reset_onlyClearsCurrentUser() {
        let suite = makeSuite()
        nonisolated(unsafe) var currentUser = "user-a"
        let store = SyncCursorStore(suite: suite, userIDProvider: { currentUser })
        store.lastPushedAt = Date(timeIntervalSince1970: 1_000)
        currentUser = "user-b"
        store.lastPushedAt = Date(timeIntervalSince1970: 2_000)

        store.reset()
        #expect(store.lastPushedAt == nil)

        currentUser = "user-a"
        #expect(store.lastPushedAt == Date(timeIntervalSince1970: 1_000))
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure** (`SyncCursorStore` has no `userIDProvider` init).

- [ ] **Step 3: Rework SyncCursorStore**

Replace the full contents of `SnapKei/Data/Sync/SyncCursorStore.swift`:

```swift
import Foundation

public final class SyncCursorStore: @unchecked Sendable {
    /// Mirrors LLMGatewayKit AuthService.Keys.cachedAppleSub — the stable per-Apple-account
    /// identifier that AuthService writes on login and removes on logout.
    public static let cachedAppleSubKey = "LLMGatewayKit.cachedAppleSub"

    private let suite: UserDefaults
    private let userIDProvider: @Sendable () -> String

    public init(
        suite: UserDefaults = .standard,
        userIDProvider: @escaping @Sendable () -> String = {
            UserDefaults.standard.string(forKey: SyncCursorStore.cachedAppleSubKey) ?? "_anonymous"
        }
    ) {
        self.suite = suite
        self.userIDProvider = userIDProvider
    }

    private var key: String { "SnapKei.sync.lastPushedAt.\(userIDProvider())" }

    public var lastPushedAt: Date? {
        get { suite.object(forKey: key) as? Date }
        set { suite.set(newValue, forKey: key) }
    }

    public func reset() {
        suite.removeObject(forKey: key)
    }
}
```

- [ ] **Step 4: Update the call site**

Replace `SnapKei/App/SnapKeiApp.swift:50`:

```swift
        let cursor = SyncCursorStore()
```

(The default provider tracks login/logout via the shared UserDefaults key; the old `auth.currentUser?.id ?? auth.cachedAppleSub ?? "_anonymous"` init-time snapshot is removed.)

- [ ] **Step 5: Run full tests — expect PASS** (2 new tests; existing suite green).

- [ ] **Step 6: Commit (ask user first)**

```bash
git add SnapKei/Data/Sync/SyncCursorStore.swift SnapKeiTests/SyncCursorStoreTests.swift SnapKei/App/SnapKeiApp.swift
git commit -m "fix: sync cursor resolves current user lazily so account switches do not skip pulls"
```

---

### Task 4: Sync layer unit tests + hide soft-deleted FixedAssets

**Background:** `SnapKeiChangeCollector`/`SnapKeiMerger` have zero tests. Also `FixedAssetSection`'s `@Query` shows assets with `deletedAt != nil` (remote tombstones become visible ghosts).

**Files:**
- Test: `SnapKeiTests/SnapKeiMergerTests.swift` (create)
- Test: `SnapKeiTests/SnapKeiChangeCollectorTests.swift` (create)
- Modify: `SnapKei/Presentation/Settings/FixedAssetSection.swift:5`

- [ ] **Step 1: Write merger tests**

Create `SnapKeiTests/SnapKeiMergerTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
import LLMGatewayKit
@testable import SnapKei

@Suite("SnapKeiMerger", .serialized)
struct SnapKeiMergerTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try SnapKeiModelContainer.inMemory()
        TestMergerContainerRetainer.retain(container)
        return container.mainContext
    }

    private func entryPayloadData(syncId: UUID, updatedAt: Date, isVoided: Bool = false, amount: Int = 1100) throws -> Data {
        let entry = JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: Date(timeIntervalSince1970: 0),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: amount, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "リモート商店", transactionDescription: "クラウド由来",
            sourceType: .manual, updatedAt: updatedAt, syncId: syncId, isVoided: isVoided
        )
        return try JSONEncoder.snapkeiSync.encode(JournalEntryPayload(from: entry))
    }

    @MainActor
    @Test func apply_insertsNewJournalEntry() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let data = try entryPayloadData(syncId: syncId, updatedAt: Date())

        try await merger.apply(SyncEnvelope(entityType: "JournalEntry", entityID: syncId.uuidString, modifiedAt: Date(), data: data))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.syncId == syncId)
        #expect(fetched.first?.counterpartyName == "リモート商店")
    }

    @MainActor
    @Test func apply_olderPayload_doesNotOverwriteNewerLocal() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let newer = Date()
        let older = newer.addingTimeInterval(-3600)

        try await merger.apply(SyncEnvelope(entityType: "JournalEntry", entityID: syncId.uuidString, modifiedAt: newer, data: entryPayloadData(syncId: syncId, updatedAt: newer, amount: 2200)))
        try await merger.apply(SyncEnvelope(entityType: "JournalEntry", entityID: syncId.uuidString, modifiedAt: older, data: entryPayloadData(syncId: syncId, updatedAt: older, amount: 1100)))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.amountIncludingTax == 2200)
    }

    @MainActor
    @Test func apply_voidedRemoteEntry_insertsAsVoided() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let data = try entryPayloadData(syncId: syncId, updatedAt: Date(), isVoided: true)

        try await merger.apply(SyncEnvelope(entityType: "JournalEntry", entityID: syncId.uuidString, modifiedAt: Date(), data: data))

        let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(fetched.first?.isVoided == true)
    }

    @MainActor
    @Test func apply_fixedAsset_insertAndTombstoneUpdate() async throws {
        let context = try makeContext()
        let merger = SnapKeiMerger(context: context)
        let syncId = UUID()
        let t0 = Date()
        let asset = FixedAsset(
            assetName: "リモートPC", assetCategoryCode: "PC",
            acquisitionDate: t0, serviceStartDate: t0, acquisitionAmount: 300_000,
            usefulLifeYears: 4, treatment: .normalDepreciation,
            syncId: syncId, updatedAt: t0
        )
        let insertData = try JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
        try await merger.apply(SyncEnvelope(entityType: "FixedAsset", entityID: syncId.uuidString, modifiedAt: t0, data: insertData))
        #expect(try context.fetch(FetchDescriptor<FixedAsset>()).count == 1)

        asset.deletedAt = t0.addingTimeInterval(60)
        asset.updatedAt = t0.addingTimeInterval(60)
        let deleteData = try JSONEncoder.snapkeiSync.encode(FixedAssetPayload(from: asset))
        try await merger.apply(SyncEnvelope(entityType: "FixedAsset", entityID: syncId.uuidString, modifiedAt: asset.updatedAt, data: deleteData))

        let fetched = try context.fetch(FetchDescriptor<FixedAsset>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.deletedAt != nil)
    }
}

@MainActor
private enum TestMergerContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
```

- [ ] **Step 2: Write collector tests**

Create `SnapKeiTests/SnapKeiChangeCollectorTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import SnapKei

@Suite("SnapKeiChangeCollector", .serialized)
struct SnapKeiChangeCollectorTests {

    @MainActor
    private func makeFixture() throws -> (ModelContext, SyncCursorStore, SnapKeiChangeCollector) {
        let container = try SnapKeiModelContainer.inMemory()
        TestCollectorContainerRetainer.retain(container)
        let suite = UserDefaults(suiteName: "CollectorTests-\(UUID().uuidString)")!
        let cursor = SyncCursorStore(suite: suite, userIDProvider: { "test-user" })
        let collector = SnapKeiChangeCollector(context: container.mainContext, cursor: cursor)
        return (container.mainContext, cursor, collector)
    }

    private func insertEntry(_ context: ModelContext, updatedAt: Date) {
        context.insert(JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "店", transactionDescription: "件",
            sourceType: .manual, updatedAt: updatedAt
        ))
    }

    @MainActor
    @Test func collectPending_returnsOnlyChangesAfterCursor() async throws {
        let (context, cursor, collector) = try makeFixture()
        let cutoff = Date()
        insertEntry(context, updatedAt: cutoff.addingTimeInterval(-60))
        insertEntry(context, updatedAt: cutoff.addingTimeInterval(60))
        try context.save()

        cursor.lastPushedAt = cutoff
        let envelopes = try await collector.collectPending()
        #expect(envelopes.count == 1)
    }

    @MainActor
    @Test func markSynced_advancesCursorToLatestModifiedAt() async throws {
        let (context, cursor, collector) = try makeFixture()
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        insertEntry(context, updatedAt: t1)
        insertEntry(context, updatedAt: t2)
        try context.save()

        let envelopes = try await collector.collectPending()
        try await collector.markSynced(envelopes)
        #expect(cursor.lastPushedAt == t2)
    }
}

@MainActor
private enum TestCollectorContainerRetainer {
    static var containers: [ModelContainer] = []
    static func retain(_ container: ModelContainer) { containers.append(container) }
}
```

- [ ] **Step 3: Run tests** — expect PASS (the production code already implements this behavior; these are characterization tests). If `SyncEnvelope`'s initializer differs (argument order/labels), check `/Users/lee/workspace/LLMGatewayKit/Sources/LLMGatewayKit/Sync/` and adjust the test, not the production code.

- [ ] **Step 4: Hide soft-deleted assets in Settings**

In `SnapKei/Presentation/Settings/FixedAssetSection.swift`, replace line 5:

```swift
    @Query(
        filter: #Predicate<FixedAsset> { $0.deletedAt == nil },
        sort: \FixedAsset.acquisitionDate, order: .reverse
    ) private var assets: [FixedAsset]
```

- [ ] **Step 5: Full test run** — expect `** TEST SUCCEEDED **` (~82+ tests).

- [ ] **Step 6: Commit (ask user first)**

```bash
git add SnapKeiTests/SnapKeiMergerTests.swift SnapKeiTests/SnapKeiChangeCollectorTests.swift SnapKei/Presentation/Settings/FixedAssetSection.swift
git commit -m "test: cover sync merger/collector; hide soft-deleted fixed assets in settings"
```

---

### Task 5: First-run onboarding + in-app disclaimer (税理士法 positioning)

**Background:** README has a "not tax advice" disclaimer but the app never shows it. The app suggests asset treatments and deduction amounts — it must present itself as a **self-filing support tool** with user-driven decisions. Also there is no first-run experience at all.

**Files:**
- Modify: `SnapKei/Data/Settings/AppSettings.swift`
- Test: `SnapKeiTests/AppSettingsTests.swift` (append)
- Create: `SnapKei/Presentation/Legal/LegalTexts.swift`
- Create: `SnapKei/Presentation/Legal/DisclaimerView.swift`
- Create: `SnapKei/Presentation/Legal/OnboardingView.swift`
- Modify: `SnapKei/Presentation/RootView.swift`
- Modify: `SnapKei/Presentation/Settings/SettingsView.swift` (アプリ情報 section)

- [ ] **Step 1: Write the failing test (AppSettings flag)**

Append to `SnapKeiTests/AppSettingsTests.swift` (inside the existing suite):

```swift
    @Test func hasCompletedOnboarding_defaultsFalse_andRoundTrips() {
        let suite = UserDefaults(suiteName: "AppSettingsTests-onboarding-\(UUID().uuidString)")!
        #expect(AppSettings.load(defaults: suite).hasCompletedOnboarding == false)

        var settings = AppSettings.load(defaults: suite)
        settings.hasCompletedOnboarding = true
        settings.save(defaults: suite)
        #expect(AppSettings.load(defaults: suite).hasCompletedOnboarding == true)
    }
```

(If the existing suite lacks `import Foundation`, add it.)

- [ ] **Step 2: Run — expect compile failure** (`hasCompletedOnboarding` not a member).

- [ ] **Step 3: Add the field to AppSettings**

In `SnapKei/Data/Settings/AppSettings.swift`:
- Add property after `lateEntryThresholdDays` (line 8): `public var hasCompletedOnboarding: Bool`
- `default`: add `hasCompletedOnboarding: false`
- `init`: add final parameter `hasCompletedOnboarding: Bool = false` and assignment
- `Keys`: add `nonisolated static let hasCompletedOnboarding = "app.hasCompletedOnboarding"`
- `load`: add `hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding)`
- `save`: add `defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)`

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Create the legal texts**

Create `SnapKei/Presentation/Legal/LegalTexts.swift`:

```swift
import Foundation

public enum LegalTexts {
    public static let disclaimerTitle = "免責事項"

    public static let disclaimer = """
    SnapKei は記帳補助ツールであり、税務相談・税務代理サービスではありません。

    ・本アプリが表示する勘定科目・資産処理・控除額などは、法令の一般的な説明に基づく参考情報です。利用者個別の事情に対する税務判断を行うものではありません。
    ・勘定科目の選択、資産の処理方法、控除の適用などの最終判断は、利用者ご自身が行ってください。
    ・確定申告は利用者ご自身の責任で行っていただきます。本アプリが申告を代理することはありません。
    ・個別の税務判断が必要な場合は、税務署または税理士にご相談ください。
    ・本アプリの利用により生じたいかなる損害についても、開発者は責任を負いません。
    """

    public static let onboardingAgreeLabel = "上記の免責事項に同意します"
}
```

- [ ] **Step 6: Create DisclaimerView**

Create `SnapKei/Presentation/Legal/DisclaimerView.swift`:

```swift
import SwiftUI

public struct DisclaimerView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            Text(LegalTexts.disclaimer)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(LegalTexts.disclaimerTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 7: Create OnboardingView**

Create `SnapKei/Presentation/Legal/OnboardingView.swift`:

```swift
import SwiftUI

public struct OnboardingView: View {
    @State private var page = 0
    @State private var agreed = false
    @State private var businessName = ""
    @State private var ownerName = ""

    private let onComplete: (_ businessName: String, _ ownerName: String) -> Void

    public init(onComplete: @escaping (_ businessName: String, _ ownerName: String) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            disclaimerPage.tag(1)
            setupPage.tag(2)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground))
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("SnapKei へようこそ")
                .font(.largeTitle.bold())
            Text("レシートを撮影するだけで、青色申告に対応した複式簿記の仕訳を作成します。帳簿づけから決算準備まで、個人事業主の記帳をサポートします。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("次へ") { withAnimation { page = 1 } }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 48)
        }
    }

    private var disclaimerPage: some View {
        VStack(spacing: 16) {
            Text(LegalTexts.disclaimerTitle)
                .font(.title.bold())
                .padding(.top, 48)
            ScrollView {
                Text(LegalTexts.disclaimer)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            Toggle(LegalTexts.onboardingAgreeLabel, isOn: $agreed)
                .padding(.horizontal, 24)
            Button("次へ") { withAnimation { page = 2 } }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
                .padding(.bottom, 48)
        }
    }

    private var setupPage: some View {
        VStack(spacing: 16) {
            Text("事業者情報")
                .font(.title.bold())
                .padding(.top, 48)
            Text("青色申告決算書などの書類に使用します。あとから設定画面で変更できます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Form {
                TextField("屋号（任意）", text: $businessName)
                TextField("氏名", text: $ownerName)
            }
            .frame(maxHeight: 180)
            .scrollDisabled(true)
            Spacer()
            Button("はじめる") { onComplete(businessName, ownerName) }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
                .padding(.bottom, 48)
        }
    }
}
```

- [ ] **Step 8: Present on first launch from RootView**

In `SnapKei/Presentation/RootView.swift`, add state above `body` (after line 4):

```swift
    @State private var showOnboarding = !AppSettings.load().hasCompletedOnboarding
```

and attach to the `TabView` (after the closing brace of `TabView { … }`):

```swift
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { businessName, ownerName in
                var settings = AppSettings.load()
                if !businessName.isEmpty { settings.businessName = businessName }
                if !ownerName.isEmpty { settings.ownerName = ownerName }
                settings.hasCompletedOnboarding = true
                settings.save()
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
```

- [ ] **Step 9: Permanent disclaimer access in Settings**

In `SnapKei/Presentation/Settings/SettingsView.swift`, replace the アプリ情報 section (lines 61–66):

```swift
                Section("アプリ情報") {
                    Text("SnapKei v0.1.0")
                    Text("青色申告対応 仕訳作成アプリ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink(LegalTexts.disclaimerTitle) { DisclaimerView() }
                }
```

- [ ] **Step 10: Build + full tests + manual smoke**

Expected: `** TEST SUCCEEDED **`. Manual: delete app from simulator → run → onboarding appears → 同意 required to proceed → completes once and never reappears.

- [ ] **Step 11: Commit (ask user first)**

```bash
git add SnapKei/Data/Settings/AppSettings.swift SnapKeiTests/AppSettingsTests.swift SnapKei/Presentation/Legal/ SnapKei/Presentation/RootView.swift SnapKei/Presentation/Settings/SettingsView.swift
git commit -m "feat: first-run onboarding with disclaimer consent and business info setup"
```

---

### Task 6: Show sync toast app-wide (currently Settings-only)

**Files:**
- Modify: `SnapKei/Presentation/Settings/SettingsView.swift` (remove overlay, lines 88–90)
- Modify: `SnapKei/Presentation/RootView.swift`

- [ ] **Step 1: Remove the Settings-local overlay**

In `SettingsView.swift` delete:

```swift
            .overlay(alignment: .top) {
                SyncToastView(observer: syncObserver)
            }
```

(Keep the `@Environment(SyncStatusObserver.self) private var syncObserver` property — delete it only if the compiler reports it unused.)

- [ ] **Step 2: Add the overlay at root**

In `RootView.swift` add the environment property after `captureViewModel` (line 4):

```swift
    @Environment(SyncStatusObserver.self) private var syncObserver
```

with `import LLMGatewayKit` added at the top (line 1), and attach to the `TabView` (alongside the Task 5 modifier):

```swift
        .overlay(alignment: .top) {
            SyncToastView(observer: syncObserver)
        }
```

**Note:** `#Preview { RootView() }` at the bottom of RootView will now crash previews without the environment — change it to:

```swift
#Preview {
    Text("RootView requires app environment")
}
```

- [ ] **Step 3: Build + run tests** — expect green.

- [ ] **Step 4: Commit (ask user first)**

```bash
git add SnapKei/Presentation/RootView.swift SnapKei/Presentation/Settings/SettingsView.swift
git commit -m "feat: show sync toast app-wide via root overlay"
```

---

### Task 7: Placeholder app icon (unblocks archive/TestFlight)

**Background:** `AppIcon.appiconset` contains only `Contents.json` — archiving for App Store will fail validation. Generate a decent placeholder programmatically; replace with real artwork later.

**Files:**
- Create: `tools/generate_app_icon.swift`
- Create: `SnapKei/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (generated)
- Modify: `SnapKei/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Create the generator script**

Create `tools/generate_app_icon.swift`:

```swift
#!/usr/bin/env swift
// Generates a 1024x1024 opaque PNG placeholder app icon (receipt + red seal "計").
// Run from repo root:  swift tools/generate_app_icon.swift
import AppKit

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: 1024, height: 1024)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background gradient (deep indigo -> teal)
let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.50, blue: 0.52, alpha: 1),
    ]
)!
gradient.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -60)

// White receipt card
let card = NSBezierPath(roundedRect: NSRect(x: 272, y: 176, width: 480, height: 672), xRadius: 48, yRadius: 48)
NSColor.white.setFill()
card.fill()

// Receipt text lines
NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
for i in 0..<4 {
    let width: CGFloat = (i == 3) ? 208 : 352
    NSBezierPath(
        roundedRect: NSRect(x: 336, y: 712 - CGFloat(i) * 96, width: width, height: 32),
        xRadius: 16, yRadius: 16
    ).fill()
}

// Red seal with 計
NSColor(calibratedRed: 0.79, green: 0.16, blue: 0.16, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 552, y: 224, width: 176, height: 176)).fill()
let text = NSAttributedString(string: "計", attributes: [
    .font: NSFont.boldSystemFont(ofSize: 104),
    .foregroundColor: NSColor.white,
])
let textSize = text.size()
text.draw(at: NSPoint(x: 640 - textSize.width / 2, y: 312 - textSize.height / 2))

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: "SnapKei/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
try! png.write(to: out)
print("Wrote \(out.path) (\(png.count) bytes)")
```

- [ ] **Step 2: Generate**

Run from repo root: `swift tools/generate_app_icon.swift`
Expected: `Wrote SnapKei/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. Verify: `file SnapKei/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` reports `1024 x 1024` PNG.

- [ ] **Step 3: Point Contents.json at the file**

Read the current `SnapKei/Assets.xcassets/AppIcon.appiconset/Contents.json`, then overwrite with:

```json
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

(Dark/tinted variants are optional; omitting them falls back to the single icon.)

- [ ] **Step 4: Build** — expect success with no asset-catalog warnings about AppIcon. Run app in simulator and confirm the icon shows on the home screen.

- [ ] **Step 5: Commit (ask user first)**

```bash
git add tools/generate_app_icon.swift SnapKei/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat: add generated placeholder app icon"
```

---

### Task 8: Privacy manifest, export-compliance flag, localization regions

**Files:**
- Create: `SnapKei/PrivacyInfo.xcprivacy`
- Modify: `SnapKei.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the privacy manifest**

Create `SnapKei/PrivacyInfo.xcprivacy` (auto-included by the synchronized root group):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherFinancialInfo</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhotosorVideos</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Declare export compliance**

In `project.pbxproj`, next to each of the two `INFOPLIST_KEY_NSCameraUsageDescription` lines (405 and 447), add:

```
				INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
```

(SnapKei uses only HTTPS + OS Keychain — exempt encryption.)

- [ ] **Step 3: Fix localization regions**

In `project.pbxproj` replace:

```
			developmentRegion = en;
```
with
```
			developmentRegion = ja;
```

and the `knownRegions` list:

```
			knownRegions = (
				en,
				Base,
			);
```
with
```
			knownRegions = (
				en,
				ja,
				"zh-Hans",
				Base,
			);
```

- [ ] **Step 4: Build + test** — expect green; confirm `PrivacyInfo.xcprivacy` appears in build products: `xcodebuild ... build 2>&1 | grep -i xcprivacy` shows a copy/process step (or verify it exists inside the built `.app`).

- [ ] **Step 5: Commit (ask user first)**

```bash
git add SnapKei/PrivacyInfo.xcprivacy SnapKei.xcodeproj/project.pbxproj
git commit -m "chore: add privacy manifest, export-compliance flag, ja/zh-Hans regions"
```

---

### Task 9: Privacy policy + support documents

App Store Connect requires a privacy policy URL and a support URL. Host these from the repo (GitHub Pages or repo URL once public). Writing them now unblocks the submission checklist.

**Files:**
- Create: `docs/legal/privacy-policy.md`
- Create: `docs/legal/support.md`
- Modify: `README.md`

- [ ] **Step 1: Create the privacy policy**

Create `docs/legal/privacy-policy.md`:

```markdown
# SnapKei プライバシーポリシー

最終更新日: 2026-06-08

SnapKei（以下「本アプリ」）は、個人事業主向けの記帳補助アプリです。本ポリシーは、本アプリが取り扱う情報と利用目的を説明します。

## 収集・処理する情報

| 情報 | 保存場所 | 目的 |
|---|---|---|
| レシート画像・PDF | 端末内（アプリ専用領域） | 仕訳作成・証憑保存（電子帳簿保存法対応） |
| レシート画像（解析時） | AI 解析サーバーへ送信 | 文字認識・仕訳候補の生成（処理後は保存されません） |
| 仕訳・固定資産データ | 端末内。クラウド同期を有効にした場合は当社サーバー | 記帳機能・端末間バックアップ |
| Apple アカウント識別子・メールアドレス | 当社サーバー | サインイン（Sign in with Apple）・アカウント管理 |
| 屋号・氏名 | 端末内 | 帳簿・レポート表示、申告準備の補助 |
| 自前 API キー（BYOK） | 端末の Keychain のみ | 利用者自身の AI プロバイダ接続。SnapKei のサーバーには送信・同期しませんが、API 認証のため選択した AI プロバイダへ HTTPS で送信されます |

## 第三者への提供

- AI 解析には外部の AI プロバイダ（内蔵 AI 利用時は当社ゲートウェイ経由、BYOK 時は利用者が設定したプロバイダ）を使用します。
- 課金処理には RevenueCat を使用します。
- 法令に基づく場合を除き、個人情報を第三者に販売・提供しません。
- 広告目的のトラッキングは行いません。

## データの削除

- 端末内データはアプリの削除により消去されます（税法上の帳簿保存義務は利用者の責任で履行してください）。
- クラウド同期データの削除とアカウント削除は、リリース時点でアプリ内に実装済みの手段、または下記サポート窓口からの依頼により対応します。App Store 提出前に、実装済みの削除フローに合わせて本項を再確認してください。

## お問い合わせ

下記サポート窓口までご連絡ください。
```

- [ ] **Step 2: Create the support page**

Create `docs/legal/support.md`:

```markdown
# SnapKei サポート

## お問い合わせ

- 不具合報告・機能要望: GitHub Issues（リポジトリ公開後）
- メール: zhang-xiaotian@earth-eyes.co.jp

## よくある質問

**Q. 内蔵 AI と自前 API Key の違いは？**
内蔵 AI はサインインのみで利用できる解析チャネルです。自前 API Key（BYOK）では、ご自身の Anthropic API キーを端末の Keychain に保存し、直接 API を呼び出します。

**Q. クラウド同期のデータはどこに保存されますか？**
有料プランで有効化した場合のみ、当社サーバーのストレージに保存されます。設定からいつでも無効化・削除できます。

**Q. 本アプリだけで確定申告は完結しますか？**
現バージョンは記帳・帳簿づけと決算準備の支援が中心です。申告書の提出は e-Tax 等で利用者ご自身が行ってください。
```

- [ ] **Step 3: Link from README**

In `README.md`, in the `## Disclaimer` section, append:

```markdown
Privacy policy: [docs/legal/privacy-policy.md](docs/legal/privacy-policy.md) · Support: [docs/legal/support.md](docs/legal/support.md)
```

- [ ] **Step 4: Commit (ask user first)**

```bash
git add docs/legal/ README.md
git commit -m "docs: add privacy policy and support pages for App Store submission"
```

**Manual follow-up (App Store Connect, not automatable — record as TODO for the user):** enter privacy policy URL + support URL, complete the App Privacy questionnaire (matches `PrivacyInfo.xcprivacy`: financial info / photos / user ID / email, all linked, no tracking), confirm export compliance = exempt.

---

### Task 10: Align deployment target with README (26.0 → 18.5, with fallback)

**Background:** `IPHONEOS_DEPLOYMENT_TARGET = 26.0` at 6 sites (lines 223, 251, 324, 382, 412, 454) vs README "iOS 18.5+". `LLMGatewayKit` requires only `.iOS(.v18)`, so 18.5 should work unless app code uses iOS-26-only APIs.

**Files:**
- Modify: `SnapKei.xcodeproj/project.pbxproj`
- Possibly modify: `README.md` (fallback only)

- [ ] **Step 1: Lower the target**

```bash
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/IPHONEOS_DEPLOYMENT_TARGET = 18.5;/g' SnapKei.xcodeproj/project.pbxproj
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 18.5;" SnapKei.xcodeproj/project.pbxproj
```

Expected: `6`.

- [ ] **Step 2: Build + full test**

Run the standard test command.
- If `** TEST SUCCEEDED **` → done, proceed to commit.
- If the build fails with `is only available in iOS 26.0 or newer` availability errors → **fallback:** `git checkout SnapKei.xcodeproj/project.pbxproj`, then edit `README.md` line 18 from `- iOS 18.5+` to `- iOS 26+`, and record which APIs forced it (paste the error list into the commit message).

- [ ] **Step 3: Commit (ask user first)**

```bash
git add SnapKei.xcodeproj/project.pbxproj README.md
git commit -m "chore: align iOS deployment target with documented requirement"
```

---

### Task 11: Accessibility labels for icon-only controls

**Files:**
- Modify: `SnapKei/Presentation/ExpenseList/ExpenseListView.swift:54-57`

- [ ] **Step 1: Label the toolbar buttons**

Replace lines 54–57:

```swift
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showFilter = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("フィルタ")
                Button { exportCSV(viewModel: viewModel) } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("CSV を共有")
            }
```

- [ ] **Step 2: Audit for other icon-only buttons**

Run: `grep -rn "label: { Image(systemName:" SnapKei/Presentation/ | grep -v accessibilityLabel`
Add `.accessibilityLabel("…")` with an appropriate Japanese label to any remaining hits (expected: none or 1–2; use the button's visible purpose as the label).

- [ ] **Step 3: Build + test, commit (ask user first)**

```bash
git add SnapKei/Presentation/
git commit -m "fix: accessibility labels for icon-only toolbar buttons"
```

---

### Task 12: Localization catalog completeness check

**Background:** `Localizable.xcstrings` (sourceLanguage `zh-Hans`, 143 keys) — most UI text is hardcoded Japanese (fine for the ja-first v1), but the ~20 *semantic* keys (`tab.*`, `capture.*`, `settings.*`, …) must each have a `ja` translation or Japanese users see raw keys.

**Files:**
- Create: `tools/check_localizations.py`
- Modify: `SnapKei/Resources/Localizable.xcstrings`

- [ ] **Step 1: Create the check script**

Create `tools/check_localizations.py`:

```python
#!/usr/bin/env python3
"""Report semantic xcstrings keys (dotted identifiers) missing a ja translation."""
import json
import re
import sys

PATH = "SnapKei/Resources/Localizable.xcstrings"
SEMANTIC = re.compile(r"^[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$")

with open(PATH) as f:
    catalog = json.load(f)

missing = []
for key, value in sorted(catalog["strings"].items()):
    if not SEMANTIC.match(key):
        continue
    ja = value.get("localizations", {}).get("ja", {}).get("stringUnit", {})
    if ja.get("state") != "translated" or not ja.get("value"):
        missing.append(key)

if missing:
    print("Semantic keys missing ja translation:")
    for key in missing:
        print(f"  {key}")
    sys.exit(1)
print("OK: all semantic keys have ja translations.")
```

- [ ] **Step 2: Run it**

Run: `python3 tools/check_localizations.py`
If it prints `OK`, skip to Step 4.

- [ ] **Step 3: Fill any reported keys**

For each reported key, add/complete the `ja` localization in `SnapKei/Resources/Localizable.xcstrings` following the existing entry shape, e.g. for `tab.home`:

```json
    "tab.home" : {
      "localizations" : {
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "ホーム" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "首页" } }
      }
    },
```

Known expected values if missing: `tab.home`→ホーム, `tab.capture`→撮影, `tab.list`→一覧, `tab.settings`→設定. Re-run the script until it exits 0.

- [ ] **Step 4: Build + test, commit (ask user first)**

```bash
git add tools/check_localizations.py SnapKei/Resources/Localizable.xcstrings
git commit -m "chore: localization completeness check, fill missing ja semantic keys"
```

---

### Task 13: Final verification sweep

- [ ] **Step 1: Full clean test run**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO clean test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`, ≥85 tests (76 baseline + ~9 new), 0 failures.

- [ ] **Step 2: Archive smoke (validates icon + manifest + signing path)**

```bash
xcodebuild -scheme SnapKei -destination 'generic/platform=iOS' -archivePath /tmp/SnapKei.xcarchive archive 2>&1 | tail -5
```

Expected: `** ARCHIVE SUCCEEDED **`. (Signing errors about distribution certificates are acceptable at this stage; asset/manifest errors are not.)

- [ ] **Step 3: Manual smoke checklist (simulator)**

- Fresh install → onboarding → disclaimer consent gate works
- Settings → AI 設定 → BYOK key save / delete round-trips
- Settings → アプリ情報 → 免責事項 opens
- Capture → save entry → appears in 一覧 → CSV share sheet opens
- App icon visible on home screen

- [ ] **Step 4: Report results to the user** — list any deviations, then stop. Do NOT push.
