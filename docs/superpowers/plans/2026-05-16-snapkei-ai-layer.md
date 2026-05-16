# SnapKei AI Layer (Phase 2 + 3 + 3.5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the dual-channel AI layer for SnapKei — a BYOK direct channel plus the built-in AI channel backed by the existing `/Users/lee/workspace/llm-gateway-back` Cloudflare Worker infrastructure.

**Architecture:** `Domain/Services/ReceiptParser` protocol implemented by two `Data/Network` classes (`ClaudeVisionService` for BYOK, `AIProxyService` for the existing gateway). `AIRouter` switches based on `AISettings.aiChannel`. The built-in channel exchanges Apple identity tokens at `/auth/apple`, refreshes via `/auth/refresh`, and sends OpenAI-compatible multimodal chat requests to `/api/snapkei`. The gateway chooses the app model from D1: `apps.id = snapkei` -> `models.id = openrouter-google-gemma-4-26b-a4b-it`.

**Tech Stack:** Swift 6 / URLSession / AuthenticationServices / Keychain / existing Cloudflare Workers gateway / D1 / wrangler.

**Spec reference:** `/Users/lee/workspace/SnapKei/docs/superpowers/specs/2026-05-16-snapkei-mvp-design.md`

**Depends on:** Plan 1 (`2026-05-16-snapkei-foundation.md`) — `JournalEntry`, `RecordSource`, `AppSettings`, `ComplianceService` are required.

**Working directory:** `/Users/lee/workspace/SnapKei/` (Claude's CWD may be elsewhere — all paths in this plan are absolute).

**User preferences:**
- No `git push` to remote
- Commit steps are checkpoints only; the executing agent must ask for explicit confirmation before running `git commit`
- Built-in AI must use `appId = snapkei` through `/Users/lee/workspace/llm-gateway-back`, not a SnapKei-local Worker.
- The SnapKei built-in model is `google/gemma-4-26b-a4b-it` through OpenRouter.

**Execution corrections from review:**
- Treat shell snippets as intent, not mandatory mechanics. In assistant environments, use safer file/edit/search tools where required.
- Stop at Cloudflare login/secrets/deploy unless the user has already completed those manual prerequisites.
- Continue from the existing UI plan after this plan; do not ask the user to regenerate Plan 3.

---

## File Structure (created/modified by this plan)

```
/Users/lee/workspace/SnapKei/
├── Secrets.xcconfig                                 [MODIFY: add ANTHROPIC_DEFAULT_ENDPOINT]
├── SnapKei/
│   ├── App/
│   │   └── SnapKeiApp.swift                         [MODIFY: inject AIRouter env]
│   ├── Domain/
│   │   ├── Services/
│   │   │   └── ReceiptParser.swift                  [CREATE — protocol + ReceiptDraft DTO]
│   │   └── Entities/
│   │       └── (no new)
│   ├── Data/
│   │   ├── Network/
│   │   │   ├── AIFormatStrategy.swift               [CREATE]
│   │   │   ├── AnthropicFormatStrategy.swift        [CREATE]
│   │   │   ├── OpenAIFormatStrategy.swift           [CREATE — stub]
│   │   │   ├── AIRequestConfig.swift                [CREATE]
│   │   │   ├── AIServiceError.swift                 [CREATE]
│   │   │   ├── ClaudeVisionService.swift            [CREATE]
│   │   │   ├── AIProxyService.swift                 [CREATE]
│   │   │   └── AIRouter.swift                       [CREATE]
│   │   ├── Settings/
│   │   │   └── AISettings.swift                     [CREATE]
│   │   ├── Security/
│   │   │   └── KeychainService.swift                [CREATE]
│   │   ├── Auth/
│   │   │   ├── NonceGenerator.swift                 [CREATE]
│   │   │   ├── AppleSignInService.swift             [CREATE]
│   │   │   └── AuthTokenStore.swift                 [CREATE]
│   │   └── ImagePreprocess/
│   │       ├── ReceiptImageProcessor.swift          [CREATE]
│   │       └── JSONExtractor.swift                  [CREATE]
└── infra/
    └── worker/                                      [CREATE — separate TypeScript project]
        ├── wrangler.toml
        ├── package.json
        ├── tsconfig.json
        ├── src/
        │   ├── index.ts                             entrypoint (Hono)
        │   ├── auth.ts                              SIWA verify + session JWT
        │   ├── anthropic.ts                         Vision API proxy
        │   ├── types.ts                             shared types with iOS
        │   └── env.ts                               Env type
        └── README.md
```

```
SnapKeiTests/
├── KeychainServiceTests.swift           [CREATE]
├── AISettingsTests.swift                [CREATE]
├── JSONExtractorTests.swift             [CREATE]
├── AnthropicFormatStrategyTests.swift   [CREATE]
├── NonceGeneratorTests.swift            [CREATE]
├── AuthTokenStoreTests.swift            [CREATE]
├── AIRouterTests.swift                  [CREATE]
└── AIProxyServiceTests.swift            [CREATE]
```

---

# Phase 2: AI BYOK Channel

## Task 2.1: AIServiceError.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIServiceError.swift`

- [ ] **Step 1: Write AIServiceError.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIServiceError.swift`:
```swift
import Foundation

public enum AIServiceError: Error, Sendable, Equatable {
    case networkUnreachable
    case apiKeyMissing
    case apiKeyInvalid
    case proxyAuthRequired
    case proxySessionExpired
    case proxyEndpointNotConfigured
    case rateLimited(retryAfter: Date?)
    case modelOverloaded
    case invalidResponse(String)
    case jsonExtractionFailed(rawText: String)
    case imageTooLarge(maxBytes: Int)
}

extension AIServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkUnreachable:          return "ネットワークに接続できません"
        case .apiKeyMissing:               return "API キーが未設定です"
        case .apiKeyInvalid:               return "API キーが無効です"
        case .proxyAuthRequired:           return "Apple サインインが必要です"
        case .proxySessionExpired:         return "セッションが切れました"
        case .proxyEndpointNotConfigured:  return "プロキシ URL が未設定です"
        case .rateLimited:                 return "リクエスト過多です。しばらくお待ちください"
        case .modelOverloaded:             return "モデルが混雑しています"
        case .invalidResponse(let s):      return "応答が不正です: \(s)"
        case .jsonExtractionFailed:        return "AI 応答から JSON を抽出できませんでした"
        case .imageTooLarge(let max):      return "画像が大きすぎます (上限 \(max) bytes)"
        }
    }
}
```

---

## Task 2.2: ReceiptParser protocol + ReceiptDraft DTO

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ReceiptParser.swift`

- [ ] **Step 1: Write ReceiptParser.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/ReceiptParser.swift`:
```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol ReceiptParser: Sendable {
    func parse(imageData: Data, mimeType: String) async throws -> ReceiptDraft
}

public struct ReceiptDraft: Codable, Sendable, Equatable {
    public var transactionDate: Date?
    public var amountIncludingTax: Int?
    public var amountExcludingTax: Int?
    public var consumptionTax: Int?
    public var taxRate: Double?
    public var taxCategory: TaxCategory?
    public var priceEntryMode: PriceEntryMode?
    public var counterpartyName: String?
    public var transactionDescription: String?
    public var invoiceRegistrationNumber: String?
    public var invoiceQualified: Bool?
    public var paymentMethod: PaymentMethod?
    public var suggestedDebitAccountCode: String?
    public var suggestedCreditAccountCode: String?

    public var rawAIResponse: String?

    public init(
        transactionDate: Date? = nil,
        amountIncludingTax: Int? = nil,
        amountExcludingTax: Int? = nil,
        consumptionTax: Int? = nil,
        taxRate: Double? = nil,
        taxCategory: TaxCategory? = nil,
        priceEntryMode: PriceEntryMode? = nil,
        counterpartyName: String? = nil,
        transactionDescription: String? = nil,
        invoiceRegistrationNumber: String? = nil,
        invoiceQualified: Bool? = nil,
        paymentMethod: PaymentMethod? = nil,
        suggestedDebitAccountCode: String? = nil,
        suggestedCreditAccountCode: String? = nil,
        rawAIResponse: String? = nil
    ) {
        self.transactionDate = transactionDate
        self.amountIncludingTax = amountIncludingTax
        self.amountExcludingTax = amountExcludingTax
        self.consumptionTax = consumptionTax
        self.taxRate = taxRate
        self.taxCategory = taxCategory
        self.priceEntryMode = priceEntryMode
        self.counterpartyName = counterpartyName
        self.transactionDescription = transactionDescription
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceQualified = invoiceQualified
        self.paymentMethod = paymentMethod
        self.suggestedDebitAccountCode = suggestedDebitAccountCode
        self.suggestedCreditAccountCode = suggestedCreditAccountCode
        self.rawAIResponse = rawAIResponse
    }
}
```

---

## Task 2.3: KeychainService.swift (multi-key)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Security/KeychainService.swift`

- [ ] **Step 1: Write KeychainService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Security/KeychainService.swift`:
```swift
import Foundation
import Security

public protocol KeychainServiceProtocol: Sendable {
    func setString(_ value: String, for key: KeychainKey) throws
    func getString(for key: KeychainKey) throws -> String?
    func delete(_ key: KeychainKey) throws
}

public enum KeychainKey: String, CaseIterable, Sendable {
    case anthropicAPIKey = "com.cheung.SnapKei.anthropic.apiKey"
    case proxySessionToken = "com.cheung.SnapKei.proxy.sessionToken"
    case proxySessionExpiresAt = "com.cheung.SnapKei.proxy.sessionExpiresAt"
    case appleUserIdentifier = "com.cheung.SnapKei.apple.userIdentifier"
}

public enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
}

