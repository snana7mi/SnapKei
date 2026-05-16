# SharedAccountKit & SnapKei Settings Redesign — Design Spec

**Date:** 2026-05-16
**Status:** Awaiting user review
**Scope:** Multi-repo (SnapKei + ConchTalk + new SharedAccountKit package + llm-gateway-back is unchanged)

---

## 1. Goal

Bring SnapKei's Settings page up to parity with ConchTalk's: Apple Sign In, profile, usage display, shared paid subscription, and R1 cloud sync. Do this by extracting the relevant ConchTalk modules into a new local Swift Package (`SharedAccountKit`) that both apps depend on, so the implementation is shared and maintained in one place.

The two apps share **paid membership and usage quota** at the user level (keyed on Apple sub), because the gateway backend (`llm-gateway-back`) already stores `users.tier` and `usage_ledger` per-user (not per-app). Buying Pro in either app unlocks Pro in both.

## 2. Non-Goals

- E2E encryption for SnapKei sync (chose plaintext-on-server — see §6.4)
- Server-side report generation from synced ledger data (future work)
- A formal published version of `SharedAccountKit` on a public registry (it lives as a local-path Swift Package; promoting it later is a separate decision)
- Migrating the host of either app to a monorepo

## 3. High-Level Architecture

### 3.1 Repository layout

```
~/workspace/
├── SharedAccountKit/                          🆕 new local Swift Package
│   ├── Package.swift
│   ├── Sources/SharedAccountKit/
│   │   ├── Config/SharedAccountKitConfig.swift
│   │   ├── Auth/                              # AuthService, AuthError, AccountUser, KeychainTokenStore
│   │   ├── Subscription/                      # SubscriptionService, PurchaseState
│   │   ├── Sync/                              # SyncEngine, SyncAPIClient, SyncEnvelope,
│   │   │                                      # SyncPayloadCodec, IdentityPayloadCodec,
│   │   │                                      # SyncChangeCollecting, SyncMerging, SyncState
│   │   ├── Models/                            # UsageInfo, UsageBreakdown
│   │   └── UI/                                # ProfileView, PaywallView, PaywallViewModel,
│   │                                          # RainbowAvatarBorder
│   └── Tests/SharedAccountKitTests/
│
├── conchtalk/                                 (P3 migrates to use the package)
└── SnapKei/                                   (P2 adopts the package + new Settings UI)
```

### 3.2 Phased delivery

| Phase | Work | Repo | Ships with |
|---|---|---|---|
| **P1 Build package** | Create `SharedAccountKit`; copy-and-parameterize code from ConchTalk; write minimal unit tests | `SharedAccountKit/` | P2 |
| **P2 SnapKei adoption** | Add path dependency; implement `SnapKeiChangeCollector`/`Merger`; rebuild SettingsView in ConchTalk style | SnapKei | P1 |
| **P3 ConchTalk migration** | Delete in-app duplicates; switch to package imports; one-shot keychain/UserDefaults key migration | conchtalk | Same plan |

All three phases are committed together in this design. P3 includes data-migration safety for existing ConchTalk users.

### 3.3 Configuration boundary

```swift
public struct SharedAccountKitConfig: Sendable {
    public let baseURL: URL                       // "https://api.conch-talk.com" — shared gateway host
    public let entitlementID: String              // "pro" — shared across apps
    public let appDisplayName: String             // "SnapKei" | "ConchTalk"
    public let companionAppNames: [String]        // ["ConchTalk"] in SnapKei, ["SnapKei"] in ConchTalk
    public let revenueCatAPIKey: String?          // injected; nil disables RC integration
    public let paywallFeatures: [PaywallFeature]
    public let deviceName: String                 // UIDevice.current.name, surfaced to backend sessions
}

public struct PaywallFeature: Sendable, Identifiable {
    public let id: String
    public let icon: String                       // SF Symbol name
    public let title: String                      // localized
    public let subtitle: String?                  // optional
}
```

App-side wiring example (SnapKei):

