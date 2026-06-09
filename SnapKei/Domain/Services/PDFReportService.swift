import Foundation
import SwiftData

#if canImport(UIKit)
import UIKit

public enum PDFReportService {
    public enum Error: Swift.Error, Equatable {
        case renderFailed
    }

    public static func renderProfitAndLoss(fiscalYear: Int, context: ModelContext) throws -> Data {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && !$0.isVoided }
        ))
        let accounts = try context.fetch(FetchDescriptor<Account>())

        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        let summary = ProfitAndLossService.summary(entries: entries, accounts: accounts)
        let revenueByCode = summary.revenueByCode
        let expenseByCode = summary.expenseByCode
        let revenueTotal = summary.revenueTotal
        let expenseTotal = summary.expenseTotal
        let netIncome = summary.netIncome

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()

            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12)]

            "損益計算書 (\(fiscalYear) 年)".draw(at: CGPoint(x: 40, y: 40), withAttributes: title)
            var y: CGFloat = 100
            drawSection("売上", totals: revenueByCode, accounts: accountByCode, y: &y, body: body, bold: bold, context: context)
            "売上合計".draw(at: CGPoint(x: 60, y: y), withAttributes: bold)
            "¥\(revenueTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
            y += 36

            drawSection("経費", totals: expenseByCode, accounts: accountByCode, y: &y, body: body, bold: bold, context: context)
            "経費合計".draw(at: CGPoint(x: 60, y: y), withAttributes: bold)
            "¥\(expenseTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
            y += 36

            "所得金額".draw(at: CGPoint(x: 40, y: y), withAttributes: title)
            "¥\(netIncome)".draw(at: CGPoint(x: 450, y: y), withAttributes: title)
        }
    }

    public static func renderBalanceSheet(fiscalYear: Int, context: ModelContext) throws -> Data {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && !$0.isVoided }
        ))
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let openingBalances = try OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)
        let report = BalanceSheetService.report(
            fiscalYear: fiscalYear,
            entries: entries,
            openingBalances: openingBalances,
            accounts: accounts
        )

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()

            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12)]

            "貸借対照表 (\(fiscalYear) 年)".draw(at: CGPoint(x: 40, y: 40), withAttributes: title)
            var y: CGFloat = 96
            drawBalanceSection("資産", lines: report.assetLines, y: &y, body: body, bold: bold, context: context)
            "事業主貸".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(report.ownerDrawClosing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 24
            "資産合計".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
            "¥\(report.assetTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
            y += 42

            drawBalanceSection("負債", lines: report.liabilityLines, y: &y, body: body, bold: bold, context: context)
            "純資産".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
            y += 24
            "事業主借".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(report.ownerLoanClosing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 20
            "元入金".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(report.capitalClosing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 20
            if report.otherEquityClosing != 0 {
                "その他純資産".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                "¥\(report.otherEquityClosing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
                y += 20
            }
            "当期所得".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(report.netIncome)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 28
            "負債・純資産合計".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
            "¥\(report.liabilityEquityTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: bold)
        }
    }

    private static func drawSection(
        _ title: String,
        totals: [String: Int],
        accounts: [String: Account],
        y: inout CGFloat,
        body: [NSAttributedString.Key: Any],
        bold: [NSAttributedString.Key: Any],
        context: UIGraphicsPDFRendererContext
    ) {
        "【\(title)】".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
        y += 24
        for (code, amount) in totals.sorted(by: { $0.key < $1.key }) {
            let name = accounts[code]?.nameJa ?? code
            "\(code) \(name)".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(amount)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 18
            if y > 760 {
                context.beginPage()
                y = 60
            }
        }
    }

    private static func drawBalanceSection(
        _ title: String,
        lines: [BalanceSheetLine],
        y: inout CGFloat,
        body: [NSAttributedString.Key: Any],
        bold: [NSAttributedString.Key: Any],
        context: UIGraphicsPDFRendererContext
    ) {
        "【\(title)】".draw(at: CGPoint(x: 40, y: y), withAttributes: bold)
        y += 24
        for line in lines {
            "\(line.accountCode) \(line.accountName)".draw(at: CGPoint(x: 60, y: y), withAttributes: body)
            "¥\(line.closing)".draw(at: CGPoint(x: 450, y: y), withAttributes: body)
            y += 18
            if y > 760 {
                context.beginPage()
                y = 60
            }
        }
    }
}
#endif
