import Foundation
import SwiftData

public enum SnapKeiModelContainer {
    @MainActor
    public static let shared: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration("SnapKei.sqlite")
            )
            AccountSeeder.seedIfNeeded(context: container.mainContext)
            AssetUsefulLifeSeeder.seedIfNeeded(context: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    @MainActor
    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let schema = Schema([
        Account.self,
        AssetUsefulLife.self,
        JournalEntry.self,
        SystemActivityLog.self,
        FixedAsset.self
    ])
}
