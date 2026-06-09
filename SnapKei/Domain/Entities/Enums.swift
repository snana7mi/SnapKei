import Foundation

public enum TaxCategory: String, Codable, Sendable, CaseIterable {
    case standard10
    case reduced8
    case nonTaxable
    case outOfScope
}

public enum PriceEntryMode: String, Codable, Sendable, CaseIterable {
    case taxIncluded
    case taxExcluded
}

public enum PaymentMethod: String, Codable, Sendable, CaseIterable {
    case cash
    case creditCard
    case bankTransfer
    case ownerLoan
    case ownerWithdraw
    case accountsPayable
    case other
}

public enum RecordSource: String, Codable, Sendable, CaseIterable {
    case aiParsed
    case electronicTransaction
    case manual
    case imported
    case depreciation
}

public enum AccountType: String, Codable, Sendable, CaseIterable {
    case asset
    case liability
    case equity
    case revenue
    case expense
}

public enum AssetTreatment: String, Codable, Sendable, CaseIterable {
    case normalDepreciation
    case lumpSumDepreciation
    case smallAmountFullExpense
}

public enum DepreciationMethod: String, Codable, Sendable, CaseIterable {
    case straightLine
    // 定率法 was removed pre-launch because it was previously computed as straight-line.
    // Reintroduce only with a correct Japanese declining-balance implementation.
}

public enum AIChannel: String, Codable, Sendable, CaseIterable {
    case directApiKey
    case builtInProxy
}

public enum APIFormat: String, Codable, Sendable, CaseIterable {
    case openAI
    case anthropic
}
