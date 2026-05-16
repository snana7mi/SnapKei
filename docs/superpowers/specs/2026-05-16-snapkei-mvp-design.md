# SnapKei MVP 设计文档

**日期**：2026-05-16
**版本**：v1
**状态**：待用户审阅
**位置**：`/Users/lee/workspace/SnapKei/`

---

## 1. 概述

SnapKei 是一款面向日本个人事业主（主要受众 IT エンジニア）的 iOS 经费管理 / 仕訳作成应用。核心流程：相机或 PDF → AI Vision 解析 → 復式簿記仕訳生成 → 本地保存（青色申告就绪）→ 期末損益計算書 PDF 出力。

### 1.1 产品定位
- **税务等级**：青色申告就绪 + 优良な電子帳簿目标（钉 65/75 万円控除路线）
- **法定合规**：電子帳簿保存法（スキャナ保存 + 電子取引データ保存）、インボイス制度（経過措置 5 段阶）、少額減価償却資産特例（2026.4 以降 40 万円、従業員 400 人以下前提）
- **目标年限**：MVP 上线 = 2026 年报税季前；为 2027 年（令和9年分）の 75 万円控除提前打基础
- **MVP 现实最大控除 = 65 万円**：75 万円控除には e-Tax 連携が必須だが MVP には e-Tax 提出機能を含めない。ユーザーは別途 e-Tax ソフト（または freee/弥生 の e-Tax 連携機能）で提出する必要あり

### 1.1.1 令和8年度税制改正による控除路線の整理（令和9年分以降）

| 控除額 | 要件 | MVP で達成可能か |
|---|---|---|
| 10万円 | 簡易記帳 + 紙申告。**前々年収入 1000万円超 → この控除も不可** | n/a（青色申告就绪が前提） |
| **65万円** | e-Tax 提出 + 仕訳帳/総勘定元帳 電子保存 | **MVP 可能**（e-Tax は外部ソフト経由） |
| **75万円** | 65万円要件 + 優良な電子帳簿 + **届出書事前提出** | **データ層は MVP 可能**、ただし届出書ユーザー提出 + e-Tax 外部経由 |

**廃止**：紙申告 55万円控除は令和9年分以降廃止。

### 1.2 技术栈
- Swift / SwiftUI
- iOS **18.5+**
- 本地数据库：**SwiftData**
- AI 解析：**Anthropic Claude API**（Vision、默认 `claude-haiku-4-5-20251001`、可切 `claude-sonnet-4-6`）
- 認証：**Sign in with Apple**（仅内置代理通道）
- 云端代理：**Cloudflare Worker**（Phase 3.5 部署）
- 本地化：**中文 / 日本語** 双语（zh = 开发主语言、ja = 生产用户）

### 1.3 非功能性需求
- 電帳法スキャナ保存合规（時間印付きファイル名 + SHA256 + 訂正・削除履歴 → タイムスタンプ付与不要ルート）
- 离线可用（除 AI 解析外的全部 4 个 Tab、设置、CSV 出力均离线工作）
- 多设备 Sync 不在 MVP（架构预留 `syncId` 字段）

---

## 2. 架构

### 2.1 分层（Clean Architecture、参考 ConchTalk）

```
SnapKei/
├── App/                        ReceiboApp.swift, RootView.swift
├── Domain/
│   ├── Entities/               JournalEntry / SystemActivityLog / Account / FixedAsset /
│   │                           AssetUsefulLife / ExpenseCategory enums
│   ├── Services/               ComplianceService / DepreciationService / PDFReportService /
│   │                           JSONExtractor / 协议: ReceiptParser
│   └── UseCases/               CreateJournalEntry / RecordAmendment / GenerateYearEndDepreciation
├── Data/
│   ├── Network/                AIFormatStrategy (protocol) / AnthropicFormatStrategy /
│   │                           OpenAIFormatStrategy (骨架) / AIRequestConfig /
│   │                           AIRouter / ClaudeVisionService / AIProxyService / AIServiceError
│   ├── Persistence/            ModelContainer + ExpenseRepository (entryNumber 連番 + 取引検索)
│   ├── Settings/               AISettings / AppSettings (屋号 / 適格番号 / 事業年度開始月)
│   ├── Security/               KeychainService (multi-key)
│   ├── Auth/                   AppleSignInService / AuthTokenStore / NonceGenerator
│   ├── ImagePreprocess/        ReceiptImageProcessor (EXIF / 解像度 / metadata / 圧縮)
│   ├── PDFImport/              ElectronicReceiptImporter
│   └── Storage/                ImageStorageService (時間印ファイル名 + SHA256)
├── Presentation/
│   ├── Home/                   HomeView + HomeViewModel (月概要 / 控除路線 / レポート)
│   ├── Capture/                CaptureView + CaptureViewModel + ConfirmationForm
│   ├── ExpenseList/            ExpenseListView + ExpenseListViewModel (検索 / 過濾 / CSV 出力)
│   └── Settings/               SettingsView + SettingsViewModel
└── Resources/
    └── Localizable.xcstrings   (zh + ja)

infra/
└── worker/                     Cloudflare Worker (TypeScript、独立 wrangler 项目)
```

