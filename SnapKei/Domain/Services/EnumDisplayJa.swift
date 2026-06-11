import Foundation

/// 列挙の日本語表示名の単一定義。
/// EntryDetailView（詳細）・EntryEditView（編集フォーム）・訂正履歴 diff が共用する。

nonisolated public extension TaxCategory {
    var labelJa: String {
        switch self {
        case .standard10: "10%"
        case .reduced8: "8% 軽減"
        case .nonTaxable: "非課税"
        case .outOfScope: "対象外"
        }
    }
}

nonisolated public extension PriceEntryMode {
    var labelJa: String {
        switch self {
        case .taxIncluded: "税込"
        case .taxExcluded: "税抜"
        }
    }
}

nonisolated public extension PaymentMethod {
    var labelJa: String {
        switch self {
        case .cash: "現金"
        case .creditCard: "クレジット"
        case .bankTransfer: "銀行振込"
        case .ownerLoan: "事業主借"
        case .ownerWithdraw: "事業主貸"
        case .accountsPayable: "未払金"
        case .other: "その他"
        }
    }
}

nonisolated public extension RecordSource {
    var labelJa: String {
        switch self {
        case .aiParsed: "AI解析（レシート撮影）"
        case .electronicTransaction: "電子取引（PDF取込）"
        case .manual: "手動入力"
        case .imported: "インポート"
        case .depreciation: "減価償却（自動）"
        }
    }
}

nonisolated public extension ActivityType {
    var labelJa: String {
        switch self {
        case .createEntry: "作成"
        case .editEntry: "編集"
        case .voidEntry: "取消"
        case .unlockPeriod: "年度再開"
        case .fiscalYearTransition: "年度締め"
        case .aiParsing: "AI解析"
        case .depreciationPosting: "減価償却計上"
        }
    }
}
