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

    public static func renderKessansho(report: KessanshoReport) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        func yen(_ amount: Int) -> String {
            YenFormat.string(amount)
        }

        return renderer.pdfData { context in
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
            let subtitle: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11)]
            let warning: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: UIColor.systemRed,
            ]
            var y: CGFloat = 40

            func newPage() {
                context.beginPage()
                y = 40
            }

            func ensure(_ height: CGFloat) {
                if y + height > 800 { newPage() }
            }

            func text(_ value: String, x: CGFloat, attrs: [NSAttributedString.Key: Any] = body) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }

            func row(_ label: String, _ value: String, attrs: [NSAttributedString.Key: Any] = body) {
                ensure(18)
                text(label, x: 60, attrs: attrs)
                text(value, x: 420, attrs: attrs)
                y += 18
            }

            func section(_ value: String) {
                ensure(34)
                y += 8
                text("【\(value)】", x: 40, attrs: bold)
                y += 24
            }

            newPage()
            text("青色申告決算書 確認サマリー (\(report.header.fiscalYear) 年分)", x: 40, attrs: title)
            y += 28
            text("申告内容の確認用サマリーです。国税庁の公式様式そのものではありません。", x: 40, attrs: subtitle)
            y += 18
            text("氏名: \(report.header.ownerName)   屋号: \(report.header.businessName)", x: 40, attrs: body)
            y += 24

            section("申告前チェック")
            row("貸借状態", report.balanceSheet.isBalanced ? "貸借一致" : "貸借不一致", attrs: report.balanceSheet.isBalanced ? body : warning)
            row("青色申告特別控除額", yen(report.profitAndLoss.blueDeduction))
            row(
                "減価償却",
                report.hasProjectedDepreciation ? "未計上見込あり" : "計上済",
                attrs: report.hasProjectedDepreciation ? warning : body
            )

            let profitAndLoss = report.profitAndLoss
            section("損益計算書")
            row("売上(収入)金額", yen(profitAndLoss.salesRevenue))
            row("売上原価", yen(profitAndLoss.costOfGoodsSold))
            row("差引金額", yen(profitAndLoss.grossProfit))
            for line in profitAndLoss.expenseRows {
                row(line.label, yen(line.amount))
            }
            row("経費計", yen(profitAndLoss.expenseTotal), attrs: bold)
            row("青色申告特別控除前の所得金額", yen(profitAndLoss.netBeforeDeduction))
            row("青色申告特別控除額", yen(profitAndLoss.blueDeduction))
            row("所得金額", yen(profitAndLoss.income), attrs: bold)

            section("月別売上(収入)金額")
            for month in report.monthly {
                row("\(month.month) 月", yen(month.sales))
            }

            section("減価償却費の計算")
            if report.depreciation.isEmpty {
                row("対象資産なし", "")
            } else {
                for item in report.depreciation {
                    row("\(item.assetName) (\(item.acquisitionYearMonth), \(item.method), \(item.usefulLifeYears)年)", item.isPosted ? "計上済" : "未計上見込")
                    row("取得価額", yen(item.acquisitionAmount))
                    row("本年償却 / 必要経費算入", "\(yen(item.yearDepreciation)) / \(yen(item.deductibleAmount))")
                    row("事業割合 / 期末残高", "\(item.businessRatePercent)% / \(yen(item.yearEndBalance))")
                }
            }

            if !report.rentDetails.isEmpty {
                section("地代家賃の内訳")
                for rent in report.rentDetails {
                    row(rent.payee, "賃借料 \(yen(rent.annualRent)) / 経費算入 \(yen(rent.deductibleAmount))")
                }
            }

            let balanceSheet = report.balanceSheet
            section("貸借対照表")
            row("資産合計", yen(balanceSheet.assetTotal), attrs: bold)
            row("負債・資本合計", yen(balanceSheet.liabilityEquityTotal), attrs: bold)
            if !balanceSheet.isBalanced {
                row("警告", "貸借が一致していません", attrs: warning)
            }
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