### 2.2 依存方向

```
Presentation → Domain ← Data
```
- `Presentation` 仅依赖 `Domain/Services` 与 Entities，不直接 import `Data/*`
- `Data` 实现 `Domain` 中协议（如 `ReceiptParser`）
- `App` 完成 DI（ModelContainer / KeychainService / AIRouter 等单例注入）

---

## 3. データモデル（SwiftData）

### 3.1 `JournalEntry`（@Model、仕訳エントリ）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | 主键 |
| `entryNumber` | `Int` | 事業年度内連番（不可空洞、軟削除のみ） |
| `fiscalYear` | `Int` | 事業年度（西暦 YYYY） |
| `transactionDate` | `Date` | 取引日 |
| `inputDate` | `Date` | 入力日（スキャナ保存「入力期間内」判定用） |
| `isLateEntry` | `Bool` | (inputDate − transactionDate) が閾値超 / 跨期入力 → true |
| `debitAccountCode` | `String` | 借方科目（FK→Account.code） |
| `creditAccountCode` | `String` | 貸方科目 |
| `amountIncludingTax` | `Int` | 税込金額（按分後）、円整数 |
| `amountExcludingTax` | `Int` | 税抜金額 |
| `consumptionTax` | `Int` | 消費税額 |
| `taxCategory` | `TaxCategory` | `.standard10` / `.reduced8` / `.nonTaxable` / `.outOfScope` |
| `priceEntryMode` | `PriceEntryMode` | `.taxIncluded` / `.taxExcluded` |
| `paymentMethod` | `PaymentMethod` | `cash` / `creditCard` / `bankTransfer` / `ownerLoan` / `ownerWithdraw` / `accountsPayable` / `other` |
| `counterpartyName` | `String` | 取引先（仕訳帳必須項） |
| `invoiceRegistrationNumber` | `String?` | T+13桁 |
| `invoiceQualified` | `Bool` | 適格事業者か |
| `transitionalMeasureRate` | `Double` | 経過措置率（自動算出、5 段階） |
| `transactionDescription` | `String` | 取引内容（仕訳帳必須項、非空） |
| `memo` | `String?` | 内部 |
| `businessAllocationRate` | `Double` | 事業按分率（0.0–1.0、default 1.0） |
| `originalAmountIncludingTax` | `Int?` | 按分前金額（rate < 1.0 時のみ） |
| `relatedFixedAssetId` | `UUID?` | 固定資産との関連 |
| `receiptImagePath` | `String?` | Documents 相対パス |
| `receiptImageHash` | `String?` | SHA256 hex（相互関連性 + 改竄検出） |
| `sourceType` | `RecordSource` | `aiParsed` / `electronicTransaction` / `manual` / `imported` / `depreciation` |
| `createdAt` | `Date` | 入力時刻、不可変 |
| `updatedAt` | `Date` | |
| `syncId` | `UUID` | 同期予約（MVP 未使用） |
| `isVoided` | `Bool` | 軟削除 |

### 3.2 `SystemActivityLog`（@Model）

優良電子帳簿要件 ①「訂正・削除履歴の確保」（通常業務処理期間経過後の入力履歴を含む）+ システム操作監査 を 1 表で兼ねる。

| 字段 | 类型 |
|---|---|
| `id` | `UUID` |
| `occurredAt` | `Date` |
| `actorDeviceId` | `String` |
| `activityType` | `.createEntry` / `.editEntry` / `.voidEntry` / `.unlockPeriod` / `.fiscalYearTransition` / `.aiParsing` |
| `targetEntryId` | `UUID?` |
| `beforeSnapshot` | `Data?`（JournalEntry の JSON 全体スナップショット、編集前） |
| `afterSnapshot` | `Data?` |
| `reason` | `String?` |

### 3.3 `Account`（@Model、勘定科目マスタ）

`code` (4 桁) / `nameJa` / `nameZh` / `accountType` (`asset` / `liability` / `equity` / `revenue` / `expense`) / `isBuiltin` / `isActive` / `defaultBusinessAllocationRate: Double = 1.0`

**初始種值**（標準 33 科目、青色決算書順）：
- 資産：1110 現金 / 1210 普通預金 / 1310 売掛金 …
- 負債：2210 未払金 / 2310 借入金 …
- 純資産：3110 元入金 / 3210 事業主借 / 3220 事業主貸 …
- 売上：4110 売上高 …
- 費用：5100 旅費交通費 / 5110 通信費 / 5120 接待交際費 / 5130 会議費 / 5140 消耗品費 / 5150 事務用品費 / 5160 新聞図書費 / 5170 水道光熱費 / 5180 地代家賃 / 5190 外注工賃 / 5200 支払手数料 / 5210 修繕費 / 5220 租税公課 / 5230 減価償却費 / 5290 雑費

