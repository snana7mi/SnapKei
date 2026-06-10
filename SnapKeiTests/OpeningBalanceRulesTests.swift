import Testing
@testable import SnapKei

@Suite("OpeningBalanceRules")
struct OpeningBalanceRulesTests {

    @Test func editable_balanceSheetAccountsOnly() {
        #expect(OpeningBalanceRules.isEditable(code: "1110", type: .asset))
        #expect(OpeningBalanceRules.isEditable(code: "1710", type: .asset))
        #expect(OpeningBalanceRules.isEditable(code: "2310", type: .liability))
        #expect(!OpeningBalanceRules.isEditable(code: "4110", type: .revenue))
        #expect(!OpeningBalanceRules.isEditable(code: "5110", type: .expense))
    }

    @Test func editable_excludesCapitalAndOwnerAccounts() {
        // 元入金は自動調整、事業主貸/借は年度境界で元入金へ集約されるため期首は常に0。
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.capital, type: .equity))
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.ownerLoan, type: .equity))
        #expect(!OpeningBalanceRules.isEditable(code: AccountCode.ownerDraw, type: .equity))
    }

    @Test func storedAmount_signByAccountSide() {
        // ストレージは借方プラス: 資産 +、負債/資本 −。
        #expect(OpeningBalanceRules.storedAmount(entered: 100_000, code: "1110", type: .asset) == 100_000)
        #expect(OpeningBalanceRules.storedAmount(entered: 300_000, code: "2310", type: .liability) == -300_000)
        #expect(OpeningBalanceRules.storedAmount(entered: 50_000, code: "3110", type: .equity) == -50_000)
    }

    @Test func storedAmount_contraAsset1710_isNegative() {
        // 減価償却累計額は資産型だが貸方性質（コントラ）。正の入力を負で保存する。
        #expect(OpeningBalanceRules.storedAmount(entered: 120_000, code: "1710", type: .asset) == -120_000)
    }

    @Test func displayAmount_roundTripsStoredAmount() {
        let cases: [(Int, String, AccountType)] = [
            (250_000, "1110", .asset),
            (120_000, "1710", .asset),
            (300_000, "2310", .liability),
        ]
        for (entered, code, type) in cases {
            let stored = OpeningBalanceRules.storedAmount(entered: entered, code: code, type: type)
            #expect(OpeningBalanceRules.displayAmount(stored: stored, code: code, type: type) == entered)
        }
    }
}
