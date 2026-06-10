import SwiftData
import SwiftUI

/// 期首残高の閲覧・編集。コミットごとに元入金を自動調整（adjustCapitalToBalance）。
/// 締め済み年度は読み取り専用。ユーザーは常に正数で入力し、符号は OpeningBalanceRules が扱う。
struct OpeningBalanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var closures: [FiscalYearClosure]

    let fiscalYear: Int

    @State private var storedByCode: [String: Int] = [:]
    @State private var hasAutoRolled = false
    @State private var drafts: [String: String] = [:]
    @State private var errorMessage: String?
    @FocusState private var focusedCode: String?

    var body: some View {
        List {
            if isClosed {
                Section {
                    Label("締め済みの年度です。年次締めから再オープンすると編集できます。", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if hasAutoRolled {
                Section {
                    Label("前年の年次締めから自動繰越された値です。編集すると手動値になり、前年を再締めすると上書きされます。", systemImage: "arrow.uturn.forward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            summarySection
            accountSection("資産", type: .asset)
            accountSection("負債", type: .liability)
            accountSection("資本（元入金・事業主貸借を除く）", type: .equity)

            Section {
                Text("開業初年度は通常入力不要です。アプリ導入前から事業を行っている場合は前年末時点の残高を入力してください。引継ぎ固定資産は取得価額を 工具器具備品、償却累計額を 減価償却累計額（控除）に入力します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(verbatim: "期首残高 \(fiscalYear)年"))
        .task { reload() }
        .onChange(of: focusedCode) { previous, _ in
            if let previous { commit(code: previous) }
        }
        .onDisappear {
            // numberPad には Return が無く、フォーカスを残したまま戻ると
            // onChange が届かないことがあるため、離脱時にも確実にコミットする。
            if let code = focusedCode { commit(code: code) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedCode = nil }
            }
        }
        .alert(
            "保存できませんでした",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("サマリー") {
            row("資産合計", YenFormat.string(assetTotal))
            row("負債合計", YenFormat.string(liabilityTotal))
            HStack {
                Text("元入金（自動調整）")
                Spacer()
                Text(YenFormat.string(capitalDisplay))
                    .foregroundStyle(capitalDisplay < 0 ? Color.orange : Color.secondary)
                    .font(.body.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            if capitalDisplay < 0 {
                Label("元入金がマイナス（債務超過）です。入力値を確認してください。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func accountSection(_ title: String, type: AccountType) -> some View {
        let rows = editableAccounts(of: type)
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { account in
                    balanceRow(account)
                }
            }
        }
    }

    private func balanceRow(_ account: Account) -> some View {
        HStack {
            Text(label(for: account))
            Spacer()
            if isClosed {
                Text(YenFormat.string(displayValue(for: account)))
                    .foregroundStyle(.secondary)
                    .font(.body.monospacedDigit())
            } else {
                TextField("0", text: draftBinding(for: account.code))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .focused($focusedCode, equals: account.code)
                    .onSubmit { commit(code: account.code) }
                    .font(.body.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived values

    private var isClosed: Bool {
        closures.contains { $0.fiscalYear == fiscalYear && $0.deletedAt == nil }
    }

    private var typeByCode: [String: AccountType] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.code, $0.accountType) })
    }

    private func editableAccounts(of type: AccountType) -> [Account] {
        accounts.filter {
            $0.isActive && $0.accountType == type
                && OpeningBalanceRules.isEditable(code: $0.code, type: $0.accountType)
        }
    }

    private func label(for account: Account) -> String {
        OpeningBalanceRules.contraAssetCodes.contains(account.code)
            ? "\(account.nameJa)（控除・プラス入力）"
            : account.nameJa
    }

    private func displayValue(for account: Account) -> Int {
        OpeningBalanceRules.displayAmount(
            stored: storedByCode[account.code] ?? 0,
            code: account.code,
            type: account.accountType
        )
    }

    private var assetTotal: Int {
        storedByCode.reduce(0) { sum, item in
            typeByCode[item.key] == .asset ? sum + item.value : sum
        }
    }

    private var liabilityTotal: Int {
        -storedByCode.reduce(0) { sum, item in
            typeByCode[item.key] == .liability ? sum + item.value : sum
        }
    }

    /// 元入金は貸方プラス表示（stored は借方プラスのため反転）。マイナス = 債務超過。
    private var capitalDisplay: Int {
        -(storedByCode[AccountCode.capital] ?? 0)
    }

    // MARK: - Editing

    private func draftBinding(for code: String) -> Binding<String> {
        Binding(
            get: { drafts[code] ?? "" },
            set: { newValue in
                // Int 範囲超過（20桁超）は Int() が nil → 0 になり既存残高を静かに
                // 消すため、桁数も制限する（12桁 = 1兆円未満で実用十分）。
                drafts[code] = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(12))
            }
        )
    }

    private func commit(code: String) {
        guard !isClosed, let account = accounts.first(where: { $0.code == code }) else { return }
        let entered = Int(drafts[code] ?? "") ?? 0
        let stored = OpeningBalanceRules.storedAmount(entered: entered, code: code, type: account.accountType)
        guard stored != (storedByCode[code] ?? 0) else { return }
        let store = OpeningBalanceStore(context: context)
        do {
            try store.set(fiscalYear: fiscalYear, accountCode: code, amount: stored)
            try store.adjustCapitalToBalance(fiscalYear: fiscalYear)
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    private func reload() {
        let store = OpeningBalanceStore(context: context)
        let rows = (try? store.rows(fiscalYear: fiscalYear)) ?? []
        storedByCode = Dictionary(rows.map { ($0.accountCode, $0.amount) }, uniquingKeysWith: { first, _ in first })
        // 元入金は導出行として常に isAutoRolled — 繰越バナーの判定からは除外する。
        hasAutoRolled = rows.contains { $0.isAutoRolled && $0.accountCode != AccountCode.capital }
        var newDrafts: [String: String] = [:]
        for account in accounts where OpeningBalanceRules.isEditable(code: account.code, type: account.accountType) {
            let display = displayValue(for: account)
            newDrafts[account.code] = display == 0 ? "" : String(display)
        }
        drafts = newDrafts
    }
}
