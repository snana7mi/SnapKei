# SnapKei 仕訳詳細 + 証憑ビューア Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一覧の仕訳行から詳細画面を開き、全項目・証憑（画像/PDF、拡大、SHA-256 検証）・理由付き取消を提供する。

**Architecture:** 証憑の解決（種別・URL・完全性）は `ReceiptAttachment.resolve`（TDD）に分離。`EntryDetailView` は sheet 表示で、ビューアは画像（ScrollView ズーム）/ PDF（PDFKit）。取消は既存 `SwiftDataExpenseRepository.void` に理由を渡す。資産連動仕訳の取消禁止ルールは一覧と共通。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / PDFKit / swift-testing。

**Spec reference:** `docs/superpowers/specs/2026-06-11-snapkei-entry-detail-design.md`

**Branch:** `entry-detail`（作成済み）

**User preferences carried forward:** 完了後 merge + push まで実施（今回ユーザー承認済み）。コード変更タスクの最後にフルテスト実行。

**Standard test command:**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "error:|✘ Test|✘ Suite|TEST SUCCEEDED|TEST FAILED|with [0-9]+ tests" | head -20
```

Baseline: `** TEST SUCCEEDED **`, 229 tests / 44 suites（main = 57a22b6）。

---

## File Structure

```
SnapKei/Domain/Services/ReceiptAttachment.swift          [CREATE — 証憑解決]
SnapKei/Presentation/ExpenseList/EntryDetailView.swift   [CREATE — 詳細+ビューア]
SnapKei/Presentation/ExpenseList/ExpenseListView.swift   [MODIFY — 行タップ + sheet + 取消移譲]
SnapKeiTests/ReceiptAttachmentTests.swift                [CREATE]
```

---

## Task 1: ReceiptAttachment

**Files:**
- Create: `SnapKei/Domain/Services/ReceiptAttachment.swift`
- Test: `SnapKeiTests/ReceiptAttachmentTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SnapKei

@Suite("ReceiptAttachment")
struct ReceiptAttachmentTests {

    @Test func nilPath_returnsNil() {
        #expect(ReceiptAttachment.resolve(relativePath: nil, expectedHash: nil) == nil)
    }

    @Test func jpegFile_withMatchingHash_isVerifiedImage() throws {
        let data = Data(repeating: 0xCD, count: 128)
        let stored = try ImageStorageService.persist(jpegData: data, fiscalYear: 2026, transactionDate: Date())

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: stored.sha256Hex
        ))

        #expect(attachment.kind == .image)
        #expect(attachment.integrity == .verified)
        #expect(try Data(contentsOf: attachment.url) == data)
    }

    @Test func wrongHash_isTampered() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x01, count: 64), fiscalYear: 2026, transactionDate: Date()
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: "deadbeef"
        ))

        #expect(attachment.integrity == .tampered)
    }

    @Test func missingFile_isMissing() throws {
        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: "receipts/2026/does-not-exist.jpg", expectedHash: "x"
        ))

        #expect(attachment.integrity == .missingFile)
    }

    @Test func nilHash_isUnverified() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x02, count: 64), fiscalYear: 2026, transactionDate: Date()
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: nil
        ))

        #expect(attachment.integrity == .unverified)
    }

    @Test func pdfExtension_isPdfKind() throws {
        let stored = try ImageStorageService.persist(
            jpegData: Data(repeating: 0x03, count: 64), fiscalYear: 2026,
            transactionDate: Date(), fileExtension: "pdf"
        )

        let attachment = try #require(ReceiptAttachment.resolve(
            relativePath: stored.relativePath, expectedHash: stored.sha256Hex
        ))

        #expect(attachment.kind == .pdf)
        #expect(attachment.integrity == .verified)
    }
}
```

- [ ] **Step 2: Run to verify RED**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SnapKeiTests/ReceiptAttachmentTests test 2>&1 | grep -E "error:|TEST FAILED" | head -4
```

Expected: compile failure — `ReceiptAttachment` 不存在。

- [ ] **Step 3: Implement ReceiptAttachment.swift**

```swift
import Foundation

/// 仕訳の証憑（レシート画像/PDF）の解決: 種別・ファイル URL・SHA-256 完全性。
/// 電帳法のスキャナ保存要件（真実性の確保）を画面に出すための単一定義。
public struct ReceiptAttachment: Equatable {
    public enum Kind: Equatable {
        case image
        case pdf
    }

    public enum Integrity: Equatable {
        case verified      // ハッシュ一致
        case tampered      // ハッシュ不一致（改ざんの可能性）
        case missingFile   // ファイルが存在しない
        case unverified    // 期待ハッシュなし（旧データ等）
    }

    public let kind: Kind
    public let url: URL
    public let integrity: Integrity

    public static func resolve(relativePath: String?, expectedHash: String?) -> ReceiptAttachment? {
        guard let relativePath, let url = ImageStorageService.absoluteURL(for: relativePath) else {
            return nil
        }
        let kind: Kind = url.pathExtension.lowercased() == "pdf" ? .pdf : .image

        let integrity: Integrity
        if !FileManager.default.fileExists(atPath: url.path) {
            integrity = .missingFile
        } else if let expectedHash {
            integrity = ImageStorageService.verifyIntegrity(at: relativePath, expectedHash: expectedHash)
                ? .verified
                : .tampered
        } else {
            integrity = .unverified
        }
        return ReceiptAttachment(kind: kind, url: url, integrity: integrity)
    }
}
```

