import SwiftUI

public struct ComplianceSection: View {
    @Binding private var settings: AppSettings
    private let onCommit: () -> Void
    @State private var hasFiledNotification = UserDefaults.standard.bool(forKey: "controlRoute.hasFiledOptimalBookNotification")
    @State private var willUseEtax = UserDefaults.standard.bool(forKey: "controlRoute.willUseEtax")

    public init(settings: Binding<AppSettings>, onCommit: @escaping () -> Void) {
        self._settings = settings
        self.onCommit = onCommit
    }

    public var body: some View {
        Section("コンプライアンス") {
            Stepper(value: $settings.lateEntryThresholdDays, in: 1...90, onEditingChanged: { _ in onCommit() }) {
                Text("入力期限警告余裕: \(settings.lateEntryThresholdDays) 日")
            }
            Toggle("優良電子帳簿の届出書を提出済", isOn: $hasFiledNotification)
                .onChange(of: hasFiledNotification) { _, value in UserDefaults.standard.set(value, forKey: "controlRoute.hasFiledOptimalBookNotification") }
            Toggle("e-Tax で申告予定", isOn: $willUseEtax)
                .onChange(of: willUseEtax) { _, value in UserDefaults.standard.set(value, forKey: "controlRoute.willUseEtax") }
        }
    }
}
