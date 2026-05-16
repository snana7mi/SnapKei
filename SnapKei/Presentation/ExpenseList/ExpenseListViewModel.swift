import Foundation
import Observation

@MainActor
@Observable
public final class ExpenseListViewModel {
    public var searchText: String = ""
    public var criteria = ExpenseSearchCriteria()
    public var entries: [JournalEntry] = []

    private let repository: ExpenseRepository

    public init(repository: ExpenseRepository) {
        self.repository = repository
    }

    public func refresh() {
        do {
            var results = try repository.search(criteria: criteria)
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                results = results.filter {
                    $0.counterpartyName.localizedCaseInsensitiveContains(term) ||
                    $0.transactionDescription.localizedCaseInsensitiveContains(term)
                }
            }
            entries = results
        } catch {
            entries = []
        }
    }

    public var totalAmount: Int {
        entries.reduce(0) { $0 + $1.amountIncludingTax }
    }
}
