import SwiftData
import SwiftUI

/// 固定資産の登記フォーム。新規購入（取得仕訳自動生成）と既存資産の引継ぎに対応。
struct FixedAssetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AssetUsefulLife.code) private var categories: [AssetUsefulLife]

    @State private var name = ""
    @State private var categoryCode = "PC"
    @State private var acquisitionDate = Date()
    @State private var serviceStartDate = Date()
    @State private var amountText = ""
    @State private var usefulLifeYears = 4
    @State private var treatment = AssetTreatment.normalDepreciation
    @State private var allocationPercentText = "100"
    @State private var allocationRate = 1.0
    @FocusState private var allocationFieldFocused: Bool
    @State private var paymentMethod = PaymentMethod.ownerLoan
    @State private var taxCategory = TaxCategory.standard10
    @State private var isCarriedOver = false
    @State private var accumulatedText = "0"
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("資産") {
                    TextField("資産名", text: $name)
                    Picker("カテゴリ", selection: $categoryCode) {
                        ForEach(categories, id: \.code) { category in
                            Text(category.nameJa).tag(category.code)
                        }
                    }
                    Stepper("耐用年数: \(usefulLifeYears) 年", value: $usefulLifeYears, in: 2...50)
                    DatePicker("取得日", selection: $acquisitionDate, displayedComponents: .date)
                    DatePicker("使用開始日", selection: $serviceStartDate, displayedComponents: .date)
                }

                Section {
                    TextField("取得価額(税込)", text: $amountText).keyboardType(.numberPad)
                    if let amount = Int(amountText), amount > 0 {
                        if availableTreatments.isEmpty {
                            Label("10万円未満は固定資産ではなく消耗品費等で経費計上してください。", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else {
                            Picker("償却区分", selection: $treatment) {
                                ForEach(availableTreatments, id: \.self) { option in
                                    Text(treatmentLabel(option)).tag(option)
                                }
                            }
                            if let suggested = ComplianceService.suggestAssetTreatment(amount: amount, acquisitionDate: acquisitionDate) {
                                Text("推奨: \(treatmentLabel(suggested))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Text("事業割合")
                        Spacer()
                        TextField("", text: $allocationPercentText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($allocationFieldFocused)
                            .frame(width: 56)
                            .onChange(of: allocationPercentText) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue { allocationPercentText = filtered }
                            }
                            .onChange(of: allocationFieldFocused) { _, focused in
                                if !focused { commitAllocationPercent() }
                            }
                            .onSubmit(commitAllocationPercent)
                        Text("%").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("金額・償却")
                }

                Section {
                    Toggle("既存資産の引継ぎ", isOn: $isCarriedOver)
                    if isCarriedOver {
                        TextField("償却累計額", text: $accumulatedText)
                            .keyboardType(.numberPad)
                            .onChange(of: accumulatedText) { _, newValue in
                                // 全角数字・カンマ等は Int() が nil → 0 になり累計が静かに
                                // 消えるため、半角数字以外を弾く。
                                let filtered = newValue.filter { $0.isASCII && $0.isNumber }
                                if filtered != newValue { accumulatedText = filtered }
                            }
                    } else {
                        Picker("支払方法", selection: $paymentMethod) {
                            Text("現金").tag(PaymentMethod.cash)
                            Text("クレジット").tag(PaymentMethod.creditCard)
                            Text("銀行振込").tag(PaymentMethod.bankTransfer)
                            Text("事業主借").tag(PaymentMethod.ownerLoan)
                        }
                        Picker("税区分", selection: $taxCategory) {
                            Text("10%").tag(TaxCategory.standard10)
                            Text("8% 軽減").tag(TaxCategory.reduced8)
                            Text("対象外").tag(TaxCategory.outOfScope)
                        }
                    }
                } header: {
                    Text("記帳")
                } footer: {
                    Text(isCarriedOver
                        ? "開業前・アプリ導入前から保有する資産用。仕訳は生成されません（期首残高で資産計上してください）。"
                        : "登記と同時に取得仕訳（工具器具備品/支払方法）を自動生成します。")
                }

                Section {
                    Button("登録") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("資産を登録")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!name.isEmpty || !amountText.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
            .onChange(of: categoryCode) { _, newCode in
                if let category = categories.first(where: { $0.code == newCode }) {
                    usefulLifeYears = category.years
                }
            }
            .onChange(of: amountText) { _, _ in correctTreatmentIfUnavailable() }
            .onChange(of: acquisitionDate) { _, _ in correctTreatmentIfUnavailable() }
            .alert(
                "登録できませんでした",
                isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private var availableTreatments: [AssetTreatment] {
        FixedAssetRules.availableTreatments(amount: Int(amountText) ?? 0, acquisitionDate: acquisitionDate)
    }

    /// 金額帯・取得日（少額特例の適用期限）で選択不能になった償却区分を補正する。
    private func correctTreatmentIfUnavailable() {
        if !availableTreatments.isEmpty, !availableTreatments.contains(treatment) {
            treatment = availableTreatments[0]
        }
    }

    private var isValid: Bool {
        FixedAssetRules.validate(
            name: name,
            amount: Int(amountText) ?? 0,
            usefulLifeYears: usefulLifeYears,
            allocationRate: allocationRate,
            treatment: treatment,
            acquisitionDate: acquisitionDate,
            isCarriedOver: isCarriedOver,
            accumulatedDepreciation: Int(accumulatedText) ?? 0
        ).isEmpty
    }

    private func treatmentLabel(_ treatment: AssetTreatment) -> String {
        switch treatment {
        case .normalDepreciation: "定額法"
        case .lumpSumDepreciation: "一括償却(3年)"
        case .smallAmountFullExpense: "少額特例(即時償却)"
        }
    }

    private func commitAllocationPercent() {
        let clamped = max(0, min(100, Int(allocationPercentText) ?? 0))
        allocationPercentText = String(clamped)
        allocationRate = Double(clamped) / 100.0
    }

    private func save() {
        guard !isSaving else { return }
        commitAllocationPercent()
        guard let amount = Int(amountText), amount > 0 else { return }
        isSaving = true
        let service = FixedAssetService(context: context, deviceId: DeviceID.current)
        do {
            try service.register(FixedAssetService.RegistrationInput(
                name: name,
                categoryCode: categoryCode,
                acquisitionDate: acquisitionDate,
                serviceStartDate: serviceStartDate,
                acquisitionAmount: amount,
                usefulLifeYears: usefulLifeYears,
                treatment: treatment,
                businessAllocationRate: allocationRate,
                paymentMethod: paymentMethod,
                taxCategory: taxCategory,
                isCarriedOver: isCarriedOver,
                accumulatedDepreciation: Int(accumulatedText) ?? 0
            ))
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
