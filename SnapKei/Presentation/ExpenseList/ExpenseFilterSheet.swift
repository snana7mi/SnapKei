import SwiftData
import SwiftUI

public struct ExpenseFilterSheet: View {
    @Binding private var criteria: ExpenseSearchCriteria
    @Query(sort: \Account.code) private var accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    @State private var useDateRange = false
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var useAmountRange = false
    @State private var amountMin = ""
    @State private var amountMax = ""
    @State private var selectedAccounts: Set<String> = []
    @State private var qualifiedOnly = false
    @State private var lateEntryOnly = false
    @State private var includeVoided = false

    public init(criteria: Binding<ExpenseSearchCriteria>) {
        self._criteria = criteria
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("期間") {
                    Toggle("期間を指定", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("開始", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("終了", selection: $dateTo, displayedComponents: .date)
                    }
                }
                Section("金額") {
                    Toggle("金額範囲", isOn: $useAmountRange)
                    if useAmountRange {
                        TextField("下限", text: $amountMin).keyboardType(.numberPad)
                        TextField("上限", text: $amountMax).keyboardType(.numberPad)
                    }
                }
                Section("勘定科目") {
                    ForEach(accounts.filter { $0.accountType == .expense }) { account in
                        Toggle(isOn: Binding(
                            get: { selectedAccounts.contains(account.code) },
                            set: { isOn in
                                if isOn { selectedAccounts.insert(account.code) } else { selectedAccounts.remove(account.code) }
                            }
                        )) {
                            Text("\(account.code) \(account.nameJa)")
                        }
                    }
                }
                Section("その他") {
                    Toggle("適格のみ", isOn: $qualifiedOnly)
                    Toggle("遅延入力のみ", isOn: $lateEntryOnly)
                    Toggle("取消を含む", isOn: $includeVoided)
                }
            }
            .navigationTitle("フィルタ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        criteria = buildCriteria()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func buildCriteria() -> ExpenseSearchCriteria {
        ExpenseSearchCriteria(
            dateFrom: useDateRange ? dateFrom : nil,
            dateTo: useDateRange ? dateTo : nil,
            debitAccountCodes: selectedAccounts.isEmpty ? nil : Array(selectedAccounts),
            amountMin: useAmountRange ? Int(amountMin) : nil,
            amountMax: useAmountRange ? Int(amountMax) : nil,
            qualifiedOnly: qualifiedOnly ? true : nil,
            lateEntryOnly: lateEntryOnly ? true : nil,
            includeVoided: includeVoided
        )
    }
}
