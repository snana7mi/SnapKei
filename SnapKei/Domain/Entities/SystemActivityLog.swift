import Foundation
import SwiftData

public enum ActivityType: String, Codable, Sendable, CaseIterable {
    case createEntry
    case editEntry
    case voidEntry
    case unlockPeriod
    case fiscalYearTransition
    case aiParsing
}

@Model
public final class SystemActivityLog {
    @Attribute(.unique) public var id: UUID
    public var occurredAt: Date
    public var actorDeviceId: String
    public var activityTypeRaw: String
    public var targetEntryId: UUID?
    public var beforeSnapshot: Data?
    public var afterSnapshot: Data?
    public var reason: String?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        actorDeviceId: String,
        activityType: ActivityType,
        targetEntryId: UUID? = nil,
        beforeSnapshot: Data? = nil,
        afterSnapshot: Data? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.actorDeviceId = actorDeviceId
        self.activityTypeRaw = activityType.rawValue
        self.targetEntryId = targetEntryId
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
        self.reason = reason
    }

    public var activityType: ActivityType {
        ActivityType(rawValue: activityTypeRaw) ?? .editEntry
    }
}
