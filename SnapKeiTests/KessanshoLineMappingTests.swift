import Foundation
import Testing
@testable import SnapKei

@Suite("KessanshoLineMapping")
struct KessanshoLineMappingTests {
    @Test func mapsAllSeedExpenseCodesToExpectedRows_tableDriven() {
        let names = [
            "5100": "旅費交通費",
            "5110": "通信費",
            "5120": "接待交際費",
            "5130": "会議費",
            "5140": "消耗品費",
            "5150": "事務用品費",
            "5160": "新聞図書費",
            "5170": "水道光熱費",
            "5180": "地代家賃",
            "5190": "外注工賃",
            "5200": "支払手数料",
            "5210": "修繕費",
            "5220": "租税公課",
            "5230": "減価償却費",
            "5290": "雑費",
        ]
        let expenseByCode = [
            "5100": 5_100,
            "5110": 5_110,
            "5120": 5_120,
            "5130": 5_130,
            "5140": 5_140,
            "5150": 5_150,
            "5160": 5_160,
            "5170": 5_170,
            "5180": 5_180,
            "5190": 5_190,
            "5200": 5_200,
            "5210": 5_210,
            "5220": 5_220,
            "5230": 5_230,
            "5290": 5_290,
        ]

        let lines = KessanshoLineMapping.expenseLines(
            expenseByCode: expenseByCode,
            accountNameByCode: names
        )

        #expect(lines == [
            KessanshoExpenseLine(label: "租税公課", amount: 5_220),
            KessanshoExpenseLine(label: "水道光熱費", amount: 5_170),
            KessanshoExpenseLine(label: "旅費交通費", amount: 5_100),
            KessanshoExpenseLine(label: "通信費", amount: 5_110),
            KessanshoExpenseLine(label: "接待交際費", amount: 5_120),
            KessanshoExpenseLine(label: "修繕費", amount: 5_210),
            KessanshoExpenseLine(label: "消耗品費", amount: 5_140),
            KessanshoExpenseLine(label: "減価償却費", amount: 5_230),
            KessanshoExpenseLine(label: "外注工賃", amount: 5_190),
            KessanshoExpenseLine(label: "地代家賃", amount: 5_180),
            KessanshoExpenseLine(label: "会議費", amount: 5_130),
            KessanshoExpenseLine(label: "事務用品費", amount: 5_150),
            KessanshoExpenseLine(label: "新聞図書費", amount: 5_160),
            KessanshoExpenseLine(label: "支払手数料", amount: 5_200),
            KessanshoExpenseLine(label: "雑費", amount: 5_290),
        ])
    }

    @Test func customAccountsBecomeBlankRows_orderedByCode() {
        let names = ["5130": "会議費", "5150": "事務用品費", "5160": "新聞図書費", "5200": "支払手数料"]

        let lines = KessanshoLineMapping.expenseLines(
            expenseByCode: ["5200": 400, "5130": 100, "5160": 300, "5150": 200],
            accountNameByCode: names
        )

        #expect(lines == [
            KessanshoExpenseLine(label: "会議費", amount: 100),
            KessanshoExpenseLine(label: "事務用品費", amount: 200),
            KessanshoExpenseLine(label: "新聞図書費", amount: 300),
            KessanshoExpenseLine(label: "支払手数料", amount: 400),
        ])
    }

    @Test func sixthCustomFoldsIntoMisc() {
        var expenseByCode: [String: Int] = [:]
        var names: [String: String] = [:]
        for i in 1...6 {
            let code = "900\(i)"
            expenseByCode[code] = i * 100
            names[code] = "カスタム\(i)"
        }

        let lines = KessanshoLineMapping.expenseLines(
            expenseByCode: expenseByCode,
            accountNameByCode: names
        )

        #expect(lines == [
            KessanshoExpenseLine(label: "カスタム1", amount: 100),
            KessanshoExpenseLine(label: "カスタム2", amount: 200),
            KessanshoExpenseLine(label: "カスタム3", amount: 300),
            KessanshoExpenseLine(label: "カスタム4", amount: 400),
            KessanshoExpenseLine(label: "カスタム5", amount: 500),
            KessanshoExpenseLine(label: "雑費", amount: 600),
        ])
    }

    @Test func zeroAmountRowsAreOmitted() {
        let lines = KessanshoLineMapping.expenseLines(
            expenseByCode: ["5110": 0, "5130": 0, "5230": 24_000],
            accountNameByCode: ["5110": "通信費", "5130": "会議費", "5230": "減価償却費"]
        )

        #expect(lines == [KessanshoExpenseLine(label: "減価償却費", amount: 24_000)])
    }

    @Test func miscAccountAndOverflowCombine() {
        var expenseByCode = ["5290": 500]
        var names = ["5290": "雑費"]
        for i in 1...6 {
            let code = "800\(i)"
            expenseByCode[code] = 10
            names[code] = "custom\(i)"
        }

        let lines = KessanshoLineMapping.expenseLines(
            expenseByCode: expenseByCode,
            accountNameByCode: names
        )

        #expect(lines.first { $0.label == "雑費" } == KessanshoExpenseLine(label: "雑費", amount: 510))
    }
}
