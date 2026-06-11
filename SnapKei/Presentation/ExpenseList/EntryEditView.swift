import SwiftData
import SwiftUI

/// 保存済み仕訳の直接編集フォーム。保存は repository.edit() 経由で、
/// SystemActivityLog に before/after スナップショットと理由が記録される（電帳法の訂正履歴）。
///
/// 重要: @Model を直接バインドしない。SwiftData の変更は即時反映のため、
/// 直接バインドすると (a) キャンセルしてもモデルが汚染される、
/// (b) edit() の before スナップショットが「変更後」を撮って diff が空になる。
/// よって @State に複製し、保存時の applying クロージャ内でのみ書き戻す。
struct EntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]

    let entry: JournalEntry

    @State private var transactionDate: Date
    @State private var counterpartyName: String
    @State private var transactionDescription: String
    @State private var memo: String
    @State private var amountText: String
    @State private var taxCategory: TaxCategory
    @State private var priceEntryMode: PriceEntryMode
    @State private var debitAccountCode: String
    @State private var creditAccountCode: String
    @State private var paymentMethod: PaymentMethod
    @State private var invoiceRegistrationNumber: String
    @State private var businessAllocationRate: Double
    @State private var businessAllocationPercentText: String
    @State private var editReason = ""
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var showCancelConfirm = false
    @FocusState private var allocationFieldFocused: Bool

    /// キャンセル確認・保存ボタン活性の基準となる初期値（@State と同じ導出で固定）。
    /// let だと親 body の再評価で再 init された際に「現在値」へ再基準化されてしまう
    /// （@State は保持されるのに基準だけズレて hasChanges が壊れる）ため @State で一度だけ確定する。
    @State private var initialValues: InitialValues

    private struct InitialValues {
        let transactionDate: Date
        let counterpartyName: String
        let transactionDescription: String
        let memo: String
        let amountText: String
        let taxCategory: TaxCategory
        let priceEntryMode: PriceEntryMode
        let debitAccountCode: String
        let creditAccountCode: String
        let paymentMethod: PaymentMethod
        let invoiceRegistrationNumber: String
        let businessAllocationPercentText: String
    }

    init(entry: JournalEntry) {
        self.entry = entry

        // 金額欄は按分前の数値を編集する（保存時に TaxSplit→TaxAllocation で再計算）。
        // 税抜入力かつ按分ありの場合のみ按分前税抜額が保存されていないため整数式で逆算する
        // （保存時の再丸めで ±1円 揺れうるが、按分+税抜入力は稀でありこの誤差を受容する）。
        let preTotal = entry.originalAmountIncludingTax ?? entry.amountIncludingTax
        let initialAmount: Int
        if entry.priceEntryMode == .taxExcluded {
            if entry.businessAllocationRate < 1 {
                let ratePercent = Int((entry.taxCategory.taxRate * 100).rounded())
                initialAmount = preTotal * 100 / (100 + ratePercent)
            } else {
                initialAmount = entry.amountExcludingTax
            }
        } else {
            initialAmount = preTotal
        }

        let initial = InitialValues(
            transactionDate: entry.transactionDate,
            counterpartyName: entry.counterpartyName,
            transactionDescription: entry.transactionDescription,
            memo: entry.memo ?? "",
            amountText: String(initialAmount),
            taxCategory: entry.taxCategory,
            priceEntryMode: entry.priceEntryMode,
            debitAccountCode: entry.debitAccountCode,
            creditAccountCode: entry.creditAccountCode,
            paymentMethod: entry.paymentMethod,
            invoiceRegistrationNumber: entry.invoiceRegistrationNumber ?? "",
            businessAllocationPercentText: String(Int((entry.businessAllocationRate * 100).rounded()))
        )
        _initialValues = State(initialValue: initial)

        _transactionDate = State(initialValue: initial.transactionDate)
        _counterpartyName = State(initialValue: initial.counterpartyName)
        _transactionDescription = State(initialValue: initial.transactionDescription)
        _memo = State(initialValue: initial.memo)
        _amountText = State(initialValue: initial.amountText)
        _taxCategory = State(initialValue: initial.taxCategory)
        _priceEntryMode = State(initialValue: initial.priceEntryMode)
        _debitAccountCode = State(initialValue: initial.debitAccountCode)
        _creditAccountCode = State(initialValue: initial.creditAccountCode)
        _paymentMethod = State(initialValue: initial.paymentMethod)
        _invoiceRegistrationNumber = State(initialValue: initial.invoiceRegistrationNumber)
        _businessAllocationRate = State(initialValue: entry.businessAllocationRate)
        _businessAllocationPercentText = State(initialValue: initial.businessAllocationPercentText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "取引日",
                        selection: $transactionDate,
                        in: FiscalYearRule.dateRange(for: entry.fiscalYear),
                        displayedComponents: .date
                    )
                    TextField("取引先", text: $counterpartyName)
                    TextField("内容", text: $transactionDescription)
                    TextField("メモ", text: $memo)
                } header: {
                    Text("取引")
                } footer: {
                    Text("取引日は \(String(entry.fiscalYear)) 年度内でのみ変更できます。年度をまたぐ場合は取消して再入力してください。")
                }

                Section("金額") {
                    TextField("金額(税込/税抜)", text: $amountText)
                        .keyboardType(.numberPad)
                    Picker("税区分", selection: $taxCategory) {
                        ForEach(TaxCategory.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                    }
                    Picker("入力方式", selection: $priceEntryMode) {
                        ForEach(PriceEntryMode.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                    }
                }

                Section("仕訳") {
                    Picker("借方科目", selection: $debitAccountCode) {
                        ForEach(choices(current: debitAccountCode)) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    Picker("貸方科目", selection: $creditAccountCode) {
                        ForEach(choices(current: creditAccountCode)) { account in
                            Text("\(account.code) \(account.nameJa)").tag(account.code)
                        }
                    }
                    if derivedKind == .expense {
                        Picker("支払方法", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases, id: \.self) { Text($0.labelJa).tag($0) }
                        }
                    }
                }

                if derivedKind == .expense {
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
                    TextField("訂正理由（任意）", text: $editReason)
                } footer: {
                    Text("編集は記録を残したまま内容を修正します（電帳法の訂正・削除履歴）。")
                }

                Section {
                    Button("保存") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid || !hasChanges || isSaving)
                }
            }
            .navigationTitle("仕訳を編集")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasChanges { showCancelConfirm = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("変更を破棄しますか？", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("破棄する", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
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

    /// 全有効科目（元入金除く）。ただし現在選択中のコードは無効化済みでも残す
    /// （同期で科目がカスタム化されていても Picker の選択が壊れない）。
    private func choices(current: String) -> [Account] {
        accounts.filter { ($0.isActive && $0.code != AccountCode.capital) || $0.code == current }
    }

    /// 現在の借方/貸方から仕訳の種別を導出（ManualEntryRules.kind が単一定義）。
    private var derivedKind: ManualEntryKind {
        ManualEntryRules.kind(
            debitType: accountType(of: debitAccountCode),
            creditType: accountType(of: creditAccountCode)
        )
    }

    private var isValid: Bool {
        ManualEntryRules.validate(
            kind: derivedKind,
            debitCode: debitAccountCode,
            debitType: accountType(of: debitAccountCode),
            creditCode: creditAccountCode,
            creditType: accountType(of: creditAccountCode),
            amount: Int(amountText) ?? 0,
            counterparty: counterpartyName,
            description: transactionDescription,
            allocationRate: derivedKind == .expense ? businessAllocationRate : 1.0
        ).isEmpty
    }

    private var hasChanges: Bool {
        transactionDate != initialValues.transactionDate
            || counterpartyName != initialValues.counterpartyName
            || transactionDescription != initialValues.transactionDescription
            || memo != initialValues.memo
            || amountText != initialValues.amountText
            || taxCategory != initialValues.taxCategory
            || priceEntryMode != initialValues.priceEntryMode
            || debitAccountCode != initialValues.debitAccountCode
            || creditAccountCode != initialValues.creditAccountCode
            || paymentMethod != initialValues.paymentMethod
            || invoiceRegistrationNumber != initialValues.invoiceRegistrationNumber
            || businessAllocationPercentText != initialValues.businessAllocationPercentText
    }

    private func accountType(of code: String) -> AccountType? {
        accounts.first { $0.code == code }?.accountType
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

        let kind = derivedKind
        let split = TaxSplit.split(amount: amount, mode: priceEntryMode, rate: taxCategory.taxRate)
        let allocationRate = kind == .expense ? businessAllocationRate : 1.0
        let allocation = TaxAllocation.allocate(
            total: split.total, excludingTax: split.excludingTax, rate: allocationRate)

        let invoice = invoiceRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = kind == .expense && invoice.hasPrefix("T") && invoice.count == 14
        let memoTrimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = editReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMethod: PaymentMethod = switch kind {
        case .income: ManualEntryRules.paymentMethod(forIncomeDebit: debitAccountCode)
        case .expense: paymentMethod
        case .transfer: .other
        }

        let repository = SwiftDataExpenseRepository(context: context, deviceId: DeviceID.current)
        do {
            try repository.edit(entry, applying: {
                entry.transactionDate = transactionDate
                entry.counterpartyName = counterpartyName
                entry.transactionDescription = transactionDescription
                entry.memo = memoTrimmed.isEmpty ? nil : memoTrimmed
                entry.debitAccountCode = debitAccountCode
                entry.creditAccountCode = creditAccountCode
                entry.amountIncludingTax = allocation.total
                entry.amountExcludingTax = allocation.excludingTax
                entry.consumptionTax = allocation.tax
                entry.taxCategoryRaw = taxCategory.rawValue
                entry.priceEntryModeRaw = priceEntryMode.rawValue
                entry.paymentMethodRaw = effectiveMethod.rawValue
                entry.invoiceRegistrationNumber = kind == .expense && !invoice.isEmpty ? invoice : nil
                entry.invoiceQualified = qualified
                entry.transitionalMeasureRate = kind == .expense
                    ? ComplianceService.transitionalRate(qualified: qualified, transactionDate: transactionDate)
                    : 1.0
                entry.businessAllocationRate = allocationRate
                entry.originalAmountIncludingTax = allocationRate < 1 ? split.total : nil
            }, reason: reason.isEmpty ? "ユーザー操作" : reason)
            dismiss()
            isSaving = false
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
