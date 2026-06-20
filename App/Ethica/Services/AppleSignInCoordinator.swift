//
//  AppleSignInCoordinator.swift
//  Ethica
//
//  Native Sign in with Apple via AuthenticationServices.
//

import AuthenticationServices
import CryptoKit
import UIKit

enum AppleSignInError: LocalizedError {
    case missingIdentityToken
    case presentationContextUnavailable

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple Sign In did not return an identity token."
        case .presentationContextUnavailable:
            return "Unable to present Apple Sign In. Please try again."
        }
    }
}

@MainActor
final class AppleSignInCoordinator: NSObject {
    static let shared = AppleSignInCoordinator()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private weak var presentationAnchor: ASPresentationAnchor?

    private override init() {
        super.init()
    }

    /// Presents the native Apple Sign In sheet and returns the authorization + raw nonce for Supabase.
    func signIn(presentationAnchor: ASPresentationAnchor?) async throws -> (authorization: ASAuthorization, rawNonce: String) {
        guard continuation == nil else {
            throw NSError(
                domain: "AuthError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Apple Sign In is already in progress."]
            )
        }

        let anchor = presentationAnchor ?? WebAuthSessionPresenter.shared.window
        guard let anchor else {
            throw AppleSignInError.presentationContextUnavailable
        }

        let rawNonce = Self.randomNonceString()
        let hashedNonce = Self.sha256(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.presentationAnchor = anchor

        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            self.continuation = continuation
            controller.performRequests()
        }

        self.presentationAnchor = nil
        return (authorization, rawNonce)
    }

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func finish(with result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.presentationAnchor = nil
        continuation.resume(with: result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(with: .success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(with: .failure(error))
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let presentationAnchor {
            return presentationAnchor
        }

        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        if let candidate = scenes
            .flatMap(\.windows)
            .first(where: { !$0.isHidden && $0.alpha > 0 }) {
            return candidate
        }

        return ASPresentationAnchor()
    }
}
