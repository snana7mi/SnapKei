import Foundation
import Testing
@testable import SnapKei

@Suite("ReceiptAttachment")
struct ReceiptAttachmentTests {

    @Test func nilPath_returnsNil() {
        #expect(ReceiptAttachment.resolve(relativePath: nil, expectedHash: nil) == nil)
    }

    @Test func jpegFile_withMatchingHash_isVerifiedImage() throws {
        let data = Data(repeating: 0xCD, count: 128)
        let stored = try ImageStorageService.persist(jpegData: data, fiscalYear: 2026, transactionDate: Date())

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: stored.sha256Hex
        ))

        #expect(attachment.kind == .image)
        #expect(attachment.integrity == .verified)
        #expect(try Data(contentsOf: attachment.url) == data)
    }

    @Test func wrongHash_isTampered() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x01, count: 64), fiscalYear: 2026, transactionDate: Date()
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: "deadbeef"
        ))

        #expect(attachment.integrity == .tampered)
    }

    @Test func missingFile_isMissing() throws {
        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: "receipts/2026/does-not-exist.jpg", expectedHash: "x"
        ))

        #expect(attachment.integrity == .missingFile)
    }

    @Test func nilHash_isUnverified() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x02, count: 64), fiscalYear: 2026, transactionDate: Date()
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: nil
        ))

        #expect(attachment.integrity == .unverified)
    }

    @Test func pdfExtension_isPdfKind() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x03, count: 64), fiscalYear: 2026,
            transactionDate: Date(), fileExtension: "pdf"
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: stored.sha256Hex
        ))

        #expect(attachment.kind == .pdf)
        #expect(attachment.integrity == .verified)
    }
}