### 3.4 `FixedAsset`（@Model、固定資産台帳）

| 字段 | 类型 |
|---|---|
| `id` | `UUID` |
| `assetName` | `String` |
| `assetCategoryCode` | `String`（FK→AssetUsefulLife.code） |
| `acquisitionDate` | `Date` |
| `serviceStartDate` | `Date` |
| `acquisitionAmount` | `Int` |
| `usefulLifeYears` | `Int`（自動展開 from master） |
| `depreciationMethod` | `.straightLine` / `.decliningBalance` |
| `treatment` | `.normalDepreciation` / `.lumpSumDepreciation`（20万円未満 3 年均等） / `.smallAmountFullExpense`（青色限定 30/40 万円特例） |
| `businessAllocationRate` | `Double` |
| `acquisitionJournalEntryId` | `UUID?` |
| `accumulatedDepreciation` | `Int` |
| `bookValue` | `Int` |
| `disposalDate` / `disposalAmount` | `Date?` / `Int?` |
| `syncId` | `UUID` |

### 3.5 `AssetUsefulLife`（@Model、耐用年数マスタ）

`code` (e.g. "PC") / `nameJa` / `nameZh` / `years: Int` / `isBuiltin: Bool`

**初始種値**：
- PC（電子計算機）: 4 年
- サーバー：5 年
- ソフトウェア（自社利用）：5 年
- カメラ：5 年
- 事務机・椅子：8 年
- 自動車（営業用以外）：6 年
- その他工具器具備品：5 年

### 3.6 列挙

```swift
enum TaxCategory: String   { case standard10, reduced8, nonTaxable, outOfScope }
enum PriceEntryMode: String { case taxIncluded, taxExcluded }
enum PaymentMethod: String { case cash, creditCard, bankTransfer, ownerLoan, ownerWithdraw, accountsPayable, other }
enum RecordSource: String  { case aiParsed, electronicTransaction, manual, imported, depreciation }
enum AssetTreatment: String { case normalDepreciation, lumpSumDepreciation, smallAmountFullExpense }
enum AccountType: String   { case asset, liability, equity, revenue, expense }
enum DepreciationMethod: String { case straightLine, decliningBalance }
enum AIChannel: String     { case directApiKey, builtInProxy }
enum APIFormat: String     { case openAI, anthropic }
```

### 3.7 設計原則

- 金額は全て `Int`（円整数、Decimal/Double 不使用）
- `entryNumber` は fiscalYear 単位で max+1 を末尾追加、削除は `isVoided=true`（中抜なし）
- 編集・取消は `JournalEntry` を直接更新し、変更前の状態を `SystemActivityLog.beforeSnapshot` に整 JSON スナップショットで保存（per-field diff より単純、法定要件「訂正前の内容」を満たす）
- `Account` master table 構造で「自定义科目」を将来 UI で開放（MVP は隠す）
- 全 @Model に `syncId: UUID` を予約

---

## 4. 法定合規層

### 4.1 `ComplianceService`

```swift
enum ComplianceService {
    static func daysUntilScanDeadline(receiptDate: Date, today: Date) -> Int
    static func isLateEntry(transactionDate: Date, inputDate: Date) -> Bool
    static func validateImageResolution(_ image: UIImage) -> Bool
    static func transitionalRate(qualified: Bool, transactionDate: Date) -> Double
    static func suggestAssetTreatment(amount: Int, acquisitionDate: Date) -> AssetTreatment?
}
```

### 4.2 `ComplianceConstants`

```swift
enum ComplianceConstants {
    static let smallDepreciableAssetThreshold = 400_000  // 2026.4 以降 40 万円
    static let smallDepreciableAnnualCap     = 3_000_000
    static let smallDepreciableExpiry        = "2029-03-31"
    static let lumpSumDepreciationThreshold  = 200_000   // 一括償却資産 20 万円未満

    static let scanDeadlineMonths            = 2
    static let scanDeadlineExtraBusinessDays = 7
    static let defaultLateEntryThresholdDays = 14         // AppSettings.lateEntryThresholdDays の初期値、Settings で上書き可

    // インボイス制度 経過措置（令和8年度改正後、5 段階）
    static let transitionalRateSchedule: [(until: String, rate: Double)] = [
        ("2026-09-30", 0.80),
        ("2028-09-30", 0.70),
        ("2030-09-30", 0.50),
        ("2031-09-30", 0.30),
        // それ以降 0.00
    ]
}
```

