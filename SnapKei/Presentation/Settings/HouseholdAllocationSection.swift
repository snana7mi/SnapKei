import SwiftData
import SwiftUI

public struct HouseholdAllocationSection: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Environment(\.modelContext) private var context

    public init() {}

    public var body: some View {
        Section("家事按分デフォルト") {
            let candidates = accounts.filter { $0.accountType == .expense }
            if candidates.isEmpty {
                Text("勘定科目がまだ読み込まれていません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates) { account in
                    HStack {
                        Text("\(account.code) \(account.nameJa)")
                        Spacer()
                        Stepper(value: Binding(
                            get: { account.defaultBusinessAllocationRate },
                            set: { value in
                                account.defaultBusinessAllocationRate = value
                                try? context.save()
                            }
                        ), in: 0...1, step: 0.1) {
                            Text("\(Int(account.defaultBusinessAllocationRate * 100))%")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
