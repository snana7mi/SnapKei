import SwiftData
import SwiftUI
import UIKit

public struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var viewModel: ExpenseListViewModel?
    @State private var showFilter = false
    @State private var showManualEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var voidErrorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    listContent(viewModel)
                } else {
                    ProgressView().task { initializeViewModel() }
                }
            }
            .navigationTitle("一覧")
        }
    }

    private func listContent(_ viewModel: ExpenseListViewModel) -> some View {
        List {
            ForEach(viewModel.entries) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.counterpartyName).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("¥\(entry.amountIncludingTax)").font(.subheadline.monospacedDigit())
                        }
                        HStack {
                            Text(entry.transactionDate, format: .dateTime.year().month().day())
                            Text(entry.transactionDescription).lineLimit(1)
                            Spacer()
                            if entry.invoiceQualified { badge("適格", color: .green) }
                            if entry.isLateEntry { badge("遅延", color: .orange) }
                            if entry.isVoided { badge("取消", color: .red) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) {
                    if !entry.isVoided {
                        Button(role: .destructive) { voidEntry(entry, viewModel: viewModel) } label: {
                            Label("取消", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .searchable(text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0; viewModel.refresh() }))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showManualEntry = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("手動入力")
                Button { showFilter = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("フィルタ")
                Button { exportCSV(viewModel: viewModel) } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("CSV を共有")
            }
            ToolbarItem(placement: .bottomBar) {
                let typeByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.accountType) })
                let totals = viewModel.totals(accountTypes: { typeByCode[$0] })
                Text("支出 ¥\(totals.expense)　収入 ¥\(totals.income)")
            }
        }
        .sheet(isPresented: $showFilter) {
            ExpenseFilterSheet(criteria: Binding(get: { viewModel.criteria }, set: { viewModel.criteria = $0; viewModel.refresh() }))
        }
        .sheet(isPresented: $showManualEntry, onDismiss: { viewModel.refresh() }) {
            ManualEntryView()
        }
        .sheet(item: $selectedEntry, onDismiss: { viewModel.refresh() }) { entry in
            EntryDetailView(entry: entry)
        }
        .alert(
            "取消できません",
            isPresented: Binding(get: { voidErrorMessage != nil }, set: { if !$0 { voidErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voidErrorMessage ?? "")
        }
        .task { viewModel.refresh() }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func initializeViewModel() {
        viewModel = ExpenseListViewModel(repository: SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current))
    }

    private func voidEntry(_ entry: JournalEntry, viewModel: ExpenseListViewModel) {
        // 資産連動の仕訳（取得・処分・償却）を単独で取消すると固定資産台帳と
        // 帳簿が乖離する。資産側の削除/処分から操作させる。
        guard entry.relatedFixedAssetId == nil else {
            voidErrorMessage = "固定資産に関連する仕訳です。設定の固定資産台帳から資産の削除・処分を行ってください。"
            return
        }
        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.void(entry, reason: "ユーザー操作")
        } catch {
            voidErrorMessage = error.localizedDescription
        }
        viewModel.refresh()
    }

    private func exportCSV(viewModel: ExpenseListViewModel) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let nameByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.nameJa) })
        let data = CSVExportService.export(viewModel.entries) { code in nameByCode[code] ?? code }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapkei_export.csv")
        try? data.write(to: url, options: [.atomic])
        SharePresenter.share(url: url)
    }
}
