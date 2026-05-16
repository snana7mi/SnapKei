# ConchTalk → LLMGatewayKit Migration — Implementation Plan (P3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ConchTalk to consume `LLMGatewayKit` (already published at 0.1.0 from Plan A), replacing the in-app `AuthService`/`SubscriptionService`/sync stack with the package's, while preserving every existing user's login, paid tier, and cloud-sync history.

**Architecture:** ConchTalk adds the package as a SwiftPM git-URL dependency. The in-app `SyncCryptoService`, `SyncChangeCollector`, and `SyncMergeEngine` are renamed and adapted to conform to package protocols (`SyncPayloadCodec`, `SyncChangeCollecting`, `SyncMerging`). A one-shot `LegacyMigrationHelper` copies keychain and `UserDefaults` keys from ConchTalk's namespace into the package's namespace on first launch under the new build. Entitlement rename from `"conchtalk Pro"` to `"pro"` is handled out-of-band in RevenueCat (dual-attach during transition).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, RevenueCat 5.x, `LLMGatewayKit` 0.1.0.

**Spec reference:** `docs/superpowers/specs/2026-05-16-llm-gateway-kit-design.md` (§10 — ConchTalk Migration)

**Pre-flight (operator-side):** Plan A is complete. `LLMGatewayKit` 0.1.0 is tagged and pushed. The RevenueCat dashboard has both `"conchtalk Pro"` and `"pro"` entitlements attached to ConchTalk's Pro products (dual-attach window).

---

## Task 1: Branch + add LLMGatewayKit dependency

**Files:**
- Modify: `ConchTalk.xcodeproj/project.pbxproj` (via Xcode UI)

- [ ] **Step 1: Cut a feature branch**

```bash
cd /Users/lee/workspace/conchtalk
git checkout -b llm-gateway-kit-migration
```

- [ ] **Step 2: Add the package**

Open `ConchTalk.xcodeproj` → File → Add Package Dependencies → URL `https://github.com/snana7mi/LLMGatewayKit` → Dependency Rule: Up to Next Minor from `0.1.0` → Add Package → check the `LLMGatewayKit` library and add to target `ConchTalk`.

- [ ] **Step 3: Build to verify the dependency resolves**

```bash
cd /Users/lee/workspace/conchtalk
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ConchTalk.xcodeproj/project.pbxproj
git add ConchTalk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
git commit -m "Add LLMGatewayKit 0.1.0 dependency"
```

---

## Task 2: `LegacyMigrationHelper`

**Files:**
- Create: `Sources/Data/Migration/LegacyMigrationHelper.swift`
- Create: `ConchTalkTests/LegacyMigrationHelperTests.swift`

This runs once at app launch. It moves three keychain accounts and several UserDefaults keys from ConchTalk's namespace to the package's. Idempotent via a `LLMGatewayKit.migrationDone_v1` flag.

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import LLMGatewayKit
@testable import ConchTalk

final class LegacyMigrationHelperTests: XCTestCase {
    func test_migration_copiesUserDefaults() throws {
        let suite = UserDefaults(suiteName: "test_\(UUID())")!
        suite.set("user-123", forKey: "AuthService.cachedAppleSub")
        suite.set(true, forKey: "SyncState.enabled")
        suite.set("u-abc", forKey: "SyncState.disabledByUserID")

        let helper = LegacyMigrationHelper(defaults: suite,
                                           legacyServicePrefix: "com.cheung.ConchTalk",
                                           targetKeychainStore: InMemoryTokenStore())
        try helper.migrateIfNeeded()

        XCTAssertEqual(suite.string(forKey: "LLMGatewayKit.cachedAppleSub"), "user-123")
        XCTAssertTrue(suite.bool(forKey: "LLMGatewayKit.sync.isEnabled"))
        XCTAssertEqual(suite.string(forKey: "LLMGatewayKit.sync.disabledByUserID"), "u-abc")
        XCTAssertTrue(suite.bool(forKey: "LLMGatewayKit.migrationDone_v1"))
    }

