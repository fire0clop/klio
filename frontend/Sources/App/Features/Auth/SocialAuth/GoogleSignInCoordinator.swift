import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// "Sign in with Google" через `ASWebAuthenticationSession` + PKCE.
///
/// Не используем Google Sign-In SDK ради минимума зависимостей: открываем
/// Google OAuth-страницу, ловим redirect, обмениваем code на id_token.
///
/// Возвращает Google `id_token` (JWT) — его и отправляем на бэкенд.
@MainActor
final class GoogleSignInCoordinator: NSObject {
    private var session: ASWebAuthenticationSession?
    private var strongSelf: GoogleSignInCoordinator?

    func signIn() async throws -> String {
        guard !AppConfig.googleClientID.hasPrefix("REPLACE_ME") else {
            throw SocialAuthError.googleNotConfigured
        }

        // PKCE
        let verifier = Self.randomURLSafe(byteLength: 64)
        let challenge = Self.sha256URLBase64(verifier)
        let state = Self.randomURLSafe(byteLength: 32)
        let nonce = Self.randomURLSafe(byteLength: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        guard let authURL = components.url else { throw SocialAuthError.invalidURL }

        let callbackURL = try await startWebAuthSession(
            authURL: authURL,
            callbackScheme: AppConfig.googleReversedClientID
        )

        // Парсим redirect: проверяем state, получаем code.
        guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = callbackComps.queryItems
        else { throw SocialAuthError.invalidCallback }

        if let err = items.first(where: { $0.name == "error" })?.value {
            throw SocialAuthError.providerError(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw SocialAuthError.invalidCallback
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SocialAuthError.invalidCallback
        }

        // Обмен code → id_token (на Google token endpoint, без client_secret для PKCE-клиента)
        return try await exchangeCodeForIDToken(code: code, verifier: verifier)
    }

    // MARK: - Steps

    private func startWebAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.strongSelf = self
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] url, error in
                defer { self?.strongSelf = nil; self?.session = nil }
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: SocialAuthError.userCancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let url else { cont.resume(throwing: SocialAuthError.invalidCallback); return }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: SocialAuthError.couldNotStartSession)
            }
        }
    }

    private func exchangeCodeForIDToken(code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("client_id", AppConfig.googleClientID),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", AppConfig.googleRedirectURI),
        ]
        req.httpBody = params
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SocialAuthError.tokenExchangeFailed
        }

        struct TokenResp: Decodable { let id_token: String? }
        let parsed = try? JSONDecoder().decode(TokenResp.self, from: data)
        guard let idToken = parsed?.id_token else { throw SocialAuthError.missingIdentityToken }
        return idToken
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(byteLength: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteLength, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func sha256URLBase64(_ str: String) -> String {
        let digest = SHA256.hash(data: Data(str.utf8))
        return Data(digest).base64URLEncoded
    }
}

extension GoogleSignInCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    /// base64url без паддинга (RFC 7636 PKCE).
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
