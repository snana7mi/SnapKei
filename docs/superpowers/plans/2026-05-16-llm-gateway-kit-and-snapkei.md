# LLMGatewayKit & SnapKei Adoption — Implementation Plan (P1 + P2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `LLMGatewayKit` open-source Swift Package (P1) and integrate it into SnapKei to replace the current stub auth/sync with a working Apple Sign In + paid subscription + R1 cloud sync setup (P2).

**Architecture:** Public-on-GitHub Swift Package at `github.com/snana7mi/LLMGatewayKit` provides `AuthService`, `SubscriptionService`, `SyncEngine`, `ProfileView`, `PaywallView`. SnapKei depends on it via versioned git-URL SwiftPM dependency, implements two app-specific protocols (`SyncChangeCollecting`, `SyncMerging`) against SwiftData entities, and rebuilds `SettingsView` in the ConchTalk style.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AuthenticationServices, RevenueCat 5.x, XCTest, Swift Testing.

**Spec reference:** `docs/superpowers/specs/2026-05-16-llm-gateway-kit-design.md`

---

## Prerequisites (operator-side, before Task 1)

- GitHub account `snana7mi` accessible with `gh` CLI authenticated
- `gh auth status` reports logged-in
- `~/workspace/` exists and is writable
- Xcode 26+ with iOS 18.5 SDK installed
- RevenueCat dashboard access (for §7.3 of the spec — operator handles this manually; not blocking for code work)

---

# Part I — LLMGatewayKit Package (P1)

> All P1 work happens in `~/workspace/LLMGatewayKit`. Each task ends with `git commit` in that repo. After Task 18, the repo is tagged `0.1.0` and pushed to GitHub.

---

## Task 1: Scaffold the LLMGatewayKit repo

**Files:**
- Create: `~/workspace/LLMGatewayKit/Package.swift`
- Create: `~/workspace/LLMGatewayKit/README.md`
- Create: `~/workspace/LLMGatewayKit/LICENSE`
- Create: `~/workspace/LLMGatewayKit/.gitignore`
- Create: `~/workspace/LLMGatewayKit/Sources/LLMGatewayKit/LLMGatewayKit.swift`
- Create: `~/workspace/LLMGatewayKit/Tests/LLMGatewayKitTests/SmokeTests.swift`

- [ ] **Step 1: Create the directory and initialize git**

```bash
mkdir -p ~/workspace/LLMGatewayKit
cd ~/workspace/LLMGatewayKit
git init
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMGatewayKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "LLMGatewayKit", targets: ["LLMGatewayKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "LLMGatewayKit",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LLMGatewayKitTests", dependencies: ["LLMGatewayKit"]),
    ]
)
```

- [ ] **Step 3: Write minimal `README.md`**

```markdown
# LLMGatewayKit

Swift client SDK for [llm-gateway-back](https://github.com/snana7mi/llm-gateway-back),
plus shared account/subscription/sync infrastructure used by SnapKei and ConchTalk.

## Install

```swift
.package(url: "https://github.com/snana7mi/LLMGatewayKit", from: "0.1.0")
```

## Status

0.1.x — public API may change before 1.0.

## License

MIT.
```

- [ ] **Step 4: Write `LICENSE` (MIT)**

Use the standard MIT template; copyright holder is `snana7mi`; year `2026`. Get the exact text via:

```bash
curl -sL https://opensource.org/licenses/MIT > /tmp/mit.txt
# Then construct LICENSE with header lines and the body, replacing [year] and [fullname].
```

Final file contents (paste verbatim, replacing nothing further):

```
MIT License

Copyright (c) 2026 snana7mi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5: Write `.gitignore`**

```
.DS_Store
.build/
.swiftpm/
DerivedData/
Package.resolved
*.xcodeproj
```

- [ ] **Step 6: Write smoke target source**

`Sources/LLMGatewayKit/LLMGatewayKit.swift`:

```swift
public enum LLMGatewayKit {
    public static let version = "0.1.0"
}
```

- [ ] **Step 7: Write smoke test**

`Tests/LLMGatewayKitTests/SmokeTests.swift`:

```swift
import XCTest
@testable import LLMGatewayKit

final class SmokeTests: XCTestCase {
    func test_version() {
        XCTAssertEqual(LLMGatewayKit.version, "0.1.0")
    }
}
```

- [ ] **Step 8: Verify the build**

Run:
```bash
cd ~/workspace/LLMGatewayKit
swift build
swift test
```
Expected: both succeed; one test passes.

- [ ] **Step 9: Create the public GitHub repo and commit**

```bash
cd ~/workspace/LLMGatewayKit
gh repo create snana7mi/LLMGatewayKit --public --description "Swift client SDK for llm-gateway-back + shared account/subscription/sync used by SnapKei and ConchTalk" --license MIT
git add -A
git commit -m "Initial scaffolding of LLMGatewayKit"
git branch -M main
git push -u origin main
```

---

## Task 2: Config types — `LLMGatewayKitConfig`, `PaywallFeature`

**Files:**
- Create: `Sources/LLMGatewayKit/Config/LLMGatewayKitConfig.swift`
- Create: `Tests/LLMGatewayKitTests/Config/LLMGatewayKitConfigTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class LLMGatewayKitConfigTests: XCTestCase {
    func test_initStoresProperties() {
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: "https://api.conch-talk.com")!,
            entitlementID: "pro",
            appDisplayName: "SnapKei",
            companionAppNames: ["ConchTalk"],
            revenueCatAPIKey: "key_abc",
            paywallFeatures: [.init(id: "f1", icon: "star", title: "Feature 1", subtitle: nil)],
            deviceName: "TestDevice"
        )
        XCTAssertEqual(config.entitlementID, "pro")
        XCTAssertEqual(config.companionAppNames, ["ConchTalk"])
        XCTAssertEqual(config.paywallFeatures.first?.title, "Feature 1")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter LLMGatewayKitConfigTests
```
Expected: FAIL — type `LLMGatewayKitConfig` not found.

- [ ] **Step 3: Implement the types**

```swift
import Foundation

public struct LLMGatewayKitConfig: Sendable {
    public let baseURL: URL
    public let entitlementID: String
    public let appDisplayName: String
    public let companionAppNames: [String]
    public let revenueCatAPIKey: String?
    public let paywallFeatures: [PaywallFeature]
    public let deviceName: String

    public init(
        baseURL: URL,
        entitlementID: String,
        appDisplayName: String,
        companionAppNames: [String],
        revenueCatAPIKey: String?,
        paywallFeatures: [PaywallFeature],
        deviceName: String
    ) {
        self.baseURL = baseURL
        self.entitlementID = entitlementID
        self.appDisplayName = appDisplayName
        self.companionAppNames = companionAppNames
        self.revenueCatAPIKey = revenueCatAPIKey
        self.paywallFeatures = paywallFeatures
        self.deviceName = deviceName
    }
}

public struct PaywallFeature: Sendable, Identifiable, Equatable {
    public let id: String
    public let icon: String
    public let title: String
    public let subtitle: String?

    public init(id: String, icon: String, title: String, subtitle: String?) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter LLMGatewayKitConfigTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LLMGatewayKit/Config Tests/LLMGatewayKitTests/Config
git commit -m "Add LLMGatewayKitConfig and PaywallFeature"
```

---

## Task 3: Domain models — `AccountUser`, `UsageInfo`, `UsageBreakdown`, `AuthError`

**Files:**
- Create: `Sources/LLMGatewayKit/Models/AccountUser.swift`
- Create: `Sources/LLMGatewayKit/Models/UsageInfo.swift`
- Create: `Sources/LLMGatewayKit/Auth/AuthError.swift`
- Create: `Tests/LLMGatewayKitTests/Models/AccountUserTests.swift`
- Create: `Tests/LLMGatewayKitTests/Models/UsageInfoTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/LLMGatewayKitTests/Models/AccountUserTests.swift`:

```swift
import XCTest
@testable import LLMGatewayKit

final class AccountUserTests: XCTestCase {
    func test_equality() {
        let a = AccountUser(id: "u1", email: "e@x", displayName: "N", tier: "paid",
                            tierExpiresAt: nil, createdAt: nil, avatarURL: nil)
        let b = AccountUser(id: "u1", email: "e@x", displayName: "N", tier: "paid",
                            tierExpiresAt: nil, createdAt: nil, avatarURL: nil)
        XCTAssertEqual(a, b)
    }
}
```

`Tests/LLMGatewayKitTests/Models/UsageInfoTests.swift`:

```swift
import XCTest
@testable import LLMGatewayKit

final class UsageInfoTests: XCTestCase {
    func test_formattedAmounts() {
        let u = UsageInfo(budgetUsed: 1_500_000, budgetLimit: 5_000_000, percentage: 30.0,
                          resetsAt: nil, tier: "paid", breakdown: [])
        XCTAssertEqual(u.formattedBudgetUsed, "$1.50")
        XCTAssertEqual(u.formattedBudgetLimit, "$5.00")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter AccountUserTests
swift test --filter UsageInfoTests
```
Expected: FAIL — types not found.

- [ ] **Step 3: Implement**

`Sources/LLMGatewayKit/Models/AccountUser.swift`:

```swift
import Foundation

public struct AccountUser: Sendable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let tier: String
    public let tierExpiresAt: String?
    public let createdAt: String?
    public let avatarURL: String?

    public init(id: String, email: String?, displayName: String?, tier: String,
                tierExpiresAt: String?, createdAt: String?, avatarURL: String?) {
        self.id = id; self.email = email; self.displayName = displayName
        self.tier = tier; self.tierExpiresAt = tierExpiresAt
        self.createdAt = createdAt; self.avatarURL = avatarURL
    }
}
```

`Sources/LLMGatewayKit/Models/UsageInfo.swift`:

```swift
import Foundation

public struct UsageInfo: Sendable, Equatable {
    public let budgetUsed: Int         // micro-USD
    public let budgetLimit: Int        // micro-USD
    public let percentage: Double
    public let resetsAt: String?
    public let tier: String
    public let breakdown: [UsageBreakdown]

    public init(budgetUsed: Int, budgetLimit: Int, percentage: Double,
                resetsAt: String?, tier: String, breakdown: [UsageBreakdown]) {
        self.budgetUsed = budgetUsed; self.budgetLimit = budgetLimit
        self.percentage = percentage; self.resetsAt = resetsAt
        self.tier = tier; self.breakdown = breakdown
    }

    public var formattedBudgetUsed: String {
        String(format: "$%.2f", Double(budgetUsed) / 1_000_000.0)
    }
    public var formattedBudgetLimit: String {
        String(format: "$%.2f", Double(budgetLimit) / 1_000_000.0)
    }
}

public struct UsageBreakdown: Sendable, Equatable {
    public let appId: String
    public let callCount: Int
    public let costUsed: Int

    public init(appId: String, callCount: Int, costUsed: Int) {
        self.appId = appId; self.callCount = callCount; self.costUsed = costUsed
    }
}
```

`Sources/LLMGatewayKit/Auth/AuthError.swift`:

```swift
import Foundation

public enum AuthError: LocalizedError, Sendable, Equatable {
    case notLoggedIn
    case sessionExpired
    case invalidURL
    case networkError
    case invalidResponse
    case serverError(String)
    case accountDeletionFailed

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:            return "Please sign in to continue."
        case .sessionExpired:         return "Session expired. Please sign in again."
        case .invalidURL:             return "Invalid server URL."
        case .networkError:           return "Network error."
        case .invalidResponse:        return "Invalid server response."
        case .serverError(let msg):   return "Server error: \(msg)"
        case .accountDeletionFailed:  return "Failed to delete account."
        }
    }
}
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
swift test --filter "AccountUserTests|UsageInfoTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/LLMGatewayKit/Models Sources/LLMGatewayKit/Auth/AuthError.swift Tests/LLMGatewayKitTests/Models
git commit -m "Add AccountUser, UsageInfo, UsageBreakdown, AuthError"
```

---

## Task 4: `KeychainTokenStore`

**Files:**
- Create: `Sources/LLMGatewayKit/Auth/KeychainTokenStore.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/KeychainTokenStoreTests.swift`

The store wraps Apple's keychain for three secrets — access token, refresh token, expiry — under a configurable service name so each app keeps its own keys.

- [ ] **Step 1: Write failing test (uses an in-memory test seam)**

```swift
import XCTest
@testable import LLMGatewayKit

final class KeychainTokenStoreTests: XCTestCase {
    func test_roundTrip() throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "A", refreshToken: "R", expiry: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.loadAccessToken(), "A")
        XCTAssertEqual(try store.loadRefreshToken(), "R")
        XCTAssertEqual(try store.loadExpiry()?.timeIntervalSince1970, 1000)
    }

    func test_clear() throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "A", refreshToken: "R", expiry: Date())
        try store.clear()
        XCTAssertNil(try store.loadAccessToken())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: types `InMemoryTokenStore` and `TokenStoring` not found.

- [ ] **Step 3: Implement the protocol + two concrete stores**

```swift
import Foundation
import Security

public protocol TokenStoring: Sendable {
    func save(accessToken: String, refreshToken: String, expiry: Date) throws
    func loadAccessToken() throws -> String?
    func loadRefreshToken() throws -> String?
    func loadExpiry() throws -> Date?
    func clear() throws
}

public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    private enum Keys {
        static let access = "kit.accessToken"
        static let refresh = "kit.refreshToken"
        static let expiry = "kit.tokenExpiry"
    }
    private let service: String

    public init(service: String = "LLMGatewayKit") {
        self.service = service
    }

    public func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        try writeString(accessToken, account: Keys.access)
        try writeString(refreshToken, account: Keys.refresh)
        try writeString(ISO8601DateFormatter().string(from: expiry), account: Keys.expiry)
    }

    public func loadAccessToken() throws -> String? { try readString(Keys.access) }
    public func loadRefreshToken() throws -> String? { try readString(Keys.refresh) }
    public func loadExpiry() throws -> Date? {
        guard let s = try readString(Keys.expiry) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    public func clear() throws {
        try delete(Keys.access)
        try delete(Keys.refresh)
        try delete(Keys.expiry)
    }

    private func writeString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(account)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.serverError("Keychain add \(status)") }
    }

    private func readString(_ account: String) throws -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthError.serverError("Keychain read \(status)")
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.serverError("Keychain delete \(status)")
        }
    }
}

public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var access: String?
    private var refresh: String?
    private var expiry: Date?

    public init() {}

    public func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        lock.lock(); defer { lock.unlock() }
        self.access = accessToken; self.refresh = refreshToken; self.expiry = expiry
    }
    public func loadAccessToken() throws -> String? { lock.withLock { access } }
    public func loadRefreshToken() throws -> String? { lock.withLock { refresh } }
    public func loadExpiry() throws -> Date? { lock.withLock { expiry } }
    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        access = nil; refresh = nil; expiry = nil
    }
}
```

