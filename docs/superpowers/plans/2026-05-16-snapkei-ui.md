# SnapKei UI (Phase 4 + 5 + 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete MVP user interface — Capture flow (camera/album/PDF), 4-tab navigation (Home/Capture/List/Settings), the report generation (P/L PDF + CSV), and finish localization. After this plan, the MVP is shippable.

**Architecture:** SwiftUI + `@Observable` ViewModels in `Presentation/<Tab>/`. SwiftData queries via `@Query`. AI parsing via the `AIRouter` from Plan 2. Each Tab is independent but they all read from the same `ModelContainer`. Settings drives `AISettings` / `AppSettings` persistence and triggers SIWA.

**Tech Stack:** SwiftUI / SwiftData @Query / Observation / PhotosUI / AVFoundation (camera) / PDFKit / Swift Charts / AuthenticationServices (already wired in Plan 2).

**Spec reference:** `/Users/lee/workspace/SnapKei/docs/superpowers/specs/2026-05-16-snapkei-mvp-design.md`

**Depends on:** Plan 1 (data layer) + Plan 2 (AI + Auth).

**Manual prerequisites (Phase 4 start):**
- Enable **Sign in with Apple** capability in the Xcode project (Signing & Capabilities → + → Sign in with Apple)
- Add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` keys to the auto-generated Info.plist via build settings (`GENERATE_INFOPLIST_FILE = YES`, so use `INFOPLIST_KEY_*` settings)

**User preferences:**
- No `git push`
- Commit steps are checkpoints only; the executing agent must ask for explicit confirmation before running `git commit`
- App icon design is out of scope (Phase 6 has a placeholder task)

**Execution corrections from review:**
- Prefer automated project edits for Info.plist build settings and entitlements; only pause for Xcode UI if Sign in with Apple capability cannot be created reliably.
- Treat shell snippets as intent, not mandatory mechanics. In assistant environments, use safer file/edit/search tools where required.
- App icon remains an optional manual/design step and must not block code verification.

---

## File Structure (created/modified by this plan)

```
/Users/lee/workspace/SnapKei/
├── SnapKei.xcodeproj/project.pbxproj                  [MODIFY: add 2 INFOPLIST_KEY_* + SIWA entitlement]
├── SnapKei/
│   ├── App/SnapKeiApp.swift                           [MODIFY: inject AIRouter via environment]
│   ├── Data/
│   │   ├── Storage/ImageStorageService.swift          [CREATE]
│   │   └── PDFImport/ElectronicReceiptImporter.swift  [CREATE]
│   ├── Domain/
│   │   └── Services/
│   │       ├── PDFReportService.swift                 [CREATE]
│   │       └── CSVExportService.swift                 [CREATE]
│   ├── Presentation/
│   │   ├── RootView.swift                             [MODIFY: replace placeholder with real tabs]
│   │   ├── Capture/
│   │   │   ├── CaptureView.swift                      [CREATE]
│   │   │   ├── CaptureViewModel.swift                 [CREATE]
│   │   │   ├── ImageSourcePicker.swift                [CREATE]
│   │   │   ├── ConfirmationForm.swift                 [CREATE]
│   │   │   ├── TreatmentSuggestionBanner.swift        [CREATE]
│   │   │   └── InputDeadlineWarning.swift             [CREATE]
│   │   ├── Home/
│   │   │   ├── HomeView.swift                         [CREATE]
│   │   │   └── HomeViewModel.swift                    [CREATE]
│   │   ├── ExpenseList/
│   │   │   ├── ExpenseListView.swift                  [CREATE]
│   │   │   ├── ExpenseListViewModel.swift             [CREATE]
│   │   │   └── ExpenseFilterSheet.swift               [CREATE]
│   │   └── Settings/
│   │       ├── SettingsView.swift                     [CREATE]
│   │       ├── SettingsViewModel.swift                [CREATE]
│   │       ├── BusinessInfoSection.swift              [CREATE]
│   │       ├── AISettingsSection.swift                [CREATE]
│   │       ├── FixedAssetSection.swift                [CREATE]
│   │       ├── HouseholdAllocationSection.swift       [CREATE]
│   │       └── ComplianceSection.swift                [CREATE]
│   └── Resources/Localizable.xcstrings                [MODIFY: full zh + ja strings]
└── README.md                                          [CREATE — user-facing readme]
```

---

# Phase 4: Capture UI (核心 golden path)

## Task 4.1: Enable SIWA capability + Info.plist permission keys (automated first, Xcode UI fallback)

> **Agentic workers:** first try to create the entitlements file and project build settings programmatically. If SIWA capability linking is not reliable, pause here and surface the Xcode UI fallback to the user.

- [ ] **Step 1: Enable or verify SIWA capability**

Preferred automated outcome:
- `SnapKei.entitlements` exists.
- The app target build settings reference the entitlements file.
- The entitlements file contains `com.apple.developer.applesignin`.

If automation is not feasible, use the manual fallback:

User instructions:
1. Open `/Users/lee/workspace/SnapKei/SnapKei.xcodeproj` in Xcode
2. Select the **SnapKei** target → **Signing & Capabilities** tab
3. Click **+ Capability**, search for **Sign in with Apple**, double-click to add
4. Save (⌘S) — Xcode creates `SnapKei.entitlements` and links it

- [ ] **Step 2: Add Info.plist permission keys to build settings**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
plutil -p SnapKei.xcodeproj/project.pbxproj 2>/dev/null >/dev/null; \
ed -s SnapKei.xcodeproj/project.pbxproj <<'EOF' || true
,s|GENERATE_INFOPLIST_FILE = YES;|GENERATE_INFOPLIST_FILE = YES;\
				INFOPLIST_KEY_NSCameraUsageDescription = "領収書を撮影するためにカメラを使用します。";\
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "領収書画像を選択するために写真ライブラリにアクセスします。";|g
w
q
EOF
```

> **If `ed` errors / pbxproj corrupted:** revert with `git checkout SnapKei.xcodeproj/project.pbxproj` and add the keys manually via Xcode UI (Target → Build Settings → search "Info.plist" → "Camera Usage Description" and "Photo Library Usage Description").

- [ ] **Step 3: Verify entitlements file exists**

Run:
```bash
ls /Users/lee/workspace/SnapKei/SnapKei.entitlements 2>&1 || \
ls /Users/lee/workspace/SnapKei/SnapKei/SnapKei.entitlements 2>&1
```
Expected: file exists (location depends on Xcode version).

- [ ] **Step 4: Build sanity check**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

---

## Task 4.2: ImageStorageService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/Storage/ImageStorageService.swift`

- [ ] **Step 1: Write ImageStorageService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/Storage/ImageStorageService.swift`:
```swift
import Foundation
import CryptoKit

public enum ImageStorageService {

    public struct Result {
        public let relativePath: String   // e.g. "receipts/2026/2026-05-16_174523_a1b2c3d4.jpg"
        public let sha256Hex: String
    }

    public enum Error: Swift.Error {
        case directoryCreationFailed
        case writeFailed
    }

    /// 領収書画像を `Documents/receipts/{fiscalYear}/{filename}` に保存し、SHA256 と相対パスを返す。
    public static func persist(
        jpegData: Data,
        fiscalYear: Int,
        transactionDate: Date,
        fileExtension: String = "jpg"
    ) throws -> Result {

        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = documents
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = makeFilename(transactionDate: transactionDate, extension: fileExtension)
        let url = dir.appendingPathComponent(filename)

        do {
            try jpegData.write(to: url, options: [.atomic])
        } catch {
            throw Error.writeFailed
        }

        let hash = SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined()
        let relativePath = "receipts/\(fiscalYear)/\(filename)"
        return Result(relativePath: relativePath, sha256Hex: hash)
    }

    public static func absoluteURL(for relativePath: String) -> URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return nil }
        return documents.appendingPathComponent(relativePath)
    }

    public static func verifyIntegrity(at relativePath: String, expectedHash: String) -> Bool {
        guard let url = absoluteURL(for: relativePath),
              let data = try? Data(contentsOf: url) else { return false }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expectedHash
    }

    private static func makeFilename(transactionDate: Date, extension ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let datePart = f.string(from: transactionDate)
        let shortId = UUID().uuidString.prefix(8).lowercased()
        return "\(datePart)_\(shortId).\(ext)"
    }
}
```

---

## Task 4.3: ImageStorageService tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/ImageStorageServiceTests.swift`

- [ ] **Step 1: Write ImageStorageServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/ImageStorageServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("ImageStorageService")
struct ImageStorageServiceTests {

    @Test func persist_writesFile_and_returnsHashAndPath() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04])
        let result = try ImageStorageService.persist(
            jpegData: data, fiscalYear: 2026, transactionDate: Date()
        )
        #expect(result.relativePath.hasPrefix("receipts/2026/"))
        #expect(result.relativePath.hasSuffix(".jpg"))
        #expect(result.sha256Hex.count == 64)

        let url = ImageStorageService.absoluteURL(for: result.relativePath)!
        let read = try Data(contentsOf: url)
        #expect(read == data)
    }

    @Test func verifyIntegrity_matchingHash_true() throws {
        let data = Data(repeating: 0xAB, count: 256)
        let result = try ImageStorageService.persist(
            jpegData: data, fiscalYear: 2026, transactionDate: Date()
        )
        #expect(ImageStorageService.verifyIntegrity(at: result.relativePath, expectedHash: result.sha256Hex) == true)
    }

    @Test func verifyIntegrity_differentHash_false() throws {
        let data = Data(repeating: 0xAB, count: 256)
        let result = try ImageStorageService.persist(
            jpegData: data, fiscalYear: 2026, transactionDate: Date()
        )
        #expect(ImageStorageService.verifyIntegrity(at: result.relativePath, expectedHash: "wrong") == false)
    }

    @Test func filename_containsDateAndShortUUID() throws {
        let date = ISO8601DateFormatter().date(from: "2026-05-16T17:45:23+09:00")!
        let result = try ImageStorageService.persist(
            jpegData: Data([0x00]), fiscalYear: 2026, transactionDate: date
        )
        // receipts/2026/2026-05-16_174523_xxxxxxxx.jpg
        #expect(result.relativePath.contains("2026-05-16_174523_"))
    }
}
```

---

## Task 4.4: ElectronicReceiptImporter.swift (PDF → image)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Data/PDFImport/ElectronicReceiptImporter.swift`

