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

    /// 表示中の仕訳を 収入/支出 に分けて合計する（振替は資金移動なので除外）。
    public func totals(accountTypes: (String) -> AccountType?) -> (income: Int, expense: Int) {
        var income = 0
        var expense = 0
        for entry in entries {
            let debitType = accountTypes(entry.debitAccountCode)
            let creditType = accountTypes(entry.creditAccountCode)
            switch ManualEntryRules.kind(debitType: debitType, creditType: creditType) {
            case .income:
                income += creditType == .revenue ? entry.amountIncludingTax : -entry.amountIncludingTax
            case .expense:
                expense += (debitType == .expense ? 1 : -1) * entry.amountIncludingTax
            case .transfer:
                break
            }
        }
        return (income, expense)
    }
}