- [ ] **Step 4: Run test and confirm pass**

```bash
swift test --filter KeychainTokenStoreTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/LLMGatewayKit/Auth/KeychainTokenStore.swift Tests/LLMGatewayKitTests/Auth
git commit -m "Add KeychainTokenStore and in-memory test seam"
```

---

## Task 5: `AppleSignInBridge`

**Files:**
- Create: `Sources/LLMGatewayKit/Auth/AppleSignInBridge.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AppleSignInBridgeTests.swift`

A protocol + UIKit-backed implementation that wraps `ASAuthorizationController`. The implementation is iOS-only; tests run against a mock conforming to the protocol.

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class AppleSignInBridgeTests: XCTestCase {
    func test_protocolConformance() async throws {
        let mock = MockAppleSignInBridge(
            result: .success(.init(identityToken: "tok", appleUserId: "sub"))
        )
        let result = try await mock.authenticate(nonceRaw: "n", hashedNonce: "h")
        XCTAssertEqual(result.identityToken, "tok")
        XCTAssertEqual(result.appleUserId, "sub")
    }
}

final class MockAppleSignInBridge: AppleSignInAuthenticating, @unchecked Sendable {
    let result: Result<AppleSignInResult, Error>
    init(result: Result<AppleSignInResult, Error>) { self.result = result }
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        try result.get()
    }
}
```

- [ ] **Step 2: Implement protocol + result + concrete bridge**

```swift
import AuthenticationServices
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct AppleSignInResult: Sendable, Equatable {
    public let identityToken: String
    public let appleUserId: String
    public init(identityToken: String, appleUserId: String) {
        self.identityToken = identityToken; self.appleUserId = appleUserId
    }
}

public protocol AppleSignInAuthenticating: Sendable {
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult
}

@MainActor
public final class AppleSignInBridge: NSObject, AppleSignInAuthenticating {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    public override init() { super.init() }

    public func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        guard continuation == nil else { throw AuthError.serverError("Sign-in already in progress") }
        return try await withCheckedThrowingContinuation { c in
            self.continuation = c
            let req = ASAuthorizationAppleIDProvider().createRequest()
            req.requestedScopes = [.fullName, .email]
            req.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [req])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleSignInBridge: ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithAuthorization auth: ASAuthorization) {
        defer { continuation = nil }
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken,
              let tok = String(data: data, encoding: .utf8) else {
            continuation?.resume(throwing: AuthError.invalidResponse); return
        }
        continuation?.resume(returning: .init(identityToken: tok, appleUserId: cred.user))
    }

    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppleSignInBridge: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter AppleSignInBridgeTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/LLMGatewayKit/Auth/AppleSignInBridge.swift Tests/LLMGatewayKitTests/Auth/AppleSignInBridgeTests.swift
git commit -m "Add AppleSignInBridge with mockable protocol"
```

---

## Task 6: `NonceGenerator` helper

**Files:**
- Create: `Sources/LLMGatewayKit/Auth/NonceGenerator.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/NonceGeneratorTests.swift`

(Same logic SnapKei already has in `SnapKei/Data/Auth/NonceGenerator.swift`; move into the package to centralize.)

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class NonceGeneratorTests: XCTestCase {
    func test_pairHasNonEmptyRawAndHashedDifferent() {
        let pair = NonceGenerator.makePair()
        XCTAssertFalse(pair.raw.isEmpty)
        XCTAssertFalse(pair.hashedSHA256.isEmpty)
        XCTAssertNotEqual(pair.raw, pair.hashedSHA256)
    }

    func test_hashIsSHA256Hex() {
        let pair = NonceGenerator.makePair()
        XCTAssertEqual(pair.hashedSHA256.count, 64)
        XCTAssertTrue(pair.hashedSHA256.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
```

- [ ] **Step 2: Implement**

```swift
import CryptoKit
import Foundation

public enum NonceGenerator {
    public struct Pair: Sendable {
        public let raw: String
        public let hashedSHA256: String
    }

    public static func makePair(length: Int = 32) -> Pair {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var raw = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for b in bytes { raw.append(charset[Int(b) % charset.count]) }
        let hashed = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return Pair(raw: raw, hashedSHA256: hashed)
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter NonceGeneratorTests
git add Sources/LLMGatewayKit/Auth/NonceGenerator.swift Tests/LLMGatewayKitTests/Auth/NonceGeneratorTests.swift
git commit -m "Add NonceGenerator (CryptoKit-backed)"
```

---

## Task 7: `AuthService` — scaffolding + authenticate

**Files:**
- Create: `Sources/LLMGatewayKit/Auth/AuthService.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AuthServiceAuthenticateTests.swift`

We construct `AuthService` with a `TokenStoring`, an `AppleSignInAuthenticating`, a `URLSession`, and the `LLMGatewayKitConfig`. This task implements only `authenticate(identityToken:fullName:appleSub:)` and the supporting state.

- [ ] **Step 1: Write failing test (stubbed URLSession via URLProtocol)**

```swift
import XCTest
@testable import LLMGatewayKit

final class AuthServiceAuthenticateTests: XCTestCase {
    func test_authenticate_storesTokensAndUser() async throws {
        let json = """
        {"accessToken":"acc","refreshToken":"ref","user":{"id":"u","tier":"paid","displayName":"D","email":"e@x"}}
        """
        URLProtocolStub.responses = [.success(body: json, status: 200)]

        let session = URLSession(configuration: URLProtocolStub.makeConfig())
        let store = InMemoryTokenStore()
        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .success(.init(identityToken: "t", appleUserId: "sub"))),
                              session: session)

        try await sut.authenticate(
            identityToken: Data("rawToken".utf8),
            fullName: "Full Name",
            appleSub: "sub"
        )

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(sut.currentUser?.id, "u")
        XCTAssertEqual(try store.loadAccessToken(), "acc")
        XCTAssertEqual(try store.loadRefreshToken(), "ref")
    }
}

enum TestConfig {
    static func make() -> LLMGatewayKitConfig {
        .init(baseURL: URL(string: "https://api.test")!, entitlementID: "pro",
              appDisplayName: "Test", companionAppNames: [],
              revenueCatAPIKey: nil, paywallFeatures: [],
              deviceName: "Test Device")
    }
}
```

Add `URLProtocolStub` test helper at `Tests/LLMGatewayKitTests/Helpers/URLProtocolStub.swift`:

```swift
import Foundation

final class URLProtocolStub: URLProtocol {
    enum Response {
        case success(body: String, status: Int)
        case failure(URLError)
    }
    static var responses: [Response] = []
    static var requests: [URLRequest] = []

    static func makeConfig() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [URLProtocolStub.self]
        return c
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        URLProtocolStub.requests.append(request)
        guard !URLProtocolStub.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = URLProtocolStub.responses.removeFirst()
        switch response {
        case .success(let body, let status):
            let http = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let err):
            client?.urlProtocol(self, didFailWithError: err)
        }
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: type `AuthService` not found.

- [ ] **Step 3: Implement `AuthService` scaffolding + `authenticate`**

```swift
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class AuthService {
    public private(set) var isLoggedIn: Bool = false
    public private(set) var currentUser: AccountUser?
    public private(set) var cachedAvatarData: Data?

    public var cachedAppleSub: String? {
        UserDefaults.standard.string(forKey: Keys.cachedAppleSub)
    }

    enum Keys {
        static let cachedAppleSub = "LLMGatewayKit.cachedAppleSub"
        static let migrationDone  = "LLMGatewayKit.migrationDone"
    }

    private let config: LLMGatewayKitConfig
    private let tokenStore: TokenStoring
    private let appleBridge: AppleSignInAuthenticating
    private let session: URLSession
    private var refreshTask: Task<Void, Error>?
    private var cachedAvatarURL: String?

    public init(config: LLMGatewayKitConfig,
                tokenStore: TokenStoring = KeychainTokenStore(),
                appleBridge: AppleSignInAuthenticating? = nil,
                session: URLSession = .shared) {
        self.config = config
        self.tokenStore = tokenStore
        self.session = session
        self.appleBridge = appleBridge ?? {
            #if canImport(UIKit)
            return AppleSignInBridge()
            #else
            return _UnavailableAppleBridge()
            #endif
        }()
    }

    public func authenticate(identityToken: Data, fullName: String?, appleSub: String) async throws {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidResponse
        }
        var body: [String: Any] = ["identityToken": tokenString, "deviceName": config.deviceName]
        if let fullName, !fullName.isEmpty { body["displayName"] = fullName }

        let data = try await postJSON(path: "/auth/apple", body: body)
        let parsed = try Self.parseTokenResponse(data)
        try tokenStore.save(accessToken: parsed.accessToken, refreshToken: parsed.refreshToken,
                            expiry: Date().addingTimeInterval(15 * 60))
        isLoggedIn = true
        currentUser = parsed.user
        UserDefaults.standard.set(appleSub, forKey: Keys.cachedAppleSub)
    }

    // MARK: - Helpers

    func postJSON(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: config.baseURL.absoluteString + path) else { throw AuthError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        return try await performJSON(req)
    }

    func performJSON(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["error"] as? String { throw AuthError.serverError(msg) }
            }
            throw AuthError.serverError("HTTP \(http.statusCode)")
        }
        return data
    }

    static func parseTokenResponse(_ data: Data) throws -> (accessToken: String, refreshToken: String, user: AccountUser?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["accessToken"] as? String,
              let refresh = json["refreshToken"] as? String else {
            throw AuthError.invalidResponse
        }
        var user: AccountUser? = nil
        if let userDict = json["user"] as? [String: Any],
           let id = userDict["id"] as? String,
           let tier = userDict["tier"] as? String {
            user = AccountUser(
                id: id, email: userDict["email"] as? String,
                displayName: userDict["displayName"] as? String, tier: tier,
                tierExpiresAt: userDict["tierExpiresAt"] as? String,
                createdAt: userDict["createdAt"] as? String,
                avatarURL: userDict["avatarURL"] as? String)
        }
        return (access, refresh, user)
    }
}

// Fallback that throws (used on non-UIKit platforms; never hit on iOS).
private struct _UnavailableAppleBridge: AppleSignInAuthenticating {
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        throw AuthError.serverError("Apple sign-in unavailable on this platform")
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter AuthServiceAuthenticateTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/LLMGatewayKit/Auth/AuthService.swift Tests/LLMGatewayKitTests/Auth Tests/LLMGatewayKitTests/Helpers
git commit -m "AuthService: scaffolding + authenticate()"
```

---

## Task 8: `AuthService` — `validAccessToken` + single-flight `refreshAccessToken`

**Files:**
- Modify: `Sources/LLMGatewayKit/Auth/AuthService.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AuthServiceRefreshTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import LLMGatewayKit

final class AuthServiceRefreshTests: XCTestCase {
    @MainActor
    func test_validAccessToken_refreshesWhenNearExpiry() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(30)) // <60s

        URLProtocolStub.responses = [.success(body: #"{"accessToken":"new","refreshToken":"ref2"}"#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        let token = try await sut.validAccessToken()
        XCTAssertEqual(token, "new")
        XCTAssertEqual(try store.loadAccessToken(), "new")
    }

    @MainActor
    func test_concurrentRefresh_coalescesIntoOneRequest() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(10))

        URLProtocolStub.requests = []
        URLProtocolStub.responses = [.success(body: #"{"accessToken":"new","refreshToken":"r2"}"#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        async let t1 = sut.validAccessToken()
        async let t2 = sut.validAccessToken()
        let (a, b) = try await (t1, t2)
        XCTAssertEqual(a, "new")
        XCTAssertEqual(b, "new")
        XCTAssertEqual(URLProtocolStub.requests.count, 1)
    }
}
```

- [ ] **Step 2: Implement methods in `AuthService`**

Add inside `AuthService`:

```swift
    public func restoreSession() {
        if (try? tokenStore.loadAccessToken()) ?? nil != nil,
           (try? tokenStore.loadRefreshToken()) ?? nil != nil {
            isLoggedIn = true
            Task { try? await fetchAccount() }
        }
    }

    public func validAccessToken() async throws -> String {
        guard let access = try tokenStore.loadAccessToken() else { throw AuthError.notLoggedIn }
        let expiry = try tokenStore.loadExpiry()
        if let expiry, expiry.timeIntervalSinceNow < 60 {
            try await refreshAccessToken()
            guard let renewed = try tokenStore.loadAccessToken() else { throw AuthError.notLoggedIn }
            return renewed
        }
        return access
    }

    public func refreshAccessToken() async throws {
        if let existing = refreshTask { return try await existing.value }
        let task = Task { defer { self.refreshTask = nil }; try await performRefresh() }
        refreshTask = task
        try await task.value
    }

    private func performRefresh() async throws {
        guard let refresh = try tokenStore.loadRefreshToken() else {
            await logout(); throw AuthError.notLoggedIn
        }
        let body: [String: Any] = ["refreshToken": refresh, "deviceName": config.deviceName]
        do {
            let data = try await postJSON(path: "/auth/refresh", body: body)
            let parsed = try Self.parseTokenResponse(data)
            try tokenStore.save(accessToken: parsed.accessToken,
                                refreshToken: parsed.refreshToken,
                                expiry: Date().addingTimeInterval(15 * 60))
        } catch is URLError {
            // Network: keep session, surface error
            throw URLError(.notConnectedToInternet)
        } catch {
            await logout()
            throw AuthError.sessionExpired
        }
    }
```

Stub these methods at the bottom of `AuthService` (full impl in later tasks):

```swift
    public func logout() async { /* will be implemented in Task 9 */ }
    public func fetchAccount() async throws { /* will be implemented in Task 10 */ }
```

- [ ] **Step 3: Run tests, confirm pass**

```bash
swift test --filter AuthServiceRefreshTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/LLMGatewayKit/Auth/AuthService.swift Tests/LLMGatewayKitTests/Auth/AuthServiceRefreshTests.swift
git commit -m "AuthService: validAccessToken + single-flight refresh"
```

---

## Task 9: `AuthService` — `logout` + `deleteAccount`

**Files:**
- Modify: `Sources/LLMGatewayKit/Auth/AuthService.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AuthServiceLogoutTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import LLMGatewayKit

final class AuthServiceLogoutTests: XCTestCase {
    @MainActor
    func test_logout_clearsAllState() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        UserDefaults.standard.set("sub", forKey: AuthService.Keys.cachedAppleSub)

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        await sut.logout()

        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(sut.currentUser)
        XCTAssertNil(try store.loadAccessToken())
        XCTAssertNil(UserDefaults.standard.string(forKey: AuthService.Keys.cachedAppleSub))
    }

