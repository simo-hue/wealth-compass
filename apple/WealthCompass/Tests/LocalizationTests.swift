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

    /// The exported ledger's future-dated footnote, resolved the way `ReportDocumentBuilder`
    /// resolves it. The count goes *into* the lookup; substituting it afterwards leaves the plural
    /// category unchosen.
    private func futureNote(_ count: Int, _ language: String) -> String {
        AppLocalization.string(
            "\(count) future-dated entries are listed in grey. They are excluded from the balances and subtotals above, matching how the app itself reports current cash.",
            appLanguage: language
        )
    }

    /// One future-dated row is the common case — a single scheduled invoice — and it must not read
    /// "1 future-dated entries".
    func testFutureDatedNoteHasAnEnglishSingular() {
        XCTAssertTrue(futureNote(1, "en").hasPrefix("1 future-dated entry is listed in grey."),
                      futureNote(1, "en"))
        XCTAssertTrue(futureNote(4, "en").hasPrefix("4 future-dated entries are listed in grey."),
                      futureNote(4, "en"))
    }

    /// The eight languages with more than two categories must get more than two *wordings*. The
    /// counts are chosen per language to land in different CLDR buckets: Romanian only leaves `few`
    /// at 20, and Arabic's dual is n = 2 alone.
    ///
    /// The count is masked before comparing. Without a catalog entry the lookup returns the key
    /// with the specifier filled in, so every count already yields a different *string* while the
    /// sentence around it never changes — comparing raw strings would pass on no translation at all.
    func testFutureDatedNoteUsesTheLanguagesOwnPluralCategories() {
        let probes: [String: [Int]] = [
            "cs": [1, 3, 8], "sk": [1, 3, 8], "ru": [1, 3, 8], "uk": [1, 3, 8],
            "pl": [1, 3, 8], "hr": [1, 3, 8], "ro": [1, 3, 25], "ar": [1, 2, 3],
        ]
        for (language, counts) in probes.sorted(by: { $0.key < $1.key }) {
            let wordings = Set(counts.map {
                futureNote($0, language).replacingOccurrences(of: "\($0)", with: "#")
            })
            XCTAssertEqual(wordings.count, counts.count,
                           "\(language) uses one wording for n = \(counts): \(wordings)")
        }
    }

    /// Every locale must say something of its own, or the note ships in English inside an otherwise
    /// translated report.
    func testFutureDatedNoteIsTranslatedEverywhereTheToastIs() {
        for language in ["ar", "ca", "cs", "da", "de", "el", "es", "es-419", "fi", "fr", "he", "hi",
                         "hr", "hu", "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR",
                         "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans",
                         "zh-Hant"] {
            XCTAssertNotEqual(futureNote(3, language), futureNote(3, "en"),
                              "\(language) falls back to English")
        }
    }

    /// A category whose value dropped the specifier would print a sentence with no quantity in it.
    /// Arabic is excluded the same way it is from the toast's own check: its one/two forms name the
    /// quantity in words, which is what the language actually does.
    func testEveryFutureDatedCategoryStillPrintsTheCount() {
        for language in ["en", "cs", "sk", "ru", "uk", "pl", "hr", "ro", "it", "de", "ja"] {
            for count in [1, 2, 3, 5, 11, 21, 101] {
                XCTAssertTrue(
                    futureNote(count, language).contains("\(count)"),
                    "\(language) n=\(count) lost the count: \(futureNote(count, language))"
                )
            }
        }
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

    /// Every locale the catalog carries. Spelled out rather than derived, so a locale silently
    /// dropped from the catalog fails the assertions below instead of vanishing from them.
    private static let everyLanguage = [
        "ar", "ca", "cs", "da", "de", "el", "en", "es", "es-419", "fi", "fr", "he", "hi", "hr",
        "hu", "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk",
        "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    /// The lock-screen reminder has to name the product, not a translation of it.
    ///
    /// `Reminder` / `Open Wealth Compass Tracker to review.` is everything a locked device shows
    /// under Privacy Mode, so that one sentence is all the reader gets — and eight locales had
    /// translated the app's own name inside it: 财富指南针, 財富指南針, Zenginlik Pusulası, Kompas
    /// Kekayaan, kompas bohatstva, เข็มทิศความมั่งคั่ง, بوصلة الثروة, वेल्थ कंपास. A product name is not a
    /// noun phrase; the sentence was telling people to open something that is not on their home
    /// screen and cannot be searched for.
    ///
    /// Kept as its own test because the lock screen is the surface where the cost is highest, but it
    /// is no longer the only string covered — `testNoLocaleRenamesTheAppInTheCatalog` sweeps all 21.
    /// The carve-out that used to stand here, exempting the standalone `Wealth Compass Tracker` key
    /// as "the app's display name, which some locales deliberately localize", was wrong: see that
    /// test's doc comment.
    func testTheLockScreenReminderDoesNotTranslateTheProductName() {
        let english = AppLocalization.string("Open Wealth Compass Tracker to review.", appLanguage: "en")
        for language in Self.everyLanguage {
            let body = AppLocalization.string(
                "Open Wealth Compass Tracker to review.", appLanguage: language
            )
            XCTAssertTrue(
                body.contains("Wealth Compass Tracker"),
                "\(language) translates the product name in the lock-screen reminder: \(body)"
            )
            guard language != "en" else { continue }
            XCTAssertNotEqual(
                body, english,
                """
                \(language) resolves the lock-screen reminder to the English source, so the check \
                above passed on a string this reader will never understand.
                """
            )
        }
    }

    /// Fails if any locale renames the app, in any string whose English source names it.
    ///
    /// The rule the narrow lock-screen test above expressed for one sentence, applied to all 21 —
    /// because the same defect was in the other 20, and because the exemption written to justify
    /// stopping at one was false.
    ///
    /// That exemption said the standalone `Wealth Compass Tracker` key is the app's **display name**,
    /// which `ar`, `de`, `es`, `fr`, `it` and `zh-Hans` localize on purpose. The display name is
    /// `CFBundleDisplayName`, hardcoded at `Resources/iOS/Info.plist:7-8` and
    /// `project.pbxproj:973`/`:999`, and there is no `InfoPlist.xcstrings` in the build tree — so
    /// nothing in the catalog can reach it. That key is ordinary in-app UI text, drawn at
    /// `LockView.swift:33`, `MacPlatformServices.swift:97` and `MacRootView.swift:145`. In those six
    /// locales the unlock screen was therefore showing a translated name while the home-screen icon
    /// underneath it still said "Wealth Compass Tracker" — which is the exact confusion the
    /// lock-screen fix was about, on the screen the user reaches it from.
    ///
    /// A product name is not a noun phrase. Translating it tells the reader to open, unlock or trust
    /// something that is not on their home screen and cannot be searched for. This asks only that
    /// the name survives; everything around it must still be translated, which is what the second
    /// assertion is for.
    ///
    /// It reads the catalog rather than resolving through `AppLocalization`, so it covers keys with
    /// format specifiers and keys nothing references yet — three of the 21 are unreferenced, and a
    /// dead key is one somebody wires up later. `testTheAppNameSurvivesTheRuntimeLookup` is the
    /// other half: that the compiled `.lproj` actually hands back what the catalog holds.
    func testNoLocaleRenamesTheAppInTheCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Shared/Resources/Localizable.xcstrings")
        let parsed = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
        let strings = try XCTUnwrap((parsed as? [String: Any])?["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 500, "only \(strings.count) keys — the catalog has moved")

        let name = "Wealth Compass Tracker"
        var offenders: [String] = []
        var checked = 0
        var keysNamingTheApp = 0

        for (key, entry) in strings.sorted(by: { $0.key < $1.key }) where key.contains(name) {
            keysNamingTheApp += 1
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, localization) in localizations.sorted(by: { $0.key < $1.key })
            where language != "en" {
                guard let unit = (localization as? [String: Any])?["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                checked += 1
                guard !value.contains(name) else { continue }
                offenders.append("  \(language) — \(key)\n      \(value)")
            }
        }

        XCTAssertGreaterThanOrEqual(
            keysNamingTheApp, 21,
            "\(keysNamingTheApp) key(s) name the app; the sweep is no longer reading the catalog"
        )
        XCTAssertGreaterThan(checked, 300, "only \(checked) translation(s) read across those keys")
        XCTAssertEqual(
            offenders, [],
            """
            \(offenders.count) translation(s) rename the app. A product name is not a noun phrase — \
            these tell the reader to open, unlock or trust something that is not on their home \
            screen, whose icon says "\(name)" in every locale because `CFBundleDisplayName` is \
            hardcoded:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The runtime half of the rule above: the compiled `.lproj` hands back the name the catalog
    /// holds.
    ///
    /// Only the standalone key can be checked this way — every other one carries `%@` specifiers
    /// whose arguments differ per call site — but it is the one that matters most, because it is
    /// what the unlock screen draws next to a home-screen icon that always says the same thing.
    /// Unlike the other translation tests here there is no "and differs from English" assertion, and
    /// there cannot be: for this key the correct value in all 34 languages *is* the English one.
    func testTheAppNameSurvivesTheRuntimeLookup() {
        for language in Self.everyLanguage {
            XCTAssertEqual(
                AppLocalization.string("Wealth Compass Tracker", appLanguage: language),
                "Wealth Compass Tracker",
                "\(language) draws a translated app name on the unlock screen and in the window title"
            )
        }
    }
}
