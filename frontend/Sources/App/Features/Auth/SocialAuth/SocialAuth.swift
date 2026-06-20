import Foundation

/// Унифицированные ошибки социальной авторизации.
enum SocialAuthError: LocalizedError {
    case userCancelled
    case missingIdentityToken
    case invalidURL
    case invalidCallback
    case couldNotStartSession
    case tokenExchangeFailed
    case providerError(String)
    case googleNotConfigured

    var errorDescription: String? {
        switch self {
        case .userCancelled:         return "Отменено"
        case .missingIdentityToken:  return "Не удалось получить токен"
        case .invalidURL:            return "Ошибка конфигурации"
        case .invalidCallback:       return "Некорректный ответ провайдера"
        case .couldNotStartSession:  return "Не удалось открыть окно входа"
        case .tokenExchangeFailed:   return "Не удалось завершить вход"
        case .providerError(let m):  return "Ошибка провайдера: \(m)"
        case .googleNotConfigured:   return "Google Sign-In не настроен"
        }
    }

    var isCancellation: Bool {
        if case .userCancelled = self { return true } else { return false }
    }
}

/// Высокоуровневые операции входа через Apple / Google.
/// Обе возвращают `TokenResponse` от нашего бэкенда и сохраняют его в `SessionStore`.
@MainActor
enum SocialAuth {
    static func signInWithApple(session: SessionStore) async throws {
        let coord = AppleSignInCoordinator()
        let result = try await coord.signIn()

        struct Body: Encodable {
            let identityToken: String
            let email: String?
            let name: String?
        }
        let resp: TokenResponse = try await APIClient.shared.request(
            "auth/apple", method: "POST",
            body: Body(
                identityToken: result.identityToken,
                email: result.email,
                name: result.fullName
            )
        )
        session.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        await session.fetchOnboardingStatus()
    }

    static func signInWithGoogle(session: SessionStore) async throws {
        let coord = GoogleSignInCoordinator()
        let idToken = try await coord.signIn()

        struct Body: Encodable { let idToken: String }
        let resp: TokenResponse = try await APIClient.shared.request(
            "auth/google", method: "POST",
            body: Body(idToken: idToken)
        )
        session.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        await session.fetchOnboardingStatus()
    }
}
