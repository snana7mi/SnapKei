import Foundation

public struct AppSettings: Sendable, Equatable {
    public var businessName: String
    public var ownerName: String
    public var ownInvoiceRegistrationNumber: String
    public var fiscalYearStartMonth: Int
    public var lateEntryThresholdDays: Int
    public var hasCompletedOnboarding: Bool

    public static let `default` = AppSettings(
        businessName: "",
        ownerName: "",
        ownInvoiceRegistrationNumber: "",
        fiscalYearStartMonth: 1,
        lateEntryThresholdDays: ComplianceConstants.defaultLateEntryThresholdDays,
        hasCompletedOnboarding: false
    )

    public nonisolated init(
        businessName: String,
        ownerName: String,
        ownInvoiceRegistrationNumber: String,
        fiscalYearStartMonth: Int,
        lateEntryThresholdDays: Int,
        hasCompletedOnboarding: Bool = false
    ) {
        self.businessName = businessName
        self.ownerName = ownerName
        self.ownInvoiceRegistrationNumber = ownInvoiceRegistrationNumber
        self.fiscalYearStartMonth = fiscalYearStartMonth
        self.lateEntryThresholdDays = lateEntryThresholdDays
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum Keys {
        nonisolated static let businessName = "app.businessName"
        nonisolated static let ownerName = "app.ownerName"
        nonisolated static let ownInvoiceRegistrationNumber = "app.ownInvoiceRegistrationNumber"
        nonisolated static let fiscalYearStartMonth = "app.fiscalYearStartMonth"
        nonisolated static let lateEntryThresholdDays = "app.lateEntryThresholdDays"
        nonisolated static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
    }

    public nonisolated static func load(defaults: UserDefaults = .standard) -> AppSettings {
        let storedFy = defaults.integer(forKey: Keys.fiscalYearStartMonth)
        let storedTh = defaults.integer(forKey: Keys.lateEntryThresholdDays)
        return AppSettings(
            businessName: defaults.string(forKey: Keys.businessName) ?? "",
            ownerName: defaults.string(forKey: Keys.ownerName) ?? "",
            ownInvoiceRegistrationNumber: defaults.string(forKey: Keys.ownInvoiceRegistrationNumber) ?? "",
            fiscalYearStartMonth: storedFy >= 1 && storedFy <= 12 ? storedFy : 1,
            lateEntryThresholdDays: storedTh > 0 ? storedTh : ComplianceConstants.defaultLateEntryThresholdDays,
            hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding)
        )
    }

    public nonisolated func save(defaults: UserDefaults = .standard) {
        defaults.set(businessName, forKey: Keys.businessName)
        defaults.set(ownerName, forKey: Keys.ownerName)
        defaults.set(ownInvoiceRegistrationNumber, forKey: Keys.ownInvoiceRegistrationNumber)
        defaults.set(fiscalYearStartMonth, forKey: Keys.fiscalYearStartMonth)
        defaults.set(lateEntryThresholdDays, forKey: Keys.lateEntryThresholdDays)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
    }
}
