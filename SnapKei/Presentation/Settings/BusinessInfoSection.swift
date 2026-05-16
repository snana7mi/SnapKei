import SwiftUI

public struct BusinessInfoSection: View {
    @Binding private var settings: AppSettings
    private let onCommit: () -> Void

    public init(settings: Binding<AppSettings>, onCommit: @escaping () -> Void) {
        self._settings = settings
        self.onCommit = onCommit
    }

    public var body: some View {
        Section("事業者情報") {
            TextField("屋号", text: $settings.businessName).onSubmit(onCommit)
            TextField("氏名", text: $settings.ownerName).onSubmit(onCommit)
            TextField("適格番号 (T+13桁)", text: $settings.ownInvoiceRegistrationNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(onCommit)
            Stepper(value: $settings.fiscalYearStartMonth, in: 1...12, onEditingChanged: { _ in onCommit() }) {
                Text("事業年度開始月: \(settings.fiscalYearStartMonth) 月")
            }
        }
    }
}
