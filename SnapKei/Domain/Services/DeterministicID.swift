import Foundation
import CryptoKit

/// Derives a stable UUID from a natural-key string so that independent devices generate the
/// SAME sync identity for the same logical record (e.g. one 元入金 row per fiscal-year/account,
/// one closure per fiscal year). This lets last-write-wins collapse cross-device duplicates
/// instead of leaving orphaned server rows.
public enum DeterministicID {
    public nonisolated static func uuid(for key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension OpeningBalance {
    public nonisolated static func deterministicSyncId(fiscalYear: Int, accountCode: String) -> UUID {
        DeterministicID.uuid(for: "OpeningBalance:\(fiscalYear):\(accountCode)")
    }
}

extension FiscalYearClosure {
    public nonisolated static func deterministicSyncId(fiscalYear: Int) -> UUID {
        DeterministicID.uuid(for: "FiscalYearClosure:\(fiscalYear)")
    }
}
