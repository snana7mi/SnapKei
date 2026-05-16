import SwiftData
import SwiftUI

public struct ConfirmationForm: View {
    @Binding private var draft: ReceiptDraft
    private let receiptImagePath: String?
    private let receiptImageHash: String?
    private let sourceType: RecordSource
    private let onSave: (JournalEntry) -> Void

    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var didApplyDraft = false
    @State private var transactionDate = Date()
    @State private var amountIncludingTaxText = ""
    @State private var taxCategory = TaxCategory.standard10
    @State private var priceEntryMode = PriceEntryMode.taxIncluded
    @State private var paymentMethod = PaymentMethod.ownerLoan
    @State private var counterpartyName = ""
    @State private var transactionDescription = ""
    @State private var debitAccountCode = "5110"
    @State private var creditAccountCode = "3210"
    @State private var invoiceRegistrationNumber = ""
    @State private var businessAllocationRate = 1.0

    public init(
        draft: Binding<ReceiptDraft>,
        receiptImagePath: String?,
        receiptImageHash: String?,
        sourceType: RecordSource,
        onSave: @escaping (JournalEntry) -> Void
    ) {
        self._draft = draft
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.sourceType = sourceType
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            InputDeadlineWarning(transactionDate: transactionDate)

            if let amount = Int(amountIncludingTaxText), amount > 0 {
                TreatmentSuggestionBanner(amount: amount, transactionDate: transactionDate)
            }

            Section("取引") {
                DatePicker("取引日", selection: $transactionDate, displayedComponents: .date)
                TextField("取引先", text: $counterpartyName)
                TextField("取引内容", text: $transactionDescription)
            }

            Section("金額") {
                TextField("税込金額", text: $amountIncludingTaxText).keyboardType(.numberPad)
                Picker("税区分", selection: $taxCategory) {
                    Text("10%").tag(TaxCategory.standard10)
                    Text("8% 軽減").tag(TaxCategory.reduced8)
                    Text("非課税").tag(TaxCategory.nonTaxable)
                    Text("対象外").tag(TaxCategory.outOfScope)
                }
                Picker("入力方式", selection: $priceEntryMode) {
                    Text("税込").tag(PriceEntryMode.taxIncluded)
                    Text("税抜").tag(PriceEntryMode.taxExcluded)
                }
            }

            Section("仕訳") {
                Picker("借方科目", selection: $debitAccountCode) {
                    ForEach(accounts.filter { $0.accountType == .expense }) { account in
                        Text("\(account.code) \(account.nameJa)").tag(account.code)
                    }
                }
                Picker("貸方科目", selection: $creditAccountCode) {
                    ForEach(accounts.filter { [.asset, .liability, .equity, .revenue].contains($0.accountType) }) { account in
                        Text("\(account.code) \(account.nameJa)").tag(account.code)
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
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section("家事按分") {
                Slider(value: $businessAllocationRate, in: 0...1, step: 0.1)
                Text("\(Int(businessAllocationRate * 100))%")
                if businessAllocationRate < 1, let amount = Int(amountIncludingTaxText) {
                    Text("仕訳計上額: ¥\(Int(Double(amount) * businessAllocationRate))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("保存") { save() }
                    .frame(maxWidth: .infinity)
                    .disabled(!isValid)
            }

            if let rawText = draft.rawText {
                Section("AI/OCR テキスト") {
                    Text(rawText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("仕訳確認")
        .onAppear(perform: applyDraftOnce)
    }

    private var isValid: Bool {
        guard let amount = Int(amountIncludingTaxText), amount > 0 else { return false }
        return !counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !transactionDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyDraftOnce() {
        guard !didApplyDraft else { return }
        didApplyDraft = true
        transactionDate = draft.transactionDate ?? Date()
        amountIncludingTaxText = String(draft.amountIncludingTax)
        taxCategory = draft.taxCategory
        priceEntryMode = draft.priceEntryMode
        paymentMethod = draft.paymentMethod
        counterpartyName = draft.counterpartyName
        transactionDescription = draft.transactionDescription
        invoiceRegistrationNumber = draft.invoiceRegistrationNumber ?? ""
        if let suggested = draft.suggestedDebitAccountCode, isValidDebitCode(suggested) {
            debitAccountCode = suggested
        } else {
            debitAccountCode = firstExpenseCode() ?? debitAccountCode
        }
        creditAccountCode = firstCreditCode() ?? creditAccountCode
    }

    private func save() {
        guard let amount = Int(amountIncludingTaxText) else { return }
        let rate = taxCategory.taxRate
        let amountExcludingTax: Int
        let consumptionTax: Int
        let total: Int
        if priceEntryMode == .taxIncluded {
            amountExcludingTax = Int((Double(amount) / (1 + rate)).rounded(.down))
            consumptionTax = amount - amountExcludingTax
            total = amount
        } else {
            amountExcludingTax = amount
            consumptionTax = Int((Double(amount) * rate).rounded(.down))
            total = amount + consumptionTax
        }

        let allocatedTotal = Int((Double(total) * businessAllocationRate).rounded(.down))
        let allocatedExcludingTax = Int((Double(amountExcludingTax) * businessAllocationRate).rounded(.down))
        let allocatedTax = Int((Double(consumptionTax) * businessAllocationRate).rounded(.down))
        let qualified = invoiceRegistrationNumber.hasPrefix("T") && invoiceRegistrationNumber.count == 14

        onSave(JournalEntry(
            entryNumber: 0,
            fiscalYear: Calendar(identifier: .gregorian).component(.year, from: transactionDate),
            transactionDate: transactionDate,
            isLateEntry: ComplianceService.daysUntilScanDeadline(receiptDate: transactionDate) < 0,
            debitAccountCode: isValidDebitCode(debitAccountCode) ? debitAccountCode : (firstExpenseCode() ?? debitAccountCode),
            creditAccountCode: isValidCreditCode(creditAccountCode) ? creditAccountCode : (firstCreditCode() ?? creditAccountCode),
            amountIncludingTax: allocatedTotal,
            amountExcludingTax: allocatedExcludingTax,
            consumptionTax: allocatedTax,
            taxCategory: taxCategory,
            priceEntryMode: priceEntryMode,
            paymentMethod: paymentMethod,
            counterpartyName: counterpartyName,
            invoiceRegistrationNumber: invoiceRegistrationNumber.isEmpty ? nil : invoiceRegistrationNumber,
            invoiceQualified: qualified,
            transitionalMeasureRate: ComplianceService.transitionalRate(qualified: qualified, transactionDate: transactionDate),
            transactionDescription: transactionDescription,
            businessAllocationRate: businessAllocationRate,
            originalAmountIncludingTax: businessAllocationRate < 1 ? total : nil,
            receiptImagePath: receiptImagePath,
            receiptImageHash: receiptImageHash,
            sourceType: sourceType
        ))
    }

    private func isValidDebitCode(_ code: String) -> Bool {
        accounts.contains { $0.code == code && $0.accountType == .expense && $0.isActive }
    }

    private func isValidCreditCode(_ code: String) -> Bool {
        accounts.contains { $0.code == code && [.asset, .liability, .equity, .revenue].contains($0.accountType) && $0.isActive }
    }

    private func firstExpenseCode() -> String? {
        accounts.first { $0.accountType == .expense && $0.isActive }?.code
    }

    private func firstCreditCode() -> String? {
        accounts.first { [.asset, .liability, .equity, .revenue].contains($0.accountType) && $0.isActive }?.code
    }
}

private extension TaxCategory {
    var taxRate: Double {
        switch self {
        case .standard10: 0.10
        case .reduced8: 0.08
        case .nonTaxable, .outOfScope: 0
        }
    }
}