### 4.3 優良電子帳簿 4 要件 対応表（国税庁公式定義）

| 法定要件 | 設計承載 |
|---|---|
| ① 訂正・削除履歴の確保（**通常の業務処理期間（約 2 ヶ月）経過後の入力履歴を含む**） | `SystemActivityLog.beforeSnapshot`（整 JSON）+ `JournalEntry.isLateEntry` |
| ② 帳簿間相互関連性 | `entryNumber` + `receiptImagePath` + `receiptImageHash` + `relatedFixedAssetId` |
| ③ 検索機能（取引年月日 / 取引金額 / 取引先 + 日付/金額の範囲 + 2 項目以上の組合せ） | `ExpenseRepository.search(criteria:)` 3 条件 AND |
| ④ **届出書の事前提出**（「国税関係帳簿の電磁的記録等による保存等に係る65万円の青色申告特別控除・過少申告加算税の特例の適用を受ける旨の届出書」を税務署に提出） | **ユーザーが税務署に提出するアクション**。アプリは「届出書」生成機能（v2 候補）でサポートし、Home の控除路線ステータスで「届出書 提出済 ☐」を表示してチェックリスト化する |

### 4.4 スキャナ保存 / 電子取引データ 区分

- `RecordSource.aiParsed`：紙レシート拍照 → **スキャナ保存**ルート
- `RecordSource.electronicTransaction`：PDF / 邮件取入 → **電子取引データ保存**ルート（紙印刷保管禁止 2024.1 以降）

両者で適用法令が異なる為、`sourceType` で明確区分。

---

## 5. AI 層

### 5.1 `AIFormatStrategy`（協議）

```swift
protocol AIFormatStrategy: Sendable {
    func setAuthHeaders(on request: inout URLRequest, apiKey: String)
    func buildVisionRequestBody(
        imageBase64: String,
        mimeType: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int
    ) throws -> Data
    func parseTextContent(from data: Data) throws -> String
    func parseError(data: Data, statusCode: Int) -> AIServiceError
}
```

`AnthropicFormatStrategy` MVP 実装。`OpenAIFormatStrategy` は型定義 + プロトコル準拠のみで `buildVisionRequestBody` 等は `throw .invalidResponse` を返す stub。`AIRouter` には登録しない（将来 multi-format 対応時の拡張点として残す）。

### 5.2 双通道路由（`AIRouter`）

```swift
@MainActor
final class AIRouter: ReceiptParser {
    func parse(image: UIImage) async throws -> ReceiptDraft {
        switch settings.aiChannel {
        case .directApiKey:
            guard !settings.apiKey.isEmpty else { throw .apiKeyMissing }
            return try await directParser.parse(image: image)
        case .builtInProxy:
            return try await proxyParser.parse(image: image)
        }
    }
}
```

### 5.3 Sign in with Apple 流程

```
[Settings 切到 .builtInProxy 或 App 起動時 channel=proxy だが session 無効]
   ↓
NonceGenerator.makeNonce() → rawNonce
   ↓
SHA256(rawNonce) → hashedNonce → ASAuthorizationAppleIDRequest.nonce
   ↓
ASAuthorizationController.performRequests()
   ↓
[ユーザー認可]
   ↓
Credential: identityToken (JWT, 約 10 分有効) + user (stable ID)
   ↓
POST {proxyBaseURL}/v1/auth/exchange  { appleIdentityToken, nonce: rawNonce }
   ↓
Worker: JWKS 検証 + nonce 検証 → sessionToken + expiresAt
   ↓
AuthTokenStore.save(sessionToken, appleUserId, expiresAt) → Keychain
   ↓
以後 /v1/receipts/parse は Authorization: Bearer <sessionToken>
   ↓
401 session_expired 時 → 静默 SIWA re-auth → 再 exchange → 元 request 再試行
         （静默失敗のみログイン画面提示）
```

### 5.4 Worker 接口契約

```
POST {proxyBaseURL}/v1/auth/exchange
  Req:  { appleIdentityToken: string, nonce: string }
  Resp: { sessionToken: string, expiresAt: ISO8601, appleUserId: string }
  Err:  401 invalid_token / 400 bad_nonce

POST {proxyBaseURL}/v1/receipts/parse
  Headers: Authorization: Bearer <sessionToken>
  Req:  { imageBase64: string, mimeType: "image/jpeg"|"image/png"|"application/pdf", locale: "ja-JP" }
  Resp: { draft: ReceiptDraft, tokenUsage: { input: int, output: int }, modelUsed: string }
  Err:  401 session_expired / 429 rate_limited (Retry-After) / 503 upstream_overloaded
```

### 5.5 設定（`AISettings`）