```swift
let config = SharedAccountKitConfig(
    baseURL: URL(string: "https://api.conch-talk.com")!,
    entitlementID: "pro",
    appDisplayName: "SnapKei",
    companionAppNames: ["ConchTalk"],
    revenueCatAPIKey: Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
    paywallFeatures: [
        .init(id: "ai-quota", icon: "doc.text.magnifyingglass", title: "AI 解析回数の増加", subtitle: nil),
        .init(id: "cloud-sync", icon: "icloud.fill", title: "R1 クラウド自動バックアップ", subtitle: nil),
        .init(id: "reports", icon: "chart.bar.fill", title: "詳細レポート", subtitle: nil),
    ],
    deviceName: UIDevice.current.name
)
```

## 4. Backend (No Changes)

`llm-gateway-back` already provides every endpoint we need:

| Endpoint | Used by |
|---|---|
| `POST /auth/apple` | AuthService.authenticate |
| `POST /auth/refresh` | AuthService.refreshAccessToken |
| `DELETE /auth/account` | AuthService.deleteAccount |
| `GET /account` | AuthService.fetchAccount |
| `PUT /account/avatar` | AuthService.uploadAvatar (multipart) |
| `GET /usage` | AuthService.fetchUsage |
| `PUT /sync/push` | SyncAPIClient.push |
| `GET /sync/pull` | SyncAPIClient.pull |
| `GET /sync/status` | SyncAPIClient.status |
| `DELETE /sync/data` | SyncEngine.disableAndDeleteCloud |
| `POST /webhooks/revenuecat` | RC dashboard → backend (already wired) |

The `users` table is keyed by `apple_sub`, so the same Apple ID maps to the same backend user across both apps. `usage_ledger` is also per-user — no app-level partition. This is the entire mechanism by which shared membership and shared quota Just Work.

The RevenueCat webhook reads `event.app_user_id` (= Apple sub) — it is **App-agnostic**, so renaming the entitlement does not require any webhook change.

## 5. AuthService (`SharedAccountKit/Auth/`)

### 5.1 Public API

```swift
@Observable
@MainActor
public final class AuthService {
    public private(set) var isLoggedIn: Bool
    public private(set) var currentUser: AccountUser?
    public private(set) var cachedAvatarData: Data?
    public var cachedAppleSub: String? { get }

    public init(config: SharedAccountKitConfig, keychain: KeychainTokenStore = .standard)

    public func restoreSession()
    public func authenticate(identityToken: Data, fullName: String?, appleSub: String) async throws
    public func validAccessToken() async throws -> String
    public func refreshAccessToken() async throws       // single-flight
    public func logout() async
    public func deleteAccount() async throws
    public func fetchAccount() async throws
    public func fetchUsage() async throws -> UsageInfo
    public func uploadAvatar(imageData: Data) async throws -> String
    public func loadAvatarDataIfNeeded() async -> Data?
    public func updateCurrentUser(_ user: AccountUser)
}

public struct AccountUser: Sendable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let tier: String              // "free" | "paid"
    public let tierExpiresAt: String?
    public let createdAt: String?
    public let avatarURL: String?
}

public enum AuthError: LocalizedError, Sendable {
    case notLoggedIn
    case sessionExpired
    case invalidURL
    case networkError
    case invalidResponse
    case serverError(String)
    case accountDeletionFailed
}
```

### 5.2 Token storage

Package-internal `KeychainTokenStore` owns three keychain accounts: `kit.accessToken`, `kit.refreshToken`, `kit.tokenExpiry`. Apple sub is held in `UserDefaults` (key `SharedAccountKit.cachedAppleSub`) — it is non-secret and used for RevenueCat App User ID restoration after a fresh launch.

Access tokens are assumed to expire 15 minutes after issue; the store records the wall-clock expiry. `validAccessToken()` refreshes when the remaining lifetime is < 60s.

### 5.3 Single-flight refresh

`refreshAccessToken()` coalesces concurrent callers into one `Task`. Single-use refresh tokens (gateway issues a new refresh on every refresh) make this critical — a duplicated refresh attempt revokes the session.

