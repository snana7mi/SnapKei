import Foundation

public enum DepreciationService {
    public static func annualDepreciation(for asset: FixedAsset, fiscalYear: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        if fiscalYear < acquisitionYear { return 0 }
        if asset.accumulatedDepreciation >= asset.acquisitionAmount { return 0 }

        switch asset.treatment {
        case .smallAmountFullExpense:
            return 0
        case .lumpSumDepreciation:
            let baseAmount = Double(asset.acquisitionAmount) / 3.0
            let allocated = baseAmount * asset.businessAllocationRate
            return Int(allocated.rounded(.down))
        case .normalDepreciation:
            switch asset.depreciationMethod {
            case .straightLine, .decliningBalance:
                return straightLineAnnual(asset: asset, fiscalYear: fiscalYear, calendar: calendar)
            }
        }
    }

    public static func suggestTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment? {
        ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate)
    }

    private static func straightLineAnnual(asset: FixedAsset, fiscalYear: Int, calendar: Calendar) -> Int {
        let baseAnnual = Double(asset.acquisitionAmount) / Double(asset.usefulLifeYears)
        let acquisitionYear = calendar.component(.year, from: asset.serviceStartDate)
        let acquisitionMonth = calendar.component(.month, from: asset.serviceStartDate)

        var amount: Double
        if fiscalYear == acquisitionYear {
            let monthsInUse = max(0, 13 - acquisitionMonth)
            amount = baseAnnual * Double(monthsInUse) / 12.0
        } else {
            amount = baseAnnual
        }

        let remaining = asset.acquisitionAmount - asset.accumulatedDepreciation
        amount = min(amount, Double(remaining))

        let allocated = amount * asset.businessAllocationRate
        return Int(allocated.rounded(.down))
    }
}