```swift
struct AISettings {
    var aiChannel: AIChannel          // .directApiKey 默认
    var apiFormat: APIFormat          // .anthropic 默认
    var apiKey: String                // Keychain
    var endpointURL: String           // 默认 https://api.anthropic.com
    var modelName: String             // 默认 claude-haiku-4-5-20251001
    var proxyBaseURL: String          // xcconfig 默认 + Settings 可覆盖
    var maxImageBytes: Int            // 默认 5_000_000
}
```

API Key / Proxy Session Token / Apple User Identifier は KeychainService で異なる key で分離保存。

### 5.6 エラーモデル

```swift
enum AIServiceError: Error, LocalizedError {
    case networkUnreachable
    case apiKeyMissing, apiKeyInvalid
    case proxyAuthRequired, proxySessionExpired, proxyEndpointNotConfigured
    case rateLimited(retryAfter: Date?)
    case modelOverloaded
    case invalidResponse(String)
    case jsonExtractionFailed(rawText: String)
    case imageTooLarge(maxBytes: Int)
}
```

### 5.7 Vision Prompt

System Prompt（日本語ベース、Token 効率優先）：

```
あなたは日本の青色申告に対応する仕訳作成 AI です。
受け取った領収書・レシート画像から下記 JSON のみを返してください。
JSON 以外の説明文・コードフェンス・前置きは一切禁止です。
不明な値は null にしてください。推測は禁止です。

{
  "transactionDate": "YYYY-MM-DD",
  "amountIncludingTax": <整数、円>,
  "amountExcludingTax": <整数、円>,
  "consumptionTax": <整数、円>,
  "taxRate": 0.10 | 0.08 | 0.00,
  "taxCategory": "standard10" | "reduced8" | "nonTaxable" | "outOfScope",
  "priceEntryMode": "taxIncluded" | "taxExcluded",
  "counterpartyName": "店舗名・取引先名",
  "transactionDescription": "取引内容（例：『打合せ昼食』『SSL 証明書購入』）",
  "invoiceRegistrationNumber": "T で始まる 13 桁、なければ null",
  "invoiceQualified": <bool、T番号があれば true>,
  "paymentMethod": "cash"|"creditCard"|"bankTransfer"|"ownerLoan"|"other"|null,
  "suggestedDebitAccountCode":  "4 桁の勘定科目コード",
  "suggestedCreditAccountCode": "4 桁の勘定科目コード"
}

勘定科目マスタ（借方候補）：
  5100 旅費交通費  / 5110 通信費 / 5120 接待交際費 / 5130 会議費
  5140 消耗品費   / 5150 事務用品費 / 5160 新聞図書費 / 5170 水道光熱費
  5180 地代家賃   / 5190 外注工賃   / 5200 支払手数料 / 5210 修繕費
  5220 租税公課   / 5290 雑費

paymentMethod → 貸方科目の対応：
  cash         → 1110 現金
  creditCard   → 2210 未払金
  bankTransfer → 1210 普通預金
  ownerLoan    → 3210 事業主借
  other / null → 3210 事業主借（デフォルト）
```

User Prompt：画像 + `「この領収書を仕訳してください」`

### 5.8 JSON 抽出（`JSONExtractor`）

```swift
enum JSONExtractor {
    static func extract(from text: String) throws -> Data
    // 1) 最初の平衡 { ... } を抜き出し
    // 2) 失敗時 throw .jsonExtractionFailed(rawText: text)
    //    UI で raw を readonly debug として表示し、手動入力に fallback
}
```

---

## 6. キャプチャ → 仕訳保存 データフロー

```
[Tab2 進入]
   ↓
[ChannelGate]：settings.aiChannel チェック
   ├ .directApiKey で apiKey 空 → Settings へ
   └ .builtInProxy で session 無効 → 静默 SIWA トリガー
   ↓
[ImageSourceSheet]：📷 撮影 / 🖼 アルバム / 📄 PDF
   ↓
[ReceiptImageProcessor] or [ElectronicReceiptImporter]
   - EXIF 矫正 → 解像度チェック → metadata 除去 → JPEG 圧縮 → base64
   - PDF の場合：1 ページ目を画像化、原 PDF は Documents/receipts/electronic/{year}/ 保存
   ↓
[AIRouter.parse(image:)] → ReceiptDraft
   ├ jsonExtractionFailed → 手動モード、raw text を ConfirmationForm に表示
   └ rateLimited / overloaded → 指数バックオフ再試行ボタン
   ↓
[ConfirmationForm] — 全フィールド編集可
   - 必須校验：transactionDate / amount / debit / credit / counterparty / description
   - 自動再算：priceEntryMode 切替時 amountExcludingTax / consumptionTax
   - 適格 vendor フラグ赤緑 + transitionalMeasureRate 自動算
   - 借方科目「AI 推荐」ラベル + 切替可
   - businessAllocationRate スライダ + 按分後金額表示
   - treatment 提案 banner（金額が 10万 / 20万 / 40万 跨ぎ時）：
     「この取引は 28 万円。少額減価償却特例の対象です。固定資産台帳に登録しますか？」
     → はい → FixedAsset 同時生成、treatment = .smallAmountFullExpense
   - 入力期限警告：transactionDate − today > 1.5 ヶ月 = 黄色、> 2 ヶ月 = 赤
   ↓
[Save] - 原子事務
   1. ImageStorageService.persist(jpeg) → Documents/receipts/{fy}/{filename} + SHA256
   2. JournalEntry insert（entryNumber = max+1 within fiscalYear）
   3. FixedAsset insert（treatment 提案を承諾した場合）
   4. SystemActivityLog.append(.createEntry, after: snapshot)
      isLateEntry=true なら details に「通常業務以外」フラグ
   ↓
[Toast 保存完了] → Tab2 残留（次の領収書に） or Tab1 戻る
```

