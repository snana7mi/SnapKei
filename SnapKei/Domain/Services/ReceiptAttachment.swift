import Foundation

/// 仕訳の証憑（レシート画像/PDF）の解決: 種別・ファイル URL・SHA-256 完全性。
/// 電帳法のスキャナ保存要件（真実性の確保）を画面に出すための単一定義。
/// ファイル IO + ハッシュ計算を伴うためバックグラウンドから呼べるよう nonisolated。
nonisolated public struct ReceiptAttachment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case image
        case pdf
    }

    public enum Integrity: Equatable, Sendable {
        case verified      // ハッシュ一致
        case tampered      // ハッシュ不一致（改ざんの可能性）
        case missingFile   // ファイルが存在しない
        case unverified    // 期待ハッシュなし（旧データ等）
    }

    public let kind: Kind
    public let url: URL
    public let integrity: Integrity

    public static func resolve(relativePath: String?, expectedHash: String?) -> ReceiptAttachment? {
        guard let relativePath, let url = ImageStorageService.absoluteURL(for: relativePath) else {
            return nil
        }
        let kind: Kind = url.pathExtension.lowercased() == "pdf" ? .pdf : .image

        let integrity: Integrity
        if !FileManager.default.fileExists(atPath: url.path) {
            integrity = .missingFile
        } else if let expectedHash {
            integrity = ImageStorageService.verifyIntegrity(at: relativePath, expectedHash: expectedHash)
                ? .verified
                : .tampered
        } else {
            integrity = .unverified
        }
        return ReceiptAttachment(kind: kind, url: url, integrity: integrity)
    }
}
