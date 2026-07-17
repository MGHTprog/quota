import Foundation

/// Concrete UI languages shipped with the app.
enum AppLanguage: String, CaseIterable, Equatable {
    case english = "en"
    case simplifiedChinese = "zh-hans"

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_CN")
        }
    }
}

/// User-facing language setting, including “follow system”.
enum AppLanguagePreference: String, CaseIterable, Equatable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-hans"

    var resolvedLanguage: AppLanguage {
        switch self {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            return Self.systemLanguage()
        }
    }

    private static func systemLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

/// Persists the user's language preference in `UserDefaults`.
final class LanguageSettingsStore {
    static let shared = LanguageSettingsStore()

    private let defaults: UserDefaults
    private let preferenceKey = "language.preference"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preference: AppLanguagePreference {
        get {
            let rawValue = defaults.string(forKey: preferenceKey) ?? ""
            if rawValue == "zh-Hans" {
                return .simplifiedChinese
            }
            return AppLanguagePreference(rawValue: rawValue) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: preferenceKey)
        }
    }
}