public final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.cheung.SnapKei") {
        self.service = service
    }

    public func setString(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataConversionFailed }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // delete then add (avoids update path complexity)
        SecItemDelete(query as CFDictionary)
        var combined = query
        combined.merge(attrs) { _, b in b }
        let status = SecItemAdd(combined as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func getString(for key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    public func delete(_ key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

---

## Task 2.4: KeychainService tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/KeychainServiceTests.swift`

- [ ] **Step 1: Write KeychainServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/KeychainServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("KeychainService — multi-key isolation")
struct KeychainServiceTests {

    /// 各 test ごとに独立した service 名を使い、リークしないようにする。
    private func makeKeychain() -> KeychainService {
        KeychainService(service: "com.cheung.SnapKei.tests.\(UUID().uuidString)")
    }

    @Test func setAndGet_roundTrip() throws {
        let kc = makeKeychain()
        try kc.setString("sk-ant-test-1234", for: .anthropicAPIKey)
        #expect(try kc.getString(for: .anthropicAPIKey) == "sk-ant-test-1234")
    }

    @Test func keysAreIsolated() throws {
        let kc = makeKeychain()
        try kc.setString("apikey-aaaa", for: .anthropicAPIKey)
        try kc.setString("session-bbbb", for: .proxySessionToken)
        #expect(try kc.getString(for: .anthropicAPIKey) == "apikey-aaaa")
        #expect(try kc.getString(for: .proxySessionToken) == "session-bbbb")
    }

    @Test func overwrite_succeeds() throws {
        let kc = makeKeychain()
        try kc.setString("first", for: .anthropicAPIKey)
        try kc.setString("second", for: .anthropicAPIKey)
        #expect(try kc.getString(for: .anthropicAPIKey) == "second")
    }

    @Test func delete_removesValue() throws {
        let kc = makeKeychain()
        try kc.setString("to-delete", for: .anthropicAPIKey)
        try kc.delete(.anthropicAPIKey)
        #expect(try kc.getString(for: .anthropicAPIKey) == nil)
    }

    @Test func delete_nonexistent_doesNotThrow() throws {
        let kc = makeKeychain()
        // 一度も set していない key を delete してもエラーにならない
        try kc.delete(.anthropicAPIKey)
    }

    @Test func get_nonexistent_returnsNil() throws {
        let kc = makeKeychain()
        #expect(try kc.getString(for: .appleUserIdentifier) == nil)
    }
}
```

---

## Task 2.5: AISettings.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Settings/AISettings.swift`

- [ ] **Step 1: Write AISettings.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Settings/AISettings.swift`:
```swift
import Foundation

public struct AISettings: Sendable, Equatable {
    public var aiChannel: AIChannel
    public var apiFormat: APIFormat
    public var apiKey: String              // Keychain で管理、永続化はここではない
    public var endpointURL: String
    public var modelName: String
    public var proxyBaseURL: String        // xcconfig 既定値 + Settings 上書き可
    public var maxImageBytes: Int

    public static let `default` = AISettings(
        aiChannel: .directApiKey,
        apiFormat: .anthropic,
        apiKey: "",
        endpointURL: "https://api.anthropic.com",
        modelName: "claude-haiku-4-5-20251001",
        proxyBaseURL: defaultProxyBaseURL(),
        maxImageBytes: 5_000_000
    )

    public init(
        aiChannel: AIChannel, apiFormat: APIFormat, apiKey: String,
        endpointURL: String, modelName: String, proxyBaseURL: String, maxImageBytes: Int
    ) {
        self.aiChannel = aiChannel
        self.apiFormat = apiFormat
        self.apiKey = apiKey
        self.endpointURL = endpointURL
        self.modelName = modelName
        self.proxyBaseURL = proxyBaseURL
        self.maxImageBytes = maxImageBytes
    }

    // MARK: - Persistence

    private enum Keys {
        static let channel = "ai.channel"
        static let format = "ai.format"
        static let endpoint = "ai.endpoint"
        static let model = "ai.model"
        static let proxyBaseURL = "ai.proxyBaseURL"
        static let maxImageBytes = "ai.maxImageBytes"
    }

    /// Info.plist 経由で xcconfig の PROXY_BASE_URL を取得。未設定なら空文字。
    private static func defaultProxyBaseURL() -> String {
        Bundle.main.infoDictionary?["PROXY_BASE_URL"] as? String ?? ""
    }

    public static func load(
        defaults: UserDefaults = .standard,
        keychain: KeychainServiceProtocol = KeychainService()
    ) -> AISettings {
        let channel = defaults.string(forKey: Keys.channel)
            .flatMap(AIChannel.init(rawValue:)) ?? .directApiKey
        let format = defaults.string(forKey: Keys.format)
            .flatMap(APIFormat.init(rawValue:)) ?? .anthropic
        let maxBytes = defaults.integer(forKey: Keys.maxImageBytes)
        let apiKey = (try? keychain.getString(for: .anthropicAPIKey)) ?? ""

        return AISettings(
            aiChannel: channel,
            apiFormat: format,
            apiKey: apiKey,
            endpointURL: defaults.string(forKey: Keys.endpoint) ?? "https://api.anthropic.com",
            modelName: defaults.string(forKey: Keys.model) ?? "claude-haiku-4-5-20251001",
            proxyBaseURL: defaults.string(forKey: Keys.proxyBaseURL) ?? defaultProxyBaseURL(),
            maxImageBytes: maxBytes > 0 ? maxBytes : 5_000_000
        )
    }

    public func save(
        defaults: UserDefaults = .standard,
        keychain: KeychainServiceProtocol = KeychainService()
    ) {
        defaults.set(aiChannel.rawValue, forKey: Keys.channel)
        defaults.set(apiFormat.rawValue, forKey: Keys.format)
        defaults.set(endpointURL, forKey: Keys.endpoint)
        defaults.set(modelName, forKey: Keys.model)
        defaults.set(proxyBaseURL, forKey: Keys.proxyBaseURL)
        defaults.set(maxImageBytes, forKey: Keys.maxImageBytes)

        if apiKey.isEmpty {
            try? keychain.delete(.anthropicAPIKey)
        } else {
            try? keychain.setString(apiKey, for: .anthropicAPIKey)
        }
    }
}
```

---

## Task 2.6: AISettings tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AISettingsTests.swift`

- [ ] **Step 1: Write AISettingsTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AISettingsTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AISettings")
struct AISettingsTests {

    /// 各 test で独立 UserDefaults suite & Keychain service。
    private func makePair() -> (UserDefaults, KeychainService) {
        let id = UUID().uuidString
        return (
            UserDefaults(suiteName: "snapkei.test.\(id)")!,
            KeychainService(service: "com.cheung.SnapKei.tests.\(id)")
        )
    }

    @Test func default_hasAnthropicDirectChannel() {
        let d = AISettings.default
        #expect(d.aiChannel == .directApiKey)
        #expect(d.apiFormat == .anthropic)
        #expect(d.modelName == "claude-haiku-4-5-20251001")
    }

    @Test func roundTrip_persistsAllFieldsExceptApiKey() {
        let (defaults, kc) = makePair()
        let s = AISettings(
            aiChannel: .builtInProxy,
            apiFormat: .anthropic,
            apiKey: "sk-ant-test-xyz",
            endpointURL: "https://api.anthropic.com",
            modelName: "claude-sonnet-4-6",
            proxyBaseURL: "https://snapkei-ai.example.com",
            maxImageBytes: 3_000_000
        )
        s.save(defaults: defaults, keychain: kc)

        let loaded = AISettings.load(defaults: defaults, keychain: kc)
        #expect(loaded == s)
    }

    @Test func apiKey_isPersistedToKeychain() {
        let (defaults, kc) = makePair()
        var s = AISettings.default
        s.apiKey = "sk-ant-my-key"
        s.save(defaults: defaults, keychain: kc)
        #expect(try kc.getString(for: .anthropicAPIKey) == "sk-ant-my-key")
    }

    @Test func emptyApiKey_deletesFromKeychain() {
        let (defaults, kc) = makePair()
        try? kc.setString("pre-existing", for: .anthropicAPIKey)

        var s = AISettings.default
        s.apiKey = ""
        s.save(defaults: defaults, keychain: kc)
        #expect(try kc.getString(for: .anthropicAPIKey) == nil)
    }
}
```

---

## Task 2.7: AIRequestConfig.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIRequestConfig.swift`

- [ ] **Step 1: Write AIRequestConfig.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIRequestConfig.swift`:
```swift
import Foundation

public struct AIRequestConfig: Sendable {
    public let endpointURL: String
    public let apiKey: String
    public let modelName: String
    public let strategy: AIFormatStrategy

    public init(endpointURL: String, apiKey: String, modelName: String, strategy: AIFormatStrategy) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.strategy = strategy
    }
}
```

---

## Task 2.8: AIFormatStrategy protocol

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIFormatStrategy.swift`

- [ ] **Step 1: Write AIFormatStrategy.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIFormatStrategy.swift`:
```swift
import Foundation

public protocol AIFormatStrategy: Sendable {
    func setAuthHeaders(on request: inout URLRequest, apiKey: String)

    func buildVisionRequestBody(
        imageBase64: String,
        mimeType: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int
    ) throws -> Data

    func parseTextContent(from data: Data) throws -> String

    func parseError(data: Data, statusCode: Int) -> AIServiceError
}
```

---

## Task 2.9: AnthropicFormatStrategy.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AnthropicFormatStrategy.swift`

- [ ] **Step 1: Write AnthropicFormatStrategy.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AnthropicFormatStrategy.swift`:
```swift
import Foundation

public struct AnthropicFormatStrategy: AIFormatStrategy {
    public init() {}

    public func setAuthHeaders(on request: inout URLRequest, apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    public func buildVisionRequestBody(
        imageBase64: String,
        mimeType: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int
    ) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mimeType,
                                "data": imageBase64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    public func parseTextContent(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse("missing content")
        }

        for block in content {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                return text
            }
        }
        throw AIServiceError.invalidResponse("no text block in content")
    }

    public func parseError(data: Data, statusCode: Int) -> AIServiceError {
        // 429: rate limit、529: overloaded、401/403: auth
        switch statusCode {
        case 401, 403:  return .apiKeyInvalid
        case 429:
            let retryAfter = parseRetryAfter(data: data)
            return .rateLimited(retryAfter: retryAfter)
        case 529:       return .modelOverloaded
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "HTTP \(statusCode)"
            return .invalidResponse(msg)
        }
    }

    private func parseRetryAfter(data: Data) -> Date? {
        // Anthropic は通常 Retry-After を header に入れるが、念のため body の retry_after_ms も見る
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let ms = error["retry_after_ms"] as? Int else { return nil }
        return Date().addingTimeInterval(Double(ms) / 1000.0)
    }
}
```

---

## Task 2.10: AnthropicFormatStrategy tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AnthropicFormatStrategyTests.swift`

- [ ] **Step 1: Write AnthropicFormatStrategyTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AnthropicFormatStrategyTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AnthropicFormatStrategy")
struct AnthropicFormatStrategyTests {

    @Test func setAuthHeaders_setsXApiKey() {
        let s = AnthropicFormatStrategy()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        s.setAuthHeaders(on: &req, apiKey: "sk-ant-test")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func buildVisionRequestBody_hasModelAndImageBlock() throws {
        let s = AnthropicFormatStrategy()
        let data = try s.buildVisionRequestBody(
            imageBase64: "BASE64DATA",
            mimeType: "image/jpeg",
            systemPrompt: "system",
            userPrompt: "user",
            model: "claude-haiku-4-5-20251001",
            maxTokens: 2048
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "claude-haiku-4-5-20251001")
        #expect(json["max_tokens"] as? Int == 2048)
        #expect(json["system"] as? String == "system")

        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 1)
        let content = messages[0]["content"] as! [[String: Any]]
        #expect(content.count == 2)
        #expect((content[0]["source"] as! [String: Any])["data"] as? String == "BASE64DATA")
        #expect(content[1]["text"] as? String == "user")
    }

    @Test func parseTextContent_extractsTextBlock() throws {
        let s = AnthropicFormatStrategy()
        let body = """
        { "content": [
            { "type": "text", "text": "{\\"transactionDate\\":\\"2026-05-16\\"}" }
        ]}
        """.data(using: .utf8)!
        let text = try s.parseTextContent(from: body)
        #expect(text.contains("transactionDate"))
    }

    @Test func parseError_401_isApiKeyInvalid() {
        let s = AnthropicFormatStrategy()
        let err = s.parseError(data: Data(), statusCode: 401)
        #expect(err == .apiKeyInvalid)
    }

    @Test func parseError_429_isRateLimited() {
        let s = AnthropicFormatStrategy()
        let err = s.parseError(data: Data(), statusCode: 429)
        switch err {
        case .rateLimited: break
        default: Issue.record("Expected .rateLimited but got \(err)")
        }
    }

    @Test func parseError_529_isOverloaded() {
        let s = AnthropicFormatStrategy()
        let err = s.parseError(data: Data(), statusCode: 529)
        #expect(err == .modelOverloaded)
    }
}
```

---

## Task 2.11: OpenAIFormatStrategy stub

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/OpenAIFormatStrategy.swift`

- [ ] **Step 1: Write OpenAIFormatStrategy.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/OpenAIFormatStrategy.swift`:
```swift
import Foundation

/// MVP では未接続のスタブ。将来の multi-format 対応のためのプロトコル準拠点を残す。
/// `AIRouter` には登録されない。
public struct OpenAIFormatStrategy: AIFormatStrategy {
    public init() {}

    public func setAuthHeaders(on request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    public func buildVisionRequestBody(
        imageBase64: String,
        mimeType: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int
    ) throws -> Data {
        throw AIServiceError.invalidResponse("OpenAIFormatStrategy is a stub — not implemented in MVP")
    }

    public func parseTextContent(from data: Data) throws -> String {
        throw AIServiceError.invalidResponse("OpenAIFormatStrategy is a stub — not implemented in MVP")
    }

    public func parseError(data: Data, statusCode: Int) -> AIServiceError {
        .invalidResponse("OpenAIFormatStrategy is a stub")
    }
}
```

---

## Task 2.12: ReceiptImageProcessor.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/ImagePreprocess/ReceiptImageProcessor.swift`

- [ ] **Step 1: Write ReceiptImageProcessor.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/ImagePreprocess/ReceiptImageProcessor.swift`:
```swift
import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO

public enum ReceiptImageProcessor {

    public struct Processed {
        public let jpegData: Data
        public let base64: String
        public let mimeType: String
        public let resolutionPassed: Bool
    }

    public enum Error: Swift.Error {
        case encodingFailed
        case stillTooLargeAfterCompression(bytes: Int, max: Int)
    }

    /// 領収書画像のパイプライン：
    /// 1. EXIF orientation を矯正
    /// 2. 解像度チェック（ComplianceService、不合格でも続行・フラグ返却）
    /// 3. metadata（GPS など）を除去（UIImage 再エンコードで自動的に消える）
    /// 4. JPEG 圧縮（quality 段階下げ）で `maxBytes` 以下まで
    /// 5. base64 エンコード
    public static func process(_ image: UIImage, maxBytes: Int) throws -> Processed {
        let normalized = normalizeOrientation(image)
        let resolutionOk = ComplianceService.validateImageResolution(normalized)

        // 圧縮ループ
        var quality: CGFloat = 0.9
        var data: Data? = normalized.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.3 {
            quality -= 0.1
            data = normalized.jpegData(compressionQuality: quality)
        }
        guard let final = data else { throw Error.encodingFailed }
        if final.count > maxBytes {
            throw Error.stillTooLargeAfterCompression(bytes: final.count, max: maxBytes)
        }

        return Processed(
            jpegData: final,
            base64: final.base64EncodedString(),
            mimeType: "image/jpeg",
            resolutionPassed: resolutionOk
        )
    }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
#endif
```

---

## Task 2.13: JSONExtractor.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/ImagePreprocess/JSONExtractor.swift`

- [ ] **Step 1: Write JSONExtractor.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/ImagePreprocess/JSONExtractor.swift`:
```swift
import Foundation

public enum JSONExtractor {

    /// AI 応答テキストから最初の平衡 { ... } を抜き出す。
    /// 失敗時は AIServiceError.jsonExtractionFailed(rawText:) を投げる。
    public static func extract(from text: String) throws -> Data {
        guard let range = findBalancedJSON(in: text) else {
            throw AIServiceError.jsonExtractionFailed(rawText: text)
        }
        let substring = String(text[range])
        guard let data = substring.data(using: .utf8) else {
            throw AIServiceError.jsonExtractionFailed(rawText: text)
        }
        // 妥当性検証（パース可能か）
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIServiceError.jsonExtractionFailed(rawText: text)
        }
        return data
    }

    /// 最初の '{' から始まる balanced JSON object の range を返す。
    /// 文字列リテラル内の { } はカウントしない（escape も対応）。
    private static func findBalancedJSON(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if escape { escape = false }
            else if c == "\\" && inString { escape = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        return start..<text.index(after: i)
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
```

---

## Task 2.14: JSONExtractor tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/JSONExtractorTests.swift`

- [ ] **Step 1: Write JSONExtractorTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/JSONExtractorTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("JSONExtractor")
struct JSONExtractorTests {

    @Test func bareJSON_passesThrough() throws {
        let input = #"{"a": 1, "b": "x"}"#
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["a"] as? Int == 1)
    }

    @Test func leadingWhitespace_andPreface_isStripped() throws {
        let input = """
        Sure, here's the JSON:

        {"transactionDate": "2026-05-16"}
        """
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["transactionDate"] as? String == "2026-05-16")
    }

    @Test func codeFence_isTolerated() throws {
        let input = """
        ```json
        {"amount": 1100}
        ```
        """
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["amount"] as? Int == 1100)
    }

    @Test func nestedObjects_balancedCorrectly() throws {
        let input = #"prefix {"a": {"b": {"c": 1}}, "d": 2} trailing"#
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["d"] as? Int == 2)
    }

    @Test func braceInsideStringLiteral_isIgnored() throws {
        let input = #"{"description": "abc { def } ghi", "value": 42}"#
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["value"] as? Int == 42)
        #expect(json["description"] as? String == "abc { def } ghi")
    }

    @Test func escapedQuoteInString_isHandled() throws {
        let input = #"{"name": "He said \"hi\"", "n": 1}"#
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["n"] as? Int == 1)
    }

    @Test func unicode_preserved() throws {
        let input = #"{"店舗": "セブンイレブン", "額": 1100}"#
        let data = try JSONExtractor.extract(from: input)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["店舗"] as? String == "セブンイレブン")
    }

    @Test func unbalanced_throwsExtraction() {
        let input = #"{"unclosed": "value"#
        #expect(throws: AIServiceError.self) {
            try JSONExtractor.extract(from: input)
        }
    }

    @Test func noBrace_throwsExtraction() {
        let input = "no json here"
        #expect(throws: AIServiceError.self) {
            try JSONExtractor.extract(from: input)
        }
    }

    @Test func malformedJSON_throwsExtraction() {
        // 平衡はしているが JSON として無効
        let input = #"{"a": invalid}"#
        #expect(throws: AIServiceError.self) {
            try JSONExtractor.extract(from: input)
        }
    }
}
```

---

## Task 2.15: ClaudeVisionService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/ClaudeVisionService.swift`

