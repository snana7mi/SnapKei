import Foundation

/// 固定資産登記の検証と償却区分の選択可否（View から分離してテスト可能に）。
nonisolated public enum FixedAssetRules {
    public enum Issue: Equatable, Sendable {
        case missingName
        case invalidAmount
        case invalidUsefulLife
        case invalidAllocation
        case treatmentNotAvailable
        case invalidAccumulated
        case carriedOverMustBePriorYear
        case carriedOverSmallAmountNotFullyExpensed
    }

    /// 金額・取得日から法的に選択可能な償却区分。10万円未満は資産計上対象外（空配列）。
    /// 先頭は常に定額法（恒久的に選択可能）。
    public static func availableTreatments(amount: Int, acquisitionDate: Date) -> [AssetTreatment] {
        guard amount >= 100_000 else { return [] }
        var treatments: [AssetTreatment] = [.normalDepreciation]
        if amount < ComplianceConstants.lumpSumDepreciationThreshold {
            treatments.append(.lumpSumDepreciation)
        }
        if amount < ComplianceConstants.smallDepreciableAssetThreshold,
           acquisitionDate <= ComplianceConstants.smallDepreciableExpiry {
            treatments.append(.smallAmountFullExpense)
        }
        return treatments
    }

    public static func validate(
        name: String,
        amount: Int,
        usefulLifeYears: Int,
        allocationRate: Double,
        treatment: AssetTreatment,
        acquisitionDate: Date,
        isCarriedOver: Bool,
        accumulatedDepreciation: Int,
        today: Date = Date()
    ) -> [Issue] {
        var issues: [Issue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.missingName) }
        if amount <= 0 { issues.append(.invalidAmount) }
        if !(2...50).contains(usefulLifeYears) { issues.append(.invalidUsefulLife) }
        if allocationRate <= 0 || allocationRate > 1 { issues.append(.invalidAllocation) }
        if amount > 0, !availableTreatments(amount: amount, acquisitionDate: acquisitionDate).contains(treatment) {
            issues.append(.treatmentNotAvailable)
        }
        if isCarriedOver {
            if !(0...max(amount, 0)).contains(accumulatedDepreciation) {
                issues.append(.invalidAccumulated)
            }
            // 当年取得の資産を引継ぎ登録すると月割償却と引継ぎ累計が二重計上になる。
            if FiscalYearRule.year(for: acquisitionDate) >= FiscalYearRule.year(for: today) {
                issues.append(.carriedOverMustBePriorYear)
            }
            // 少額特例は供用年に全額経費化済みのはず（未満だと永久に償却されない簿価が残る）。
            if treatment == .smallAmountFullExpense, accumulatedDepreciation != amount {
                issues.append(.carriedOverSmallAmountNotFullyExpensed)
            }
        }
        return issues
    }
}
