import Testing
import Foundation
@testable import SnapKei

@Suite("AppSettings")
struct AppSettingsTests {

    private func suiteDefaults(_ id: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: id)!
    }

    @Test func default_hasSaneInitialValues() {
        let d = AppSettings.default
        #expect(d.businessName.isEmpty)
        #expect(d.fiscalYearStartMonth == 1)
        #expect(d.lateEntryThresholdDays == ComplianceConstants.defaultLateEntryThresholdDays)
    }

    @Test func roundTrip_persistsAllFields() {
        let defaults = suiteDefaults()
        let s = AppSettings(
            businessName: "Lee 個人事業",
            ownerName: "Zhang Xiaotian",
            ownInvoiceRegistrationNumber: "T1234567890123",
            fiscalYearStartMonth: 1,
            lateEntryThresholdDays: 30
        )
        s.save(defaults: defaults)

        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded == s)
    }

    @Test func load_emptyDefaults_returnsDefault() {
        let defaults = suiteDefaults()
        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded == AppSettings.default)
    }

    @Test func load_invalidFiscalMonth_falls_back_to_1() {
        let defaults = suiteDefaults()
        defaults.set(99, forKey: "app.fiscalYearStartMonth")
        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded.fiscalYearStartMonth == 1)
    }
}