### 5.4 401 retry pathway

Callers that hit a 401 on an authenticated endpoint must call `refreshAccessToken()` once and retry. `AuthService` does not perform automatic transport-layer retries (callers control retry semantics). Retry-then-401 again ⇒ `await logout()`.

### 5.5 SnapKei: AIProxyService refactor

`SnapKei/Data/Network/AIProxyService.swift` currently duplicates token handling. Refactor:

- Delete `validAccessToken()`, `authenticateWithApple()`, `refreshAccessToken()` (~35 lines)
- `init(authService: AuthService, ...)`; call `try await authService.validAccessToken()`
- On 401: `try await authService.refreshAccessToken()` once, then retry; if still 401, throw `AIServiceError.proxySessionExpired`
- The "first parse triggers SIWA" fallback is preserved: if `validAccessToken()` throws `.notLoggedIn`, `AIProxyService` calls a new helper `authService.authenticateInteractively()` that presents the system Sign-in-with-Apple sheet (uses the existing `AppleSignInService` internally, moved into the package as `Auth/AppleSignInBridge.swift`).

## 6. CloudSync (`SharedAccountKit/Sync/`)

### 6.1 Wire protocol (already defined by gateway)

- `PUT /sync/push` body: `{ key_generation: Int, device_id: String, entries: [{ entity_type, entity_id, modified_at, data: base64 }] }`
- `GET /sync/pull?since=<ISO>&since_id=<id>&device_id=<id>&limit=<n>` → `{ entries: [...], next_cursor: { since, since_id } | null }`
- Server treats `data` as opaque bytes. Encryption (or lack thereof) is a client concern.

### 6.2 Protocols

```swift
public protocol SyncPayloadCodec: Sendable {
    func encode(_ plaintext: Data, entityType: String) async throws -> Data
    func decode(_ wire: Data, entityType: String) async throws -> Data
}

public struct IdentityPayloadCodec: SyncPayloadCodec {
    public init() {}
    public func encode(_ p: Data, entityType: String) async -> Data { p }
    public func decode(_ w: Data, entityType: String) async -> Data { w }
}

public protocol SyncChangeCollecting: Sendable {
    func collectPending() async throws -> [SyncEnvelope]
    func markSynced(_ envelopes: [SyncEnvelope]) async throws
}

public protocol SyncMerging: Sendable {
    func apply(_ envelope: SyncEnvelope) async throws
}

public struct SyncEnvelope: Codable, Sendable, Equatable {
    public let entityType: String
    public let entityID: String
    public let modifiedAt: Date
    public let data: Data         // plaintext bytes; codec wraps for wire
}
```

### 6.3 SyncEngine

```swift
public actor SyncEngine {
    public init(apiClient: SyncAPIClient,
                codec: SyncPayloadCodec,
                collector: SyncChangeCollecting,
                merger: SyncMerging,
                state: SyncState,
                deviceID: String,
                keyGeneration: Int = 1)

    public func syncNow() async throws -> SyncResult
    public func forceFullSync() async throws -> SyncResult
    public func disableAndDeleteCloud() async throws
    public func startAutoSync(repoChanges: AsyncStream<Void>)
    public func stopAutoSync()
}

public struct SyncResult: Sendable {
    public let pushedCount: Int
    public let pulledCount: Int
    public let prunedCount: Int
    public let success: Bool
    public let error: String?
    public let timestamp: Date
}
```

### 6.4 SnapKei codec choice

SnapKei uses `IdentityPayloadCodec` — plaintext JSON bytes, no encryption. The user has explicitly accepted this trade-off (TLS-only, server can read records in support of future server-side reports). `key_generation` is fixed to `1`.

### 6.5 ConchTalk codec choice (P3)

