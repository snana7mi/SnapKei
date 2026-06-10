import Foundation

public struct KessanshoReport: Equatable, Sendable {
    public struct Header: Equatable, Sendable {
        public let fiscalYear: Int
        public let ownerName: String
        public let businessName: String
    }

    public struct ProfitAndLoss: Equatable, Sendable {
        public let salesRevenue: Int
        public let costOfGoodsSold: Int
        public let grossProfit: Int
        public let expenseRows: [KessanshoExpenseLine]
        public let expenseTotal: Int
        public let netBeforeDeduction: Int
        public let blueDeduction: Int
        public let income: Int
    }

    public struct MonthlyRow: Equatable, Sendable, Identifiable {
        public var id: Int { month }
        public let month: Int
        public let sales: Int
    }

    public struct DepreciationRow: Equatable, Sendable, Identifiable {
        public var id: UUID { assetId }
        public let assetId: UUID
        public let assetName: String
        public let acquisitionYearMonth: String
        public let acquisitionAmount: Int
        public let method: String
        public let usefulLifeYears: Int
        public let yearDepreciation: Int
        public let businessRatePercent: Int
        public let deductibleAmount: Int
        public let yearEndBalance: Int
        public let isPosted: Bool
    }

    public struct RentRow: Equatable, Sendable, Identifiable {
        public var id: String { payee }
        public let payee: String
        public let annualRent: Int
        public let deductibleAmount: Int
    }

    public let header: Header
    public let profitAndLoss: ProfitAndLoss
    public let monthly: [MonthlyRow]
    public let depreciation: [DepreciationRow]
    public let rentDetails: [RentRow]
    public let balanceSheet: BalanceSheetReport

    /// 画面の申告前チェック・出力確認・PDF の三者が同じ定義を参照する。
    public var hasProjectedDepreciation: Bool {
        depreciation.contains { !$0.isPosted }
    }
}

