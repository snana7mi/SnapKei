import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var appSettings: AppSettings
    public var aiSettings: AISettings
    private var savedAppSettings: AppSettings
    private var savedAISettings: AISettings

    public init(appSettings: AppSettings = AppSettings.load(), aiSettings: AISettings = AISettings.load()) {
        self.appSettings = appSettings
        self.aiSettings = aiSettings
        self.savedAppSettings = appSettings
        self.savedAISettings = aiSettings
    }

    public var hasUnsavedChanges: Bool {
        appSettings != savedAppSettings || aiSettings != savedAISettings
    }

    public func saveAll() {
        appSettings.save()
        aiSettings.save()
        savedAppSettings = appSettings
        savedAISettings = aiSettings
    }

    public func saveApp() {
        appSettings.save()
        savedAppSettings = appSettings
    }

    public func saveAI() {
        aiSettings.save()
        savedAISettings = aiSettings
    }

    public func discard() {
        appSettings = savedAppSettings
        aiSettings = savedAISettings
    }
}
