import Foundation

/// One expense row in the 青色申告決算書 review summary.
public struct KessanshoExpenseLine: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let amount: Int

    public init(label: String, amount: Int) {
        self.label = label
        self.amount = amount
    }
}

/// Maps SnapKei expense account codes onto 青色申告決算書 expense row labels.
public enum KessanshoLineMapping {
    public static let legalRows: [String] = [
        "租税公課",
        "荷造運賃",
        "水道光熱費",
        "旅費交通費",
        "通信費",
        "広告宣伝費",
        "接待交際費",
        "損害保険料",
        "修繕費",
        "消耗品費",
        "減価償却費",
        "福利厚生費",
        "給料賃金",
        "外注工賃",
        "利子割引料",
        "地代家賃",
        "貸倒金",
    ]
    public static let miscRow = "雑費"
    public static let blankRowLimit = 5

    private static let standardRowByCode: [String: String] = [
        "5100": "旅費交通費",
        "5110": "通信費",
        "5120": "接待交際費",
        "5140": "消耗品費",
        "5170": "水道光熱費",
        "5180": "地代家賃",
        "5190": "外注工賃",
        "5210": "修繕費",
        "5220": "租税公課",
        "5230": "減価償却費",
        "5290": miscRow,
    ]

    public static func expenseLines(
        expenseByCode: [String: Int],
        accountNameByCode: [String: String]
    ) -> [KessanshoExpenseLine] {
        var standardTotals: [String: Int] = [:]
        var miscTotal = 0
        var customCandidates: [(code: String, amount: Int)] = []

        for (code, amount) in expenseByCode where amount != 0 {
            guard let standardRow = standardRowByCode[code] else {
                customCandidates.append((code, amount))
                continue
            }

            if standardRow == miscRow {
                miscTotal += amount
            } else {
                standardTotals[standardRow, default: 0] += amount
            }
        }

        customCandidates.sort { $0.code < $1.code }

        var customLines: [KessanshoExpenseLine] = []
        for (index, candidate) in customCandidates.enumerated() {
            if index < blankRowLimit {
                customLines.append(KessanshoExpenseLine(
                    label: accountNameByCode[candidate.code] ?? candidate.code,
                    amount: candidate.amount
                ))
            } else {
                miscTotal += candidate.amount
            }
        }

        var result: [KessanshoExpenseLine] = []
        for row in legalRows {
            if let total = standardTotals[row], total != 0 {
                result.append(KessanshoExpenseLine(label: row, amount: total))
            }
        }
        result.append(contentsOf: customLines)
        if miscTotal != 0 {
            result.append(KessanshoExpenseLine(label: miscRow, amount: miscTotal))
        }
        return result
    }
}