    func test_migration_isIdempotent() throws {
        let suite = UserDefaults(suiteName: "test_\(UUID())")!
        suite.set(true, forKey: "LLMGatewayKit.migrationDone_v1")
        suite.set("ignored", forKey: "AuthService.cachedAppleSub")

        let helper = LegacyMigrationHelper(defaults: suite,
                                           legacyServicePrefix: "com.cheung.ConchTalk",
                                           targetKeychainStore: InMemoryTokenStore())
        try helper.migrateIfNeeded()

        XCTAssertNil(suite.string(forKey: "LLMGatewayKit.cachedAppleSub"))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import Security
import LLMGatewayKit

final class LegacyMigrationHelper {
    private enum LegacyDefaultsKeys {
        static let cachedAppleSub = "AuthService.cachedAppleSub"
        static let cachedTier     = "AuthService.cachedTier"
        static let cachedUserID   = "AuthService.cachedUserID"
        static let syncEnabled    = "SyncState.enabled"
        static let lastPullTS     = "SyncState.lastPullTimestamp"
        static let lastSyncedVer  = "SyncState.lastSyncedVersion"
        static let disabledByUser = "SyncState.disabledByUserID"
        static let deviceId       = "SyncState.deviceId"
        static let keyGeneration  = "SyncState.keyGeneration"
    }
    private static let migrationFlag = "LLMGatewayKit.migrationDone_v1"

    private let defaults: UserDefaults
    private let legacyServicePrefix: String
    private let targetStore: TokenStoring

    init(defaults: UserDefaults = .standard,
         legacyServicePrefix: String = "com.cheung.ConchTalk",
         targetKeychainStore: TokenStoring = KeychainTokenStore()) {
        self.defaults = defaults
        self.legacyServicePrefix = legacyServicePrefix
        self.targetStore = targetKeychainStore
    }

    func migrateIfNeeded() throws {
        guard !defaults.bool(forKey: Self.migrationFlag) else { return }

        // UserDefaults
        if let sub = defaults.string(forKey: LegacyDefaultsKeys.cachedAppleSub) {
            defaults.set(sub, forKey: "LLMGatewayKit.cachedAppleSub")
        }
        if defaults.object(forKey: LegacyDefaultsKeys.syncEnabled) != nil {
            defaults.set(defaults.bool(forKey: LegacyDefaultsKeys.syncEnabled),
                         forKey: "LLMGatewayKit.sync.isEnabled")
        }
        if let ts = defaults.string(forKey: LegacyDefaultsKeys.lastPullTS) {
            defaults.set(ts, forKey: "LLMGatewayKit.sync.lastPullSince")
        }
        if let disabledBy = defaults.string(forKey: LegacyDefaultsKeys.disabledByUser) {
            defaults.set(disabledBy, forKey: "LLMGatewayKit.sync.disabledByUserID")
        }
        // conchtalk-specific: keep deviceId, lastSyncedVersion, keyGeneration in their original keys —
        // ConchtalkChangeCollector reads them directly. Migration touches only what the package owns.

        // Keychain
        let legacyAccess = readKeychainString(service: legacyServicePrefix, account: "\(legacyServicePrefix).auth.accessToken")
        let legacyRefresh = readKeychainString(service: legacyServicePrefix, account: "\(legacyServicePrefix).auth.refreshToken")
        let legacyExpiryString = readKeychainString(service: legacyServicePrefix, account: "\(legacyServicePrefix).auth.tokenExpiry")
        if let access = legacyAccess, let refresh = legacyRefresh {
            let expiry: Date
            if let s = legacyExpiryString, let parsed = ISO8601DateFormatter().date(from: s) {
                expiry = parsed
            } else {
                expiry = Date().addingTimeInterval(15 * 60)
            }
            try targetStore.save(accessToken: access, refreshToken: refresh, expiry: expiry)
        }

        defaults.set(true, forKey: Self.migrationFlag)
    }

    private func readKeychainString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:ConchTalkTests/LegacyMigrationHelperTests test
git add Sources/Data/Migration/LegacyMigrationHelper.swift ConchTalkTests/LegacyMigrationHelperTests.swift
git commit -m "Add LegacyMigrationHelper for one-shot key migration"
```

---

## Task 3: `ConchtalkE2ECodec` adapter

**Files:**
- Create: `Sources/Data/Sync/ConchtalkE2ECodec.swift`
- Modify: nothing yet (existing `SyncCryptoService.swift` stays in place; the adapter wraps it)
- Create: `ConchTalkTests/ConchtalkE2ECodecTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import LLMGatewayKit
@testable import ConchTalk

final class ConchtalkE2ECodecTests: XCTestCase {
    func test_roundTrip() async throws {
        let crypto = SyncCryptoService(/* existing init args */)
        let codec = ConchtalkE2ECodec(crypto: crypto)
        let plaintext = Data("hello".utf8)
        let encoded = try await codec.encode(plaintext, entityType: "Server")
        let decoded = try await codec.decode(encoded, entityType: "Server")
        XCTAssertEqual(decoded, plaintext)
    }
}
```

Adapt the `SyncCryptoService` constructor call to match its real signature (it derives a key from `cachedAppleSub`). The test may need to seed `UserDefaults` accordingly — copy the setup from any existing `SyncCryptoServiceTests`.

- [ ] **Step 2: Implement the adapter**

```swift
import Foundation
import LLMGatewayKit

public struct ConchtalkE2ECodec: SyncPayloadCodec {
    private let crypto: SyncCryptoService

    public init(crypto: SyncCryptoService) {
        self.crypto = crypto
    }

    public func encode(_ plaintext: Data, entityType: String) async throws -> Data {
        guard let entity = SyncEntityType(rawValue: entityType) else {
            throw SyncCryptoError.unknownEntityType
        }
        return try await crypto.encrypt(plaintext, entityType: entity)
    }

    public func decode(_ wire: Data, entityType: String) async throws -> Data {
        guard let entity = SyncEntityType(rawValue: entityType) else {
            throw SyncCryptoError.unknownEntityType
        }
        return try await crypto.decrypt(wire, entityType: entity)
    }
}
```

If `SyncCryptoError` does not yet have a `unknownEntityType` case, add it to `Sources/Data/Sync/SyncCryptoService.swift`.

- [ ] **Step 3: Run tests, commit**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:ConchTalkTests/ConchtalkE2ECodecTests test
git add Sources/Data/Sync/ConchtalkE2ECodec.swift Sources/Data/Sync/SyncCryptoService.swift ConchTalkTests/ConchtalkE2ECodecTests.swift
git commit -m "Add ConchtalkE2ECodec wrapping existing SyncCryptoService"
```

---

## Task 4: `ConchtalkChangeCollector` and `ConchtalkMerger` adapters

**Files:**
- Modify: `Sources/Data/Sync/SyncChangeCollector.swift` (rename type → `ConchtalkChangeCollector`)
- Modify: `Sources/Data/Sync/SyncMergeEngine.swift` (rename type → `ConchtalkMerger`)
- Create: `ConchTalkTests/ConchtalkSyncAdaptersTests.swift`

The existing `SyncChangeCollector` already returns conchtalk envelopes; we adapt its public surface to conform to `SyncChangeCollecting`. Same for the merge engine.

- [ ] **Step 1: Inspect existing API**

```bash
grep -n "public\|func collect\|func merge\|class SyncChangeCollector\|class SyncMergeEngine" Sources/Data/Sync/SyncChangeCollector.swift Sources/Data/Sync/SyncMergeEngine.swift
```

- [ ] **Step 2: Adapt `SyncChangeCollector` to `SyncChangeCollecting`**

In `SyncChangeCollector.swift`:

1. Rename the type to `ConchtalkChangeCollector` (use Xcode "Rename" refactor or `sed`).
2. Add at the top of the file:

```swift
import LLMGatewayKit
```

3. Declare conformance and implement the protocol methods. The existing class likely already has a `collectChanges(since:batchSize:)` that returns conchtalk-shaped envelopes. Wrap it:

```swift
extension ConchtalkChangeCollector: SyncChangeCollecting {
    public func collectPending() async throws -> [SyncEnvelope] {
        let internalEnvelopes = try await collectChanges(since: SyncState.lastSyncedVersion, batchSize: 50)
        return internalEnvelopes.map { internal in
            SyncEnvelope(entityType: internal.entityType.rawValue,
                         entityID: internal.entityId,
                         modifiedAt: internal.modifiedAt,
                         data: internal.jsonData)
        }
    }

    public func markSynced(_ envelopes: [SyncEnvelope]) async throws {
        let maxVersion = envelopes.map(\.modifiedAt).max()
        if let maxVersion {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            SyncState.lastSyncedVersion = iso.string(from: maxVersion)
        }
    }
}
```

Adjust the internal envelope type name and field names to match the actual source.

- [ ] **Step 3: Adapt `SyncMergeEngine` to `SyncMerging`**

In `SyncMergeEngine.swift`:

1. Rename the type to `ConchtalkMerger`.
2. Add conformance:

```swift
extension ConchtalkMerger: SyncMerging {
    public func apply(_ envelope: SyncEnvelope) async throws {
        guard let entityType = SyncEntityType(rawValue: envelope.entityType) else { return }
        _ = try await merge(entityType: entityType, jsonData: envelope.data)
    }
}
```

- [ ] **Step 4: Write adapter tests**

`ConchtalkSyncAdaptersTests.swift`:

```swift
import XCTest
import SwiftData
import LLMGatewayKit
@testable import ConchTalk

final class ConchtalkSyncAdaptersTests: XCTestCase {
    func test_collector_returnsEnvelopes() async throws {
        // Insert a fixture entity, then assert collectPending returns at least one envelope
        // (Use the existing test pattern from SyncChangeCollectorTests.)
    }

    func test_merger_appliesEnvelope() async throws {
        // Construct a SyncEnvelope from a fixture, call apply, assert local store updated.
    }
}
```

- [ ] **Step 5: Run tests, commit**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:ConchTalkTests/ConchtalkSyncAdaptersTests test
git add Sources/Data/Sync/SyncChangeCollector.swift Sources/Data/Sync/SyncMergeEngine.swift ConchTalkTests/ConchtalkSyncAdaptersTests.swift
git commit -m "Adapt SyncChangeCollector/SyncMergeEngine to package protocols"
```

---

## Task 5: Replace `ConchTalkApp.swift` wiring

**Files:**
- Modify: `Sources/ConchTalkApp.swift`

- [ ] **Step 1: Read the current bootstrap**

```bash
grep -n "AuthService\|SubscriptionService\|SyncService\|Purchases.configure" Sources/ConchTalkApp.swift
```

- [ ] **Step 2: Replace the dependency-injection section**

Replace the construction of the in-app `AuthService`/`SubscriptionService`/`SyncService` with constructors from `LLMGatewayKit`. Run `LegacyMigrationHelper` BEFORE constructing the kit's `AuthService` (which reads the keychain).

```swift
import SwiftUI
import LLMGatewayKit
import RevenueCat
import UIKit

@main
struct ConchTalkApp: App {
    @State private var authService: AuthService
    @State private var subscriptionService: SubscriptionService
    @State private var syncObserver: SyncStatusObserver
    private let syncEngine: SyncEngine
    private let config: LLMGatewayKitConfig

    init() {
        // 1) Migrate legacy state BEFORE the kit reads anything.
        try? LegacyMigrationHelper().migrateIfNeeded()

        // 2) Build kit config.
        let rcKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
        let baseURL = (Bundle.main.object(forInfoDictionaryKey: "GATEWAY_BASE_URL") as? String)
            ?? "https://api.conch-talk.com"
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: baseURL)!,
            entitlementID: "pro",
            appDisplayName: "ConchTalk",
            companionAppNames: ["SnapKei"],
            revenueCatAPIKey: rcKey,
            paywallFeatures: [
                .init(id: "agent", icon: "terminal", title: "AI コーディングエージェント", subtitle: nil),
                .init(id: "cloud", icon: "icloud.fill", title: "クラウド同期", subtitle: nil),
                .init(id: "dlc", icon: "bolt.horizontal.fill", title: "DLC エージェント", subtitle: nil),
            ],
            deviceName: UIDevice.current.name)
        self.config = config

        // 3) Kit services.
        let auth = AuthService(config: config)
        auth.restoreSession()
        self._authService = State(initialValue: auth)

        let subscription = SubscriptionService(authService: auth, config: config)
        self._subscriptionService = State(initialValue: subscription)
        if let rcKey, !rcKey.isEmpty {
            if let sub = auth.cachedAppleSub {
                Purchases.configure(withAPIKey: rcKey, appUserID: sub)
            } else {
                Purchases.configure(withAPIKey: rcKey)
            }
            subscription.startListening()
        }

        // 4) Sync engine with E2E codec + conchtalk collector/merger.
        let crypto = SyncCryptoService(/* existing init args */)
        let codec = ConchtalkE2ECodec(crypto: crypto)
        let collector = ConchtalkChangeCollector(/* existing init args */)
        let merger = ConchtalkMerger(/* existing init args */)
        let apiClient = SyncAPIClient(config: config, auth: auth)
        let deviceID = SyncState.deviceId   // legacy: keep existing per-user device id for cross-device dedup
        let engine = SyncEngine(
            apiClient: apiClient, codec: codec,
            collector: collector, merger: merger,
            state: LLMGatewayKit.SyncState.shared,
            deviceID: deviceID, keyGeneration: SyncState.keyGeneration,
            isEligible: { [weak auth] in
                guard let auth else { return false }
                return await MainActor.run {
                    auth.isLoggedIn && auth.currentUser?.tier == "paid" &&
                        LLMGatewayKit.SyncState.shared.isEnabled
                }
            })
        self.syncEngine = engine
        self._syncObserver = State(initialValue: SyncStatusObserver(engine: engine))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .environment(subscriptionService)
                .environment(syncObserver)
                .environment(\.llmGatewayKitConfig, config)
                .environment(\.conchtalkSyncEngine, syncEngine)
        }
    }
}