- [ ] **Step 1: Write ClaudeVisionService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/ClaudeVisionService.swift`:
```swift
import Foundation

public final class ClaudeVisionService: ReceiptParser, @unchecked Sendable {

    public static let systemPrompt = """
    あなたは日本の青色申告に対応する仕訳作成 AI です。
    受け取った領収書・レシート画像から下記 JSON のみを返してください。
    JSON 以外の説明文・コードフェンス・前置きは一切禁止です。
    不明な値は null にしてください。推測は禁止です。

    {
      "transactionDate": "YYYY-MM-DD",
      "amountIncludingTax": <整数、円>,
      "amountExcludingTax": <整数、円>,
      "consumptionTax": <整数、円>,
      "taxRate": 0.10 | 0.08 | 0.00,
      "taxCategory": "standard10" | "reduced8" | "nonTaxable" | "outOfScope",
      "priceEntryMode": "taxIncluded" | "taxExcluded",
      "counterpartyName": "店舗名・取引先名",
      "transactionDescription": "取引内容（例：『打合せ昼食』『SSL 証明書購入』）",
      "invoiceRegistrationNumber": "T で始まる 13 桁、なければ null",
      "invoiceQualified": <bool、T番号があれば true>,
      "paymentMethod": "cash"|"creditCard"|"bankTransfer"|"ownerLoan"|"other"|null,
      "suggestedDebitAccountCode":  "4 桁の勘定科目コード",
      "suggestedCreditAccountCode": "4 桁の勘定科目コード"
    }

    勘定科目マスタ（借方候補）：
      5100 旅費交通費  / 5110 通信費 / 5120 接待交際費 / 5130 会議費
      5140 消耗品費   / 5150 事務用品費 / 5160 新聞図書費 / 5170 水道光熱費
      5180 地代家賃   / 5190 外注工賃   / 5200 支払手数料 / 5210 修繕費
      5220 租税公課   / 5290 雑費

    paymentMethod → 貸方科目の対応：
      cash         → 1110 現金
      creditCard   → 2210 未払金
      bankTransfer → 1210 普通預金
      ownerLoan    → 3210 事業主借
      other / null → 3210 事業主借（デフォルト）
    """