### 6.1 画像保存規則

```
Documents/receipts/{fiscalYear}/{YYYY-MM-DD}_{HHmmss}_{shortUUID}.{jpg|pdf}
```

`JournalEntry.receiptImagePath` には Documents 相対パス、`receiptImageHash` には SHA256 hex を保存。読出時に整合性検証可能。

### 6.2 オフライン挙動

- 离线时 AI 解析不可 → ConfirmationForm 直接打开（全て手動入力）
- ConfirmationForm 保存 → 全本地 → 离线 OK
- Tab1 / Tab3 / Tab4 完全离线

---

## 7. UI

### 7.1 Tab1 `HomeView`
- 本月概要カード（件数 / 税込合計 / 消費税合計）
- 控除路線ステータスバー（4 チェックポイント、ユーザーが現在どの路線にいるか判定）：
  - 複式簿記での記帳 ✓ / ✗
  - 訂正・削除履歴の確保（優良要件①）✓ / ✗
  - 帳簿間相互関連性 + 検索機能（優良要件②③）✓ / ✗
  - **届出書 提出済**（優良要件④、ユーザー手入力）☐ / ✓
  - e-Tax 提出（**MVP では外部ソフト経由**、ユーザー手入力）☐ / ✓
  - 上記の組合せで「現在の見込控除額：10万 / 65万 / 75万」を表示
- 入力期限警告 Section（1 ヶ月以上未入力の取引）
- 科目別円グラフ（Swift Charts SectorMark、本月借方科目集計）
- 固定資産・減価償却 概要（当年取得件数 / 累計償却 / 簿価合計 / 次年度予測）
- レポート Section：「損益計算書 PDF を生成」ボタン → 共有シート
- 直近 5 件 List

### 7.2 Tab2 `CaptureView`（§6 詳述）

ヘッダーに現在の AI channel 状態表示（「内置代理 / Anthropic 直連」+ 設定への shortcut）。

### 7.3 Tab3 `ExpenseListView`
- SearchBar：counterpartyName + transactionDescription
- 過濾シート：
  - 日付範囲（年 / 月クイック）
  - 金額範囲
  - 勘定科目（debit 複数選択）
  - 適格 / 不適格 only
  - 入力区分（通常 / late entry only）
  - 取消エントリ表示
- Section 分組（月別 デフォルト、科目別切替可）
- 各行：transactionDate / counterpartyName / amountIncludingTax / debit / 適格バッジ / late バッジ
- スワイプ：編集（→ SystemActivityLog .edit） / 取消（→ .void、物理削除なし）
- 底部ツールバー：期間合計 + **CSV 出力**ボタン

### 7.4 Tab4 `SettingsView`

**事業者情報**
- 屋号 / 氏名 / 適格番号（T+13桁、自分の）/ 事業年度開始月

**AI 設定**
- Channel：自带 Key / 内置代理
- 自带 Key 時：API Format / API Key（Keychain、masked）/ Endpoint URL / モデル選択（haiku 4.5 / sonnet 4.6 / カスタム）
- 内置代理 時：Apple アカウント表示 + ログアウト / Proxy URL / セッション状態
- 「AI 接続テスト」ボタン

**勘定科目マスタ**
- 標準科目一覧（読取専用）
- 「カスタム科目（近日対応）」灰色

**固定資産台帳**
- FixedAsset 一覧
- 「年末減価償却を実行」ボタン → DepreciationService → プレビュー → 確認後仕訳生成

**家事按分デフォルト**
- 科目別 `defaultBusinessAllocationRate` 編集（自宅事務所 / 通信費 等）

**コンプライアンス**
- 入力期限警告余裕日数（デフォルト 14 日）
- 期末ロック（fiscalYear 単位、解除時に SystemActivityLog 記録）
- 「電子帳簿等保存に関する届出書」生成（v2）

**データ**
- バックアップ（zip Documents + SwiftData store）→ 共有シート

