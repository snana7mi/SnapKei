import Foundation

public final class SyncChangeNotifier: @unchecked Sendable {
    public static let shared = SyncChangeNotifier()

    public nonisolated let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init() {
        (self.changes, self.continuation) = AsyncStream.makeStream()
    }

    public func notify() {
        continuation.yield()
    }
}
