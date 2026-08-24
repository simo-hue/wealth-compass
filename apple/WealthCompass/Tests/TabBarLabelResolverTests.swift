import XCTest
@testable import WealthCompassMobile

/// The tab bar is the one place in the app that resolves its own language instead of going through
/// `AppLocalization`, because the five labels are shortened per-language and live in a generated
/// table rather than the string catalog. That divergence is precisely why it drifted: `appLanguage`
/// is the in-app override and is `nil` for every user who has never opened the language picker, and
/// mapping that `nil` to `"en"` put five English labels underneath an otherwise fully translated UI.
final class TabBarLabelResolverTests: XCTestCase {

    /// Every language the generated table carries a column for.
    private let supported = [
        "ar", "ca", "cs", "da", "de", "el", "en", "es", "es-419", "fi", "fr", "he", "hi", "hr",
        "hu", "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk",
        "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    /// An explicit in-app override wins regardless of what the device is set to. This path was not
    /// changed by the fix; it is here so a future refactor cannot quietly break the override.
    func testExplicitOverrideWinsOverDeviceLanguage() {
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .dashboard, appLanguage: "fr", preferredLanguages: ["en-US"]),
            "Tableau"
        )
    }

    /// The regression this file exists for: no override means "follow the device", not "English".
    func testNoOverrideFollowsTheDeviceLanguage() {
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .dashboard, appLanguage: nil, preferredLanguages: ["fr-FR"]),
            "Tableau",
            "a French device with no in-app override must not get the English label"
        )
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .settings, appLanguage: nil, preferredLanguages: ["de-DE"]),
            "Optionen"
        )
    }

    /// Region folds to the base language: the table has no `fr-CA` column and `fr` is the answer.
    func testRegionalVariantFoldsToItsBaseLanguage() {
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .dashboard, appLanguage: nil, preferredLanguages: ["fr-CA"]),
            "Tableau"
        )
    }

    /// Script is load-bearing where the table distinguishes it; folding Hant to Hans would be wrong.
    func testScriptVariantsStayDistinct() {
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .settings, appLanguage: nil, preferredLanguages: ["zh-Hant-TW"]),
            "設定"
        )
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .settings, appLanguage: nil, preferredLanguages: ["zh-Hans-CN"]),
            "设置"
        )
    }

    /// pt-BR and pt-PT carry genuinely different labels, so neither may absorb the other.
    func testPortugueseVariantsAreNotInterchangeable() {
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .settings, appLanguage: nil, preferredLanguages: ["pt-BR"]),
            "Ajustes"
        )
        XCTAssertEqual(
            TabBarLabelResolver.title(for: .settings, appLanguage: nil, preferredLanguages: ["pt-PT"]),
            "Definições"
        )
    }

    /// Languages whose correct fallback shares NO subtag with the language itself.
    ///
    /// This is the case an earlier version of the fix got wrong. It "validated" Apple's match by
    /// comparing primary subtags, so `yue` → `zh-Hant` and `nn`/`no` → `nb` were all rejected as
    /// bogus and fell back to English — reintroducing the original bug for Cantonese and Nynorsk
    /// users, both of which are shipping Apple system languages. Trust Apple's matcher.
    func testLanguagesWhoseFallbackSharesNoSubtagWithTheMatch() {
        let cases: [(String, TabBarLabelResolver.Tab, String)] = [
            ("yue-Hant-HK", .dashboard, "儀表板"),   // Cantonese (Traditional) -> zh-Hant
            ("yue-Hans-CN", .dashboard, "仪表板"),   // Cantonese (Simplified)  -> zh-Hans
            ("nn-NO", .dashboard, "Dashbord"),      // Nynorsk                 -> nb
            ("no-NO", .cashFlow, "Strøm"),          // Norwegian macrolanguage -> nb
        ]
        for (language, tab, expected) in cases {
            XCTAssertEqual(
                TabBarLabelResolver.title(for: tab, appLanguage: nil, preferredLanguages: [language]),
                expected,
                "\(language) must resolve through Apple's fallback, not to English"
            )
        }
    }

    /// A genuinely unsupported language falls back to English.
    ///
    /// Note this holds because `supportedLanguages` contains `"en"`: with English among the
    /// candidates, `Bundle.preferredLocalizations` returns `"en"` for an unmatched language rather
    /// than the first candidate. Verified against sw-KE, is-IS and af-ZA. No extra guard is needed,
    /// and adding one is what broke the Cantonese case above.
    func testUnsupportedLanguageFallsBackToEnglish() {
        for language in ["sw-KE", "is-IS", "af-ZA"] {
            XCTAssertEqual(
                TabBarLabelResolver.title(for: .dashboard, appLanguage: nil, preferredLanguages: [language]),
                "Dashboard",
                "\(language) is unsupported and must land on English"
            )
        }
    }

    /// The invariant that makes the two resolution paths one behaviour: for every language the
    /// table supports, resolving it from the device must produce exactly what naming it explicitly
    /// produces. This is what a coverage test is worth — comparing against `tab.rawValue` is not,
    /// because the raw values are lowercase (`"dashboard"`) while every label is capitalized, so a
    /// total collapse to English would still satisfy it.
    func testDeviceResolutionMatchesExplicitOverrideForEverySupportedLanguage() {
        for tab in TabBarLabelResolver.Tab.allCases {
            for language in supported {
                let viaOverride = TabBarLabelResolver.title(
                    for: tab, appLanguage: language, preferredLanguages: nil
                )
                let viaDevice = TabBarLabelResolver.title(
                    for: tab, appLanguage: nil, preferredLanguages: [language]
                )
                XCTAssertEqual(
                    viaDevice, viaOverride,
                    "\(tab.rawValue) in \(language): device resolution disagrees with the override"
                )
                XCTAssertFalse(viaOverride.isEmpty, "\(tab.rawValue) in \(language) resolved to empty")
            }
        }
    }
}
