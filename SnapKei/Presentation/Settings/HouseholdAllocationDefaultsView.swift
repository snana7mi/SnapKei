import SwiftData
import SwiftUI

public struct HouseholdAllocationDefaultsView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Environment(\.modelContext) private var context

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text("勘定科目ごとに、業務として按分するデフォルト割合 (0〜100) を設定します。単票登録時にこの値が初期値として読み込まれ、その場で変更も可能です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            let candidates = accounts.filter { $0.accountType == .expense }
            if candidates.isEmpty {
                Section {
                    Text("勘定科目がまだ読み込まれていません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(candidates) { account in
                        AllocationRow(account: account, onCommit: { try? context.save() })
                    }
                }
            }
        }
        .navigationTitle("家事按分デフォルト")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AllocationRow: View {
    @Bindable var account: Account
    let onCommit: () -> Void
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text("\(account.code) \(account.nameJa)")
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 56)
                .onChange(of: text) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        text = filtered
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onSubmit(commit)
            Text("%")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = String(Int((account.defaultBusinessAllocationRate * 100).rounded()))
        }
    }

    private func commit() {
        let clamped = max(0, min(100, Int(text) ?? 0))
        text = String(clamped)
        let newRate = Double(clamped) / 100.0
        if account.defaultBusinessAllocationRate != newRate {
            account.defaultBusinessAllocationRate = newRate
            onCommit()
        }
    }
}
