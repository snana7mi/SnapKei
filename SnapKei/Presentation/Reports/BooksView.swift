import SwiftData
import SwiftUI

public struct BooksView: View {
    @Query(sort: \JournalEntry.fiscalYear) private var allEntries: [JournalEntry]
    @State private var selectedYear = Calendar(identifier: .gregorian).component(.year, from: Date())

    public init() {}

    private var availableYears: [Int] {
        let current = Calendar(identifier: .gregorian).component(.year, from: Date())
        // Offer every year that has entries, plus the current and prior calendar years
        // (during the Feb–Mar filing season the user works on the prior year).
        let years = Set(allEntries.map(\.fiscalYear) + [current, current - 1])
        return years.sorted(by: >)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("対象年度", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(verbatim: "\(year) 年").tag(year)
                        }
                    }
                }
                Section("帳簿") {
                    NavigationLink("仕訳帳") { JournalBookView(fiscalYear: selectedYear) }
                    NavigationLink("総勘定元帳") { GeneralLedgerView(fiscalYear: selectedYear) }
                    NavigationLink("残高試算表") { TrialBalanceView(fiscalYear: selectedYear) }
                }
                Section("決算書") {
                    NavigationLink("損益計算書") { ProfitAndLossReportView(fiscalYear: selectedYear) }
                    NavigationLink("貸借対照表") { BalanceSheetReportView(fiscalYear: selectedYear) }
                    NavigationLink("年次締め") { ClosingView(fiscalYear: selectedYear) }
                }
                Section {
                    Text("帳簿・決算書は記帳補助のための表示です。55万/65万円控除の適用や税務判断を保証するものではありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("帳簿")
        }
    }
}

private struct JournalBookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.entryNumber) private var entries: [JournalEntry]
    let fiscalYear: Int

    private var yearEntries: [JournalEntry] {
        entries.filter { $0.fiscalYear == fiscalYear && !$0.isVoided }
    }

    var body: some View {
        List(yearEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(entry.entryNumber) \(entry.transactionDescription)")
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.debitAccountCode) / \(entry.creditAccountCode)  ¥\(entry.amountIncludingTax)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "仕訳帳 \(fiscalYear)年"))
        .toolbar {
            Button { exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("仕訳帳 CSV を共有")
        }
    }

    private func exportCSV() {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let nameByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.nameJa) })
        let data = CSVExportService.export(yearEntries) { code in nameByCode[code] ?? code }
        share(data, fileName: "snapkei_journal_\(fiscalYear).csv")
    }
}

