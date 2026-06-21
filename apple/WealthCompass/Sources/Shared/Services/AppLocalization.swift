import Foundation
import SwiftUI

enum AppLocalization {
    static func effectiveLocale(appLanguage: String?) -> Locale {
        appLanguage.map { Locale(identifier: $0) } ?? .current
    }

    static func string(_ key: String.LocalizationValue, appLanguage: String?) -> String {
        String(localized: key, bundle: .main, locale: effectiveLocale(appLanguage: appLanguage))
    }

    static func applyLanguagePreference(_ appLanguage: String?) {
        if let appLanguage {
            UserDefaults.standard.set([appLanguage, "en"], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var appLanguage: String? {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

extension View {
    func appLanguage(_ language: String?) -> some View {
        environment(\.appLanguage, language)
            .environment(\.locale, AppLocalization.effectiveLocale(appLanguage: language))
    }
}
