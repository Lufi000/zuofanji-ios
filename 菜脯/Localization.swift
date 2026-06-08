import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var promptLanguageName: String {
        switch self {
        case .chinese: "Simplified Chinese"
        case .english: "English"
        case .japanese: "Japanese"
        }
    }

    static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }

        let preferred = Locale.preferredLanguages.first ?? ""
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("en") { return .english }
        return .chinese
    }
}

enum AppLocalization {
    static var prefersChinese: Bool {
        AppLanguage.current == .chinese
    }

    static func text(_ key: String) -> String {
        guard let path = Bundle.main.path(
            forResource: AppLanguage.current.rawValue,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: AppLanguage.current.locale, arguments: arguments)
    }
}