**关于**
- 版本 / 法令リンク / 隠私ポリシー

---

## 8. レポート出力

### 8.1 `PDFReportService.renderProfitAndLoss(fiscalYear:)`
- PDFKit で A4 1 ページ表組
- 売上科目集計 → 経費科目集計 → 利益
- ファイル名：`損益計算書_{fiscalYear}.pdf`

### 8.2 CSV 出力
- ExpenseListView の現在過濾結果を CSV
- ヘッダー：**日付 / 借方科目名 / 貸方科目名** / 取引内容 / 取引先 / 税込 / 税抜 / 消費税 / 適格番号 / 備考
- **科目はコードではなく科目名（日本語）を出力**：SnapKei の独自 4 桁コードは弥生・freee と互換性がないため、相手ソフト側で科目名マッピングしてもらう前提
- UTF-8 BOM 付き（Excel 互換）、RFC 4180 quoting

---

## 9. テスト戦略

| 層 | テスト | ツール |
|---|---|---|
| `ComplianceService` | 経過措置率 5 段階切替、解像度算出、入力期限跨年/跨月 | XCTest |
| `JSONExtractor` | code fence / 前置文 / 半 JSON / 入子 / Unicode | XCTest |
| `AnthropicFormatStrategy` | request body shape / auth header / error 401/429/529 | XCTest |
| `KeychainService` | multi-key 隔離 | XCTest |
| `ExpenseRepository` | entryNumber 連番空洞なし、SystemActivityLog 書込 | XCTest + in-memory ModelContainer |
| `AIRouter` | mock ReceiptParser で channel 分発 + session 失効静默再試行 | XCTest |
| `AIProxyService` 静默 SIWA | URLProtocol mock Worker | XCTest |
| `DepreciationService` | straight-line / lump-sum / smallAmountFullExpense 各パターン | XCTest |
| Receipt parsing E2E | 真レシート fixture × 10 種類、真 API 提交 | XCTest（CI skip、ローカル run） |
| UI flow | Capture → Save golden path のみ | XCUITest |

**TDD 適用範囲**：ComplianceService / JSONExtractor / AnthropicFormatStrategy / ExpenseRepository / DepreciationService（純ロジック）。UI / SwiftUI View は強制せず。

**Build 検証ルール**（user memory `feedback_compile_before_complete` 準拠）：
- 各 Phase 交付前に `xcodebuild -scheme SnapKei build` 全パス
- `xcodebuild test` 全緑
- 警告 clean

---

## 10. 実装フェーズ

### Phase 0 — 脚手架
- `SnapKei.xcodeproj` 調整：iOS 18.5、SwiftUI、SwiftData、AuthenticationServices、PDFKit
- ディレクトリ骨格（Domain / Data / Presentation / App / Resources）
- String Catalog（zh / ja）
- `Secrets.xcconfig`（`PROXY_BASE_URL` 等）
- Unit test target

### Phase 1 — データモデル + 合規層
- `JournalEntry` / `SystemActivityLog` / `Account`（`defaultBusinessAllocationRate` 含む）/ `FixedAsset` / `AssetUsefulLife` + 全列挙
- `Account` master 33 科目、`AssetUsefulLife` master 7 種 種値スクリプト
- `ComplianceService` / `ComplianceConstants`
- `AppSettings`（屋号 / 適格番号 / 事業年度開始月 / lateEntryThresholdDays）
- `ExpenseRepository`（entryNumber 連番 + 検索 API）
- `DepreciationService`
- 全単元テスト

### Phase 2 — AI 層 BYOK 通道
- `AIFormatStrategy` + `AnthropicFormatStrategy`
- `AIRequestConfig` / `AISettings` / `KeychainService`
- `ClaudeVisionService`
- `ReceiptImageProcessor` / `JSONExtractor`
- 単元テスト + 真 API E2E

### Phase 3 — AI 層 Proxy 通道（クライアント側）
- `AppleSignInService`（含 nonce）/ `AuthTokenStore` / `NonceGenerator`
- `AIProxyService`（静默 re-SIWA）
- `AIRouter`
- Worker 接口契約 markdown（独立ドキュメント、まだデプロイなし）

### Phase 3.5 — Cloudflare Worker デプロイ
- `infra/worker/` TypeScript 子プロジェクト
- `/v1/auth/exchange`（JWKS 検証）+ `/v1/receipts/parse`（Anthropic 転送）
- D1（最小：device_id / apple_user_id テーブル） + R2 不要（画像保存しない、転送のみ）
- Wrangler 設定 + 用户の Cloudflare アカウントで本番デプロイ
- 客户端の `PROXY_BASE_URL` を本番に切替

### Phase 4 — UI Tab2 Capture
- `CaptureView` + `CaptureViewModel` + `ImageSourcePicker`
- `ConfirmationForm`（按分 slider + treatment banner + 入力期限警告）
- `ElectronicReceiptImporter`（PDF 単頁）

