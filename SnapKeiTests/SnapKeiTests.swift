import Testing
@testable import SnapKei

@Suite("SnapKei smoke tests")
struct SnapKeiTests {
    @Test func appModuleLoads() {
        #expect(Bool(true))
    }
}