- [ ] **Step 1: Write ElectronicReceiptImporter.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Data/PDFImport/ElectronicReceiptImporter.swift`:
```swift
import Foundation
#if canImport(UIKit)
import UIKit
import PDFKit

public enum ElectronicReceiptImporter {

    public struct Result {
        public let jpegData: Data
        public let originalPDFRelativePath: String
        public let originalPDFHash: String
    }

    public enum Error: Swift.Error {
        case cannotOpenPDF
        case noPages
        case renderFailed
    }

    /// PDF 1 ページ目を画像化し、原 PDF も `Documents/receipts/electronic/{year}/` に保存。
    public static func process(pdfURL: URL, fiscalYear: Int, transactionDate: Date) throws -> Result {
        guard let pdf = PDFDocument(url: pdfURL) else { throw Error.cannotOpenPDF }
        guard let page = pdf.page(at: 0) else { throw Error.noPages }

        // 1 ページ目を 200dpi 相当でレンダリング（A4 = 1654×2339 px）
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 200.0 / 72.0  // PDF は 72 DPI 基準
        let pixelSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pageRect.size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0, y: pageRect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { throw Error.renderFailed }

        // 原 PDF を保存
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = documents
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent("electronic", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let filename = "\(f.string(from: transactionDate))_\(UUID().uuidString.prefix(8).lowercased()).pdf"
        let dest = dir.appendingPathComponent(filename)

        let originalData = (try? Data(contentsOf: pdfURL)) ?? Data()
        try originalData.write(to: dest, options: [.atomic])

        let hash = originalData.isEmpty ? "" :
            originalData.withUnsafeBytes { _ in
                originalData.sha256Hex()
            }

        return Result(
            jpegData: jpeg,
            originalPDFRelativePath: "receipts/electronic/\(fiscalYear)/\(filename)",
            originalPDFHash: hash
        )
    }
}

import CryptoKit
private extension Data {
    func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
```

---

## Task 4.5: CaptureViewModel.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/CaptureViewModel.swift`

- [ ] **Step 1: Write CaptureViewModel.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/CaptureViewModel.swift`:
```swift
import Foundation
import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
public final class CaptureViewModel {

    public enum Stage: Equatable {
        case idle
        case parsing
        case confirming(ReceiptDraft)
        case error(String)
        case saved
    }

    public var stage: Stage = .idle
    public var pickedImage: UIImage?
    public var pickedPDFURL: URL?
    public var receiptImagePath: String?
    public var receiptImageHash: String?

    private let aiRouter: AIRouter
    private let repository: ExpenseRepository
    private let appSettings: () -> AppSettings
    private let aiSettings: () -> AISettings

    public init(
        aiRouter: AIRouter,
        repository: ExpenseRepository,
        appSettings: @escaping () -> AppSettings,
        aiSettings: @escaping () -> AISettings
    ) {
        self.aiRouter = aiRouter
        self.repository = repository
        self.appSettings = appSettings
        self.aiSettings = aiSettings
    }