### Phase 5 — UI Tab1 / Tab3 / Tab4
- HomeView（月概要 / 控除路線 / レポート Section）
- ExpenseListView（全過濾 + CSV 出力）
- SettingsView（全 Section + 固定資産台帳 + 家事按分デフォルト）
- `PDFReportService.renderProfitAndLoss`

### Phase 6 — 本地化打磨 + 文書
- zh / ja String Catalog 完全
- README + 電帳法対応説明 + 不法責任声明
- App Store スクリーンショット / 紹介文

---

## 11. YAGNI（MVP 不含）

- 多设备 Sync（schema 予約のみ）
- カスタム勘定科目 UI（master はあるが Settings 編集なし）
- 多ページ PDF 処理（1 頁目のみ）
- 仕訳帳 PDF 出力（CSV 优先）
- B/S 貸借対照表 / 製造原価（P/L のみ）
- 売掛金 / 買掛金 / 棚卸資産（IT freelance 想定外）
- 自動車按分の自動計算（一律手動 rate）
- OpenAI Format（骨架のみ、routing 未接続）
- 「電子帳簿等保存に関する届出書」PDF 生成（v2 — **75万円控除に必須だがユーザーが税務署様式を手書きで提出する前提**）
- **e-Tax 連携 / XML 提出**（MVP は外部ソフト経由。これにより MVP の現実最大控除は 65 万円）
- iPad 専用 UI（iPhone 中心、iPad は scale でカバい）

## 11.1 法的前提・コード前提

- **個人事業主・従業員 400 人以下を前提**：少額減価償却特例の対象法人要件（令和8年度改正後 400 人以下）。法人や大規模事業者は対象外
- **令和9年分以降の紙申告 55 万円控除は廃止**：本アプリは e-Tax または優良電子帳簿路線を前提に設計
- **10 万円控除も「前々年収入 1000 万円超」だと使えなくなる**：その場合は青色申告 65 万 / 75 万 のいずれかが必須
- **SnapKei が振る 4 桁勘定科目コードは独自規格**：標準ではない。弥生 / freee からのインポート時は科目名でマッピング前提

---

## 12. オープン課題

| 項目 | 状況 |
|---|---|
| ファビコン / アプリアイコン | デザイン未着手 |
| App Store 紹介文 / プライバシーポリシー | Phase 6 で対応 |
| Cloudflare Worker の本番ドメイン名 | 用户の Cloudflare アカウント確認時に決定 |
| iCloud / Sign in with Apple 既存ユーザーのテストデバイス | 用户の手元 Apple ID で検証 |
| 仕訳帳 PDF（v2 候補） | フォーマット要件 = freee / 弥生 で再検討 |
| 多端末 Sync 設計 | conchtalk の `Sources/Data/Sync/` を参考、別 spec で別途設計 |

---

## 13. リスク

- **Anthropic Vision の OCR 精度**：日本語 + 手書き混在レシートの抽出失敗率。対策：失敗時の手動入力 fallback + raw text 表示
- **電帳法 / インボイス制度の改正頻度**：`ComplianceConstants` を一箇所に集中、改正対応の改修コストを最小化
- **Cloudflare Worker の運用コスト / 障害**：BYOK チャネルを常に維持し、Proxy 障害時の冗長化
- **App Store 審査**：金融 / 税務関連アプリの追加審査リスク。対策：「税務相談ではなく記録ツール」と明示

---

## 14. 参考資料

- [No.2070 青色申告制度｜国税庁](https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2070.htm)
- [65万円控除届出書｜国税庁](https://www.nta.go.jp/taxes/tetsuzuki/shinsei/annai/shinkoku/annai/09_2.htm)
- [令和8年度税制改正：青色申告特別控除 75万円](https://showzeirishi.com/special-blue)
- [インボイス制度 経過措置 2026 改正 5 段階](https://sogyotecho.jp/inputtaxcredit-extension/)
- [少額減価償却資産特例 2026 改正 40 万円](https://www.yayoi-kk.co.jp/shinkoku/aoiroshinkoku/oyakudachi/shogakugenkashokyakushisan/)
- [電子帳簿保存法 スキャナ保存 タイムスタンプ](https://www.optim.co.jp/denshichobo/blog/easy-to-understand-explanations/)
- [仕訳帳・総勘定元帳 必須記載事項](https://www.yayoi-kk.co.jp/shinkoku/aoiroshinkoku/oyakudachi/sokanjomotocho/)
- ConchTalk 参考実装：`/Users/lee/workspace/conchtalk/Sources/Data/Network/`（`APIFormatStrategy`, `AnthropicFormatStrategy`, `ProviderProfiles`, `AIProxyService`, `KeychainService`）
