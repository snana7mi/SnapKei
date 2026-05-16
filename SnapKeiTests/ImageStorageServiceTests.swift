import Foundation
import Testing
@testable import SnapKei

@Suite("ImageStorageService")
struct ImageStorageServiceTests {
    @Test func persistWritesFileAndReturnsHashAndRelativePath() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04])
        let date = ISO8601DateFormatter().date(from: "2026-05-16T17:45:23+09:00")!

        let result = try ImageStorageService.persist(jpegData: data, fiscalYear: 2026, transactionDate: date)

        #expect(result.relativePath.hasPrefix("receipts/2026/2026-05-16_174523_"))
        #expect(result.relativePath.hasSuffix(".jpg"))
        #expect(result.sha256Hex.count == 64)
        let url = try #require(ImageStorageService.absoluteURL(for: result.relativePath))
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func verifyIntegrityReturnsTrueOnlyForMatchingHash() throws {
        let data = Data(repeating: 0xAB, count: 256)
        let result = try ImageStorageService.persist(jpegData: data, fiscalYear: 2026, transactionDate: Date())

        #expect(ImageStorageService.verifyIntegrity(at: result.relativePath, expectedHash: result.sha256Hex))
        #expect(!ImageStorageService.verifyIntegrity(at: result.relativePath, expectedHash: "wrong"))
    }
}