    public func handlePickedImage(_ image: UIImage) async {
        pickedImage = image
        pickedPDFURL = nil
        stage = .parsing

        do {
            let maxBytes = aiSettings().maxImageBytes
            let processed = try ReceiptImageProcessor.process(image, maxBytes: maxBytes)
            let draft = try await aiRouter.parse(
                imageData: processed.jpegData, mimeType: processed.mimeType
            )
            // Persist image (use draft.transactionDate if present, else today)
            let txDate = draft.transactionDate ?? Date()
            let fy = fiscalYear(for: txDate)
            let stored = try ImageStorageService.persist(
                jpegData: processed.jpegData, fiscalYear: fy, transactionDate: txDate
            )
            receiptImagePath = stored.relativePath
            receiptImageHash = stored.sha256Hex
            stage = .confirming(draft)
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    public func handlePickedPDF(_ url: URL) async {
        pickedImage = nil
        pickedPDFURL = url
        stage = .parsing

        do {
            let txDateGuess = Date()
            let fy = fiscalYear(for: txDateGuess)
            let imported = try ElectronicReceiptImporter.process(
                pdfURL: url, fiscalYear: fy, transactionDate: txDateGuess
            )
            let draft = try await aiRouter.parse(
                imageData: imported.jpegData, mimeType: "image/jpeg"
            )
            receiptImagePath = imported.originalPDFRelativePath
            receiptImageHash = imported.originalPDFHash
            stage = .confirming(draft)
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    public func saveConfirmed(_ entry: JournalEntry) {
        do {
            try repository.create(entry, reason: nil)
            stage = .saved
        } catch {
            stage = .error("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    public func reset() {
        stage = .idle
        pickedImage = nil
        pickedPDFURL = nil
        receiptImagePath = nil
        receiptImageHash = nil
    }

    private func fiscalYear(for date: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let startMonth = appSettings().fiscalYearStartMonth
        return month >= startMonth ? year : year - 1
    }
}
```

---

## Task 4.6: ImageSourcePicker.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/ImageSourcePicker.swift`

- [ ] **Step 1: Write ImageSourcePicker.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/ImageSourcePicker.swift`:
```swift
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct ImageSourcePicker: View {

    public enum Source: Identifiable {
        case camera
        case album
        case pdf
        public var id: String {
            switch self {
            case .camera: return "camera"
            case .album:  return "album"
            case .pdf:    return "pdf"
            }
        }
    }

    @Binding public var sheetSource: Source?
    public var onImagePicked: (UIImage) -> Void
    public var onPDFPicked: (URL) -> Void

    public init(
        sheetSource: Binding<Source?>,
        onImagePicked: @escaping (UIImage) -> Void,
        onPDFPicked: @escaping (URL) -> Void
    ) {
        self._sheetSource = sheetSource
        self.onImagePicked = onImagePicked
        self.onPDFPicked = onPDFPicked
    }

    public var body: some View {
        VStack(spacing: 12) {
            Button {
                sheetSource = .camera
            } label: {
                Label("撮影", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                sheetSource = .album
            } label: {
                Label("アルバム", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                sheetSource = .pdf
            } label: {
                Label("PDF をインポート", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .sheet(item: $sheetSource) { source in
            switch source {
            case .camera: CameraPicker { onImagePicked($0); sheetSource = nil }
            case .album:  PhotoLibraryPicker { onImagePicked($0); sheetSource = nil }
            case .pdf:    DocumentPicker(contentTypes: [.pdf]) { onPDFPicked($0); sheetSource = nil }
            }
        }
    }
}

// MARK: - UIKit Wrappers

private struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage { onPicked(img) }
        }
    }
}

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let p = PHPickerViewController(configuration: config)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage {
                    DispatchQueue.main.async { self.onPicked(img) }
                }
            }
        }
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        p.delegate = context.coordinator
        p.allowsMultipleSelection = false
        return p
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}
```

---

## Task 4.7: TreatmentSuggestionBanner + InputDeadlineWarning

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/TreatmentSuggestionBanner.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/InputDeadlineWarning.swift`

- [ ] **Step 1: Write TreatmentSuggestionBanner.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/TreatmentSuggestionBanner.swift`:
```swift
import SwiftUI

public struct TreatmentSuggestionBanner: View {
    public let amount: Int
    public let transactionDate: Date
    @Binding public var registerAsFixedAsset: Bool

    public init(amount: Int, transactionDate: Date, registerAsFixedAsset: Binding<Bool>) {
        self.amount = amount
        self.transactionDate = transactionDate
        self._registerAsFixedAsset = registerAsFixedAsset
    }

    public var body: some View {
        if let treatment = ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: transactionDate) {
            VStack(alignment: .leading, spacing: 8) {
                Label(headline(for: treatment), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(detail(for: treatment))
                    .font(.footnote)
                Toggle("固定資産台帳に登録する", isOn: $registerAsFixedAsset)
            }
            .padding()
            .background(Color.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func headline(for t: AssetTreatment) -> String {
        switch t {
        case .lumpSumDepreciation:    return "一括償却資産の対象です"
        case .smallAmountFullExpense: return "少額減価償却特例の対象です（青色限定）"
        case .normalDepreciation:     return "通常の減価償却が必要です"
        }
    }

    private func detail(for t: AssetTreatment) -> String {
        switch t {
        case .lumpSumDepreciation:
            return "10–20 万円未満の固定資産は 3 年均等償却が選択可能です。"
        case .smallAmountFullExpense:
            return "20–40 万円未満の固定資産は青色申告者の特例で一括費用化できます（年 300 万円上限、令和10年度末まで）。"
        case .normalDepreciation:
            return "取得価額 40 万円以上は耐用年数に応じた減価償却が必要です。"
        }
    }
}
```

- [ ] **Step 2: Write InputDeadlineWarning.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/InputDeadlineWarning.swift`:
```swift
import SwiftUI

public struct InputDeadlineWarning: View {
    public let transactionDate: Date

    public init(transactionDate: Date) {
        self.transactionDate = transactionDate
    }

    public var body: some View {
        let days = ComplianceService.daysUntilScanDeadline(receiptDate: transactionDate)
        if days < 0 {
            warningBlock(color: .red,
                         icon: "xmark.octagon.fill",
                         title: "電帳法スキャナ保存期限切れ",
                         detail: "受領後 2 ヶ月＋約 7 営業日を経過しています。紙の原本を保管してください。")
        } else if days < 14 {
            warningBlock(color: .orange,
                         icon: "exclamationmark.triangle.fill",
                         title: "スキャナ保存期限まで残り \(days) 日",
                         detail: "期限内に入力を完了してください。")
        } else {
            EmptyView()
        }
    }

    private func warningBlock(color: Color, icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).foregroundStyle(color).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

---

## Task 4.8: ConfirmationForm.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/ConfirmationForm.swift`

- [ ] **Step 1: Write ConfirmationForm.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/ConfirmationForm.swift`:
```swift
import SwiftUI
import SwiftData

public struct ConfirmationForm: View {
    @Binding public var draft: ReceiptDraft
    public let receiptImagePath: String?
    public let receiptImageHash: String?
    public let onSave: (JournalEntry) -> Void

    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var transactionDate: Date = Date()
    @State private var amountIncludingTaxText: String = ""
    @State private var taxRate: Double = 0.10
    @State private var priceEntryMode: PriceEntryMode = .taxIncluded
    @State private var taxCategory: TaxCategory = .standard10
    @State private var paymentMethod: PaymentMethod = .ownerLoan
    @State private var counterpartyName: String = ""
    @State private var transactionDescription: String = ""
    @State private var debitAccountCode: String = "5290"
    @State private var creditAccountCode: String = "3210"
    @State private var invoiceRegistrationNumber: String = ""
    @State private var businessAllocationRate: Double = 1.0
    @State private var registerAsFixedAsset: Bool = false

    public init(
        draft: Binding<ReceiptDraft>,
        receiptImagePath: String?,
        receiptImageHash: String?,
        onSave: @escaping (JournalEntry) -> Void
    ) {
        self._draft = draft
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            InputDeadlineWarning(transactionDate: transactionDate)

            if let amount = Int(amountIncludingTaxText), amount > 0 {
                TreatmentSuggestionBanner(
                    amount: amount,
                    transactionDate: transactionDate,
                    registerAsFixedAsset: $registerAsFixedAsset
                )
            }

            Section("取引") {
                DatePicker("取引日", selection: $transactionDate, displayedComponents: .date)
                TextField("取引先", text: $counterpartyName)
                TextField("取引内容", text: $transactionDescription)
            }

            Section("金額") {
                TextField("税込金額", text: $amountIncludingTaxText)
                    .keyboardType(.numberPad)
                Picker("税率", selection: $taxRate) {
                    Text("10%").tag(0.10)
                    Text("8% (軽減)").tag(0.08)
                    Text("0% (非課税)").tag(0.00)
                }
                Picker("税抜/税込", selection: $priceEntryMode) {
                    Text("税込").tag(PriceEntryMode.taxIncluded)
                    Text("税抜").tag(PriceEntryMode.taxExcluded)
                }
            }

            Section("仕訳") {
                Picker("借方科目", selection: $debitAccountCode) {
                    ForEach(accounts.filter { $0.accountType == .expense }) { acc in
                        Text("\(acc.code) \(acc.nameJa)").tag(acc.code)
                    }
                }
                Picker("貸方科目", selection: $creditAccountCode) {
                    ForEach(accounts.filter { $0.accountType == .asset || $0.accountType == .liability || $0.accountType == .equity }) { acc in
                        Text("\(acc.code) \(acc.nameJa)").tag(acc.code)
                    }
                }
                Picker("支払方法", selection: $paymentMethod) {
                    Text("現金").tag(PaymentMethod.cash)
                    Text("クレジット").tag(PaymentMethod.creditCard)
                    Text("銀行振込").tag(PaymentMethod.bankTransfer)
                    Text("事業主借").tag(PaymentMethod.ownerLoan)
                    Text("その他").tag(PaymentMethod.other)
                }
            }

            Section("インボイス") {
                TextField("適格番号 (T+13桁)", text: $invoiceRegistrationNumber)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
            }

            Section("家事按分") {
                Slider(value: $businessAllocationRate, in: 0...1, step: 0.1) {
                    Text("事業按分率")
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                Text("\(Int(businessAllocationRate * 100))%")
                if businessAllocationRate < 1.0, let amount = Int(amountIncludingTaxText) {
                    Text("仕訳計上額: ¥\(Int(Double(amount) * businessAllocationRate))")
                        .foregroundStyle(.secondary).font(.footnote)
                }
            }

            Section {
                Button("保存") { save() }
                    .frame(maxWidth: .infinity)
                    .disabled(!isValid)
            }

            if let raw = draft.rawAIResponse {
                Section("AI 応答（デバッグ）") {
                    Text(raw).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("仕訳確認")
        .onAppear(perform: applyDraft)
    }

    private var isValid: Bool {
        guard let amount = Int(amountIncludingTaxText), amount > 0 else { return false }
        return !counterpartyName.isEmpty && !transactionDescription.isEmpty
    }

    private func applyDraft() {
        if let d = draft.transactionDate { transactionDate = d }
        if let a = draft.amountIncludingTax { amountIncludingTaxText = String(a) }
        if let r = draft.taxRate { taxRate = r }
        if let m = draft.priceEntryMode { priceEntryMode = m }
        if let c = draft.taxCategory { taxCategory = c }
        if let p = draft.paymentMethod { paymentMethod = p }
        counterpartyName = draft.counterpartyName ?? ""
        transactionDescription = draft.transactionDescription ?? ""
        invoiceRegistrationNumber = draft.invoiceRegistrationNumber ?? ""
        if let d = draft.suggestedDebitAccountCode { debitAccountCode = d }
        if let c = draft.suggestedCreditAccountCode { creditAccountCode = c }
    }

    private func save() {
        guard let amount = Int(amountIncludingTaxText) else { return }
        let cal = Calendar(identifier: .gregorian)
        let fiscalYear = cal.component(.year, from: transactionDate)
        let isQualified = invoiceRegistrationNumber.hasPrefix("T") && invoiceRegistrationNumber.count == 14
        let rate = ComplianceService.transitionalRate(qualified: isQualified, transactionDate: transactionDate)

        // tax 計算
        let (excl, tax): (Int, Int) = {
            if priceEntryMode == .taxIncluded {
                let e = Int(Double(amount) / (1 + taxRate))
                return (e, amount - e)
            } else {
                let t = Int(Double(amount) * taxRate)
                return (amount, t)
            }
        }()
        let total = priceEntryMode == .taxIncluded ? amount : (amount + tax)

        // 家事按分後の金額
        let allocatedTotal = Int(Double(total) * businessAllocationRate)
        let allocatedExcl  = Int(Double(excl)  * businessAllocationRate)
        let allocatedTax   = Int(Double(tax)   * businessAllocationRate)

        let entry = JournalEntry(
            entryNumber: 0,  // repo が確定
            fiscalYear: fiscalYear,
            transactionDate: transactionDate,
            debitAccountCode: debitAccountCode,
            creditAccountCode: creditAccountCode,
            amountIncludingTax: allocatedTotal,
            amountExcludingTax: allocatedExcl,
            consumptionTax: allocatedTax,
            taxCategory: taxCategory,
            priceEntryMode: priceEntryMode,
            paymentMethod: paymentMethod,
            counterpartyName: counterpartyName,
            invoiceRegistrationNumber: invoiceRegistrationNumber.isEmpty ? nil : invoiceRegistrationNumber,
            invoiceQualified: isQualified,
            transitionalMeasureRate: rate,
            transactionDescription: transactionDescription,
            businessAllocationRate: businessAllocationRate,
            originalAmountIncludingTax: businessAllocationRate < 1.0 ? total : nil,
            receiptImagePath: receiptImagePath,
            receiptImageHash: receiptImageHash,
            sourceType: .aiParsed
        )
        onSave(entry)
    }
}
```

---

## Task 4.9: CaptureView.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/CaptureView.swift`

- [ ] **Step 1: Write CaptureView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Capture/CaptureView.swift`:
```swift
import SwiftUI

public struct CaptureView: View {
    @State private var sheetSource: ImageSourcePicker.Source?
    @Bindable public var viewModel: CaptureViewModel

    public init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ChannelStatusBar(channel: viewModel.currentChannelDescription)

                switch viewModel.stage {
                case .idle:
                    Spacer()
                    Text("領収書を撮影またはインポート").foregroundStyle(.secondary)
                    Spacer()
                    ImageSourcePicker(
                        sheetSource: $sheetSource,
                        onImagePicked: { img in
                            Task { await viewModel.handlePickedImage(img) }
                        },
                        onPDFPicked: { url in
                            Task { await viewModel.handlePickedPDF(url) }
                        }
                    )

                case .parsing:
                    Spacer()
                    ProgressView("AI が解析中…").progressViewStyle(.circular).controlSize(.large)
                    Spacer()

                case .confirming(let draft):
                    ConfirmationFormWrapper(
                        initialDraft: draft,
                        receiptImagePath: viewModel.receiptImagePath,
                        receiptImageHash: viewModel.receiptImageHash,
                        onSave: { entry in viewModel.saveConfirmed(entry) }
                    )

                case .error(let msg):
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(msg).multilineTextAlignment(.center).padding(.horizontal)
                        Button("やり直し") { viewModel.reset() }.buttonStyle(.borderedProminent)
                    }
                    Spacer()

                case .saved:
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle).foregroundStyle(.green)
                        Text("保存しました").font(.title2)
                        Button("次の領収書") { viewModel.reset() }.buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
            .navigationTitle("撮影・取込")
        }
    }
}

private struct ConfirmationFormWrapper: View {
    let initialDraft: ReceiptDraft
    let receiptImagePath: String?
    let receiptImageHash: String?
    let onSave: (JournalEntry) -> Void
    @State private var draft: ReceiptDraft

    init(initialDraft: ReceiptDraft, receiptImagePath: String?, receiptImageHash: String?,
         onSave: @escaping (JournalEntry) -> Void) {
        self.initialDraft = initialDraft
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ConfirmationForm(
            draft: $draft,
            receiptImagePath: receiptImagePath,
            receiptImageHash: receiptImageHash,
            onSave: onSave
        )
    }
}

private struct ChannelStatusBar: View {
    let channel: String
    var body: some View {
        HStack {
            Image(systemName: "cpu")
            Text(channel).font(.caption)
            Spacer()
            NavigationLink(value: "settings") { Image(systemName: "gearshape") }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

// MARK: - VM extension for channel display

extension CaptureViewModel {
    public var currentChannelDescription: String {
        // 簡易表示。Plan 2 の AISettings.load を呼ぶ
        let s = AISettings.load()
        switch s.aiChannel {
        case .directApiKey: return "Anthropic 直接（自前 Key）"
        case .builtInProxy: return "内蔵プロキシ（Apple サインイン）"
        }
    }
}
```

---

## Task 4.10: Phase 4 build + commit

- [ ] **Step 1: Build + test**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test 2>&1 | tail -30
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei/ SnapKei.entitlements SnapKei.xcodeproj/project.pbxproj SnapKeiTests/ && \
git commit -m "$(cat <<'EOF'
feat: Phase 4 — Capture UI golden path

- ImageStorageService (Documents/receipts/{fy}/timestamped + SHA256)
- ElectronicReceiptImporter (PDF → 200dpi rendered JPEG + original PDF stored)
- CaptureViewModel (parsing/confirming/error/saved state machine)
- ImageSourcePicker (camera / PHPicker / DocumentPicker for PDF)
- TreatmentSuggestionBanner (10/20/40万 threshold prompts)
- InputDeadlineWarning (scan deadline countdown / overdue)
- ConfirmationForm (full editable form: amount with auto tax split, 家事按分
  slider with allocated-amount preview, 適格 invoice cross-check setting
  transitional rate, debit/credit account dropdowns from Account master)
- CaptureView state-based shell + channel status bar
- Capabilities: Sign in with Apple, NSCameraUsageDescription,
  NSPhotoLibraryUsageDescription

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 5: Home / List / Settings + Reports

## Task 5.1: HomeViewModel + HomeView

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Home/HomeViewModel.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Write HomeViewModel.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Home/HomeViewModel.swift`:
```swift
import Foundation
import Observation

/// ユーザーが申告する際の路線判定。届出書 / e-Tax 利用は UserDefaults に保存。
public struct ControlRouteStatus: Sendable, Equatable {
    public var hasFiledOptimalBookNotification: Bool   // 優良電子帳簿の届出書を税務署に提出済か
    public var willUseEtax: Bool                       // e-Tax で申告予定か
    public var doubleEntryBookkeeping: Bool            // 複式簿記で記帳済（JournalEntry が 1 件以上）
    public var amendmentHistoryEnabled: Bool           // 訂正・削除履歴あり（SnapKei では常に true）
    public var searchableLedger: Bool                  // 検索機能あり（SnapKei では常に true）

    /// 上記から見込控除額を判定。
    public var estimatedDeduction: Int {
        // 75万: 複式簿記 + 履歴 + 検索 + 届出書 + e-Tax
        if doubleEntryBookkeeping && amendmentHistoryEnabled && searchableLedger
           && hasFiledOptimalBookNotification && willUseEtax {
            return 750_000
        }
        // 65万: 複式簿記 + e-Tax
        if doubleEntryBookkeeping && willUseEtax {
            return 650_000
        }
        // 10万: 複式簿記のみ
        if doubleEntryBookkeeping {
            return 100_000
        }
        return 0
    }

    private enum Keys {
        static let filed = "controlRoute.hasFiledOptimalBookNotification"
        static let etax  = "controlRoute.willUseEtax"
    }

    public static func load(
        defaults: UserDefaults = .standard,
        hasEntries: Bool
    ) -> ControlRouteStatus {
        ControlRouteStatus(
            hasFiledOptimalBookNotification: defaults.bool(forKey: Keys.filed),
            willUseEtax: defaults.bool(forKey: Keys.etax),
            doubleEntryBookkeeping: hasEntries,
            amendmentHistoryEnabled: true,
            searchableLedger: true
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(hasFiledOptimalBookNotification, forKey: Keys.filed)
        defaults.set(willUseEtax, forKey: Keys.etax)
    }
}

@MainActor
@Observable
public final class HomeViewModel {

    public struct MonthlySummary {
        public let entryCount: Int
        public let totalIncludingTax: Int
        public let totalConsumptionTax: Int
    }

    public struct AccountTotal: Identifiable {
        public let id: String   // account code
        public let name: String
        public let amount: Int
    }

    private let repository: ExpenseRepository

    public init(repository: ExpenseRepository) {
        self.repository = repository
    }

    public func controlRouteStatus() throws -> ControlRouteStatus {
        let any = try repository.search(criteria: ExpenseSearchCriteria())
        return ControlRouteStatus.load(hasEntries: !any.isEmpty)
    }

    public func monthlySummary(year: Int, month: Int) throws -> MonthlySummary {
        let cal = Calendar(identifier: .gregorian)
        let from = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let to = cal.date(byAdding: DateComponents(month: 1, day: -1), to: from)!
        let entries = try repository.search(criteria: ExpenseSearchCriteria(dateFrom: from, dateTo: to))
        return MonthlySummary(
            entryCount: entries.count,
            totalIncludingTax: entries.reduce(0) { $0 + $1.amountIncludingTax },
            totalConsumptionTax: entries.reduce(0) { $0 + $1.consumptionTax }
        )
    }

    public func byDebitAccount(year: Int, month: Int, accountLookup: (String) -> String) throws -> [AccountTotal] {
        let cal = Calendar(identifier: .gregorian)
        let from = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let to = cal.date(byAdding: DateComponents(month: 1, day: -1), to: from)!
        let entries = try repository.search(criteria: ExpenseSearchCriteria(dateFrom: from, dateTo: to))
        let grouped = Dictionary(grouping: entries, by: \.debitAccountCode)
        return grouped.map { code, list in
            AccountTotal(id: code, name: accountLookup(code), amount: list.reduce(0) { $0 + $1.amountIncludingTax })
        }
        .sorted { $0.amount > $1.amount }
    }

    public func overdueEntries() throws -> [JournalEntry] {
        let all = try repository.search(criteria: ExpenseSearchCriteria())
        let now = Date()
        return all.filter { ComplianceService.daysUntilScanDeadline(receiptDate: $0.transactionDate, today: now) < 14 }
    }

    public func recentEntries(limit: Int = 5) throws -> [JournalEntry] {
        let all = try repository.search(criteria: ExpenseSearchCriteria())
        return Array(all.prefix(limit))
    }
}
```

- [ ] **Step 2: Write HomeView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Home/HomeView.swift`:
```swift
import SwiftUI
import SwiftData
import Charts

public struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var summary: HomeViewModel.MonthlySummary?
    @State private var byAccount: [HomeViewModel.AccountTotal] = []
    @State private var overdue: [JournalEntry] = []
    @State private var recent: [JournalEntry] = []
    @State private var controlRoute: ControlRouteStatus?

    public init() {}

    @ViewBuilder
    private func routeRow(_ text: String, checked: Bool) -> some View {
        Label(text, systemImage: checked ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(checked ? .green : .secondary)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("今月の概要") {
                    if let s = summary {
                        HStack { Text("件数"); Spacer(); Text("\(s.entryCount) 件") }
                        HStack { Text("税込合計"); Spacer(); Text("¥\(s.totalIncludingTax)") }
                        HStack { Text("消費税"); Spacer(); Text("¥\(s.totalConsumptionTax)") }
                    } else {
                        Text("計算中…").foregroundStyle(.secondary)
                    }
                }

                Section("控除路線") {
                    if let route = controlRoute {
                        routeRow("複式簿記での記帳", checked: route.doubleEntryBookkeeping)
                        routeRow("訂正・削除履歴（優良要件①）", checked: route.amendmentHistoryEnabled)
                        routeRow("帳簿間相互関連性 + 検索機能（優良要件②③）", checked: route.searchableLedger)
                        routeRow("届出書 提出済（優良要件④、税務署へ）", checked: route.hasFiledOptimalBookNotification)
                        routeRow("e-Tax で申告予定（MVP は外部ソフト経由）", checked: route.willUseEtax)
                        HStack {
                            Text("見込控除額").font(.headline)
                            Spacer()
                            Text("¥\(route.estimatedDeduction)").font(.title3.monospacedDigit().weight(.bold))
                                .foregroundStyle(route.estimatedDeduction >= 650_000 ? .green : .primary)
                        }
                    }
                }

                if !overdue.isEmpty {
                    Section("入力期限警告") {
                        ForEach(overdue) { e in
                            VStack(alignment: .leading) {
                                Text(e.counterpartyName).font(.subheadline.weight(.semibold))
                                Text("取引日 \(e.transactionDate, format: .dateTime.year().month().day())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !byAccount.isEmpty {
                    Section("科目別（今月）") {
                        Chart(byAccount) { item in
                            SectorMark(
                                angle: .value("金額", item.amount),
                                innerRadius: .ratio(0.5)
                            )
                            .foregroundStyle(by: .value("科目", item.name))
                        }
                        .frame(height: 220)
                    }
                }

                Section("直近の取引") {
                    ForEach(recent) { e in
                        VStack(alignment: .leading) {
                            Text(e.counterpartyName).font(.subheadline.weight(.semibold))
                            Text("\(e.transactionDescription) — ¥\(e.amountIncludingTax)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("レポート") {
                    Button("損益計算書 PDF を生成") {
                        Task { await generatePnL() }
                    }
                }
            }
            .navigationTitle("ホーム")
            .task { await refresh() }
        }
    }

    private func refresh() async {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        do {
            let repo = SwiftDataExpenseRepository(context: context, deviceId: deviceId())
            let vm = HomeViewModel(repository: repo)
            summary = try vm.monthlySummary(year: year, month: month)
            byAccount = try vm.byDebitAccount(year: year, month: month) { code in
                accounts.first(where: { $0.code == code })?.nameJa ?? code
            }
            overdue = try vm.overdueEntries()
            recent = try vm.recentEntries()
            controlRoute = try vm.controlRouteStatus()
        } catch {
            print("[HomeView] refresh failed: \(error)")
        }
    }

    private func generatePnL() async {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: Date())
        do {
            let data = try PDFReportService.renderProfitAndLoss(fiscalYear: year, context: context)
            await share(data: data, filename: "損益計算書_\(year).pdf")
        } catch {
            print("[HomeView] PDF generation failed: \(error)")
        }
    }

    private func deviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    @MainActor
    private func share(data: Data, filename: String) async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? data.write(to: url, options: [.atomic])
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(av, animated: true)
    }
}
```

---

## Task 5.2: PDFReportService.swift (P/L)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/PDFReportService.swift`

- [ ] **Step 1: Write PDFReportService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/PDFReportService.swift`:
```swift
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
import PDFKit

public enum PDFReportService {

    public enum Error: Swift.Error {
        case renderFailed
    }

    public static func renderProfitAndLoss(fiscalYear: Int, context: ModelContext) throws -> Data {
        // 1. 売上 / 経費を集計
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear && !$0.isVoided }
        ))
        let accounts = try context.fetch(FetchDescriptor<Account>())

        var revenueByCode: [String: Int] = [:]
        var expenseByCode: [String: Int] = [:]
        for e in entries {
            // 借方が費用 / 貸方が収益という convention（個人事業主標準）
            if let acc = accounts.first(where: { $0.code == e.debitAccountCode }) {
                if acc.accountType == .expense {
                    expenseByCode[acc.code, default: 0] += e.amountIncludingTax
                }
            }
            if let acc = accounts.first(where: { $0.code == e.creditAccountCode }) {
                if acc.accountType == .revenue {
                    revenueByCode[acc.code, default: 0] += e.amountIncludingTax
                }
            }
        }

        let revenueTotal = revenueByCode.values.reduce(0, +)
        let expenseTotal = expenseByCode.values.reduce(0, +)
        let netIncome = revenueTotal - expenseTotal

        // 2. PDF 描画（A4: 595×842 pt）
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22)
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            let boldBodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12)
            ]

            "損益計算書 (\(fiscalYear) 年)".draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttrs)

            var y: CGFloat = 100
            "【売上】".draw(at: CGPoint(x: 40, y: y), withAttributes: boldBodyAttrs)
            y += 24
            for (code, amount) in revenueByCode.sorted(by: { $0.key < $1.key }) {
                let name = accounts.first(where: { $0.code == code })?.nameJa ?? code
                "\(code) \(name)".draw(at: CGPoint(x: 60, y: y), withAttributes: bodyAttrs)
                "¥\(amount)".draw(at: CGPoint(x: 450, y: y), withAttributes: bodyAttrs)
                y += 18
            }
            "売上合計".draw(at: CGPoint(x: 60, y: y), withAttributes: boldBodyAttrs)
            "¥\(revenueTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: boldBodyAttrs)
            y += 36

            "【経費】".draw(at: CGPoint(x: 40, y: y), withAttributes: boldBodyAttrs)
            y += 24
            for (code, amount) in expenseByCode.sorted(by: { $0.key < $1.key }) {
                let name = accounts.first(where: { $0.code == code })?.nameJa ?? code
                "\(code) \(name)".draw(at: CGPoint(x: 60, y: y), withAttributes: bodyAttrs)
                "¥\(amount)".draw(at: CGPoint(x: 450, y: y), withAttributes: bodyAttrs)
                y += 18
                if y > 760 { ctx.beginPage(); y = 60 }
            }
            "経費合計".draw(at: CGPoint(x: 60, y: y), withAttributes: boldBodyAttrs)
            "¥\(expenseTotal)".draw(at: CGPoint(x: 450, y: y), withAttributes: boldBodyAttrs)
            y += 36

            "所得金額".draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttrs)
            "¥\(netIncome)".draw(at: CGPoint(x: 450, y: y), withAttributes: titleAttrs)
        }

        return data
    }
}
#endif
```

---

## Task 5.3: PDFReportService tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/PDFReportServiceTests.swift`

- [ ] **Step 1: Write PDFReportServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/PDFReportServiceTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import SnapKei

@Suite("PDFReportService")
struct PDFReportServiceTests {

    @MainActor
    @Test func renderPnL_emptyYear_returnsValidPDF() throws {
        let container = try SnapKeiModelContainer.inMemory()
        AccountSeeder.seedIfNeeded(context: container.mainContext)
        let data = try PDFReportService.renderProfitAndLoss(fiscalYear: 2026, context: container.mainContext)
        #expect(data.count > 0)
        // PDF magic bytes
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }

    @MainActor
    @Test func renderPnL_withEntries_includesAccountNames() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)
        let repo = SwiftDataExpenseRepository(context: ctx, deviceId: "test")
        let e = JournalEntry(
            entryNumber: 0, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5110", creditAccountCode: "3210",
            amountIncludingTax: 1100, amountExcludingTax: 1000, consumptionTax: 100,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .ownerLoan,
            counterpartyName: "テスト", transactionDescription: "テスト", sourceType: .manual
        )
        try repo.create(e, reason: nil)

        let data = try PDFReportService.renderProfitAndLoss(fiscalYear: 2026, context: ctx)
        #expect(data.count > 1000)
    }
}
```

---

## Task 5.4: CSVExportService.swift

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/CSVExportService.swift`

- [ ] **Step 1: Write CSVExportService.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Domain/Services/CSVExportService.swift`:
```swift
import Foundation

public enum CSVExportService {

    /// 弥生 / freee で「科目名」マッピング前提の CSV（UTF-8 BOM 付き、RFC 4180）。
    /// SnapKei の独自 4 桁コードは出さず、日本語科目名を出力する。
    /// - Parameter accountNameLookup: code → nameJa を返すクロージャ（呼び出し側で Account master を捕捉）
    public static func export(
        _ entries: [JournalEntry],
        accountNameLookup: (String) -> String
    ) -> Data {
        var out = "\u{FEFF}日付,借方科目,貸方科目,取引内容,取引先,税込金額,税抜金額,消費税,適格番号,備考\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd"
        df.timeZone = TimeZone(identifier: "Asia/Tokyo")
        for e in entries {
            let row = [
                df.string(from: e.transactionDate),
                escape(accountNameLookup(e.debitAccountCode)),
                escape(accountNameLookup(e.creditAccountCode)),
                escape(e.transactionDescription),
                escape(e.counterpartyName),
                String(e.amountIncludingTax),
                String(e.amountExcludingTax),
                String(e.consumptionTax),
                e.invoiceRegistrationNumber ?? "",
                escape(e.memo ?? "")
            ].joined(separator: ",")
            out.append(row + "\n")
        }
        return out.data(using: .utf8) ?? Data()
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }
}
```

---

## Task 5.5: CSV tests

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKeiTests/CSVExportServiceTests.swift`

- [ ] **Step 1: Write CSVExportServiceTests.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKeiTests/CSVExportServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import SnapKei

@Suite("CSVExportService")
struct CSVExportServiceTests {

    private func makeEntry(counterparty: String = "セブン", desc: String = "コーヒー", memo: String? = nil) -> JournalEntry {
        JournalEntry(
            entryNumber: 1, fiscalYear: 2026, transactionDate: Date(),
            debitAccountCode: "5140", creditAccountCode: "1110",
            amountIncludingTax: 220, amountExcludingTax: 200, consumptionTax: 20,
            taxCategory: .standard10, priceEntryMode: .taxIncluded, paymentMethod: .cash,
            counterpartyName: counterparty, transactionDescription: desc, memo: memo,
            sourceType: .manual
        )
    }

    private let lookup: (String) -> String = { code in
        switch code {
        case "5140": return "消耗品費"
        case "1110": return "現金"
        default:     return code
        }
    }

    @Test func export_emptyEntries_returnsHeaderOnly() {
        let data = CSVExportService.export([], accountNameLookup: lookup)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("日付,借方科目,貸方科目"))
        #expect(s.components(separatedBy: "\n").count == 2)
    }

    @Test func export_outputsAccountNameNotCode() {
        let data = CSVExportService.export([makeEntry()], accountNameLookup: lookup)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("消耗品費"))
        #expect(s.contains("現金"))
        #expect(!s.contains(",5140,"))   // コードは出ないことを確認
    }

    @Test func export_specialChars_areEscaped() {
        let entry = makeEntry(counterparty: "店、A", desc: "「コーヒー」")
        let data = CSVExportService.export([entry], accountNameLookup: lookup)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("\"店、A\""))
    }

