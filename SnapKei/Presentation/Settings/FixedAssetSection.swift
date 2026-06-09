import SwiftData
import SwiftUI

public struct FixedAssetSection: View {
    @Query(
        filter: #Predicate<FixedAsset> { $0.deletedAt == nil },
        sort: \FixedAsset.acquisitionDate,
        order: .reverse
    ) private var assets: [FixedAsset]

    public init() {}

    public var body: some View {
        Section("固定資産台帳") {
            if assets.isEmpty {
                Text("資産が登録されていません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    VStack(alignment: .leading) {
                        Text(asset.assetName).font(.subheadline.weight(.semibold))
                        HStack {
                            Text("取得 ¥\(asset.acquisitionAmount)")
                            Spacer()
                            Text("簿価 ¥\(asset.bookValue)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