ConchTalk keeps its existing E2E encryption: package adds `ConchtalkE2ECodec: SyncPayloadCodec` adapter that wraps the existing `SyncCryptoService` (moved out of the package into ConchTalk's own sources).

### 6.6 Auto-sync wiring (SnapKei)

- `ExpenseRepository` is extended to publish an `AsyncStream<Void>` of write events. Implementation: after each save, the repo's continuation `yield()`s.
- `SyncEngine.startAutoSync(repoChanges:)` debounces 2s, then `syncNow()`.
- On app foreground (`scenePhase == .active`): `syncNow()` immediately.
- Failure backoff: 1s → 5s → 30s → 5min, capped at 5min. Resets on success.
- Conflict resolution: server's `modified_at` vs local — last-write-wins. Local mutations during pull are not blocked; subsequent push will overwrite.

### 6.7 Tombstones (deletes)

`SyncEnvelope.data` carries a `deletedAt: Date?` field in the JSON when the entity is deleted (rather than introducing a separate envelope type). `SnapKeiMerger` checks this field; if present, it removes the local record. Push does the same: `SnapKeiChangeCollector` emits envelopes for tombstoned entities (with the deletion timestamp populated in the JSON).

### 6.8 SnapKei collector/merger implementations

```swift
struct SnapKeiChangeCollector: SyncChangeCollecting {
    let repo: ExpenseRepository                    // SwiftData wrapper
    let lastSyncStore: SyncCursorStore

    func collectPending() async throws -> [SyncEnvelope] {
        let since = lastSyncStore.lastPushedAt
        var out: [SyncEnvelope] = []
        for entry in try repo.journalEntries(updatedAfter: since) {
            let data = try JSONEncoder.snapkeiSync.encode(entry)
            out.append(.init(entityType: "JournalEntry", entityID: entry.syncId.uuidString,
                             modifiedAt: entry.updatedAt, data: data))
        }
        for asset in try repo.fixedAssets(updatedAfter: since) {
            let data = try JSONEncoder.snapkeiSync.encode(asset)
            out.append(.init(entityType: "FixedAsset", entityID: asset.syncId.uuidString,
                             modifiedAt: asset.updatedAt, data: data))
        }
        return out
    }

    func markSynced(_ envelopes: [SyncEnvelope]) async throws {
        let latest = envelopes.map(\.modifiedAt).max() ?? Date()
        lastSyncStore.lastPushedAt = latest
    }
}

struct SnapKeiMerger: SyncMerging {
    let repo: ExpenseRepository
    func apply(_ envelope: SyncEnvelope) async throws {
        switch envelope.entityType {
        case "JournalEntry":
            let decoded = try JSONDecoder.snapkeiSync.decode(JournalEntry.self, from: envelope.data)
            try repo.upsertFromSync(decoded)
        case "FixedAsset":
            let decoded = try JSONDecoder.snapkeiSync.decode(FixedAsset.self, from: envelope.data)
            try repo.upsertFromSync(decoded)
        default:
            return    // forward-compat: unknown types are ignored
        }
    }
}
```

`JSONEncoder.snapkeiSync` / `JSONDecoder.snapkeiSync` are static factory configurations local to SnapKei: ISO 8601 dates with fractional seconds, sorted keys. They live in `SnapKei/Data/Sync/SnapKeiSyncCoders.swift`.

`ExpenseRepository.upsertFromSync` checks `syncId`. If a local record exists with a newer `updatedAt`, the merge is skipped (LWW). Otherwise it overwrites or inserts.

`updatedAt` is a new requirement on `JournalEntry` and `FixedAsset`: both must record their last-mutation timestamp. The migration adds a column (`@Attribute(.unique) updatedAt: Date`, defaulting to current date for existing rows).

## 7. SubscriptionService (`SharedAccountKit/Subscription/`)

### 7.1 Public API

```swift
@Observable
@MainActor
public final class SubscriptionService {
    public private(set) var displayPrice: String?
    public private(set) var purchaseState: PurchaseState

    public init(authService: AuthService, config: SharedAccountKitConfig)

    public func startListening()
    public func loadProducts() async
    public func purchase() async
    public func restore() async
}

public enum PurchaseState: Equatable, Sendable {
    case idle, purchasing, verifying, success
    case failed(String)
}
```

### 7.2 Behavior

- `startListening()` subscribes to `Purchases.shared.customerInfoStream`. When the entitlement (`config.entitlementID`) flips state, call `try? await authService.fetchAccount()` to pull the new tier from the gateway.
- `purchase()` requires `isLoggedIn` (otherwise → `.failed("Please sign in first")`). On success, polls `fetchAccount()` 5 times × 1s waiting for tier sync (webhook delay).
- `restore()` always works (logged-out users can restore RC entitlement and are then prompted to sign in).
- Package does **not** call `Purchases.configure(...)` — the host app does that at boot with its own RC API key.

### 7.3 RevenueCat configuration (operational)

In the RevenueCat dashboard:

1. Add SnapKei iOS App under the existing ConchTalk RC Project (same Project, multiple Apps).
2. Create a new entitlement named `pro` (lowercase). Attach it to existing ConchTalk Pro products **and** to SnapKei's IAP products.
3. Keep the old `"conchtalk Pro"` entitlement attached during the migration window (P3) — package only reads `"pro"`, but the dual-attach prevents existing subscribers from losing access during rollout.
4. Once P3 ships and all live ConchTalk installs have updated, the old entitlement can be retired.

SnapKei's IAPs are created in App Store Connect under SnapKei's own subscription group with the same pricing as ConchTalk's Pro products. Users can subscribe via either app; both lead to the same entitlement.

## 8. UI in the Package (`SharedAccountKit/UI/`)

### 8.1 `ProfileView`

Public, takes `config: SharedAccountKitConfig`, `authService`, `subscriptionService`. Renders:

- Avatar editing via `PhotosPicker`, uploads through `authService.uploadAvatar`. Compressed to ≤512px max side, JPEG.
- Tier + Upgrade button (opens host's paywall via callback)
- Usage % (one decimal), red when > 100%
- Resets-In countdown derived from `usage.resetsAt`
- Restore Purchases, Sign Out, Delete Account (with confirmation alert)

When not logged in, renders a `SignInWithAppleButton` that calls `authService.authenticate(...)`.

`ProfileView` is fully shareable. Per-app variations (e.g., different upgrade copy) come from `config`.

### 8.2 `PaywallView`

Renders `config.paywallFeatures` as an icon-+-title list. Displays the multi-app message:

> "このサブスクリプションは ConchTalk と SnapKei の両方で有効です"

(template assembles from `config.appDisplayName` + `config.companionAppNames`).

Buy button uses `subscriptionService.purchase()`. Restore button is shown prominently next to Buy (not buried). Localized into Japanese (primary) and English (fallback).

### 8.3 `RainbowAvatarBorder`

Existing ConchTalk visual modifier moved into the package, applied to paid users' avatars in `ProfileView` and in `AccountHeaderSection`.

## 9. SnapKei Settings Composition (`Presentation/Settings/`)

```swift
NavigationStack {
    Form {
        AccountHeaderSection(authService: authService, onTapAvatar: { showProfile = true })
        CloudSyncSection(syncEngine: syncEngine, authService: authService, onUpgrade: { showPaywall = true })
        BusinessInfoSection(...)            // existing
        AISettingsSection(...)              // existing, with pseudo-SIWA button removed
        FixedAssetSection()                 // existing
        HouseholdAllocationSection()        // existing
        ComplianceSection(...)              // existing
        SaveButtonSection(...)              // unsaved-changes UX from ConchTalk
        AboutSection()
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $showProfile) {
        ProfileView(config: config, authService: authService, subscriptionService: subscriptionService,
                    onRequestUpgrade: { showPaywall = true })
    }
    .sheet(isPresented: $showPaywall) {
        PaywallView(config: config, viewModel: PaywallViewModel(subscriptionService: subscriptionService))
    }
    .overlay(alignment: .top) { SyncToastView(syncEngine: syncEngine) }
}
```

### 9.1 `AccountHeaderSection` (new, SnapKei-side)

Big "設定" title left-aligned + circular avatar right-aligned. Tap → `ProfileView`. Paid users' avatar gets the rainbow border. Logged-out state: SF Symbol `person.crop.circle.fill`.

### 9.2 `CloudSyncSection` (new, SnapKei-side)

- Toggle "クラウド同期", disabled when not logged-in OR not paid
- "Sign in to use cloud sync" / "Upgrade to Pro" hints (mirrors ConchTalk patterns)
- "強制同期" button when enabled
- Footer: "暗号化された通信で R1 ストレージに保存されます。"

### 9.3 `SaveButtonSection` (new, SnapKei-side)

Mirrors ConchTalk's pattern: `SettingsViewModel` holds `savedAppSettings`/`savedAISettings` snapshots, `hasUnsavedChanges` is a computed property, the "Save Settings" button shows orange + "Unsaved changes" caption when dirty, with a Discard button next to it.

### 9.4 `AISettingsSection` edit

Remove the `onSignInWithApple` parameter and the "Apple でサインイン" button (Profile owns sign-in now). When in `builtInProxy` channel and `!isLoggedIn`, show an inline caption "ログインすると内蔵 AI を使用できます" with a button that drills into Profile.

### 9.5 `SyncToastView` (new, SnapKei-side)

Listens to `syncEngine` state changes; on each `SyncResult`, shows a brief top toast for 2s — green "同期完了", red "同期エラー: …", orange "古いデータが自動削除されました (n)".

## 10. ConchTalk Migration (P3)

### 10.1 Files to delete

```
Sources/Data/Network/AuthService.swift
Sources/Data/Subscription/SubscriptionService.swift
Sources/Data/Subscription/SubscriptionStatus.swift
Sources/Domain/Protocols/SubscriptionServiceProtocol.swift
Sources/Domain/Protocols/AuthServiceProtocol.swift
Sources/Data/Sync/SyncAPIClient.swift
Sources/Data/Sync/SyncService.swift                # replaced by package SyncEngine
Sources/Presentation/Paywall/PaywallView.swift
Sources/Presentation/Paywall/PaywallViewModel.swift
Sources/Presentation/Settings/ProfileView.swift
```

### 10.2 Files to keep (ConchTalk-specific implementations of package protocols)

```
Sources/Data/Sync/SyncChangeCollector.swift  →  ConchtalkChangeCollector: SyncChangeCollecting
Sources/Data/Sync/SyncMergeEngine.swift      →  ConchtalkMerger: SyncMerging
Sources/Data/Sync/SyncCryptoService.swift    →  ConchtalkE2ECodec: SyncPayloadCodec
Sources/Data/Sync/SyncConstants.swift        →  ConchTalk-specific constants stay
```

### 10.3 ConchTalkApp.swift edits

Construct the `SharedAccountKitConfig` with ConchTalk's specific values (`appDisplayName: "ConchTalk"`, `companionAppNames: ["SnapKei"]`, ConchTalk's existing paywall feature list) and instantiate `AuthService`/`SubscriptionService`/`SyncEngine` from the package.

### 10.4 One-shot data migrations

ConchTalk users have an existing app install with state stored at keys the package does not use. The package's `AuthService.init` (or a separate `MigrationHelper`) runs once on first launch under the new build:

1. **Keychain key migration**: copy
   - old `accessToken`/`refreshToken` keychain accounts → new `kit.accessToken`/`kit.refreshToken`
   - old `tokenExpiry` → `kit.tokenExpiry`
   - old `cachedAppleSub` UserDefault key → new key
2. **SyncState UserDefaults migration**: copy `SyncState.isEnabled`, `lastPushedAt`, key generation if any, → new package-namespaced keys
3. Mark migration done in `UserDefaults` so the operation is idempotent

After P3, the old keys remain readable for the next release (≥30 days after P3 ships) as a safety net; the cleanup is a separate follow-up commit that deletes the migration-helper code and the legacy keys.

### 10.5 RevenueCat entitlement migration

See §7.3. The dual-attach (`"conchtalk Pro"` AND `"pro"` on the same products) means no user loses access during the transition. P3 client only reads `"pro"`.

### 10.6 P3 verification checklist

Tested by installing the existing public ConchTalk build, then upgrading to the P3 build with no other action:

- [ ] User stays logged in
- [ ] Tier still shows correctly (paid users still paid)
- [ ] Cloud sync history still visible
- [ ] Force Full Sync round-trips without data loss
- [ ] Sign Out + Sign In cycle works
- [ ] Paywall opens, displays prices, can Restore

## 11. Testing Strategy

### 11.1 `SharedAccountKit` package unit tests

- `AuthService`: mocked URLSession, verify token storage, single-flight refresh, 401 handling, logout state
- `SubscriptionService`: mocked RC `Purchases` (via protocol wrapper inside the package), verify state machine, tier-sync polling
- `SyncEngine`: in-memory `SyncAPIClient` stub, fake codec + collector + merger, verify push/pull cycle, debounce, backoff, tombstone application
- `IdentityPayloadCodec`: trivial round-trip

### 11.2 SnapKei integration tests

- `SnapKeiChangeCollector` against a SwiftData in-memory store: insert, update, delete → expect correct envelopes
- `SnapKeiMerger`: apply envelopes against in-memory store, verify LWW, verify tombstone deletion
- `AIProxyService` against a mocked `AuthService`: 401 flow, token refresh

### 11.3 Manual smoke tests (per release)

- Sign in fresh, complete a purchase in sandbox, verify entitlement becomes active in both apps
- Capture a receipt in SnapKei, observe automatic sync, sign in to ConchTalk on a second device → not applicable to ConchTalk; just verify SnapKei pulls down on second SnapKei device
- Delete account → verify R2 sync data cleared (already wired in `/auth/account`)

## 12. Risks & Open Questions

| Risk | Mitigation |
|---|---|
| ConchTalk users hit P3 with stale tokens after keychain migration | Migration is idempotent; old keys remain for 1 release cycle as fallback |
| Entitlement rename causes paid users to appear free briefly | Dual-attach during transition (§7.3) |
| Auto-sync floods backend with tiny pushes during bulk import | 2s debounce + exponential backoff cap at 5min |
| SnapKei's `updatedAt` migration on `JournalEntry`/`FixedAsset` breaks existing local data | Default backfill to "now" for existing rows; sync is opt-in so no data loss before user toggles it on |
| Path-package dependency requires CI agents to have both repos cloned at the right paths | Documented in each repo's README; CI runs `git clone` for both into expected paths |

Open questions:

- None blocking; all spec'd decisions confirmed during brainstorming.

## 13. Operational Checklist (before P1+P2 ship)

- [ ] RevenueCat dashboard: SnapKei iOS App added under existing ConchTalk Project
- [ ] RevenueCat: `"pro"` entitlement created; attached to ConchTalk's Pro products + SnapKei's new Pro products
- [ ] App Store Connect: SnapKei IAP products created with matching pricing
- [ ] SnapKei `Secrets.xcconfig`: `REVENUECAT_API_KEY` set (same key as ConchTalk's RC Project)
- [ ] Apple sub-bundle registration: gateway `apps` table contains SnapKei's bundle ID (already true per migration `0026`)
- [ ] R2 bucket for sync data confirmed accessible from gateway worker (existing)

## 14. References

- Gateway endpoints: `~/workspace/llm-gateway-back/src/index.ts:22-91`
- ConchTalk AuthService: `~/workspace/conchtalk/Sources/Data/Network/AuthService.swift`
- ConchTalk SyncService: `~/workspace/conchtalk/Sources/Data/Sync/SyncService.swift`
- ConchTalk SettingsView: `~/workspace/conchtalk/Sources/Presentation/Settings/SettingsView.swift`
- SnapKei current SettingsView: `~/workspace/SnapKei/SnapKei/Presentation/Settings/SettingsView.swift`
- SnapKei current AIProxyService: `~/workspace/SnapKei/SnapKei/Data/Network/AIProxyService.swift`
