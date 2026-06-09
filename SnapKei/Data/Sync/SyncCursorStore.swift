import Foundation

public final class SyncCursorStore: @unchecked Sendable {
    public nonisolated static let cachedAppleSubKey = "LLMGatewayKit.cachedAppleSub"

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
