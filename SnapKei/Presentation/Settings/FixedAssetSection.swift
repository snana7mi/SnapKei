import SwiftData
import SwiftUI

public struct FixedAssetSection: View {
    @Query(
        filter: #Predicate<FixedAsset> { $0.deletedAt == nil },
        sort: \FixedAsset.acquisitionDate,
        order: .reverse
    ) private var assets: [FixedAsset]

    @State private var showRegisterForm = false
    @State private var selectedAsset: FixedAsset?

    public init() {}

    public var body: some View {
        Section("固定資産台帳") {
            Button {
                showRegisterForm = true
            } label: {
                Label("資産を登録", systemImage: "plus.circle")
            }

            if assets.isEmpty {
                Text("資産が登録されていません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    Button {
                        selectedAsset = asset
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(asset.assetName).font(.subheadline.weight(.semibold))
                                if asset.disposalDate != nil {
                                    Text("処分済")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            HStack {
                                Text("取得 \(YenFormat.string(asset.acquisitionAmount))")
                                Spacer()
                                Text("簿価 \(YenFormat.string(asset.bookValue))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showRegisterForm) { FixedAssetFormView() }
        .sheet(item: $selectedAsset) { asset in FixedAssetDetailView(asset: asset) }
    }
}
