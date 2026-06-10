# SnapKei — 仕訳詳細 + 証憑ビューア 設計スペック

**Date:** 2026-06-11
**Status:** Approved

## 背景 / 目的

一覧の仕訳行はタップ不能（スワイプ取消のみ）で、保存済みレシート画像/PDF を見る手段が無い（電帳法のための保存が形骸化）。仕訳詳細画面を新設し、全項目の確認・証憑の閲覧（拡大）・SHA-256 完全性検証・理由付き取消を提供する。編集は次フィーチャー（訂正履歴の合規設計を伴うため分離）。

## ドメイン層（TDD 対象）

### `ReceiptAttachment`（新規, Domain/Services）

```swift
public struct ReceiptAttachment: Equatable {
    public enum Kind: Equatable { case image, pdf }
    public enum Integrity: Equatable {
        case verified      // ハッシュ一致
        case tampered      // ハッシュ不一致（改ざんの可能性）
        case missingFile   // ファイルが存在しない
        case unverified    // 期待ハッシュなし（旧データ等）
    }
    public let kind: Kind
    public let url: URL
    public let integrity: Integrity

    // relativePath nil → nil（証憑なし）。kind は拡張子（.pdf → pdf、他は image）。
    // url は ImageStorageService.absoluteURL。integrity は verifyIntegrity による。
    public static func resolve(relativePath: String?, expectedHash: String?) -> ReceiptAttachment?
}
```

## UI

### `EntryDetailView(entry:)`（Presentation/ExpenseList、sheet 表示）

セクション:
1. **取引**: 取引日 / 取引先 / 内容 / memo（あれば）
2. **仕訳**: #連番・年度 / 借方・貸方（コード+科目名、@Query accounts で解決）/ 税込・税抜・消費税（YenFormat）/ 税区分・入力方式・支払方法 / 家事按分（rate < 1 のとき割合と按分前金額）
3. **インボイス**: 適格番号 / 適格 badge / 経過措置率（非適格かつ < 1.0 のとき）
4. **証憑**: サムネイル（image は Image、pdf は PDFKit サムネイル or「PDF を表示」行）→ タップでフルスクリーンビューア（pinch zoom）。Integrity badge: `整合性OK`(green) / `改ざんの可能性`(red) / `ファイルなし`(orange) / `未検証`(secondary)。証憑なしの場合は「証憑なし（手動入力等）」表示。
5. **ステータス**: 記帳種別（AI解析/電子取引/手動入力/減価償却/取込）/ 入力日 / 遅延・取消 badge
6. **操作**: 「取消（理由を入力）」— alert + TextField、空理由は「ユーザー操作」にフォールバック。資産連動仕訳（relatedFixedAssetId != nil）は取消ボタン非表示+案内文。取消済は操作なし。

### ビューア

- 画像: ScrollView ベースの ZoomableImageViewer（pinch 1x–5x、ダブルタップでリセット）。fullScreenCover。
- PDF: PDFKit `PDFView`（UIViewRepresentable、autoScales）。

### 一覧接線

`ExpenseListView` の行を Button 化 → `sheet(item: $selectedEntry)` で EntryDetailView。スワイプ取消は現状維持。取消実行後は dismiss + onDismiss で `viewModel.refresh()`。

## テスト

`ReceiptAttachmentTests`（TDD）: nil path → nil / 拡張子 kind 判定 / verified / tampered / missingFile / unverified。一時ファイルは `ImageStorageService.persist` で作成し teardown で削除（ImageStorageServiceTests と同パターン）。View は build + smoke。

## Out of scope

仕訳編集（次フィーチャー）/ 証憑の差し替え・再撮影 / OCR 再解析 / 監査ログ閲覧 UI。