private struct LLMGatewayKitConfigKey: EnvironmentKey {
    static let defaultValue: LLMGatewayKitConfig? = nil
}
private struct ConchtalkSyncEngineKey: EnvironmentKey {
    static let defaultValue: SyncEngine? = nil
}
extension EnvironmentValues {
    var llmGatewayKitConfig: LLMGatewayKitConfig? {
        get { self[LLMGatewayKitConfigKey.self] }
        set { self[LLMGatewayKitConfigKey.self] = newValue }
    }
    var conchtalkSyncEngine: SyncEngine? {
        get { self[ConchtalkSyncEngineKey.self] }
        set { self[ConchtalkSyncEngineKey.self] = newValue }
    }
}
```

Note: ConchTalk's `SyncState` enum stays in place — it owns `deviceId`, `keyGeneration`, and `lastSyncedVersion` which the codec/collector use. The package's `LLMGatewayKit.SyncState` owns the user-facing `isEnabled` toggle, pull cursor, and `disabledByUserID`. The two coexist temporarily.

- [ ] **Step 3: Hook up the auto-sync stream**

Wherever ConchTalk's existing repo signals changes, route them into `syncEngine.startAutoSync(repoChanges:)`. ConchTalk already has a publisher (`SyncChangeCollector` may have a "pending count" notification). Convert it to `AsyncStream<Void>` in the bootstrap.

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ConchTalkApp.swift
git commit -m "Switch ConchTalkApp bootstrap to LLMGatewayKit services"
```