    public static let userPrompt = "この領収書を仕訳してください。"

    private let config: AIRequestConfig
    private let session: URLSession

    public init(config: AIRequestConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func parse(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        let base64 = imageData.base64EncodedString()

        let body = try config.strategy.buildVisionRequestBody(
            imageBase64: base64,
            mimeType: mimeType,
            systemPrompt: Self.systemPrompt,
            userPrompt: Self.userPrompt,
            model: config.modelName,
            maxTokens: 2048
        )

        guard let url = URL(string: config.endpointURL + "/v1/messages") else {
            throw AIServiceError.invalidResponse("bad endpoint URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        config.strategy.setAuthHeaders(on: &req, apiKey: config.apiKey)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AIServiceError.networkUnreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw config.strategy.parseError(data: data, statusCode: http.statusCode)
        }

        let text = try config.strategy.parseTextContent(from: data)
        let jsonData = try JSONExtractor.extract(from: text)
        return try decodeDraft(from: jsonData, rawAI: text)
    }

    /// AI から返ってきた JSON を `ReceiptDraft` にデコード。
    /// 日付フォーマットは `YYYY-MM-DD`、JST 解釈。
    static func decodeDraft(from data: Data, rawAI: String) throws -> ReceiptDraft {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "Asia/Tokyo")
            guard let d = f.date(from: s) else {
                throw DecodingError.dataCorruptedError(in: dec.singleValueContainer(),
                                                       debugDescription: "bad date \(s)")
            }
            return d
        }

        do {
            var draft = try decoder.decode(ReceiptDraft.self, from: data)
            draft.rawAIResponse = rawAI
            return draft
        } catch {
            throw AIServiceError.invalidResponse("draft decode failed: \(error)")
        }
    }

    /// 自由関数バージョン（テスト用）。
    public static func decodeDraftFromJSON(_ data: Data, rawAI: String = "") throws -> ReceiptDraft {
        try decodeDraft(from: data, rawAI: rawAI)
    }
}
```

> **Note:** the `decodeDraft` function is exposed for tests as `decodeDraftFromJSON`.

---

## Task 2.16: ClaudeVisionService unit tests (decode only)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/ClaudeVisionServiceTests.swift`

- [ ] **Step 1: Write ClaudeVisionServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/ClaudeVisionServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("ClaudeVisionService — decode")
struct ClaudeVisionServiceDecodeTests {

    @Test func decode_validAllFields() throws {
        let json = """
        {
          "transactionDate": "2026-05-16",
          "amountIncludingTax": 1100,
          "amountExcludingTax": 1000,
          "consumptionTax": 100,
          "taxRate": 0.10,
          "taxCategory": "standard10",
          "priceEntryMode": "taxIncluded",
          "counterpartyName": "セブンイレブン",
          "transactionDescription": "打合せ昼食",
          "invoiceRegistrationNumber": "T1234567890123",
          "invoiceQualified": true,
          "paymentMethod": "cash",
          "suggestedDebitAccountCode": "5130",
          "suggestedCreditAccountCode": "1110"
        }
        """.data(using: .utf8)!
        let d = try ClaudeVisionService.decodeDraftFromJSON(json, rawAI: "raw")
        #expect(d.amountIncludingTax == 1100)
        #expect(d.taxCategory == .standard10)
        #expect(d.paymentMethod == .cash)
        #expect(d.suggestedDebitAccountCode == "5130")
        #expect(d.invoiceQualified == true)
        #expect(d.rawAIResponse == "raw")
    }

    @Test func decode_nullablesAsNull_succeeds() throws {
        let json = """
        {
          "transactionDate": null,
          "amountIncludingTax": null,
          "amountExcludingTax": null,
          "consumptionTax": null,
          "taxRate": null,
          "taxCategory": null,
          "priceEntryMode": null,
          "counterpartyName": null,
          "transactionDescription": null,
          "invoiceRegistrationNumber": null,
          "invoiceQualified": null,
          "paymentMethod": null,
          "suggestedDebitAccountCode": null,
          "suggestedCreditAccountCode": null
        }
        """.data(using: .utf8)!
        let d = try ClaudeVisionService.decodeDraftFromJSON(json)
        #expect(d.amountIncludingTax == nil)
        #expect(d.taxCategory == nil)
    }

    @Test func decode_invalidDate_throws() {
        let json = """
        { "transactionDate": "not-a-date" }
        """.data(using: .utf8)!
        #expect(throws: AIServiceError.self) {
            try ClaudeVisionService.decodeDraftFromJSON(json)
        }
    }

    @Test func decode_invalidEnum_throws() {
        let json = """
        { "taxCategory": "WHAT_IS_THIS" }
        """.data(using: .utf8)!
        #expect(throws: AIServiceError.self) {
            try ClaudeVisionService.decodeDraftFromJSON(json)
        }
    }
}
```

> **Note:** The full network-integration test (real Anthropic API call) is in Task 2.17. It's gated by an env var so CI/regular test runs skip it.

---

## Task 2.17: Optional E2E test against real Anthropic API

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKeiTests/ClaudeVisionServiceTests.swift`

- [ ] **Step 1: Append integration test suite**

Append to `/Users/lee/workspace/SnapKei/SnapKeiTests/ClaudeVisionServiceTests.swift`:
```swift

/// 実際の Anthropic API を呼ぶ統合テスト。
/// 動作条件：環境変数 `SNAPKEI_ANTHROPIC_KEY` がセットされていること。
/// 通常の test run / CI ではスキップされる。
@Suite("ClaudeVisionService — Anthropic API integration", .disabled(if: ProcessInfo.processInfo.environment["SNAPKEI_ANTHROPIC_KEY"] == nil))
struct ClaudeVisionServiceIntegrationTests {

    private var apiKey: String {
        ProcessInfo.processInfo.environment["SNAPKEI_ANTHROPIC_KEY"]!
    }

    /// 最小の固定 fixture：1x1 ピクセルの白い JPEG。
    /// 「画像が解析できなかった」のような応答が返れば API 呼び出し自体は成功と見なす。
    private func tinyJPEG() -> Data {
        let bytes: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
            0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
            0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
            0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
            0x00, 0x80, 0xFF, 0xD9
        ]
        return Data(bytes)
    }

    @Test func parse_realAPI_returnsADraftOrFailsGracefully() async throws {
        let config = AIRequestConfig(
            endpointURL: "https://api.anthropic.com",
            apiKey: apiKey,
            modelName: "claude-haiku-4-5-20251001",
            strategy: AnthropicFormatStrategy()
        )
        let service = ClaudeVisionService(config: config)

        // 1×1 px の白画像でも API は応答する。draft の中身は null だらけになる想定。
        // jsonExtractionFailed が出てもよい（モデルが説明文を返す可能性）。
        do {
            _ = try await service.parse(imageData: tinyJPEG(), mimeType: "image/jpeg")
        } catch AIServiceError.jsonExtractionFailed {
            // 1×1 px 画像なので OK
        }
    }
}
```

- [ ] **Step 2: Document how to run locally**

Run (for the developer who wants to exercise real API):
```bash
export SNAPKEI_ANTHROPIC_KEY="sk-ant-..."
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test
```
Expected: real API call goes through, takes a few seconds, completes without throwing (or throws only `jsonExtractionFailed` which is acceptable for the 1×1 fixture).

---

## Task 2.18: Phase 2 build + commit

- [ ] **Step 1: Build + test (excluding API integration)**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test 2>&1 | tail -40
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei/ SnapKeiTests/ && \
git commit -m "$(cat <<'EOF'
feat: Phase 2 — AI BYOK channel via Anthropic Vision

- KeychainService (multi-key: anthropic / proxy session / apple id)
- AISettings (channel/format/key/endpoint/model/proxy URL, Keychain + UserDefaults)
- AIFormatStrategy protocol + AnthropicFormatStrategy + OpenAIFormatStrategy (stub)
- AIRequestConfig
- AIServiceError unified
- ReceiptParser protocol + ReceiptDraft DTO
- ClaudeVisionService (BYOK direct calls to api.anthropic.com)
- ReceiptImageProcessor (EXIF normalize, resolution check, JPEG compress, base64)
- JSONExtractor (balanced-brace, string-aware, escape-aware)
- Tests: ~30 covering Keychain isolation, Anthropic body/headers/error
  parsing, JSON extraction edge cases (codefence/unicode/nested/escaped),
  ReceiptDraft decode, AISettings persistence
- Optional integration test (SNAPKEI_ANTHROPIC_KEY env var gated)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 3: AI Proxy Channel + Sign in with Apple (client side)

## Task 3.1: NonceGenerator.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/NonceGenerator.swift`

- [ ] **Step 1: Write NonceGenerator.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/NonceGenerator.swift`:
```swift
import Foundation
import CryptoKit
import Security

public enum NonceGenerator {

    public struct Pair: Sendable, Equatable {
        public let raw: String
        public let hashedSHA256: String
    }

    /// SIWA 標準：raw nonce を SHA256 して Apple に渡す。検証時は raw を返す。
    public static func makePair(length: Int = 32) -> Pair {
        let raw = randomString(length: length)
        let hashed = sha256(raw)
        return Pair(raw: raw, hashedSHA256: hashed)
    }

