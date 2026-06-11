import SwiftData
import SwiftUI

/// 訂正・削除履歴の全体ログ（設定 → コンプライアンス）。
/// 優良電子帳簿の「訂正・削除の事実と内容が確認できること」の提示画面。
struct ActivityLogView: View {
    @Query(sort: \SystemActivityLog.occurredAt, order: .reverse)
    private var logs: [SystemActivityLog]
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var typeFilter: ActivityType?
    @State private var yearFilter: Int?

    var body: some View {
        List {
            Section {
                Picker("種別", selection: $typeFilter) {
                    Text("すべて").tag(ActivityType?.none)
                    ForEach(ActivityType.allCases, id: \.self) { type in
                        Text(type.labelJa).tag(Optional(type))
                    }
                }
                Picker("操作年", selection: $yearFilter) {
                    Text("すべて").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text("\(String(year))年").tag(Optional(year))
                    }
                }
            }

            Section {
                if filteredLogs.isEmpty {
                    Text("履歴がありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLogs) { log in
                        ActivityLogRowView(log: log, accountName: lookupAccountName, showsEntryHeader: true)
                    }
                }
            } footer: {
                Text("履歴は本端末で行った操作の記録です（端末間では同期されません）。")
            }
        }
        .navigationTitle("訂正・削除履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableYears: [Int] {
        Array(Set(logs.map { FiscalYearRule.year(for: $0.occurredAt) })).sorted(by: >)
    }

    private var filteredLogs: [SystemActivityLog] {
        logs.filter { log in
            (typeFilter == nil || log.activityType == typeFilter)
                && (yearFilter == nil || FiscalYearRule.year(for: log.occurredAt) == yearFilter)
        }
    }

    private func lookupAccountName(_ code: String) -> String? {
        let name = accounts.first { $0.code == code }?.nameJa
        return (name?.isEmpty ?? true) ? nil : name
    }
}