private struct GeneralLedgerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \JournalEntry.transactionDate) private var entries: [JournalEntry]
    @State private var accountCode = AccountCode.cash
    let fiscalYear: Int

    var body: some View {
        List {
            Picker("勘定科目", selection: $accountCode) {
                ForEach(accounts, id: \.code) { account in
                    Text("\(account.code) \(account.nameJa)").tag(account.code)
                }
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(line.entryNumber) \(line.summary)")
                    Text("借方 \(line.debit) / 貸方 \(line.credit) / 残高 \(line.runningBalance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "総勘定元帳 \(fiscalYear)年"))
        .toolbar {
            Button { share(CSVExportService.exportLedgerLines(lines), fileName: "snapkei_ledger_\(accountCode)_\(fiscalYear).csv") } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("総勘定元帳 CSV を共有")
        }
        .onAppear {
            if !accounts.contains(where: { $0.code == accountCode }), let first = accounts.first {
                accountCode = first.code
            }
        }
    }

    private var lines: [LedgerLine] {
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        return LedgerService.ledgerLines(accountCode: accountCode, fiscalYear: fiscalYear, openingBalance: openings[accountCode] ?? 0, entries: entries)
    }
}

private struct TrialBalanceView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [JournalEntry]
    @Query private var accounts: [Account]
    let fiscalYear: Int

    var body: some View {
        let report = makeReport()
        List {
            ForEach(report.rows) { row in
                VStack(alignment: .leading) {
                    Text("\(row.accountCode) \(row.accountName)")
                    Text("借方 \(row.debitTotal) / 貸方 \(row.creditTotal) / 期末 \(row.closingBalance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text(report.isBalanced ? "貸借一致" : "不一致: 期首差額 \(report.openingImbalance)")
                    .foregroundStyle(report.isBalanced ? .green : .red)
            }
        }
        .navigationTitle(Text(verbatim: "残高試算表 \(fiscalYear)年"))
        .toolbar {
            Button { share(CSVExportService.exportTrialBalance(report), fileName: "snapkei_trial_balance_\(fiscalYear).csv") } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("残高試算表 CSV を共有")
        }
    }

    private func makeReport() -> TrialBalanceReport {
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        return TrialBalanceService.report(fiscalYear: fiscalYear, entries: entries, openingBalances: openings, accounts: accounts)
    }
}

private struct ProfitAndLossReportView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [JournalEntry]
    @Query private var accounts: [Account]
    let fiscalYear: Int

    var body: some View {
        let summary = ProfitAndLossService.summary(entries: entries.filter { $0.fiscalYear == fiscalYear }, accounts: accounts)
        List {
            Section("売上") { Text("¥\(summary.revenueTotal)") }
            Section("経費") { Text("¥\(summary.expenseTotal)") }
            Section("所得金額") { Text("¥\(summary.netIncome)").font(.headline) }
        }
        .navigationTitle(Text(verbatim: "損益計算書 \(fiscalYear)年"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { share(CSVExportService.exportProfitAndLoss(summary), fileName: "snapkei_profit_loss_\(fiscalYear).csv") } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("損益計算書 CSV を共有")
                Button { exportPDF() } label: { Image(systemName: "doc.richtext") }
                    .accessibilityLabel("損益計算書 PDF を共有")
            }
        }
    }

    private func exportPDF() {
        if let data = try? PDFReportService.renderProfitAndLoss(fiscalYear: fiscalYear, context: context) {
            share(data, fileName: "snapkei_profit_loss_\(fiscalYear).pdf")
        }
    }
}

private struct BalanceSheetReportView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [JournalEntry]
    @Query private var accounts: [Account]
    let fiscalYear: Int

    var body: some View {
        let report = makeReport()
        List {
            Section("資産") {
                ForEach(report.assetLines) { Text("\($0.accountName)  ¥\($0.closing)") }
                Text("事業主貸  ¥\(report.ownerDrawClosing)")
                Text("資産合計  ¥\(report.assetTotal)").font(.headline)
            }
            Section("負債・純資産") {
                ForEach(report.liabilityLines) { Text("\($0.accountName)  ¥\($0.closing)") }
                Text("事業主借  ¥\(report.ownerLoanClosing)")
                Text("元入金  ¥\(report.capitalClosing)")
                if report.otherEquityClosing != 0 {
                    Text("その他純資産  ¥\(report.otherEquityClosing)")
                }
                Text("当期所得  ¥\(report.netIncome)")
                Text("合計  ¥\(report.liabilityEquityTotal)").font(.headline)
            }
        }
        .navigationTitle(Text(verbatim: "貸借対照表 \(fiscalYear)年"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { share(CSVExportService.exportBalanceSheet(report), fileName: "snapkei_balance_sheet_\(fiscalYear).csv") } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("貸借対照表 CSV を共有")
                Button { exportPDF() } label: { Image(systemName: "doc.richtext") }
                    .accessibilityLabel("貸借対照表 PDF を共有")
            }
        }
    }

    private func makeReport() -> BalanceSheetReport {
        let openings = (try? OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear)) ?? [:]
        return BalanceSheetService.report(fiscalYear: fiscalYear, entries: entries, openingBalances: openings, accounts: accounts)
    }

    private func exportPDF() {
        if let data = try? PDFReportService.renderBalanceSheet(fiscalYear: fiscalYear, context: context) {
            share(data, fileName: "snapkei_balance_sheet_\(fiscalYear).pdf")
        }
    }
}

private struct ClosingView: View {
    @Environment(\.modelContext) private var context
    @State private var status = ""
    @State private var reopenReason = ""
    let fiscalYear: Int

    var body: some View {
        Form {
            Section("年度") { Text(verbatim: "\(fiscalYear) 年") }
            Section {
                Button("減価償却を計上") { run { try service.runDepreciation(fiscalYear: fiscalYear) } }
                Button("年度を締める") { run { try service.close(fiscalYear: fiscalYear) } }
            }
            Section("再オープン") {
                TextField("理由", text: $reopenReason)
                Button("年度を再オープン", role: .destructive) {
                    run { try service.reopen(fiscalYear: fiscalYear, reason: reopenReason) }
                }
            }
            if !status.isEmpty { Section { Text(status).font(.caption) } }
        }
        .navigationTitle(Text(verbatim: "年次締め \(fiscalYear)年"))
    }

    private var service: YearEndClosingService {
        YearEndClosingService(context: context, deviceId: "local-device")
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            status = "完了しました"
        } catch RepositoryError.fiscalYearClosed(let year) {
            status = "\(year) 年度は締め済みです"
        } catch {
            status = "失敗しました: \(error)"
        }
    }
}

private func share(_ data: Data, fileName: String) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    try? data.write(to: url, options: [.atomic])
    SharePresenter.share(url: url)
}
