import SwiftData
import SwiftUI

/// レシートなしの手動仕訳入力。収入/支出/振替の三モード誘導型。
/// モード別の科目制約・検証は ManualEntryRules、税分解は TaxSplit に委譲する。
struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var kind: ManualEntryKind = .income
    @State private var transactionDate = Date()
    @State private var counterpartyName = ""
    @State private var transactionDescription = ""
    @State private var amountText = ""
    @State private var taxCategory = TaxCategory.standard10
    @State private var priceEntryMode = PriceEntryMode.taxIncluded
    @State private var debitAccountCode = AccountCode.bankDeposit
    @State private var creditAccountCode = AccountCode.salesRevenue
    @State private var paymentMethod = PaymentMethod.ownerLoan
    @State private var userEditedCreditAccount = false
    @State private var invoiceRegistrationNumber = ""
    @State private var businessAllocationRate = 1.0
    @State private var businessAllocationPercentText = "100"
    @FocusState private var allocationFieldFocused: Bool
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種別", selection: $kind) {
                        Text("収入").tag(ManualEntryKind.income)
                        Text("支出").tag(ManualEntryKind.expense)
                        Text("振替").tag(ManualEntryKind.transfer)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if kind == .transfer {
                        Text("売掛金の回収・借入・事業主貸/借の振替など、収入・支出以外の仕訳に使います。")
                    }
                }

                if kind == .expense, let amount = Int(amountText), amount > 0 {
                    TreatmentSuggestionBanner(amount: amount, transactionDate: transactionDate)
                }

                Section("取引") {
                    DatePicker("取引日", selection: $transactionDate, displayedComponents: .date)
                    TextField("取引先", text: $counterpartyName)
                    TextField("内容", text: $transactionDescription)
                }

                Section("金額") {
                    TextField("金額(税込/税抜)", text: $amountText)
                        .keyboardType(.numberPad)
                    // 振替でも税区分を選べるようにする（固定資産の購入など課税取引の
                    // 受け皿。デフォルトは applyKindDefaults で 対象外）。
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
                    Picker(kind == .income ? "入金先" : "借方科目", selection: $debitAccountCode) {
                        ForEach(debitChoices) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    Picker(kind == .income ? "科目" : "貸方科目", selection: creditSelectionBinding) {
                        ForEach(creditChoices) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    if kind == .expense {
                        Picker("支払方法", selection: $paymentMethod) {
                            Text("現金").tag(PaymentMethod.cash)
                            Text("クレジット").tag(PaymentMethod.creditCard)
                            Text("銀行振込").tag(PaymentMethod.bankTransfer)
                            Text("事業主借").tag(PaymentMethod.ownerLoan)
                            Text("その他").tag(PaymentMethod.other)
                        }
                    }
                }

                if kind == .expense {
                    Section("インボイス") {
                        TextField("適格番号 (T+13桁)", text: $invoiceRegistrationNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    Section("家事按分") {
                        HStack {
                            Text("業務割合")
                            Spacer()
                            TextField("", text: $businessAllocationPercentText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($allocationFieldFocused)
                                .frame(width: 56)
                                .onChange(of: businessAllocationPercentText) { _, newValue in
                                    let filtered = newValue.filter(\.isNumber)
                                    if filtered != newValue {
                                        businessAllocationPercentText = filtered
                                    }
                                }
                                .onChange(of: allocationFieldFocused) { _, focused in
                                    if !focused { commitAllocationPercent() }
                                }
                                .onSubmit(commitAllocationPercent)
                            Text("%").foregroundStyle(.secondary)
                        }
                        if businessAllocationRate < 1, let amount = Int(amountText) {
                            Text("仕訳計上額: ¥\(Int(Double(amount) * businessAllocationRate))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("保存") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("手動入力")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedInput)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onChange(of: kind) { _, newKind in applyKindDefaults(newKind) }
            .onChange(of: paymentMethod) { _, newMethod in applyCreditDefault(for: newMethod) }
            .onChange(of: debitAccountCode) { _, newCode in
                if kind == .expense { applyAllocationDefault(forDebitCode: newCode) }
            }
            .alert(
                "保存できませんでした",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    // MARK: - Choices & validation

    private var debitChoices: [Account] {
        accounts.filter {
            $0.isActive && $0.code != AccountCode.capital
                && ManualEntryRules.allowedDebitTypes(for: kind).contains($0.accountType)
        }
    }

    private var creditChoices: [Account] {
        accounts.filter {
            $0.isActive && $0.code != AccountCode.capital
                && ManualEntryRules.allowedCreditTypes(for: kind).contains($0.accountType)
        }
    }

    private var isValid: Bool {
        ManualEntryRules.validate(
            kind: kind,
            debitCode: debitAccountCode,
            debitType: accountType(of: debitAccountCode),
            creditCode: creditAccountCode,
            creditType: accountType(of: creditAccountCode),
            amount: Int(amountText) ?? 0,
            counterparty: counterpartyName,
            description: transactionDescription,
            allocationRate: kind == .expense ? businessAllocationRate : 1.0
        ).isEmpty
    }

    private var hasUnsavedInput: Bool {
        !amountText.isEmpty || !counterpartyName.isEmpty || !transactionDescription.isEmpty
    }

    private func accountType(of code: String) -> AccountType? {
        accounts.first { $0.code == code && $0.isActive }?.accountType
    }

    // MARK: - Mode defaults

    private func applyKindDefaults(_ newKind: ManualEntryKind) {
        userEditedCreditAccount = false
        switch newKind {
        case .income:
            debitAccountCode = preferredCode(AccountCode.bankDeposit, in: debitChoices)
            creditAccountCode = preferredCode(AccountCode.salesRevenue, in: creditChoices)
            taxCategory = .standard10
        case .expense:
            debitAccountCode = preferredCode("5110", in: debitChoices)
            paymentMethod = .ownerLoan
            creditAccountCode = preferredCode(AccountCode.ownerLoan, in: creditChoices)
            taxCategory = .standard10
            applyAllocationDefault(forDebitCode: debitAccountCode)
        case .transfer:
            debitAccountCode = preferredCode(AccountCode.cash, in: debitChoices)
            creditAccountCode = preferredCode(AccountCode.bankDeposit, in: creditChoices)
            taxCategory = .outOfScope
        }
    }

    /// 希望コードが選択肢に存在すればそれ、無ければ先頭（科目表が同期でカスタム化していても破綻しない）。
    private func preferredCode(_ preferred: String, in choices: [Account]) -> String {
        choices.contains { $0.code == preferred } ? preferred : (choices.first?.code ?? preferred)
    }

    /// 貸方科目 Picker の手動変更を記録し、以後 applyCreditDefault が上書きしないようにする。
    private var creditSelectionBinding: Binding<String> {
        Binding(
            get: { creditAccountCode },
            set: { newValue in
                creditAccountCode = newValue
                userEditedCreditAccount = true
            }
        )
    }

    private func applyCreditDefault(for method: PaymentMethod) {
        guard kind == .expense else { return }
        if !userEditedCreditAccount,
           let mapped = method.defaultCreditAccountCode,
           creditChoices.contains(where: { $0.code == mapped }) {
            creditAccountCode = mapped
        }
    }

    private func applyAllocationDefault(forDebitCode code: String) {
        guard let account = accounts.first(where: { $0.code == code }) else { return }
        businessAllocationRate = account.defaultBusinessAllocationRate
        businessAllocationPercentText = String(Int((account.defaultBusinessAllocationRate * 100).rounded()))
    }

    private func commitAllocationPercent() {
        let clamped = max(0, min(100, Int(businessAllocationPercentText) ?? 0))
        businessAllocationPercentText = String(clamped)
        businessAllocationRate = Double(clamped) / 100.0
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        commitAllocationPercent()
        guard let amount = Int(amountText), amount > 0 else { return }
        isSaving = true
        let split = TaxSplit.split(amount: amount, mode: priceEntryMode, rate: taxCategory.taxRate)

        let allocationRate = kind == .expense ? businessAllocationRate : 1.0
        let allocation = TaxAllocation.allocate(total: split.total, excludingTax: split.excludingTax, rate: allocationRate)

        let invoice = invoiceRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = kind == .expense && invoice.hasPrefix("T") && invoice.count == 14

        // isLateEntry（スキャナ保存期限）はレシート画像のある仕訳の概念。書類なしの
        // 手動仕訳には適用しない（デフォルト false のまま）。
        let entry = JournalEntry(
            entryNumber: 0,
            fiscalYear: FiscalYearRule.year(for: transactionDate),
            transactionDate: transactionDate,
            debitAccountCode: debitAccountCode,
            creditAccountCode: creditAccountCode,
            amountIncludingTax: allocation.total,
            amountExcludingTax: allocation.excludingTax,
            consumptionTax: allocation.tax,
            taxCategory: taxCategory,
            priceEntryMode: priceEntryMode,
            paymentMethod: effectivePaymentMethod,
            counterpartyName: counterpartyName,
            invoiceRegistrationNumber: kind == .expense && !invoice.isEmpty ? invoice : nil,
            invoiceQualified: qualified,
            transitionalMeasureRate: kind == .expense
                ? ComplianceService.transitionalRate(qualified: qualified, transactionDate: transactionDate)
                : 1.0,
            transactionDescription: transactionDescription,
            businessAllocationRate: allocationRate,
            originalAmountIncludingTax: allocationRate < 1 ? split.total : nil,
            sourceType: .manual
        )

        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.create(entry, reason: nil)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private var effectivePaymentMethod: PaymentMethod {
        switch kind {
        case .income: ManualEntryRules.paymentMethod(forIncomeDebit: debitAccountCode)
        case .expense: paymentMethod
        case .transfer: .other
        }
    }
}
