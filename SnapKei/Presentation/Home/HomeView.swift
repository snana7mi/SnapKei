import Charts
import SwiftData
import SwiftUI
import UIKit

public struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var summary: HomeViewModel.MonthlySummary?
    @State private var byAccount: [HomeViewModel.AccountTotal] = []
    @State private var overdue: [JournalEntry] = []
    @State private var recent: [JournalEntry] = []
    @State private var controlRoute: ControlRouteStatus?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("今月の概要") {
                    if let summary {
                        HStack { Text("件数"); Spacer(); Text("\(summary.entryCount) 件") }
                        HStack { Text("税込合計"); Spacer(); Text("¥\(summary.totalIncludingTax)") }
                        HStack { Text("消費税"); Spacer(); Text("¥\(summary.totalConsumptionTax)") }
                    } else {
                        Text("計算中...").foregroundStyle(.secondary)
                    }
                }

                Section("控除路線") {
                    if let controlRoute {
                        routeRow("複式簿記での記帳", checked: controlRoute.doubleEntryBookkeeping)
                        routeRow("訂正・削除履歴", checked: controlRoute.amendmentHistoryEnabled)
                        routeRow("検索機能", checked: controlRoute.searchableLedger)
                        routeRow("優良電子帳簿の届出書", checked: controlRoute.hasFiledOptimalBookNotification)
                        routeRow("e-Tax で申告予定", checked: controlRoute.willUseEtax)
                        HStack {
                            Text("見込控除額").font(.headline)
                            Spacer()
                            Text("¥\(controlRoute.estimatedDeduction)")
                                .font(.title3.monospacedDigit().weight(.bold))
                                .foregroundStyle(controlRoute.estimatedDeduction >= 650_000 ? .green : .primary)
                        }
                    }
                }

                if !overdue.isEmpty {
                    Section("入力期限警告") {
                        ForEach(overdue) { entry in
                            entryRow(entry)
                        }
                    }
                }

                if !byAccount.isEmpty {
                    Section("科目別（今月）") {
                        Chart(byAccount) { item in
                            SectorMark(angle: .value("金額", item.amount), innerRadius: .ratio(0.5))
                                .foregroundStyle(by: .value("科目", item.name))
                        }
                        .frame(height: 220)
                    }
                }

                Section("直近の取引") {
                    if recent.isEmpty {
                        Text("まだ取引がありません").foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { entry in entryRow(entry) }
                    }
                }

                Section("レポート") {
                    Button("損益計算書 PDF を生成") {
                        Task { await generatePnL() }
                    }
                }
            }
            .navigationTitle("ホーム")
            .task { await refresh() }
        }
    }

    private func routeRow(_ text: String, checked: Bool) -> some View {
        Label(text, systemImage: checked ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(checked ? .green : .secondary)
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.counterpartyName).font(.subheadline.weight(.semibold))
            Text("\(entry.transactionDescription) - ¥\(entry.amountIncludingTax)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        do {
            let viewModel = HomeViewModel(repository: SwiftDataExpenseRepository(context: context, deviceId: deviceID()))
            summary = try viewModel.monthlySummary(year: year, month: month)
            byAccount = try viewModel.byDebitAccount(year: year, month: month) { code in
                accounts.first(where: { $0.code == code })?.nameJa ?? code
            }
            overdue = try viewModel.overdueEntries()
            recent = try viewModel.recentEntries()
            controlRoute = try viewModel.controlRouteStatus()
        } catch {
            print("[HomeView] refresh failed: \(error)")
        }
    }

    private func generatePnL() async {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        do {
            let data = try PDFReportService.renderProfitAndLoss(fiscalYear: year, context: context)
            await SharePresenter.share(data: data, filename: "損益計算書_\(year).pdf")
        } catch {
            print("[HomeView] PDF generation failed: \(error)")
        }
    }

    private func deviceID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}

@MainActor
enum SharePresenter {
    static func share(data: Data, filename: String) async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? data.write(to: url, options: [.atomic])
        share(url: url)
    }

    static func share(url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let presenter = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        if let view = presenter?.view {
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            activity.popoverPresentationController?.permittedArrowDirections = []
        }
        presenter?.present(activity, animated: true)
    }
}