    @Test func export_quoteChar_isDoubled() {
        let entry = makeEntry(desc: #"He said "hello""#)
        let data = CSVExportService.export([entry], accountNameLookup: lookup)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("He said \"\"hello\"\""))
    }

    @Test func export_hasBOM() {
        let data = CSVExportService.export([makeEntry()], accountNameLookup: lookup)
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
    }
}
```

---

## Task 5.6: ExpenseFilterSheet + ExpenseListViewModel + ExpenseListView

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseListViewModel.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseFilterSheet.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseListView.swift`

- [ ] **Step 1: Write ExpenseListViewModel.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseListViewModel.swift`:
```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class ExpenseListViewModel {
    public var searchText: String = ""
    public var criteria: ExpenseSearchCriteria = .init()
    public var entries: [JournalEntry] = []

    private let repository: ExpenseRepository

    public init(repository: ExpenseRepository) {
        self.repository = repository
    }

    public func refresh() {
        do {
            var results = try repository.search(criteria: criteria)
            if !searchText.isEmpty {
                let term = searchText
                results = results.filter {
                    $0.counterpartyName.localizedCaseInsensitiveContains(term) ||
                    $0.transactionDescription.localizedCaseInsensitiveContains(term)
                }
            }
            entries = results
        } catch {
            entries = []
        }
    }

    public var totalAmount: Int {
        entries.reduce(0) { $0 + $1.amountIncludingTax }
    }
}
```

- [ ] **Step 2: Write ExpenseFilterSheet.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseFilterSheet.swift`:
```swift
import SwiftUI
import SwiftData

public struct ExpenseFilterSheet: View {
    @Binding public var criteria: ExpenseSearchCriteria
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var useDateRange = false
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var useAmountRange = false
    @State private var amountMin: String = ""
    @State private var amountMax: String = ""
    @State private var selectedAccounts: Set<String> = []
    @State private var qualifiedOnly = false
    @State private var lateEntryOnly = false
    @State private var includeVoided = false
    @Environment(\.dismiss) private var dismiss

    public init(criteria: Binding<ExpenseSearchCriteria>) {
        self._criteria = criteria
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("期間") {
                    Toggle("期間を指定", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("開始", selection: $dateFrom, displayedComponents: .date)
                        DatePicker("終了", selection: $dateTo, displayedComponents: .date)
                    }
                }
                Section("金額") {
                    Toggle("金額範囲", isOn: $useAmountRange)
                    if useAmountRange {
                        TextField("下限", text: $amountMin).keyboardType(.numberPad)
                        TextField("上限", text: $amountMax).keyboardType(.numberPad)
                    }
                }
                Section("勘定科目（借方）") {
                    ForEach(accounts.filter { $0.accountType == .expense }) { acc in
                        Toggle(isOn: Binding(
                            get: { selectedAccounts.contains(acc.code) },
                            set: { isOn in
                                if isOn { selectedAccounts.insert(acc.code) }
                                else { selectedAccounts.remove(acc.code) }
                            })) {
                                Text("\(acc.code) \(acc.nameJa)")
                            }
                    }
                }
                Section("その他") {
                    Toggle("適格のみ", isOn: $qualifiedOnly)
                    Toggle("通常業務以外のみ", isOn: $lateEntryOnly)
                    Toggle("取消エントリを含む", isOn: $includeVoided)
                }
            }
            .navigationTitle("フィルタ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        criteria = build()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func build() -> ExpenseSearchCriteria {
        ExpenseSearchCriteria(
            dateFrom: useDateRange ? dateFrom : nil,
            dateTo: useDateRange ? dateTo : nil,
            debitAccountCodes: selectedAccounts.isEmpty ? nil : Array(selectedAccounts),
            amountMin: useAmountRange ? Int(amountMin) : nil,
            amountMax: useAmountRange ? Int(amountMax) : nil,
            qualifiedOnly: qualifiedOnly ? true : nil,
            lateEntryOnly: lateEntryOnly ? true : nil,
            includeVoided: includeVoided
        )
    }
}
```

- [ ] **Step 3: Write ExpenseListView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/ExpenseList/ExpenseListView.swift`:
```swift
import SwiftUI
import SwiftData

public struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel: ExpenseListViewModel?
    @State private var showFilter = false

