import Foundation
import Testing
@testable import SnapKei

@Suite("KessanshoService")
struct KessanshoServiceTests {
    private func date(_ s: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter.date(from: s)!
    }

    private func account(_ code: String, _ name: String, _ type: AccountType) -> Account {
        Account(code: code, nameJa: name, nameZh: name, accountType: type)
    }

    private var accounts: [Account] {
        [
            account("1110", "現金", .asset),
            account("1610", "工具器具備品", .asset),
            account("1710", "減価償却累計額", .asset),
            account("3110", "元入金", .equity),
            account("3210", "事業主借", .equity),
            account("3220", "事業主貸", .equity),
            account("4110", "売上高", .revenue),
            account("5110", "通信費", .expense),
            account("5180", "地代家賃", .expense),
            account("5230", "減価償却費", .expense),
        ]
    }

    private func entry(
        _ debit: String,
        _ credit: String,
        _ amount: Int,
        day: String,
        fiscalYear: Int = 2026,
        voided: Bool = false,
        counterparty: String = "取引先",
        original: Int? = nil,
        relatedAssetId: UUID? = nil,
        sourceType: RecordSource = .manual
    ) -> JournalEntry {
        JournalEntry(
            entryNumber: 1,
            fiscalYear: fiscalYear,
            transactionDate: date(day),
            debitAccountCode: debit,
            creditAccountCode: credit,
            amountIncludingTax: amount,
            amountExcludingTax: amount,
            consumptionTax: 0,
            taxCategory: .outOfScope,
            priceEntryMode: .taxIncluded,
            paymentMethod: .other,
            counterpartyName: counterparty,
            transactionDescription: "test",
            originalAmountIncludingTax: original,
            relatedFixedAssetId: relatedAssetId,
            sourceType: sourceType,
            isVoided: voided
        )
    }

