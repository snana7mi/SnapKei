import Foundation
import SwiftData

@Model
public final class Account {
    @Attribute(.unique) public var code: String
    public var nameJa: String
    public var nameZh: String
    public var accountTypeRaw: String
    public var isBuiltin: Bool
    public var isActive: Bool
    public var defaultBusinessAllocationRate: Double

    public init(
        code: String,
        nameJa: String,
        nameZh: String,
        accountType: AccountType,
        isBuiltin: Bool = true,
        isActive: Bool = true,
        defaultBusinessAllocationRate: Double = 1.0
    ) {
        self.code = code
        self.nameJa = nameJa
        self.nameZh = nameZh
        self.accountTypeRaw = accountType.rawValue
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.defaultBusinessAllocationRate = defaultBusinessAllocationRate
    }

    public var accountType: AccountType {
        AccountType(rawValue: accountTypeRaw) ?? .expense
    }
}
