import Foundation
import Security

public protocol SecretStore: Sendable {
    func save(_ value: String, account: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

public final class KeychainService: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.cheung.SnapKei") {
        self.service = service
    }

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    public func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw keychainError(status) }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw keychainError(status)
        }
    }

    private func keychainError(_ status: OSStatus) -> AIServiceError {
        AIServiceError.network("Keychain status \(status)")
    }
}