public enum KessanshoService {
    public static func build(
        fiscalYear: Int,
        header: KessanshoReport.Header,
        entries: [JournalEntry],
        accounts: [Account],
        assets: [FixedAsset],
        openingBalances: [String: Int],
        maxBlueDeduction: Int
    ) -> KessanshoReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let targetYearEntries = entries.filter { $0.fiscalYear == fiscalYear && !$0.isVoided }
        let nonVoidedEntriesThroughFiscalYear = entries.filter { $0.fiscalYear <= fiscalYear && !$0.isVoided }
        let accountByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0) })
        let accountNameByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.nameJa) })

        let profitAndLossSummary = ProfitAndLossService.summary(entries: targetYearEntries, accounts: accounts)
        let expenseRows = KessanshoLineMapping.expenseLines(
            expenseByCode: profitAndLossSummary.expenseByCode,
            accountNameByCode: accountNameByCode
        )
        let netBeforeDeduction = profitAndLossSummary.netIncome
        let blueDeduction = min(maxBlueDeduction, max(0, netBeforeDeduction))
        let profitAndLoss = KessanshoReport.ProfitAndLoss(
            salesRevenue: profitAndLossSummary.revenueTotal,
            costOfGoodsSold: 0,
            grossProfit: profitAndLossSummary.revenueTotal,
            expenseRows: expenseRows,
            expenseTotal: profitAndLossSummary.expenseTotal,
            netBeforeDeduction: netBeforeDeduction,
            blueDeduction: blueDeduction,
            income: netBeforeDeduction - blueDeduction
        )

        let monthly = monthlyRows(
            fiscalYearEntries: targetYearEntries,
            accountByCode: accountByCode,
            calendar: calendar
        )
        let depreciation = depreciationRows(
            fiscalYear: fiscalYear,
            assets: assets,
            targetYearEntries: targetYearEntries,
            entriesThroughFiscalYear: nonVoidedEntriesThroughFiscalYear,
            calendar: calendar
        )
        let rentDetails = rentRows(entries: targetYearEntries)
        let balanceSheet = BalanceSheetService.report(
            fiscalYear: fiscalYear,
            entries: targetYearEntries,
            openingBalances: openingBalances,
            accounts: accounts
        )

        return KessanshoReport(
            header: header,
            profitAndLoss: profitAndLoss,
            monthly: monthly,
            depreciation: depreciation,
            rentDetails: rentDetails,
            balanceSheet: balanceSheet
        )
    }

    private static func monthlyRows(
        fiscalYearEntries: [JournalEntry],
        accountByCode: [String: Account],
        calendar: Calendar
    ) -> [KessanshoReport.MonthlyRow] {
        var monthlySales = Array(repeating: 0, count: 12)
        for entry in fiscalYearEntries {
            let month = calendar.component(.month, from: entry.transactionDate)
            guard (1...12).contains(month) else { continue }

            if accountByCode[entry.creditAccountCode]?.accountType == .revenue {
                monthlySales[month - 1] += entry.amountIncludingTax
            }
            if accountByCode[entry.debitAccountCode]?.accountType == .revenue {
                monthlySales[month - 1] -= entry.amountIncludingTax
            }
        }

        return (1...12).map {
            KessanshoReport.MonthlyRow(month: $0, sales: monthlySales[$0 - 1])
        }
    }

    private static let acquisitionYearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func methodLabel(for asset: FixedAsset) -> String {
        switch asset.treatment {
        case .normalDepreciation: "定額法"
        case .lumpSumDepreciation: "一括償却"
        case .smallAmountFullExpense: "即時償却"
        }
    }

    private static func depreciationRows(
        fiscalYear: Int,
        assets: [FixedAsset],
        targetYearEntries: [JournalEntry],
        entriesThroughFiscalYear: [JournalEntry],
        calendar: Calendar
    ) -> [KessanshoReport.DepreciationRow] {
        let ymFormatter = acquisitionYearMonthFormatter

        return assets
            .filter { $0.deletedAt == nil }
            .filter { calendar.component(.year, from: $0.serviceStartDate) <= fiscalYear }
            .sorted { $0.acquisitionDate < $1.acquisitionDate }
            .compactMap { asset in
                let targetEntries = postedDepreciationEntries(for: asset, in: targetYearEntries)
                if !targetEntries.isEmpty {
                    let postedThroughYear = postedDepreciationEntries(for: asset, in: entriesThroughFiscalYear)
                    let postedAccumulated = postedThroughYear.reduce(0) { $0 + $1.amountIncludingTax }
                    let yearDepreciation = targetEntries.reduce(0) { $0 + $1.amountIncludingTax }
                    let deductibleAmount = targetEntries.reduce(0) {
                        $0 + ($1.debitAccountCode == AccountCode.depreciationExpense ? $1.amountIncludingTax : 0)
                    }
                    return KessanshoReport.DepreciationRow(
                        assetId: asset.syncId,
                        assetName: asset.assetName,
                        acquisitionYearMonth: ymFormatter.string(from: asset.acquisitionDate),
                        acquisitionAmount: asset.acquisitionAmount,
                        method: methodLabel(for: asset),
                        usefulLifeYears: asset.usefulLifeYears,
                        yearDepreciation: yearDepreciation,
                        businessRatePercent: Int((asset.businessAllocationRate * 100).rounded()),
                        deductibleAmount: deductibleAmount,
                        yearEndBalance: max(0, asset.acquisitionAmount - postedAccumulated),
                        isPosted: postedDepreciationIsComplete(
                            asset: asset,
                            fiscalYear: fiscalYear,
                            yearDepreciation: yearDepreciation,
                            deductibleAmount: deductibleAmount
                        )
                    )
                }

                let projected = DepreciationService.annualAmount(for: asset, fiscalYear: fiscalYear)
                guard projected.full > 0 else { return nil }
                return KessanshoReport.DepreciationRow(
                    assetId: asset.syncId,
                    assetName: asset.assetName,
                    acquisitionYearMonth: ymFormatter.string(from: asset.acquisitionDate),
                    acquisitionAmount: asset.acquisitionAmount,
                    method: methodLabel(for: asset),
                    usefulLifeYears: asset.usefulLifeYears,
                    yearDepreciation: projected.full,
                    businessRatePercent: Int((asset.businessAllocationRate * 100).rounded()),
                    deductibleAmount: projected.deductible,
                    yearEndBalance: max(0, asset.acquisitionAmount - (asset.accumulatedDepreciation + projected.full)),
                    isPosted: false
                )
            }
    }

    private static func postedDepreciationEntries(
        for asset: FixedAsset,
        in entries: [JournalEntry]
    ) -> [JournalEntry] {
        entries.filter {
            $0.sourceTypeRaw == RecordSource.depreciation.rawValue
                && $0.relatedFixedAssetId == asset.syncId
        }
    }

    private static func postedDepreciationIsComplete(
        asset: FixedAsset,
        fiscalYear: Int,
        yearDepreciation: Int,
        deductibleAmount: Int
    ) -> Bool {
        guard yearDepreciation > 0 else { return false }
        let projected = DepreciationService.annualAmount(for: asset, fiscalYear: fiscalYear)
        if projected.full > 0, yearDepreciation == projected.full, deductibleAmount == projected.deductible {
            return true
        }

        // 計上後の資産状態（accumulatedDepreciation 反映済み）からは当年の予定額を
        // 再構成できないケースがある: 償却済み（projected.full == 0）と、最終年度の
        // 端数残（例: 100,000/3年 → 33,333×3 計上後に残存1円で projected.full == 1）。
        // その場合は計上済み合計の家事按分の整合のみ検証する。
        let expectedDeductible = Int((Double(yearDepreciation) * asset.businessAllocationRate).rounded(.down))
        return deductibleAmount == expectedDeductible
    }

    private static func rentRows(entries: [JournalEntry]) -> [KessanshoReport.RentRow] {
        var totalsByPayee: [String: (annual: Int, deductible: Int)] = [:]
        for entry in entries {
            let sign: Int
            if entry.debitAccountCode == AccountCode.rent {
                sign = 1
            } else if entry.creditAccountCode == AccountCode.rent {
                sign = -1
            } else {
                continue
            }

            let payee = entry.counterpartyName
            var totals = totalsByPayee[payee] ?? (0, 0)
            totals.annual += sign * (entry.originalAmountIncludingTax ?? entry.amountIncludingTax)
            totals.deductible += sign * entry.amountIncludingTax
            totalsByPayee[payee] = totals
        }

        return totalsByPayee
            .filter { $0.value.annual != 0 || $0.value.deductible != 0 }
            .sorted { $0.key < $1.key }
            .map {
                KessanshoReport.RentRow(
                    payee: $0.key,
                    annualRent: $0.value.annual,
                    deductibleAmount: $0.value.deductible
                )
            }
    }
}
