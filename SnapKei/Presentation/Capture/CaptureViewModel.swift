import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

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
    #if canImport(UIKit)
    public var pickedImage: UIImage?
    #endif
    public var pickedPDFURL: URL?
    public var receiptImagePath: String?
    public var receiptImageHash: String?
    public var sourceType: RecordSource = .aiParsed

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

    #if canImport(UIKit)
    public func handlePickedImage(_ image: UIImage) async {
        pickedImage = image
        pickedPDFURL = nil
        sourceType = .aiParsed
        stage = .parsing
        do {
            let jpegData = try ReceiptImageProcessor.jpegData(from: image)
            let draft = try await aiRouter.parseReceipt(imageData: jpegData, mimeType: "image/jpeg")
            let transactionDate = draft.transactionDate ?? Date()
            let stored = try ImageStorageService.persist(
                jpegData: jpegData,
                fiscalYear: fiscalYear(for: transactionDate),
                transactionDate: transactionDate
            )
            receiptImagePath = stored.relativePath
            receiptImageHash = stored.sha256Hex
            stage = .confirming(draft)
        } catch {
            stage = .error(error.localizedDescription)
        }
    }
    #endif

    public func handlePickedPDF(_ url: URL) async {
        pickedPDFURL = url
        sourceType = .electronicTransaction
        stage = .parsing
        do {
            #if canImport(UIKit)
            let guessDate = Date()
            let imported = try ElectronicReceiptImporter.process(
                pdfURL: url,
                fiscalYear: fiscalYear(for: guessDate),
                transactionDate: guessDate
            )
            let draft = try await aiRouter.parseReceipt(imageData: imported.jpegData, mimeType: "image/jpeg")
            receiptImagePath = imported.originalPDFRelativePath
            receiptImageHash = imported.originalPDFHash
            stage = .confirming(draft)
            #else
            throw AIServiceError.invalidResponse("PDF import requires UIKit")
            #endif
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    public func saveConfirmed(_ entry: JournalEntry) {
        do {
            try repository.create(entry, reason: nil)
            stage = .saved
        } catch {
            cleanupStagedReceipt()
            stage = .error("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    public func reset() {
        if case .confirming = stage {
            cleanupStagedReceipt()
        }
        stage = .idle
        #if canImport(UIKit)
        pickedImage = nil
        #endif
        pickedPDFURL = nil
        receiptImagePath = nil
        receiptImageHash = nil
        sourceType = .aiParsed
    }

    private func cleanupStagedReceipt() {
        if let receiptImagePath {
            ImageStorageService.delete(relativePath: receiptImagePath)
        }
    }

    private func fiscalYear(for date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let startMonth = appSettings().fiscalYearStartMonth
        return month >= startMonth ? year : year - 1
    }
}
