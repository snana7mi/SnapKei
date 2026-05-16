import Foundation
import SwiftData

public enum AccountSeeder {
    private struct Row: Decodable {
        let code: String
        let nameJa: String
        let nameZh: String
        let accountType: String
        let defaultBusinessAllocationRate: Double?
    }

    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        guard existing == 0 else { return }
        seed(context: context)
    }

    public static func seed(context: ModelContext) {
        guard let data = seedData(named: "accounts_seed"),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else {
            assertionFailure("accounts_seed.json missing or invalid")
            return
        }

        for row in rows {
            guard let type = AccountType(rawValue: row.accountType) else { continue }
            let account = Account(
                code: row.code,
                nameJa: row.nameJa,
                nameZh: row.nameZh,
                accountType: type,
                isBuiltin: true,
                isActive: true,
                defaultBusinessAllocationRate: row.defaultBusinessAllocationRate ?? 1.0
            )
            context.insert(account)
        }
        try? context.save()
    }

    private static func seedData(named name: String) -> Data? {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
}

private final class BundleToken {}
