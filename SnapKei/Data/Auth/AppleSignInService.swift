import AuthenticationServices
import Foundation
import UIKit

public struct AppleSignInResult: Sendable, Equatable {
    public let identityToken: String
    public let appleUserId: String

    public nonisolated init(identityToken: String, appleUserId: String) {
        self.identityToken = identityToken
        self.appleUserId = appleUserId
    }
}

public protocol AppleSignInAuthenticating: Sendable {
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult
}

@MainActor
public final class AppleSignInService: NSObject, AppleSignInAuthenticating {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var activeController: ASAuthorizationController?

    public func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        guard continuation == nil else { throw AIServiceError.proxyAuthRequired }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.activeController = controller
            controller.performRequests()
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            continuation?.resume(throwing: AIServiceError.proxyAuthRequired)
            continuation = nil
            return
        }
        continuation?.resume(returning: AppleSignInResult(identityToken: token, appleUserId: credential.user))
        continuation = nil
        activeController = nil
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        activeController = nil
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
