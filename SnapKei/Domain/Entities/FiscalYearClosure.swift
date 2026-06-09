import Foundation
import SwiftData

/// Existence of a row means the fiscal year is locked.
@Model
public final class FiscalYearClosure {
    @Attribute(.unique) public var fiscalYear: Int
    public var closedAt: Date
    public var netIncomeAtClosing: Int
    public var closedByDeviceId: String
    public var syncId: UUID
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        fiscalYear: Int,
        closedAt: Date = Date(),
        netIncomeAtClosing: Int,
        closedByDeviceId: String,
        syncId: UUID = UUID(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.fiscalYear = fiscalYear
        self.closedAt = closedAt
        self.netIncomeAtClosing = netIncomeAtClosing
        self.closedByDeviceId = closedByDeviceId
        self.syncId = syncId
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
