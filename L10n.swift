import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en

    static let defaultsKey = "appLanguage"
    static var verificationLanguage: AppLanguage?

    var bundleIdentifier: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        }
    }

    var localeIdentifier: String {
        bundleIdentifier ?? Locale.current.identifier
    }

    var menuTitle: String {
        L10n.tr("language.\(rawValue)")
    }

    static var current: AppLanguage {
        get {
            if let verificationLanguage { return verificationLanguage }
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let language = AppLanguage(rawValue: raw) else { return .system }
            return language
        }
        set {
            if verificationLanguage != nil {
                verificationLanguage = newValue
                return
            }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: L10n.languageDidChangeNotification, object: nil)
        }
    }
}

enum L10n {
    static let languageDidChangeNotification = Notification.Name("StarryNightLanguageDidChange")
    private static let supported = ["zh-Hans", "zh-Hant", "en"]

    static var resolvedLanguage: String {
        AppLanguage.current.bundleIdentifier
            ?? Bundle.preferredLocalizations(from: supported).first
            ?? "en"
    }

    private static var bundle: Bundle {
        let code = resolvedLanguage
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    static var locale: Locale {
        Locale(identifier: AppLanguage.current.localeIdentifier)
    }

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: args)
    }
}
