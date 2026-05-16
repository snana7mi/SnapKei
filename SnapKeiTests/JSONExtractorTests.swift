import Foundation
import Testing
@testable import SnapKei

@Suite("JSONExtractor")
struct JSONExtractorTests {
    @Test func extractsFencedJSON() throws {
        let data = try JSONExtractor.extractJSONObject(from: "text```json\n{\"amountIncludingTax\":1100}\n```tail")
        #expect(String(data: data, encoding: .utf8) == "{\"amountIncludingTax\":1100}")
    }

    @Test func extractsFirstJSONObject() throws {
        let data = try JSONExtractor.extractJSONObject(from: "prefix {\"ok\":true} suffix")
        #expect(String(data: data, encoding: .utf8) == "{\"ok\":true}")
    }
}