    public init() {}

    public var body: some View {
        NavigationStack {
            if let vm = viewModel {
                List {
                    ForEach(vm.entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.counterpartyName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("¥\(e.amountIncludingTax)").font(.subheadline.monospacedDigit())
                            }
                            HStack {
                                Text("\(e.transactionDate, format: .dateTime.year().month().day())")
                                Text("•")
                                Text(e.transactionDescription).lineLimit(1)
                                Spacer()
                                if e.invoiceQualified {
                                    Text("適格").font(.caption2).padding(.horizontal, 4).background(Color.green.opacity(0.2))
                                }
                                if e.isLateEntry {
                                    Text("遅延").font(.caption2).padding(.horizontal, 4).background(Color.orange.opacity(0.2))
                                }
                                if e.isVoided {
                                    Text("取消").font(.caption2).padding(.horizontal, 4).background(Color.red.opacity(0.2))
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                voidEntry(e, vm: vm)
                            } label: {
                                Label("取消", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .searchable(text: Binding(get: { vm.searchText }, set: { vm.searchText = $0; vm.refresh() }))
                .navigationTitle("一覧")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showFilter = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                        Button { exportCSV(vm: vm) } label: { Image(systemName: "square.and.arrow.up") }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Text("合計 ¥\(vm.totalAmount)")
                    }
                }
                .sheet(isPresented: $showFilter) {
                    ExpenseFilterSheet(criteria: Binding(get: { vm.criteria }, set: { vm.criteria = $0; vm.refresh() }))
                }
                .task { vm.refresh() }
            } else {
                ProgressView().task { initVM() }
            }
        }
    }

    private func initVM() {
        let repo = SwiftDataExpenseRepository(context: context, deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        viewModel = ExpenseListViewModel(repository: repo)
    }

    private func voidEntry(_ e: JournalEntry, vm: ExpenseListViewModel) {
        let repo = SwiftDataExpenseRepository(context: context, deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        try? repo.void(e, reason: "ユーザー操作")
        vm.refresh()
    }

    private func exportCSV(vm: ExpenseListViewModel) {
        // 科目名 lookup のため Account を再 fetch
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let nameByCode = Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.nameJa) })
        let data = CSVExportService.export(vm.entries) { code in nameByCode[code] ?? code }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapkei_export.csv")
        try? data.write(to: url, options: [.atomic])
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(av, animated: true)
    }
}
```

---

## Task 5.7: SettingsView (all sections)

**Files:**
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/SettingsViewModel.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/SettingsView.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/BusinessInfoSection.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/AISettingsSection.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/FixedAssetSection.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/HouseholdAllocationSection.swift`
- Create: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/ComplianceSection.swift`

- [ ] **Step 1: Write SettingsViewModel.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/SettingsViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var appSettings: AppSettings = .default
    public var aiSettings: AISettings = .default

    public init() {
        self.appSettings = AppSettings.load()
        self.aiSettings = AISettings.load()
    }

    public func saveApp() { appSettings.save() }
    public func saveAI() { aiSettings.save() }
}
```

- [ ] **Step 2: Write BusinessInfoSection.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/BusinessInfoSection.swift`:
```swift
import SwiftUI

public struct BusinessInfoSection: View {
    @Binding public var settings: AppSettings
    public let onCommit: () -> Void

