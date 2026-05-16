import Foundation

public enum JSONExtractor {
    public static func extractJSONObject(from text: String) throws -> Data {
        if let range = text.range(of: "```json") {
            let rest = text[range.upperBound...]
            if let end = rest.range(of: "```") {
                return Data(rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            }
        }

        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            throw AIServiceError.invalidResponse("no JSON object found")
        }
        return Data(text[start...end].utf8)
    }
}

public enum ReceiptDraftDecoder {
    public static func decode(_ data: Data) throws -> ReceiptDraft {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.dateFormatter)
        return try decoder.decode(ReceiptDraft.self, from: data)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
