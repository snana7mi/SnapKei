import Foundation

// 個人事業主の会計期間は暦年固定（所得税法）のため、事業年度開始月の設定は存在しない。
public struct AppSettings: Sendable, Equatable {
    public var businessName: String
    public var ownerName: String
    public var ownInvoiceRegistrationNumber: String
    public var lateEntryThresholdDays: Int
    public var hasCompletedOnboarding: Bool

    public static let `default` = AppSettings(
        businessName: "",
        ownerName: "",
        ownInvoiceRegistrationNumber: "",
        lateEntryThresholdDays: ComplianceConstants.defaultLateEntryThresholdDays,
        hasCompletedOnboarding: false
    )

    public nonisolated init(
        businessName: String,
        ownerName: String,
        ownInvoiceRegistrationNumber: String,
        lateEntryThresholdDays: Int,
        hasCompletedOnboarding: Bool = false
    ) {
        self.businessName = businessName
        self.ownerName = ownerName
        self.ownInvoiceRegistrationNumber = ownInvoiceRegistrationNumber
        self.lateEntryThresholdDays = lateEntryThresholdDays
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum Keys {
        nonisolated static let businessName = "app.businessName"
        nonisolated static let ownerName = "app.ownerName"
        nonisolated static let ownInvoiceRegistrationNumber = "app.ownInvoiceRegistrationNumber"
        nonisolated static let lateEntryThresholdDays = "app.lateEntryThresholdDays"
        nonisolated static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
    }

    public nonisolated static func load(defaults: UserDefaults = .standard) -> AppSettings {
        let storedTh = defaults.integer(forKey: Keys.lateEntryThresholdDays)
        return AppSettings(
            businessName: defaults.string(forKey: Keys.businessName) ?? "",
            ownerName: defaults.string(forKey: Keys.ownerName) ?? "",
            ownInvoiceRegistrationNumber: defaults.string(forKey: Keys.ownInvoiceRegistrationNumber) ?? "",
            lateEntryThresholdDays: storedTh > 0 ? storedTh : ComplianceConstants.defaultLateEntryThresholdDays,
            hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding)
        )
    }

    public nonisolated func save(defaults: UserDefaults = .standard) {
        defaults.set(businessName, forKey: Keys.businessName)
        defaults.set(ownerName, forKey: Keys.ownerName)
        defaults.set(ownInvoiceRegistrationNumber, forKey: Keys.ownInvoiceRegistrationNumber)
        defaults.set(lateEntryThresholdDays, forKey: Keys.lateEntryThresholdDays)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
    }
}