    public init(settings: Binding<AppSettings>, onCommit: @escaping () -> Void) {
        self._settings = settings
        self.onCommit = onCommit
    }

    public var body: some View {
        Section("事業者情報") {
            TextField("屋号", text: $settings.businessName).onSubmit(onCommit)
            TextField("氏名", text: $settings.ownerName).onSubmit(onCommit)
            TextField("適格番号 (T+13桁)", text: $settings.ownInvoiceRegistrationNumber)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .onSubmit(onCommit)
            Stepper(value: $settings.fiscalYearStartMonth, in: 1...12, onEditingChanged: { _ in onCommit() }) {
                Text("事業年度開始月：\(settings.fiscalYearStartMonth) 月")
            }
        }
    }
}
```

- [ ] **Step 3: Write AISettingsSection.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/AISettingsSection.swift`:
```swift
import SwiftUI

public struct AISettingsSection: View {
    @Binding public var ai: AISettings
    public let onCommit: () -> Void
    public let onSignInWithApple: () async -> Void
    public let onTestConnection: () async -> Void

    @State private var testResult: String?

    public init(
        ai: Binding<AISettings>,
        onCommit: @escaping () -> Void,
        onSignInWithApple: @escaping () async -> Void,
        onTestConnection: @escaping () async -> Void
    ) {
        self._ai = ai
        self.onCommit = onCommit
        self.onSignInWithApple = onSignInWithApple
        self.onTestConnection = onTestConnection
    }

    public var body: some View {
        Section("AI 設定") {
            Picker("チャネル", selection: $ai.aiChannel) {
                Text("自前 Key (Anthropic)").tag(AIChannel.directApiKey)
                Text("内蔵プロキシ").tag(AIChannel.builtInProxy)
            }
            .onChange(of: ai.aiChannel) { _, _ in onCommit() }

            if ai.aiChannel == .directApiKey {
                SecureField("Anthropic API Key", text: $ai.apiKey).onSubmit(onCommit)
                TextField("Endpoint", text: $ai.endpointURL).onSubmit(onCommit)
                Picker("モデル", selection: $ai.modelName) {
                    Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                }
                .onChange(of: ai.modelName) { _, _ in onCommit() }
            } else {
                Button("Apple でサインイン") {
                    Task { await onSignInWithApple() }
                }
                TextField("プロキシ URL", text: $ai.proxyBaseURL).onSubmit(onCommit)
            }

            Button("接続テスト") {
                Task {
                    await onTestConnection()
                    testResult = "テスト完了（コンソール参照）"
                }
            }
            if let t = testResult {
                Text(t).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 4: Write FixedAssetSection.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/FixedAssetSection.swift`:
```swift
import SwiftUI
import SwiftData

public struct FixedAssetSection: View {
    @Query(sort: \FixedAsset.acquisitionDate, order: .reverse) private var assets: [FixedAsset]
    @Environment(\.modelContext) private var context

    public init() {}

    public var body: some View {
        Section("固定資産台帳") {
            if assets.isEmpty {
                Text("資産が登録されていません").foregroundStyle(.secondary).font(.footnote)
            } else {
                ForEach(assets) { a in
                    VStack(alignment: .leading) {
                        Text(a.assetName).font(.subheadline.weight(.semibold))
                        HStack {
                            Text("取得 ¥\(a.acquisitionAmount)")
                            Spacer()
                            Text("簿価 ¥\(a.bookValue)")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("年末減価償却を実行") {
                Task { await runYearEnd() }
            }
        }
    }

    private func runYearEnd() async {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: Date())
        let entries = (try? DepreciationService.generateYearEndJournalEntries(fiscalYear: year, context: context)) ?? []
        print("[Settings] generated \(entries.count) depreciation entries for FY \(year)")
    }
}

// DepreciationService に generateYearEndJournalEntries が無い場合は no-op
extension DepreciationService {
    public static func generateYearEndJournalEntries(fiscalYear: Int, context: ModelContext) throws -> [JournalEntry] {
        let assets = try context.fetch(FetchDescriptor<FixedAsset>())
        var created: [JournalEntry] = []
        for asset in assets {
            let amount = annualDepreciation(for: asset, fiscalYear: fiscalYear)
            guard amount > 0 else { continue }
            let entry = JournalEntry(
                entryNumber: 0,
                fiscalYear: fiscalYear,
                transactionDate: Calendar(identifier: .gregorian).date(from: DateComponents(year: fiscalYear, month: 12, day: 31))!,
                debitAccountCode: "5230",
                creditAccountCode: "1710",
                amountIncludingTax: amount,
                amountExcludingTax: amount,
                consumptionTax: 0,
                taxCategory: .outOfScope,
                priceEntryMode: .taxIncluded,
                paymentMethod: .other,
                counterpartyName: "(減価償却)",
                transactionDescription: "年末減価償却 — \(asset.assetName)",
                relatedFixedAssetId: asset.id,
                sourceType: .depreciation
            )
            asset.accumulatedDepreciation += amount
            asset.bookValue = max(0, asset.acquisitionAmount - asset.accumulatedDepreciation)
            context.insert(entry)
            created.append(entry)
        }
        try context.save()
        return created
    }
}
```

- [ ] **Step 5: Write HouseholdAllocationSection.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/HouseholdAllocationSection.swift`:
```swift
import SwiftUI
import SwiftData

public struct HouseholdAllocationSection: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Environment(\.modelContext) private var context

