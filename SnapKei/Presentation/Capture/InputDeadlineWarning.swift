import SwiftUI

public struct InputDeadlineWarning: View {
    public let transactionDate: Date

    public init(transactionDate: Date) {
        self.transactionDate = transactionDate
    }

    public var body: some View {
        let days = ComplianceService.daysUntilScanDeadline(receiptDate: transactionDate)
        if days < 0 {
            warningBlock(color: .red, icon: "xmark.octagon.fill", title: "スキャナ保存期限切れ", detail: "紙の原本も保管してください。")
        } else if days < 14 {
            warningBlock(color: .orange, icon: "exclamationmark.triangle.fill", title: "保存期限まで残り \(days) 日", detail: "期限内に入力を完了してください。")
        }
    }

    private func warningBlock(color: Color, icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
