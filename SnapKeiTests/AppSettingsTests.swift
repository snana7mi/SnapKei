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
        #expect(d.lateEntryThresholdDays == ComplianceConstants.defaultLateEntryThresholdDays)
    }

    @Test func roundTrip_persistsAllFields() {
        let defaults = suiteDefaults()
        let s = AppSettings(
            businessName: "Lee 個人事業",
            ownerName: "Zhang Xiaotian",
            ownInvoiceRegistrationNumber: "T1234567890123",
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

    @Test func load_ignoresStaleFiscalYearStartMonthKey() {
        // 個人事業主の会計期間は暦年固定（所得税法）。旧バージョンが残した
        // 設定キーは読み込みに影響しないこと。
        let defaults = suiteDefaults()
        defaults.set(4, forKey: "app.fiscalYearStartMonth")
        let loaded = AppSettings.load(defaults: defaults)
        #expect(loaded == AppSettings.default)
    }

    @Test func hasCompletedOnboarding_defaultsFalse_andRoundTrips() {
        let defaults = suiteDefaults()
        #expect(AppSettings.load(defaults: defaults).hasCompletedOnboarding == false)

        var settings = AppSettings.load(defaults: defaults)
        settings.hasCompletedOnboarding = true
        settings.save(defaults: defaults)
        #expect(AppSettings.load(defaults: defaults).hasCompletedOnboarding == true)
    }
}
