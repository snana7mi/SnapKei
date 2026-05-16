import Foundation
import SwiftData

public enum AssetUsefulLifeSeeder {
    private struct Row: Decodable {
        let code: String
        let nameJa: String
        let nameZh: String
        let years: Int
    }

    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<AssetUsefulLife>())) ?? 0
        guard existing == 0 else { return }
        seed(context: context)
    }

    public static func seed(context: ModelContext) {
        guard let data = seedData(named: "asset_useful_life_seed"),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else {
            assertionFailure("asset_useful_life_seed.json missing or invalid")
            return
        }

        for row in rows {
            let entry = AssetUsefulLife(
                code: row.code,
                nameJa: row.nameJa,
                nameZh: row.nameZh,
                years: row.years,
                isBuiltin: true
            )
            context.insert(entry)
        }
        try? context.save()
    }

    private static func seedData(named name: String) -> Data? {
        let bundles = [Bundle.main, Bundle(for: AssetUsefulLifeBundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
}

private final class AssetUsefulLifeBundleToken {}