- [ ] **Step 4: Run to verify GREEN** — same command, expected `** TEST SUCCEEDED **`。

- [ ] **Step 5: Checkpoint**

```bash
git add SnapKei/Domain/Services/ReceiptAttachment.swift SnapKeiTests/ReceiptAttachmentTests.swift
git commit -m "feat: receipt attachment resolution with integrity check"
```

---

## Task 2: EntryDetailView + ビューア + 一覧接線

**Files:**
- Create: `SnapKei/Presentation/ExpenseList/EntryDetailView.swift`
- Modify: `SnapKei/Presentation/ExpenseList/ExpenseListView.swift`

View のため単体テストなし（build + smoke）。

- [ ] **Step 1: Create EntryDetailView.swift**

```swift
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

    private var attachment: ReceiptAttachment? {
        ReceiptAttachment.resolve(relativePath: entry.receiptImagePath, expectedHash: entry.receiptImageHash)
    }

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
                    row("税区分", taxCategoryLabel)
                    row("入力方式", entry.priceEntryModeRaw == PriceEntryMode.taxExcluded.rawValue ? "税抜" : "税込")
                    row("支払方法", paymentMethodLabel)
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
                    row("記帳種別", sourceTypeLabel)
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
            if let uiImage = UIImage(contentsOfFile: attachment.url.path) {
                Image(uiImage: uiImage)
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
            Label("証憑ファイルが見つかりません", systemImage: "questionmark.folder")
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

    private var taxCategoryLabel: String {
        switch TaxCategory(rawValue: entry.taxCategoryRaw) {
        case .standard10: "10%"
        case .reduced8: "8% 軽減"
        case .nonTaxable: "非課税"
        case .outOfScope, .none: "対象外"
        }
    }

    private var paymentMethodLabel: String {
        switch PaymentMethod(rawValue: entry.paymentMethodRaw) {
        case .cash: "現金"
        case .creditCard: "クレジット"
        case .bankTransfer: "銀行振込"
        case .ownerLoan: "事業主借"
        case .ownerWithdraw: "事業主貸"
        case .accountsPayable: "未払金"
        case .other, .none: "その他"
        }
    }

    private var sourceTypeLabel: String {
        switch RecordSource(rawValue: entry.sourceTypeRaw) {
        case .aiParsed: "AI解析（レシート撮影）"
        case .electronicTransaction: "電子取引（PDF取込）"
        case .manual: "手動入力"
        case .imported: "インポート"
        case .depreciation: "減価償却（自動）"
        case .none: entry.sourceTypeRaw
        }
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

/// ScrollView ベースの pinch zoom（1x–5x、ダブルタップでリセット/2x トグル）。
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
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor),
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
```

- [ ] **Step 2: ExpenseListView — 行タップで詳細 sheet**

`@State private var selectedEntry: JournalEntry?` を追加し、ForEach の行 VStack を Button でラップ:

```swift
            ForEach(viewModel.entries) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        // …既存の行内容そのまま…
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) { /* 既存のまま */ }
            }
```

`.sheet(isPresented: $showManualEntry, ...)` の後に:

```swift
        .sheet(item: $selectedEntry, onDismiss: { viewModel.refresh() }) { entry in
            EntryDetailView(entry: entry)
        }
```

（`JournalEntry` は `@Model` で Identifiable。）

- [ ] **Step 3: Build to verify compile**

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | sort -u | head
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Checkpoint**

```bash
git add SnapKei/Presentation/ExpenseList/EntryDetailView.swift SnapKei/Presentation/ExpenseList/ExpenseListView.swift
git commit -m "feat: entry detail with receipt viewer and reasoned void"
```

---

## Task 3: Final verification + merge + push

- [ ] **Step 1: Full test run** — standard command. Expected: `** TEST SUCCEEDED **`, 235 tests 前後（229 + ReceiptAttachment 6）。
- [ ] **Step 2: Review pass**（並列レビュア、確認済みの実バグのみ修正）
- [ ] **Step 3: Manual smoke** — 一覧 > 行タップ: AI 撮影仕訳に画像+整合性OK、PDF 取込仕訳に PDF ビューア、手動仕訳に「証憑なし」、取消（理由入力）後に一覧へ反映、資産連動仕訳は取消ボタンなし。
- [ ] **Step 4: Merge to main + push**（ユーザー承認済みフロー）

---

## Out-of-Scope（spec 参照）

仕訳編集 / 証憑差し替え / OCR 再解析 / 監査ログ閲覧 UI。