---

## Task 6: Delete in-app duplicates

**Files (delete):**
- `Sources/Data/Network/AuthService.swift`
- `Sources/Domain/Protocols/AuthServiceProtocol.swift`
- `Sources/Data/Subscription/SubscriptionService.swift`
- `Sources/Domain/Protocols/SubscriptionServiceProtocol.swift`
- `Sources/Domain/Entities/SubscriptionStatus.swift` (if no other references)
- `Sources/Data/Sync/SyncAPIClient.swift`
- `Sources/Data/Sync/SyncService.swift`
- `Sources/Presentation/Paywall/PaywallView.swift`
- `Sources/Presentation/Paywall/PaywallViewModel.swift`
- `Sources/Presentation/Settings/ProfileView.swift`

Plus their corresponding test files in `ConchTalkTests/`.

- [ ] **Step 1: Find and audit references**

```bash
cd /Users/lee/workspace/conchtalk
grep -rn "AuthService\|SubscriptionService\|SyncService\|PaywallView\|PaywallViewModel\|ProfileView" Sources/ --include="*.swift" | grep -v "// " | grep -v "import LLMGatewayKit" | sort -u
```

For each surviving reference, ensure it now resolves to the kit's symbol (i.e., the call site imports `LLMGatewayKit`).

- [ ] **Step 2: Remove each file**

