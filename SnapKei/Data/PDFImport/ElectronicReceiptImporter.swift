import Foundation

#if canImport(UIKit)
import PDFKit
import UIKit

public enum ElectronicReceiptImporter {
    public struct Result: Sendable, Equatable {
        public let jpegData: Data
        public let originalPDFRelativePath: String
        public let originalPDFHash: String
    }

    public enum Error: Swift.Error, Equatable {
        case cannotOpenPDF
        case noPages
        case renderFailed
    }

    public static func process(pdfURL: URL, fiscalYear: Int, transactionDate: Date) throws -> Result {
        guard let pdf = PDFDocument(url: pdfURL) else { throw Error.cannotOpenPDF }
        guard let page = pdf.page(at: 0) else { throw Error.noPages }

        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(pageRect)
            context.cgContext.translateBy(x: 0, y: pageRect.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else { throw Error.renderFailed }

        let originalData = try Data(contentsOf: pdfURL)
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent("electronic", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = "\(formatter.string(from: transactionDate))_\(UUID().uuidString.prefix(8).lowercased()).pdf"
        try originalData.write(to: directory.appendingPathComponent(filename), options: [.atomic])

        return Result(
            jpegData: jpegData,
            originalPDFRelativePath: "receipts/electronic/\(fiscalYear)/\(filename)",
            originalPDFHash: ImageStorageService.sha256Hex(originalData)
        )
    }
}
#endif
