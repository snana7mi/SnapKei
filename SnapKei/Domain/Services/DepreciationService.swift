import Foundation

public struct DepreciationAmount: Equatable, Sendable {
    /// 本年分の償却費合計。家事按分に関係なく簿価を減らす金額。
    public let full: Int
    /// 必要経費算入額 = full x 事業専用割合。
    public let deductible: Int
    /// 家事分。年度末に事業主貸で処理する。
    public var ownerPortion: Int { full - deductible }

    public init(full: Int, deductible: Int) {
        self.full = full
        self.deductible = deductible
    }
}

public enum DepreciationService {
    public static func annualAmount(for asset: FixedAsset, fiscalYear: Int) -> DepreciationAmount {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        if fiscalYear < acquisitionYear { return DepreciationAmount(full: 0, deductible: 0) }
        if asset.accumulatedDepreciation >= asset.acquisitionAmount { return DepreciationAmount(full: 0, deductible: 0) }

        let fullBase: Double
        switch asset.treatment {
        case .smallAmountFullExpense:
            return DepreciationAmount(full: 0, deductible: 0)
        case .lumpSumDepreciation:
            fullBase = Double(asset.acquisitionAmount) / 3.0
        case .normalDepreciation:
            let baseAnnual = Double(asset.acquisitionAmount) / Double(asset.usefulLifeYears)
            let acquisitionMonth = calendar.component(.month, from: asset.serviceStartDate)
            if fiscalYear == acquisitionYear {
                let monthsInUse = max(0, 13 - acquisitionMonth)
                fullBase = baseAnnual * Double(monthsInUse) / 12.0
            } else {
                fullBase = baseAnnual
            }
        }

        let remaining = asset.acquisitionAmount - asset.accumulatedDepreciation
        let full = min(Int(fullBase.rounded(.down)), remaining)
        let deductible = Int((Double(full) * asset.businessAllocationRate).rounded(.down))
        return DepreciationAmount(full: full, deductible: deductible)
    }

    public static func annualDepreciation(for asset: FixedAsset, fiscalYear: Int) -> Int {
        annualAmount(for: asset, fiscalYear: fiscalYear).deductible
    }

    public static func suggestTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate)
    }

}
