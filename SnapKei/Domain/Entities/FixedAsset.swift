import Foundation
import SwiftData

@Model
public final class FixedAsset {
    @Attribute(.unique) public var id: UUID
    public var assetName: String
    public var assetCategoryCode: String
    public var acquisitionDate: Date
    public var serviceStartDate: Date
    public var acquisitionAmount: Int
    public var usefulLifeYears: Int
    public var depreciationMethodRaw: String
    public var treatmentRaw: String
    public var businessAllocationRate: Double
    public var acquisitionJournalEntryId: UUID?
    public var accumulatedDepreciation: Int
    public var bookValue: Int
    public var disposalDate: Date?
    public var disposalAmount: Int?
    public var syncId: UUID
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        assetName: String,
        assetCategoryCode: String,
        acquisitionDate: Date,
        serviceStartDate: Date,
        acquisitionAmount: Int,
        usefulLifeYears: Int,
        depreciationMethod: DepreciationMethod = .straightLine,
        treatment: AssetTreatment,
        businessAllocationRate: Double = 1.0,
        acquisitionJournalEntryId: UUID? = nil,
        accumulatedDepreciation: Int = 0,
        bookValue: Int? = nil,
        disposalDate: Date? = nil,
        disposalAmount: Int? = nil,
        syncId: UUID = UUID(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.assetName = assetName
        self.assetCategoryCode = assetCategoryCode
        self.acquisitionDate = acquisitionDate
        self.serviceStartDate = serviceStartDate
        self.acquisitionAmount = acquisitionAmount
        self.usefulLifeYears = usefulLifeYears
        self.depreciationMethodRaw = depreciationMethod.rawValue
        self.treatmentRaw = treatment.rawValue
        self.businessAllocationRate = businessAllocationRate
        self.acquisitionJournalEntryId = acquisitionJournalEntryId
        self.accumulatedDepreciation = accumulatedDepreciation
        self.bookValue = bookValue ?? acquisitionAmount
        self.disposalDate = disposalDate
        self.disposalAmount = disposalAmount
        self.syncId = syncId
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var depreciationMethod: DepreciationMethod {
        DepreciationMethod(rawValue: depreciationMethodRaw) ?? .straightLine
    }

    public var treatment: AssetTreatment {
        AssetTreatment(rawValue: treatmentRaw) ?? .normalDepreciation
    }
}
