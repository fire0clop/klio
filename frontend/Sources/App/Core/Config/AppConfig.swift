import Foundation

/// Централизованные настройки приложения.
///
/// Внимание: для прод-релиза замени `apiBaseURL` на HTTPS-домен,
/// `googleClientID` и `googleReversedClientID` — на значения из Google Cloud
/// Console (OAuth 2.0 iOS Client). См. SOCIAL_AUTH_SETUP.md.
enum AppConfig {
    /// Базовый URL API. ВНИМАНИЕ: при сборке релиза заменить на HTTPS-prod.
    static let apiBaseURL = URL(string: "https://api.klio-diary.ru/api/v1")!

    // MARK: - Google OAuth

    /// Google iOS OAuth 2.0 Client ID.
    /// Формат: "1234567890-abcdefghijklmn.apps.googleusercontent.com".
    static let googleClientID = "451444746651-kvkiheuitpq599u21vdiac165uvo7qmh.apps.googleusercontent.com"

    /// Reverse-DNS форма clientID. Этот же scheme должен быть прописан в
    /// Info.plist → CFBundleURLTypes → CFBundleURLSchemes.
    /// Получается перестановкой: "com.googleusercontent.apps.1234567890-abcdefghijklmn"
    static let googleReversedClientID = "com.googleusercontent.apps.451444746651-kvkiheuitpq599u21vdiac165uvo7qmh"

    /// Полный redirect URI для OAuth-флоу.
    static var googleRedirectURI: String { "\(googleReversedClientID):/oauthredirect" }
}
