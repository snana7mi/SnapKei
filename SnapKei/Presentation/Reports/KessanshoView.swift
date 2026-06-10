import SwiftData
import SwiftUI

struct KessanshoView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [JournalEntry]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(filter: #Predicate<FixedAsset> { $0.deletedAt == nil }) private var assets: [FixedAsset]

    @State private var confirmedDeduction: Int?
    @State private var showExportConfirmation = false

    let fiscalYear: Int

    var body: some View {
        let state = reportState()
        let report = state.report
        List {
            checkSection(state)
            if state.entryCount == 0 {
                Section {
                    ContentUnavailableView {
                        Label("対象年度の仕訳がありません", systemImage: "tray")
                    } description: {
                        Text("\(fiscalYear)年の仕訳を登録すると、損益計算書・貸借対照表のサマリーがここに表示されます。")
                    }
                }
            } else {
                deductionSection(estimatedDeduction: state.estimatedDeduction)
                profitAndLossSection(report.profitAndLoss)
                monthlySection(report.monthly)
                depreciationSection(report.depreciation)
                rentSection(report.rentDetails)
                balanceSheetSection(report.balanceSheet)
            }
            Section {
                Text("確認用サマリーです。国税庁の公式様式そのものではありません。住所や一部の内訳など、SnapKei が保持していない項目は手動で確認してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "青色申告決算書 \(fiscalYear)年"))
        .toolbar {
            Button {
                if state.warnings.isEmpty {
                    exportPDF(report)
                } else {
                    showExportConfirmation = true
                }
            } label: {
                Image(systemName: "doc.richtext")
            }
            .accessibilityLabel("決算書 PDF を共有")
            .accessibilityHint("確認用サマリー PDF を生成して共有シートを開きます")
        }
        .confirmationDialog("確認事項があります", isPresented: $showExportConfirmation, titleVisibility: .visible) {
            // body 評価時の report をそのまま使う（再計算すると確認した警告と
            // 出力される PDF の内容がずれうる）。
            Button("PDF を生成") { exportPDF(report) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(state.warnings.joined(separator: "\n"))
        }
        .onAppear {
            if confirmedDeduction == nil {
                confirmedDeduction = state.estimatedDeduction
            }
        }
    }

    private func reportState() -> ReportState {
        let yearEntries = entries.filter { $0.fiscalYear == fiscalYear && !$0.isVoided }
        let settings = AppSettings.load()
        // 控除ルートの推定は帳簿全体の状態で判断する（HomeViewModel と同じ全年度・
        // 取消除外基準）。選択中の年度に仕訳が無いだけで推定 ¥0 にしない。
        // 監査ログは存在確認だけなので全件 @Query ではなく fetchCount を使う。
        let hasAuditLog = ((try? context.fetchCount(FetchDescriptor<SystemActivityLog>())) ?? 0) > 0
        let estimatedDeduction = ControlRouteStatus.load(
            hasEntries: entries.contains { !$0.isVoided },
            hasAuditLog: hasAuditLog
        ).estimatedDeduction
        let openingResult = Result { try OpeningBalanceStore(context: context).balances(fiscalYear: fiscalYear) }
        let openings = (try? openingResult.get()) ?? [:]
        let report = KessanshoService.build(
            fiscalYear: fiscalYear,
            header: KessanshoReport.Header(
                fiscalYear: fiscalYear,
                ownerName: settings.ownerName,
                businessName: settings.businessName
            ),
            entries: entries,
            accounts: accounts,
            assets: assets,
            openingBalances: openings,
            maxBlueDeduction: confirmedDeduction ?? estimatedDeduction
        )
        return ReportState(
            report: report,
            entryCount: yearEntries.count,
            estimatedDeduction: estimatedDeduction,
            ownerNameMissing: settings.ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            businessNameMissing: settings.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            openingBalanceLoadFailed: openingResult.isFailure
        )
    }

    private func checkSection(_ state: ReportState) -> some View {
        Section("申告前チェック") {
            checkRow("年度", "\(fiscalYear) 年")
            checkRow("氏名", state.ownerNameMissing ? "未設定" : "設定済", warning: state.ownerNameMissing)
            checkRow("屋号", state.businessNameMissing ? "未設定" : "設定済", warning: state.businessNameMissing)
            checkRow("仕訳件数", "\(state.entryCount) 件", warning: state.entryCount == 0)
            checkRow("青色申告特別控除額", yen(state.report.profitAndLoss.blueDeduction))
            checkRow(
                "減価償却",
                state.hasProjectedDepreciation ? "未計上見込あり" : "計上済",
                warning: state.hasProjectedDepreciation
            )
            checkRow(
                "貸借",
                state.report.balanceSheet.isBalanced ? "一致" : "不一致",
                warning: !state.report.balanceSheet.isBalanced
            )
            if state.openingBalanceLoadFailed {
                Label("期首残高を読み込めませんでした。貸借対照表を確認してください。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if state.warnings.isEmpty {
                Label("PDF 出力前の主要チェックに問題はありません。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func deductionSection(estimatedDeduction: Int) -> some View {
        Section {
            Picker("控除額", selection: deductionBinding(estimatedDeduction: estimatedDeduction)) {
                Text("0 円").tag(0)
                Text("10 万円").tag(100_000)
                Text("55 万円").tag(550_000)
                Text("65 万円").tag(650_000)
            }
            Text("推定: \(yen(estimatedDeduction))。控除額は申告条件を確認して選択してください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("青色申告特別控除")
        }
    }

    private func profitAndLossSection(_ profitAndLoss: KessanshoReport.ProfitAndLoss) -> some View {
        Section("損益計算書") {
            amountRow("売上(収入)金額", profitAndLoss.salesRevenue)
            amountRow("売上原価", profitAndLoss.costOfGoodsSold)
            amountRow("差引金額", profitAndLoss.grossProfit)
            ForEach(profitAndLoss.expenseRows) { line in
                amountRow(line.label, line.amount)
            }
            amountRow("経費計", profitAndLoss.expenseTotal, bold: true)
            amountRow("青色申告特別控除前の所得金額", profitAndLoss.netBeforeDeduction)
            amountRow("青色申告特別控除額", profitAndLoss.blueDeduction)
            amountRow("所得金額", profitAndLoss.income, bold: true)
        }
    }

    private func monthlySection(_ monthly: [KessanshoReport.MonthlyRow]) -> some View {
        Section("月別売上(収入)金額") {
            ForEach(monthly) { month in
                amountRow("\(month.month) 月", month.sales)
            }
        }
    }

    private func depreciationSection(_ rows: [KessanshoReport.DepreciationRow]) -> some View {
        Section("減価償却費の計算") {
            if rows.isEmpty {
                Text("対象資産なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(row.assetName) (\(row.acquisitionYearMonth) / \(row.method) / \(row.usefulLifeYears)年)")
                            .font(.subheadline)
                        Spacer()
                        Text(row.isPosted ? "計上済" : "未計上見込")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.isPosted ? .green : .orange)
                    }
                    Text("取得 \(yen(row.acquisitionAmount)) / 本年償却 \(yen(row.yearDepreciation)) / 事業割合 \(row.businessRatePercent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("必要経費算入 \(yen(row.deductibleAmount)) / 期末残高 \(yen(row.yearEndBalance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func rentSection(_ rows: [KessanshoReport.RentRow]) -> some View {
        if !rows.isEmpty {
            Section("地代家賃の内訳") {
                ForEach(rows) { row in
                    amountRow("\(row.payee)（経費算入 \(yen(row.deductibleAmount))）", row.annualRent)
                }
            }
        }
    }

    private func balanceSheetSection(_ balanceSheet: BalanceSheetReport) -> some View {
        Section("貸借対照表") {
            amountRow("資産合計", balanceSheet.assetTotal, bold: true)
            amountRow("負債・資本合計", balanceSheet.liabilityEquityTotal, bold: true)
            Label(
                balanceSheet.isBalanced ? "貸借一致" : "貸借不一致",
                systemImage: balanceSheet.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(balanceSheet.isBalanced ? .green : .red)
        }
    }

    private func checkRow(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(warning ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func amountRow(_ label: String, _ amount: Int, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(bold ? .subheadline.weight(.bold) : .subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(yen(amount))
                .font((bold ? Font.subheadline.weight(.bold) : .subheadline).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func deductionBinding(estimatedDeduction: Int) -> Binding<Int> {
        Binding(
            get: { confirmedDeduction ?? estimatedDeduction },
            set: { confirmedDeduction = $0 }
        )
    }

    private func exportPDF(_ report: KessanshoReport) {
        let data = PDFReportService.renderKessansho(report: report)
        Task {
            await SharePresenter.share(data: data, filename: "青色申告決算書_\(fiscalYear).pdf")
        }
    }

    private func yen(_ amount: Int) -> String {
        YenFormat.string(amount)
    }
}

private struct ReportState {
    let report: KessanshoReport
    let entryCount: Int
    let estimatedDeduction: Int
    let ownerNameMissing: Bool
    let businessNameMissing: Bool
    let openingBalanceLoadFailed: Bool

    var hasProjectedDepreciation: Bool {
        report.hasProjectedDepreciation
    }

    var warnings: [String] {
        var result: [String] = []
        if ownerNameMissing { result.append("氏名が未設定です。") }
        if businessNameMissing { result.append("屋号が未設定です。") }
        if entryCount == 0 { result.append("対象年度の仕訳がありません。") }
        if openingBalanceLoadFailed { result.append("期首残高を読み込めませんでした。") }
        if hasProjectedDepreciation { result.append("減価償却に未計上見込の行があります。") }
        if !report.balanceSheet.isBalanced { result.append("貸借対照表が一致していません。") }
        return result
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { true } else { false }
    }
}