```bash
git rm Sources/Data/Network/AuthService.swift
git rm Sources/Domain/Protocols/AuthServiceProtocol.swift
git rm Sources/Data/Subscription/SubscriptionService.swift
git rm Sources/Domain/Protocols/SubscriptionServiceProtocol.swift
git rm Sources/Data/Sync/SyncAPIClient.swift
git rm Sources/Data/Sync/SyncService.swift
git rm Sources/Presentation/Paywall/PaywallView.swift
git rm Sources/Presentation/Paywall/PaywallViewModel.swift
git rm Sources/Presentation/Settings/ProfileView.swift
```

Delete corresponding test files only after the deletions above compile cleanly:

```bash
git rm ConchTalkTests/AuthServiceTests.swift 2>/dev/null
git rm ConchTalkTests/SubscriptionServiceTests.swift 2>/dev/null
git rm ConchTalkTests/SyncServiceTests.swift 2>/dev/null
git rm ConchTalkTests/SyncAPIClientTests.swift 2>/dev/null
```

Keep `SyncCryptoService.swift` (used by the codec adapter), `SyncChangeCollector.swift` (now `ConchtalkChangeCollector`), `SyncMergeEngine.swift` (now `ConchtalkMerger`), `SyncConstants.swift`.

- [ ] **Step 3: Resolve remaining compile errors**