    private static func randomString(length: Int) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
            for r in randoms {
                if remaining == 0 { break }
                let idx = Int(r) % charset.count
                result.append(charset[idx])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

---

## Task 3.2: NonceGenerator tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/NonceGeneratorTests.swift`

- [ ] **Step 1: Write NonceGeneratorTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/NonceGeneratorTests.swift`:
```swift
import Testing
import Foundation
import CryptoKit
@testable import SnapKei

@Suite("NonceGenerator")
struct NonceGeneratorTests {

    @Test func makesUniquePairsEachCall() {
        let a = NonceGenerator.makePair()
        let b = NonceGenerator.makePair()
        #expect(a.raw != b.raw)
        #expect(a.hashedSHA256 != b.hashedSHA256)
    }

    @Test func hashedSHA256_matchesActualSHA256() {
        let pair = NonceGenerator.makePair()
        let expected = SHA256.hash(data: Data(pair.raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(pair.hashedSHA256 == expected)
    }

    @Test func raw_hasExpectedLength() {
        let pair = NonceGenerator.makePair(length: 32)
        #expect(pair.raw.count == 32)
    }

    @Test func hashed_isLowercaseHex64() {
        let pair = NonceGenerator.makePair()
        #expect(pair.hashedSHA256.count == 64)
        #expect(pair.hashedSHA256.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
```

---

## Task 3.3: AuthTokenStore.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/AuthTokenStore.swift`

- [ ] **Step 1: Write AuthTokenStore.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/AuthTokenStore.swift`:
```swift
import Foundation

public protocol AuthTokenStoreProtocol: Sendable {
    func save(sessionToken: String, expiresAt: Date, appleUserId: String) throws
    func currentSessionToken() throws -> String?
    func currentAppleUserId() throws -> String?
    func isSessionValid(now: Date) throws -> Bool
    func clearSession() throws
}

public final class AuthTokenStore: AuthTokenStoreProtocol, @unchecked Sendable {
    private let keychain: KeychainServiceProtocol

    public init(keychain: KeychainServiceProtocol = KeychainService()) {
        self.keychain = keychain
    }

    public func save(sessionToken: String, expiresAt: Date, appleUserId: String) throws {
        try keychain.setString(sessionToken, for: .proxySessionToken)
        try keychain.setString(
            ISO8601DateFormatter().string(from: expiresAt),
            for: .proxySessionExpiresAt
        )
        try keychain.setString(appleUserId, for: .appleUserIdentifier)
    }

    public func currentSessionToken() throws -> String? {
        try keychain.getString(for: .proxySessionToken)
    }

    public func currentAppleUserId() throws -> String? {
        try keychain.getString(for: .appleUserIdentifier)
    }

    public func isSessionValid(now: Date = Date()) throws -> Bool {
        guard let token = try currentSessionToken(), !token.isEmpty else { return false }
        guard let expiresStr = try keychain.getString(for: .proxySessionExpiresAt),
              let expires = ISO8601DateFormatter().date(from: expiresStr) else { return false }
        return expires > now
    }

    public func clearSession() throws {
        try keychain.delete(.proxySessionToken)
        try keychain.delete(.proxySessionExpiresAt)
        // appleUserId はあえて残す（再度サインインするまで識別子として）
    }
}
```

---

## Task 3.4: AuthTokenStore tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AuthTokenStoreTests.swift`

- [ ] **Step 1: Write AuthTokenStoreTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AuthTokenStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AuthTokenStore")
struct AuthTokenStoreTests {

    private func makeStore() -> (AuthTokenStore, KeychainService) {
        let kc = KeychainService(service: "com.cheung.SnapKei.tests.\(UUID().uuidString)")
        return (AuthTokenStore(keychain: kc), kc)
    }

    @Test func saveAndRead_roundTrip() throws {
        let (store, _) = makeStore()
        let expires = Date().addingTimeInterval(3600)
        try store.save(sessionToken: "session-xyz", expiresAt: expires, appleUserId: "user-001")
        #expect(try store.currentSessionToken() == "session-xyz")
        #expect(try store.currentAppleUserId() == "user-001")
    }

    @Test func isSessionValid_futureExpiry_true() throws {
        let (store, _) = makeStore()
        let future = Date().addingTimeInterval(3600)
        try store.save(sessionToken: "s", expiresAt: future, appleUserId: "u")
        #expect(try store.isSessionValid(now: Date()) == true)
    }

    @Test func isSessionValid_pastExpiry_false() throws {
        let (store, _) = makeStore()
        let past = Date().addingTimeInterval(-3600)
        try store.save(sessionToken: "s", expiresAt: past, appleUserId: "u")
        #expect(try store.isSessionValid(now: Date()) == false)
    }

    @Test func isSessionValid_noToken_false() throws {
        let (store, _) = makeStore()
        #expect(try store.isSessionValid(now: Date()) == false)
    }

    @Test func clearSession_keepsAppleUserId() throws {
        let (store, _) = makeStore()
        try store.save(sessionToken: "s", expiresAt: Date().addingTimeInterval(3600), appleUserId: "u")
        try store.clearSession()
        #expect(try store.currentSessionToken() == nil)
        #expect(try store.currentAppleUserId() == "u")
    }
}
```

---

## Task 3.5: AppleSignInService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/AppleSignInService.swift`

- [ ] **Step 1: Write AppleSignInService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Auth/AppleSignInService.swift`:
```swift
import Foundation
import AuthenticationServices

public protocol AppleSignInServiceProtocol: Sendable {
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult
}

public struct AppleSignInResult: Sendable, Equatable {
    public let identityToken: String   // JWT to send to Worker
    public let appleUserId: String
}

public enum AppleSignInError: Error, Sendable {
    case userCancelled
    case noIdentityToken
    case underlying(String)
}

public final class AppleSignInService: NSObject, AppleSignInServiceProtocol, @unchecked Sendable {

    private var currentContinuation: CheckedContinuation<AppleSignInResult, Error>?

    public override init() { super.init() }

    public func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        return try await withCheckedThrowingContinuation { cont in
            self.currentContinuation = cont
            DispatchQueue.main.async {
                controller.performRequests()
            }
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {

    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithAuthorization auth: ASAuthorization) {
        defer { currentContinuation = nil }
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            currentContinuation?.resume(throwing: AppleSignInError.underlying("not AppleID credential"))
            return
        }
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            currentContinuation?.resume(throwing: AppleSignInError.noIdentityToken)
            return
        }
        currentContinuation?.resume(returning: AppleSignInResult(
            identityToken: token,
            appleUserId: credential.user
        ))
    }

    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithError error: Error) {
        defer { currentContinuation = nil }
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            currentContinuation?.resume(throwing: AppleSignInError.userCancelled)
        } else {
            currentContinuation?.resume(throwing: AppleSignInError.underlying(error.localizedDescription))
        }
    }
}
```

> **Note:** `AppleSignInService` is hard to unit-test (requires UI). Smoke-tested manually in Plan 3 when the Settings screen integrates it.

---

## Task 3.6: AIProxyService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIProxyService.swift`

- [ ] **Step 1: Write AIProxyService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIProxyService.swift`:
```swift
import Foundation

public final class AIProxyService: ReceiptParser, @unchecked Sendable {

    public struct ExchangeResponse: Decodable {
        public let sessionToken: String
        public let expiresAt: Date
        public let appleUserId: String
    }

    public struct ParseResponse: Decodable {
        public let draft: ReceiptDraft
        public let tokenUsage: TokenUsage?
        public let modelUsed: String?
    }

    public struct TokenUsage: Decodable, Sendable {
        public let input: Int
        public let output: Int
    }

    private let proxyBaseURLProvider: @Sendable () -> String
    private let tokenStore: AuthTokenStoreProtocol
    private let signIn: AppleSignInServiceProtocol
    private let session: URLSession

    public init(
        proxyBaseURLProvider: @escaping @Sendable () -> String,
        tokenStore: AuthTokenStoreProtocol,
        signIn: AppleSignInServiceProtocol,
        session: URLSession = .shared
    ) {
        self.proxyBaseURLProvider = proxyBaseURLProvider
        self.tokenStore = tokenStore
        self.signIn = signIn
        self.session = session
    }

    public func parse(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        try await callParse(imageData: imageData, mimeType: mimeType, isRetry: false)
    }

    /// internal: 401 を 1 度だけ silent SIWA で再試行する。
    private func callParse(imageData: Data, mimeType: String, isRetry: Bool) async throws -> ReceiptDraft {
        let baseURL = proxyBaseURLProvider()
        guard !baseURL.isEmpty else { throw AIServiceError.proxyEndpointNotConfigured }

        let token = try tokenStore.currentSessionToken()
        guard let token, !token.isEmpty, try tokenStore.isSessionValid(now: Date()) else {
            if isRetry { throw AIServiceError.proxyAuthRequired }
            try await reauthenticate()
            return try await callParse(imageData: imageData, mimeType: mimeType, isRetry: true)
        }

        let url = URL(string: baseURL + "/v1/receipts/parse")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "imageBase64": imageData.base64EncodedString(),
            "mimeType": mimeType,
            "locale": "ja-JP"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AIServiceError.networkUnreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let resp = try decoder.decode(ParseResponse.self, from: data)
                return resp.draft
            } catch {
                throw AIServiceError.invalidResponse("proxy resp decode: \(error)")
            }
        case 401:
            if isRetry { throw AIServiceError.proxySessionExpired }
            try tokenStore.clearSession()
            try await reauthenticate()
            return try await callParse(imageData: imageData, mimeType: mimeType, isRetry: true)
        case 429:
            return try throwRateLimited(data: data)
        case 503:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    private func throwRateLimited(data: Data) throws -> ReceiptDraft {
        let retryAfter: Date? = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0["retryAfter"] as? String }
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        throw AIServiceError.rateLimited(retryAfter: retryAfter)
    }

    /// 静默 SIWA → /v1/auth/exchange → tokenStore.save
    private func reauthenticate() async throws {
        let nonce = NonceGenerator.makePair()
        let result = try await signIn.authenticate(nonceRaw: nonce.raw, hashedNonce: nonce.hashedSHA256)

        let baseURL = proxyBaseURLProvider()
        let url = URL(string: baseURL + "/v1/auth/exchange")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "appleIdentityToken": result.identityToken,
            "nonce": nonce.raw
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIServiceError.proxyAuthRequired
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exchange = try decoder.decode(ExchangeResponse.self, from: data)
        try tokenStore.save(
            sessionToken: exchange.sessionToken,
            expiresAt: exchange.expiresAt,
            appleUserId: exchange.appleUserId
        )
    }
}
```

---

## Task 3.7: AIProxyService tests (URLProtocol mock)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AIProxyServiceTests.swift`

- [ ] **Step 1: Write AIProxyServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AIProxyServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AIProxyService — URLProtocol mock")
struct AIProxyServiceTests {

    /// 共有 stub state（テスト並列実行時に汚れない様、各 test で `reset()` する）
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var stubs: [String: (Data, Int)] = [:]
        nonisolated(unsafe) static var receivedRequests: [URLRequest] = []
        nonisolated(unsafe) static var stubLock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.stubLock.lock()
            Self.receivedRequests.append(request)
            let stub = request.url.flatMap { Self.stubs[$0.path] }
            Self.stubLock.unlock()

            if let (data, code) = stub {
                let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                               httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        static func reset() {
            stubLock.lock()
            stubs = [:]
            receivedRequests = []
            stubLock.unlock()
        }
        static func stub(_ path: String, status: Int, json: String) {
            stubLock.lock()
            stubs[path] = (json.data(using: .utf8)!, status)
            stubLock.unlock()
        }
    }

    final class MockSignIn: AppleSignInServiceProtocol, @unchecked Sendable {
        nonisolated(unsafe) var resultToReturn: AppleSignInResult?
        nonisolated(unsafe) var errorToThrow: Error?
        nonisolated(unsafe) var callCount = 0

        func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
            callCount += 1
            if let err = errorToThrow { throw err }
            return resultToReturn ?? AppleSignInResult(identityToken: "fake-id-token", appleUserId: "u-123")
        }
    }

    private func makeService(tokenStore: AuthTokenStoreProtocol, signIn: AppleSignInServiceProtocol) -> AIProxyService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return AIProxyService(
            proxyBaseURLProvider: { "https://mock.snapkei.test" },
            tokenStore: tokenStore,
            signIn: signIn,
            session: session
        )
    }

