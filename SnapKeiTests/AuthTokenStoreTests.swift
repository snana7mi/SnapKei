import Foundation
import Testing
@testable import SnapKei

final class MemorySecretStore: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func save(_ value: String, account: String) throws { values[account] = value }
    func read(account: String) throws -> String? { values[account] }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

@Suite("AuthTokenStore")
struct AuthTokenStoreTests {
    @Test func roundTripGatewayTokens() throws {
        let store = AuthTokenStore(keychain: MemorySecretStore())
        try store.save(accessToken: "access", refreshToken: "refresh", appleUserId: "apple")
        let loaded = try store.load()
        #expect(loaded?.accessToken == "access")
        #expect(loaded?.refreshToken == "refresh")
        #expect(loaded?.appleUserId == "apple")
    }

    @Test func updateAccessTokenPreservesRefreshAndUser() throws {
        let store = AuthTokenStore(keychain: MemorySecretStore())
        try store.save(accessToken: "old", refreshToken: "refresh", appleUserId: "apple")
        try store.updateAccessToken("new")
        let loaded = try store.load()
        #expect(loaded?.accessToken == "new")
        #expect(loaded?.refreshToken == "refresh")
        #expect(loaded?.appleUserId == "apple")
    }

    @Test func clearSessionRemovesValues() throws {
        let store = AuthTokenStore(keychain: MemorySecretStore())
        try store.save(accessToken: "access", refreshToken: "refresh", appleUserId: "apple")
        try store.clearSession()
        #expect(try store.load() == nil)
    }
}
