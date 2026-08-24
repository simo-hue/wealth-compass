import XCTest
@testable import WealthCompassMobile

/// Catalog-level assertions that no view test would catch, because the defect is in the data rather
/// than the code path that reads it.
final class LocalizationTests: XCTestCase {

    /// The recurring-transaction toast, resolved the way `MacRootView` resolves it.
    private func toast(_ count: Int, _ language: String) -> String {
        AppLocalization.string(
            "\(count) due transactions were added to Cash Flow.", appLanguage: language
        )
    }

    /// Sanity: the catalog is reachable per-language at all. If this fails, every assertion below
    /// is meaningless because they would all be comparing English to English.
    func testCatalogResolvesPerLanguage() {
        let italian = AppLocalization.string("Net Worth", appLanguage: "it")
        XCTAssertEqual(italian, "Patrimonio Netto")
        XCTAssertNotEqual(
            italian, AppLocalization.string("Net Worth", appLanguage: "en"),
            "per-language lookup is not working; the plural tests below would be vacuous"
        )
    }

    /// `NET WORTH` in Spanish carried the Italian spelling (`PATRIMONIO NETTO`) while the
    /// title-case key was correct, so nothing flagged it. Both cases, both Spanishes.
    func testSpanishNetWorthIsNotTheItalianSpelling() {
        for language in ["es", "es-419"] {
            let upper = AppLocalization.string("NET WORTH", appLanguage: language)
            XCTAssertFalse(upper.contains("NETTO"), "\(language) uppercase is the Italian spelling: \(upper)")
        }
        XCTAssertEqual(AppLocalization.string("NET WORTH", appLanguage: "it"), "PATRIMONIO NETTO")
    }

    /// The compact range labels are durations. `M` was read as the *million* abbreviation and
    /// shipped as "3 milyon" / "6 milhões" / "12 miliónov".
    func testRangeLabelsAreDurationsNotMagnitudes() {
        let magnitudes = ["milyon", "milhõ", "milione", "milj", "miliónov", "mil ", "triệu", "εκ", "млн"]
        for key in ["3M", "6M", "12M"] {
            for language in ["tr", "pt-BR", "pt-PT", "fi", "sk", "cs", "el", "vi", "it", "es"] {
                let value = AppLocalization.string(String.LocalizationValue(key), appLanguage: language)
                for magnitude in magnitudes {
                    XCTAssertFalse(
                        value.lowercased().contains(magnitude),
                        "\(key) in \(language) reads as a magnitude, not a duration: \(value)"
                    )
                }
            }
        }
    }

    /// `NET` means net, never *network*. It shipped as RETE / СЕТЬ / 网络 / 網路.
    func testNetIsNotNetwork() {
        let networkWords = ["rete", "сеть", "网络", "網路", "réseau", "netzwerk", "mạng"]
        for language in ["it", "ru", "zh-Hans", "zh-Hant", "fr", "de", "vi"] {
            let value = AppLocalization.string("%@ NET", appLanguage: language)
            for word in networkWords {
                XCTAssertFalse(
                    value.lowercased().contains(word),
                    "%@ NET in \(language) reads as 'network': \(value)"
                )
            }
        }
    }

    // MARK: - Number and percent formatting

    /// Percentages follow the locale's own convention.
    ///
    /// Every site built these as `number.formatted(...) + "%"`, which renders `12,3%` in all 35
    /// languages. Turkish puts the sign first, French separates it with a narrow no-break space,
    /// and under RTL a hand-appended sign lands on the wrong side of the digits.
    func testPercentagesFollowTheLocaleConvention() {
        XCTAssertTrue(
            formattedPercent(12.3, locale: Locale(identifier: "tr_TR")).hasPrefix("%"),
            "Turkish writes the percent sign before the number: \(formattedPercent(12.3, locale: Locale(identifier: "tr_TR")))"
        )
        let french = formattedPercent(12.3, locale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(french.contains(","), "French uses a decimal comma: \(french)")
        XCTAssertNotEqual(
            french, "12,3%",
            "French separates the sign from the digits; a hand-appended % cannot"
        )
        XCTAssertEqual(formattedPercent(12.3, locale: Locale(identifier: "en_US")), "12.3%")
    }

    /// A non-finite share must not print as "nan%".
    func testNonFinitePercentIsAnEmDash() {
        XCTAssertEqual(formattedPercent(.nan, locale: Locale(identifier: "en_US")), "—")
        XCTAssertEqual(formattedPercent(.infinity, locale: Locale(identifier: "en_US")), "—")
    }

    // MARK: - Plural categories

    /// English has exactly two categories, and the singular must not read "1 due transactions".
    func testEnglishSingularAndPlural() {
        XCTAssertEqual(toast(1, "en"), "1 due transaction was added to Cash Flow.")
        XCTAssertEqual(toast(3, "en"), "3 due transactions were added to Cash Flow.")
    }

    /// Czech needs a third form at n = 2…4. A `count == 1` branch in Swift can only ever express
    /// the two categories English has, which is why this moved into the catalog.
    func testCzechUsesADistinctFormBetweenTwoAndFour() {
        XCTAssertTrue(toast(1, "cs").contains("byla přidána"), toast(1, "cs"))
        XCTAssertTrue(toast(3, "cs").contains("byly přidány"), toast(3, "cs"))
        XCTAssertTrue(toast(8, "cs").contains("bylo přidáno"), toast(8, "cs"))
        XCTAssertNotEqual(toast(3, "cs"), toast(8, "cs"), "n=3 and n=8 are different Czech categories")
    }

    /// Russian returns 21, 31, 101 to the *singular* category — the case a two-way split gets
    /// exactly backwards, since it would hand 21 the "many" genitive form.
    func testRussianTwentyOneTakesTheSingularForm() {
        XCTAssertTrue(toast(1, "ru").contains("добавлена"), toast(1, "ru"))
        XCTAssertTrue(toast(21, "ru").contains("добавлена"), toast(21, "ru"))
        XCTAssertTrue(toast(3, "ru").contains("добавлены"), toast(3, "ru"))
        XCTAssertTrue(toast(8, "ru").contains("добавлено"), toast(8, "ru"))
    }

    /// Arabic distinguishes six categories including a dual; one form cannot serve them.
    func testArabicDistinguishesSingularDualAndPlural() {
        let forms = [toast(1, "ar"), toast(2, "ar"), toast(3, "ar"), toast(11, "ar")]
        XCTAssertEqual(Set(forms).count, 4, "one/two/few/many must all differ: \(forms)")
    }

    /// Romanian requires the `de` linker from 20 upward.
    func testRomanianTakesTheLinkerAboveTwenty() {
        XCTAssertFalse(toast(3, "ro").contains(" de tranzac"), toast(3, "ro"))
        XCTAssertTrue(toast(25, "ro").contains(" de tranzac"), toast(25, "ro"))
    }

    /// Whatever the count or language, the number itself must appear — a category whose value
    /// dropped the specifier would silently print a sentence with no quantity in it.
    func testEveryCategoryStillPrintsTheCount() {
        for language in ["en", "cs", "sk", "ru", "uk", "pl", "hr", "ro", "it", "de", "ja"] {
            for count in [2, 3, 5, 11, 21, 101] {
                XCTAssertTrue(
                    toast(count, language).contains("\(count)"),
                    "\(language) n=\(count) lost the count: \(toast(count, language))"
                )
            }
        }
    }
}