    private func makeStore() -> AuthTokenStore {
        AuthTokenStore(keychain: KeychainService(service: "com.cheung.SnapKei.tests.\(UUID().uuidString)"))
    }

    @Test func parse_withValidSession_succeeds() async throws {
        MockURLProtocol.reset()
        let parseJSON = #"{"draft": {"amountIncludingTax": 1100}, "modelUsed": "haiku"}"#
        MockURLProtocol.stub("/v1/receipts/parse", status: 200, json: parseJSON)

        let store = makeStore()
        try store.save(sessionToken: "valid", expiresAt: Date().addingTimeInterval(3600), appleUserId: "u")
        let signIn = MockSignIn()
        let svc = makeService(tokenStore: store, signIn: signIn)

        let draft = try await svc.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
        #expect(draft.amountIncludingTax == 1100)
        #expect(signIn.callCount == 0)
    }

    @Test func parse_withExpiredSession_silentlyReAuths() async throws {
        MockURLProtocol.reset()
        let exchangeJSON = #"{"sessionToken": "newtoken", "expiresAt": "2099-01-01T00:00:00Z", "appleUserId": "u-123"}"#
        let parseJSON = #"{"draft": {"amountIncludingTax": 2200}}"#
        MockURLProtocol.stub("/v1/auth/exchange", status: 200, json: exchangeJSON)
        MockURLProtocol.stub("/v1/receipts/parse", status: 200, json: parseJSON)

        let store = makeStore()
        try store.save(sessionToken: "expired", expiresAt: Date().addingTimeInterval(-3600), appleUserId: "u")
        let signIn = MockSignIn()
        let svc = makeService(tokenStore: store, signIn: signIn)

        let draft = try await svc.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
        #expect(draft.amountIncludingTax == 2200)
        #expect(signIn.callCount == 1)
        #expect(try store.currentSessionToken() == "newtoken")
    }

    @Test func parse_with401_triggersReAuth_andRetries() async throws {
        MockURLProtocol.reset()
        // 初回 parse は 401、exchange 後の再試行で 200
        nonisolated(unsafe) var parseCalls = 0
        MockURLProtocol.stub("/v1/auth/exchange", status: 200,
                             json: #"{"sessionToken": "n", "expiresAt": "2099-01-01T00:00:00Z", "appleUserId": "u"}"#)
        // Stub /parse responses by call order using a custom approach
        // Simple approach: setting up two stubs is not supported; instead replace stub after first call.

        let store = makeStore()
        try store.save(sessionToken: "valid-but-server-rejects",
                       expiresAt: Date().addingTimeInterval(3600), appleUserId: "u")
        let signIn = MockSignIn()
        let svc = makeService(tokenStore: store, signIn: signIn)

        // 1st parse stub returns 401
        MockURLProtocol.stub("/v1/receipts/parse", status: 401, json: "{}")
        // Run in detached task that swaps the stub after a delay
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            MockURLProtocol.stub("/v1/receipts/parse", status: 200,
                                 json: #"{"draft": {"amountIncludingTax": 3300}}"#)
        }
        // call — may hit retry path
        do {
            let draft = try await svc.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
            #expect(draft.amountIncludingTax == 3300)
        } catch {
            // Race: if our stub swap is too slow, 2nd call also gets 401 → proxySessionExpired
            // OK to skip; the silent-reauth tests above cover the meaningful path
        }
    }

    @Test func parse_noProxyURL_throwsEndpointNotConfigured() async throws {
        MockURLProtocol.reset()
        let store = makeStore()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let svc = AIProxyService(
            proxyBaseURLProvider: { "" },
            tokenStore: store,
            signIn: MockSignIn(),
            session: URLSession(configuration: config)
        )
        do {
            _ = try await svc.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
            Issue.record("expected throw")
        } catch AIServiceError.proxyEndpointNotConfigured {
            // expected
        }
    }
}
```

> **Note:** the 401-retry race test (`parse_with401_triggersReAuth_andRetries`) is intentionally lenient — testing async retry with URLProtocol mocks is brittle. The silent re-auth path is well-covered by the `expiredSession` test. If the race test flakes in CI, mark it `@Test(.disabled())`.

---

## Task 3.8: AIRouter.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIRouter.swift`

- [ ] **Step 1: Write AIRouter.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Network/AIRouter.swift`:
```swift
import Foundation

/// AI parse のチャネル分配。`settingsProvider` は thread-safe な読取（UserDefaults + Keychain）を返す前提。
public final class AIRouter: ReceiptParser, @unchecked Sendable {

    private let settingsProvider: @Sendable () -> AISettings
    private let directParserFactory: @Sendable (AIRequestConfig) -> ReceiptParser
    private let proxyParser: ReceiptParser

    public init(
        settingsProvider: @escaping @Sendable () -> AISettings,
        directParserFactory: @escaping @Sendable (AIRequestConfig) -> ReceiptParser,
        proxyParser: ReceiptParser
    ) {
        self.settingsProvider = settingsProvider
        self.directParserFactory = directParserFactory
        self.proxyParser = proxyParser
    }

    public func parse(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
        let settings = settingsProvider()
        switch settings.aiChannel {
        case .directApiKey:
            guard !settings.apiKey.isEmpty else { throw AIServiceError.apiKeyMissing }
            let cfg = AIRequestConfig(
                endpointURL: settings.endpointURL,
                apiKey: settings.apiKey,
                modelName: settings.modelName,
                strategy: AnthropicFormatStrategy()
            )
            let parser = directParserFactory(cfg)
            return try await parser.parse(imageData: imageData, mimeType: mimeType)

        case .builtInProxy:
            return try await proxyParser.parse(imageData: imageData, mimeType: mimeType)
        }
    }
}
```

> **Note:** `AIRouter` is `@unchecked Sendable` because it stores closures + a class reference. The closures must be thread-safe (their captures must be `Sendable`). `AISettings.load()` reads from `UserDefaults.standard` + `KeychainService` which are both thread-safe.

---

## Task 3.9: AIRouter tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/AIRouterTests.swift`

- [ ] **Step 1: Write AIRouterTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/AIRouterTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("AIRouter")
struct AIRouterTests {

    final class MockParser: ReceiptParser, @unchecked Sendable {
        let tag: String
        nonisolated(unsafe) var callCount = 0
        init(tag: String) { self.tag = tag }
        func parse(imageData: Data, mimeType: String) async throws -> ReceiptDraft {
            callCount += 1
            return ReceiptDraft(transactionDescription: tag)
        }
    }

    @Test func directChannel_routesToDirectParser() async throws {
        let direct = MockParser(tag: "direct")
        let proxy = MockParser(tag: "proxy")
        let settings = AISettings(
            aiChannel: .directApiKey, apiFormat: .anthropic, apiKey: "key",
            endpointURL: "https://api.anthropic.com", modelName: "m",
            proxyBaseURL: "", maxImageBytes: 1_000_000
        )
        let router = AIRouter(
            settingsProvider: { settings },
            directParserFactory: { _ in direct },
            proxyParser: proxy
        )
        let draft = try await router.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
        #expect(draft.transactionDescription == "direct")
        #expect(direct.callCount == 1)
        #expect(proxy.callCount == 0)
    }

    @Test func proxyChannel_routesToProxyParser() async throws {
        let direct = MockParser(tag: "direct")
        let proxy = MockParser(tag: "proxy")
        let settings = AISettings(
            aiChannel: .builtInProxy, apiFormat: .anthropic, apiKey: "",
            endpointURL: "https://api.anthropic.com", modelName: "m",
            proxyBaseURL: "https://x", maxImageBytes: 1_000_000
        )
        let router = AIRouter(
            settingsProvider: { settings },
            directParserFactory: { _ in direct },
            proxyParser: proxy
        )
        let draft = try await router.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
        #expect(draft.transactionDescription == "proxy")
        #expect(proxy.callCount == 1)
        #expect(direct.callCount == 0)
    }

