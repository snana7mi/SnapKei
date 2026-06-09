import Foundation

public struct LedgerPosting: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryId: UUID
    public let entryNumber: Int
    public let transactionDate: Date
    public let accountCode: String
    public let counterAccountCode: String
    public let debit: Int
    public let credit: Int
    public let summary: String
    public let isVoided: Bool
}

public struct LedgerLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryNumber: Int
    public let transactionDate: Date
    public let counterAccountCode: String
    public let summary: String
    public let debit: Int
    public let credit: Int
    /// Debit-signed running balance: assets/expenses positive, liabilities/equity/revenue negative.
    public let runningBalance: Int
}

public enum LedgerService {
    public static func postings(from entries: [JournalEntry]) -> [LedgerPosting] {
        entries
            .sorted {
                if $0.transactionDate == $1.transactionDate {
                    return $0.entryNumber < $1.entryNumber
                }
                return $0.transactionDate < $1.transactionDate
            }
            .flatMap { entry -> [LedgerPosting] in
                let summary = "\(entry.counterpartyName) \(entry.transactionDescription)"
                return [
                    LedgerPosting(
                        id: "\(entry.id)-d",
                        entryId: entry.id,
                        entryNumber: entry.entryNumber,
                        transactionDate: entry.transactionDate,
                        accountCode: entry.debitAccountCode,
                        counterAccountCode: entry.creditAccountCode,
                        debit: entry.amountIncludingTax,
                        credit: 0,
                        summary: summary,
                        isVoided: entry.isVoided
                    ),
                    LedgerPosting(
                        id: "\(entry.id)-c",
                        entryId: entry.id,
                        entryNumber: entry.entryNumber,
                        transactionDate: entry.transactionDate,
                        accountCode: entry.creditAccountCode,
                        counterAccountCode: entry.debitAccountCode,
                        debit: 0,
                        credit: entry.amountIncludingTax,
                        summary: summary,
                        isVoided: entry.isVoided
                    ),
                ]
            }
    }

    public static func ledgerLines(accountCode: String, fiscalYear: Int, openingBalance: Int, entries: [JournalEntry]) -> [LedgerLine] {
        var balance = openingBalance
        return postings(from: entries.filter { $0.fiscalYear == fiscalYear })
            .filter { $0.accountCode == accountCode && !$0.isVoided }
            .map { posting in
                balance += posting.debit - posting.credit
                return LedgerLine(
                    id: posting.id,
                    entryNumber: posting.entryNumber,
                    transactionDate: posting.transactionDate,
                    counterAccountCode: posting.counterAccountCode,
                    summary: posting.summary,
                    debit: posting.debit,
                    credit: posting.credit,
                    runningBalance: balance
                )
            }
    }

    public static func missingEntryNumbers(entries: [JournalEntry]) -> [Int] {
        let numbers = Set(entries.map(\.entryNumber))
        guard let maxNumber = numbers.max(), maxNumber >= 1 else { return [] }
        return (1...maxNumber).filter { !numbers.contains($0) }
    }
}
