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

    public static func exportLedgerLines(_ lines: [LedgerLine]) -> Data {
        var output = "\u{FEFF}日付,仕訳番号,相手科目,摘要,借方,貸方,残高\n"
        let formatter = csvDateFormatter()
        for line in lines {
            output.append([
                formatter.string(from: line.transactionDate),
                String(line.entryNumber),
                escape(line.counterAccountCode),
                escape(line.summary),
                String(line.debit),
                String(line.credit),
                String(line.runningBalance),
            ].joined(separator: ","))
            output.append("\n")
        }
        return Data(output.utf8)
    }

    public static func exportTrialBalance(_ report: TrialBalanceReport) -> Data {
        var output = "\u{FEFF}勘定科目コード,勘定科目名,借方合計,貸方合計,期首残高,期末残高\n"
        for row in report.rows {
            output.append([
                escape(row.accountCode),
                escape(row.accountName),
                String(row.debitTotal),
                String(row.creditTotal),
                String(row.openingBalance),
                String(row.closingBalance),
            ].joined(separator: ","))
            output.append("\n")
        }
        output.append("合計,,\(report.totalDebit),\(report.totalCredit),,\n")
        return Data(output.utf8)
    }

    public static func exportProfitAndLoss(_ summary: PLSummary) -> Data {
        var output = "\u{FEFF}区分,勘定科目コード,金額\n"
        for (code, amount) in summary.revenueByCode.sorted(by: { $0.key < $1.key }) {
            output.append("売上,\(escape(code)),\(amount)\n")
        }
        output.append("売上合計,,\(summary.revenueTotal)\n")
        for (code, amount) in summary.expenseByCode.sorted(by: { $0.key < $1.key }) {
            output.append("経費,\(escape(code)),\(amount)\n")
        }
        output.append("経費合計,,\(summary.expenseTotal)\n")
        output.append("所得金額,,\(summary.netIncome)\n")
        return Data(output.utf8)
    }

    public static func exportBalanceSheet(_ report: BalanceSheetReport) -> Data {
        var output = "\u{FEFF}貸借対照表,\(report.fiscalYear)\n区分,勘定科目コード,勘定科目名,期首,期末\n"
        for line in report.assetLines {
            output.append("資産,\(escape(line.accountCode)),\(escape(line.accountName)),\(line.opening),\(line.closing)\n")
        }
        output.append("資産,3220,事業主貸,,\(report.ownerDrawClosing)\n")
        output.append("資産合計,\(report.assetTotal)\n")
        for line in report.liabilityLines {
            output.append("負債,\(escape(line.accountCode)),\(escape(line.accountName)),\(line.opening),\(line.closing)\n")
        }
        output.append("純資産,3210,事業主借,,\(report.ownerLoanClosing)\n")
        output.append("純資産,3110,元入金,,\(report.capitalClosing)\n")
        if report.otherEquityClosing != 0 {
            output.append("純資産,その他,その他純資産,,\(report.otherEquityClosing)\n")
        }
        output.append("純資産,当期所得,,,\(report.netIncome)\n")
        output.append("負債・純資産合計,\(report.liabilityEquityTotal)\n")
        return Data(output.utf8)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func csvDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