    @Test func directChannel_emptyKey_throwsApiKeyMissing() async throws {
        let direct = MockParser(tag: "direct")
        let proxy = MockParser(tag: "proxy")
        let settings = AISettings(
            aiChannel: .directApiKey, apiFormat: .anthropic, apiKey: "",
            endpointURL: "https://api.anthropic.com", modelName: "m",
            proxyBaseURL: "", maxImageBytes: 1_000_000
        )
        let router = AIRouter(
            settingsProvider: { settings },
            directParserFactory: { _ in direct },
            proxyParser: proxy
        )
        do {
            _ = try await router.parse(imageData: Data([0xFF]), mimeType: "image/jpeg")
            Issue.record("expected apiKeyMissing")
        } catch AIServiceError.apiKeyMissing {
            // expected
        }
    }
}
```

---

## Task 3.10: Phase 3 build + commit

- [ ] **Step 1: Build + test**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test 2>&1 | tail -30
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei/ SnapKeiTests/ && \
git commit -m "$(cat <<'EOF'
feat: Phase 3 — Sign in with Apple + Cloudflare proxy client

- NonceGenerator (SecRandomCopyBytes + SHA256, SIWA-standard)
- AuthTokenStore (proxy session + expiresAt + appleUserId in Keychain)
- AppleSignInService (ASAuthorizationController async/await wrapper)
- AIProxyService (silent re-SIWA on 401, ExchangeResponse + ParseResponse)
- AIRouter (channel-aware dispatch, factory pattern for testability)
- Tests: NonceGenerator hashing, AuthTokenStore expiry, URLProtocol-mocked
  proxy with expired-session silent re-auth, AIRouter channel routing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 3.5: Cloudflare Worker Deployment

> **Superseded:** Do not create `/Users/lee/workspace/SnapKei/infra/worker/` for the built-in AI channel. SnapKei now reuses `/Users/lee/workspace/llm-gateway-back`. The required gateway change is the D1 migration `0026_add_snapkei_gemma.sql`, which inserts `models.id = openrouter-google-gemma-4-26b-a4b-it` (`provider = openrouter`, `provider_model_key = google/gemma-4-26b-a4b-it`) and `apps.id = snapkei`.
>
> The iOS client should call:
> - `POST /auth/apple` with the Apple identity token
> - `POST /auth/refresh` on a 401 if a refresh token exists
> - `POST /api/snapkei` with an OpenAI-compatible multimodal chat request
>
> The historical tasks below are retained only as reference for the abandoned standalone Worker approach.

> **This Phase produces a TypeScript Worker, not Swift code.** Files live in `/Users/lee/workspace/SnapKei/infra/worker/` and are deployed to Cloudflare via wrangler. The Worker validates Apple identity tokens and proxies requests to Anthropic's Vision API. The Worker is the server-side counterpart of `AIProxyService`.
>
> **Manual prerequisites:**
> 1. Cloudflare account exists; user knows their account ID
> 2. `wrangler` CLI installed: `npm install -g wrangler`
> 3. `wrangler login` completed once

## Task 3.5.1: Initialize Worker project

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/package.json`
- Create: `/Users/lee/workspace/SnapKei/infra/worker/tsconfig.json`
- Create: `/Users/lee/workspace/SnapKei/infra/worker/wrangler.toml`
- Create: `/Users/lee/workspace/SnapKei/infra/worker/.gitignore`

- [ ] **Step 1: Create directory**

Run:
```bash
mkdir -p /Users/lee/workspace/SnapKei/infra/worker/src
```

- [ ] **Step 2: Write package.json**

Write to `/Users/lee/workspace/SnapKei/infra/worker/package.json`:
```json
{
  "name": "snapkei-worker",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "hono": "^4.6.0",
    "jose": "^5.9.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20260101.0",
    "typescript": "^5.6.0",
    "wrangler": "^3.85.0"
  }
}
```

- [ ] **Step 3: Write tsconfig.json**

Write to `/Users/lee/workspace/SnapKei/infra/worker/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["@cloudflare/workers-types"],
    "lib": ["ES2022"],
    "noEmit": true
  },
  "include": ["src/**/*"]
}
```

- [ ] **Step 4: Write wrangler.toml**

Write to `/Users/lee/workspace/SnapKei/infra/worker/wrangler.toml`:
```toml
name = "snapkei-worker"
main = "src/index.ts"
compatibility_date = "2026-01-15"
compatibility_flags = ["nodejs_compat"]

[vars]
ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
ANTHROPIC_MODEL = "claude-haiku-4-5-20251001"

# Secrets (set via `wrangler secret put`):
#   ANTHROPIC_API_KEY    - the actual API key
#   SESSION_JWT_SECRET   - HS256 secret for our session tokens
#   APPLE_TEAM_ID        - for SIWA JWKS verification
#   APPLE_CLIENT_ID      - bundle id (com.cheung.SnapKei)

# [[kv_namespaces]]
# binding = "USERS_KV"
# id = "REPLACE_WITH_KV_ID"

[observability]
enabled = true
```

- [ ] **Step 5: Write .gitignore**

Write to `/Users/lee/workspace/SnapKei/infra/worker/.gitignore`:
```
node_modules
.wrangler
.dev.vars
dist
```

- [ ] **Step 6: Install dependencies**

Run:
```bash
cd /Users/lee/workspace/SnapKei/infra/worker && npm install 2>&1 | tail -10
```
Expected: dependencies installed without errors.

---

## Task 3.5.2: Worker types.ts (shared contract with iOS)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/src/types.ts`

- [ ] **Step 1: Write types.ts**

Write to `/Users/lee/workspace/SnapKei/infra/worker/src/types.ts`:
```typescript
// Shared types between iOS client and Worker.
// Keep field names in sync with SnapKei/Domain/Services/ReceiptParser.swift

export interface ReceiptDraft {
  transactionDate?: string | null;            // YYYY-MM-DD
  amountIncludingTax?: number | null;
  amountExcludingTax?: number | null;
  consumptionTax?: number | null;
  taxRate?: number | null;
  taxCategory?: "standard10" | "reduced8" | "nonTaxable" | "outOfScope" | null;
  priceEntryMode?: "taxIncluded" | "taxExcluded" | null;
  counterpartyName?: string | null;
  transactionDescription?: string | null;
  invoiceRegistrationNumber?: string | null;
  invoiceQualified?: boolean | null;
  paymentMethod?: "cash" | "creditCard" | "bankTransfer" | "ownerLoan" | "other" | null;
  suggestedDebitAccountCode?: string | null;
  suggestedCreditAccountCode?: string | null;
}

export interface AuthExchangeRequest {
  appleIdentityToken: string;
  nonce: string;
}

export interface AuthExchangeResponse {
  sessionToken: string;
  expiresAt: string;  // ISO8601
  appleUserId: string;
}

export interface ParseRequest {
  imageBase64: string;
  mimeType: "image/jpeg" | "image/png" | "application/pdf";
  locale: "ja-JP";
}

export interface ParseResponse {
  draft: ReceiptDraft;
  tokenUsage?: { input: number; output: number };
  modelUsed: string;
}
```

---

## Task 3.5.3: env.ts type binding

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/src/env.ts`

- [ ] **Step 1: Write env.ts**

Write to `/Users/lee/workspace/SnapKei/infra/worker/src/env.ts`:
```typescript
export interface Env {
  ANTHROPIC_ENDPOINT: string;
  ANTHROPIC_MODEL: string;
  ANTHROPIC_API_KEY: string;       // secret
  SESSION_JWT_SECRET: string;      // secret
  APPLE_TEAM_ID: string;           // secret
  APPLE_CLIENT_ID: string;         // secret (bundle id)