    public init() {}

    public var body: some View {
        Section("家事按分デフォルト") {
            ForEach(accounts.filter { $0.accountType == .expense && $0.defaultBusinessAllocationRate < 1.0 }) { acc in
                HStack {
                    Text("\(acc.code) \(acc.nameJa)")
                    Spacer()
                    Stepper(value: Binding(
                        get: { acc.defaultBusinessAllocationRate },
                        set: { newVal in
                            acc.defaultBusinessAllocationRate = newVal
                            try? context.save()
                        }
                    ), in: 0...1, step: 0.1) {
                        Text("\(Int(acc.defaultBusinessAllocationRate * 100))%").monospacedDigit()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Write ComplianceSection.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/ComplianceSection.swift`:
```swift
import SwiftUI

public struct ComplianceSection: View {
    @Binding public var settings: AppSettings
    public let onCommit: () -> Void

    @State private var hasFiledNotification: Bool = UserDefaults.standard.bool(forKey: "controlRoute.hasFiledOptimalBookNotification")
    @State private var willUseEtax: Bool = UserDefaults.standard.bool(forKey: "controlRoute.willUseEtax")

    public init(settings: Binding<AppSettings>, onCommit: @escaping () -> Void) {
        self._settings = settings
        self.onCommit = onCommit
    }

    public var body: some View {
        Section("コンプライアンス") {
            Stepper(value: $settings.lateEntryThresholdDays, in: 1...90, onEditingChanged: { _ in onCommit() }) {
                Text("入力期限警告余裕：\(settings.lateEntryThresholdDays) 日")
            }
            Text("入力日 − 取引日 がこの値を超えると「通常業務以外の入力履歴」(優良電子帳簿要件①の一部) として記録されます。")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("優良電子帳簿の届出書を税務署に提出済", isOn: $hasFiledNotification)
                .onChange(of: hasFiledNotification) { _, newVal in
                    UserDefaults.standard.set(newVal, forKey: "controlRoute.hasFiledOptimalBookNotification")
                }
            Text("75万円控除の要件④。事前に税務署へ「国税関係帳簿の電磁的記録等による保存等に係る届出書」の提出が必要です。")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("e-Tax で申告予定", isOn: $willUseEtax)
                .onChange(of: willUseEtax) { _, newVal in
                    UserDefaults.standard.set(newVal, forKey: "controlRoute.willUseEtax")
                }
            Text("65万円・75万円控除には e-Tax 提出が必須。MVP では別ソフト（freee / 弥生 等）経由での提出を想定。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 7: Write SettingsView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/Settings/SettingsView.swift`:
```swift
import SwiftUI

public struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @State private var signIn = AppleSignInService()
    @State private var statusMessage: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                BusinessInfoSection(settings: Binding(get: { vm.appSettings }, set: { vm.appSettings = $0 }),
                                    onCommit: { vm.saveApp() })

                AISettingsSection(
                    ai: Binding(get: { vm.aiSettings }, set: { vm.aiSettings = $0 }),
                    onCommit: { vm.saveAI() },
                    onSignInWithApple: { await performSIWA() },
                    onTestConnection: { await testConnection() }
                )

                FixedAssetSection()
                HouseholdAllocationSection()
                ComplianceSection(settings: Binding(get: { vm.appSettings }, set: { vm.appSettings = $0 }),
                                  onCommit: { vm.saveApp() })

                if !statusMessage.isEmpty {
                    Section { Text(statusMessage).font(.caption) }
                }

                Section("アプリ情報") {
                    Text("SnapKei v0.1.0")
                    Text("青色申告対応 仕訳作成アプリ").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }

    private func performSIWA() async {
        let nonce = NonceGenerator.makePair()
        do {
            let result = try await signIn.authenticate(nonceRaw: nonce.raw, hashedNonce: nonce.hashedSHA256)
            // Worker と exchange
            let url = URL(string: vm.aiSettings.proxyBaseURL + "/v1/auth/exchange")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "appleIdentityToken": result.identityToken,
                "nonce": nonce.raw
            ])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                statusMessage = "サインイン失敗 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let resp = try decoder.decode(AIProxyService.ExchangeResponse.self, from: data)
            let store = AuthTokenStore()
            try store.save(sessionToken: resp.sessionToken, expiresAt: resp.expiresAt, appleUserId: resp.appleUserId)
            statusMessage = "サインイン成功"
        } catch {
            statusMessage = "サインイン失敗: \(error.localizedDescription)"
        }
    }

    private func testConnection() async {
        if vm.aiSettings.aiChannel == .directApiKey {
            statusMessage = vm.aiSettings.apiKey.isEmpty ? "API キー未設定" : "API キー設定済（実呼び出しは Capture でテスト）"
        } else {
            let store = AuthTokenStore()
            statusMessage = (try? store.isSessionValid(now: Date())) == true ? "セッション有効" : "セッション無効、再サインイン要"
        }
    }
}
```

---

## Task 5.8: Replace RootView with real tabs

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/Presentation/RootView.swift`
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`

- [ ] **Step 1: Rewrite RootView.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Presentation/RootView.swift`:
```swift
import SwiftUI

public struct RootView: View {
    @Environment(\.captureViewModel) private var captureVM

    public init() {}

    public var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house") }

            if let vm = captureVM {
                CaptureView(viewModel: vm)
                    .tabItem { Label("撮影", systemImage: "camera") }
            }

            ExpenseListView()
                .tabItem { Label("一覧", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

// MARK: - DI for CaptureViewModel

private struct CaptureViewModelKey: EnvironmentKey {
    static let defaultValue: CaptureViewModel? = nil
}

extension EnvironmentValues {
    public var captureViewModel: CaptureViewModel? {
        get { self[CaptureViewModelKey.self] }
        set { self[CaptureViewModelKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Wire DI in SnapKeiApp.swift**

Write to `/Users/lee/workspace/SnapKei/SnapKei/App/SnapKeiApp.swift`:
```swift
import SwiftUI
import SwiftData

@main
struct SnapKeiApp: App {

    @MainActor
    private var captureViewModel: CaptureViewModel = {
        let signIn = AppleSignInService()
        let tokenStore = AuthTokenStore()
        let proxyService = AIProxyService(
            proxyBaseURLProvider: { AISettings.load().proxyBaseURL },
            tokenStore: tokenStore,
            signIn: signIn
        )
        let router = AIRouter(
            settingsProvider: { AISettings.load() },
            directParserFactory: { cfg in ClaudeVisionService(config: cfg) },
            proxyParser: proxyService
        )
        let ctx = SnapKeiModelContainer.shared.mainContext
        let repo = SwiftDataExpenseRepository(
            context: ctx,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )
        return CaptureViewModel(
            aiRouter: router,
            repository: repo,
            appSettings: { AppSettings.load() },
            aiSettings: { AISettings.load() }
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.captureViewModel, captureViewModel)
        }
        .modelContainer(SnapKeiModelContainer.shared)
    }
}
```

---

## Task 5.9: Phase 5 build + commit

- [ ] **Step 1: Build + test**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test 2>&1 | tail -30
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Smoke test in simulator**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcrun simctl boot 'iPhone 17 Pro' 2>/dev/null; \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build && \
xcrun simctl install booted "$(xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -showBuildSettings | grep BUILT_PRODUCTS_DIR | head -1 | awk -F= '{print $2}' | xargs)/SnapKei.app" && \
xcrun simctl launch booted com.cheung.SnapKei
```
Expected: app launches in simulator. Manually verify all 4 tabs render without crash.

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add SnapKei/ SnapKeiTests/ && \
git commit -m "$(cat <<'EOF'
feat: Phase 5 — Home / List / Settings + PDF P/L + CSV export

- HomeView: 月概要カード, 控除路線ステータス, 入力期限警告, 円グラフ
  (Swift Charts SectorMark), 直近 5 件, レポート Section
- HomeViewModel: monthly summary, byDebitAccount aggregation, overdue
  search, recent entries
- PDFReportService.renderProfitAndLoss: A4 PDFKit-rendered, 売上 + 経費
  科目別合計 + 所得金額, ≥2 ページ自動分割
- CSVExportService: 弥生 / freee 取込互換, UTF-8 BOM, RFC 4180 escape
- ExpenseListView + ExpenseListViewModel: searchable, sortable, swipe to
  void, 過濾シート全条件 (期間/金額/借方科目/適格/通常業務以外)
- ExpenseFilterSheet: 全フィルタ UI
- SettingsView + 5 sub-sections (BusinessInfo / AISettings / FixedAsset /
  HouseholdAllocation / Compliance)
- DepreciationService.generateYearEndJournalEntries: 期末減価償却仕訳
  自動生成
- RootView: real 4 tabs with CaptureViewModel DI via environment
- SnapKeiApp: full DI wiring (AIRouter + AIProxyService + Repository +
  AppleSignInService)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 6: Localization + Documentation polish

## Task 6.1: Full Localizable.xcstrings (zh + ja)

**Files:**
- Modify: `/Users/lee/workspace/SnapKei/SnapKei/Resources/Localizable.xcstrings`

- [ ] **Step 1: Rewrite Localizable.xcstrings with all user-facing strings**

Write to `/Users/lee/workspace/SnapKei/SnapKei/Resources/Localizable.xcstrings`:
```json
{
  "sourceLanguage" : "zh-Hans",
  "version" : "1.0",
  "strings" : {
    "tab.home"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "ホーム" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "首页" }}}},
    "tab.capture"   : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "撮影" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "拍摄" }}}},
    "tab.list"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "一覧" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "列表" }}}},
    "tab.settings"  : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "設定" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "设置" }}}},

    "capture.idle"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "領収書を撮影またはインポート" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "拍摄或导入收据" }}}},
    "capture.parsing"   : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "AI が解析中…" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "AI 解析中…" }}}},
    "capture.saved"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "保存しました" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已保存" }}}},
    "capture.next"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "次の領収書" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "下一张收据" }}}},
    "capture.retry"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "やり直し" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "重试" }}}},

    "source.camera" : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "撮影" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "拍照" }}}},
    "source.album"  : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "アルバム" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "相册" }}}},
    "source.pdf"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "PDF をインポート" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "导入 PDF" }}}},

    "form.title"           : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "仕訳確認" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "仕訳确认" }}}},
    "form.transaction"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "取引" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "交易" }}}},
    "form.amount"          : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "金額" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "金额" }}}},
    "form.entry"           : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "仕訳" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "仕訳" }}}},
    "form.invoice"         : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "インボイス" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "适格发票" }}}},
    "form.allocation"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "家事按分" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "家事按分" }}}},
    "form.save"            : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "保存" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "保存" }}}},
    "form.transactionDate" : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "取引日" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "交易日期" }}}},
    "form.counterparty"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "取引先" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "交易对方" }}}},
    "form.description"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "取引内容" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "交易内容" }}}},

    "home.summary"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "今月の概要" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "本月概要" }}}},
    "home.entryCount"   : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "件数" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "件数" }}}},
    "home.totalAmount"  : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "税込合計" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "含税合计" }}}},
    "home.controlRoute" : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "控除路線" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "扣除路线" }}}},
    "home.overdue"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "入力期限警告" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "录入期限警告" }}}},
    "home.byAccount"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "科目別（今月）" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "按科目（本月）" }}}},
    "home.recent"       : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "直近の取引" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "近期交易" }}}},
    "home.report"       : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "レポート" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "报表" }}}},
    "home.pnlButton"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "損益計算書 PDF を生成" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "生成损益计算书 PDF" }}}},

    "list.filter"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "フィルタ" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "筛选" }}}},
    "list.apply"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "適用" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "应用" }}}},
    "list.cancel"     : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "キャンセル" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "取消" }}}},
    "list.total"      : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "合計" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "合计" }}}},

    "settings.businessInfo"  : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "事業者情報" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "事业者信息" }}}},
    "settings.ai"            : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "AI 設定" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "AI 设置" }}}},
    "settings.fixedAsset"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "固定資産台帳" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "固定资产台账" }}}},
    "settings.allocation"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "家事按分デフォルト" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "家事按分默认" }}}},
    "settings.compliance"    : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "コンプライアンス" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "合规" }}}},
    "settings.appInfo"       : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "アプリ情報" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "应用信息" }}}},
    "settings.signInApple"   : { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "Apple でサインイン" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "用 Apple 登录" }}}},
    "settings.testConnection": { "localizations" : { "ja" : { "stringUnit" : { "state" : "translated", "value" : "接続テスト" }}, "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "测试连接" }}}}
  }
}
```

> **Note:** To wire these into the UI, replace hardcoded strings (e.g. `Text("ホーム")`) with `Text("tab.home")` (which becomes a LocalizedStringKey). For brevity, this task includes the catalog only; updating call sites is a follow-up — a sweep across `Presentation/` replacing every Japanese literal with its key.

- [ ] **Step 2: Sweep — replace JA literals in views with localized keys**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
grep -rn '"撮影"\|"ホーム"\|"一覧"\|"設定"' SnapKei/Presentation/ | head -20
```
Then for each hit, replace the Japanese literal with the corresponding key from the catalog. Example:
```swift
// Before
Label("ホーム", systemImage: "house")
// After
Label("tab.home", systemImage: "house")
```

