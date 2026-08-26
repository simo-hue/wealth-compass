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
    /// format specifiers and keys nothing references yet — **four** of the 23 are unreferenced, and
    /// a dead key is one somebody wires up later. `testTheAppNameSurvivesTheRuntimeLookup` is the
    /// other half: that the compiled `.lproj` actually hands back what the catalog holds.
    ///
    /// Three things about the sweep were narrower than the sentence above, and each let a rename
    /// through:
    ///
    /// - **It gated on the literal `Wealth Compass Tracker`.** The product is spelled three ways in
    ///   this catalog — `Wealth Compass Tracker` (21 keys), `WealthCompass` (`Welcome to
    ///   WealthCompass`, drawn on the app's **first screen** at `OnboardingView.swift:97` and
    ///   `MacOnboardingView.swift:102`) and `Wealth Compass` (the report brand, drawn on every
    ///   exported PDF at `ReportDocumentBuilder.swift:326`, `:332` and `:1080`). Only the first was
    ///   swept, so `zh-Hans` was still greeting the user with `欢迎来到财富指南针` on the very first
    ///   screen — the same rendering this sweep had deleted eleven times elsewhere. It now matches
    ///   `Wealth\s*Compass(?:\s+Tracker)?` and requires **each rendering the English source uses** to
    ///   survive into the translation, so a rename is caught however the name is spelled.
    ///
    ///   That last clause used to end "and a locale cannot satisfy the rule by substituting the
    ///   longer name for the shorter one", which was backwards. The check was substring containment,
    ///   so it caught only the substitution that *removes* text: a key saying `Wealth Compass
    ///   Tracker` answered with `Wealth Compass` fails the containment, while a key saying `Wealth
    ///   Compass` answered with `Wealth Compass Tracker` **passed**, because the longer string
    ///   contains the shorter one.
    ///
    ///   How much that cost, exactly, because the honest answer is "nothing yet". Only a rendering
    ///   that some other rendering contains is substitutable at all, which is `Wealth Compass`
    ///   alone — `Wealth Compass Tracker` is the longest, and `WealthCompass` has no space, so
    ///   neither is a substring of anything. Of the 23 keys that name the app, **21 render `Wealth
    ///   Compass Tracker`, one renders `WealthCompass`, and exactly one renders `Wealth Compass`**:
    ///   the bare report-brand key. That one key is also one of the two
    ///   `testTheAppNameSurvivesTheRuntimeLookup` pins with equality rather than containment, so the
    ///   suite as a whole did catch it — measured, by substituting `Wealth Compass Tracker` into the
    ///   `de` body of `Wealth Compass`: the sweep below reports it, and so does that test.
    ///
    ///   The gap was therefore in this sweep, not in the suite, and it becomes live the moment
    ///   somebody adds a *sentence* key using the short brand — a new PDF footer, say — which the
    ///   runtime test cannot check, because keys carrying `%@` need per-call-site arguments. Both
    ///   directions are asked now: every rendering the key uses must survive, **and** the
    ///   translation may not introduce one the key does not use. Across the catalog's 556 bodies the
    ///   added question reports the same zero offenders as the old one, so it strengthens the rule
    ///   without moving today's verdict.
    /// - **It read `localization["stringUnit"]` only.** A key with a `variations` block keeps its
    ///   bodies one level further down, and there are two such keys here with 35 bodies each — 70
    ///   translations the sweep could not see, where a renamed plural form would have been
    ///   invisible. Both shapes are read now.
    /// - **A key with no localizations passed by having nothing to check.** `Wealth Compass` was
    ///   literally `{}`, which renders correctly — the fallback is the English source, and for a
    ///   product name the English source *is* the right answer in all 34 languages. What it was not
    ///   is *pinned*: an empty entry is an open invitation to a translation pass, and this sweep had
    ///   nothing to say about it. It carries all 34 locales now, and the assertion on `checked`
    ///   below is what stops that regressing to nothing.
    func testNoLocaleRenamesTheAppInTheCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Shared/Resources/Localizable.xcstrings")
        let parsed = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
        let strings = try XCTUnwrap((parsed as? [String: Any])?["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 500, "only \(strings.count) keys — the catalog has moved")

        /// Every spelling of the product name in one string, longest match first so
        /// `Wealth Compass Tracker` is never read as `Wealth Compass` followed by a stray word.
        let name = try NSRegularExpression(pattern: #"Wealth\s*Compass(?:\s+Tracker)?"#)
        func renderings(in text: String) -> [String] {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            var found: [String] = []
            for match in name.matches(in: text, range: range) {
                guard let matched = Range(match.range, in: text) else { continue }
                let rendering = String(text[matched])
                if !found.contains(rendering) { found.append(rendering) }
            }
            return found
        }

        /// Every translated body under one locale: the plain one, and each `variations` leaf.
        func bodies(of localization: Any?) -> [(where: String, value: String)] {
            guard let localization = localization as? [String: Any] else { return [] }
            var found: [(where: String, value: String)] = []
            if let unit = localization["stringUnit"] as? [String: Any],
               let value = unit["value"] as? String {
                found.append((where: "", value: value))
            }
            let variations = localization["variations"] as? [String: Any] ?? [:]
            for (kind, cases) in variations.sorted(by: { $0.key < $1.key }) {
                for (category, body) in (cases as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    guard let unit = (body as? [String: Any])?["stringUnit"] as? [String: Any],
                          let value = unit["value"] as? String else { continue }
                    found.append((where: " [\(kind).\(category)]", value: value))
                }
            }
            return found
        }

        var offenders: [String] = []
        var checked = 0
        var keysNamingTheApp = 0

        for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
            let expected = renderings(in: key)
            guard !expected.isEmpty else { continue }
            keysNamingTheApp += 1
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, localization) in localizations.sorted(by: { $0.key < $1.key })
            where language != "en" {
                for body in bodies(of: localization) {
                    checked += 1
                    // Two questions, because containment alone only answers one of them. `missing`
                    // catches a rendering the English source uses and the translation dropped;
                    // `substituted` catches a rendering the translation invented. Without the
                    // second, a body reading `Wealth Compass Tracker` where the key says
                    // `Wealth Compass` passes by containing it — the app renamed, undetected.
                    let missing = expected.filter { !body.value.contains($0) }
                    let substituted = renderings(in: body.value).filter { !expected.contains($0) }
                    guard !missing.isEmpty || !substituted.isEmpty else { continue }
                    var complaint: [String] = []
                    if !missing.isEmpty { complaint.append("dropped \(missing.joined(separator: ", "))") }
                    if !substituted.isEmpty {
                        complaint.append("substituted \(substituted.joined(separator: ", "))")
                    }
                    offenders.append(
                        "  \(language)\(body.where) — \(key)\n      \(body.value)\n      (\(complaint.joined(separator: "; ")))"
                    )
                }
            }
        }

        XCTAssertGreaterThanOrEqual(
            keysNamingTheApp, 23,
            "\(keysNamingTheApp) key(s) name the app; the sweep is no longer reading the catalog"
        )
        XCTAssertGreaterThanOrEqual(
            checked, 556,
            """
            Only \(checked) translation(s) read across those keys, against 556 in the catalog this \
            floor was written for. It is 34 above the count before `Wealth Compass` was filled in, \
            on purpose: an entry with no localizations passes every assertion above by having \
            nothing to check, so a floor is the only thing that notices one going empty again.
            """
        )
        XCTAssertEqual(
            offenders, [],
            """
            \(offenders.count) translation(s) rename the app. A product name is not a noun phrase — \
            these tell the reader to open, unlock or trust something that is not on their home \
            screen, whose icon says "Wealth Compass Tracker" in every locale because \
            `CFBundleDisplayName` is hardcoded:
            \(offenders.joined(separator: "\n"))
            """
        )

        // The `variations` reader is the part with nothing else holding it: the two keys that use
        // that shape today carry no product name, so the loop above would read zero of those bodies
        // and still pass if the reader were removed. This is what says it ran.
        var variationKeys = 0
        for entry in strings.values {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            if localizations.values.contains(where: { ($0 as? [String: Any])?["variations"] != nil }) {
                variationKeys += 1
            }
        }
        XCTAssertGreaterThanOrEqual(
            variationKeys, 2,
            """
            \(variationKeys) key(s) in the catalog use `variations`. The sweep reads that shape \
            because a renamed plural form is otherwise invisible to it; if the catalog no longer \
            has any, this floor is what will say so before the reader is quietly dropped.
            """
        )
    }

    /// The runtime half of the rule above: the compiled `.lproj` hands back the name the catalog
    /// holds.
    ///
    /// Only keys without `%@` specifiers can be checked this way — the rest need arguments that
    /// differ per call site — which happens to be all three spellings of the product name, and each
    /// of the three is drawn somewhere the reader has to recognise the app by name:
    ///
    /// - `Wealth Compass Tracker` — the unlock screen (`LockView.swift:33`) and the window title,
    ///   next to a home-screen icon that says the same thing in every locale.
    /// - `Wealth Compass` — the brand line, the footer and the appendix of every exported PDF
    ///   (`ReportDocumentBuilder.swift:326`, `:332`, `:1080`).
    /// - `Welcome to WealthCompass` — the first line of the first screen
    ///   (`OnboardingView.swift:97`, `MacOnboardingView.swift:102`).
    ///
    /// The first two assert equality: for a bare product name the correct value in all 34 languages
    /// *is* the English one, so unlike the other translation tests here there is no "and differs
    /// from English" clause and there cannot be. The third is a sentence, so it asserts only that
    /// the name survived inside it — which is the whole rule, and all the catalog sweep asks too.
    func testTheAppNameSurvivesTheRuntimeLookup() {
        for language in Self.everyLanguage {
            for name in ["Wealth Compass Tracker", "Wealth Compass"] {
                XCTAssertEqual(
                    AppLocalization.string(String.LocalizationValue(name), appLanguage: language),
                    name,
                    """
                    \(language) renames the app: "\(name)" resolves to \
                    "\(AppLocalization.string(String.LocalizationValue(name), appLanguage: language))". \
                    That is drawn on the unlock screen, in the window title, and on every page of \
                    every exported PDF, beside an icon that says "Wealth Compass Tracker".
                    """
                )
            }
            let welcome = AppLocalization.string("Welcome to WealthCompass", appLanguage: language)
            XCTAssertTrue(
                welcome.contains("WealthCompass"),
                """
                \(language) renames the app on the first line of the first screen: "\(welcome)". \
                Everything around the name should be translated; the name itself is what the reader \
                has to be able to recognise and search for.
                """
            )
        }
    }

    /// The other half of the rule above, which on its own only ever asked for *less*.
    ///
    /// `testTheAppNameSurvivesTheRuntimeLookup` asserts the product name survives into every
    /// translation of `Welcome to WealthCompass`. A body left as the untouched English source
    /// satisfies that perfectly — it contains the name — and 28 of the 34 locales did exactly that:
    /// `ca cs da el es-419 fi he hi hr hu id ja ko ms nb nl pl pt-BR pt-PT ro ru sk sv th tr uk vi
    /// zh-Hant` all greeted the reader in English on the first line of the first screen, with the
    /// suite at 315 / 0. Containment cannot notice that, and neither can the catalog sweep: an
    /// untranslated body is the one thing that passes a rename check by definition.
    ///
    /// So this asks the opposite question — that the sentence *around* the name moved. The two
    /// together bracket the rule: `WealthCompass` stays, everything else goes.
    ///
    /// Resolved through `AppLocalization.string`, the same path `OnboardingView.swift:97` and
    /// `MacOnboardingView.swift:102` reach under `.appLanguage`, so this is the compiled `.lproj`
    /// in the built product answering and not the catalog being re-read.
    ///
    /// **`es-419` is not covered by `es`.** `AppLocalization.bundle(for:)` resolves a language to
    /// `Bundle.main.path(forResource:ofType: "lproj")` and falls back to `.main` — the English base
    /// — so there is no parent-locale inheritance anywhere in this app. Latin American Spanish
    /// needs its own body and gets a different one (`Te damos la bienvenida a`) from the peninsular
    /// `Bienvenido a`; both are listed in `everyLanguage` and both are checked here.
    func testTheWelcomeScreenIsTranslatedInEveryLanguage() {
        let english = AppLocalization.string("Welcome to WealthCompass", appLanguage: "en")
        XCTAssertEqual(english, "Welcome to WealthCompass", "the English source has moved")

        var untranslated: [String] = []
        for language in Self.everyLanguage where language != "en" {
            let welcome = AppLocalization.string("Welcome to WealthCompass", appLanguage: language)
            if welcome == english { untranslated.append("\(language) — \"\(welcome)\"") }
        }
        XCTAssertEqual(
            untranslated, [],
            """
            \(untranslated.count) of \(Self.everyLanguage.count - 1) languages hold the English \
            source verbatim on the first line of the first screen. The product name is not \
            localised, but the greeting carrying it is:
            \(untranslated.map { "  " + $0 }.joined(separator: "\n"))
            """
        )
    }
}
