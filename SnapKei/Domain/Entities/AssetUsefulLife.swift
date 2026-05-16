import Foundation
import SwiftData

@Model
public final class AssetUsefulLife {
    @Attribute(.unique) public var code: String
    public var nameJa: String
    public var nameZh: String
    public var years: Int
    public var isBuiltin: Bool

    public init(
        code: String,
        nameJa: String,
        nameZh: String,
        years: Int,
        isBuiltin: Bool = true
    ) {
        self.code = code
        self.nameJa = nameJa
        self.nameZh = nameZh
        self.years = years
        self.isBuiltin = isBuiltin
    }
}
