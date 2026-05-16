import Testing
import Foundation
import SwiftData
@testable import SnapKei

@Suite("Seeders", .serialized)
struct SeederTests {

    @MainActor
    @Test func accountSeeder_seedsExpected33Accounts() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)

        let all = try ctx.fetch(FetchDescriptor<Account>())
        #expect(all.count == 33)
    }

    @MainActor
    @Test func accountSeeder_isIdempotent() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)
        AccountSeeder.seedIfNeeded(context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Account>()) == 33)
    }

    @MainActor
    @Test func accountSeeder_expenseAccountsHaveNonNilAllocation() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AccountSeeder.seedIfNeeded(context: ctx)

        let utilities = try ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.code == "5170" })).first
        #expect(utilities?.defaultBusinessAllocationRate == 0.3)
    }

    @MainActor
    @Test func assetUsefulLifeSeeder_seeds7() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AssetUsefulLifeSeeder.seedIfNeeded(context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<AssetUsefulLife>()) == 7)
    }

    @MainActor
    @Test func assetUsefulLifeSeeder_pcIs4Years() throws {
        let container = try SnapKeiModelContainer.inMemory()
        let ctx = container.mainContext
        AssetUsefulLifeSeeder.seedIfNeeded(context: ctx)

        let pc = try ctx.fetch(FetchDescriptor<AssetUsefulLife>(predicate: #Predicate { $0.code == "PC" })).first
        #expect(pc?.years == 4)
    }
}
