import SwiftData
import SwiftUI

/// 資産の詳細・処分・削除。
struct FixedAssetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: FixedAsset

    @State private var disposalDate = Date()
    @State private var proceedsText = ""
    @State private var showDisposeConfirmation = false
    @State private var actionErrorMessage: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("資産") {
                    row("資産名", asset.assetName)
                    row("取得日", asset.acquisitionDate.formatted(date: .numeric, time: .omitted))
                    row("取得価額", YenFormat.string(asset.acquisitionAmount))
                    row("耐用年数", "\(asset.usefulLifeYears) 年")
                    row("償却区分", treatmentLabel(asset.treatment))
                    row("事業割合", "\(Int((asset.businessAllocationRate * 100).rounded()))%")
                    row("償却累計額", YenFormat.string(asset.accumulatedDepreciation))
                    row("簿価", YenFormat.string(asset.bookValue))
                }

                if let disposed = asset.disposalDate {
                    Section("処分") {
                        row("処分日", disposed.formatted(date: .numeric, time: .omitted))
                        if let proceeds = asset.disposalAmount {
                            row("売却代金", YenFormat.string(proceeds))
                        }
                    }
                } else {
                    Section {
                        DatePicker("処分日", selection: $disposalDate, displayedComponents: .date)
                        TextField("売却代金（任意・記録のみ）", text: $proceedsText).keyboardType(.numberPad)
                        Button("処分する", role: .destructive) { showDisposeConfirmation = true }
                    } header: {
                        Text("処分（売却・除却）")
                    } footer: {
                        Text(asset.treatment == .lumpSumDepreciation
                            ? "一括償却資産は処分後も3年均等償却を継続します（転出仕訳は生成されません）。売却代金は譲渡所得（事業外）のため記帳されません。"
                            : "償却累計 \(YenFormat.string(asset.accumulatedDepreciation)) と簿価 \(YenFormat.string(asset.bookValue)) を帳簿から転出する仕訳を自動生成し、処分年度以降の減価償却を停止します。売却代金は譲渡所得（事業外）のため記帳されません。事業口座に入金した場合は手動入力の振替（普通預金/事業主借）で記帳してください。")
                    }
                }

                if asset.disposalDate == nil, canDelete {
                    Section {
                        Button("削除（誤登記の取消）", role: .destructive) { showDeleteConfirmation = true }
                    } footer: {
                        Text("台帳から削除し、取得仕訳があれば取消（void）します。")
                    }
                }
            }
            .navigationTitle("資産の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .confirmationDialog("処分を記録しますか？", isPresented: $showDisposeConfirmation, titleVisibility: .visible) {
                Button("処分する", role: .destructive) { dispose() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(asset.treatment == .lumpSumDepreciation
                    ? "処分を記録します。3年均等償却はそのまま継続します。"
                    : "転出仕訳（最大2件）を作成し、処分年度以降の減価償却を停止します。")
            }
            .confirmationDialog("削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { deleteAsset() }
                Button("キャンセル", role: .cancel) {}
            }
            .alert(
                "操作できませんでした",
                isPresented: Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
        }
    }

    private var canDelete: Bool {
        FixedAssetService(context: context, deviceId: DeviceID.current).canDelete(asset)
    }

    private func dispose() {
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.dispose(asset, on: disposalDate, proceeds: Int(proceedsText))
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func deleteAsset() {
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.delete(asset)
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func treatmentLabel(_ treatment: AssetTreatment) -> String {
        switch treatment {
        case .normalDepreciation: "定額法"
        case .lumpSumDepreciation: "一括償却(3年)"
        case .smallAmountFullExpense: "少額特例(即時償却)"
        }
    }
}
