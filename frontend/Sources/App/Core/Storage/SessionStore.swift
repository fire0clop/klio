import Foundation
import Security

@MainActor
final class SessionStore: ObservableObject {
    @Published var isLoggedIn = false
    @Published var onboardingComplete = false
    @Published var token: String = ""
    /// true пока идёт начальная инициализация (восстановление сессии + статус с сервера)
    @Published var isBootstrapping = false

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.environment["KLIO_DEMO"] == "1" {
            token = "demo"; isLoggedIn = true; onboardingComplete = true; isBootstrapping = false
            return
        }
        #endif
        if let saved = Keychain.read("access_token") {
            token = saved
            isLoggedIn = true
            // Быстрый старт из кеша, потом проверяем с сервера
            onboardingComplete = UserDefaults.standard.bool(forKey: "onboarding_complete")
            isBootstrapping = true
            Task {
                await fetchOnboardingStatus()
                isBootstrapping = false
            }
        }
        subscribeToTokenEvents()
    }

    func save(accessToken: String, refreshToken: String) {
        Keychain.save("access_token", value: accessToken)
        Keychain.save("refresh_token", value: refreshToken)
        token = accessToken
        isLoggedIn = true
    }

    /// Полный вход существующего пользователя: получаем статус онбординга ДО
    /// переключения isLoggedIn, чтобы не мелькал экран онбординга и сразу попасть на нужный экран.
    func logIn(accessToken: String, refreshToken: String) async {
        Keychain.save("access_token", value: accessToken)
        Keychain.save("refresh_token", value: refreshToken)
        token = accessToken
        if let profile: ProfileResponse = try? await APIClient.shared.request("profile", token: accessToken) {
            onboardingComplete = profile.onboardingCompleted
            UserDefaults.standard.set(profile.onboardingCompleted, forKey: "onboarding_complete")
        }
        isLoggedIn = true
    }

    func fetchOnboardingStatus() async {
        guard !token.isEmpty else { return }
        guard let profile: ProfileResponse = try? await APIClient.shared.request(
            "profile", token: token
        ) else { return }
        onboardingComplete = profile.onboardingCompleted
        UserDefaults.standard.set(profile.onboardingCompleted, forKey: "onboarding_complete")
    }

    func markOnboardingComplete() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
    }

    func logout() {
        Keychain.delete("access_token")
        Keychain.delete("refresh_token")
        token = ""
        isLoggedIn = false
        onboardingComplete = false
    }

    // MARK: - Token refresh handling

    private func subscribeToTokenEvents() {
        NotificationCenter.default.addObserver(
            forName: .didRefreshToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let newToken = notification.userInfo?["token"] as? String
            Task { @MainActor in
                if let newToken { self?.token = newToken }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .tokenExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.logout() }
        }
    }
}

// MARK: - Keychain

enum Keychain {
    static func save(_ key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
