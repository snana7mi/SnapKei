import CryptoKit
import Foundation

public struct NoncePair: Equatable, Sendable {
    public let raw: String
    public let hashedSHA256: String
}

public enum NonceGenerator {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    public static func makePair(length: Int = 32) -> NoncePair {
        var rng = SystemRandomNumberGenerator()
        let raw = String((0..<length).map { _ in charset.randomElement(using: &rng)! })
        return NoncePair(raw: raw, hashedSHA256: sha256(raw))
    }

    public static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