    private func pcAsset(
        accumulatedDepreciation: Int = 0,
        bookValue: Int? = nil,
        syncId: UUID = UUID()
    ) -> FixedAsset {
        FixedAsset(
            assetName: "PC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2026-07-01"),
            serviceStartDate: date("2026-07-01"),
            acquisitionAmount: 240_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            businessAllocationRate: 0.8,
            accumulatedDepreciation: accumulatedDepreciation,
            bookValue: bookValue,
            syncId: syncId
        )
    }

    private func depreciationEntries(assetId: UUID, fiscalYear: Int = 2026) -> [JournalEntry] {
        [
            entry(
                AccountCode.depreciationExpense,
                AccountCode.accumulatedDepreciation,
                24_000,
                day: "\(fiscalYear)-12-31",
                fiscalYear: fiscalYear,
                relatedAssetId: assetId,
                sourceType: .depreciation
            ),
            entry(
                AccountCode.ownerDraw,
                AccountCode.accumulatedDepreciation,
                6_000,
                day: "\(fiscalYear)-12-31",
                fiscalYear: fiscalYear,
                relatedAssetId: assetId,
                sourceType: .depreciation
            ),
        ]
    }

    private var workedExampleAssetId: UUID { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }

    private func build(
        entries: [JournalEntry],
        assets: [FixedAsset] = [],
        openingBalances: [String: Int] = [:],
        maxBlueDeduction: Int = 650_000
    ) -> KessanshoReport {
        KessanshoService.build(
            fiscalYear: 2026,
            header: KessanshoReport.Header(fiscalYear: 2026, ownerName: "山田太郎", businessName: "ヤマダ商店"),
            entries: entries,
            accounts: accounts,
            assets: assets,
            openingBalances: openingBalances,
            maxBlueDeduction: maxBlueDeduction
        )
    }

    private func workedExample() -> (entries: [JournalEntry], asset: FixedAsset, openings: [String: Int]) {
        let assetId = workedExampleAssetId
        let asset = pcAsset(accumulatedDepreciation: 30_000, bookValue: 210_000, syncId: assetId)
        let entries = [
            entry("1110", "4110", 110_000, day: "2026-03-10"),
            entry("5110", "3210", 11_000, day: "2026-02-05"),
            entry("1610", "3210", 240_000, day: "2026-07-01"),
        ] + depreciationEntries(assetId: assetId)
        return (entries, asset, ["1110": 100_000, "3110": -100_000])
    }

    @Test func profitAndLoss_workedExample() {
        let sample = workedExample()

        let report = build(entries: sample.entries, assets: [sample.asset], openingBalances: sample.openings)
        let profitAndLoss = report.profitAndLoss

        #expect(profitAndLoss.salesRevenue == 110_000)
        #expect(profitAndLoss.costOfGoodsSold == 0)
        #expect(profitAndLoss.grossProfit == 110_000)
        #expect(profitAndLoss.expenseRows == [
            KessanshoExpenseLine(label: "通信費", amount: 11_000),
            KessanshoExpenseLine(label: "減価償却費", amount: 24_000),
        ])
        #expect(profitAndLoss.expenseTotal == 35_000)
        #expect(profitAndLoss.netBeforeDeduction == 75_000)
        #expect(profitAndLoss.blueDeduction == 75_000)
        #expect(profitAndLoss.income == 0)
    }

    @Test func blueDeduction_zeroRoute_givesFullIncome() {
        let sample = workedExample()

        let profitAndLoss = build(
            entries: sample.entries,
            assets: [sample.asset],
            openingBalances: sample.openings,
            maxBlueDeduction: 0
        ).profitAndLoss

        #expect(profitAndLoss.blueDeduction == 0)
        #expect(profitAndLoss.income == 75_000)
    }

    @Test func voidedEntriesExcludedEverywhere() {
        let entries = [
            entry("1110", "4110", 110_000, day: "2026-03-10", voided: true),
            entry("5110", "3210", 11_000, day: "2026-02-05", voided: true),
            entry(AccountCode.rent, "3210", 30_000, day: "2026-04-01", voided: true),
        ]

        let report = build(entries: entries, maxBlueDeduction: 650_000)

        #expect(report.profitAndLoss.salesRevenue == 0)
        #expect(report.profitAndLoss.expenseTotal == 0)
        #expect(report.profitAndLoss.blueDeduction == 0)
        #expect(report.monthly.reduce(0) { $0 + $1.sales } == 0)
        #expect(report.depreciation.isEmpty)
        #expect(report.rentDetails.isEmpty)
        #expect(report.balanceSheet.assetTotal == 0)
    }

    @Test func monthlyRevenue_usesProfitAndLossSignRules() {
        let report = build(entries: [
            entry("1110", "4110", 110_000, day: "2026-03-10"),
            entry("4110", "1110", 20_000, day: "2026-03-20"),
        ], maxBlueDeduction: 0)

        #expect(report.profitAndLoss.salesRevenue == 90_000)
        #expect(report.monthly[2].sales == 90_000)
        #expect(report.monthly.reduce(0) { $0 + $1.sales } == report.profitAndLoss.salesRevenue)
    }

    @Test func depreciation_prefersPostedEntriesAndAvoidsDoubleCounting() {
        let assetId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let asset = pcAsset(accumulatedDepreciation: 30_000, bookValue: 210_000, syncId: assetId)

        let rows = build(entries: depreciationEntries(assetId: assetId), assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].assetId == assetId)
        #expect(rows[0].yearDepreciation == 30_000)
        #expect(rows[0].deductibleAmount == 24_000)
        #expect(rows[0].businessRatePercent == 80)
        #expect(rows[0].method == "定額法")
        #expect(rows[0].usefulLifeYears == 4)
        #expect(rows[0].acquisitionYearMonth == "2026-07")
        #expect(rows[0].yearEndBalance == 210_000)
        #expect(rows[0].isPosted)
    }

    @Test func depreciation_partialPostedEntriesAreNotMarkedPosted() {
        let assetId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let asset = pcAsset(accumulatedDepreciation: 30_000, bookValue: 210_000, syncId: assetId)
        let partialEntries = [
            entry(
                AccountCode.ownerDraw,
                AccountCode.accumulatedDepreciation,
                6_000,
                day: "2026-12-31",
                relatedAssetId: assetId,
                sourceType: .depreciation
            ),
        ]

        let rows = build(entries: partialEntries, assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].yearDepreciation == 6_000)
        #expect(rows[0].deductibleAmount == 0)
        #expect(!rows[0].isPosted)
    }

    @Test func depreciation_finalYearRoundingResidue_isStillMarkedPosted() {
        // 取得 100,000 / 3年 / 事業割合100%: 33,333×3 計上後に端数1円が残る。
        // 計上後の資産状態から当年予定額を再構成すると一致しないが、
        // 正しく計上済みの年を「未計上見込」と誤警告してはいけない。
        let assetId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let asset = FixedAsset(
            assetName: "プリンタ",
            assetCategoryCode: "OTHER",
            acquisitionDate: date("2024-01-01"),
            serviceStartDate: date("2024-01-01"),
            acquisitionAmount: 100_000,
            usefulLifeYears: 3,
            treatment: .normalDepreciation,
            accumulatedDepreciation: 99_999,
            bookValue: 1,
            syncId: assetId
        )
        let posted = entry(
            AccountCode.depreciationExpense,
            AccountCode.accumulatedDepreciation,
            33_333,
            day: "2026-12-31",
            relatedAssetId: assetId,
            sourceType: .depreciation
        )

        let rows = build(entries: [posted], assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].yearDepreciation == 33_333)
        #expect(rows[0].isPosted)
    }

    @Test func depreciation_carriedOverAsset_yearEndBalanceIncludesCarriedBase() {
        // 引継ぎ資産（仕訳なしの既存償却累計 300,000）に最終年 100,000 を計上した後、
        // 期末残高は 0 になるべき（計上済み仕訳だけから計算すると 300,000 と過大表示）。
        let assetId = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let asset = FixedAsset(
            assetName: "引継ぎPC",
            assetCategoryCode: "PC",
            acquisitionDate: date("2023-01-01"),
            serviceStartDate: date("2023-01-01"),
            acquisitionAmount: 400_000,
            usefulLifeYears: 4,
            treatment: .normalDepreciation,
            accumulatedDepreciation: 400_000,
            bookValue: 0,
            syncId: assetId
        )
        let posted = entry(
            AccountCode.depreciationExpense,
            AccountCode.accumulatedDepreciation,
            100_000,
            day: "2026-12-31",
            relatedAssetId: assetId,
            sourceType: .depreciation
        )

        let rows = build(entries: [posted], assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].yearDepreciation == 100_000)
        #expect(rows[0].yearEndBalance == 0)
    }

    @Test func depreciation_lumpSumAsset_isLabeledAsLumpSum() {
        let assetId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let asset = FixedAsset(
            assetName: "事務机",
            assetCategoryCode: "FURNITURE",
            acquisitionDate: date("2026-05-01"),
            serviceStartDate: date("2026-05-01"),
            acquisitionAmount: 150_000,
            usefulLifeYears: 8,
            treatment: .lumpSumDepreciation,
            syncId: assetId
        )

        let rows = build(entries: [], assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].method == "一括償却")
        #expect(rows[0].yearDepreciation == 50_000)
    }

    @Test func depreciation_projectedWhenNotPosted() {
        let assetId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let asset = pcAsset(syncId: assetId)

        let rows = build(entries: [], assets: [asset]).depreciation

        #expect(rows.count == 1)
        #expect(rows[0].yearDepreciation == 30_000)
        #expect(rows[0].deductibleAmount == 24_000)
        #expect(rows[0].yearEndBalance == 210_000)
        #expect(!rows[0].isPosted)
    }

    @Test func rentDetails_groupedByPayee_usesDebitCreditSignsAndOriginalAmount() {
        let report = build(entries: [
            entry(AccountCode.rent, "3210", 30_000, day: "2026-01-31", counterparty: "大家A", original: 60_000),
            entry(AccountCode.rent, "3210", 50_000, day: "2026-02-28", counterparty: "大家B"),
            entry("3210", AccountCode.rent, 10_000, day: "2026-03-31", counterparty: "大家A", original: 20_000),
        ])

        #expect(report.rentDetails == [
            KessanshoReport.RentRow(payee: "大家A", annualRent: 40_000, deductibleAmount: 20_000),
            KessanshoReport.RentRow(payee: "大家B", annualRent: 50_000, deductibleAmount: 50_000),
        ])
    }

    @Test func rentDetails_emptyWhenNoRent() {
        #expect(build(entries: [entry("5110", "3210", 11_000, day: "2026-02-05")]).rentDetails.isEmpty)
    }

    @Test func balanceSheet_balances_workedExample() {
        let sample = workedExample()

        let balanceSheet = build(
            entries: sample.entries,
            assets: [sample.asset],
            openingBalances: sample.openings,
            maxBlueDeduction: 0
        ).balanceSheet

        #expect(balanceSheet.isBalanced)
        #expect(balanceSheet.assetTotal == 426_000)
        #expect(balanceSheet.liabilityEquityTotal == 426_000)
    }
}
