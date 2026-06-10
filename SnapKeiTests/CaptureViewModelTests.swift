import Foundation
import Testing
@testable import SnapKei

@Suite("CaptureViewModel")
struct CaptureViewModelTests {
    @MainActor
    @Test func saveConfirmedPersistsEntryAndMovesToSavedStage() {
        let repository = MemoryExpenseRepository()
        let router = AIRouter(
            settingsProvider: { AISettings.default },
            directParser: StubReceiptParser(draft: ReceiptDraft(amountIncludingTax: 100, counterpartyName: "店", transactionDescription: "本")),
            proxyParser: StubReceiptParser(draft: ReceiptDraft(amountIncludingTax: 100, counterpartyName: "店", transactionDescription: "本"))
        )
        let vm = CaptureViewModel(
            aiRouter: router,
            repository: repository,
            aiSettings: { .default }
        )
        let entry = JournalEntry(
            entryNumber: 0,
            fiscalYear: 2026,
            transactionDate: Date(),
            debitAccountCode: "5110",
            creditAccountCode: "3210",
            amountIncludingTax: 100,
            amountExcludingTax: 91,
            consumptionTax: 9,
            taxCategory: .standard10,
            priceEntryMode: .taxIncluded,
            paymentMethod: .ownerLoan,
            counterpartyName: "店",
            transactionDescription: "本",
            sourceType: .aiParsed
        )

        vm.saveConfirmed(entry)

        #expect(repository.created.count == 1)
        #expect(vm.stage == .saved)
    }
}
