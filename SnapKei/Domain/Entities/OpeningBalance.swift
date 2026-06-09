import Foundation
import SwiftData

/// 期首残高。金額は debit-signed（資産プラス / 負債・元入金マイナス）。
@Model
public final class OpeningBalance {
    @Attribute(.unique) public var id: UUID
    public var fiscalYear: Int
    public var accountCode: String
    public var amount: Int
    public var isAutoRolled: Bool
    public var syncId: UUID
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        fiscalYear: Int,
        accountCode: String,
        amount: Int,
        isAutoRolled: Bool = false,
        syncId: UUID = UUID(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.fiscalYear = fiscalYear
        self.accountCode = accountCode
        self.amount = amount
        self.isAutoRolled = isAutoRolled
        self.syncId = syncId
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