Repeat for `tab.capture` / `tab.list` / `tab.settings` / form labels / button titles.

- [ ] **Step 3: Build to confirm**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual visual check in simulator**

Run app, switch device language to Japanese (Settings → 一般 → 言語と地域) and to Chinese (设置 → 通用 → 语言与地区), confirm both render correctly.

---

## Task 6.2: README.md

**Files:**
- Create: `/Users/lee/workspace/SnapKei/README.md`

- [ ] **Step 1: Write README.md**

Write to `/Users/lee/workspace/SnapKei/README.md`:
```markdown
# SnapKei

日本の青色申告に対応した、領収書・レシート撮影で仕訳が自動作成される iOS アプリ。

## 特徴

- 📷 領収書を撮影またはアルバム選択 → AI (Claude Vision) が日付・金額・店舗・適格番号などを自動抽出
- 📄 PDF の電子領収書もインポート可能（電帳法 電子取引データ保存対応）
- ✏️ 複式簿記の借方・貸方を AI が提案、ユーザーは確認・編集して保存
- 🏠 家事按分（自宅事務所 30%、通信費 70% など）スライダー対応
- 🧾 インボイス制度 経過措置（80/70/50/30/0% の 5 段階）自動計算
- 📑 損益計算書 PDF / 弥生 freee 取込互換 CSV 出力
- 🔒 訂正・削除履歴を完全保持（優良な電子帳簿要件①）
- 🌐 中文 / 日本語 バイリンガル

## 開発状況

MVP 段階。詳細は [docs/superpowers/](docs/superpowers/) 配下のスペック・実装計画を参照。

## 構成

- iOS アプリ（このリポジトリのルート）— Swift 6, SwiftUI, SwiftData
- Cloudflare Worker（`infra/worker/`）— TypeScript, Hono, jose

## ビルド

```bash
# Xcode 26+ が必要
open SnapKei.xcodeproj
```

API キー設定の選択肢：
1. **自前 Key**: Settings 画面で Anthropic API キーを入力
2. **内蔵プロキシ**: Cloudflare Worker をデプロイ済みの場合、Apple サインインで利用

## 不法責任声明

本アプリは記帳補助ツールです。税務相談・税理士業務には該当しません。最終的な税務判断は税理士または税務署にご確認ください。

## ライセンス

TBD
```

---

## Task 6.3: App icon placeholder (manual)

> **Manual step — out of scope for code; design work.**

- [ ] **Step 1: User adds App Icon assets via Xcode**

User instructions:
1. Design or commission a 1024×1024 PNG icon
2. Open `Assets.xcassets` in Xcode → drag the icon into `AppIcon`
3. Xcode auto-generates all required sizes

- [ ] **Step 2: Verify**

Run:
```bash
ls /Users/lee/workspace/SnapKei/SnapKei/Assets.xcassets/AppIcon.appiconset/ 2>/dev/null
```
Expected: a Contents.json + PNG files. If empty, the user has not completed the manual step — this is fine; the app will use the default blank icon for now.

---

## Task 6.4: Phase 6 final build, smoke test, commit

- [ ] **Step 1: Full build + test sweep**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:SnapKeiTests/ClaudeVisionServiceIntegrationTests test 2>&1 | tail -50
```
Expected: all tests pass.

- [ ] **Step 2: Manual smoke test in simulator**

Boot simulator, launch app, walk through:
- Settings → enter Anthropic API key
- Capture → pick album image (any photo) → see AI parse → fill missing fields → Save
- List → confirm entry appears
- Home → see month summary, generate P/L PDF

Document any issues found. If anything is broken, fix in this Phase before commit.

- [ ] **Step 3: Final commit**

Run:
```bash
cd /Users/lee/workspace/SnapKei && \
git add . && \
git commit -m "$(cat <<'EOF'
feat: Phase 6 — localization + documentation polish

- Full zh-Hans + ja Localizable.xcstrings covering tabs, capture flow,
  form, home dashboard, list, settings, AI sections
- README.md with feature list, build instructions, and 不法責任声明
- App icon path documented as manual designer step

MVP complete: app is buildable + smoke-testable end-to-end with both BYOK
and Cloudflare proxy AI channels, full 青色申告 仕訳 data model, 優良
電子帳簿 要件 1-4 covered, P/L PDF + CSV export, fixed asset registry +
年末減価償却, 家事按分, Sign in with Apple, インボイス 経過措置 5 段階.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# End of Plan 3

After Task 6.4, the SnapKei MVP is feature-complete:

| Feature | Status |
|---|---|
| 4-tab UI (Home / Capture / List / Settings) | ✓ |
| Camera + Album + PDF input | ✓ |
| AI Vision parsing (Anthropic) | ✓ via Plan 2 |
| BYOK channel | ✓ |
| Built-in Cloudflare proxy + SIWA | ✓ via Plan 2 |
| 複式簿記 仕訳作成 | ✓ |
| 仕訳連番 (青色申告要件) | ✓ via Plan 1 |
| 訂正・削除履歴の確保（通常業務処理期間経過後の入力履歴含む、優良要件①） | ✓ via Plan 1 |
| 帳簿間相互関連性 (要件②) | ✓ |
| 検索機能 (要件③) | ✓ |
| 届出書提出 (要件④) — ユーザー手入力フラグ | ✓ Settings の Toggle で対応 |
| インボイス 経過措置 5 段階 | ✓ |
| 少額減価償却 40 万円特例 | ✓ |
| 一括償却資産 | ✓ |
| 家事按分 | ✓ |
| 損益計算書 PDF | ✓ |
| 弥生/freee 互換 CSV | ✓ |
| 中文/日本語 | ✓ |

**Out of MVP (deferred to v2):**
- 多端末 sync
- カスタム勘定科目 UI
- 多ページ PDF
- 仕訳帳 PDF
- 貸借対照表 (B/S)
- 自動車按分の自動計算
- App icon design

**Next steps after Plan 3 ships:**
1. TestFlight beta with real receipts from the user's actual business
2. Real Anthropic Vision accuracy measurement on Japanese receipts
3. e-Tax 提出フロー（XML output）prototyping for FY2026 year-end
