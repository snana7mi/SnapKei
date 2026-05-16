import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var appSettings: AppSettings
    public var aiSettings: AISettings

    public init(appSettings: AppSettings = AppSettings.load(), aiSettings: AISettings = AISettings.load()) {
        self.appSettings = appSettings
        self.aiSettings = aiSettings
    }

    public func saveApp() { appSettings.save() }
    public func saveAI() { aiSettings.save() }
}
