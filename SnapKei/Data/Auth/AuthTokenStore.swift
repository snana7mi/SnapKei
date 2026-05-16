import Foundation

public struct StoredAuthSession: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let appleUserId: String
}

public final class AuthTokenStore: @unchecked Sendable {
    private enum Keys {
        static let accessToken = "gateway.accessToken"
        static let refreshToken = "gateway.refreshToken"
        static let appleUserId = "gateway.appleUserId"
    }

    private let keychain: SecretStore

    public init(keychain: SecretStore = KeychainService()) {
        self.keychain = keychain
    }

    public func save(accessToken: String, refreshToken: String, appleUserId: String) throws {
        try keychain.save(accessToken, account: Keys.accessToken)
        try keychain.save(refreshToken, account: Keys.refreshToken)
        try keychain.save(appleUserId, account: Keys.appleUserId)
    }

    public func updateAccessToken(_ accessToken: String, refreshToken: String? = nil) throws {
        guard let stored = try load() else { throw AIServiceError.proxyAuthRequired }
        try save(
            accessToken: accessToken,
            refreshToken: refreshToken ?? stored.refreshToken,
            appleUserId: stored.appleUserId
        )
    }

    public func load() throws -> StoredAuthSession? {
        guard let accessToken = try keychain.read(account: Keys.accessToken),
              let refreshToken = try keychain.read(account: Keys.refreshToken),
              let appleUserId = try keychain.read(account: Keys.appleUserId) else { return nil }
        return StoredAuthSession(accessToken: accessToken, refreshToken: refreshToken, appleUserId: appleUserId)
    }

    public func clearSession() throws {
        try keychain.delete(account: Keys.accessToken)
        try keychain.delete(account: Keys.refreshToken)
        try keychain.delete(account: Keys.appleUserId)
    }
}