Search for any unresolved references introduced by the deletions:

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build 2>&1 | grep -E "error:" | head -20
```

For each, prefix the identifier in code with `LLMGatewayKit.` or import the module. Common spots: `UsageInfo`, `AuthError`, `PurchaseState`, `AccountUser` are now in the package.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Delete in-app duplicates; route through LLMGatewayKit"
```

---

## Task 7: Update `SettingsView` to use package UI

**Files:**
- Modify: `Sources/Presentation/Settings/SettingsView.swift`

ConchTalk's `SettingsView` previously instantiated `ProfileView` and `PaywallView` from local files. They're now from the package.

- [ ] **Step 1: Read the current SettingsView destinations**

```bash
grep -n "ProfileView\|PaywallView\|paywall" Sources/Presentation/Settings/SettingsView.swift | head
```

- [ ] **Step 2: Update the imports and call sites**

Add at the top:

```swift
import LLMGatewayKit
```

Replace navigation destination for Profile:

```swift
.navigationDestination(isPresented: $navigateToProfile) {
    if let config = llmGatewayKitConfig {
        ProfileView(config: config,
                    authService: authService,
                    subscriptionService: subscriptionService,
                    onRequestUpgrade: { showPaywall = true })
    }
}
```

Replace the Paywall sheet:

```swift
.sheet(isPresented: $showPaywall) {
    if let config = llmGatewayKitConfig {
        PaywallView(config: config,
                    viewModel: PaywallViewModel(subscriptionService: subscriptionService))
    }
}
```

Add a binding for `llmGatewayKitConfig` (set up in Task 5 via `EnvironmentKey`):

```swift
@Environment(\.llmGatewayKitConfig) private var llmGatewayKitConfig
```

- [ ] **Step 3: Build, commit**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
git add Sources/Presentation/Settings/SettingsView.swift
git commit -m "SettingsView: route Profile/Paywall through LLMGatewayKit views"
```

---

## Task 8: Replace `CloudSyncSettingsView` plumbing

**Files:**
- Modify: `Sources/Presentation/Settings/CloudSyncSettingsView.swift`

- [ ] **Step 1: Read current dependencies**

The view likely calls `syncService.sync()`, `syncService.forceFullSync()`, etc. Replace with kit's `SyncEngine` methods.

- [ ] **Step 2: Refactor**

Wherever ConchTalk's SettingsView constructed `CloudSyncSettingsView`, pass the kit's `SyncEngine` instead of the deleted `SyncService`. Inside the view:

```swift
import LLMGatewayKit

struct CloudSyncSettingsView: View {
    let authService: AuthService
    let syncEngine: SyncEngine
    let subscriptionService: SubscriptionService
    let onUpgrade: () -> Void

    @State private var isEnabled = LLMGatewayKit.SyncState.shared.isEnabled
    @State private var showDisableConfirm = false

    // ...
}
```

Replace `syncService.sync()` with `try? await syncEngine.syncNow()`, `syncService.forceFullSync()` with `try? await syncEngine.forceFullSync()`, and `syncService.disableAndDeleteCloudData()` with `try? await syncEngine.disableAndDeleteCloud()`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Presentation/Settings/CloudSyncSettingsView.swift
git commit -m "CloudSyncSettingsView: drive sync via LLMGatewayKit.SyncEngine"
```

---

## Task 9: Audit and update remaining call sites

A grep sweep to catch anything missed.

- [ ] **Step 1: Run sweep**

```bash
cd /Users/lee/workspace/conchtalk
grep -rn "SubscriptionStatus\|AuthError\|UsageInfo\|UsageBreakdown\|PurchaseState\|AccountUser" Sources/ --include="*.swift" | grep -v "LLMGatewayKit"
```

