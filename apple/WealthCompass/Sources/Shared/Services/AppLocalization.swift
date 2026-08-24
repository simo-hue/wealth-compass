import Foundation
import SwiftUI

enum AppLocalization {
    static func effectiveLocale(appLanguage: String?) -> Locale {
        appLanguage.map { Locale(identifier: $0) } ?? .current
    }

    static func string(_ key: String.LocalizationValue, appLanguage: String?) -> String {
        String(
            localized: key,
            bundle: bundle(for: appLanguage),
            locale: effectiveLocale(appLanguage: appLanguage)
        )
    }

    /// The bundle whose table to read for `appLanguage`.
    ///
    /// `String(localized:bundle:locale:)` uses its `locale` argument for *formatting* — plural
    /// category selection, number and date shapes — but **not** to choose the localization table.
    /// That comes from the bundle's own preferred localizations. So passing `.main` with a locale
    /// returned the system language and silently ignored the in-app override: verified in the test
    /// host, where `String(localized: "Net Worth", bundle: .main, locale: it)` yields "Net Worth"
    /// while the `it.lproj` bundle yields "Patrimonio Netto".
    ///
    /// The effect was a half-switched UI. `Text(LocalizedStringKey)` picks up the override at once
    /// through `.environment(\.locale,)`, while every `localizedTitle(appLanguage:)` and
    /// `settings.localized(_:)` call — several hundred of them — kept rendering the old language
    /// until the process restarted and `AppleLanguages` took effect.
    ///
    /// Resolving `nil` to `.main` is deliberate: with no override the main bundle already follows
    /// the system, which is exactly what "follow the device" means.
    private static func bundle(for appLanguage: String?) -> Bundle {
        guard let appLanguage else { return .main }
        bundleCacheLock.lock()
        defer { bundleCacheLock.unlock() }
        if let cached = bundleCache[appLanguage] { return cached }
        let resolved = Bundle.main.path(forResource: appLanguage, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        bundleCache[appLanguage] = resolved
        return resolved
    }

    /// Loading a bundle hits the filesystem, and these helpers are called from view bodies, so the
    /// lookup is memoized. Language bundles cannot change for the life of the process.
    /// `NSLock` rather than `Mutex` because the deployment target is iOS 17.
    private nonisolated(unsafe) static var bundleCache: [String: Bundle] = [:]
    private static let bundleCacheLock = NSLock()

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
