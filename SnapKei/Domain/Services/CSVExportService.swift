import Foundation

public enum CSVExportService {
    public static func export(
        _ entries: [JournalEntry],
        accountNameLookup: (String) -> String
    ) -> Data {
        var output = "\u{FEFF}日付,借方科目,貸方科目,取引内容,取引先,税込金額,税抜金額,消費税,適格番号,備考\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for entry in entries {
            let row = [
                formatter.string(from: entry.transactionDate),
                escape(accountNameLookup(entry.debitAccountCode)),
                escape(accountNameLookup(entry.creditAccountCode)),
                escape(entry.transactionDescription),
                escape(entry.counterpartyName),
                String(entry.amountIncludingTax),
                String(entry.amountExcludingTax),
                String(entry.consumptionTax),
                escape(entry.invoiceRegistrationNumber ?? ""),
                escape(entry.memo ?? ""),
            ].joined(separator: ",")
            output.append(row)
            output.append("\n")
        }

        return Data(output.utf8)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
