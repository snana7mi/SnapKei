import SwiftData
import SwiftUI

/// 訂正・削除履歴の 1 行。編集はフィールド級 diff を、取消は理由を表示する。
/// EntryDetailView（変更履歴）と ActivityLogView（全体ログ）が共用する。
struct ActivityLogRowView: View {
    let log: SystemActivityLog
    let accountName: (String) -> String?
    var showsEntryHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.activityType.labelJa)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(log.occurredAt.formatted(date: .numeric, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsEntryHeader, let header = entryHeader {
                Text(header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let reason = log.reason, !reason.isEmpty {
                Text("理由: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if log.activityType == .editEntry {
                editDiff
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var editDiff: some View {
        if let changes = EntryChangeDiff.changes(
            beforeData: log.beforeSnapshot,
            afterData: log.afterSnapshot,
            accountName: accountName
        ) {
            ForEach(changes, id: \.label) { change in
                Text("\(change.label): \(change.old) → \(change.new)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            // スナップショット欠損・デコード不能（旧バージョン由来など）の降級表示。
            Text("詳細を表示できません")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    /// 全体ログで「どの仕訳の操作か」を示すヘッダ（after 優先、無ければ before）。
    private var entryHeader: String? {
        guard let data = log.afterSnapshot ?? log.beforeSnapshot,
              let snapshot = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: data) else {
            return nil
        }
        return "#\(snapshot.entryNumber)（\(String(snapshot.fiscalYear))年度） \(snapshot.counterpartyName)"
    }
}
