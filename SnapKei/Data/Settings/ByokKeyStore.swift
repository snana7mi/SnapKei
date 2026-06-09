import Foundation

/// Stores the user's own (BYOK) API keys in the Keychain, one per AI format.
/// Keys are DEVICE-scoped (not tied to any signed-in account) because BYOK is the
/// no-sign-in path: a key saved while signed out must stay readable across any later
/// auth state change.
public struct ByokKeyStore: Sendable {
    public nonisolated static let accountPrefix = "byok.apiKey"

    private let store: SecretStore

    public nonisolated init(store: SecretStore = KeychainService()) {
        self.store = store
    }

    private nonisolated func account(for format: APIFormat) -> String {
        "\(Self.accountPrefix).\(format.rawValue)"
    }

    public nonisolated func saveKey(_ key: String, for format: APIFormat) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try store.delete(account: account(for: format))
        } else {
            try store.save(trimmed, account: account(for: format))
        }
    }

    public nonisolated func loadKey(for format: APIFormat) throws -> String? {
        try store.read(account: account(for: format))
    }

    public nonisolated func deleteKey(for format: APIFormat) throws {
        try store.delete(account: account(for: format))
    }

    public nonisolated func hasKey(for format: APIFormat) -> Bool {
        ((try? store.read(account: account(for: format))) ?? nil)?.isEmpty == false
    }
}