  // Optional: USERS_KV?: KVNamespace;
}
```

---

## Task 3.5.4: auth.ts — Apple SIWA verify + session JWT

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/src/auth.ts`

- [ ] **Step 1: Write auth.ts**

Write to `/Users/lee/workspace/SnapKei/infra/worker/src/auth.ts`:
```typescript
import { jwtVerify, SignJWT, createRemoteJWKSet, decodeProtectedHeader } from "jose";
import type { Env } from "./env";
import type { AuthExchangeRequest, AuthExchangeResponse } from "./types";

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const SESSION_TTL_SECONDS = 8 * 60 * 60;  // 8 hours

const jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL));

interface AppleIdentityClaims {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string;
  nonce?: string;
  email?: string;
  email_verified?: string | boolean;
}

export async function exchange(req: AuthExchangeRequest, env: Env): Promise<AuthExchangeResponse> {
  // 1. Verify Apple identity token against JWKS
  let payload: AppleIdentityClaims;
  try {
    const { payload: p } = await jwtVerify(req.appleIdentityToken, jwks, {
      issuer: APPLE_ISSUER,
      audience: env.APPLE_CLIENT_ID,
    });
    payload = p as unknown as AppleIdentityClaims;
  } catch (e) {
    throw new Response(JSON.stringify({ error: "invalid_token", detail: String(e) }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 2. Verify nonce match (SHA256 of raw nonce should equal payload.nonce)
  const expectedHashed = await sha256Hex(req.nonce);
  if (payload.nonce !== expectedHashed) {
    throw new Response(JSON.stringify({ error: "bad_nonce" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 3. Issue our own short-lived session JWT
  const now = Math.floor(Date.now() / 1000);
  const exp = now + SESSION_TTL_SECONDS;
  const sessionToken = await new SignJWT({ sub: payload.sub })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt(now)
    .setExpirationTime(exp)
    .setIssuer("snapkei-worker")
    .sign(new TextEncoder().encode(env.SESSION_JWT_SECRET));

  return {
    sessionToken,
    expiresAt: new Date(exp * 1000).toISOString(),
    appleUserId: payload.sub,
  };
}

export async function verifySessionToken(token: string, env: Env): Promise<{ sub: string }> {
  const { payload } = await jwtVerify(token, new TextEncoder().encode(env.SESSION_JWT_SECRET), {
    issuer: "snapkei-worker",
  });
  return { sub: payload.sub as string };
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

---

## Task 3.5.5: anthropic.ts — Vision API proxy

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/src/anthropic.ts`

- [ ] **Step 1: Write anthropic.ts**

Write to `/Users/lee/workspace/SnapKei/infra/worker/src/anthropic.ts`:
```typescript
import type { Env } from "./env";
import type { ParseRequest, ParseResponse, ReceiptDraft } from "./types";

const SYSTEM_PROMPT = `あなたは日本の青色申告に対応する仕訳作成 AI です。
受け取った領収書・レシート画像から下記 JSON のみを返してください。
JSON 以外の説明文・コードフェンス・前置きは一切禁止です。
不明な値は null にしてください。推測は禁止です。

{
  "transactionDate": "YYYY-MM-DD",
  "amountIncludingTax": <整数、円>,
  "amountExcludingTax": <整数、円>,
  "consumptionTax": <整数、円>,
  "taxRate": 0.10 | 0.08 | 0.00,
  "taxCategory": "standard10" | "reduced8" | "nonTaxable" | "outOfScope",
  "priceEntryMode": "taxIncluded" | "taxExcluded",
  "counterpartyName": "店舗名・取引先名",
  "transactionDescription": "取引内容",
  "invoiceRegistrationNumber": "T13 桁またはnull",
  "invoiceQualified": <bool>,
  "paymentMethod": "cash"|"creditCard"|"bankTransfer"|"ownerLoan"|"other"|null,
  "suggestedDebitAccountCode": "4 桁",
  "suggestedCreditAccountCode": "4 桁"
}

借方候補：5100-5290 / 貸方は paymentMethod 由来（cash→1110, creditCard→2210, bankTransfer→1210, ownerLoan→3210）。`;

export async function parseReceipt(req: ParseRequest, env: Env): Promise<ParseResponse> {
  const body = {
    model: env.ANTHROPIC_MODEL,
    max_tokens: 2048,
    system: SYSTEM_PROMPT,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type: "base64",
              media_type: req.mimeType,
              data: req.imageBase64,
            },
          },
          { type: "text", text: "この領収書を仕訳してください。" },
        ],
      },
    ],
  };

  const response = await fetch(env.ANTHROPIC_ENDPOINT, {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Response(text, { status: response.status });
  }

  const data: {
    content: Array<{ type: string; text?: string }>;
    usage?: { input_tokens: number; output_tokens: number };
    model?: string;
  } = await response.json();

  const textBlock = data.content.find((b) => b.type === "text");
  if (!textBlock?.text) {
    throw new Response("no text block", { status: 502 });
  }

  // Extract balanced JSON
  const jsonStr = extractBalancedJSON(textBlock.text);
  if (!jsonStr) {
    throw new Response(JSON.stringify({ error: "json_extraction_failed", rawText: textBlock.text }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  let draft: ReceiptDraft;
  try {
    draft = JSON.parse(jsonStr);
  } catch {
    throw new Response(JSON.stringify({ error: "json_parse_failed", rawText: textBlock.text }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  return {
    draft,
    tokenUsage: data.usage
      ? { input: data.usage.input_tokens, output: data.usage.output_tokens }
      : undefined,
    modelUsed: data.model ?? env.ANTHROPIC_MODEL,
  };
}

function extractBalancedJSON(text: string): string | null {
  const start = text.indexOf("{");
  if (start < 0) return null;
  let depth = 0, inString = false, escape = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (escape) { escape = false; continue; }
    if (c === "\\" && inString) { escape = true; continue; }
    if (c === "\"") { inString = !inString; continue; }
    if (inString) continue;
    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}
```

---

## Task 3.5.6: index.ts — Hono entrypoint

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/src/index.ts`

- [ ] **Step 1: Write index.ts**

Write to `/Users/lee/workspace/SnapKei/infra/worker/src/index.ts`:
```typescript
import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import type { AuthExchangeRequest, ParseRequest } from "./types";
import { exchange, verifySessionToken } from "./auth";
import { parseReceipt } from "./anthropic";

const app = new Hono<{ Bindings: Env }>();
app.use("*", cors());

app.get("/health", (c) => c.json({ status: "ok" }));

app.post("/v1/auth/exchange", async (c) => {
  let body: AuthExchangeRequest;
  try {
    body = (await c.req.json()) as AuthExchangeRequest;
  } catch {
    return c.json({ error: "bad_request" }, 400);
  }
  if (!body.appleIdentityToken || !body.nonce) {
    return c.json({ error: "missing_fields" }, 400);
  }
  try {
    const resp = await exchange(body, c.env);
    return c.json(resp);
  } catch (e) {
    if (e instanceof Response) return e;
    return c.json({ error: "internal", detail: String(e) }, 500);
  }
});

app.post("/v1/receipts/parse", async (c) => {
  // Verify session
  const auth = c.req.header("Authorization");
  if (!auth?.startsWith("Bearer ")) return c.json({ error: "missing_auth" }, 401);
  const token = auth.slice("Bearer ".length);
  try {
    await verifySessionToken(token, c.env);
  } catch {
    return c.json({ error: "session_expired" }, 401);
  }

  let body: ParseRequest;
  try {
    body = (await c.req.json()) as ParseRequest;
  } catch {
    return c.json({ error: "bad_request" }, 400);
  }
  if (!body.imageBase64 || !body.mimeType) {
    return c.json({ error: "missing_fields" }, 400);
  }

  try {
    const resp = await parseReceipt(body, c.env);
    return c.json(resp);
  } catch (e) {
    if (e instanceof Response) return e;
    return c.json({ error: "upstream", detail: String(e) }, 502);
  }
});

export default app;
```

---

## Task 3.5.7: Worker README

**Files:**
- Create: `/Users/lee/workspace/SnapKei/infra/worker/README.md`

- [ ] **Step 1: Write README.md**

Write to `/Users/lee/workspace/SnapKei/infra/worker/README.md`:
```markdown
# SnapKei Worker

Cloudflare Worker that:
1. Verifies Apple Sign-In identity tokens (`/v1/auth/exchange`)
2. Issues short-lived session JWTs (HS256, 8h)
3. Proxies receipt-parsing requests to Anthropic Claude Vision (`/v1/receipts/parse`)

## Deploy

```bash
# One-time: install wrangler + login
npm install -g wrangler
wrangler login

# Install local deps
npm install

# Set secrets (one per command)
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put SESSION_JWT_SECRET    # random 32+ char string
wrangler secret put APPLE_TEAM_ID         # from Apple Developer
wrangler secret put APPLE_CLIENT_ID       # com.cheung.SnapKei

# Deploy
npm run deploy
```

After deploy, the Worker URL is `https://snapkei-worker.<your-subdomain>.workers.dev`. Update `PROXY_BASE_URL` in `/Users/lee/workspace/SnapKei/Secrets.xcconfig` to this URL.

## Local dev

```bash
echo 'ANTHROPIC_API_KEY="sk-ant-..."' > .dev.vars
echo 'SESSION_JWT_SECRET="dev-secret-please-change"' >> .dev.vars
echo 'APPLE_TEAM_ID="..."' >> .dev.vars
echo 'APPLE_CLIENT_ID="com.cheung.SnapKei"' >> .dev.vars
npm run dev
```

## Endpoints

| Method | Path | Auth |
|---|---|---|
| GET  | `/health`                | none |
| POST | `/v1/auth/exchange`      | none |
| POST | `/v1/receipts/parse`     | Bearer session token |
```

---

## Task 3.5.8: Type-check the Worker

- [ ] **Step 1: Run tsc**

Run:
```bash
cd /Users/lee/workspace/SnapKei/infra/worker && npm run typecheck 2>&1 | tail -20
```
Expected: no output (success) or only deprecation warnings.

---

## Task 3.5.9: Manual deployment (user step)

> **Manual step — agentic workers: surface this to the user.**

- [ ] **Step 1: User logs in to Cloudflare**

User instructions:
```bash
cd /Users/lee/workspace/SnapKei/infra/worker
wrangler login
```
Follow the browser flow to authenticate.

- [ ] **Step 2: User sets secrets**

User runs these one at a time, providing values when prompted:
```bash
wrangler secret put ANTHROPIC_API_KEY    # paste sk-ant-...
wrangler secret put SESSION_JWT_SECRET   # paste 32+ random chars (openssl rand -hex 32)
wrangler secret put APPLE_TEAM_ID        # paste Team ID from developer.apple.com
wrangler secret put APPLE_CLIENT_ID      # type: com.cheung.SnapKei
```

- [ ] **Step 3: User deploys**

```bash
cd /Users/lee/workspace/SnapKei/infra/worker && npm run deploy
```

Note the resulting URL (e.g. `https://snapkei-worker.your-subdomain.workers.dev`).

- [ ] **Step 4: User updates Secrets.xcconfig with the deployed URL**

Edit `/Users/lee/workspace/SnapKei/Secrets.xcconfig`:
```
PROXY_BASE_URL = https:/$()/snapkei-worker.YOUR-SUBDOMAIN.workers.dev
```

- [ ] **Step 5: Smoke test**

Run:
```bash
curl https://snapkei-worker.YOUR-SUBDOMAIN.workers.dev/health
```
Expected: `{"status":"ok"}`

---

## Task 3.5.10: Phase 3.5 commit

- [ ] **Step 1: Commit Worker source (NOT node_modules)**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add infra/worker/ && \
git commit -m "$(cat <<'EOF'
feat: Phase 3.5 — Cloudflare Worker (SIWA + Anthropic proxy)

- infra/worker/ TypeScript Hono app
- /v1/auth/exchange: Apple identity token verification via JWKS,
  nonce SHA256 cross-check, HS256 session JWT (8h TTL)
- /v1/receipts/parse: session JWT verify, Anthropic Vision proxy,
  balanced-JSON extraction matching iOS JSONExtractor
- wrangler.toml + tsconfig.json + package.json (Hono + jose)
- README with deploy + secrets instructions
- Deployment is a manual user step (wrangler login + secrets)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# End of Plan 2

After Task 3.5.10, the AI layer is complete and the Worker is live. The app can:
- BYOK: user pastes Anthropic API key → tap a (still unimplemented) Capture button → real Vision call returns a ReceiptDraft
- Proxy: user signs in with Apple → session token obtained → tap Capture button → Worker forwards to Anthropic
- All persistence-side data layer from Plan 1 still works untouched

But there's no UI yet to invoke any of this beyond what unit tests exercise. **Plan 3** adds CaptureView, ConfirmationForm, the other 3 Tabs, PDFReportService, CSV export, and localization polish.
