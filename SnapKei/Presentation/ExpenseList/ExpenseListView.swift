import SwiftData
import SwiftUI
import UIKit

public struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel: ExpenseListViewModel?
    @State private var showFilter = false

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
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { voidEntry(entry, viewModel: viewModel) } label: {
                        Label("取消", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .searchable(text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0; viewModel.refresh() }))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showFilter = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                Button { exportCSV(viewModel: viewModel) } label: { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .bottomBar) {
                Text("合計 ¥\(viewModel.totalAmount)")
            }
        }
        .sheet(isPresented: $showFilter) {
            ExpenseFilterSheet(criteria: Binding(get: { viewModel.criteria }, set: { viewModel.criteria = $0; viewModel.refresh() }))
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
        viewModel = ExpenseListViewModel(repository: SwiftDataExpenseRepository(context: context, deviceId: deviceID()))
    }

    private func voidEntry(_ entry: JournalEntry, viewModel: ExpenseListViewModel) {
        let repository = SwiftDataExpenseRepository(context: context, deviceId: deviceID())
        try? repository.void(entry, reason: "ユーザー操作")
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

    private func deviceID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
