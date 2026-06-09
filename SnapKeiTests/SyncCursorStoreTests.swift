import Foundation
import Testing
@testable import SnapKei

@Suite("SyncCursorStore")
struct SyncCursorStoreTests {

    private func makeSuite() -> UserDefaults {
        UserDefaults(suiteName: "SyncCursorStoreTests-\(UUID().uuidString)")!
    }

    @Test func cursor_isIsolatedPerUser() {
        let suite = makeSuite()
        nonisolated(unsafe) var currentUser = "user-a"
        let store = SyncCursorStore(suite: suite, userIDProvider: { currentUser })

        let dateA = Date(timeIntervalSince1970: 1_000)
        store.lastPushedAt = dateA
        #expect(store.lastPushedAt == dateA)

        currentUser = "user-b"
        #expect(store.lastPushedAt == nil)

        currentUser = "user-a"
        #expect(store.lastPushedAt == dateA)
    }

    @Test func reset_onlyClearsCurrentUser() {
        let suite = makeSuite()
        nonisolated(unsafe) var currentUser = "user-a"
        let store = SyncCursorStore(suite: suite, userIDProvider: { currentUser })
        store.lastPushedAt = Date(timeIntervalSince1970: 1_000)

        currentUser = "user-b"
        store.lastPushedAt = Date(timeIntervalSince1970: 2_000)
        store.reset()
        #expect(store.lastPushedAt == nil)

        currentUser = "user-a"
        #expect(store.lastPushedAt == Date(timeIntervalSince1970: 1_000))
    }
}
