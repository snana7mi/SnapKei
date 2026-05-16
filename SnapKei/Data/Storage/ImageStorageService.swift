import CryptoKit
import Foundation

public enum ImageStorageService {
    public struct Result: Sendable, Equatable {
        public let relativePath: String
        public let sha256Hex: String
    }

    public enum Error: Swift.Error, Equatable {
        case writeFailed
    }

    public static func persist(
        jpegData: Data,
        fiscalYear: Int,
        transactionDate: Date,
        fileExtension: String = "jpg"
    ) throws -> Result {
        let documents = try documentsDirectory(create: true)
        let directory = documents
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = makeFilename(transactionDate: transactionDate, fileExtension: fileExtension)
        let url = directory.appendingPathComponent(filename)
        do {
            try jpegData.write(to: url, options: [.atomic])
        } catch {
            throw Error.writeFailed
        }

        return Result(
            relativePath: "receipts/\(fiscalYear)/\(filename)",
            sha256Hex: sha256Hex(jpegData)
        )
    }

    public static func absoluteURL(for relativePath: String) -> URL? {
        guard let documents = try? documentsDirectory(create: false) else { return nil }
        return documents.appendingPathComponent(relativePath)
    }

    public static func verifyIntegrity(at relativePath: String, expectedHash: String) -> Bool {
        guard let url = absoluteURL(for: relativePath),
              let data = try? Data(contentsOf: url) else { return false }
        return sha256Hex(data) == expectedHash
    }

    public static func delete(relativePath: String) {
        guard let url = absoluteURL(for: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func documentsDirectory(create: Bool) throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
    }

    private static func makeFilename(transactionDate: Date, fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let datePart = formatter.string(from: transactionDate)
        let shortID = UUID().uuidString.prefix(8).lowercased()
        return "\(datePart)_\(shortID).\(fileExtension)"
    }
}
