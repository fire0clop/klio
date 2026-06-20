import AuthenticationServices
import Foundation
import UIKit

/// Координирует "Sign in with Apple" через `AuthenticationServices`.
///
/// Используется как одноразовая операция:
/// ```swift
/// let coord = AppleSignInCoordinator()
/// let result = try await coord.signIn()
/// ```
/// Координатор удерживает себя и `ASAuthorizationController` до завершения,
/// поскольку `controller.delegate` — weak.
@MainActor
final class AppleSignInCoordinator: NSObject {
    struct Result {
        let identityToken: String
        let email: String?
        let fullName: String?
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var controller: ASAuthorizationController?
    /// Strong self-reference, очищается после resume.
    private var strongSelf: AppleSignInCoordinator?

    func signIn() async throws -> Result {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.strongSelf = self

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(with result: Swift.Result<Result, Error>) {
        switch result {
        case .success(let r):  continuation?.resume(returning: r)
        case .failure(let e):  continuation?.resume(throwing: e)
        }
        continuation = nil
        controller = nil
        strongSelf = nil
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                finish(with: .failure(SocialAuthError.missingIdentityToken))
                return
            }

            var fullName: String? = nil
            if let comps = cred.fullName {
                let combined = [comps.givenName, comps.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !combined.isEmpty { fullName = combined }
            }

            finish(with: .success(Result(
                identityToken: token,
                email: cred.email,
                fullName: fullName
            )))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain,
               nsErr.code == ASAuthorizationError.canceled.rawValue {
                finish(with: .failure(SocialAuthError.userCancelled))
            } else {
                finish(with: .failure(error))
            }
        }
    }
}

// MARK: - Presentation anchor

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
