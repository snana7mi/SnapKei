import Foundation

extension JSONEncoder {
    static var snapkeiSync: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.snapkeiSync.string(from: date))
        }
        return encoder
    }
}

extension JSONDecoder {
    static var snapkeiSync: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.snapkeiSync.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(string)")
            }
            return date
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    nonisolated static var snapkeiSync: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
