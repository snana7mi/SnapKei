import Testing
@testable import SnapKei

@Suite("NonceGenerator")
struct NonceGeneratorTests {
    @Test func sha256KnownValue() {
        #expect(NonceGenerator.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func makePairHasRequestedLengthAndHash() {
        let pair = NonceGenerator.makePair(length: 16)
        #expect(pair.raw.count == 16)
        #expect(pair.hashedSHA256 == NonceGenerator.sha256(pair.raw))
    }
}
