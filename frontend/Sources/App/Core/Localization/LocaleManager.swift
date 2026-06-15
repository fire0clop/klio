import Foundation
import SwiftUI

/// Локализация строки-ключа из текущего (подменённого) бандла языка.
/// Для динамических/вычисляемых строк, где `Text("литерал")` не срабатывает.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

// Поддерживаемые языки приложения.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en, es
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        case .es: return "Español"
        }
    }
    var flag: String {
        switch self {
        case .ru: return "🇷🇺"
        case .en: return "🇬🇧"
        case .es: return "🇪🇸"
        }
    }
}

final class LocaleManager: ObservableObject {
    nonisolated(unsafe) static let shared = LocaleManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            Bundle.setLanguage(language.rawValue)
        }
    }

    private static let key = "app_language"

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        let system = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "ru"
        let initial = AppLanguage(rawValue: saved ?? "") ?? AppLanguage(rawValue: String(system)) ?? .ru
        language = initial
        Bundle.setLanguage(initial.rawValue)
    }

    var locale: Locale { Locale(identifier: language.rawValue) }
}

// MARK: - Runtime bundle language switch

nonisolated(unsafe) private var localeBundleKey: UInt8 = 0

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let path = objc_getAssociatedObject(self, &localeBundleKey) as? String,
              let bundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()

    static func setLanguage(_ language: String) {
        _ = swizzleOnce
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        objc_setAssociatedObject(Bundle.main, &localeBundleKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
