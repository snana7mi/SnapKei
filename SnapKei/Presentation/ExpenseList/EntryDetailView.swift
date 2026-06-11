import PDFKit
import SwiftData
import SwiftUI

/// 仕訳の詳細表示: 全項目・証憑（画像/PDF・拡大・SHA-256 検証）・理由付き取消。
struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]

    let entry: JournalEntry

    @State private var showViewer = false
    @State private var showVoidDialog = false
    @State private var voidReason = ""
    @State private var actionErrorMessage: String?
    // 解決はファイル IO + SHA-256 を伴うため body 再評価ごとに行わず、
    // バックグラウンドで一度だけ読み込む（サムネイルは縮小デコード）。
    @State private var attachment: ReceiptAttachment?
    @State private var thumbnail: UIImage?
    @State private var attachmentLoaded = false

    var body: some View {
        NavigationStack {
            List {
                Section("取引") {
                    row("取引日", entry.transactionDate.formatted(date: .numeric, time: .omitted))
                    row("取引先", entry.counterpartyName)
                    row("内容", entry.transactionDescription)
                    if let memo = entry.memo, !memo.isEmpty {
                        row("メモ", memo)
                    }
                }

                Section("仕訳") {
                    row("仕訳番号", "#\(entry.entryNumber)（\(entry.fiscalYear)年度）")
                    row("借方", accountLabel(entry.debitAccountCode))
                    row("貸方", accountLabel(entry.creditAccountCode))
                    row("税込金額", YenFormat.string(entry.amountIncludingTax))
                    row("税抜金額", YenFormat.string(entry.amountExcludingTax))
                    row("消費税", YenFormat.string(entry.consumptionTax))
                    row("税区分", entry.taxCategory.labelJa)
                    row("入力方式", entry.priceEntryMode.labelJa)
                    row("支払方法", entry.paymentMethod.labelJa)
                    if entry.businessAllocationRate < 1 {
                        row("事業割合", "\(Int((entry.businessAllocationRate * 100).rounded()))%")
                        if let original = entry.originalAmountIncludingTax {
                            row("按分前金額", YenFormat.string(original))
                        }
                    }
                }

                if entry.invoiceRegistrationNumber != nil || entry.invoiceQualified {
                    Section("インボイス") {
                        if let number = entry.invoiceRegistrationNumber {
                            row("適格番号", number)
                        }
                        row("適格請求書", entry.invoiceQualified ? "適格" : "非適格")
                        if !entry.invoiceQualified, entry.transitionalMeasureRate < 1.0 {
                            row("経過措置控除率", "\(Int((entry.transitionalMeasureRate * 100).rounded()))%")
                        }
                    }
                }

                receiptSection

                Section("ステータス") {
                    row("記帳種別", entry.sourceType.labelJa)
                    row("入力日", entry.inputDate.formatted(date: .numeric, time: .shortened))
                    if entry.isLateEntry {
                        Label("スキャナ保存期限後の入力（遅延）", systemImage: "clock.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if entry.isVoided {
                        Label("取消済", systemImage: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !entry.isVoided {
                    if entry.relatedFixedAssetId == nil {
                        Section {
                            Button("取消（理由を入力）", role: .destructive) { showVoidDialog = true }
                        } footer: {
                            Text("取消は記録を残したまま無効化します（電帳法の訂正・削除履歴）。")
                        }
                    } else {
                        Section {
                            Text("固定資産に関連する仕訳です。設定の固定資産台帳から資産の削除・処分を行ってください。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("仕訳詳細")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard !attachmentLoaded else { return }
                let path = entry.receiptImagePath
                let hash = entry.receiptImageHash
                let loaded = await Task.detached(priority: .userInitiated) { () -> (ReceiptAttachment?, UIImage?) in
                    let resolved = ReceiptAttachment.resolve(relativePath: path, expectedHash: hash)
                    var thumb: UIImage?
                    if let resolved, resolved.kind == .image, resolved.integrity != .missingFile {
                        thumb = ReceiptThumbnail.load(url: resolved.url, maxPixel: 600)
                    }
                    return (resolved, thumb)
                }.value
                attachment = loaded.0
                thumbnail = loaded.1
                attachmentLoaded = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .alert("仕訳を取消しますか？", isPresented: $showVoidDialog) {
                TextField("理由（任意）", text: $voidReason)
                Button("取消する", role: .destructive) { voidEntry() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("取消した仕訳は帳簿集計から除外されます。")
            }
            .alert(
                "操作できませんでした",
                isPresented: Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .fullScreenCover(isPresented: $showViewer) {
                if let attachment {
                    ReceiptViewer(attachment: attachment)
                } else {
                    // 到達しないはずだが、空白の全画面（脱出不能）だけは防ぐ。
                    NavigationStack {
                        ContentUnavailableView("証憑を読み込めません", systemImage: "photo")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("閉じる") { showViewer = false }
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - 証憑

    @ViewBuilder
    private var receiptSection: some View {
        Section("証憑") {
            if let attachment {
                integrityBadge(attachment.integrity)
                if attachment.integrity != .missingFile {
                    Button {
                        showViewer = true
                    } label: {
                        receiptThumbnail(attachment)
                    }
                }
            } else if entry.receiptImagePath != nil, !attachmentLoaded {
                ProgressView()
            } else if entry.receiptImagePath == nil, entry.receiptImageHash != nil {
                // 同期で受信した仕訳（旧バージョン由来でパスなし）: 証憑は撮影元の端末にある。
                Label("証憑は撮影した端末に保存されています（同期では画像は転送されません）", systemImage: "iphone.and.arrow.forward")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("証憑なし（手動入力・自動仕訳など）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func receiptThumbnail(_ attachment: ReceiptAttachment) -> some View {
        switch attachment.kind {
        case .image:
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("画像を読み込めません", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        case .pdf:
            Label("PDF を表示", systemImage: "doc.richtext")
        }
    }

    @ViewBuilder
    private func integrityBadge(_ integrity: ReceiptAttachment.Integrity) -> some View {
        switch integrity {
        case .verified:
            Label("整合性OK（SHA-256 一致）", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .tampered:
            Label("改ざんの可能性（ハッシュ不一致）", systemImage: "exclamationmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        case .missingFile:
            Label("証憑ファイルが端末内にありません（同期では画像は転送されません）", systemImage: "questionmark.folder")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .unverified:
            Label("未検証（ハッシュ記録なし）", systemImage: "seal")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func voidEntry() {
        let reason = voidReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.void(entry, reason: reason.isEmpty ? "ユーザー操作" : reason)
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Labels

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func accountLabel(_ code: String) -> String {
        let name = accounts.first { $0.code == code }?.nameJa ?? ""
        return name.isEmpty ? code : "\(code) \(name)"
    }

}

/// 証憑のフルスクリーンビューア。画像は pinch zoom、PDF は PDFKit。
private struct ReceiptViewer: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: ReceiptAttachment

    var body: some View {
        NavigationStack {
            Group {
                switch attachment.kind {
                case .image:
                    if let uiImage = UIImage(contentsOfFile: attachment.url.path) {
                        ZoomableImageViewer(image: uiImage)
                    } else {
                        ContentUnavailableView("画像を読み込めません", systemImage: "photo")
                    }
                case .pdf:
                    ReceiptPDFViewer(url: attachment.url)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("証憑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}

/// ScrollView ベースの pinch zoom（1x–5x、ダブルタップで 2x/リセット）。
private struct ZoomableImageViewer: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .systemBackground

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        // contentLayoutGuide に四辺を固定しないと contentSize が定まらず、
        // ズームはできてもパンできない（拡大時に四隅へ到達不能）。
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2, animated: true)
        }
    }
}

/// 縮小デコード（ImageIO）。フル解像度の UIImage を作らずサムネイルを生成する。
nonisolated enum ReceiptThumbnail {
    static func load(url: URL, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private struct ReceiptPDFViewer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
