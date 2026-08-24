import XCTest
@testable import WealthCompassMobile

/// The tab bar is the one place in the app that resolves its own language instead of going through
/// `AppLocalization`, because the five labels are shortened per-language and live in a generated
/// table rather than the string catalog. That divergence is precisely why it drifted: `appLanguage`
/// is the in-app override and is `nil` for every user who has never opened the language picker, and
/// mapping that `nil` to `"en"` put five English labels underneath an otherwise fully translated UI.
final class TabBarLabelResolverTests: XCTestCase {

    /// An explicit in-app override wins regardless of what the device is set to.
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

    /// An unsupported language falls back to English — never to whichever column happens to sort
    /// first. `Bundle.preferredLocalizations` returns the first candidate when nothing matches, so
    /// without the `isRequested` guard a Swahili device would be handed Arabic labels.
    func testUnsupportedLanguageFallsBackToEnglishNotTheFirstColumn() {
        let title = TabBarLabelResolver.title(
            for: .dashboard, appLanguage: nil, preferredLanguages: ["sw-KE"]
        )
        XCTAssertEqual(title, "Dashboard")
        XCTAssertNotEqual(title, "لوحة", "must not fall through to the alphabetically-first column")
    }

    /// No lookup may reach the `tab.rawValue` last resort: every tab has a label in every language.
    func testEveryTabResolvesInEverySupportedLanguage() {
        for tab in TabBarLabelResolver.Tab.allCases {
            for language in ["ar", "de", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans"] {
                let title = TabBarLabelResolver.title(
                    for: tab, appLanguage: language, preferredLanguages: nil
                )
                XCTAssertFalse(title.isEmpty, "\(tab.rawValue) in \(language) resolved to empty")
                XCTAssertNotEqual(
                    title, tab.rawValue,
                    "\(tab.rawValue) in \(language) fell through to the raw case name"
                )
            }
        }
    }
}
