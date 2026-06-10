import SwiftUI

public struct TreatmentSuggestionBanner: View {
    public let amount: Int
    public let transactionDate: Date

    public init(amount: Int, transactionDate: Date) {
        self.amount = amount
        self.transactionDate = transactionDate
    }

    public var body: some View {
        if let treatment = ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: transactionDate) {
            VStack(alignment: .leading, spacing: 8) {
                Label(headline(for: treatment), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(detail(for: treatment))
                    .font(.footnote)
            }
            .padding()
            .background(Color.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func headline(for treatment: AssetTreatment) -> String {
        switch treatment {
        case .lumpSumDepreciation: "一括償却資産の対象です"
        case .smallAmountFullExpense: "少額減価償却特例の対象です"
        case .normalDepreciation: "通常の減価償却が必要です"
        }
    }

    private func detail(for treatment: AssetTreatment) -> String {
        switch treatment {
        case .lumpSumDepreciation:
            "10-20万円未満の固定資産は3年均等償却が選択可能です。"
        case .smallAmountFullExpense:
            "20-30万円未満の固定資産は青色申告者の特例で一括費用化できます。"
        case .normalDepreciation:
            "取得価額30万円以上は耐用年数に応じた減価償却が必要です。"
        }
    }
}