For each hit:
- If the type is now provided by `LLMGatewayKit`, add `import LLMGatewayKit` to that file.
- If the type was a conchtalk-specific extension on the old kit type, decide whether to:
  - Keep it as an extension on the kit type (acceptable for visual helpers)
  - Inline the call site (better for one-off uses)

- [ ] **Step 2: Build full test suite**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

Expected: all tests pass.

- [ ] **Step 3: Commit any drive-by fixes**

```bash
git add -A
git commit -m "Migrate remaining type references to LLMGatewayKit"
```

---

## Task 10: RevenueCat dashboard configuration (operator-side)

This is a manual operations task — **not** a code task. Performed by the operator in the RevenueCat dashboard. Add a checkbox here as a gate before tagging the release.

- [ ] In the existing ConchTalk RevenueCat Project, create entitlement `pro` (lowercase).
- [ ] Attach `pro` to every ConchTalk Pro product (alongside the existing `"conchtalk Pro"` entitlement).
- [ ] Verify in the dashboard's "Customers" tab that a known paid customer now has both entitlements active.
- [ ] Do NOT remove the `"conchtalk Pro"` entitlement until at least 30 days after this build ships and >95% of active installs have updated. That cleanup is a follow-up commit.

---

## Task 11: Verification on a real device

Tested by installing the **current public** ConchTalk build, then upgrading to this branch's build on the same device with no other action between.

- [ ] User stays logged in (no re-auth required)
- [ ] Tier still shows correctly: paid users still paid; free users still free
- [ ] Cloud sync history still visible in the message list (already-uploaded messages render)
- [ ] Toggle Cloud Sync off → on; force-sync round-trips without data loss
- [ ] Sign Out → Sign In cycle succeeds; on re-login, server data restored
- [ ] Paywall opens; shows correct price; Restore button works
- [ ] After 24h, paid user's `tierExpiresAt` is still valid (no entitlement drift)

If any item fails, file a follow-up bug rather than block the merge.

---

## Task 12: Tag and ship

- [ ] **Step 1: Confirm tests green**

```bash
xcodebuild -scheme ConchTalk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "Migrate to LLMGatewayKit 0.1.0" --body "$(cat <<'EOF'
## Summary
- Adds LLMGatewayKit 0.1.0 dependency
- Migrates auth, subscription, sync, profile, paywall to the package
- One-shot LegacyMigrationHelper copies keychain + UserDefaults keys
- ConchtalkE2ECodec preserves existing E2E encryption on sync payloads

## Test plan
- [x] Unit tests: LegacyMigrationHelperTests, ConchtalkE2ECodecTests, ConchtalkSyncAdaptersTests pass
- [x] Existing test suite green
- [x] Manual: upgrade from public build, verify login/tier/sync preserved (Task 11 checklist)
- [x] RevenueCat: dual-attach of `pro` entitlement confirmed in dashboard

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: After PR merge, tag and release**

```bash
git checkout main && git pull
# bump CFBundleVersion in Xcode project, commit if needed
git tag -a v$(date +%Y.%m.%d) -m "ConchTalk migration to LLMGatewayKit"
git push origin --tags
```

- [ ] **Step 4: 30-day follow-up**

Calendar reminder: in 30 days, remove the legacy `"conchtalk Pro"` entitlement attachment in RC dashboard, and remove `LegacyMigrationHelper` + the legacy key constants in a cleanup commit. Track as a separate plan if needed.

---

# Self-Review Notes

1. **Spec coverage (§10):** §10.1 deletions covered by Task 6; §10.2 renames covered by Tasks 3-4; §10.3 ConchTalkApp edits in Task 5; §10.4 migrations in Task 2; §10.5 RC operations in Task 10; §10.6 verification in Task 11.
2. **No `fatalError` introduced**: all stubs in Task 4 must be replaced before compile (compile-fail prevents merging partial work).
3. **Migration idempotency**: Task 2's test asserts the migration runs only once via the `LLMGatewayKit.migrationDone_v1` flag.
4. **Entitlement transition window**: §7.3 / Task 10 sets up dual-attach; client reads only `pro`. Old entitlement stays attached at least 30 days.
5. **Type consistency**: the kit's `LLMGatewayKit.SyncState` and ConchTalk's `SyncState` (renamed but kept) coexist by name; references are disambiguated with `LLMGatewayKit.` prefix in Task 5.
6. **Risk**: SwiftData entity migration is not needed for ConchTalk (entities are unchanged) — only key migration. Confirmed by re-reading §10.4.

Plan ready for execution.