    @MainActor
    func test_deleteAccount_callsEndpointAndLogsOut() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.responses = [.success(body: #"{"success":true}"#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        try await sut.deleteAccount()
        XCTAssertFalse(sut.isLoggedIn)
    }
}
```

- [ ] **Step 2: Replace the stubs in `AuthService`**

```swift
    public func logout() async {
        try? tokenStore.clear()
        isLoggedIn = false
        currentUser = nil
        cachedAvatarData = nil
        cachedAvatarURL = nil
        UserDefaults.standard.removeObject(forKey: Keys.cachedAppleSub)
    }

    public func deleteAccount() async throws {
        let token = try await validAccessToken()
        guard let url = URL(string: config.baseURL.absoluteString + "/auth/account") else { throw AuthError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await performJSON(req)
        await logout()
    }
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter AuthServiceLogoutTests
git add Sources/LLMGatewayKit/Auth/AuthService.swift Tests/LLMGatewayKitTests/Auth/AuthServiceLogoutTests.swift
git commit -m "AuthService: logout and deleteAccount"
```

---

## Task 10: `AuthService` — `fetchAccount` + `fetchUsage`

**Files:**
- Modify: `Sources/LLMGatewayKit/Auth/AuthService.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AuthServiceAccountTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import LLMGatewayKit

final class AuthServiceAccountTests: XCTestCase {
    @MainActor
    func test_fetchAccount_populatesUser() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.responses = [.success(body: #"""
        {"user":{"id":"u","email":"e","displayName":"D","tier":"paid","avatarURL":"https://x"},"usage":{"budgetUsed":1,"budgetLimit":10,"percentage":10.0}}
        """#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        try await sut.fetchAccount()
        XCTAssertEqual(sut.currentUser?.tier, "paid")
        XCTAssertEqual(sut.currentUser?.avatarURL, "https://x")
    }

    @MainActor
    func test_fetchUsage_returnsParsedInfo() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.responses = [.success(body: #"""
        {"budgetUsed":250000,"budgetLimit":1000000,"percentage":25.0,"resetsAt":"2026-06-01T00:00:00Z","tier":"paid","breakdown":[]}
        """#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        let info = try await sut.fetchUsage()
        XCTAssertEqual(info.percentage, 25.0)
        XCTAssertEqual(info.tier, "paid")
    }
}
```

- [ ] **Step 2: Implement**

Add to `AuthService`:

```swift
    public func fetchAccount() async throws {
        let token = try await validAccessToken()
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/account")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await performJSON(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = json["user"] as? [String: Any],
              let id = dict["id"] as? String,
              let tier = dict["tier"] as? String else { throw AuthError.invalidResponse }
        currentUser = AccountUser(
            id: id, email: dict["email"] as? String,
            displayName: dict["displayName"] as? String, tier: tier,
            tierExpiresAt: dict["tierExpiresAt"] as? String,
            createdAt: dict["createdAt"] as? String,
            avatarURL: dict["avatarURL"] as? String)
    }

    public func fetchUsage() async throws -> UsageInfo {
        let token = try await validAccessToken()
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await performJSON(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = json["budgetUsed"] as? Int,
              let limit = json["budgetLimit"] as? Int,
              let pct = json["percentage"] as? Double,
              let tier = json["tier"] as? String else { throw AuthError.invalidResponse }
        let breakdown = (json["breakdown"] as? [[String: Any]] ?? []).compactMap { d -> UsageBreakdown? in
            guard let app = d["appId"] as? String,
                  let calls = d["callCount"] as? Int,
                  let cost = d["costUsed"] as? Int else { return nil }
            return UsageBreakdown(appId: app, callCount: calls, costUsed: cost)
        }
        return UsageInfo(budgetUsed: used, budgetLimit: limit, percentage: pct,
                         resetsAt: json["resetsAt"] as? String, tier: tier, breakdown: breakdown)
    }

    public func updateCurrentUser(_ user: AccountUser) {
        currentUser = user
    }
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter AuthServiceAccountTests
git add Sources/LLMGatewayKit/Auth/AuthService.swift Tests/LLMGatewayKitTests/Auth/AuthServiceAccountTests.swift
git commit -m "AuthService: fetchAccount, fetchUsage, updateCurrentUser"
```

---

## Task 11: `AuthService` — `uploadAvatar`, `loadAvatarDataIfNeeded`, `authenticateInteractively`

**Files:**
- Modify: `Sources/LLMGatewayKit/Auth/AuthService.swift`
- Create: `Tests/LLMGatewayKitTests/Auth/AuthServiceAvatarTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import LLMGatewayKit

final class AuthServiceAvatarTests: XCTestCase {
    @MainActor
    func test_uploadAvatar_updatesUserAvatarURL() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.responses = [.success(body: #"{"avatarURL":"https://avatars.x/u.jpg"}"#, status: 200)]

        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        sut.updateCurrentUser(.init(id: "u", email: nil, displayName: nil, tier: "paid",
                                    tierExpiresAt: nil, createdAt: nil, avatarURL: nil))
        let url = try await sut.uploadAvatar(imageData: Data([0xFF, 0xD8]))
        XCTAssertEqual(url, "https://avatars.x/u.jpg")
        XCTAssertEqual(sut.currentUser?.avatarURL, url)
    }

    @MainActor
    func test_authenticateInteractively_callsBridgeAndAuthenticate() async throws {
        URLProtocolStub.responses = [.success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free"}}"#, status: 200)]
        let store = InMemoryTokenStore()
        let bridge = MockAppleSignInBridge(result: .success(.init(identityToken: "raw", appleUserId: "sub-x")))
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: bridge,
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        try await sut.authenticateInteractively()
        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AuthService.Keys.cachedAppleSub), "sub-x")
    }
}
```

- [ ] **Step 2: Implement**

```swift
    public func uploadAvatar(imageData: Data) async throws -> String {
        let token = try await validAccessToken()
        let boundary = UUID().uuidString
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/account/avatar")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let data = try await performJSON(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["avatarURL"] as? String else { throw AuthError.invalidResponse }
        if let user = currentUser {
            currentUser = AccountUser(id: user.id, email: user.email, displayName: user.displayName,
                                      tier: user.tier, tierExpiresAt: user.tierExpiresAt,
                                      createdAt: user.createdAt, avatarURL: url)
        }
        cachedAvatarData = imageData
        cachedAvatarURL = url
        return url
    }

    public func loadAvatarDataIfNeeded() async -> Data? {
        guard let urlStr = currentUser?.avatarURL, !urlStr.isEmpty else { return nil }
        if urlStr == cachedAvatarURL, let cached = cachedAvatarData { return cached }
        guard let url = URL(string: urlStr), let (data, _) = try? await session.data(from: url) else { return nil }
        cachedAvatarData = data
        cachedAvatarURL = urlStr
        return data
    }

    public func authenticateInteractively() async throws {
        let pair = NonceGenerator.makePair()
        let result = try await appleBridge.authenticate(nonceRaw: pair.raw, hashedNonce: pair.hashedSHA256)
        try await authenticate(
            identityToken: Data(result.identityToken.utf8),
            fullName: nil,
            appleSub: result.appleUserId
        )
    }
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter AuthServiceAvatarTests
git add Sources/LLMGatewayKit/Auth/AuthService.swift Tests/LLMGatewayKitTests/Auth/AuthServiceAvatarTests.swift
git commit -m "AuthService: uploadAvatar, loadAvatarDataIfNeeded, authenticateInteractively"
```

---

## Task 12: `SubscriptionService`

**Files:**
- Create: `Sources/LLMGatewayKit/Subscription/PurchaseState.swift`
- Create: `Sources/LLMGatewayKit/Subscription/SubscriptionService.swift`
- Create: `Tests/LLMGatewayKitTests/Subscription/SubscriptionServiceTests.swift`

The state-machine logic is testable in isolation if we mock the RevenueCat surface behind a protocol. The integration with `Purchases.shared` is exercised via the SnapKei target manually.

- [ ] **Step 1: Write failing state-machine test**

```swift
import XCTest
@testable import LLMGatewayKit

final class SubscriptionServiceTests: XCTestCase {
    @MainActor
    func test_purchase_requiresLogin() async {
        let auth = makeLoggedOutAuth()
        let sut = SubscriptionService(authService: auth, config: TestConfig.make(),
                                      purchaseClient: NoopPurchaseClient())
        await sut.purchase()
        if case .failed = sut.purchaseState { return }
        XCTFail("Expected .failed, got \(sut.purchaseState)")
    }
}
```

Add helper at `Tests/LLMGatewayKitTests/Helpers/AuthHelpers.swift`:

```swift
import Foundation
@testable import LLMGatewayKit

@MainActor func makeLoggedOutAuth() -> AuthService {
    AuthService(config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
                appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                session: URLSession(configuration: URLProtocolStub.makeConfig()))
}
```

- [ ] **Step 2: Implement types**

`Sources/LLMGatewayKit/Subscription/PurchaseState.swift`:

```swift
public enum PurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case verifying
    case success
    case failed(String)
}
```

`Sources/LLMGatewayKit/Subscription/SubscriptionService.swift`:

```swift
import Foundation
import Observation
import RevenueCat

public protocol PurchaseClient: Sendable {
    func currentOffering() async throws -> Offering?
    func purchase(_ package: Package) async throws -> PurchaseResultData
    func restore() async throws -> CustomerInfo
    func customerInfoStream() -> AsyncStream<CustomerInfo>
}

public struct LivePurchaseClient: PurchaseClient {
    public init() {}
    public func currentOffering() async throws -> Offering? {
        let offerings = try await Purchases.shared.offerings()
        return offerings.current
    }
    public func purchase(_ package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }
    public func restore() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }
    public func customerInfoStream() -> AsyncStream<CustomerInfo> {
        AsyncStream { continuation in
            Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(info)
                }
                continuation.finish()
            }
        }
    }
}

public struct NoopPurchaseClient: PurchaseClient {
    public init() {}
    public func currentOffering() async throws -> Offering? { nil }
    public func purchase(_ package: Package) async throws -> PurchaseResultData {
        throw AuthError.serverError("Not configured")
    }
    public func restore() async throws -> CustomerInfo { throw AuthError.serverError("Not configured") }
    public func customerInfoStream() -> AsyncStream<CustomerInfo> { AsyncStream { $0.finish() } }
}

@MainActor
@Observable
public final class SubscriptionService {
    public private(set) var displayPrice: String?
    public private(set) var purchaseState: PurchaseState = .idle

    private let authService: AuthService
    private let config: LLMGatewayKitConfig
    private let client: PurchaseClient

    public init(authService: AuthService, config: LLMGatewayKitConfig,
                purchaseClient: PurchaseClient = LivePurchaseClient()) {
        self.authService = authService; self.config = config; self.client = purchaseClient
    }

    public func startListening() {
        Task { [weak self] in
            guard let self else { return }
            for await info in self.client.customerInfoStream() {
                let active = info.entitlements[self.config.entitlementID]?.isActive == true
                let current = self.authService.currentUser?.tier ?? "free"
                if (active && current != "paid") || (!active && current == "paid") {
                    try? await self.authService.fetchAccount()
                }
            }
        }
    }

    public func loadProducts() async {
        do {
            if let offering = try await client.currentOffering(),
               let pkg = offering.availablePackages.first {
                displayPrice = pkg.localizedPriceString
            }
        } catch { displayPrice = nil }
    }

    public func purchase() async {
        guard authService.isLoggedIn else {
            purchaseState = .failed("Please sign in first")
            return
        }
        do {
            guard let offering = try await client.currentOffering(),
                  let pkg = offering.availablePackages.first else { return }
            purchaseState = .purchasing
            let result = try await client.purchase(pkg)
            if result.userCancelled { purchaseState = .idle; return }
            purchaseState = .verifying
            purchaseState = await waitForTierSync() ? .success : .failed("Sync timeout")
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    public func restore() async {
        do {
            purchaseState = .verifying
            let info = try await client.restore()
            let active = info.entitlements[config.entitlementID]?.isActive == true
            if active {
                if authService.isLoggedIn {
                    purchaseState = await waitForTierSync() ? .success : .failed("Sync timeout")
                } else {
                    purchaseState = .failed("Restore successful. Please sign in to activate paid features.")
                }
            } else {
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    private func waitForTierSync() async -> Bool {
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(1))
            try? await authService.fetchAccount()
            if authService.currentUser?.tier == "paid" { return true }
        }
        return false
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter SubscriptionServiceTests
git add Sources/LLMGatewayKit/Subscription Tests/LLMGatewayKitTests/Subscription Tests/LLMGatewayKitTests/Helpers/AuthHelpers.swift
git commit -m "Add SubscriptionService with mockable PurchaseClient"
```

---

## Task 13: Sync protocols and codec

**Files:**
- Create: `Sources/LLMGatewayKit/Sync/SyncEnvelope.swift`
- Create: `Sources/LLMGatewayKit/Sync/SyncPayloadCodec.swift`
- Create: `Sources/LLMGatewayKit/Sync/SyncContracts.swift`
- Create: `Tests/LLMGatewayKitTests/Sync/SyncPayloadCodecTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class SyncPayloadCodecTests: XCTestCase {
    func test_identityCodec_roundtrip() async throws {
        let codec = IdentityPayloadCodec()
        let data = Data("hello".utf8)
        let encoded = try await codec.encode(data, entityType: "X")
        let decoded = try await codec.decode(encoded, entityType: "X")
        XCTAssertEqual(decoded, data)
    }
}
```

- [ ] **Step 2: Implement types**

`SyncEnvelope.swift`:

```swift
import Foundation

public struct SyncEnvelope: Codable, Sendable, Equatable {
    public let entityType: String
    public let entityID: String
    public let modifiedAt: Date
    public let data: Data

    public init(entityType: String, entityID: String, modifiedAt: Date, data: Data) {
        self.entityType = entityType; self.entityID = entityID
        self.modifiedAt = modifiedAt; self.data = data
    }
}

public struct SyncResult: Sendable, Equatable {
    public let pushedCount: Int
    public let pulledCount: Int
    public let prunedCount: Int
    public let success: Bool
    public let error: String?
    public let timestamp: Date

    public init(pushedCount: Int = 0, pulledCount: Int = 0, prunedCount: Int = 0,
                success: Bool, error: String? = nil, timestamp: Date = Date()) {
        self.pushedCount = pushedCount; self.pulledCount = pulledCount
        self.prunedCount = prunedCount; self.success = success
        self.error = error; self.timestamp = timestamp
    }
}
```

`SyncPayloadCodec.swift`:

```swift
import Foundation

public protocol SyncPayloadCodec: Sendable {
    func encode(_ plaintext: Data, entityType: String) async throws -> Data
    func decode(_ wire: Data, entityType: String) async throws -> Data
}

public struct IdentityPayloadCodec: SyncPayloadCodec {
    public init() {}
    public func encode(_ p: Data, entityType: String) async -> Data { p }
    public func decode(_ w: Data, entityType: String) async -> Data { w }
}
```

`SyncContracts.swift`:

```swift
import Foundation

public protocol SyncChangeCollecting: Sendable {
    func collectPending() async throws -> [SyncEnvelope]
    func markSynced(_ envelopes: [SyncEnvelope]) async throws
}

public protocol SyncMerging: Sendable {
    func apply(_ envelope: SyncEnvelope) async throws
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter SyncPayloadCodecTests
git add Sources/LLMGatewayKit/Sync Tests/LLMGatewayKitTests/Sync
git commit -m "Add Sync envelope, codec protocol, collector/merger contracts"
```

---

## Task 14: `SyncAPIClient`

**Files:**
- Create: `Sources/LLMGatewayKit/Sync/SyncAPIClient.swift`
- Create: `Tests/LLMGatewayKitTests/Sync/SyncAPIClientTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class SyncAPIClientTests: XCTestCase {
    @MainActor
    func test_push_postsEntriesAndReportsPruned() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store,
                               appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                               session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        URLProtocolStub.responses = [.success(body: #"{"success":true,"stored_entries":1,"pruned_count":2}"#, status: 200)]
        let client = SyncAPIClient(config: TestConfig.make(), auth: auth,
                                   session: URLSession(configuration: URLProtocolStub.makeConfig()))
        let env = SyncEnvelope(entityType: "T", entityID: "1", modifiedAt: Date(), data: Data("body".utf8))
        let res = try await client.push(entries: [env], codec: IdentityPayloadCodec(),
                                        deviceID: "dev", keyGeneration: 1)
        XCTAssertEqual(res.stored, 1)
        XCTAssertEqual(res.pruned, 2)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public final class SyncAPIClient: Sendable {
    public struct PushResult: Sendable, Equatable {
        public let stored: Int
        public let pruned: Int
    }
    public struct PullResult: Sendable {
        public let envelopes: [SyncEnvelope]
        public let nextCursor: Cursor?
        public struct Cursor: Sendable, Equatable {
            public let since: String
            public let sinceID: String
        }
    }
    public struct StatusResult: Sendable, Equatable {
        public let storageBytes: Int
        public let entryCount: Int
    }

    private let config: LLMGatewayKitConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: LLMGatewayKitConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config; self.auth = auth; self.session = session
    }

    public func push(entries: [SyncEnvelope], codec: SyncPayloadCodec,
                     deviceID: String, keyGeneration: Int) async throws -> PushResult {
        let token = try await auth.validAccessToken()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var wireEntries: [[String: Any]] = []
        for env in entries {
            let wire = try await codec.encode(env.data, entityType: env.entityType)
            wireEntries.append([
                "entity_type": env.entityType, "entity_id": env.entityID,
                "modified_at": iso.string(from: env.modifiedAt),
                "data": wire.base64EncodedString(),
            ])
        }
        let body: [String: Any] = [
            "key_generation": keyGeneration,
            "device_id": deviceID,
            "entries": wireEntries,
        ]
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/sync/push")!)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.serverError("push failed")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return .init(stored: json["stored_entries"] as? Int ?? 0,
                     pruned: json["pruned_count"] as? Int ?? 0)
    }

    public func pull(since: String?, sinceID: String?, deviceID: String,
                     codec: SyncPayloadCodec, limit: Int = 100) async throws -> PullResult {
        let token = try await auth.validAccessToken()
        var comps = URLComponents(url: config.baseURL.appendingPathComponent("sync/pull"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "since", value: since ?? "1970-01-01T00:00:00Z"),
            URLQueryItem(name: "since_id", value: sinceID ?? ""),
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.serverError("pull failed")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rawEntries = json["entries"] as? [[String: Any]] ?? []
        var envelopes: [SyncEnvelope] = []
        for d in rawEntries {
            guard let type = d["entity_type"] as? String,
                  let id = d["entity_id"] as? String,
                  let modifiedISO = d["modified_at"] as? String,
                  let modified = iso.date(from: modifiedISO),
                  let b64 = d["data"] as? String,
                  let wire = Data(base64Encoded: b64) else { continue }
            let plain = try await codec.decode(wire, entityType: type)
            envelopes.append(.init(entityType: type, entityID: id, modifiedAt: modified, data: plain))
        }
        var cursor: PullResult.Cursor?
        if let c = json["next_cursor"] as? [String: Any],
           let s = c["since"] as? String, let sid = c["since_id"] as? String {
            cursor = .init(since: s, sinceID: sid)
        }
        return .init(envelopes: envelopes, nextCursor: cursor)
    }

    public func status() async throws -> StatusResult {
        let token = try await auth.validAccessToken()
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/sync/status")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return .init(storageBytes: json["storage_bytes"] as? Int ?? 0,
                     entryCount: json["entry_count"] as? Int ?? 0)
    }

    public func deleteAll() async throws {
        let token = try await auth.validAccessToken()
        var req = URLRequest(url: URL(string: config.baseURL.absoluteString + "/sync/data")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter SyncAPIClientTests
git add Sources/LLMGatewayKit/Sync/SyncAPIClient.swift Tests/LLMGatewayKitTests/Sync/SyncAPIClientTests.swift
git commit -m "Add SyncAPIClient (push/pull/status/delete) over codec"
```

---

## Task 15: `SyncState` + `SyncEngine` (push/pull/forceFullSync)

**Files:**
- Create: `Sources/LLMGatewayKit/Sync/SyncState.swift`
- Create: `Sources/LLMGatewayKit/Sync/SyncEngine.swift`
- Create: `Tests/LLMGatewayKitTests/Sync/SyncEngineTests.swift`

- [ ] **Step 1: Write failing test (in-memory collector + merger)**

```swift
import XCTest
@testable import LLMGatewayKit

final class SyncEngineTests: XCTestCase {
    @MainActor
    func test_syncNow_pushesPendingAndPullsRemote() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store,
                               appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                               session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        URLProtocolStub.responses = [
            .success(body: #"{"success":true,"stored_entries":1,"pruned_count":0}"#, status: 200),
            .success(body: #"""
            {"entries":[{"entity_type":"X","entity_id":"r1","modified_at":"2026-05-16T00:00:00Z","data":"YWJj"}],"next_cursor":null}
            """#, status: 200),
        ]

        let pending = SyncEnvelope(entityType: "X", entityID: "p1", modifiedAt: Date(), data: Data("body".utf8))
        let collector = ArrayCollector(pending: [pending])
        let merger = ArrayMerger()
        let apiClient = SyncAPIClient(config: TestConfig.make(), auth: auth,
                                      session: URLSession(configuration: URLProtocolStub.makeConfig()))
        let engine = SyncEngine(apiClient: apiClient, codec: IdentityPayloadCodec(),
                                collector: collector, merger: merger,
                                state: SyncState(suite: UserDefaults(suiteName: "test_\(UUID())")!),
                                deviceID: "dev", isEligible: { true })
        let result = try await engine.syncNow()
        XCTAssertEqual(result.pushedCount, 1)
        XCTAssertEqual(result.pulledCount, 1)
        XCTAssertEqual(merger.applied.first?.entityID, "r1")
        XCTAssertTrue(collector.markedSynced)
    }
}

actor ArrayCollector: SyncChangeCollecting {
    var pending: [SyncEnvelope]
    var markedSynced = false
    init(pending: [SyncEnvelope]) { self.pending = pending }
    func collectPending() async throws -> [SyncEnvelope] { pending }
    func markSynced(_ envelopes: [SyncEnvelope]) async throws { markedSynced = true; pending.removeAll() }
}

actor ArrayMerger: SyncMerging {
    var applied: [SyncEnvelope] = []
    func apply(_ envelope: SyncEnvelope) async throws { applied.append(envelope) }
}
```

- [ ] **Step 2: Implement `SyncState` + `SyncEngine`**

`Sources/LLMGatewayKit/Sync/SyncState.swift`:

```swift
import Foundation

public final class SyncState: @unchecked Sendable {
    public static let shared = SyncState(suite: .standard)
    private let defaults: UserDefaults
    private enum Keys {
        static let isEnabled = "LLMGatewayKit.sync.isEnabled"
        static let lastPushCursor = "LLMGatewayKit.sync.lastPushCursor"
        static let lastPullSince = "LLMGatewayKit.sync.lastPullSince"
        static let lastPullSinceID = "LLMGatewayKit.sync.lastPullSinceID"
        static let disabledByUserID = "LLMGatewayKit.sync.disabledByUserID"
    }

    public init(suite: UserDefaults) { self.defaults = suite }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }
    public var lastPullSince: String? {
        get { defaults.string(forKey: Keys.lastPullSince) }
        set { defaults.set(newValue, forKey: Keys.lastPullSince) }
    }
    public var lastPullSinceID: String? {
        get { defaults.string(forKey: Keys.lastPullSinceID) }
        set { defaults.set(newValue, forKey: Keys.lastPullSinceID) }
    }
    public var disabledByUserID: String? {
        get { defaults.string(forKey: Keys.disabledByUserID) }
        set { defaults.set(newValue, forKey: Keys.disabledByUserID) }
    }
    public func reset() {
        [Keys.lastPushCursor, Keys.lastPullSince, Keys.lastPullSinceID].forEach { defaults.removeObject(forKey: $0) }
    }
}
```

`Sources/LLMGatewayKit/Sync/SyncEngine.swift`:

```swift
import Foundation

public actor SyncEngine {
    private let apiClient: SyncAPIClient
    private let codec: SyncPayloadCodec
    private let collector: SyncChangeCollecting
    private let merger: SyncMerging
    private let state: SyncState
    private let deviceID: String
    private let keyGeneration: Int
    private let isEligible: @Sendable () async -> Bool

    private let resultContinuation: AsyncStream<SyncResult>.Continuation
    public nonisolated let resultStream: AsyncStream<SyncResult>

    private var autoSyncTask: Task<Void, Never>?
    private var backoffSeconds: Int = 0

    public init(apiClient: SyncAPIClient, codec: SyncPayloadCodec,
                collector: SyncChangeCollecting, merger: SyncMerging,
                state: SyncState, deviceID: String, keyGeneration: Int = 1,
                isEligible: @escaping @Sendable () async -> Bool) {
        self.apiClient = apiClient; self.codec = codec
        self.collector = collector; self.merger = merger
        self.state = state; self.deviceID = deviceID
        self.keyGeneration = keyGeneration
        self.isEligible = isEligible
        (self.resultStream, self.resultContinuation) = AsyncStream.makeStream()
    }

    public func syncNow() async throws -> SyncResult {
        guard await isEligible() else {
            let r = SyncResult(success: false, error: "Not eligible")
            resultContinuation.yield(r); return r
        }
        var result = SyncResult(success: true)
        do {
            let pending = try await collector.collectPending()
            var pushedCount = 0
            var prunedCount = 0
            if !pending.isEmpty {
                let push = try await apiClient.push(entries: pending, codec: codec,
                                                    deviceID: deviceID, keyGeneration: keyGeneration)
                pushedCount = push.stored
                prunedCount = push.pruned
                try await collector.markSynced(pending)
            }
            let pull = try await apiClient.pull(since: state.lastPullSince, sinceID: state.lastPullSinceID,
                                                deviceID: deviceID, codec: codec)
            for env in pull.envelopes { try await merger.apply(env) }
            if let cursor = pull.nextCursor {
                state.lastPullSince = cursor.since
                state.lastPullSinceID = cursor.sinceID
            } else if let last = pull.envelopes.last {
                let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                state.lastPullSince = iso.string(from: last.modifiedAt)
                state.lastPullSinceID = last.entityID
            }
            backoffSeconds = 0
            result = SyncResult(pushedCount: pushedCount, pulledCount: pull.envelopes.count,
                                prunedCount: prunedCount, success: true)
        } catch {
            backoffSeconds = min(max(backoffSeconds * 5, 1), 300)
            result = SyncResult(success: false, error: error.localizedDescription)
        }
        resultContinuation.yield(result)
        return result
    }

    public func forceFullSync() async throws -> SyncResult {
        state.lastPullSince = nil
        state.lastPullSinceID = nil
        return try await syncNow()
    }

    public func disableAndDeleteCloud() async throws {
        try await apiClient.deleteAll()
        state.isEnabled = false
        state.reset()
        stopAutoSync()
    }

    public func startAutoSync(repoChanges: AsyncStream<Void>) {
        stopAutoSync()
        autoSyncTask = Task { [weak self] in
            for await _ in repoChanges {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(2))
                _ = try? await self.syncNow()
            }
        }
    }

    public func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter SyncEngineTests
git add Sources/LLMGatewayKit/Sync Tests/LLMGatewayKitTests/Sync/SyncEngineTests.swift
git commit -m "Add SyncState and SyncEngine with auto-sync support"
```

---

## Task 16: `SyncStatusObserver`

**Files:**
- Create: `Sources/LLMGatewayKit/Sync/SyncStatusObserver.swift`
- Create: `Tests/LLMGatewayKitTests/Sync/SyncStatusObserverTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import LLMGatewayKit

final class SyncStatusObserverTests: XCTestCase {
    @MainActor
    func test_observerCapturesLastResult() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store,
                               appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                               session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        URLProtocolStub.responses = [
            .success(body: #"{"success":true,"stored_entries":0,"pruned_count":0}"#, status: 200),
            .success(body: #"{"entries":[],"next_cursor":null}"#, status: 200),
        ]
        let collector = ArrayCollector(pending: [])
        let merger = ArrayMerger()
        let engine = SyncEngine(apiClient: SyncAPIClient(config: TestConfig.make(), auth: auth,
                                                          session: URLSession(configuration: URLProtocolStub.makeConfig())),
                                codec: IdentityPayloadCodec(), collector: collector, merger: merger,
                                state: SyncState(suite: UserDefaults(suiteName: "obs_\(UUID())")!),
                                deviceID: "dev", isEligible: { true })
        let observer = SyncStatusObserver(engine: engine)
        _ = try await engine.syncNow()
        try await Task.sleep(for: .milliseconds(50))   // let main-actor consumer drain
        XCTAssertNotNil(observer.lastResult)
        XCTAssertTrue(observer.lastResult?.success ?? false)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class SyncStatusObserver {
    public private(set) var lastResult: SyncResult?

    public init(engine: SyncEngine) {
        let stream = engine.resultStream
        Task { @MainActor [weak self] in
            for await result in stream {
                self?.lastResult = result
            }
        }
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
swift test --filter SyncStatusObserverTests
git add Sources/LLMGatewayKit/Sync/SyncStatusObserver.swift Tests/LLMGatewayKitTests/Sync/SyncStatusObserverTests.swift
git commit -m "Add SyncStatusObserver bridge from SyncEngine actor to MainActor"
```

---

## Task 17: UI — `RainbowAvatarBorder`, `PaywallViewModel`, `PaywallView`, `ProfileView`

**Files:**
- Create: `Sources/LLMGatewayKit/UI/RainbowAvatarBorder.swift`
- Create: `Sources/LLMGatewayKit/UI/PaywallViewModel.swift`
- Create: `Sources/LLMGatewayKit/UI/PaywallView.swift`
- Create: `Sources/LLMGatewayKit/UI/ProfileView.swift`
- Create: `Sources/LLMGatewayKit/Resources/Localizable.xcstrings` (empty stub OK)

Views are visual; cover via snapshot tests in a follow-up. For now, ensure they compile by introducing a single SwiftUI preview test.

- [ ] **Step 1: Implement `RainbowAvatarBorder`**

```swift
import SwiftUI

public extension View {
    @ViewBuilder
    func rainbowAvatarBorder(isActive: Bool, size: CGFloat, lineWidth: CGFloat = 3,
                             glowRadius: CGFloat = 6) -> some View {
        if isActive {
            self.overlay {
                Circle().strokeBorder(
                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                    center: .center),
                    lineWidth: lineWidth
                )
                .shadow(color: .pink.opacity(0.6), radius: glowRadius)
            }
        } else {
            self
        }
    }
}
```

- [ ] **Step 2: Implement `PaywallViewModel`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class PaywallViewModel {
    public let subscriptionService: SubscriptionService
    public init(subscriptionService: SubscriptionService) {
        self.subscriptionService = subscriptionService
    }
    public func onAppear() async {
        await subscriptionService.loadProducts()
    }
}
```

- [ ] **Step 3: Implement `PaywallView`**

```swift
import SwiftUI

public struct PaywallView: View {
    let config: LLMGatewayKitConfig
    @State private var viewModel: PaywallViewModel

    public init(config: LLMGatewayKitConfig, viewModel: PaywallViewModel) {
        self.config = config
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(config.appDisplayName + " Pro")
                        .font(.largeTitle.bold())

                    if !config.companionAppNames.isEmpty {
                        Text("このサブスクリプションは " +
                             ([config.appDisplayName] + config.companionAppNames).joined(separator: " と ") +
                             " の両方で有効です")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(config.paywallFeatures) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.title3)
                                .frame(width: 32)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(feature.title).font(.headline)
                                if let s = feature.subtitle {
                                    Text(s).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let price = viewModel.subscriptionService.displayPrice {
                        Text(price).font(.title2.bold())
                    }

                    Button { Task { await viewModel.subscriptionService.purchase() } } label: {
                        purchaseLabel
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("購入の復元") { Task { await viewModel.subscriptionService.restore() } }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    if case .failed(let msg) = viewModel.subscriptionService.purchaseState {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .task { await viewModel.onAppear() }
        }
    }

    @ViewBuilder
    private var purchaseLabel: some View {
        switch viewModel.subscriptionService.purchaseState {
        case .purchasing: ProgressView()
        case .verifying:  HStack { ProgressView(); Text("検証中…") }
        case .success:    Text("購入完了")
        default:          Text("登録する")
        }
    }
}
```

- [ ] **Step 4: Implement `ProfileView`**

```swift
import SwiftUI
import PhotosUI
import AuthenticationServices

public struct ProfileView: View {
    let config: LLMGatewayKitConfig
    let authService: AuthService
    let subscriptionService: SubscriptionService
    let onRequestUpgrade: () -> Void

    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var isUploadingAvatar = false
    @State private var usageInfo: UsageInfo?
    @State private var showDelete = false
    @State private var authError: String?

    public init(config: LLMGatewayKitConfig, authService: AuthService,
                subscriptionService: SubscriptionService,
                onRequestUpgrade: @escaping () -> Void) {
        self.config = config; self.authService = authService
        self.subscriptionService = subscriptionService; self.onRequestUpgrade = onRequestUpgrade
    }

    public var body: some View {
        Form {
            if authService.isLoggedIn { avatarSection; accountInfoSection; accountActionsSection }
            else { signInSection }
        }
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .alert("アカウント削除", isPresented: $showDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task { do { try await authService.deleteAccount() }
                       catch { authError = error.localizedDescription } }
            }
        } message: {
            Text("アカウントとすべてのデータが完全に削除されます。")
        }
        .task {
            if authService.isLoggedIn {
                if let data = await authService.loadAvatarDataIfNeeded(),
                   let img = uiImage(from: data) { avatarImage = img }
                usageInfo = try? await authService.fetchUsage()
            }
        }
        .onChange(of: avatarItem) { Task { await handleAvatarSelection() } }
    }

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        avatarVisual
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .rainbowAvatarBorder(isActive: authService.currentUser?.tier == "paid", size: 88)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingAvatar)

                    if let name = authService.currentUser?.displayName, !name.isEmpty {
                        Text(name).font(.title3.bold())
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var avatarVisual: some View {
        if let img = avatarImage {
            img.resizable().scaledToFill()
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text(Self.initial(from: authService.currentUser?.displayName))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var accountInfoSection: some View {
        Section("アカウント") {
            if let user = authService.currentUser {
                LabeledContent("プラン") {
                    HStack {
                        Text(user.tier.capitalized).foregroundStyle(user.tier == "paid" ? .green : .secondary)
                        if user.tier != "paid" {
                            Button("アップグレード") { onRequestUpgrade() }
                                .font(.caption).buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule).controlSize(.mini)
                        }
                    }
                }
            }
            if let usage = usageInfo {
                LabeledContent("利用率") {
                    Text(String(format: "%.1f%%", usage.percentage))
                        .foregroundStyle(usage.percentage > 100 ? .red : .primary)
                }
            }
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button("購入の復元") { Task { await subscriptionService.restore() } }.font(.footnote)
            Button("サインアウト", role: .destructive) { Task { await authService.logout() } }
            Button("アカウント削除", role: .destructive) { showDelete = true }
        }
        if let e = authError {
            Section { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }

    private var signInSection: some View {
        Section("アカウント") {
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            if let e = authError { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let token = cred.identityToken else {
                authError = "Failed to get Apple credential"; return
            }
            let name: String? = {
                guard let comps = cred.fullName else { return nil }
                let s = PersonNameComponentsFormatter().string(from: comps); return s.isEmpty ? nil : s
            }()
            Task {
                do { try await authService.authenticate(identityToken: token, fullName: name, appleSub: cred.user); authError = nil }
                catch { authError = error.localizedDescription }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authError = error.localizedDescription
            }
        }
    }

    private func handleAvatarSelection() async {
        defer { avatarItem = nil }
        guard let item = avatarItem,
              let data = try? await item.loadTransferable(type: Data.self),
              let compressed = compress(data, maxSide: 512) else { return }
        if let img = uiImage(from: compressed) { avatarImage = img }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do { _ = try await authService.uploadAvatar(imageData: compressed) }
        catch { authError = error.localizedDescription }
    }

    private func compress(_ data: Data, maxSide: CGFloat) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let s = max(image.size.width, image.size.height)
        let scale = s > maxSide ? maxSide / s : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
        #else
        return data
        #endif
    }

    private func uiImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        return nil
    }

    public static func initial(from name: String?) -> String {
        guard let name, let first = name.first else { return "?" }
        return String(first).uppercased()
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build
swift test
```

- [ ] **Step 6: Commit**

```bash
git add Sources/LLMGatewayKit/UI
git commit -m "Add RainbowAvatarBorder, PaywallView, ProfileView, PaywallViewModel"
```

---

## Task 18: Tag `0.1.0` and push

- [ ] **Step 1: Confirm full test suite passes**

```bash
cd ~/workspace/LLMGatewayKit
swift test
```
Expected: All tests pass.

- [ ] **Step 2: Tag and push**

```bash
git tag -a 0.1.0 -m "Initial public release"
git push origin main
git push origin 0.1.0
```

- [ ] **Step 3: Verify**

```bash
gh release create 0.1.0 --title "0.1.0" --notes "Initial public release. See README for usage."
```

---

# Part II — SnapKei Adoption (P2)

> All P2 work happens in `~/workspace/SnapKei`. Each task ends with `git commit` in that repo.

---

## Task 19: Add LLMGatewayKit dependency to SnapKei Xcode project

**Files:**
- Modify: `SnapKei.xcodeproj/project.pbxproj` (Xcode edit — use UI)

- [ ] **Step 1: Open SnapKei in Xcode**

```bash
open /Users/lee/workspace/SnapKei/SnapKei.xcodeproj
```

- [ ] **Step 2: Add the package dependency**

In Xcode: File → Add Package Dependencies → enter `https://github.com/snana7mi/LLMGatewayKit` → Dependency Rule: Up to Next Minor Version starting from `0.1.0` → Add Package → check the `LLMGatewayKit` library and assign to target `SnapKei`.

- [ ] **Step 3: Confirm build**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/lee/workspace/SnapKei
git add SnapKei.xcodeproj/project.pbxproj SnapKei.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
git commit -m "Add LLMGatewayKit 0.1.0 dependency"
```

---

## Task 20: Add `updatedAt` and `deletedAt` to `FixedAsset`

`JournalEntry` already has `updatedAt`. It uses `isVoided` as its soft-delete; for tombstone semantics, the sync encoder will translate `isVoided` to `deletedAt` in the wire JSON. Only `FixedAsset` needs new fields.

**Files:**
- Modify: `SnapKei/Domain/Entities/FixedAsset.swift`
- Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift` (set `updatedAt` on mutate)

- [ ] **Step 1: Write failing test**

`SnapKeiTests/FixedAssetTests.swift` (create file):

```swift
import XCTest
@testable import SnapKei

final class FixedAssetTests: XCTestCase {
    func test_initSetsUpdatedAt() {
        let now = Date()
        let asset = FixedAsset(assetName: "Mac", assetCategoryCode: "A",
                               acquisitionDate: now, serviceStartDate: now,
                               acquisitionAmount: 200_000, usefulLifeYears: 4,
                               treatment: .smallAmountDepreciableAsset)
        XCTAssertNil(asset.deletedAt)
        XCTAssertNotNil(asset.updatedAt)
    }
}
```

- [ ] **Step 2: Add fields**

In `FixedAsset.swift`, after `public var syncId: UUID`:

```swift
    public var updatedAt: Date
    public var deletedAt: Date?
```

In the initializer, set defaults:

```swift
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        // …
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
```

- [ ] **Step 3: Verify SwiftData lightweight migration**

SwiftData auto-migrates optional + defaulted properties. Re-run the existing tests:

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```
Expected: all tests pass (including the new one).

- [ ] **Step 4: Commit**

```bash
git add SnapKei/Domain/Entities/FixedAsset.swift SnapKeiTests/FixedAssetTests.swift
git commit -m "FixedAsset: add updatedAt and deletedAt for sync"
```

---

## Task 21: Add change stream to `ExpenseRepository`

**Files:**
- Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift`

- [ ] **Step 1: Write failing test**

`SnapKeiTests/ExpenseRepositoryChangeStreamTests.swift`:

```swift
import XCTest
@testable import SnapKei
import SwiftData

final class ExpenseRepositoryChangeStreamTests: XCTestCase {
    func test_streamEmitsOnCreate() async throws {
        let container = try ModelContainer(for: JournalEntry.self, FixedAsset.self, Account.self, AssetUsefulLife.self, SystemActivityLog.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repo = SwiftDataExpenseRepository(context: ModelContext(container), deviceId: "test")

        let exp = expectation(description: "change")
        let task = Task {
            for await _ in repo.changes {
                exp.fulfill(); return
            }
        }

        let entry = JournalEntry(entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
                                  debitAccountCode: "5110", creditAccountCode: "1000",
                                  amountIncludingTax: 100, amountExcludingTax: 91, consumptionTax: 9,
                                  taxCategory: .standard10, priceEntryMode: .taxIncluded,
                                  paymentMethod: .ownerLoan, counterpartyName: "X",
                                  transactionDescription: "desc")
        try repo.create(entry, reason: nil)
        await fulfillment(of: [exp], timeout: 1)
        task.cancel()
    }
}
```

- [ ] **Step 2: Add stream to protocol + implementation**

In `ExpenseRepository.swift`, modify the protocol:

```swift
public protocol ExpenseRepository: Sendable {
    func create(_ entry: JournalEntry, reason: String?) throws
    func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws
    func void(_ entry: JournalEntry, reason: String?) throws
    func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry]
    func nextEntryNumber(for fiscalYear: Int) throws -> Int
    var changes: AsyncStream<Void> { get }
}
```

In `SwiftDataExpenseRepository`, add at the top of the class:

```swift
    public nonisolated let changes: AsyncStream<Void>
    private let changesContinuation: AsyncStream<Void>.Continuation

    public init(context: ModelContext, deviceId: String) {
        self.context = context
        self.deviceId = deviceId
        (self.changes, self.changesContinuation) = AsyncStream.makeStream()
    }
```

After every `try context.save()` call, add:

```swift
        changesContinuation.yield()
```

Add a helper for `FixedAsset` mutations (needed by Task 25):

```swift
    public func upsertFromSync(_ asset: FixedAsset) throws {
        // implementation in Task 25
        fatalError("unimplemented")
    }
    public func upsertFromSync(_ entry: JournalEntry) throws {
        fatalError("unimplemented")
    }
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:SnapKeiTests/ExpenseRepositoryChangeStreamTests test
```

- [ ] **Step 4: Commit**

```bash
git add SnapKei/Data/Persistence/ExpenseRepository.swift SnapKeiTests/ExpenseRepositoryChangeStreamTests.swift
git commit -m "ExpenseRepository: expose change stream and upsertFromSync stubs"
```

---

## Task 22: `SyncCursorStore` (SnapKei-side)

**Files:**
- Create: `SnapKei/Data/Sync/SyncCursorStore.swift`
- Create: `SnapKeiTests/SyncCursorStoreTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import SnapKei

final class SyncCursorStoreTests: XCTestCase {
    func test_setAndGet() {
        let suite = UserDefaults(suiteName: "test_\(UUID())")!
        let store = SyncCursorStore(suite: suite, userID: "u1")
        XCTAssertNil(store.lastPushedAt)
        let now = Date()
        store.lastPushedAt = now
        XCTAssertEqual(store.lastPushedAt?.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public final class SyncCursorStore: Sendable {
    private let suite: UserDefaults
    private let key: String

    public init(suite: UserDefaults = .standard, userID: String) {
        self.suite = suite
        self.key = "SnapKei.sync.lastPushedAt.\(userID)"
    }

    public var lastPushedAt: Date? {
        get { suite.object(forKey: key) as? Date }
        set { suite.set(newValue, forKey: key) }
    }

    public func reset() { suite.removeObject(forKey: key) }
}
```

- [ ] **Step 3: Run, commit**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:SnapKeiTests/SyncCursorStoreTests test
git add SnapKei/Data/Sync SnapKeiTests/SyncCursorStoreTests.swift
git commit -m "Add SyncCursorStore for per-user push cursor"
```

---

## Task 23: `SnapKeiSyncCoders` (JSON config)

**Files:**
- Create: `SnapKei/Data/Sync/SnapKeiSyncCoders.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

extension JSONEncoder {
    static var snapkeiSync: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return e
    }
}

extension JSONDecoder {
    static var snapkeiSync: JSONDecoder {
        let d = JSONDecoder()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = f.date(from: s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
            }
            return date
        }
        return d
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapKei/Data/Sync/SnapKeiSyncCoders.swift
git commit -m "Add SnapKeiSyncCoders shared JSON encoder/decoder"
```

---

## Task 24: `SnapKeiChangeCollector`

**Files:**
- Create: `SnapKei/Data/Sync/SnapKeiChangeCollector.swift`
- Create: `SnapKeiTests/SnapKeiChangeCollectorTests.swift`
- Modify: `SnapKei/Domain/Entities/JournalEntry.swift` (add `Codable` payload struct — see Step 2)

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import SwiftData
import LLMGatewayKit
@testable import SnapKei

final class SnapKeiChangeCollectorTests: XCTestCase {
    func test_collectsJournalEntries() async throws {
        let container = try ModelContainer(for: JournalEntry.self, FixedAsset.self, Account.self, AssetUsefulLife.self, SystemActivityLog.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repo = SwiftDataExpenseRepository(context: ModelContext(container), deviceId: "t")
        let entry = JournalEntry(entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
                                  debitAccountCode: "5110", creditAccountCode: "1000",
                                  amountIncludingTax: 100, amountExcludingTax: 91, consumptionTax: 9,
                                  taxCategory: .standard10, priceEntryMode: .taxIncluded,
                                  paymentMethod: .ownerLoan, counterpartyName: "X",
                                  transactionDescription: "desc")
        try repo.create(entry, reason: nil)

        let suite = UserDefaults(suiteName: "t_\(UUID())")!
        let cursor = SyncCursorStore(suite: suite, userID: "u1")
        let collector = SnapKeiChangeCollector(context: ModelContext(container), cursor: cursor)
        let envelopes = try await collector.collectPending()
        XCTAssertFalse(envelopes.isEmpty)
        XCTAssertEqual(envelopes.first?.entityType, "JournalEntry")
    }
}
```

- [ ] **Step 2: Add `JournalEntryPayload` and `FixedAssetPayload` Codable structs**

Create `SnapKei/Data/Sync/SyncPayloads.swift`:

```swift
import Foundation

struct JournalEntryPayload: Codable {
    let syncId: UUID
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
    let receiptImageHash: String?
    let sourceTypeRaw: String
    let createdAt: Date
    let updatedAt: Date
    let isVoided: Bool
    let deletedAt: Date?     // mirrors isVoided ? updatedAt : nil on encode

    init(from e: JournalEntry) {
        syncId = e.syncId; entryNumber = e.entryNumber; fiscalYear = e.fiscalYear
        transactionDate = e.transactionDate; inputDate = e.inputDate; isLateEntry = e.isLateEntry
        debitAccountCode = e.debitAccountCode; creditAccountCode = e.creditAccountCode
        amountIncludingTax = e.amountIncludingTax; amountExcludingTax = e.amountExcludingTax
        consumptionTax = e.consumptionTax; taxCategoryRaw = e.taxCategoryRaw
        priceEntryModeRaw = e.priceEntryModeRaw; paymentMethodRaw = e.paymentMethodRaw
        counterpartyName = e.counterpartyName; invoiceRegistrationNumber = e.invoiceRegistrationNumber
        invoiceQualified = e.invoiceQualified; transitionalMeasureRate = e.transitionalMeasureRate
        transactionDescription = e.transactionDescription; memo = e.memo
        businessAllocationRate = e.businessAllocationRate
        originalAmountIncludingTax = e.originalAmountIncludingTax
        relatedFixedAssetId = e.relatedFixedAssetId
        receiptImageHash = e.receiptImageHash; sourceTypeRaw = e.sourceTypeRaw
        createdAt = e.createdAt; updatedAt = e.updatedAt; isVoided = e.isVoided
        deletedAt = e.isVoided ? e.updatedAt : nil
    }
}

struct FixedAssetPayload: Codable {
    let syncId: UUID
    let assetName: String
    let assetCategoryCode: String
    let acquisitionDate: Date
    let serviceStartDate: Date
    let acquisitionAmount: Int
    let usefulLifeYears: Int
    let depreciationMethodRaw: String
    let treatmentRaw: String
    let businessAllocationRate: Double
    let acquisitionJournalEntryId: UUID?
    let accumulatedDepreciation: Int
    let bookValue: Int
    let disposalDate: Date?
    let disposalAmount: Int?
    let updatedAt: Date
    let deletedAt: Date?

    init(from a: FixedAsset) {
        syncId = a.syncId; assetName = a.assetName; assetCategoryCode = a.assetCategoryCode
        acquisitionDate = a.acquisitionDate; serviceStartDate = a.serviceStartDate
        acquisitionAmount = a.acquisitionAmount; usefulLifeYears = a.usefulLifeYears
        depreciationMethodRaw = a.depreciationMethodRaw; treatmentRaw = a.treatmentRaw
        businessAllocationRate = a.businessAllocationRate
        acquisitionJournalEntryId = a.acquisitionJournalEntryId
        accumulatedDepreciation = a.accumulatedDepreciation
        bookValue = a.bookValue; disposalDate = a.disposalDate; disposalAmount = a.disposalAmount
        updatedAt = a.updatedAt; deletedAt = a.deletedAt
    }
}
```

- [ ] **Step 3: Implement the collector**

`SnapKei/Data/Sync/SnapKeiChangeCollector.swift`:

```swift
import Foundation
import SwiftData
import LLMGatewayKit

public actor SnapKeiChangeCollector: SyncChangeCollecting {
    private let context: ModelContext
    private let cursor: SyncCursorStore

    public init(context: ModelContext, cursor: SyncCursorStore) {
        self.context = context; self.cursor = cursor
    }

    public func collectPending() async throws -> [SyncEnvelope] {
        let since = cursor.lastPushedAt ?? .distantPast
        var envelopes: [SyncEnvelope] = []

        let entriesDescriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> { $0.updatedAt > since }
        )
        let entries = try context.fetch(entriesDescriptor)
        for e in entries {
            let payload = JournalEntryPayload(from: e)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(.init(entityType: "JournalEntry", entityID: e.syncId.uuidString,
                                   modifiedAt: e.updatedAt, data: data))
        }

        let assetsDescriptor = FetchDescriptor<FixedAsset>(
            predicate: #Predicate<FixedAsset> { $0.updatedAt > since }
        )
        let assets = try context.fetch(assetsDescriptor)
        for a in assets {
            let payload = FixedAssetPayload(from: a)
            let data = try JSONEncoder.snapkeiSync.encode(payload)
            envelopes.append(.init(entityType: "FixedAsset", entityID: a.syncId.uuidString,
                                   modifiedAt: a.updatedAt, data: data))
        }

        return envelopes
    }

    public func markSynced(_ envelopes: [SyncEnvelope]) async throws {
        let latest = envelopes.map(\.modifiedAt).max() ?? Date()
        cursor.lastPushedAt = latest
    }
}
```

- [ ] **Step 4: Run tests, commit**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:SnapKeiTests/SnapKeiChangeCollectorTests test
git add SnapKei/Data/Sync SnapKeiTests/SnapKeiChangeCollectorTests.swift
git commit -m "Add SnapKeiChangeCollector and sync payload structs"
```

---

## Task 25: `SnapKeiMerger` + `upsertFromSync` implementations

**Files:**
- Create: `SnapKei/Data/Sync/SnapKeiMerger.swift`
- Modify: `SnapKei/Data/Persistence/ExpenseRepository.swift` (replace `fatalError` stubs)
- Create: `SnapKeiTests/SnapKeiMergerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import SwiftData
import LLMGatewayKit
@testable import SnapKei

final class SnapKeiMergerTests: XCTestCase {
    func test_appliesNewJournalEntry() async throws {
        let container = try ModelContainer(for: JournalEntry.self, FixedAsset.self, Account.self, AssetUsefulLife.self, SystemActivityLog.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let repo = SwiftDataExpenseRepository(context: ctx, deviceId: "test")
        let merger = SnapKeiMerger(context: ctx)

        let payload = JournalEntryPayload(from: JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "1000",
            amountIncludingTax: 100, amountExcludingTax: 91, consumptionTax: 9,
            taxCategory: .standard10, priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan, counterpartyName: "X",
            transactionDescription: "desc"))
        let data = try JSONEncoder.snapkeiSync.encode(payload)
        try await merger.apply(.init(entityType: "JournalEntry", entityID: payload.syncId.uuidString,
                                     modifiedAt: payload.updatedAt, data: data))

        let fetched = try repo.search(criteria: ExpenseSearchCriteria(includeVoided: false))
        XCTAssertEqual(fetched.count, 1)
    }
}
```

- [ ] **Step 2: Implement `SnapKeiMerger`**

```swift
import Foundation
import SwiftData
import LLMGatewayKit

public actor SnapKeiMerger: SyncMerging {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func apply(_ envelope: SyncEnvelope) async throws {
        switch envelope.entityType {
        case "JournalEntry":
            let payload = try JSONDecoder.snapkeiSync.decode(JournalEntryPayload.self, from: envelope.data)
            try applyJournalEntry(payload)
        case "FixedAsset":
            let payload = try JSONDecoder.snapkeiSync.decode(FixedAssetPayload.self, from: envelope.data)
            try applyFixedAsset(payload)
        default:
            return
        }
    }

    private func applyJournalEntry(_ p: JournalEntryPayload) throws {
        let syncId = p.syncId
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.syncId == syncId })
        if let existing = try context.fetch(descriptor).first {
            if existing.updatedAt > p.updatedAt { return } // LWW
            existing.entryNumber = p.entryNumber
            existing.fiscalYear = p.fiscalYear
            existing.transactionDate = p.transactionDate
            existing.inputDate = p.inputDate
            existing.isLateEntry = p.isLateEntry
            existing.debitAccountCode = p.debitAccountCode
            existing.creditAccountCode = p.creditAccountCode
            existing.amountIncludingTax = p.amountIncludingTax
            existing.amountExcludingTax = p.amountExcludingTax
            existing.consumptionTax = p.consumptionTax
            existing.taxCategoryRaw = p.taxCategoryRaw
            existing.priceEntryModeRaw = p.priceEntryModeRaw
            existing.paymentMethodRaw = p.paymentMethodRaw
            existing.counterpartyName = p.counterpartyName
            existing.invoiceRegistrationNumber = p.invoiceRegistrationNumber
            existing.invoiceQualified = p.invoiceQualified
            existing.transitionalMeasureRate = p.transitionalMeasureRate
            existing.transactionDescription = p.transactionDescription
            existing.memo = p.memo
            existing.businessAllocationRate = p.businessAllocationRate
            existing.originalAmountIncludingTax = p.originalAmountIncludingTax
            existing.relatedFixedAssetId = p.relatedFixedAssetId
            existing.receiptImageHash = p.receiptImageHash
            existing.sourceTypeRaw = p.sourceTypeRaw
            existing.updatedAt = p.updatedAt
            existing.isVoided = p.isVoided || p.deletedAt != nil
        } else {
            guard let cat = TaxCategory(rawValue: p.taxCategoryRaw),
                  let mode = PriceEntryMode(rawValue: p.priceEntryModeRaw),
                  let pm = PaymentMethod(rawValue: p.paymentMethodRaw) else { return }
            let entry = JournalEntry(
                entryNumber: p.entryNumber, fiscalYear: p.fiscalYear,
                transactionDate: p.transactionDate, inputDate: p.inputDate,
                isLateEntry: p.isLateEntry, debitAccountCode: p.debitAccountCode,
                creditAccountCode: p.creditAccountCode,
                amountIncludingTax: p.amountIncludingTax,
                amountExcludingTax: p.amountExcludingTax,
                consumptionTax: p.consumptionTax,
                taxCategory: cat, priceEntryMode: mode, paymentMethod: pm,
                counterpartyName: p.counterpartyName,
                invoiceRegistrationNumber: p.invoiceRegistrationNumber,
                invoiceQualified: p.invoiceQualified,
                transitionalMeasureRate: p.transitionalMeasureRate,
                transactionDescription: p.transactionDescription, memo: p.memo,
                businessAllocationRate: p.businessAllocationRate,
                originalAmountIncludingTax: p.originalAmountIncludingTax,
                relatedFixedAssetId: p.relatedFixedAssetId)
            entry.syncId = p.syncId
            entry.updatedAt = p.updatedAt
            entry.isVoided = p.isVoided || p.deletedAt != nil
            context.insert(entry)
        }
        try context.save()
    }

    private func applyFixedAsset(_ p: FixedAssetPayload) throws {
        let syncId = p.syncId
        let descriptor = FetchDescriptor<FixedAsset>(predicate: #Predicate { $0.syncId == syncId })
        if let existing = try context.fetch(descriptor).first {
            if existing.updatedAt > p.updatedAt { return }
            existing.assetName = p.assetName
            existing.assetCategoryCode = p.assetCategoryCode
            existing.acquisitionDate = p.acquisitionDate
            existing.serviceStartDate = p.serviceStartDate
            existing.acquisitionAmount = p.acquisitionAmount
            existing.usefulLifeYears = p.usefulLifeYears
            existing.depreciationMethodRaw = p.depreciationMethodRaw
            existing.treatmentRaw = p.treatmentRaw
            existing.businessAllocationRate = p.businessAllocationRate
            existing.acquisitionJournalEntryId = p.acquisitionJournalEntryId
            existing.accumulatedDepreciation = p.accumulatedDepreciation
            existing.bookValue = p.bookValue
            existing.disposalDate = p.disposalDate
            existing.disposalAmount = p.disposalAmount
            existing.updatedAt = p.updatedAt
            existing.deletedAt = p.deletedAt
        } else if p.deletedAt == nil {
            guard let method = DepreciationMethod(rawValue: p.depreciationMethodRaw),
                  let treatment = AssetTreatment(rawValue: p.treatmentRaw) else { return }
            let asset = FixedAsset(
                assetName: p.assetName, assetCategoryCode: p.assetCategoryCode,
                acquisitionDate: p.acquisitionDate, serviceStartDate: p.serviceStartDate,
                acquisitionAmount: p.acquisitionAmount, usefulLifeYears: p.usefulLifeYears,
                depreciationMethod: method, treatment: treatment,
                businessAllocationRate: p.businessAllocationRate,
                acquisitionJournalEntryId: p.acquisitionJournalEntryId,
                accumulatedDepreciation: p.accumulatedDepreciation,
                bookValue: p.bookValue, disposalDate: p.disposalDate,
                disposalAmount: p.disposalAmount, syncId: p.syncId)
            asset.updatedAt = p.updatedAt
            asset.deletedAt = p.deletedAt
            context.insert(asset)
        }
        try context.save()
    }
}
```

- [ ] **Step 3: Remove the `fatalError` stubs from `ExpenseRepository.swift`**

Delete:

```swift
    public func upsertFromSync(_ asset: FixedAsset) throws { fatalError("unimplemented") }
    public func upsertFromSync(_ entry: JournalEntry) throws { fatalError("unimplemented") }
```

(They are now redundant — the merger writes directly via the `ModelContext`.)

- [ ] **Step 4: Run, commit**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:SnapKeiTests/SnapKeiMergerTests test
git add SnapKei/Data/Sync/SnapKeiMerger.swift SnapKei/Data/Persistence/ExpenseRepository.swift SnapKeiTests/SnapKeiMergerTests.swift
git commit -m "Add SnapKeiMerger with LWW conflict resolution"
```

---

## Task 26: Refactor `AIProxyService` to use `AuthService`

**Files:**
- Modify: `SnapKei/Data/Network/AIProxyService.swift`
- Modify: `SnapKeiTests/AIProxyServiceTests.swift`

- [ ] **Step 1: Read the current 401 retry flow in `AIProxyService.swift:27-55`** and plan the replacement.

- [ ] **Step 2: Rewrite the class**

Replace the contents of `SnapKei/Data/Network/AIProxyService.swift`:

```swift
import Foundation
import LLMGatewayKit

public final class AIProxyService: ReceiptParser, @unchecked Sendable {
    private static let appId = "snapkei"

    private let proxyBaseURLProvider: @Sendable () -> String
    private let authService: AuthService
    private let session: URLSession

    public init(proxyBaseURLProvider: @escaping @Sendable () -> String,
                authService: AuthService,
                session: URLSession = .shared) {
        self.proxyBaseURLProvider = proxyBaseURLProvider
        self.authService = authService
        self.session = session
    }

    public func parseReceipt(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: false)
    }

    private func callGateway(imageData: Data, mimeType: String, isRetry: Bool) async throws -> ReceiptDraft {
        let token: String
        do {
            token = try await authService.validAccessToken()
        } catch AuthError.notLoggedIn {
            try await authService.authenticateInteractively()
            token = try await authService.validAccessToken()
        }
        var request = try makeRequest(path: "/api/\(Self.appId)")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GatewayChatRequest.receipt(imageData: imageData, mimeType: mimeType))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse("missing HTTP response") }
        switch http.statusCode {
        case 200:
            return try decodeChatCompletion(data)
        case 401:
            if isRetry { throw AIServiceError.proxySessionExpired }
            try await authService.refreshAccessToken()
            return try await callGateway(imageData: imageData, mimeType: mimeType, isRetry: true)
        case 429:
            return try throwRateLimited(data: data)
        case 503:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let baseURL = proxyBaseURLProvider().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else { throw AIServiceError.invalidEndpoint }
        return URLRequest(url: url)
    }

    private func decodeChatCompletion(_ data: Data) throws -> ReceiptDraft {
        let response = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AIServiceError.invalidResponse("missing chat completion content")
        }
        let json = try JSONExtractor.extractJSONObject(from: content)
        return try ReceiptDraftDecoder.decode(json)
    }

    private func throwRateLimited(data: Data) throws -> ReceiptDraft {
        let retryAfter = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0["retryAfter"] as? String }
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        throw AIServiceError.rateLimited(retryAfter: retryAfter)
    }
}

private struct GatewayChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: [Content] }
    struct Content: Encodable {
        let type: String
        let text: String?
        let imageURL: ImageURL?
        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    }
    struct ImageURL: Encodable { let url: String }

    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    enum CodingKeys: String, CodingKey { case messages, temperature, maxTokens = "max_tokens" }

    static func receipt(imageData: Data, mimeType: String) -> GatewayChatRequest {
        let prompt = """
        You are parsing Japanese receipt images for bookkeeping. Return only JSON matching this schema:
        {"amountIncludingTax":1100,"amountExcludingTax":1000,"consumptionTax":100,"taxCategory":"standard10","priceEntryMode":"taxIncluded","paymentMethod":"ownerLoan","counterpartyName":"店名","invoiceRegistrationNumber":null,"invoiceQualified":false,"transactionDescription":"説明","suggestedDebitAccountCode":"5110","confidence":0.9,"rawText":"OCR text"}
        """
        return GatewayChatRequest(
            messages: [Message(role: "user", content: [
                Content(type: "text", text: prompt, imageURL: nil),
                Content(type: "image_url", text: nil,
                        imageURL: ImageURL(url: "data:\(mimeType);base64,\(imageData.base64EncodedString())"))
            ])],
            temperature: 0,
            maxTokens: 1024
        )
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
```

- [ ] **Step 3: Update `AIProxyServiceTests.swift`**

Adjust any tests that construct `AIProxyService` with the old `tokenStore:` + `signIn:` parameters. Replace by constructing with an `AuthService` whose internal `tokenStore` is `InMemoryTokenStore` and a stub `URLSession`. (See the kit's `AuthServiceAuthenticateTests` for the pattern.)

- [ ] **Step 4: Delete `SnapKei/Data/Auth/AppleSignInService.swift` and `NonceGenerator.swift`**

These are now provided by the package. Update any remaining imports.

```bash
git rm SnapKei/Data/Auth/AppleSignInService.swift SnapKei/Data/Auth/NonceGenerator.swift SnapKeiTests/NonceGeneratorTests.swift
```

If `AuthTokenStore.swift` is still referenced by anything in SnapKei, audit those call sites and migrate them to `AuthService.validAccessToken()`. Once nothing references it:

```bash
git rm SnapKei/Data/Auth/AuthTokenStore.swift SnapKeiTests/AuthTokenStoreTests.swift
```

- [ ] **Step 5: Run, commit**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
git add -A
git commit -m "AIProxyService: route auth through LLMGatewayKit AuthService"
```

---

## Task 27: Wire services in `SnapKeiApp`

**Files:**
- Modify: `SnapKei/App/SnapKeiApp.swift`
- Modify: `SnapKei/Presentation/RootView.swift`

- [ ] **Step 1: Read the current `SnapKeiApp.swift`** to understand its existing dependency-injection setup.

- [ ] **Step 2: Replace the `App` struct**

```swift
import SwiftUI
import SwiftData
import RevenueCat
import LLMGatewayKit

@main
struct SnapKeiApp: App {
    @State private var authService: AuthService
    @State private var subscriptionService: SubscriptionService
    @State private var syncStatusObserver: SyncStatusObserver
    private let syncEngine: SyncEngine
    private let modelContainer: ModelContainer
    private let config: LLMGatewayKitConfig

    init() {
        let bundle = Bundle.main
        let baseURLString = (bundle.object(forInfoDictionaryKey: "GATEWAY_BASE_URL") as? String)
            ?? "https://api.conch-talk.com"
        let rcKey = bundle.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
        let device = UIDevice.current.name
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: baseURLString)!,
            entitlementID: "pro",
            appDisplayName: "SnapKei",
            companionAppNames: ["ConchTalk"],
            revenueCatAPIKey: rcKey,
            paywallFeatures: [
                .init(id: "ai-quota", icon: "doc.text.magnifyingglass", title: "AI 解析回数の増加", subtitle: nil),
                .init(id: "cloud-sync", icon: "icloud.fill", title: "R1 クラウド自動バックアップ", subtitle: nil),
                .init(id: "reports", icon: "chart.bar.fill", title: "詳細レポート", subtitle: nil),
            ],
            deviceName: device)
        self.config = config

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

        let container = try! ModelContainer.snapKei()
        self.modelContainer = container

        let context = ModelContext(container)
        let cursorSuite = UserDefaults.standard
        let userID = auth.currentUser?.id ?? auth.cachedAppleSub ?? "_anonymous"
        let cursor = SyncCursorStore(suite: cursorSuite, userID: userID)
        let collector = SnapKeiChangeCollector(context: context, cursor: cursor)
        let merger = SnapKeiMerger(context: context)
        let apiClient = SyncAPIClient(config: config, auth: auth)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
        let engine = SyncEngine(
            apiClient: apiClient, codec: IdentityPayloadCodec(),
            collector: collector, merger: merger,
            state: SyncState.shared, deviceID: deviceID,
            isEligible: { [weak auth] in
                guard let auth else { return false }
                return await MainActor.run {
                    auth.isLoggedIn && auth.currentUser?.tier == "paid"
                        && SyncState.shared.isEnabled
                }
            })
        self.syncEngine = engine
        self._syncStatusObserver = State(initialValue: SyncStatusObserver(engine: engine))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .environment(subscriptionService)
                .environment(syncStatusObserver)
                .environment(\.llmGatewayKitConfig, config)
                .environment(\.snapKeiSyncEngine, syncEngine)
                .modelContainer(modelContainer)
        }
    }
}

private struct LLMGatewayKitConfigKey: EnvironmentKey {
    static let defaultValue: LLMGatewayKitConfig? = nil
}
private struct SnapKeiSyncEngineKey: EnvironmentKey {
    static let defaultValue: SyncEngine? = nil
}

extension EnvironmentValues {
    var llmGatewayKitConfig: LLMGatewayKitConfig? {
        get { self[LLMGatewayKitConfigKey.self] }
        set { self[LLMGatewayKitConfigKey.self] = newValue }
    }
    var snapKeiSyncEngine: SyncEngine? {
        get { self[SnapKeiSyncEngineKey.self] }
        set { self[SnapKeiSyncEngineKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Wire repo-change-stream → SyncEngine**

In `RootView.swift`, inside the `body`, after acquiring the repo from the environment, add:

```swift
        .task {
            if let engine = snapKeiSyncEngine, let repo = expenseRepository {
                await engine.startAutoSync(repoChanges: repo.changes)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let engine = snapKeiSyncEngine {
                Task { _ = try? await engine.syncNow() }
            }
        }
```

(Adjust property names to match the existing `RootView` accessors.)

- [ ] **Step 4: Build and run**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```

- [ ] **Step 5: Commit**

```bash
git add SnapKei/App/SnapKeiApp.swift SnapKei/Presentation/RootView.swift
git commit -m "Wire AuthService/SubscriptionService/SyncEngine in SnapKeiApp"
```

---

## Task 28: `AccountHeaderSection`

**Files:**
- Create: `SnapKei/Presentation/Settings/AccountHeaderSection.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import LLMGatewayKit

struct AccountHeaderSection: View {
    let authService: AuthService
    let onTapAvatar: () -> Void

    @State private var avatarImage: Image?

    var body: some View {
        Section {
            HStack {
                Text("設定").font(.largeTitle.bold())
                Spacer()
                Button(action: onTapAvatar) { avatarView }
                    .buttonStyle(.plain)
                    .accessibilityLabel("プロフィール")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .task(id: authService.currentUser?.avatarURL ?? authService.currentUser?.id) {
            if authService.isLoggedIn,
               let data = await authService.loadAvatarDataIfNeeded(),
               let img = ProfileView.image(from: data) {
                avatarImage = img
            } else { avatarImage = nil }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if authService.isLoggedIn {
            Group {
                if let avatarImage { avatarImage.resizable().scaledToFill() }
                else {
                    ZStack {
                        Circle().fill(Color.secondary.opacity(0.16))
                        Text(ProfileView.initial(from: authService.currentUser?.displayName))
                            .font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 45, height: 45)
            .clipShape(Circle())
            .rainbowAvatarBorder(isActive: authService.currentUser?.tier == "paid", size: 45)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
        }
    }
}

extension ProfileView {
    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapKei/Presentation/Settings/AccountHeaderSection.swift
git commit -m "Add AccountHeaderSection with avatar entry point"
```

---

## Task 29: `CloudSyncSection`

**Files:**
- Create: `SnapKei/Presentation/Settings/CloudSyncSection.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import LLMGatewayKit

struct CloudSyncSection: View {
    let authService: AuthService
    let syncEngine: SyncEngine
    let onUpgrade: () -> Void

    @State private var isEnabled = SyncState.shared.isEnabled
    @State private var showDisableConfirm = false
    @State private var suppressOnChange = false

    private var isPaid: Bool { authService.currentUser?.tier == "paid" }

    var body: some View {
        Section {
            Toggle("クラウド同期", isOn: $isEnabled)
                .disabled(!authService.isLoggedIn || !isPaid)
                .onChange(of: isEnabled) { _, newValue in
                    if suppressOnChange { suppressOnChange = false; return }
                    if newValue {
                        SyncState.shared.isEnabled = true
                        Task { _ = try? await syncEngine.syncNow() }
                    } else {
                        showDisableConfirm = true
                    }
                }

            if !authService.isLoggedIn {
                Text("クラウド同期を使用するにはサインインしてください")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !isPaid {
                VStack(alignment: .leading, spacing: 8) {
                    Text("クラウド同期は Pro プランで利用できます")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Pro にアップグレード", action: onUpgrade)
                        .font(.caption)
                }
            }
            if isEnabled && isPaid {
                Button("強制同期") { Task { _ = try? await syncEngine.forceFullSync() } }
            }
        } header: {
            Text("クラウド同期")
        } footer: {
            Text("暗号化された通信で R1 ストレージに保存されます。")
        }
        .alert("クラウド同期を無効化しますか？", isPresented: $showDisableConfirm) {
            Button("無効化して削除", role: .destructive) {
                Task {
                    try? await syncEngine.disableAndDeleteCloud()
                }
            }
            Button("キャンセル", role: .cancel) {
                suppressOnChange = true
                isEnabled = true
            }
        } message: {
            Text("クラウド上のデータは完全に削除されます。本端末のローカルデータは保持されます。")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapKei/Presentation/Settings/CloudSyncSection.swift
git commit -m "Add CloudSyncSection"
```

---

## Task 30: `SyncToastView`

**Files:**
- Create: `SnapKei/Presentation/Settings/SyncToastView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import LLMGatewayKit

struct SyncToastView: View {
    let observer: SyncStatusObserver

    @State private var toastMessage: String?
    @State private var isError: Bool = false

    var body: some View {
        Group {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isError ? .red : .green)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
        .onChange(of: observer.lastResult?.timestamp) { _, _ in
            guard let result = observer.lastResult else { return }
            if result.success {
                if result.prunedCount > 0 {
                    toastMessage = "古いデータが自動削除されました (\(result.prunedCount))"
                    isError = true
                } else if result.pushedCount > 0 || result.pulledCount > 0 {
                    toastMessage = "同期完了"
                    isError = false
                } else { return }
            } else {
                toastMessage = "同期エラー: \(result.error ?? "")"; isError = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                toastMessage = nil
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapKei/Presentation/Settings/SyncToastView.swift
git commit -m "Add SyncToastView surfacing SyncStatusObserver events"
```

---

## Task 31: `SaveButtonSection` + `SettingsViewModel` unsaved-changes tracking

**Files:**
- Modify: `SnapKei/Presentation/Settings/SettingsViewModel.swift`
- Create: `SnapKei/Presentation/Settings/SaveButtonSection.swift`

- [ ] **Step 1: Replace `SettingsViewModel`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var appSettings: AppSettings
    public var aiSettings: AISettings

    private var savedApp: AppSettings
    private var savedAI: AISettings

    public init(appSettings: AppSettings = AppSettings.load(), aiSettings: AISettings = AISettings.load()) {
        self.appSettings = appSettings; self.savedApp = appSettings
        self.aiSettings = aiSettings; self.savedAI = aiSettings
    }

    public var hasUnsavedChanges: Bool {
        appSettings != savedApp || aiSettings != savedAI
    }

    public func saveAll() {
        appSettings.save()
        aiSettings.save()
        savedApp = appSettings
        savedAI = aiSettings
    }

    public func discard() {
        appSettings = savedApp
        aiSettings = savedAI
    }
}
```

If `AppSettings` and `AISettings` are not currently `Equatable`, add the conformance (they should already be value types with simple stored properties).

- [ ] **Step 2: Implement `SaveButtonSection`**

```swift
import SwiftUI

struct SaveButtonSection: View {
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Section {
            Button(action: onSave) {
                HStack {
                    Text("設定を保存")
                        .fontWeight(hasUnsavedChanges ? .semibold : .regular)
                    Spacer()
                    if hasUnsavedChanges {
                        Text("未保存の変更").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .foregroundStyle(hasUnsavedChanges ? .orange : .accentColor)
            if hasUnsavedChanges {
                Button("変更を破棄", role: .destructive, action: onDiscard)
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add SnapKei/Presentation/Settings/SettingsViewModel.swift SnapKei/Presentation/Settings/SaveButtonSection.swift
git commit -m "Settings: unsaved-changes tracking + SaveButtonSection"
```

---

## Task 32: Trim `AISettingsSection`

**Files:**
- Modify: `SnapKei/Presentation/Settings/AISettingsSection.swift`

- [ ] **Step 1: Replace the file**

```swift
import SwiftUI
import LLMGatewayKit

public struct AISettingsSection: View {
    @Binding private var ai: AISettings
    private let onCommit: () -> Void
    private let onTestConnection: () async -> Void
    private let authService: AuthService
    private let onRequestSignIn: () -> Void
    @State private var testResult: String?

    public init(ai: Binding<AISettings>,
                onCommit: @escaping () -> Void,
                onTestConnection: @escaping () async -> Void,
                authService: AuthService,
                onRequestSignIn: @escaping () -> Void) {
        self._ai = ai
        self.onCommit = onCommit
        self.onTestConnection = onTestConnection
        self.authService = authService
        self.onRequestSignIn = onRequestSignIn
    }

    public var body: some View {
        Section("AI 設定") {
            Picker("チャネル", selection: $ai.aiChannel) {
                Text("自前 API Key").tag(AIChannel.directApiKey)
                Text("内蔵 AI").tag(AIChannel.builtInProxy)
            }
            .onChange(of: ai.aiChannel) { _, _ in onCommit() }

            Picker("フォーマット", selection: $ai.preferredFormat) {
                Text("Anthropic").tag(APIFormat.anthropic)
                Text("OpenAI").tag(APIFormat.openAI)
            }
            .onChange(of: ai.preferredFormat) { _, _ in onCommit() }

            if ai.aiChannel == .directApiKey {
                TextField("Anthropic model", text: $ai.anthropicModel).onSubmit(onCommit)
                Text("API Key は今後の BYOK 画面で Keychain 保存します。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Gateway URL", text: $ai.proxyBaseURL).onSubmit(onCommit)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !authService.isLoggedIn {
                    Button("ログインして有効化") { onRequestSignIn() }
                    Text("内蔵 AI を使用するにはサインインが必要です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Button("接続テスト") {
                Task { await onTestConnection(); testResult = "確認しました" }
            }
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapKei/Presentation/Settings/AISettingsSection.swift
git commit -m "AISettingsSection: remove pseudo-SIWA button, gate built-in AI on login"
```

---

## Task 33: Rebuild `SettingsView`

**Files:**
- Modify: `SnapKei/Presentation/Settings/SettingsView.swift`

- [ ] **Step 1: Replace the file**

```swift
import SwiftUI
import LLMGatewayKit

public struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusObserver.self) private var syncObserver
    @Environment(\.llmGatewayKitConfig) private var config
    @Environment(\.snapKeiSyncEngine) private var syncEngine

    @State private var viewModel = SettingsViewModel()
    @State private var statusMessage = ""
    @State private var showProfile = false
    @State private var showPaywall = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                AccountHeaderSection(authService: authService) { showProfile = true }

                if let syncEngine {
                    CloudSyncSection(authService: authService, syncEngine: syncEngine) {
                        showPaywall = true
                    }
                }

                BusinessInfoSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveAll() })

                AISettingsSection(
                    ai: Binding(get: { viewModel.aiSettings }, set: { viewModel.aiSettings = $0 }),
                    onCommit: { viewModel.saveAll() },
                    onTestConnection: { await testConnection() },
                    authService: authService,
                    onRequestSignIn: { showProfile = true })

                FixedAssetSection()
                HouseholdAllocationSection()
                ComplianceSection(
                    settings: Binding(get: { viewModel.appSettings }, set: { viewModel.appSettings = $0 }),
                    onCommit: { viewModel.saveAll() })

                SaveButtonSection(
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    onSave: viewModel.saveAll,
                    onDiscard: viewModel.discard)

                if !statusMessage.isEmpty {
                    Section { Text(statusMessage).font(.caption) }
                }

                Section("アプリ情報") {
                    Text("SnapKei v0.1.0")
                    Text("青色申告対応 仕訳作成アプリ").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showProfile) {
                if let config {
                    ProfileView(config: config, authService: authService,
                                subscriptionService: subscriptionService,
                                onRequestUpgrade: { showPaywall = true })
                }
            }
            .sheet(isPresented: $showPaywall) {
                if let config {
                    PaywallView(config: config,
                                viewModel: PaywallViewModel(subscriptionService: subscriptionService))
                }
            }
            .overlay(alignment: .top) { SyncToastView(observer: syncObserver) }
        }
    }

    private func testConnection() async {
        viewModel.saveAll()
        if viewModel.aiSettings.aiChannel == .builtInProxy {
            statusMessage = viewModel.aiSettings.proxyBaseURL.isEmpty
                ? "Gateway URL を設定してください" : "Gateway URL 設定済み"
        } else {
            statusMessage = "BYOK は Capture 画面で実呼び出し確認します"
        }
    }
}
```

- [ ] **Step 2: Build, run app in simulator manually**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```

Then launch the simulator from Xcode (`Cmd+R`) and verify:
- Settings page opens with the new layout
- Tapping the avatar opens `ProfileView`
- Sign In with Apple button works (sandbox account)
- After sign in, "プラン" / Usage% appear in Profile
- Toggling cloud sync is disabled until user is on `paid` tier
- Tapping "Pro にアップグレード" opens the Paywall

- [ ] **Step 3: Commit**

```bash
git add SnapKei/Presentation/Settings/SettingsView.swift
git commit -m "SettingsView: rebuild in ConchTalk style with Profile/Paywall/CloudSync"
```

---

## Task 34: Add `GATEWAY_BASE_URL` to `Secrets.xcconfig`

**Files:**
- Modify: `Secrets.xcconfig`
- Modify: `SnapKei/Info.plist` (or its xcconfig wiring)

- [ ] **Step 1: Append to `Secrets.xcconfig`**

```
GATEWAY_BASE_URL = https:/$()/api.conch-talk.com
```

(The `$()` escape preserves the double-slash through Xcode's xcconfig parser.)

- [ ] **Step 2: Make sure `Info.plist` has the corresponding key**

`Info.plist` should already pass `REVENUECAT_API_KEY` through (ConchTalk pattern). Add `GATEWAY_BASE_URL` the same way:

```xml
<key>GATEWAY_BASE_URL</key>
<string>$(GATEWAY_BASE_URL)</string>
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO build
```

- [ ] **Step 4: Commit**

```bash
git add Secrets.xcconfig SnapKei/Info.plist 2>/dev/null
git commit -m "Inject GATEWAY_BASE_URL via Secrets.xcconfig"
```

---

## Task 35: Manual smoke-test pass

This is a checklist, not a code task. Run on a real device (TestFlight build) or Simulator with a paid sandbox subscriber.

- [ ] Cold launch → "設定" page renders with header + sync toggle + business sections
- [ ] Tap avatar → ProfileView opens; Sign In With Apple sandbox flow completes
- [ ] Tier shows "Free"; Usage shows 0.0%; Reset countdown visible
- [ ] Tap "アップグレード" → Paywall opens, price displays, "両アプリで有効" text present
- [ ] Sandbox-purchase → after up to 5 seconds tier flips to "Paid"
- [ ] Toggle cloud sync ON → no error toast; in Xcode logs see "stored_entries: 0" on first push
- [ ] Capture a receipt → green "同期完了" toast appears within ~2 seconds of save
- [ ] On second device with same Apple ID: install SnapKei, sign in → previously captured receipt appears in list
- [ ] Toggle cloud sync OFF → confirmation alert → choose "無効化して削除" → toast clear; second device confirms entries no longer pulled
- [ ] In Profile, "Delete Account" → confirm; app returns to logged-out state; gateway logs show DELETE /auth/account succeeded

If any item fails, file a follow-up bug rather than tacking onto this plan.

---

# Self-Review Notes

The reviewer must check before declaring P1+P2 complete:

1. **Spec coverage**: every section of `2026-05-16-llm-gateway-kit-design.md` from §3 through §9 has a corresponding task above. §10 belongs to Plan B (ConchTalk migration) — explicitly out of scope.
2. **No `fatalError` or `TODO` in shipping code**: search `LLMGatewayKit` and `SnapKei` for `fatalError\|TODO\|FIXME` — only test fixtures may use them.
3. **Token rotation rules**: `AuthService.validAccessToken` refreshes within 60s of expiry (Task 8); `refreshAccessToken` is single-flight (Task 8 second test).
4. **Sync eligibility**: SyncEngine no-ops when not paid + logged-in + enabled (Task 27 wires `isEligible`; Task 15 tests cover the happy path).
5. **Avatar lifecycle**: ProfileView calls `loadAvatarDataIfNeeded` on `.task`; `AccountHeaderSection` re-runs on `currentUser.avatarURL` change. Verified manually in Task 33 smoke.

Plan ready for execution.
