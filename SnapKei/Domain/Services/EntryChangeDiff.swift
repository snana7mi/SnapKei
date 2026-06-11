import Foundation

/// 訂正履歴の before/after スナップショットからフィールド級の差分を導く純関数。
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
        add("税込金額", yenString(before.amountIncludingTax), yenString(after.amountIncludingTax))
        add("税抜金額", yenString(before.amountExcludingTax), yenString(after.amountExcludingTax))
        add("消費税", yenString(before.consumptionTax), yenString(after.consumptionTax))
        add("税区分", taxLabel(before.taxCategoryRaw), taxLabel(after.taxCategoryRaw))
        add("入力方式", modeLabel(before.priceEntryModeRaw), modeLabel(after.priceEntryModeRaw))
        add("支払方法", paymentLabel(before.paymentMethodRaw), paymentLabel(after.paymentMethodRaw))
        add("適格番号", before.invoiceRegistrationNumber ?? none, after.invoiceRegistrationNumber ?? none)
        add("適格請求書", qualifiedLabel(before.invoiceQualified), qualifiedLabel(after.invoiceQualified))
        add("事業割合", percentString(before.businessAllocationRate), percentString(after.businessAllocationRate))
        add(
            "按分前金額",
            before.originalAmountIncludingTax.map(yenString) ?? none,
            after.originalAmountIncludingTax.map(yenString) ?? none
        )
        add("状態", voidedLabel(before.isVoided), voidedLabel(after.isVoided))
        return result
    }

    // MARK: - Formatting

    // nonisolated(unsafe): DateFormatter は init 後は読み取り専用のため実質スレッドセーフ。
    // Swift 6 strict concurrency の "non-Sendable stored in nonisolated" 警告を抑制する。
    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    // NumberFormatter.string は内部キャッシュがあるためスレッドセーフではないが、
    // 差分表示は UI スレッドから呼ばれる想定かつ同時呼び出しが起きないため許容する。
    nonisolated(unsafe) private static let yenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    @MainActor
    private static func yenString(_ amount: Int) -> String {
        yenFormatter.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }

    @MainActor
    private static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
    private static func percentString(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }
    private static func qualifiedLabel(_ qualified: Bool) -> String { qualified ? "適格" : "非適格" }
    private static func voidedLabel(_ voided: Bool) -> String { voided ? "取消済" : "有効" }
    private static func taxLabel(_ raw: String) -> String { TaxCategory(rawValue: raw)?.labelJa ?? raw }
    private static func modeLabel(_ raw: String) -> String { PriceEntryMode(rawValue: raw)?.labelJa ?? raw }
    private static func paymentLabel(_ raw: String) -> String { PaymentMethod(rawValue: raw)?.labelJa ?? raw }
}
