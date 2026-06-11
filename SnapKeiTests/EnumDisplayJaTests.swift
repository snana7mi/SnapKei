import Testing
@testable import SnapKei

@Suite("EnumDisplayJa")
struct EnumDisplayJaTests {

    @Test func taxCategoryLabels() {
        #expect(TaxCategory.standard10.labelJa == "10%")
        #expect(TaxCategory.reduced8.labelJa == "8% 軽減")
        #expect(TaxCategory.nonTaxable.labelJa == "非課税")
        #expect(TaxCategory.outOfScope.labelJa == "対象外")
    }

    @Test func priceEntryModeLabels() {
        #expect(PriceEntryMode.taxIncluded.labelJa == "税込")
        #expect(PriceEntryMode.taxExcluded.labelJa == "税抜")
    }

    @Test func paymentMethodLabels_allCasesCovered() {
        // 全ケースに非空ラベルがあること（新ケース追加時の落とし穴防止）
        for method in PaymentMethod.allCases {
            #expect(!method.labelJa.isEmpty)
        }
        #expect(PaymentMethod.ownerLoan.labelJa == "事業主借")
        #expect(PaymentMethod.ownerWithdraw.labelJa == "事業主貸")
        #expect(PaymentMethod.accountsPayable.labelJa == "未払金")
    }

    @Test func recordSourceLabels_allCasesCovered() {
        for source in RecordSource.allCases {
            #expect(!source.labelJa.isEmpty)
        }
        #expect(RecordSource.aiParsed.labelJa == "AI解析（レシート撮影）")
    }

    @Test func activityTypeLabels_allCasesCovered() {
        for type in ActivityType.allCases {
            #expect(!type.labelJa.isEmpty)
        }
        #expect(ActivityType.createEntry.labelJa == "作成")
        #expect(ActivityType.editEntry.labelJa == "編集")
        #expect(ActivityType.voidEntry.labelJa == "取消")
    }
}
