import Testing
@testable import SnapKei

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var storage: [String: String] = [:]

    func save(_ value: String, account: String) throws {
        storage[account] = value
    }

    func read(account: String) throws -> String? {
        storage[account]
    }

    func delete(account: String) throws {
        storage[account] = nil
    }
}

@Suite("ByokKeyStore")
struct ByokKeyStoreTests {

    @Test func saveAndLoad_roundTrips() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveKey("sk-ant-test-123", for: .anthropic)
        #expect(try store.loadKey(for: .anthropic) == "sk-ant-test-123")
        #expect(store.hasKey(for: .anthropic))
    }

    @Test func save_trimsWhitespace() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveKey("  sk-ant-x \n", for: .anthropic)
        #expect(try store.loadKey(for: .anthropic) == "sk-ant-x")
    }

    @Test func save_emptyString_deletesKey() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveKey("sk-ant-x", for: .anthropic)
        try store.saveKey("   ", for: .anthropic)
        #expect(try store.loadKey(for: .anthropic) == nil)
        #expect(!store.hasKey(for: .anthropic))
    }

    @Test func delete_removesKey() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveKey("sk-ant-x", for: .anthropic)
        try store.deleteKey(for: .anthropic)
        #expect(try store.loadKey(for: .anthropic) == nil)
    }

    @Test func keys_areIsolatedPerFormat() throws {
        let store = ByokKeyStore(store: InMemorySecretStore())
        try store.saveKey("sk-ant", for: .anthropic)
        try store.saveKey("sk-openai", for: .openAI)
        #expect(try store.loadKey(for: .anthropic) == "sk-ant")
        #expect(try store.loadKey(for: .openAI) == "sk-openai")
    }

    @Test func keys_areDeviceScoped_notTiedToUserIdentity() throws {
        // BYOK is the no-sign-in path: a key saved while signed out must remain readable
        // regardless of any later auth state change. The account must not encode a user id.
        let backing = InMemorySecretStore()
        try ByokKeyStore(store: backing).saveKey("sk-ant-x", for: .anthropic)
        #expect(backing.storage.keys.contains("byok.apiKey.anthropic"))
        #expect(backing.storage.keys.allSatisfy { !$0.contains("_anonymous") })
    }
}
