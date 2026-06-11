import Foundation

/// 訂正履歴の before/after スナップショットからフィールド級の差分を導く（決定的・副作用なし、MainActor 隔離）。
/// EntryDetailView（変更履歴）と ActivityLogView（訂正・削除履歴）が共用する。
/// 優良電子帳簿の「訂正・削除の事実と内容が確認できること」の表示部分を担う。
nonisolated public enum EntryChangeDiff {
    public struct FieldChange: Equatable, Sendable {
        public let label: String
        public let old: String
        public let new: String

        public init(label: String, old: String, new: String) {
            self.label = label
            self.old = old
            self.new = new
        }
    }

    /// SystemActivityLog の Data 入口。デコード不能（欠損・破損）は nil を返し、
    /// 呼び出し側が「詳細を表示できません」と降級表示する。クラッシュ禁止。
    /// エンコーダ/デコーダは ExpenseRepository の JSONEncoder() 既定戦略と対で固定（変更すると旧ログが読めなくなる）。
    @MainActor
    public static func changes(
        beforeData: Data?,
        afterData: Data?,
        accountName: (String) -> String?
    ) -> [FieldChange]? {
        guard let beforeData, let afterData,
              let before = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: beforeData),
              let after = try? JSONDecoder().decode(JournalEntrySnapshot.self, from: afterData) else {
            return nil
        }
        return changes(before: before, after: after, accountName: accountName)
    }

    // internal: JournalEntrySnapshot のメンバーが internal のため public にできない。
    // @testable import SnapKei でテストから参照可能。
    // @MainActor: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor のため JournalEntrySnapshot の
    // Codable 準拠および NumberFormatter の利用に MainActor が必要。

    /// diff 対象外のスナップショットフィールド（追加時はここで diff するか除外するか判断すること）:
    /// - 派生値: transitionalMeasureRate（invoiceQualified+transactionDate から導出。ドライバー側を diff 済み）、
    ///   isLateEntry（inputDate から導出）
    /// - 編集不可: fiscalYear / entryNumber / receiptImagePath / receiptImageHash /
    ///   relatedFixedAssetId / sourceTypeRaw / inputDate
    /// - メタデータ: id / createdAt / updatedAt / syncId
    @MainActor
    static func changes(
        before: JournalEntrySnapshot,
        after: JournalEntrySnapshot,
        accountName: (String) -> String?
    ) -> [FieldChange] {
        var result: [FieldChange] = []
        func add(_ label: String, _ old: String, _ new: String) {
            if old != new { result.append(FieldChange(label: label, old: old, new: new)) }
        }
        func account(_ code: String) -> String {
            accountName(code).map { "\(code) \($0)" } ?? code
        }
        let none = "（なし）"

        add("取引日", dateString(before.transactionDate), dateString(after.transactionDate))
        add("取引先", before.counterpartyName, after.counterpartyName)
        add("内容", before.transactionDescription, after.transactionDescription)
        add("メモ", before.memo ?? none, after.memo ?? none)
        add("借方", account(before.debitAccountCode), account(after.debitAccountCode))
        add("貸方", account(before.creditAccountCode), account(after.creditAccountCode))
        add("税込金額", YenFormat.string(before.amountIncludingTax), YenFormat.string(after.amountIncludingTax))
        add("税抜金額", YenFormat.string(before.amountExcludingTax), YenFormat.string(after.amountExcludingTax))
        add("消費税", YenFormat.string(before.consumptionTax), YenFormat.string(after.consumptionTax))
        add("税区分", taxLabel(before.taxCategoryRaw), taxLabel(after.taxCategoryRaw))
        add("入力方式", modeLabel(before.priceEntryModeRaw), modeLabel(after.priceEntryModeRaw))
        add("支払方法", paymentLabel(before.paymentMethodRaw), paymentLabel(after.paymentMethodRaw))
        add("適格番号", before.invoiceRegistrationNumber ?? none, after.invoiceRegistrationNumber ?? none)
        add("適格請求書", qualifiedLabel(before.invoiceQualified), qualifiedLabel(after.invoiceQualified))
        add("事業割合", percentString(before.businessAllocationRate), percentString(after.businessAllocationRate))
        add(
            "按分前金額",
            before.originalAmountIncludingTax.map(YenFormat.string) ?? none,
            after.originalAmountIncludingTax.map(YenFormat.string) ?? none
        )
        add("状態", voidedLabel(before.isVoided), voidedLabel(after.isVoided)) // void ログは afterSnapshot=nil なので Data 入口経由では到達しない（防御的に保持）
        return result
    }

    // MARK: - Formatting

    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    @MainActor
    private static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
    private static func percentString(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }
    private static func qualifiedLabel(_ qualified: Bool) -> String { qualified ? "適格" : "非適格" }
    private static func voidedLabel(_ voided: Bool) -> String { voided ? "取消済" : "有効" }
    private static func taxLabel(_ raw: String) -> String { TaxCategory(rawValue: raw)?.labelJa ?? raw }
    private static func modeLabel(_ raw: String) -> String { PriceEntryMode(rawValue: raw)?.labelJa ?? raw }
    private static func paymentLabel(_ raw: String) -> String { PaymentMethod(rawValue: raw)?.labelJa ?? raw }
}
