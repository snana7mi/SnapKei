import Foundation
import SwiftData

public protocol ExpenseRepository: Sendable {
    func create(_ entry: JournalEntry, reason: String?) throws
    func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws
    func void(_ entry: JournalEntry, reason: String?) throws
    func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry]
    func nextEntryNumber(for fiscalYear: Int) throws -> Int
}

public struct ExpenseSearchCriteria: Sendable {
    public var dateFrom: Date?
    public var dateTo: Date?
    public var debitAccountCodes: [String]?
    public var amountMin: Int?
    public var amountMax: Int?
    public var qualifiedOnly: Bool?
    public var lateEntryOnly: Bool?
    public var includeVoided: Bool

    public init(
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        debitAccountCodes: [String]? = nil,
        amountMin: Int? = nil,
        amountMax: Int? = nil,
        qualifiedOnly: Bool? = nil,
        lateEntryOnly: Bool? = nil,
        includeVoided: Bool = false
    ) {
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.debitAccountCodes = debitAccountCodes
        self.amountMin = amountMin
        self.amountMax = amountMax
        self.qualifiedOnly = qualifiedOnly
        self.lateEntryOnly = lateEntryOnly
        self.includeVoided = includeVoided
    }
}

public final class SwiftDataExpenseRepository: ExpenseRepository, @unchecked Sendable {
    private let context: ModelContext
    private let deviceId: String

    public init(context: ModelContext, deviceId: String) {
        self.context = context
        self.deviceId = deviceId
    }

    public func create(_ entry: JournalEntry, reason: String? = nil) throws {
        let assigned = try nextEntryNumber(for: entry.fiscalYear)
        entry.entryNumber = assigned
        entry.createdAt = Date()
        entry.updatedAt = entry.createdAt

        context.insert(entry)

        let after = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .createEntry,
            targetEntryId: entry.id,
            beforeSnapshot: nil,
            afterSnapshot: after,
            reason: reason
        )
        context.insert(log)
        try context.save()
    }

    public func edit(_ entry: JournalEntry, applying change: () -> Void, reason: String?) throws {
        let before = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        change()
        entry.updatedAt = Date()
        let after = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))

        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .editEntry,
            targetEntryId: entry.id,
            beforeSnapshot: before,
            afterSnapshot: after,
            reason: reason
        )
        context.insert(log)
        try context.save()
    }

    public func void(_ entry: JournalEntry, reason: String?) throws {
        let before = try? JSONEncoder().encode(JournalEntrySnapshot(from: entry))
        entry.isVoided = true
        entry.updatedAt = Date()

        let log = SystemActivityLog(
            actorDeviceId: deviceId,
            activityType: .voidEntry,
            targetEntryId: entry.id,
            beforeSnapshot: before,
            afterSnapshot: nil,
            reason: reason
        )
        context.insert(log)
        try context.save()
    }

    public func search(criteria: ExpenseSearchCriteria) throws -> [JournalEntry] {
        var descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse), SortDescriptor(\.entryNumber, order: .reverse)]
        )
        descriptor.fetchLimit = nil
        var results = try context.fetch(descriptor)

        if !criteria.includeVoided {
            results = results.filter { !$0.isVoided }
        }
        if let from = criteria.dateFrom {
            results = results.filter { $0.transactionDate >= from }
        }
        if let to = criteria.dateTo {
            let endOfDay = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: 1, to: Calendar(identifier: .gregorian).startOfDay(for: to)) ?? to
            results = results.filter { $0.transactionDate < endOfDay }
        }
        if let codes = criteria.debitAccountCodes, !codes.isEmpty {
            let set = Set(codes)
            results = results.filter { set.contains($0.debitAccountCode) }
        }
        if let minA = criteria.amountMin {
            results = results.filter { $0.amountIncludingTax >= minA }
        }
        if let maxA = criteria.amountMax {
            results = results.filter { $0.amountIncludingTax <= maxA }
        }
        if let q = criteria.qualifiedOnly {
            results = results.filter { $0.invoiceQualified == q }
        }
        if let l = criteria.lateEntryOnly, l {
            results = results.filter { $0.isLateEntry }
        }
        return results
    }

    public func nextEntryNumber(for fiscalYear: Int) throws -> Int {
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )
        descriptor.sortBy = [SortDescriptor(\.entryNumber, order: .reverse)]
        descriptor.fetchLimit = 1
        let last = try context.fetch(descriptor).first
        return (last?.entryNumber ?? 0) + 1
    }
}

public struct JournalEntrySnapshot: Codable {
    let id: UUID
    let entryNumber: Int
    let fiscalYear: Int
    let transactionDate: Date
    let inputDate: Date
    let isLateEntry: Bool
    let debitAccountCode: String
    let creditAccountCode: String
    let amountIncludingTax: Int
    let amountExcludingTax: Int
    let consumptionTax: Int
    let taxCategoryRaw: String
    let priceEntryModeRaw: String
    let paymentMethodRaw: String
    let counterpartyName: String
    let invoiceRegistrationNumber: String?
    let invoiceQualified: Bool
    let transitionalMeasureRate: Double
    let transactionDescription: String
    let memo: String?
    let businessAllocationRate: Double
    let originalAmountIncludingTax: Int?
    let relatedFixedAssetId: UUID?
    let receiptImagePath: String?
    let receiptImageHash: String?
    let sourceTypeRaw: String
    let createdAt: Date
    let updatedAt: Date
    let syncId: UUID
    let isVoided: Bool

    init(from e: JournalEntry) {
        self.id = e.id
        self.entryNumber = e.entryNumber
        self.fiscalYear = e.fiscalYear
        self.transactionDate = e.transactionDate
        self.inputDate = e.inputDate
        self.isLateEntry = e.isLateEntry
        self.debitAccountCode = e.debitAccountCode
        self.creditAccountCode = e.creditAccountCode
        self.amountIncludingTax = e.amountIncludingTax
        self.amountExcludingTax = e.amountExcludingTax
        self.consumptionTax = e.consumptionTax
        self.taxCategoryRaw = e.taxCategoryRaw
        self.priceEntryModeRaw = e.priceEntryModeRaw
        self.paymentMethodRaw = e.paymentMethodRaw
        self.counterpartyName = e.counterpartyName
        self.invoiceRegistrationNumber = e.invoiceRegistrationNumber
        self.invoiceQualified = e.invoiceQualified
        self.transitionalMeasureRate = e.transitionalMeasureRate
        self.transactionDescription = e.transactionDescription
        self.memo = e.memo
        self.businessAllocationRate = e.businessAllocationRate
        self.originalAmountIncludingTax = e.originalAmountIncludingTax
        self.relatedFixedAssetId = e.relatedFixedAssetId
        self.receiptImagePath = e.receiptImagePath
        self.receiptImageHash = e.receiptImageHash
        self.sourceTypeRaw = e.sourceTypeRaw
        self.createdAt = e.createdAt
        self.updatedAt = e.updatedAt
        self.syncId = e.syncId
        self.isVoided = e.isVoided
    }
}
