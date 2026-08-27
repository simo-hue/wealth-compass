import CryptoKit
import SwiftUI
import UIKit
import UserNotifications
import XCTest
@testable import WealthCompassMobile

/// Privacy Mode has to redact percentages as well as amounts.
///
/// The leak is never in `AppSettings` — it is always at a call site. A row that masks its amount to
/// `••••` and then prints the live percentage beside it has handed the amount straight back: anyone
/// who knows one position's size can divide their way to the rest. The rule is applied at 14 call
/// sites at the time of writing, all of them `settings.privatePercent(…)`.
///
/// The three tests above `testWorkingTreeSourcesContainNoUnguardedPercentageRender` pin the helper
/// that rule goes through. They cannot pin the call sites: `ValueDelta`, the donut centres and the
/// Sankey detail row are SwiftUI `View` bodies, and this project has no view-introspection
/// dependency, so there is no supported way to read back the `Text` a body produced. Asserting on
/// `settings.privatePercent(…)` instead only restates the helper — which is what the first version
/// of this file did, and why restoring the leak at all six `ValueDelta` call sites left the suite
/// green. So the last test reads the view *sources* instead. Read its doc comment before trusting
/// it: it is a lint, and it makes a narrower promise than the other three.
@MainActor
final class PrivacyRedactionTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
    }

    // MARK: - The rule

    func testPrivatePercentRedactsWhilePrivacyModeIsOn() {
        let settings = makeSettings()
        settings.isPrivacyMode = true

        for value in [12.4, -3.75, 0, 1_000] {
            XCTAssertEqual(
                settings.privatePercent(value), settings.redactionToken,
                "\(value)% survived Privacy Mode"
            )
        }
    }

    /// The default has to stay one fraction digit. `DashboardView` and `MacDashboardView` each
    /// carried their own private `privatePercent` that took no `fractionDigits` at all; both were
    /// deleted in favour of this one on the strength of the defaults matching, so what was a
    /// detail is now a contract those two views' rendered output depends on.
    ///
    /// Stated as a relation between the helper's own outputs rather than against a literal, so it
    /// holds in whatever locale the test host runs under (`%12,4` in Turkish, `12,4 %` in French).
    func testPrivatePercentDefaultsToOneFractionDigit() {
        let settings = makeSettings()
        settings.isPrivacyMode = false

        XCTAssertEqual(settings.privatePercent(12.45), settings.privatePercent(12.45, fractionDigits: 1))
        XCTAssertNotEqual(settings.privatePercent(12.45), settings.privatePercent(12.45, fractionDigits: 2))
    }

    /// The leak was in the pair, not in either half alone: the surviving half reconstructs the one
    /// that went. Driven through a real `Investment` and a real `ValueDelta` so the two types the
    /// row feeds in — `Decimal` money and a `Double` percentage — have to keep type-checking, and
    /// so `ValueDelta`'s already-redacted-strings contract cannot quietly revert to taking numbers.
    func testValueDeltaRowRedactsBothHalves() {
        let settings = makeSettings()
        settings.isPrivacyMode = true

        let investment = Investment(
            type: .etf, symbol: "VWCE", name: "Vanguard FTSE All-World",
            quantity: 10, costBasis: 1_000, currentValue: 1_124.5, currentPrice: 112.45,
            currency: .eur, geography: "Global", sector: "Diversified", isin: "IE00BK5BQT80", fees: 0
        )

        let delta = ValueDelta(
            value: investment.gainLoss.doubleValue,
            formattedValue: settings.privateCurrency(investment.gainLoss, sourceCurrency: investment.currency),
            percentText: settings.privatePercent(investment.gainLossPercent)
        )

        XCTAssertEqual(delta.formattedValue, settings.redactionToken)
        XCTAssertEqual(delta.percentText, settings.redactionToken)
        XCTAssertNotEqual(investment.gainLossPercent, 0, "the fixture has to carry a percentage worth hiding")
    }

    /// Fails if an entity count is printed without being formatted for the reader's locale.
    ///
    /// This one is not a Privacy Mode bug at all — it fires with the cover **down**, for every
    /// user. Eight summary cards built their count as `"\(count)"`, which is `String(describing:)`
    /// and groups nothing, and then handed it to `MetricCard(value:)`. `MetricCard` renders
    /// `Text(value)`, and a `String` argument selects `Text`'s verbatim `StringProtocol` overload
    /// rather than the `LocalizedStringKey` one, so a portfolio of 1,234 positions read **1234** in
    /// every language the app ships.
    ///
    /// The property, not the exact strings: a grouping locale must not render 1234 ungrouped, and
    /// two locales that group differently must not agree. Asserting `"1.234"` for `de` would pin
    /// this test to one CLDR release; `fr` alone has moved between a space, a no-break space and a
    /// narrow no-break space.
    /// Pins `privateCount` itself. `testWorkingTreeRendersNoUnformattedEntityCount` below is what
    /// keeps the call sites reaching it — this test alone cannot, and did not.
    func testCountsAreFormattedForTheReadersLocale() {
        let settings = makeSettings()

        settings.appLanguage = "en"
        let english = settings.privateCount(1_234)
        settings.appLanguage = "de"
        let german = settings.privateCount(1_234)

        XCTAssertNotEqual(
            english, "1234",
            "an entity count is printed unformatted, so every reader sees 1234 rather than 1,234"
        )
        XCTAssertNotEqual(
            english, german,
            """
            `en` and `de` group thousands differently, and this count rendered the same in both —             so it is not being formatted for the reader at all.
            """
        )

        settings.appLanguage = nil
        settings.isPrivacyMode = true
        XCTAssertEqual(
            settings.privateCount(1_234), settings.redactionToken,
            "an entity count survived Privacy Mode"
        )
    }

    /// Fails if an entity count is rendered as a bare `String` instead of going through
    /// `privateCount`.
    ///
    /// The test above only exercises the helper, and that is not the same thing. Reverting
    /// `InvestmentsView.swift:107` to the spelling `7a92b06` replaced —
    /// `settings.isPrivacyMode ? settings.redactionToken : "\(finance.data.investments.count)"` —
    /// left the suite at 297 passed / 0 failed, so the eight call sites that commit fixed were
    /// pinned by nothing. A ninth, `MacCashFlowView.swift:262`, was missed outright and stayed in
    /// the old form with the suite green.
    ///
    /// A lint rather than a render, and the same shape as
    /// `testWorkingTreeRendersNoUnguardedLastUpdatedStamp`. The original reason was that five of
    /// the nine sites were `Sources/macOS`, which the `WealthCompassMobile` test host could not
    /// render. That reason expired when those files moved to `Sources/Desktop` and began compiling
    /// into this host so an iPad could run them — they are renderable here now. The lint stays
    /// because its actual value was never the platform argument: it reads the *working tree*, so it
    /// catches a tenth site the day someone writes it, which a render test only covers once
    /// somebody remembers to instantiate the new view.
    ///
    /// What it looks for is a count rendered where nothing will format it — a string literal whose
    /// whole content is one interpolated count, or a `String(…)` conversion of one. That is
    /// `String(describing:)` either way, it groups nothing, and it prints 1234 in every language
    /// with Privacy Mode **off**: a defect for every reader, not only the redacted ones.
    ///
    /// **The exemption is an overload test, not a prefix test — and there are six overloads, not
    /// one.** It first asked whether the text before the literal ended in `Text(`, which four
    /// spellings walked through (`Text("\(count)" + " items")`, `Text("\(count)" as String)`,
    /// `plainText(`, `bodyText(`). Narrowing that to "the entire argument of a call whose callee is
    /// exactly `Text`" fixed those and created the opposite defect: it reported five other correct
    /// spellings. Measured — `AppLocalization.string("\(1234) …")` renders `1,234` in `en` and
    /// `1.234` in `de`, while plain `String` interpolation renders `1234` — so
    /// `settings.localized("\(count)")`, `AppLocalization.string("\(count)", …)`,
    /// `String(localized: "\(count)")`, `let key: LocalizedStringKey = "\(count)"` and
    /// `"\(count)" as LocalizedStringKey` are all **correct** and were all being named a defect.
    /// That second idiom is the one this project documents at
    /// `ReportDocumentBuilder.swift:204-212`, and the exemption did not know it existed.
    ///
    /// What is asked now is whether the literal lands in a position whose parameter type is
    /// `LocalizedStringKey` or `String.LocalizationValue` — the two `ExpressibleByStringInterpolation`
    /// types that run an integer through the reader's locale — reached as a sole argument, a first
    /// argument, a `localized:` label, an annotation or an `as` cast, walked over the stripped
    /// `code` view in both directions and across line breaks. A callee that merely *takes* a
    /// `String` is not one of them, which is the case that matters most: `L("\(count)")` in
    /// `ReportDocumentBuilder` looks exactly like `localized("\(count)")` and formats nothing.
    ///
    /// The regex is wider in two places, both of which were holes rather than deliberate narrowness.
    /// The literal pattern used to require `count)` flush against the closing quote, so
    /// `Text("\(items.count) " as String)` — one trailing space — and
    /// `Text("\(items.count - 1)" as String)` — one operator — were exempt, and both are the same
    /// `as String` overload the case above pins as reportable. And `[Cc]ount` used to match anywhere
    /// inside the interpolation, so `"\(discount)"` and `"\(account)"` were reported; `count` now
    /// has to begin an identifier segment.
    ///
    /// Two shapes carry no literal at all and so were invisible to a check written against one:
    /// `String(items.count)` and `String(format: "%d", items.count)`. Both are matched now, and
    /// deliberately not by "any `String(` whose arguments mention a count" —
    /// `String(text.dropFirst(tag.count))` at `BrokerStatementImportService.swift:876` is a
    /// substring conversion, and reporting it would be the same mistake as reporting `"\(account)"`.
    ///
    /// Two holes stay open and are named in `unformattedCounts`' doc comment and in the probe list:
    /// a count bound to a variable first (`let n = items.count` … `"\(n)"`), which would take a type
    /// checker to follow, and a *sentence* containing a count (`"\(visible), +\(values.count - 6)
    /// more"`), which is out of scope on purpose — that one shipped unformatted in
    /// `MarketDataService` and is fixed where it is written, by
    /// `testAMarketRefreshSummaryGroupsItsOverflowCount`, rather than by widening this into every
    /// string mentioning a count. `Text(_:tableName:…)` would also be reported, since the literal is
    /// not the sole argument; nothing in this tree uses that overload.
    ///
    /// **This sweep alone reads the report-export files.** It used to skip them with the other four,
    /// and the exemption was borrowed rather than reasoned: `excludedFiles` exists because an export
    /// redacts nothing by design, so a redaction sweep would report the same live shares forever.
    /// That answers a privacy question. This one is not a privacy check — its own subject is a
    /// number that reads wrong "with Privacy Mode **off**, which is most readers", so the reason the
    /// other sweeps look away has never applied to it.
    ///
    /// What the borrowed exemption cost: **eight** counts printed unformatted
    /// (`ReportDocumentBuilder.swift:857`, `:950` and `:1070-1075` — the commit that introduced the
    /// exclusion said six and missed the first two), recorded in this comment for two commits and
    /// pinned by nothing. They are fixed now, routed through the builder's own `count(_:)`, and
    /// `ReportCountFormattingTests` renders them in `de_DE` and `fr_FR`. With them fixed the sweep
    /// reads all five export files and reports zero, so nothing is being exempted to keep it green.
    ///
    /// The other four sweeps keep the full `excludedFiles`, which is why this reads the directory
    /// itself rather than sharing their filter. `swept` is what says so: drop the export files back
    /// out and this test fails on the assertion below rather than quietly narrowing again.
    ///
    /// Two integers in those files are **not** offenders and this sweep is right not to report them.
    /// `ReportDocumentBuilder.swift:761` renders a calendar year with `String(year)`, which must not
    /// be grouped — `2.024` is not a year. `PDFReportRenderer.swift:343` interpolates page numbers
    /// into `Page %1$@ of %2$@`; page numbers are ungrouped by typographic convention. Neither
    /// mentions a `count`, so neither is matched, but the reason they are correct is not the reason
    /// they are unmatched, and a future reader should not have to rediscover that.
    func testWorkingTreeRendersNoUnformattedEntityCount() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        var offenders: [PercentRender] = []
        var swept: Set<String> = []

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()

            for file in swiftFiles {
                swept.insert("\(directory)/\(file)")
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                offenders += try Self.unformattedCounts(
                    in: Self.stripped(text), path: "Sources/\(directory)/\(file)"
                )
            }
        }

        // The sweep read the tree. The old floor here was on *matches* — "at least the five correct
        // `Text("\(count)")` spellings" — with no margin at all: converting one of those five to
        // `privateCount`, which is an improvement, would have failed this.
        XCTAssertGreaterThan(
            swept.count, 20,
            "only \(swept.count) Swift file(s) read — the sweep has lost the source tree"
        )
        // And it read the files the other four sweeps skip. Without this, re-adding the
        // `excludedFiles` filter above would take the export back out with the suite still green,
        // which is exactly how the eight counts survived two commits in the first place.
        let unswept = Self.excludedFiles.subtracting(swept).sorted()
        XCTAssertEqual(
            unswept, [],
            """
            \(unswept.count) report-export file(s) went unread. This sweep deliberately does not \
            take the redaction exemption — an ungrouped count is wrong for every reader, redacted \
            or not:
            \(unswept.map { "  Sources/" + $0 }.joined(separator: "\n"))
            """
        )
        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) entity count(s) render as a bare `String`, so every reader sees 1234 \
            rather than 1,234 or 1.234 — with Privacy Mode off, which is most readers. Route them \
            through `settings.privateCount(_:)`, or, under `Shared/Export`, the builder's own \
            `count(_:)` — a report is deliberately unredacted, so `privateCount` is the wrong \
            helper there and would mask a figure the export exists to print:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    /// Fails if the sweep above can be walked past by spelling the same defect differently.
    ///
    /// The sweep is a lint over the working tree, so nothing else can check it: there is no
    /// offending source in the tree for it to catch, which means a broken checker and a clean tree
    /// look identical. That is exactly how the prefix test survived — it passed at 302 / 0 while
    /// `Text("\(count)" + " items")` and `Text("\(count)" as String)` both printed an ungrouped
    /// count at a real render site, and while `plainText(`/`bodyText(` were silently exempt.
    ///
    /// So this hands the checker sources of its own and asserts the verdict on each. Every case is a
    /// spelling that actually compiles and actually renders.
    func testTheEntityCountExemptionIsAnOverloadTestNotAPrefixTest() throws {
        let cases: [(source: String, offends: Bool, why: String)] = [
            (
                #"Text("\(count)")"#, false,
                "the one correct spelling: `Text` takes the `LocalizedStringKey` overload, which formats"
            ),
            (
                "Text(\n    \"\\(count)\"\n)", false,
                "the same call wrapped across lines was reported as an offender by the prefix test"
            ),
            (
                #"Text("\(count)" + " items")"#, true,
                "`+` forces the `StringProtocol` overload, which formats nothing — and this was exempt"
            ),
            (
                #"Text("\(count)" as String)"#, true,
                "`as String` forces the same overload, at a real render site — and this was exempt"
            ),
            (
                #"Text("items " + "\(count)")"#, true,
                "the mirror image of the `+` case, which the prefix test happened to catch"
            ),
            (
                #"plainText("\(count)")"#, true,
                "`plainText(` ends in `Text(`, so the prefix test exempted it"
            ),
            (
                #"bodyText("\(count)")"#, true,
                "`bodyText(` ends in `Text(` too"
            ),
            (
                #"let label = "\(items.count)""#, true,
                "the original defect: a bare `String`, formatted for nobody"
            ),
            (
                #"Text(settings.privateCount(items.count))"#, false,
                "the other correct spelling — the count never becomes a literal at all"
            ),
            (
                #"// Text("\(count)") in a comment"#, false,
                "comments are blanked before the sweep looks; a note about a render is not a render"
            ),
            (
                #"someText("\(count)")"#, true,
                "any callee that is not exactly `Text`"
            ),

            // The other localising idiom. Measured: `AppLocalization.string("\(1234) …")` renders
            // `1,234` in `en` and `1.234` in `de`, while plain `String` interpolation renders `1234`
            // in both — so every spelling below is correct code that the checker was reporting.
            (
                #"settings.localized("\(count)")"#, false,
                "`localized(_ key: String.LocalizationValue)` formats the integer for the reader"
            ),
            (
                #"AppLocalization.string("\(count)", appLanguage: language)"#, false,
                "the same `String.LocalizationValue`, as the first of two arguments"
            ),
            (
                #"String(localized: "\(count)")"#, false,
                "the Foundation spelling of the same initialiser"
            ),
            (
                #"let key: LocalizedStringKey = "\(count)""#, false,
                "an explicit annotation reaches the localising initialiser as surely as `Text(` does"
            ),
            (
                #"Text("\(count)" as LocalizedStringKey)"#, false,
                "and so does an explicit cast — this forces the overload that formats, not the one that doesn't"
            ),
            (
                #"L("\(count)")"#, true,
                """
                `L(_ key: String)` takes a plain `String`, so the interpolation has already happened \
                by the time it is called and nothing is formatted — the one spelling that looks like \
                `localized(` and behaves like bare interpolation
                """
            ),
            (
                #"let label = "\(discount)""#, false,
                "`[Cc]ount` matched inside a word, so a discount was reported as an entity count"
            ),
            (
                #"let label = "\(account)""#, false,
                "the same, and neither is a count of anything"
            ),

            // Spellings the literal pattern used to be too tight to see. Each is the same render.
            (
                #"Text("\(items.count) " as String)"#, true,
                "one trailing space defeated a pattern that required `count)` flush against the quote"
            ),
            (
                #"Text("\(items.count - 1)" as String)"#, true,
                "and so did one arithmetic operator — the same `as String` overload case #4 pins"
            ),
            (
                #"let label = String(items.count)"#, true,
                "no literal at all, so a check written against literals could not see it"
            ),
            (
                #"let label = String(format: "%d", items.count)"#, true,
                "`%d` formats for nobody; `%@` with a formatted number would be the fix"
            ),
            // Five more spellings of the same two renders. None of them ships — they are here
            // because "no source spells it that way today" is what the previous two roundings of
            // this pattern were resting on, and both were wrong within a commit or two.
            (
                #"let label = String(format: "%i", items.count)"#, true,
                "`%i` is `%d` under another name; the alternation accepted `d` and `u` only"
            ),
            (
                #"let label = String(format: "%zd", items.count)"#, true,
                "`%zd` is what a `count` naturally reaches for, being word-sized"
            ),
            (
                #"let label = String(format: "%D", items.count)"#, true,
                "`%D` is the Foundation spelling of `%d`, and formats for nobody in the same way"
            ),
            (
                #"let label = String(describing: items.count)"#, true,
                "`String(describing:)` is the bare conversion with a label — 1234 in every language"
            ),
            (
                #"let label = String(items.count, radix: 10)"#, true,
                "the same conversion; the pattern wanted the count flush against the closing paren"
            ),
            (
                #"let separator = String(repeating: "·", count: 4)"#, false,
                "a repeat count is an argument label, not something drawn for a reader"
            ),
            (
                #"let text = String(describing: error)"#, false,
                """
                `describing:` widened the conversion pattern, so the one call site that uses it — \
                `MarketDataService.swift:880`, describing an error into a log line — has to stay \
                exempt. It is not a count and nothing draws it for a reader.
                """
            ),
            (
                #"return String(text.dropFirst(tag.count))"#, false,
                """
                a substring conversion that happens to mention a count — reporting it would be the \
                same class of mistake as reporting `"\\(account)"`, and it is real code in \
                `BrokerStatementImportService.swift:876`
                """
            ),
        ]

        for probe in cases {
            let found = try Self.unformattedCounts(in: Self.stripped(probe.source), path: "probe.swift")
            XCTAssertEqual(
                !found.isEmpty, probe.offends,
                """
                `\(probe.source)` was \(found.isEmpty ? "exempted" : "reported") and should have been \
                \(probe.offends ? "reported" : "exempted") — \(probe.why).
                """
            )
        }

        // Holes that are open, recorded here so closing one is a test change rather than a
        // discovery. Both are limits of matching text rather than types, and both are stated in
        // `unformattedCounts`' doc comment.
        let open: [(source: String, why: String)] = [
            (
                "let n = items.count\nlet label = \"\\(n)\"",
                """
                the count is bound to a variable first, so by the time the literal is written it is \
                an `Int` named anything at all. Following it takes a type checker, not a regex.
                """
            ),
            (
                #"let label = "\(visible), +\(values.count - 6) more""#,
                """
                a sentence that contains a count rather than a literal that is one. Out of scope on \
                purpose — widening into every string mentioning a count is how a lint starts \
                reporting correct code — and fixed where it is written instead, which is what \
                `testAMarketRefreshSummaryGroupsItsOverflowCount` does for the one site that had it.
                """
            ),
        ]
        for hole in open {
            let found = try Self.unformattedCounts(in: Self.stripped(hole.source), path: "probe.swift")
            XCTAssertTrue(
                found.isEmpty,
                """
                `\(hole.source)` is now reported. That is an improvement, not a failure — delete this \
                entry and move it to the list above. It was recorded as an open hole because \
                \(hole.why)
                """
            )
        }
    }

    /// Fails if the market-refresh summary prints its overflow count unformatted.
    ///
    /// `compactList` lists the first six symbols and then says "+N more". That `N` went straight
    /// through `String` interpolation, so a reader with a large portfolio saw `+1234 more` in every
    /// language — the same defect the nine view sites were fixed for, in a sentence the sweep above
    /// cannot see, because the literal is not *only* the count.
    ///
    /// Rendered rather than linted: `MarketPriceRefreshResult` is a value type with a plain
    /// initializer, so unlike the view call sites this one can simply be built and read back.
    func testAMarketRefreshSummaryGroupsItsOverflowCount() {
        var result = MarketPriceRefreshResult()
        result.updatedInvestments = 1
        result.skippedInvestments = (0..<1_240).map { "SYM\($0)" }

        let english = result.localizedMessage(appLanguage: "en")
        let german = result.localizedMessage(appLanguage: "de")

        XCTAssertFalse(
            english.contains("1234"),
            "the overflow count is printed unformatted: \(english)"
        )
        XCTAssertTrue(english.contains("1,234"), "English groups thousands with a comma: \(english)")
        XCTAssertTrue(german.contains("1.234"), "German groups thousands with a point: \(german)")
    }

    /// A reference to a count, spelled so that it is one.
    ///
    /// The old pattern was `[Cc]ount` anywhere inside the interpolation, which reports `"\(discount)"`
    /// and `"\(account)"` — correct code, named a verdict. What is asked now is that `count` begins
    /// an identifier segment: preceded by a non-identifier character (`items.count`, `(count`,
    /// start of line) or capitalised after a lowercase or a digit (`rowCount`, `importedRecordCount`).
    /// The trailing `(?!\s*:)` drops argument labels, so `String(repeating: "·", count: 4)` is a
    /// repeat count and not a render.
    private static let countReference =
        #"(?:(?<![A-Za-z0-9_])count|(?<=[a-z0-9])Count)(?![A-Za-z0-9_])(?!\s*:)"#

    /// Every entity count in one source that is rendered without being formatted for the reader.
    ///
    /// Two shapes, because the defect has two:
    ///
    /// - a string literal whose whole content is one interpolated count — `"\(items.count)"`,
    ///   `"\(items.count) "`, `"\(items.count - 1)"` — anywhere the compiler will not pick a
    ///   localising overload;
    /// - `String(items.count)` and `String(format: "%d", items.count)`, which carry no literal at
    ///   all and so were invisible to a check written against one.
    ///
    /// Both halves have now been rounded twice, each time for the same reason: the pattern spelled
    /// out the shapes that happened to exist rather than the shape of the defect. The conversion
    /// wanted the count flush against the closing paren, so `String(describing: items.count)` and
    /// `String(items.count, radix: 10)` walked through; the specifier was the alternation
    /// `%(?:l{0,2}d|u)`, so `%i`, `%zd` and `%D` walked through. None of the five ships — which is
    /// precisely the state the previous two roundings were in until somebody wrote one.
    ///
    /// Split out of the sweep so the checker can be handed sources of its own — see
    /// `testTheEntityCountExemptionIsAnOverloadTestNotAPrefixTest`, which is the only thing that can
    /// hold it, since a broken checker and a clean tree look identical from the sweep's side.
    ///
    /// **One hole is known and open.** A count assigned to a variable first —
    /// `let n = items.count` … `"\(n)"` — is invisible here, because by the time the literal is
    /// written the count is a plain `Int` named anything at all, and following that would take a
    /// type checker rather than a regex. Recorded in the probe list rather than left implied.
    /// A literal that is a *sentence* containing a count (`"\(visible), +\(values.count - 6) more"`)
    /// is out of scope on purpose and by a different argument: it is fixed where it is written, as
    /// `testAMarketRefreshSummaryGroupsItsOverflowCount` does, not by widening this into every
    /// string that mentions a count.
    private static func unformattedCounts(
        in source: StrippedSource, path: String
    ) throws -> [PercentRender] {
        // A string literal that is nothing but one interpolation, with any spacing around it. The
        // old pattern required the interpolation to end in `count)` flush against the closing quote,
        // so one trailing space or one arithmetic operator walked past it.
        let countLiteral = try NSRegularExpression(pattern: ##""\s*\\\(([^"\n]*)\)\s*""##)
        let counts = try NSRegularExpression(pattern: Self.countReference)
        // `String(<something ending in a count>)`, optionally with arithmetic. Deliberately not
        // "any `String(` whose arguments mention a count": `String(text.dropFirst(tag.count))` is a
        // substring conversion, and reporting it would be the same class of mistake as `"\(account)"`.
        // `describing:` is a conversion like the bare one, and a trailing `, radix: 10` is still a
        // conversion of the same count — the old pattern wanted the count flush against the closing
        // paren, so both walked past it.
        let countConversion = try NSRegularExpression(
            pattern: ##"\bString\(\s*(?:describing\s*:\s*)?(?:[A-Za-z_][A-Za-z0-9_.]*)?\##(Self.countReference)\s*(?:[-+*/]\s*\d+\s*)?(?:,[^)\n]*)?\)"##
        )
        // Every integer conversion specifier, not the three that were spelled out. `%i`, `%zd` and
        // `%D` format an integer for nobody exactly as `%d` does; the old alternation
        // `%(?:l{0,2}d|u)` accepted `%d`, `%ld`, `%lld` and `%u` and nothing else.
        let countFormat = try NSRegularExpression(
            pattern: ##"\bString\(\s*format\s*:[^)\n]*%[-+ #0]*\d*(?:h{1,2}|l{1,2}|z|t|j|q)?[diuDU][^)\n]*\##(Self.countReference)[^)\n]*\)"##
        )

        // `scan` and `code` are the same characters line for line — `stripped` writes one character
        // to each per character of input — so an offset found in one indexes the other.
        let scan = source.scan.map { String($0) }.joined(separator: "\n")
        let code = Array(source.code.map { String($0) }.joined(separator: "\n"))
        let lineOfOffset = { (offset: Int) -> Int in
            code[..<offset].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        }
        func matches(_ text: String) -> Bool {
            counts.numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) > 0
        }

        var offenders: [PercentRender] = []
        func report(at start: Int, pattern: String) {
            let line = lineOfOffset(start)
            offenders.append(PercentRender(
                file: path, line: line, pattern: pattern,
                source: String(source.scan[line - 1]).trimmingCharacters(in: .whitespaces)
            ))
        }

        let range = NSRange(scan.startIndex..<scan.endIndex, in: scan)
        for match in countLiteral.matches(in: scan, range: range) {
            guard let matched = Range(match.range, in: scan),
                  let interpolation = Range(match.range(at: 1), in: scan) else { continue }
            // One interpolation, not a sentence stitched out of several.
            let inner = String(scan[interpolation])
            guard !inner.contains("\\("), matches(inner) else { continue }
            let start = scan.distance(from: scan.startIndex, to: matched.lowerBound)
            let end = scan.distance(from: scan.startIndex, to: matched.upperBound)
            guard !isLocalizingPosition(from: start, to: end, in: code) else { continue }
            report(at: start, pattern: #""\(…count)""#)
        }
        // Read over `code`, where string bodies are blanked: `String(format:)`'s specifier lives in
        // a literal, so that one reads `scan`. Neither can be reached from inside a comment.
        let codeText = String(code)
        for (regex, source, pattern) in [
            (countConversion, codeText, "String(…count)"),
            (countFormat, scan, #"String(format: "%d", …count)"#),
        ] {
            for match in regex.matches(
                in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)
            ) {
                guard let matched = Range(match.range, in: source) else { continue }
                report(at: source.distance(from: source.startIndex, to: matched.lowerBound), pattern: pattern)
            }
        }
        return offenders.sorted { ($0.line, $0.pattern) < ($1.line, $1.pattern) }
    }

    /// Whether the literal spanning `start..<end` lands somewhere the compiler formats it.
    ///
    /// The exemption used to be "is this the entire argument of a call whose callee is exactly
    /// `Text`", which is one localising position out of six and reports the other five. Measured:
    /// `AppLocalization.string("\(1234) …")` renders `1,234` in `en` and `1.234` in `de`, while
    /// plain `String` interpolation renders `1234` in both — so `settings.localized("\(count)")` is
    /// **correctly** formatted and was being named a defect. That second idiom is the one this
    /// project documents at `ReportDocumentBuilder.swift:204-212`, and the exemption did not know it
    /// existed.
    ///
    /// What formats, and why: `Text` and `LocalizedStringKey` take a `LocalizedStringKey`;
    /// `AppLocalization.string`, `settings.localized(_:)` and `String(localized:)` take a
    /// `String.LocalizationValue`. Both are `ExpressibleByStringInterpolation` types whose
    /// interpolation runs the integer through the reader's locale. An explicit annotation or an `as`
    /// cast to either reaches the same initialiser.
    ///
    /// What does not, and why: anything that forces the `StringProtocol` overload — `+`,
    /// `as String`, a second unlabelled argument — and any callee that merely takes a `String`,
    /// which is the case that matters most here. `L("\(count)")` in `ReportDocumentBuilder` looks
    /// exactly like `localized("\(count)")` and formats nothing, because `L(_ key: String)` receives
    /// a `String` that has already been interpolated. Its own doc comment says so.
    private static func isLocalizingPosition(from start: Int, to end: Int, in code: [Character]) -> Bool {
        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        /// A dotted identifier read backwards from `index`, e.g. `AppLocalization.string`.
        func identifier(endingAt index: Int) -> String {
            guard index >= 0, index < code.count else { return "" }
            var first = index
            while first >= 0, isIdentifier(code[first]) || code[first] == "." { first -= 1 }
            guard first < index else { return "" }
            return String(code[(first + 1)...index])
        }
        func skippingWhitespace(from index: Int, by step: Int) -> Int {
            var index = index
            while index >= 0, index < code.count, code[index].isWhitespace { index += step }
            return index
        }

        // `"\(count)" as LocalizedStringKey`
        let cast = skippingWhitespace(from: end, by: 1)
        if cast + 2 <= code.count, cast >= 0, String(code[cast..<min(cast + 2, code.count)]) == "as",
           cast + 2 == code.count || !isIdentifier(code[cast + 2]) {
            var type = skippingWhitespace(from: cast + 2, by: 1)
            let first = type
            while type < code.count, isIdentifier(code[type]) || code[type] == "." { type += 1 }
            return Self.localizingTypes.contains(String(code[first..<type]))
        }

        let before = skippingWhitespace(from: start - 1, by: -1)
        guard before >= 0, before < code.count else { return false }

        // `let key: LocalizedStringKey = "\(count)"`
        if code[before] == "=", before == 0 || !"=!<>+-*/".contains(code[before - 1]) {
            let last = skippingWhitespace(from: before - 1, by: -1)
            let type = identifier(endingAt: last)
            guard Self.localizingTypes.contains(type) else { return false }
            let colon = skippingWhitespace(from: last - type.count, by: -1)
            return colon >= 0 && code[colon] == ":"
        }

        // `String(localized: "\(count)")`
        if code[before] == ":" {
            let label = identifier(endingAt: before - 1)
            guard label == "localized" else { return false }
            let open = skippingWhitespace(from: before - 1 - label.count, by: -1)
            guard open >= 0, code[open] == "(" else { return false }
            return identifier(endingAt: open - 1) == "String"
        }

        guard code[before] == "(" else { return false }
        let callee = identifier(endingAt: before - 1)
        let after = skippingWhitespace(from: end, by: 1)
        let soleArgument = after >= 0 && after < code.count && code[after] == ")"
        switch callee {
        case "Text", "LocalizedStringKey":
            return soleArgument
        case "AppLocalization.string":
            // The key is the first of two arguments here, so a `,` is the shape to expect.
            return after >= 0 && after < code.count && (code[after] == "," || code[after] == ")")
        default:
            // `settings.localized(_:)`, `self.localized(_:)`, a bare `localized(_:)`. Matched on the
            // last segment, so the receiver can be anything; `L(` and `plainText(` are not this.
            return soleArgument && (callee == "localized" || callee.hasSuffix(".localized"))
        }
    }

    /// The types whose string interpolation runs an integer through the reader's locale.
    private static let localizingTypes: Set<String> = [
        "LocalizedStringKey", "String.LocalizationValue", "LocalizationValue",
    ]

    func testPrivateDateRedactsWhilePrivacyModeIsOn() {
        let settings = makeSettings()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNotEqual(
            settings.privateDate(stamp), settings.redactionToken,
            "with Privacy Mode off the stamp has to render, or the redaction below proves nothing"
        )
        XCTAssertNotEqual(
            settings.privateDate(stamp, time: .shortened), settings.privateDate(stamp),
            "the `.shortened` time style is dropped, so the macOS rows lose their time of day"
        )

        settings.isPrivacyMode = true
        XCTAssertEqual(
            settings.privateDate(stamp), settings.redactionToken,
            "a `last updated` stamp survived Privacy Mode"
        )
        XCTAssertEqual(
            settings.privateDate(stamp, time: .shortened), settings.redactionToken,
            "a `last updated` stamp survived Privacy Mode with its time of day attached"
        )
    }

    /// Fails if a record's "last updated" stamp is rendered without going through `privateDate`.
    ///
    /// `52c062a` tokenised the Investments and Crypto **Status cards** because "a 'last updated'
    /// timestamp is itself data about the account". It left the per-row stamps beside every
    /// position and holding in the clear, printing the same class of fact at finer grain — the two
    /// macOS rows carry the time of day as well as the date — directly beside a figure already
    /// masked to `••••`.
    ///
    /// A lint rather than a render. Two of the four sites used to be unrenderable here — they were
    /// `Sources/macOS`, and the test bundle hosts `WealthCompassMobile` — but they now live in
    /// `Sources/Desktop` and compile into this host, because an iPad runs them. The lint is kept
    /// for the reason given on `testWorkingTreeSourcesContainNoUnformattedEntityCount`: it sweeps
    /// the working tree, so a fifth site is caught the day it appears. It is narrow on purpose: a *transaction's* date is shown in the clear all over the app by a separate ruling,
    /// so this asks only about `updatedAt`, the field the Status-card decision was about.
    func testWorkingTreeRendersNoUnguardedLastUpdatedStamp() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        var offenders: [PercentRender] = []
        var renders = 0

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .filter { !Self.excludedFiles.contains("\(directory)/\($0)") }
                .sorted()

            for file in swiftFiles {
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                let source = Self.stripped(text)
                for index in source.scan.indices {
                    let line = String(source.scan[index])
                    // A line that both reads `updatedAt` and renders it. The `let latestUpdate =
                    // …map(\.updatedAt).max()` gathering lines and the `item.updatedAt = Date()`
                    // writes match neither half.
                    guard line.contains("updatedAt"),
                          line.contains("Text(") || line.contains("localized(") else { continue }
                    renders += 1
                    guard !line.contains("privateDate") else { continue }
                    offenders.append(PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1, pattern: "updatedAt",
                        source: line.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        XCTAssertGreaterThanOrEqual(
            renders, 4,
            "found \(renders) rendered `updatedAt` stamp(s) — there are four, so the sweep has lost the source tree"
        )
        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) "last updated" stamp(s) render in the clear. A bystander reads off \
            when this account last refreshed a price — the fact `52c062a` tokenised one card away \
            from — beside amounts that are already `••••`. Route them through \
            `settings.privateDate(_:time:)`:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    // MARK: - The call sites

    /// Every directory under `Sources/` that holds Swift, so neither sweep can be dodged by
    /// putting the leak somewhere it does not look.
    ///
    /// `Shared/Stores` is in because a percentage built in an `AppSettings` extension renders on
    /// screen exactly like one built in a view. `Shared/Export` is in because it is not only the
    /// report renderer: `ExportOptionsView` is a user-facing SwiftUI sheet that *is* privacy-aware
    /// (`isPrivacyModeOn` at its `:14` and `:91`). `Shared/Models`, `Shared/Services` and
    /// `Shared/Persistence` spell no percentage and draw no chart today, and used to be left out
    /// for that reason — but "it has none right now" is not a boundary. A `View` with a
    /// `Chart`/`SectorMark` in `Shared/Services/AnalyticsEngine.swift`, rendered from the privacy
    /// branch, was invisible to both sweeps with the suite green; now it is not. `Shared/Resources`
    /// is the only directory left out, and it holds no Swift at all — the per-directory
    /// `XCTAssertFalse` below is what stops a real one from being quietly dropped from this list.
    private static let scannedDirectories = [
        "iOS", "macOS", "Desktop", "Shared/Platform",
        "Shared/UI", "Shared/Stores", "Shared/Export",
        "Shared/Models", "Shared/Services", "Shared/Persistence",
    ]

    /// The files that compose the exported report. A PDF or JSON export is an explicit act on the
    /// user's part and redacts nothing at all, deliberately — `ReportDocumentBuilder.swift:676` and
    /// `:679` print live shares next to live amounts, and nothing there is masked, so there is no
    /// masked amount for a percentage to give away. `ExportOptionsView.swift:91` shows a warning
    /// before the user commits. Scanning these files would report those two lines forever.
    ///
    /// Full paths under `Sources/`, not basenames. Every sweep matched on `lastPathComponent`, so
    /// any future file anywhere in the tree that happened to be called `ReportPaginator.swift` —
    /// or `PDFDrawingContext.swift`, a name a chart or a receipt could reasonably reuse — was
    /// silently exempt from all five sweeps, with nothing to say so.
    ///
    /// **Four sweeps, not five.** `testWorkingTreeRendersNoUnformattedEntityCount` opts out and
    /// reads these files: the exemption above is an argument about redaction, and an ungrouped
    /// count is wrong with Privacy Mode off. It borrowed this list once and eight unformatted
    /// counts shipped behind it. That test's doc comment carries the reasoning.
    private static let excludedFiles: Set<String> = [
        "Shared/Export/ReportDocumentBuilder.swift", "Shared/Export/ReportChartRenderer.swift",
        "Shared/Export/PDFReportRenderer.swift", "Shared/Export/ReportPaginator.swift",
        "Shared/Export/PDFDrawingContext.swift",
    ]

    /// Fails if any Swift under `Sources/` sits outside `scannedDirectories`.
    ///
    /// The per-directory `XCTAssertFalse(swiftFiles.isEmpty)` inside each sweep catches a *listed*
    /// directory that has gone away. It cannot catch the other direction, and neither can
    /// `filesRead > 20`: delete `"Shared/UI"` from the list and 39 files are still enumerated, both
    /// sweeps still pass, and the entire design system — every `AllocationChart` ring — has quietly
    /// stopped being read. Adding a directory is then a deliberate act with a failing test in front
    /// of it, which is the only reason the list can be trusted to mean "everywhere".
    func testEverySwiftSourceIsUnderAScannedDirectory() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let swiftFiles = try FileManager.default
            .subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(swiftFiles.count, 20, "only \(swiftFiles.count) Swift files under Sources/")

        let unscanned = swiftFiles
            .filter { path in !Self.scannedDirectories.contains { path.hasPrefix($0 + "/") } }
            .sorted()
        XCTAssertEqual(
            unscanned, [],
            """
            \(unscanned.count) Swift file(s) live where neither sweep looks. Add the directory to \
            `scannedDirectories`, or say in its doc comment why it is exempt:
            \(unscanned.map { "  Sources/" + $0 }.joined(separator: "\n"))
            """
        )

        // And the exemptions name real files. The list used to be matched on `lastPathComponent`,
        // which meant it could not be checked at all: every entry "existed" wherever a file of that
        // name turned up, and a moved or renamed report file would have quietly stopped being
        // exempt — or, worse, gone on exempting some unrelated future file with the same basename.
        let missing = Self.excludedFiles.filter { !swiftFiles.contains($0) }.sorted()
        XCTAssertEqual(
            missing, [],
            """
            \(missing.count) excluded path(s) do not exist under Sources/. They must be full paths \
            relative to Sources/, not basenames:
            \(missing.map { "  " + $0 }.joined(separator: "\n"))
            """
        )
        let unreachable = Self.excludedFiles
            .filter { path in !Self.scannedDirectories.contains { path.hasPrefix($0 + "/") } }
            .sorted()
        XCTAssertEqual(
            unreachable, [], "\(unreachable.count) excluded path(s) no sweep would have read anyway"
        )
    }

    private struct PercentRender: CustomStringConvertible {
        let file: String
        let line: Int
        let pattern: String
        let source: String
        var description: String { "\(file):\(line): \(source)   [\(pattern)]" }
    }

    /// Fails if any scanned source builds a percentage that Privacy Mode does not cover.
    ///
    /// **What it actually checks.** It greps the *working tree*, not the binary under test. It has
    /// no way to observe a rendered `Text`, so it reads the checked-out `.swift` files it finds
    /// relative to `#filePath` and reports any line that spells a percentage one of the three ways
    /// this codebase can (`percentagePatterns`) without a visible `isPrivacyMode` gate covering it.
    ///
    /// **Two consequences of that, which are easy to get wrong.**
    ///
    /// 1. A green run says the sources on disk are clean. It says nothing about the app that was
    ///    built. Build a bundle from a leaking tree, restore the sources, run
    ///    `test-without-building` against that same bundle, and this passes while the binary leaks.
    ///    Only a full `xcodebuild test` from the tree it just read means anything.
    /// 2. It is a lint, so indirection defeats it. A renamed wrapper around `formattedPercent`, a
    ///    computed property in a file outside `scannedDirectories`, a percentage assembled from
    ///    `NumberFormatter`, or any spelling not in `percentagePatterns` all pass unseen. It was
    ///    built to catch one regression — a call site quietly reverting to the raw formatter — and
    ///    that is the only thing it reliably catches.
    ///
    /// **The gate a render has to sit under** is one of the two idioms already in the codebase: go
    /// through `settings.privatePercent(…)`, in which case there is no pattern here to find, or sit
    /// under a visible `isPrivacyMode` gate — an inline
    /// `settings.isPrivacyMode ? settings.redactionToken : …`, or an enclosing
    /// `if !settings.isPrivacyMode { … }`. The gate has to cover *this* render's own expression or
    /// open the block it sits in; a sibling statement's privacy check no longer counts, because a
    /// live card dropped into a `LazyVGrid` beside a redacted one is precisely the bug. It also has
    /// to read the right way round: the render must land on the arm privacy does *not* take, so
    /// flipping either idiom's condition is reported rather than accepted.
    ///
    /// It cannot be defeated by reformatting: comments and string-literal bodies are blanked before
    /// any brace is counted, so Allman braces, a `{` in a comment and a `{` in a string all read
    /// correctly, and a `formattedPercent(` mentioned in a comment is not a render.
    func testWorkingTreeSourcesContainNoUnguardedPercentageRender() throws {
        let sources = URL(fileURLWithPath: #filePath)   // …/Tests/PrivacyRedactionTests.swift
            .deletingLastPathComponent()                // …/Tests
            .deletingLastPathComponent()                // …/WealthCompass
            .appendingPathComponent("Sources")

        var offenders: [PercentRender] = []
        var filesRead = 0
        var linesRead = 0

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .filter { !Self.excludedFiles.contains("\(directory)/\($0)") }
                .sorted()
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "read no Swift files under \(root.path) — the sweep is not seeing the source tree"
            )

            for file in swiftFiles {
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                let source = Self.stripped(text)
                filesRead += 1
                linesRead += source.scan.count

                for index in source.scan.indices {
                    guard let match = Self.percentageMatch(at: index, in: source) else { continue }
                    guard !Self.isStringHelper(at: index, in: source.code) else { continue }
                    guard !Self.isPrivacyGated(at: index, column: match.column, in: source.code) else { continue }
                    offenders.append(PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1, pattern: match.pattern,
                        source: String(source.scan[index]).trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        // Was the sweep alive? Deliberately *not* a floor on how many renders it found: routing
        // more sites through `privatePercent` makes the app strictly more private and must never
        // turn this red. Files and lines only shrink if the enumeration itself broke, and
        // `testPercentageSweepStillCatchesALeak` covers the case where the matching broke instead.
        XCTAssertGreaterThan(filesRead, 20, "only \(filesRead) Swift files enumerated — the sweep lost the source tree")
        XCTAssertGreaterThan(linesRead, 5_000, "only \(linesRead) lines read — the sweep lost the source tree")

        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) percentage(s) render live beside an amount Privacy Mode redacts. \
            Route each through `settings.privatePercent(…)`:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    /// The alarm that used to be a hardcoded floor on the number of renders found.
    ///
    /// A source sweep that silently matches nothing is worse than no sweep, and a count floor is
    /// the wrong way to notice: it also fires when someone *fixes* a call site. This runs the same
    /// matcher and the same gate over fixtures instead, so it fails when the sweep breaks and stays
    /// quiet when the app gets more private.
    func testPercentageSweepStillCatchesALeak() {
        // Every spelling the matcher claims to catch, in a shape it has to report.
        let leaks = [
            "formattedPercent(": "Text(formattedPercent(percent, locale: settings.effectiveLocale))",
            "space before paren": "Text(formattedPercent (percent, locale: settings.effectiveLocale))",
            "printf %%": #"Text(String(format: "%.1f%%", percent))"#,
            ".formatted(.percent": "Text((percent / 100).formatted(.percent.precision(.fractionLength(1))))",
        ]
        for (name, line) in leaks {
            let fixture = ["var body: some View {", "    " + line, "}"]
            let source = Self.stripped(fixture.joined(separator: "\n"))
            guard let match = Self.percentageMatch(at: 1, in: source) else {
                XCTFail("the sweep no longer sees a percentage in \(name): \(line)")
                continue
            }
            XCTAssertFalse(
                Self.isPrivacyGated(at: 1, column: match.column, in: source.code),
                "the sweep called an ungated \(name) render gated: \(line)"
            )
        }

        // …and the two gate idioms the codebase actually uses, which it must not report.
        let gated = [
            "inline ternary": [
                "var body: some View {",
                "    Text(settings.isPrivacyMode ? settings.redactionToken : formattedPercent(p, locale: l))",
                "}",
            ],
            "enclosing if": [
                "var body: some View {",
                "    if !settings.isPrivacyMode {",
                "        Text(formattedPercent(p, locale: l))",
                "    }",
                "}",
            ],
        ]
        for (name, fixture) in gated {
            let source = Self.stripped(fixture.joined(separator: "\n"))
            let index = fixture.count == 3 ? 1 : 2
            guard let match = Self.percentageMatch(at: index, in: source) else {
                XCTFail("the sweep no longer sees a percentage in the \(name) fixture")
                continue
            }
            XCTAssertTrue(
                Self.isPrivacyGated(at: index, column: match.column, in: source.code),
                "the sweep would now report the \(name) idiom, which is the codebase's own"
            )
        }

        // …and the same two idioms with the check flipped. Both print the live figure exactly
        // while Privacy Mode is on. `isPrivacyGated` used to ask only whether the flag was named,
        // so both read as gated.
        let flipped = [
            "inline ternary": ([
                "var body: some View {",
                "    Text(!settings.isPrivacyMode ? settings.redactionToken : formattedPercent(p, locale: l))",
                "}",
            ], 1),
            "enclosing if": ([
                "var body: some View {",
                "    if settings.isPrivacyMode {",
                "        Text(formattedPercent(p, locale: l))",
                "    }",
                "}",
            ], 2),
        ]
        for (name, (fixture, index)) in flipped {
            let source = Self.stripped(fixture.joined(separator: "\n"))
            guard let match = Self.percentageMatch(at: index, in: source) else {
                XCTFail("the sweep no longer sees a percentage in the flipped \(name) fixture")
                continue
            }
            XCTAssertFalse(
                Self.isPrivacyGated(at: index, column: match.column, in: source.code),
                "the \(name) gate reads the same flipped, so a branch swap is invisible"
            )
        }

        // A sibling's gate is not this render's gate — the hole that let a live Performance card
        // sit in a `LazyVGrid` beside `••••`-masked ones.
        let sibling = [
            "LazyVGrid(columns: columns, spacing: 12) {",
            #"    MetricCard(title: "Holdings", value: settings.isPrivacyMode ? settings.redactionToken : "\(count)")"#,
            #"    MetricCard(title: "Performance", value: formattedPercent(percent, locale: l))"#,
            "}",
        ]
        let source = Self.stripped(sibling.joined(separator: "\n"))
        guard let match = Self.percentageMatch(at: 2, in: source) else {
            return XCTFail("the sweep no longer sees the sibling-gate fixture's percentage")
        }
        XCTAssertFalse(
            Self.isPrivacyGated(at: 2, column: match.column, in: source.code),
            "a privacy check on a sibling card counts as this card's gate again"
        )
    }

    // MARK: - Chart geometry

    /// Fails if any scanned source draws a donut that Privacy Mode does not conceal.
    ///
    /// **Why a second sweep rather than a case of the first.** Redaction and concealment are
    /// different promises. The percentage sweep asks whether a *number* is masked; this one asks
    /// whether a *shape* is drawn, because a wedge's angle is its share of the total whether or not
    /// the label beside it says `••••`. `SankeyDiagramView.swift:54-56` states the rule in prose and
    /// `PrivacyChartCover`'s own message states it to the user — "Values and proportions are hidden."
    ///
    /// **What it actually checks**, with the same two caveats as the percentage sweep: it greps the
    /// working tree via `#filePath`, not the binary under test, and it is a lint, so it only sees
    /// the spellings in `geometryPatterns`.
    ///
    /// **What draws a proportion here.** An earlier version of this comment claimed `SectorMark`
    /// was "the only proportional-geometry primitive in this codebase". Three of its four negatives
    /// are true — there is no `Gauge`, no `Canvas` and no sparkline anywhere — but the claim was
    /// wrong, and being wrong about the inventory is how a sweep ends up looking complete while a
    /// live proportion sits beside it. The full list, checked against the tree:
    ///
    /// - `SectorMark` — the donut wedge. Two sites: `DesignSystem.swift` and `CashFlowView.swift`.
    /// - `BarMark` — six sites, all cash-flow columns. A bar's length is its share just as much as
    ///   a wedge's angle is, so `Chart(categories) { BarMark(x: .value("Expense", item.value)) }`
    ///   in the privacy branch is the same leak in a different mark. Matched.
    /// - `.trim(from:to:)` — absent today, but `Circle().trim(…).stroke(…)` over running category
    ///   shares is a donut with no `SectorMark` in it at all. Matched, so it cannot arrive unseen.
    /// - A **data-scaled `.frame`** — `DashboardView.swift:553` sizes a `Capsule` to
    ///   `geometry.size.width * <share>`, a proportional bar built out of layout rather than
    ///   Charts. Matched by shape: a measured `size.width`/`size.height` scaled by something that
    ///   is not a numeric literal. Decorative uses (`min(proxy.size.width * 0.95, 420)`, the
    ///   background-glow `.offset`s) scale by literals and are not matched.
    /// - `Path`-based ribbons (`SankeyDiagramView.swift:183`, `:544`) and the report's `addArc`
    ///   donut (`ReportChartRenderer.swift:565-569`) are **not** matched. The Sankey conceals its
    ///   whole diagram before it does anything else (`SankeyDiagramView.swift:45-53`) and the
    ///   report files are in `excludedFiles` because an export redacts nothing by design. A new
    ///   hand-drawn `Path` proportion elsewhere would be invisible here.
    ///
    /// **The gate a chart has to sit under** is an enclosing `isPrivacyMode` branch that Privacy
    /// Mode does *not* take — `isConcealed` — or an inline gate on the mark's own expression —
    /// `isPrivacyGated`, which is what covers the data-scaled `.frame`, whose conceal is a
    /// `settings.isPrivacyMode ? 0 :` rather than a branch. Both are polarity-aware: naming the
    /// flag is not enough, the chart has to be on the arm that draws when privacy is off.
    ///
    /// **Holes left open, deliberately.** Each of these was built and landed with the suite green
    /// before this sweep was repaired; the first four are now caught, these are not:
    ///
    /// 1. Indirection of any kind. A `SectorMark` behind a renamed wrapper, a chart assembled by a
    ///    function in another file, a mark chosen at runtime — the sweep reads text, not meaning.
    /// 2. A proportion drawn by hand into a `Path`, as the Sankey does. Matching `Path` generally
    ///    would report every leader line and every rounded corner in the codebase.
    /// 3. A conceal that is technically present but ineffective: `SectorMark(angle: …, innerRadius:
    ///    settings.isPrivacyMode ? .ratio(1) : .ratio(0.72))` mentions the flag on the mark's own
    ///    expression and still draws every wedge.
    /// 4. The binary. A green run says the sources on disk are clean, nothing more — see the
    ///    percentage sweep's first caveat, which applies here word for word.
    func testWorkingTreeSourcesDrawNoUnconcealedDonut() throws {
        let sources = URL(fileURLWithPath: #filePath)   // …/Tests/PrivacyRedactionTests.swift
            .deletingLastPathComponent()                // …/Tests
            .deletingLastPathComponent()                // …/WealthCompass
            .appendingPathComponent("Sources")

        var offenders: [PercentRender] = []
        var filesRead = 0

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .filter { !Self.excludedFiles.contains("\(directory)/\($0)") }
                .sorted()
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "read no Swift files under \(root.path) — the sweep is not seeing the source tree"
            )

            for file in swiftFiles {
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                let source = Self.stripped(text)
                filesRead += 1

                for index in source.code.indices {
                    guard let match = Self.geometryMatch(at: index, in: source.code) else { continue }
                    guard !Self.isConcealed(at: index, column: match.column, in: source.code) else { continue }
                    guard !Self.isPrivacyGated(at: index, column: match.column, in: source.code) else { continue }
                    offenders.append(PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1, pattern: match.pattern,
                        source: String(source.code[index]).trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        XCTAssertGreaterThan(filesRead, 20, "only \(filesRead) Swift files enumerated — the sweep lost the source tree")

        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) donut(s) draw true proportions while Privacy Mode is on. Conceal the \
            chart behind a privacy branch instead of redacting only its labels:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    /// The alarm for the sweep above, in the shape `testPercentageSweepStillCatchesALeak` takes: a
    /// source sweep that quietly matches nothing, or calls everything gated, is worse than no sweep.
    func testDonutSweepStillCatchesALeak() {
        /// The sweep's own verdict on a matched proportion: an enclosing conceal branch, or an
        /// inline gate on the mark's own expression.
        func isSafe(_ code: [[Character]], at line: Int, column: Int) -> Bool {
            Self.isConcealed(at: line, column: column, in: code)
                || Self.isPrivacyGated(at: line, column: column, in: code)
        }

        /// A fixture is `(lines, the line the proportion is on)`.
        func match(_ fixture: [String], _ line: Int, _ name: String) -> ([[Character]], Int)? {
            let code = Self.stripped(fixture.joined(separator: "\n")).code
            guard let found = Self.geometryMatch(at: line, in: code) else {
                XCTFail("the sweep no longer sees a proportion in the \(name) fixture")
                return nil
            }
            return (code, found.column)
        }

        // Every spelling the sweep claims to catch, drawn with nothing in front of it.
        let leaks: [String: ([String], Int)] = [
            "plain SectorMark": (["var body: some View {",
                                  "    Chart(slices) { slice in",
                                  "        SectorMark(angle: .value(\"Value\", slice.value))",
                                  "    }",
                                  "}"], 2),
            "SectorMark with a space": (["var body: some View {",
                                         "    Chart(slices) { slice in",
                                         "        SectorMark (angle: .value(\"Value\", slice.value))",
                                         "    }",
                                         "}"], 2),
            // Same proportions, different mark.
            "BarMark": (["var body: some View {",
                         "    Chart(categories) { item in",
                         "        BarMark(x: .value(\"Expense\", item.value))",
                         "    }",
                         "}"], 2),
            // A donut with no `SectorMark` in it at all.
            "a trimmed ring": (["var body: some View {",
                                "    ForEach(categories) { item in",
                                "        Circle().trim(from: 0, to: item.value / total).stroke(color)",
                                "    }",
                                "}"], 2),
            // `DashboardView.swift:553` with its inline gate dropped.
            "a data-scaled frame": (["var body: some View {",
                                     "    GeometryReader { geometry in",
                                     "        Capsule()",
                                     "            .frame(width: geometry.size.width * max(0, item.percentage / 100))",
                                     "    }",
                                     "}"], 3),
        ]
        for (name, (fixture, line)) in leaks {
            guard let (code, column) = match(fixture, line, name) else { continue }
            XCTAssertFalse(isSafe(code, at: line, column: column), "an unconcealed \(name) read as concealed")
        }

        // A length scaled by a literal is layout, not data. Reporting `min(proxy.size.width * 0.95,
        // 420)` forever is how a sweep gets switched off.
        let decorative = ["var body: some View {",
                          "    GeometryReader { proxy in",
                          "        Image(\"glow\")",
                          "            .frame(width: min(proxy.size.width * 0.95, 420))",
                          "    }",
                          "}"]
        XCTAssertNil(
            Self.geometryMatch(at: 3, in: Self.stripped(decorative.joined(separator: "\n")).code),
            "a literal-scaled .frame reads as a data proportion"
        )

        // The conceal shapes the codebase uses — the flat `else if` chain (`AllocationChart`,
        // `CashFlowView`), the `ZStack` + inner `if` (`MacDashboardView`), the inline gate
        // (`DashboardView.swift:553`) — each also written in Allman braces, which changes where
        // the `{` sits and must not change the verdict.
        let concealed: [String: ([String], Int)] = [
            "else-if chain": ([
                "var body: some View {",
                "    if slices.isEmpty {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    } else if settings.isPrivacyMode {",
                "        MobilePrivacyChartCover(",
                "            title: \"Allocation concealed\",",
                "            message: \"Values and proportions are hidden.\"",
                "        )",
                "    } else {",
                "        Chart(slices) { slice in",
                "            SectorMark(angle: .value(\"Value\", slice.value))",
                "        }",
                "    }",
                "}",
            ], 10),
            "else-if chain, Allman": ([
                "var body: some View {",
                "    if slices.isEmpty",
                "    {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    }",
                "    else if settings.isPrivacyMode",
                "    {",
                "        MobilePrivacyChartCover(title: title, message: message)",
                "    }",
                "    else",
                "    {",
                "        Chart(slices) { slice in",
                "            SectorMark(angle: .value(\"Value\", slice.value))",
                "        }",
                "    }",
                "}",
            ], 12),
            "ZStack with inner if": ([
                "var body: some View {",
                "    ZStack {",
                "        if settings.isPrivacyMode {",
                "            PrivacyChartCover(title: title, message: message)",
                "        } else {",
                "            Chart(slices) { slice in",
                "                SectorMark(angle: .value(\"Value\", slice.value))",
                "            }",
                "        }",
                "    }",
                "}",
            ], 6),
            "ZStack with inner if, Allman": ([
                "var body: some View {",
                "    ZStack",
                "    {",
                "        if settings.isPrivacyMode",
                "        {",
                "            PrivacyChartCover(title: title, message: message)",
                "        }",
                "        else",
                "        {",
                "            Chart(slices) { slice in",
                "                SectorMark(angle: .value(\"Value\", slice.value))",
                "            }",
                "        }",
                "    }",
                "}",
            ], 10),
            // The other polarity, written correctly: the chart in the body of a negated check.
            "negated if": ([
                "var body: some View {",
                "    if !settings.isPrivacyMode {",
                "        Chart(slices) { slice in",
                "            SectorMark(angle: .value(\"Value\", slice.value))",
                "        }",
                "    }",
                "}",
            ], 3),
            // No branch at all — the bar is simply given no width while privacy is on.
            "inline gate on the mark": ([
                "var body: some View {",
                "    GeometryReader { geometry in",
                "        Capsule()",
                "            .frame(width: settings.isPrivacyMode ? 0 : geometry.size.width * item.share)",
                "    }",
                "}",
            ], 3),
        ]
        for (name, (fixture, line)) in concealed {
            guard let (code, column) = match(fixture, line, name) else { continue }
            XCTAssertTrue(isSafe(code, at: line, column: column),
                          "the sweep would now report the \(name) conceal, which is the codebase's own")
        }

        // The same four shapes with the check flipped. Every one of these draws the true
        // proportions in Privacy Mode, and every one of them was read as concealed until
        // `PrivacyGate` started asking which arm the chart is on: adding a `!` to
        // `AllocationChart`'s own branch used to leave the whole suite green.
        let flipped: [String: ([String], Int)] = [
            "else-if chain": ([
                "var body: some View {",
                "    if slices.isEmpty {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    } else if !settings.isPrivacyMode {",
                "        MobilePrivacyChartCover(title: title, message: message)",
                "    } else {",
                "        Chart(slices) { slice in",
                "            SectorMark(angle: .value(\"Value\", slice.value))",
                "        }",
                "    }",
                "}",
            ], 7),
            "ZStack with inner if": ([
                "var body: some View {",
                "    ZStack {",
                "        if !settings.isPrivacyMode {",
                "            PrivacyChartCover(title: title, message: message)",
                "        } else {",
                "            Chart(slices) { slice in",
                "                SectorMark(angle: .value(\"Value\", slice.value))",
                "            }",
                "        }",
                "    }",
                "}",
            ], 6),
            "positive if": ([
                "var body: some View {",
                "    if settings.isPrivacyMode {",
                "        Chart(slices) { slice in",
                "            SectorMark(angle: .value(\"Value\", slice.value))",
                "        }",
                "    }",
                "}",
            ], 3),
            "inline gate on the mark": ([
                "var body: some View {",
                "    GeometryReader { geometry in",
                "        Capsule()",
                "            .frame(width: !settings.isPrivacyMode ? 0 : geometry.size.width * item.share)",
                "    }",
                "}",
            ], 3),
        ]
        for (name, (fixture, line)) in flipped {
            guard let (code, column) = match(fixture, line, name) else { continue }
            XCTAssertFalse(isSafe(code, at: line, column: column),
                           "the \(name) conceal reads the same flipped, so a branch swap is invisible")
        }

        // A privacy check on a sibling statement is not this chart's gate — the same hole the
        // percentage sweep had to close.
        let sibling = [
            "var body: some View {",
            "    VStack {",
            "        Text(settings.isPrivacyMode ? settings.redactionToken : total)",
            "        Chart(slices) { slice in",
            "            SectorMark(angle: .value(\"Value\", slice.value))",
            "        }",
            "    }",
            "}",
        ]
        if let (code, column) = match(sibling, 4, "sibling-gate") {
            XCTAssertFalse(isSafe(code, at: 4, column: column),
                           "a privacy check on a sibling row counts as the chart's gate")
        }

        // …and a conceal in a *different* declaration is not this chart's gate either.
        let elsewhere = [
            "var cover: some View {",
            "    if settings.isPrivacyMode {",
            "        MobilePrivacyChartCover(title: title, message: message)",
            "    }",
            "}",
            "",
            "var ring: some View {",
            "    Chart(slices) { slice in",
            "        SectorMark(angle: .value(\"Value\", slice.value))",
            "    }",
            "}",
        ]
        if let (code, column) = match(elsewhere, 8, "other-declaration") {
            XCTAssertFalse(isSafe(code, at: 8, column: column),
                           "a conceal written in another computed property counts as this chart's gate")
        }
    }

    // MARK: - Branch order

    /// Fails if a privacy cover is not the *first* branch of the chain it sits in.
    ///
    /// **What emptiness gives away.** A chart card has three states — no data, concealed, drawn —
    /// and for a long time every card but one checked them in that order. So with Privacy Mode on
    /// and no data the user got "No assets found" or "No recent cash flow" instead of a cover, and
    /// a bystander learned the category is empty. `SankeyDiagramView.swift:45-53` argued the other
    /// way from the start: "whether a period is empty is itself information". That reasoning now
    /// holds everywhere, and this is what keeps it holding.
    ///
    /// It bites hardest on the two cards under a range picker. Net worth and cash flow both let
    /// anyone holding the device toggle 1W/1M/3M/6M/12M; if the empty state wins, walking the
    /// picker maps which windows contain data, with every figure still redacted. The allocation
    /// donuts offer no such probe, which is why those are the milder half of the same rule.
    ///
    /// **The rule, stated structurally.** Nothing may be evaluated ahead of the cover. It has to
    /// open its own `if` chain — `if settings.isPrivacyMode { cover }`, never
    /// `} else if settings.isPrivacyMode { cover }` — *and* no enclosing block, out to the
    /// declaration, may be conditional either. Both halves are needed: `CashFlowView` and
    /// `MacDashboardView` wrote `if categories.isEmpty { … } else { if settings.isPrivacyMode
    /// { cover } … }`, where the privacy check does open a chain and the emptiness test is simply
    /// one level out. Against the tree as it stood before this ordering change, the first half
    /// alone found six of the eight sites.
    ///
    /// The check is deliberately blunt: it does not try to prove the earlier condition is
    /// data-dependent, it requires there to be no earlier condition. A chain whose first branch is
    /// some genuinely privacy-independent thing would have to be argued for here rather than
    /// written past.
    ///
    /// Same caveats as the other two sweeps: it reads the working tree, not the binary, and only
    /// the cover spellings in `coverPatterns`. A card that draws no cover at all is invisible to
    /// it — `MacDashboardView.swift:746` is the one such site, and it makes the same guarantee by
    /// hand with `if sankey.isEmpty && !settings.isPrivacyMode`.
    func testWorkingTreeChecksPrivacyBeforeEmptiness() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        var offenders: [PercentRender] = []
        var covers = 0

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .filter { !Self.excludedFiles.contains("\(directory)/\($0)") }
                .sorted()
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "read no Swift files under \(root.path) — the sweep is not seeing the source tree"
            )

            for file in swiftFiles {
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                let source = Self.stripped(text)

                for index in source.scan.indices {
                    guard let match = Self.coverMatch(at: index, in: source) else { continue }
                    covers += 1
                    guard !Self.privacyIsCheckedFirst(at: index, column: match.column, in: source.code) else { continue }
                    offenders.append(PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1, pattern: match.pattern,
                        source: String(source.scan[index]).trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        XCTAssertGreaterThan(covers, 5, "only \(covers) privacy cover(s) found — the sweep lost the source tree")

        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) privacy cover(s) sit behind another branch, so something else renders \
            first while Privacy Mode is on. Move the privacy check to the head of the chain:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    /// The alarm for the sweep above, in the shape the other two take.
    func testBranchOrderSweepStillCatchesALeak() {
        func check(_ fixture: [String], _ line: Int, _ name: String) -> Bool? {
            let source = Self.stripped(fixture.joined(separator: "\n"))
            guard let match = Self.coverMatch(at: line, in: source) else {
                XCTFail("the sweep no longer sees a cover in the \(name) fixture")
                return nil
            }
            return Self.privacyIsCheckedFirst(at: line, column: match.column, in: source.code)
        }

        // Emptiness first — what every card but the Sankey used to do.
        let emptinessFirst: [String: ([String], Int)] = [
            "else-if cover": ([
                "var body: some View {",
                "    if slices.isEmpty {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    } else if settings.isPrivacyMode {",
                "        MobilePrivacyChartCover(title: title, message: message)",
                "    } else {",
                "        chart",
                "    }",
                "}",
            ], 4),
            "else-if cover, Allman": ([
                "var body: some View {",
                "    if slices.isEmpty",
                "    {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    }",
                "    else if settings.isPrivacyMode",
                "    {",
                "        PrivacyChartCover(title: title, message: message)",
                "    }",
                "}",
            ], 7),
            // The cover spelled as an `EmptyState`, which is what macOS Cash Flow and the Sankey use.
            "else-if EmptyState cover": ([
                "var body: some View {",
                "    if !hasCashFlow {",
                "        EmptyState(title: \"No recent cash flow\", systemImage: \"chart.bar.xaxis\")",
                "    } else if settings.isPrivacyMode {",
                "        EmptyState(title: \"Cash-flow chart concealed\", systemImage: \"eye.slash\")",
                "    }",
                "}",
            ], 4),
            // The nested variant: the privacy check *does* open its own chain, but that chain only
            // runs inside the `else` of an emptiness test one level out. `CashFlowView` and
            // `MacDashboardView` were both written this way, and a check that only reads the line
            // above the cover calls both of them clean.
            "privacy nested inside the non-empty branch": ([
                "var body: some View {",
                "    if categories.isEmpty {",
                "        EmptyState(title: \"No expenses for this period\", systemImage: \"chart.pie\")",
                "    } else {",
                "        if settings.isPrivacyMode {",
                "            MobilePrivacyChartCover(title: title, message: message)",
                "        } else {",
                "            chart",
                "        }",
                "    }",
                "}",
            ], 5),
            // The three desktop spellings of the "Hidden by Privacy Mode" cover, reverted to the
            // order they had before `f3fac7c` / `fb5272c`. None of these was swept at all until
            // the title pattern was added. They had no other coverage back when they lived in
            // `Sources/macOS`, which the `WealthCompassMobile` test host could not render; since
            // the move to `Sources/Desktop` they compile into this host, so that is no longer the
            // reason they are pinned here — the sweep is.
            "ContentUnavailableView cover behind emptiness": ([
                "var body: some View {",
                "    if topHoldings.isEmpty {",
                "        ContentUnavailableView(",
                "            \"No Investments\",",
                "            systemImage: \"chart.line.uptrend.xyaxis\"",
                "        )",
                "    } else if settings.isPrivacyMode {",
                "        ContentUnavailableView(",
                "            \"Hidden by Privacy Mode\",",
                "            systemImage: \"eye.slash\"",
                "        )",
                "    }",
                "}",
            ], 8),
            "DashboardEmptyState cover behind emptiness": ([
                "var body: some View {",
                "    if transactions.isEmpty {",
                "        DashboardEmptyState(",
                "            title: \"No activity yet\",",
                "            systemImage: \"clock.arrow.circlepath\"",
                "        )",
                "    } else if settings.isPrivacyMode {",
                "        DashboardEmptyState(",
                "            title: \"Hidden by Privacy Mode\",",
                "            systemImage: \"eye.slash\"",
                "        )",
                "    }",
                "}",
            ], 8),
            "EmptyState cover behind emptiness": ([
                "var body: some View {",
                "    if !hasAnyTransactions {",
                "        EmptyState(title: \"No transactions found\", systemImage: \"tray\")",
                "    } else if settings.isPrivacyMode, filtered.isEmpty {",
                "        EmptyState(title: \"Hidden by Privacy Mode\", systemImage: \"eye.slash\")",
                "    }",
                "}",
            ], 4),
        ]
        for (name, (fixture, line)) in emptinessFirst {
            if let opens = check(fixture, line, name) {
                XCTAssertFalse(opens, "a cover behind an emptiness check reads as first in its chain (\(name))")
            }
        }

        // Privacy first — the shape the codebase now uses everywhere.
        let privacyFirst: [String: ([String], Int)] = [
            "cover opens the chain": ([
                "var body: some View {",
                "    if settings.isPrivacyMode {",
                "        MobilePrivacyChartCover(title: title, message: message)",
                "    } else if slices.isEmpty {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    } else {",
                "        chart",
                "    }",
                "}",
            ], 2),
            "cover opens the chain, Allman": ([
                "var body: some View {",
                "    if settings.isPrivacyMode",
                "    {",
                "        PrivacyChartCover(title: title, message: message)",
                "    }",
                "    else if slices.isEmpty",
                "    {",
                "        EmptyState(title: \"No assets found\", systemImage: \"chart.pie\")",
                "    }",
                "}",
            ], 3),
            // `MacDashboardView`'s asset ring shape, before this ordering change reached it.
            "inside a ZStack": ([
                "var body: some View {",
                "    ZStack {",
                "        if settings.isPrivacyMode {",
                "            PrivacyChartCover(title: title, message: message)",
                "        } else {",
                "            chart",
                "        }",
                "    }",
                "}",
            ], 3),
            // The macOS spellings as the tree actually holds them: the title sits inside the
            // constructor's parentheses, one or two lines below the `{` that opens the branch.
            "ContentUnavailableView cover opens the chain": ([
                "var body: some View {",
                "    if settings.isPrivacyMode, topHoldings.isEmpty {",
                "        ContentUnavailableView(",
                "            \"Hidden by Privacy Mode\",",
                "            systemImage: \"eye.slash\"",
                "        )",
                "    } else if topHoldings.isEmpty {",
                "        ContentUnavailableView(\"No Investments\", systemImage: \"chart.pie\")",
                "    }",
                "}",
            ], 3),
            "DashboardEmptyState cover opens the chain": ([
                "var body: some View {",
                "    if settings.isPrivacyMode, transactions.isEmpty {",
                "        DashboardEmptyState(",
                "            title: \"Hidden by Privacy Mode\",",
                "            systemImage: \"eye.slash\"",
                "        )",
                "    } else if transactions.isEmpty {",
                "        DashboardEmptyState(title: \"No activity yet\", systemImage: \"clock\")",
                "    }",
                "}",
            ], 3),
            // The `String`-returning helper shape: `MacCashFlowView.transactionEmptyTitle` picks
            // the table's empty title in Swift rather than in the view body, and the same rule
            // has to reach it.
            "cover chosen in a String helper": ([
                "private var transactionEmptyTitle: String {",
                "    if settings.isPrivacyMode {",
                "        return settings.localized(\"Hidden by Privacy Mode\")",
                "    }",
                "    return settings.localized(\"No Transactions\")",
                "}",
            ], 2),
        ]
        for (name, (fixture, line)) in privacyFirst {
            if let opens = check(fixture, line, name) {
                XCTAssertTrue(opens, "the sweep would now report the \(name) shape, which is the codebase's own")
            }
        }

        // A cover under a check that is not a privacy check is not a privacy branch at all.
        let wrongFlag = [
            "var body: some View {",
            "    if isCompactLayout {",
            "        MobilePrivacyChartCover(title: title, message: message)",
            "    }",
            "}",
        ]
        if let opens = check(wrongFlag, 2, "non-privacy gate") {
            XCTAssertFalse(opens, "a cover under an unrelated flag reads as a privacy branch")
        }

        // …and one under a *negated* privacy check renders exactly when privacy is off.
        let negated = [
            "var body: some View {",
            "    if !settings.isPrivacyMode {",
            "        MobilePrivacyChartCover(title: title, message: message)",
            "    }",
            "}",
        ]
        if let opens = check(negated, 2, "negated gate") {
            XCTAssertFalse(opens, "a cover under `!isPrivacyMode` reads as a privacy branch")
        }
    }

    // MARK: - Existence

    /// Two snapshots inside the hero's default 1W window, so `netWorthChange` is non-nil and the
    /// movement row has something to draw. Dated off `Date()` rather than off a fixed instant for
    /// exactly that reason: a hard-coded 2026 date falls outside 1W within months, `rangeChange`
    /// goes nil in *both* states, and the fixture stops exercising the branch it exists for while
    /// the test stays green.
    private func snapshotFixture() -> [NetWorthSnapshot] {
        let now = Date()
        return [
            NetWorthSnapshot(
                date: now.addingTimeInterval(-86_400 * 5), totalAssets: 10_000, totalLiabilities: 0,
                netWorth: 10_000, liquidity: 5_000, investments: 5_000, crypto: 0, currency: .eur
            ),
            NetWorthSnapshot(
                date: now.addingTimeInterval(-86_400 * 1), totalAssets: 12_000, totalLiabilities: 0,
                netWorth: 12_000, liquidity: 6_000, investments: 6_000, crypto: 0, currency: .eur
            ),
        ]
    }

    /// Draws the real `DashboardView` — real `FinanceStore`, real `AppSettings`, real SwiftUI
    /// layout — and returns the PNG bytes.
    ///
    /// `UIHostingController` in a key `UIWindow`, captured through `layer.render(in:)`. Three
    /// other instruments were measured against this view and rejected, which is worth recording
    /// because each looks like it should work:
    ///
    /// * `ImageRenderer(content: DashboardView(...))` returns *the same bytes for every input* —
    ///   with data, without data, Privacy Mode on and off. It never draws the body.
    /// * `window.drawHierarchy(in:afterScreenUpdates: true)` on a window that belongs to no scene
    ///   returns a 6 KB blank, and blank compares equal to blank, so it passes this test always.
    /// * Walking `accessibilityElements` finds only the UIKit segmented controls ("1W", "1M", …).
    ///   SwiftUI does not publish a `Text` through that tree, so a VoiceOver-shaped assertion
    ///   could not see the strings at issue either.
    ///
    /// Only `layer.render(in:)` yields real content (~290 KB) that moves when the data moves.
    private func renderDashboard(snapshots: [NetWorthSnapshot], privacyMode: Bool) -> Data {
        let settings = makeSettings()
        settings.isPrivacyMode = privacyMode
        let store = FinanceStore(
            persistence: SeededPersistence(FinancialData(snapshots: snapshots)),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore()
        )
        let host = UIHostingController(
            rootView: DashboardView(selectedTab: .constant(.dashboard))
                .environmentObject(store)
                .environmentObject(settings)
        )
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 700)
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        // The hero animates its chart and its delta on a spring. Let the first frame settle, or
        // two captures of the same state can disagree for reasons that have nothing to do with
        // privacy — which `sameStateRendersIdentically` below would then report as instability.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: bounds, format: format)
            .image { context in host.view.layer.render(in: context.cgContext) }
            .pngData() ?? Data()
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Fails if Privacy Mode lets the Dashboard disclose **whether snapshots exist**.
    ///
    /// The three sweeps above are lints: they read the working tree, they cannot follow
    /// indirection, and a green run says only that the checked-out `.swift` files look clean. This
    /// one asserts on the app instead. It renders the Dashboard twice with Privacy Mode on,
    /// changing nothing but `FinancialData.snapshots`, and requires the two images to be
    /// byte-identical — the owner's rule stated as a property: with the cover up, no pixel may
    /// depend on whether there is data behind it.
    ///
    /// It was written against four known tells, all in `netWorthHero`, and fails on any of them:
    /// `"Add another snapshot to see movement"` and the movement row it alternates with (whose
    /// arrow and tint spell the *sign* of the change even though both figures beside them are
    /// already `••••`), `"No snapshots"` and the freshness badge it alternates with.
    ///
    /// **The controls matter more than the assertion.** A capture that silently went blank would
    /// satisfy byte-equality forever — that is exactly what `drawHierarchy` does here — so the
    /// size floor, the determinism check and above all `rendererIsReadingSnapshots` are what stop
    /// this from becoming the second vacuous test in this file's history. If the last of those
    /// ever fails, this test is asserting nothing and must be fixed before it is trusted again.
    ///
    /// **Reach.** iOS only. The bundle hosts `WealthCompassMobile`, so `MacDashboardView`'s
    /// identical pair of sites cannot be rendered here and rests on review. And it varies only
    /// `snapshots`: every other collection on this screen has its own ungated empty state, and
    /// those are still open.
    func testPrivacyModeConcealsWhetherSnapshotsExist() throws {
        let concealedWithout = renderDashboard(snapshots: [], privacyMode: true)
        let concealedWithoutAgain = renderDashboard(snapshots: [], privacyMode: true)
        let concealedWith = renderDashboard(snapshots: snapshotFixture(), privacyMode: true)
        let openWithout = renderDashboard(snapshots: [], privacyMode: false)
        let openWith = renderDashboard(snapshots: snapshotFixture(), privacyMode: false)

        XCTAssertGreaterThan(
            concealedWithout.count, 50_000,
            "captured \(concealedWithout.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )

        XCTAssertEqual(
            digest(concealedWithout), digest(concealedWithoutAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )

        XCTAssertNotEqual(
            digest(openWithout), digest(openWith),
            """
            With Privacy Mode OFF the Dashboard rendered identically with and without snapshots.             That is not a privacy result — it means the render is no longer reading             `data.snapshots`, so the assertion below can no longer fail and must not be trusted.
            """
        )

        XCTAssertEqual(
            digest(concealedWithout), digest(concealedWith),
            """
            With Privacy Mode ON the Dashboard rendered differently with and without snapshots, so             a bystander holding the device can read off whether this person tracks a net worth at             all — the one thing the cover over the chart exists to refuse. Look in `netWorthHero`:             the movement row and its "Add another snapshot to see movement" alternative, and             `snapshotFreshness` and its "No snapshots" alternative, all have to be behind the             privacy gate, not beside it.
            """
        )
    }

    // MARK: - Existence: counts

    /// One of each entity, `n` times over, so two fixtures can differ **only** in how many records
    /// exist. Every count-shaped leak in the app reads a `.count` off one of these arrays, and a
    /// 1-vs-2 pair exercises them without ever flipping an `isEmpty` — which keeps the empty-state
    /// branches, the onboarding card and `isCompletelyEmpty` out of the comparison, so a failure
    /// can only be a count.
    private func records(_ n: Int) -> FinancialData {
        // Built step by step with explicit types on purpose: one `FinancialData(...)` literal
        // holding six mapped closures does not type-check in reasonable time. `Transaction` is
        // spelled out because this file imports SwiftUI, which has one of its own.
        let day: TimeInterval = 86_400
        let past = Date().addingTimeInterval(-day * 400)
        let future = Date().addingTimeInterval(day * 400)

        var transactions: [WealthCompassMobile.Transaction] = []
        var schedules: [RecurringTransaction] = []
        var investments: [Investment] = []
        var crypto: [CryptoHolding] = []
        var liabilities: [Liability] = []
        var snapshots: [NetWorthSnapshot] = []

        for i in 0..<n {
            let step = Decimal(i + 1)
            transactions.append(
                WealthCompassMobile.Transaction(
                    type: .expense,
                    category: "Food",
                    amount: step,
                    description: "note",
                    date: past,
                    currency: .eur
                )
            )
            schedules.append(
                RecurringTransaction(
                    type: .expense,
                    category: "Food",
                    amount: step,
                    description: "rec",
                    startDate: past,
                    frequency: .monthly,
                    nextDueDate: future,
                    currency: .eur
                )
            )
            investments.append(
                Investment(
                    type: .stock,
                    symbol: "S",
                    name: "Stock",
                    quantity: 1,
                    costBasis: step,
                    currentValue: step,
                    currentPrice: step,
                    currency: .eur,
                    geography: "US",
                    sector: "Technology",
                    isin: "",
                    fees: 0
                )
            )
            crypto.append(
                CryptoHolding(
                    symbol: "C",
                    name: "Coin",
                    quantity: 1,
                    avgBuyPrice: step,
                    currentPrice: step,
                    currency: .eur,
                    fees: 0,
                    coinId: "coin"
                )
            )
            liabilities.append(
                Liability(name: "Loan", currentBalance: step, currency: .eur)
            )
            snapshots.append(
                NetWorthSnapshot(
                    date: past.addingTimeInterval(-day * Double(i)),
                    totalAssets: 10_000,
                    totalLiabilities: 0,
                    netWorth: 10_000,
                    liquidity: 5_000,
                    investments: 5_000,
                    crypto: 0,
                    currency: .eur
                )
            )
        }

        return FinancialData(
            transactions: transactions,
            recurringTransactions: schedules,
            investments: investments,
            crypto: crypto,
            liabilities: liabilities,
            snapshots: snapshots
        )
    }

    /// The generic half of `renderDashboard`, so the same instrument can be pointed at any screen.
    /// Read that method's doc comment first — it records the three instruments that produce a
    /// vacuous test here and must not be reached for again.
    ///
    /// `height` is load-bearing. The window is the viewport: a `List` or a `ScrollView` only
    /// realises what fits, so a screen whose leak sits below the fold renders identically at 700pt
    /// whatever the data — a pass that means nothing. Every caller below therefore states the
    /// height its leak needs, and each has a control assertion that fails if that height stopped
    /// reaching it.
    /// `cropTop` discards that many points from the top of the capture, leaving the layout
    /// untouched — the window is still `height` tall and lays out exactly as it would without it.
    /// It exists so a control can be made to depend on one element instead of on the whole screen:
    /// see `testPrivacyModeConcealsWhyTheTransactionListIsEmpty`, whose control was satisfied by a
    /// row four inches above the thing under test.
    private func renderScreen<V: View>(
        _ rootView: (FinanceStore, AppSettings) -> V,
        data: FinancialData,
        privacyMode: Bool,
        height: CGFloat,
        cropTop: CGFloat = 0
    ) -> Data {
        let settings = makeSettings()
        settings.isPrivacyMode = privacyMode
        let store = FinanceStore(
            persistence: SeededPersistence(data),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore()
        )
        let host = UIHostingController(rootView: rootView(store, settings))
        let bounds = CGRect(x: 0, y: 0, width: 393, height: height)
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let capture = CGRect(x: 0, y: 0, width: bounds.width, height: height - cropTop)
        return UIGraphicsImageRenderer(bounds: capture, format: format)
            .image { context in
                context.cgContext.translateBy(x: 0, y: -cropTop)
                host.view.layer.render(in: context.cgContext)
            }
            .pngData() ?? Data()
    }

    private func renderSettings(data: FinancialData, privacyMode: Bool) -> Data {
        // 3000pt because the Storage section is the last one on the page. At 700pt the `List` has
        // not realised those rows at all and the capture is identical for every fixture — measured,
        // not assumed.
        renderScreen(
            { store, settings in
                SettingsView()
                    .environmentObject(store)
                    .environmentObject(settings)
                    .environmentObject(AppLockStore())
            },
            data: data, privacyMode: privacyMode, height: 3_000
        )
    }

    /// Fails if Privacy Mode lets Settings → Storage read out **how many records exist**.
    ///
    /// Six rows printed `finance.data.<entity>.count` in the clear, one of them
    /// `finance.data.snapshots.count` — the exact number `b93f391` had just finished concealing on
    /// the Dashboard, spelled out one screen away. The fixtures differ only in count (1 vs 2), so
    /// nothing else on the page can move: no `isEmpty` flips, and the Refresh Prices button stays
    /// enabled in both (it disables itself when there are no holdings, which is its own tell — see
    /// the report, it is not fixed here).
    func testPrivacyModeConcealsHowManyRecordsAreStored() throws {
        let concealedOne = renderSettings(data: records(1), privacyMode: true)
        let concealedOneAgain = renderSettings(data: records(1), privacyMode: true)
        let concealedTwo = renderSettings(data: records(2), privacyMode: true)
        let openOne = renderSettings(data: records(1), privacyMode: false)
        let openTwo = renderSettings(data: records(2), privacyMode: false)

        XCTAssertGreaterThan(
            concealedOne.count, 50_000,
            "captured \(concealedOne.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedOne), digest(concealedOneAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )
        XCTAssertNotEqual(
            digest(openOne), digest(openTwo),
            """
            With Privacy Mode OFF the Settings page rendered identically for one record and for two.             The Storage rows are below the fold or no longer read `finance.data`, so the assertion             below cannot fail and must not be trusted.
            """
        )
        XCTAssertEqual(
            digest(concealedOne), digest(concealedTwo),
            """
            With Privacy Mode ON the Storage section still moves with the data, so a bystander can             read off exactly how many transactions, schedules, positions, holdings, liabilities and             snapshots this person has. All six rows have to go through `privateCount(_:)`.
            """
        )
    }

    /// Fails if Privacy Mode lets the Dashboard's Position grid read out **how many** positions,
    /// holdings or liabilities exist.
    ///
    /// The three cards masked their figures to `••••` and then printed "2 positions", "2 holdings",
    /// "2 liabilities" underneath — and "0 positions" when there were none, which is the same
    /// disclosure `InvestmentsView.swift:107` has always refused to make.
    ///
    /// 1600pt: the grid sits below the hero, and at 700pt it is not in the viewport at all.
    func testPrivacyModeConcealsHowManyPositionsTheDashboardSummarises() throws {
        func render(_ n: Int, privacy: Bool) -> Data {
            renderScreen(
                { store, settings in
                    DashboardView(selectedTab: .constant(.dashboard))
                        .environmentObject(store)
                        .environmentObject(settings)
                },
                data: records(n), privacyMode: privacy, height: 1_600
            )
        }

        let concealedOne = render(1, privacy: true)
        let concealedOneAgain = render(1, privacy: true)
        let concealedTwo = render(2, privacy: true)

        XCTAssertGreaterThan(
            concealedOne.count, 50_000,
            "captured \(concealedOne.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedOne), digest(concealedOneAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )
        XCTAssertNotEqual(
            digest(render(1, privacy: false)), digest(render(2, privacy: false)),
            """
            With Privacy Mode OFF the Dashboard rendered identically for one record and for two, so             the Position grid is out of the viewport or no longer reads the counts, and the assertion             below can no longer fail.
            """
        )
        XCTAssertEqual(
            digest(concealedOne), digest(concealedTwo),
            """
            With Privacy Mode ON the Position grid still counts out loud. Look at the `detail:` of             the Investments, Crypto and Liabilities cards in `positionSection` — a `%lld positions`             plural key cannot be tokenised, so under Privacy Mode the caption has to be a fixed             phrase that does not move with the data.
            """
        )
    }

    /// Fails if Privacy Mode lets the Recorded Cash card say **whether any cash flow exists**.
    ///
    /// Its caption read "No activity yet" with an empty transaction list and "Income less expenses"
    /// otherwise, directly under a figure already masked to `••••`.
    ///
    /// Both fixtures carry a liability so `isCompletelyEmpty` is false either way — that keeps the
    /// onboarding card out of the comparison, so a failure here is this caption and not that card.
    /// The transaction is **income**, because Net Savings picks its arrow and its tint from the
    /// sign of the month's balance and an expense would flip both (a value leak, not an existence
    /// one — reported separately, not fixed here). 1200pt keeps the ranked expense list and Recent
    /// Activity, which do move with the data by the owner's separate ruling, below the fold.
    func testPrivacyModeConcealsWhetherAnyCashFlowHasBeenRecorded() throws {
        let liability = Liability(name: "Loan", currentBalance: 1_000, currency: .eur)
        let quiet = FinancialData(liabilities: [liability])
        let active = FinancialData(
            transactions: [
                WealthCompassMobile.Transaction(
                    type: .income, category: "Salary", amount: 2_000, description: "pay",
                    date: Date().addingTimeInterval(-3_600), currency: .eur
                )
            ],
            liabilities: [liability]
        )

        func render(_ data: FinancialData, privacy: Bool) -> Data {
            renderScreen(
                { store, settings in
                    DashboardView(selectedTab: .constant(.dashboard))
                        .environmentObject(store)
                        .environmentObject(settings)
                },
                data: data, privacyMode: privacy, height: 1_200
            )
        }

        let concealedQuiet = render(quiet, privacy: true)
        let concealedQuietAgain = render(quiet, privacy: true)
        let concealedActive = render(active, privacy: true)

        XCTAssertGreaterThan(
            concealedQuiet.count, 50_000,
            "captured \(concealedQuiet.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedQuiet), digest(concealedQuietAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )
        XCTAssertNotEqual(
            digest(render(quiet, privacy: false)), digest(render(active, privacy: false)),
            """
            With Privacy Mode OFF the Dashboard rendered identically with and without a transaction,             so the Position grid is out of the viewport and the assertion below cannot fail.
            """
        )
        XCTAssertEqual(
            digest(concealedQuiet), digest(concealedActive),
            """
            With Privacy Mode ON the Recorded Cash card still announces whether any cash flow has             ever been recorded. Its `detail:` must not branch on `transactions.isEmpty`.
            """
        )
    }

    // MARK: - Existence: why a list is empty

    /// Fails if Privacy Mode lets the transaction list say **which kind** of empty it is.
    ///
    /// The card drew "No transactions found" when the ledger had never held anything and "No
    /// transactions match these filters" when it had — and every filter that produces the second
    /// state is a control in the row directly above it. Walk the type, period and search controls
    /// with Privacy Mode on and the pair maps out which windows and categories hold records, with
    /// every amount on screen already `••••`. That is the probe the net-worth card
    /// (`DashboardView.swift:202-205`) and the Sankey diagram (`SankeyDiagramView.swift:45-53`)
    /// were both changed to refuse.
    ///
    /// The two fixtures are the two kinds of empty: nothing recorded at all, and one transaction
    /// dated outside the default 30-day period filter. Under Privacy Mode the card must not be
    /// able to tell them apart.
    ///
    /// It renders `CashFlowView(initialTab: .transactions)` because the tab is `@State`: setting
    /// the UIKit segmented control's `selectedSegmentIndex` and sending `.valueChanged` moves the
    /// pill and leaves the SwiftUI binding untouched, so the list is unreachable from outside
    /// without that parameter (measured before adding it, not assumed).
    func testPrivacyModeConcealsWhyTheTransactionListIsEmpty() throws {
        let nothingRecorded = FinancialData()
        func filteredOut(_ n: Int) -> FinancialData {
            FinancialData(transactions: (0..<n).map { i in
                WealthCompassMobile.Transaction(
                    type: .expense, category: "Food", amount: Decimal(42 + i), description: "old\(i)",
                    date: Date().addingTimeInterval(-86_400 * Double(400 + i)), currency: .eur
                )
            })
        }

        func render(_ data: FinancialData, privacy: Bool, cropTop: CGFloat = 0) -> Data {
            renderScreen(
                { store, settings in
                    CashFlowView(initialTab: .transactions)
                        .environmentObject(store)
                        .environmentObject(settings)
                },
                data: data, privacyMode: privacy, height: 900, cropTop: cropTop
            )
        }

        let concealedNothing = render(nothingRecorded, privacy: true)
        let concealedNothingAgain = render(nothingRecorded, privacy: true)
        let concealedFiltered = render(filteredOut(1), privacy: true)

        XCTAssertGreaterThan(
            concealedNothing.count, 50_000,
            "captured \(concealedNothing.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedNothing), digest(concealedNothingAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )

        // The control, in three parts, because a whole-screen comparison could not do this job.
        //
        // The two fixtures also differ in `transactionHeader`'s "Showing 0 of 1" row: it is drawn
        // only when `totalCount > 0`, so it is present for one fixture and absent for the other,
        // and it is *four inches above* the card's empty state. A single whole-screen
        // `XCTAssertNotEqual` was therefore satisfied by that row alone — this test passed every
        // one of its own controls at 300pt, with the privacy gate deleted from `CashFlowView`,
        // while the thing it exists to check was off-screen. The row cannot move in the concealed
        // comparison (Privacy Mode draws `Showing •••• of ••••` either way), so it propped the
        // control up and asserted nothing.
        //
        // So the control is cropped below that row and pinned from both sides. 300pt is measured,
        // not guessed: at 260 the two `filteredOut` renders still differ, at 300 they do not.
        let headerBand: CGFloat = 300
        let filteredOneCropped = render(filteredOut(1), privacy: false, cropTop: headerBand)

        XCTAssertNotEqual(
            digest(render(filteredOut(1), privacy: false)), digest(render(filteredOut(2), privacy: false)),
            """
            One old transaction and two rendered the same full screen, so the "Showing 0 of N" row             is not on screen and the crop below proves nothing about it.
            """
        )
        XCTAssertGreaterThan(
            filteredOneCropped.count, 10_000,
            "the cropped capture is \(filteredOneCropped.count) bytes, so the crop left nothing to compare"
        )
        XCTAssertEqual(
            digest(filteredOneCropped), digest(render(filteredOut(2), privacy: false, cropTop: headerBand)),
            """
            Below \(Int(headerBand))pt, one old transaction and two still render differently — so the             crop has not excluded the "Showing 0 of N" row after all, and the control below is back             to being satisfied by a row that cannot move under Privacy Mode.
            """
        )
        XCTAssertNotEqual(
            digest(render(nothingRecorded, privacy: false, cropTop: headerBand)), digest(filteredOneCropped),
            """
            With Privacy Mode OFF the two kinds of empty render identically below \(Int(headerBand))pt.             The card's empty state is the only thing that can differ there, so either it is out of             the viewport or the fixture no longer produces two states — and the assertion below can             no longer fail.
            """
        )

        XCTAssertEqual(
            digest(concealedNothing), digest(concealedFiltered),
            """
            With Privacy Mode ON the card still distinguishes "you have never recorded a             transaction" from "you have, just not these" — so a bystander can vary the filters above             it and map what exists. Both empty arms have to produce the same output under Privacy             Mode; gating only one leaves the other as the tell.
            """
        )
    }

    // MARK: - Existence: announcements and fallbacks

    /// Fails if Privacy Mode lets the Dashboard's onboarding card announce **an empty account**.
    ///
    /// The card is gated on `isCompletelyEmpty` — no transactions, no positions, no holdings, no
    /// liabilities — so its presence alone tells a bystander that this person has no financial data
    /// at all, on a page where every figure is already `••••`. There is no value in it to mask; the
    /// slot is the signal, so the slot goes.
    ///
    /// **Why nothing but the card can move here — and it is not the height.** This comment used to
    /// say "700pt on purpose. At that height the Position grid is below the fold — measured". That
    /// is wrong, and measuring it says so: at 700pt the grid's *first row* is on screen, low in the
    /// viewport. Two fixtures differing by one investment render differently at 700pt even cropped
    /// to the last 50pt, so the Investments card and its caption are inside the frame.
    ///
    /// What actually holds the test up is that under Privacy Mode every caption in that grid is a
    /// fixed phrase rather than a count, and every figure is `••••` — so the visible part of the
    /// grid cannot move for any fixture. (The Liabilities card, the one place these two fixtures
    /// differ in count, does happen to sit below the fold at 700pt; that is a coincidence of layout
    /// and nothing here should be read as relying on it.) The height buys nothing this test needs;
    /// it only keeps the capture small.
    func testPrivacyModeHidesTheDashboardOnboardingCard() throws {
        let empty = FinancialData()
        let oneLiability = FinancialData(liabilities: [
            Liability(name: "Loan", currentBalance: 1_000, currency: .eur)
        ])

        func render(_ data: FinancialData, privacy: Bool) -> Data {
            renderScreen(
                { store, settings in
                    DashboardView(selectedTab: .constant(.dashboard))
                        .environmentObject(store)
                        .environmentObject(settings)
                },
                data: data, privacyMode: privacy, height: 700
            )
        }

        let concealedEmpty = render(empty, privacy: true)
        let concealedEmptyAgain = render(empty, privacy: true)
        let concealedOne = render(oneLiability, privacy: true)

        XCTAssertGreaterThan(
            concealedEmpty.count, 50_000,
            "captured \(concealedEmpty.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedEmpty), digest(concealedEmptyAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )
        XCTAssertNotEqual(
            digest(render(empty, privacy: false)), digest(render(oneLiability, privacy: false)),
            """
            With Privacy Mode OFF the Dashboard rendered identically with an empty account and with             a liability, so the onboarding card is no longer drawn at all and the assertion below             cannot fail.
            """
        )
        XCTAssertEqual(
            digest(concealedEmpty), digest(concealedOne),
            """
            With Privacy Mode ON the Dashboard still shows the onboarding card, whose only entry             condition is that this person has no financial data whatsoever. Gate it on             `!settings.isPrivacyMode` — there is no value here to redact, only a slot to remove.
            """
        )
    }

    /// Fails if the Investments summary still says **"Never"** while Privacy Mode is on.
    ///
    /// The Status card's title already redacts its sector count to `••••`; its value then read
    /// "Never" whenever the portfolio was empty and an exact timestamp whenever it was not — the
    /// same fact, in the same card, one line apart. Tokenised rather than hidden: the card is drawn
    /// in both states and only its value moves.
    ///
    /// This is the one screen where a whole-view comparison works, because the Investments tab
    /// opens on Overview: a summary grid whose every figure redacts, and three allocation rings
    /// that draw a cover. The position list lives on the other tab.
    func testPrivacyModeConcealsWhenThePortfolioWasLastUpdated() throws {
        func render(_ data: FinancialData, privacy: Bool) -> Data {
            renderScreen(
                { store, settings in
                    InvestmentsView()
                        .environmentObject(store)
                        .environmentObject(settings)
                },
                data: data, privacyMode: privacy, height: 1_400
            )
        }

        let concealedEmpty = render(FinancialData(), privacy: true)
        let concealedEmptyAgain = render(FinancialData(), privacy: true)
        let concealedOne = render(records(1), privacy: true)

        XCTAssertGreaterThan(
            concealedEmpty.count, 50_000,
            "captured \(concealedEmpty.count) bytes, so the window drew nothing — every assertion below is vacuous"
        )
        XCTAssertEqual(
            digest(concealedEmpty), digest(concealedEmptyAgain),
            "the same state rendered twice produced different pixels — the instrument is too unstable to conclude anything from"
        )
        XCTAssertNotEqual(
            digest(render(FinancialData(), privacy: false)), digest(render(records(1), privacy: false)),
            """
            With Privacy Mode OFF the Investments overview rendered identically with and without a             position, so it is no longer reading the portfolio and the assertion below cannot fail.
            """
        )
        XCTAssertEqual(
            digest(concealedEmpty), digest(concealedOne),
            """
            With Privacy Mode ON the Investments overview still moves with the portfolio. The Status             card is the one figure left: `latestUpdate.map { settings.date($0) } ?? "Never"` says             whether anything is held, and the populated arm prints a real timestamp besides.
            """
        )
    }

    // MARK: - Existence: what the fixed captions cost

    /// Fails if a caption Privacy Mode substitutes for a count is left untranslated in any locale.
    ///
    /// `65bf189` replaced `%lld positions` / `%lld holdings` / `%lld liabilities` — translated in
    /// all 34 locales — with three fixed phrases that were not, and shipped it. A Polish reader
    /// with Privacy Mode on then read "Stocks, ETFs, and more" and "Tracked assets" in English
    /// beside a translated "Ile jesteś winien", on one grid, where all three used to be Polish.
    /// Privacy Mode is not supposed to cost the reader their language.
    ///
    /// It resolves through `AppLocalization.string(_:appLanguage:)`, which is the app's own
    /// lookup, against the built bundle rather than the catalog source — so it fails on a
    /// translation that exists in `.xcstrings` but never reaches an `.lproj`. Equality with the
    /// English source is the tell: no correct translation of any of these three is the English
    /// string (checked against all 34), so a match means the lookup fell through.
    func testEveryCaptionPrivacyModeSubstitutesForACountIsTranslated() throws {
        // The Position grid's three privacy captions, on both platforms:
        // `DashboardView.positionSection` and `MacDashboardView`. The first two are also the
        // captions `InvestmentsView.swift:107` and `CryptoView.swift:104` print with Privacy Mode
        // off, so this covers those too.
        let captions = ["Stocks, ETFs, and more", "Tracked assets", "What you owe"]
        let languages = Bundle.main.localizations.filter { $0 != "en" && $0 != "Base" }

        XCTAssertGreaterThanOrEqual(
            languages.count, 34,
            "the bundle reports \(languages.count) non-English localizations, so this test is no longer sweeping them all"
        )

        for language in languages.sorted() {
            for caption in captions {
                let resolved = AppLocalization.string(
                    String.LocalizationValue(stringLiteral: caption), appLanguage: language
                )
                XCTAssertNotEqual(
                    resolved, caption,
                    """
                    `\(caption)` resolves to the English source under `\(language)`, so Privacy                     Mode drops that reader out of their own language mid-grid. Add the locale to                     the key in `Localizable.xcstrings`.
                    """
                )
            }
        }
    }

    // MARK: - Existence: the lock screen

    /// The platform prefix the iOS service is configured with
    /// (`RecurringTransactionNotificationService.shared`). macOS uses
    /// `wealth-compass-mac-recurring-`; the prefix is a constructor argument, so a test can pass
    /// either and the builder is the same code on both.
    private static let reminderIdentifierPrefix = "wealth-compass-recurring-"

    /// Fails if Privacy Mode lets a recurring reminder describe the schedule **on the lock screen**.
    ///
    /// Every other disclosure in this file needs a bystander holding the device already unlocked.
    /// This one did not: the reminder posted `content.title = "Recurring Expense due"` and
    /// `content.body = "Rent is scheduled. …"`, so a phone lying face-up on a desk published the
    /// category and the type of a schedule to anyone walking past. The amount was already redacted,
    /// which is what hid the rest — the flag was called `showAmounts` and it only reached the body's
    /// figure, while the title named the type on its own, outside the branch entirely.
    ///
    /// The two fixtures share no field a notification could read: different type, category,
    /// description, amount, currency and frequency.
    ///
    /// It asserts on the `UNNotificationRequest` the builder returns, not on a
    /// `UNMutableNotificationContent`, and that is what gives it reach. The earlier version called
    /// `RecurringNotificationService.content(for:…)` and compared the object it got back — but that
    /// object is a **class** instance, and `sync` went on holding a reference to it. Injecting
    ///
    ///     content.threadIdentifier = schedule.category
    ///     content.subtitle = schedule.description
    ///
    /// into `sync` one line after the builder call left the suite at 297 passed / 0 failed, on
    /// exactly the two fields the previous doc comment named as the ones that "would each carry the
    /// same disclosure if a later change started setting them from `schedule`". A request's
    /// `content` is an immutable copy taken at construction, so a request is the last thing that can
    /// still change and the first thing that cannot — which makes it the right thing to assert on.
    ///
    /// **Which** request, though, is the second half of the lesson, and it cost a second regression.
    /// The version that shipped with `866b3c7` asked `request(for:…)` for both branches. One commit
    /// later `5265c96` moved the Privacy Mode production path off that function — `requests(for:…)`
    /// now sends the hidden case to `coalescedRequest`/`hiddenContent` and only ever calls
    /// `request(for:…)` with `showDetails: true` — so the assertions below were re-running the
    /// *detailed* builder in a hidden costume and the branch a locked phone actually uses was
    /// covered by nothing. Measured: injecting
    ///
    ///     leak.subtitle = schedule.description
    ///     leak.threadIdentifier = schedule.category
    ///
    /// into `coalescedRequest`'s payload left the suite at **302 passed / 0 failed**. The hidden
    /// half now goes through `requests(for:…)`, which is the one function `sync` calls and therefore
    /// the last thing that is still "what the notification centre gets" no matter how the branches
    /// are rearranged underneath it.
    /// `testEveryReminderReachingTheNotificationCentreComesFromOneBuilder` is what keeps that true.
    ///
    /// The payload comparison is the whole archived object rather than a list of field names, so a
    /// field this test has never heard of still fails it.
    ///
    /// The builder is `nonisolated static` because `sync` returns early unless
    /// `UNUserNotificationCenter` reports an authorization the test host is never granted — measured
    /// on this host: `authorizationStatus.rawValue == 0` (`.notDetermined`), `center.add` retains 0
    /// of 5 requests handed to it, and `deliveredNotifications()` is permanently empty. So the loop
    /// in `sync` that adds these never runs here, and nothing about delivery can be asserted at all.
    /// Both platforms reach this same builder (`MacRecurringTransactionNotificationService` is an
    /// `enum` in `macOS/MacAppDelegate.swift` holding a configured instance of the same actor), so
    /// this covers the macOS reminder too — the one place in this audit where it does.
    func testPrivacyModeStopsTheRecurringReminderDescribingTheSchedule() throws {
        let rent = RecurringTransaction(
            type: .expense, category: "Rent", amount: 1_450, description: "flat",
            startDate: Date(), frequency: .monthly, nextDueDate: Date().addingTimeInterval(86_400),
            endDate: nil, currency: .eur
        )
        let salary = RecurringTransaction(
            type: .income, category: "Salary", amount: 3_800, description: "payroll",
            startDate: Date(), frequency: .weekly, nextDueDate: Date().addingTimeInterval(172_800),
            endDate: nil, currency: .usd
        )

        func request(_ schedule: RecurringTransaction, showDetails: Bool) -> UNNotificationRequest {
            RecurringNotificationService.request(
                for: schedule,
                convertedAmount: schedule.amount,
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        /// Exactly what `sync` hands to `center.add`, hidden branch included.
        func posted(_ schedules: [RecurringTransaction], showDetails: Bool) -> [UNNotificationRequest] {
            RecurringNotificationService.requests(
                for: schedules,
                convertedAmounts: Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }),
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        /// The whole payload, byte for byte, minus the one field that is meant to differ.
        ///
        /// `UNNotificationContent` is `NSSecureCoding`, so archiving it compares every property the
        /// class has — including any a later edit or a later OS adds, which a hand-written list of
        /// field names cannot. `userInfo` is cleared first: it carries the schedule's UUID by
        /// design, it is app-private, and it is never drawn.
        func rendered(_ request: UNNotificationRequest) throws -> Data {
            let payload = try XCTUnwrap(request.content.mutableCopy() as? UNMutableNotificationContent)
            payload.userInfo = [:]
            return try NSKeyedArchiver.archivedData(withRootObject: payload, requiringSecureCoding: true)
        }

        let openRent = request(rent, showDetails: true)
        let openSalary = request(salary, showDetails: true)
        XCTAssertNotEqual(
            try rendered(openRent), try rendered(openSalary),
            """
            With Privacy Mode OFF two schedules that share no field produced the same payload, so \
            the builder is no longer reading the schedule at all and the assertions below cannot \
            fail.
            """
        )
        XCTAssertFalse(
            openRent.content.title.isEmpty || openRent.content.body.isEmpty,
            "the notification rendered no text at all, so comparing it proves nothing"
        )

        // Through `requests(for:…)`, not `request(for:…)`: under Privacy Mode production never
        // reaches the latter, so asserting on it covers the wrong branch. See the doc comment.
        let hiddenRent = try XCTUnwrap(posted([rent], showDetails: false).first)
        let hiddenSalary = try XCTUnwrap(posted([salary], showDetails: false).first)

        XCTAssertEqual(
            try rendered(hiddenRent), try rendered(try XCTUnwrap(posted([rent], showDetails: false).first)),
            """
            One schedule built twice archived to two different payloads, so the comparison below is \
            measuring the archiver and not the notification. Fall back to asserting named fields.
            """
        )
        XCTAssertEqual(
            hiddenRent.content.title, hiddenSalary.content.title,
            """
            With Privacy Mode ON `content.title` still names the *type* — "Recurring Expense due" \
            against "Recurring Income due" — on a surface that needs no unlock. The title used to be \
            assigned outside the branch, so redacting the body alone left it standing.
            """
        )
        XCTAssertEqual(
            hiddenRent.content.body, hiddenSalary.content.body,
            """
            With Privacy Mode ON `content.body` still names the category, so a locked phone spells \
            out "Rent is scheduled" to anyone walking past it.
            """
        )
        XCTAssertEqual(
            try rendered(hiddenRent), try rendered(hiddenSalary),
            """
            With Privacy Mode ON some rendered field other than title/body moves with the schedule. \
            This is the entire archived payload, so it does not matter which field it is, nor where \
            in the pipeline it was set — a `threadIdentifier` of "expense" publishes the type \
            exactly as the title used to, and a `subtitle` of the description publishes more than \
            the title ever did.
            """
        )
        XCTAssertEqual(
            hiddenRent.content.attachments.count, 0,
            "an attachment is drawn on the lock screen; nothing here may add one under Privacy Mode"
        )
        XCTAssertFalse(
            hiddenRent.content.body.contains("1,450") || hiddenRent.content.body.contains("1450")
                || hiddenRent.content.title.contains("1,450"),
            "the amount is back in the reminder"
        )

        // The pair above is two sets of one. A real sync hands over a whole batch at once, and the
        // hidden branch builds those from a fire *moment* rather than from a schedule — so this
        // asks the question the pair cannot: across schedules that agree on nothing and fall on
        // different days, is there exactly one payload in the whole batch?
        let crowd = [rent, salary] + (1...4).map { offset in
            RecurringTransaction(
                type: offset.isMultiple(of: 2) ? .income : .expense,
                category: "Category \(offset)", amount: Decimal(offset * 97),
                description: "note \(offset)", startDate: Date(),
                frequency: offset.isMultiple(of: 2) ? .weekly : .yearly,
                nextDueDate: Date().addingTimeInterval(Double(offset) * 86_400 + 3_600),
                endDate: nil, currency: offset.isMultiple(of: 2) ? .gbp : .chf
            )
        }
        var batch: Set<Data> = []
        for request in posted(crowd, showDetails: false) { batch.insert(try rendered(request)) }
        XCTAssertEqual(
            batch.count, 1,
            """
            Privacy Mode produced \(batch.count) distinct payloads for \(crowd.count) schedules, so \
            something a lock screen draws still moves with the schedule — or with which day it \
            falls on, which is the same disclosure one step removed.
            """
        )
        XCTAssertGreaterThan(
            posted(crowd, showDetails: false).count, 1,
            "the batch collapsed to a single request, so the comparison above had nothing to compare"
        )
    }

    /// Pins the two things a reminder carries that are *not* payload: the request `identifier` and
    /// the `trigger`.
    ///
    /// The privacy test above deliberately does not require these to match across schedules —
    /// they must not. The identifier is how `cancel(scheduleID:)` names one reminder, and a trigger
    /// that did not move with the due date would be no reminder at all. Neither is drawn on a lock
    /// screen. What they need is to be *right*, and until the builder returned a whole request no
    /// test could see either of them: `sync` built both inline, below an authorization guard the
    /// test host never clears.
    ///
    /// WC-L5 is the substance here. A date-only or imported schedule carries a midnight time, which
    /// would fire the reminder at 00:00; those are pinned to 09:00 local, and a schedule with a real
    /// time of day keeps it.
    func testRecurringReminderCarriesItsScheduleIdentifierAndFireTime() throws {
        let calendar = Calendar.current
        // Mid-June, so no zone shifts its clocks across the midnight this depends on.
        let dateOnly = try XCTUnwrap(calendar.date(from: DateComponents(year: 2031, month: 6, day: 15)))
        let evening = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2031, month: 6, day: 15, hour: 18, minute: 30))
        )

        func schedule(dueAt due: Date) -> RecurringTransaction {
            RecurringTransaction(
                type: .expense, category: "Rent", amount: 1_450, description: "flat",
                startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
            )
        }
        func trigger(for schedule: RecurringTransaction, prefix: String) throws -> UNCalendarNotificationTrigger {
            let request = RecurringNotificationService.request(
                for: schedule, convertedAmount: nil, currencyCode: "EUR",
                showDetails: false, appLanguage: nil, identifierPrefix: prefix
            )
            return try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        }

        let imported = schedule(dueAt: dateOnly)
        let pinned = try trigger(for: imported, prefix: Self.reminderIdentifierPrefix).dateComponents
        XCTAssertEqual(
            [pinned.year, pinned.month, pinned.day, pinned.hour, pinned.minute],
            [2031, 6, 15, 9, 0],
            """
            WC-L5: a date-only schedule carries a midnight time and has to be pinned to 09:00 local, \
            or every imported schedule wakes the reader at 00:00. Got \
            \(String(describing: pinned.hour)):\(String(describing: pinned.minute)) on \
            \(String(describing: pinned.year))-\(String(describing: pinned.month))-\(String(describing: pinned.day)).
            """
        )

        let timed = schedule(dueAt: evening)
        let kept = try trigger(for: timed, prefix: Self.reminderIdentifierPrefix).dateComponents
        XCTAssertEqual(
            [kept.year, kept.month, kept.day, kept.hour, kept.minute], [2031, 6, 15, 18, 30],
            "a schedule with a real time of day had its own time overwritten, so it fires at the wrong hour"
        )

        for prefix in [Self.reminderIdentifierPrefix, "wealth-compass-mac-recurring-"] {
            let request = RecurringNotificationService.request(
                for: imported, convertedAmount: nil, currencyCode: "EUR",
                showDetails: false, appLanguage: nil, identifierPrefix: prefix
            )
            XCTAssertEqual(
                request.identifier, "\(prefix)\(imported.id.uuidString)",
                """
                The reminder is filed under an identifier that is not "<platform prefix><schedule \
                UUID>". `sync` tears down by prefix and `cancel(scheduleID:)` rebuilds this exact \
                string, so a reminder filed under anything else can never be cancelled.
                """
            )
            XCTAssertEqual(
                request.identifier,
                RecurringNotificationService.notificationIdentifier(for: imported.id, prefix: prefix),
                "the builder and `cancel(scheduleID:)` no longer spell the identifier the same way"
            )
        }
    }

    /// Fails if a teardown path in `RecurringNotificationService` clears the reminders still waiting
    /// to fire and leaves the ones already on the lock screen.
    ///
    /// Two versions of the same mistake shipped together. `sync` removed *pending* requests only, so
    /// turning Privacy Mode **on** rewrote every reminder that had not fired yet and left the one
    /// already published — "Recurring Expense due / Rent: €1.450,00" — exactly where it was. That is
    /// the normal case rather than the corner one: people turn Privacy Mode on *because* schedules
    /// exist, so a fired reminder is precisely what is on screen at that moment. And `cancelAll`,
    /// the erase-everything path, *did* call `removeDeliveredNotifications` — with a list built by
    /// filtering `pendingNotificationRequests()`. A delivered notification is by definition no
    /// longer pending, so its identifier could never appear in that list and the call reached
    /// nothing; a factory reset left the schedules describing themselves on a wiped device.
    ///
    /// A source lint, because none of it is observable from here. The test host reports
    /// `authorizationStatus == .notDetermined` and `UNUserNotificationCenter.add` retains none of
    /// the requests handed to it, so `deliveredNotifications()` is permanently empty and no
    /// assertion against the real notification centre can tell the fixed code from the broken code.
    /// What this pins instead is the shape that allowed both bugs: a body that reaches for one of
    /// the two queues and not the other. It reads the stripped `code` view, so a doc comment naming
    /// these APIs — the service's own, or this one — cannot satisfy it.
    ///
    /// `cancel(scheduleID:)` passes and always did: it builds its single identifier from the
    /// schedule's UUID instead of enumerating a queue, so the second rule never fires on it, and it
    /// already called both removals.
    func testRecurringReminderTeardownClearsDeliveredBannersToo() throws {
        let code = try Self.notificationServiceCode()

        // Each rule reads "a body that reaches for this must also reach for that".
        let rules: [(reaches: String, mustAlsoReach: String, because: String)] = [
            (
                "removePendingNotificationRequests", "removeDeliveredNotifications",
                "empties the pending queue and leaves the banners already on the lock screen"
            ),
            (
                "pendingNotificationRequests()", "deliveredNotifications()",
                "enumerates the pending queue alone, so no identifier list it builds can name a delivered banner"
            ),
        ]

        let functions = try Self.functionBodies(in: code)
        XCTAssertGreaterThanOrEqual(
            functions.count, 5,
            "found \(functions.count) function(s) in RecurringNotificationService.swift — the sweep has lost the file"
        )

        var offenders: [String] = []
        var reaches = 0
        for current in functions {
            for rule in rules where current.body.contains(rule.reaches) {
                reaches += 1
                guard !current.body.contains(rule.mustAlsoReach) else { continue }
                offenders.append(
                    "  \(current.name)() at :\(current.line) calls `\(rule.reaches)` "
                        + "without `\(rule.mustAlsoReach)` — it \(rule.because)"
                )
            }
        }

        XCTAssertGreaterThanOrEqual(
            reaches, 2,
            "\(reaches) teardown call(s) matched; the sweep is no longer reading this service at all"
        )
        XCTAssertEqual(
            offenders, [],
            """
            \(offenders.count) teardown path(s) touch one notification queue and not the other, which \
            is how a fired reminder survived both a Privacy Mode toggle and a factory reset:
            \(offenders.joined(separator: "\n"))
            """
        )

        // The erase path stays all-or-nothing. `sync`'s teardown is now scoped to the banners no
        // live schedule still supports, which is right for a re-sync and wrong for "erase local
        // data": after an erase there are no schedules to compare against, and a banner kept would
        // be one describing data the user just wiped off a device.
        let eraser = try XCTUnwrap(
            functions.first { $0.name == "cancelAll" },
            "`cancelAll` is gone from RecurringNotificationService — the erase path is unaccounted for"
        )
        XCTAssertTrue(
            eraser.body.contains("clearScheduledReminders()"),
            "cancelAll() no longer routes through the unconditional teardown"
        )
        let unconditional = try XCTUnwrap(functions.first { $0.name == "clearScheduledReminders" })

        // What the erase path removes has to be exactly what `everyReminder` named. Asking for the
        // absence of the literal `staleDelivered` was a check about spelling, and a teardown that
        // caches the schedules in `sync` and keeps the banners still backed by them passes it
        // verbatim — under any name at all, which is what makes a name-based rule the wrong shape.
        let owned = try XCTUnwrap(
            Self.soleCallBinding(of: "Self.everyReminder", in: unconditional.body),
            """
            The erase path no longer takes its identifier list straight from `Self.everyReminder(…)`. \
            Either it builds the list some other way, or something is chained onto the call — and \
            a `.filter` there is all it takes for a factory reset to leave the user's schedules \
            describing themselves on a wiped device, which is the bug 73e3b22 fixed.
            """
        )
        for removal in ["removePendingNotificationRequests", "removeDeliveredNotifications"] {
            XCTAssertTrue(
                Self.squeezed(unconditional.body).contains("\(removal)(withIdentifiers: \(owned))"),
                """
                clearScheduledReminders() calls `\(removal)` with something other than the whole \
                list `everyReminder` returned, so the erase path is no longer all-or-nothing.
                """
            )
        }
        XCTAssertEqual(
            unconditional.body.components(separatedBy: owned).count - 1, 3,
            """
            `\(owned)` is bound once and read twice; it appears a different number of times, so \
            something in clearScheduledReminders() is narrowing or rebinding the list on its way to \
            the two removals.
            """
        )
    }

    /// Fails if tearing down after one schedule changes takes the other schedules' unread banners
    /// with it.
    ///
    /// `73e3b22` fixed a real bug — a fired reminder survived turning Privacy Mode on, and survived
    /// a factory reset — by clearing *every* delivered banner carrying the platform prefix on every
    /// `sync`. Its justification was that "`sync` is never called speculatively", so every call
    /// already meant the banner had stopped describing the data. It is called speculatively, by
    /// three paths (see `staleDelivered`'s doc comment), and the cost was that adding a "Gym"
    /// reminder at 20:00 silently dismissed an unread "Rent: €1.450,00" banner from 09:00.
    ///
    /// The rule now is literal: rebuild what each live schedule's reminder *would* say, and keep a
    /// delivered banner if and only if one of those is filed under the same identifier and says the
    /// same thing. Everything below is a consequence of that one sentence, asserted separately so a
    /// weaker rule that happens to satisfy one case still fails the others.
    ///
    /// `staleDelivered` is a pure function over plain values because nothing else is available: the
    /// test host reports `authorizationStatus.rawValue == 0`, `center.add` retains 0 of 5 requests,
    /// and `deliveredNotifications()` is permanently empty, so no assertion here observes a real
    /// queue. What is checked is the decision the teardown makes, not that the system honours it.
    /// New coverage in the same sense `requests(for:…)` was — the function it exercises did not
    /// exist to call before the fix. Measured against a `staleDelivered` whose body is reverted to
    /// `73e3b22`'s rule (`delivered.filter { $0.identifier.hasPrefix(identifierPrefix) }`), this
    /// test fails and the rest of the suite does not.
    func testTearingDownAfterOneScheduleKeepsTheOtherBanners() throws {
        let calendar = Calendar.current
        let nineToday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2031, month: 6, day: 15, hour: 9))
        )
        let eightTonight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2031, month: 6, day: 15, hour: 20))
        )

        func schedule(
            _ category: String, _ amount: Decimal, dueAt due: Date
        ) -> RecurringTransaction {
            RecurringTransaction(
                type: .expense, category: category, amount: amount, description: category,
                startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
            )
        }
        var rent = schedule("Rent", 1_450, dueAt: nineToday)
        let gym = schedule("Gym", 40, dueAt: eightTonight)

        /// The banner `rent` put on the lock screen at 09:00, built by the service itself so the
        /// fixture cannot drift from what production would have delivered.
        func banner(
            for schedule: RecurringTransaction, showDetails: Bool = true
        ) throws -> RecurringNotificationService.DeliveredReminder {
            let requests = RecurringNotificationService.requests(
                for: [schedule],
                convertedAmounts: [schedule.id: schedule.amount],
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
            return RecurringNotificationService.DeliveredReminder(try XCTUnwrap(requests.first))
        }
        func stale(
            _ delivered: [RecurringNotificationService.DeliveredReminder],
            _ schedules: [RecurringTransaction],
            showDetails: Bool = true,
            currencyCode: String = "EUR"
        ) -> [String] {
            RecurringNotificationService.staleDelivered(
                delivered,
                schedules: schedules,
                convertedAmounts: Dictionary(
                    uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }
                ),
                currencyCode: currencyCode,
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        let rentBanner = try banner(for: rent)
        XCTAssertFalse(
            rentBanner.body.isEmpty,
            "the fixture banner says nothing, so every comparison below is between two blanks"
        )

        // The bug, stated as a test: the Gym schedule is added and Rent's unread banner survives.
        XCTAssertEqual(
            stale([rentBanner], [rent, gym]), [],
            """
            Adding an unrelated schedule took down an unread banner that still describes its own \
            schedule exactly. That is a reminder the reader never saw, dismissed by an edit to \
            something else — and a silent CloudKit push, a 30-second timer tick that advanced a \
            different schedule's nextDueDate, or a backup import all reach this same teardown while \
            the phone is locked.
            """
        )
        // Nothing at all changed: the same schedules, re-synced.
        XCTAssertEqual(stale([rentBanner], [rent]), [], "a bare re-sync dismissed the banner")

        // Deleted.
        XCTAssertEqual(
            stale([rentBanner], [gym]), [rentBanner.identifier],
            "the schedule is gone and its banner stayed on the lock screen"
        )

        // The figure moved, so the banner is now quoting a number the ledger no longer holds.
        var repriced = rent
        repriced.amount = 1_500
        XCTAssertEqual(
            stale([rentBanner], [repriced, gym]), [rentBanner.identifier],
            "the amount changed and the banner still shows the old one"
        )

        // The display currency moved. Same schedule, different sentence.
        XCTAssertEqual(
            stale([rentBanner], [rent, gym], currencyCode: "USD"), [rentBanner.identifier],
            "the display currency changed and the banner still shows the old denomination"
        )

        // 73e3b22's own fix, which must not regress: turning Privacy Mode on takes down every
        // detailed banner, because the hidden branch files under `due-<moment>` and can never
        // match a banner filed under a schedule's UUID.
        XCTAssertEqual(
            stale([rentBanner], [rent, gym], showDetails: false), [rentBanner.identifier],
            """
            Privacy Mode was switched on and a banner spelling out "Rent: €1.450,00" stayed on the \
            lock screen. This is the regression 73e3b22 fixed; scoping the teardown must not undo it.
            """
        )
        // And the other way: a hidden banner does not survive Privacy Mode being switched off.
        let hiddenBanner = try banner(for: rent, showDetails: false)
        XCTAssertEqual(
            stale([hiddenBanner], [rent, gym], showDetails: false), [],
            "a coalesced banner was taken down while its own moment still has a schedule behind it"
        )
        XCTAssertEqual(
            stale([hiddenBanner], [rent, gym]), [hiddenBanner.identifier],
            "Privacy Mode was switched off and the coalesced banner was left standing"
        )

        // A coalesced banner stands for every schedule due at that moment, so it outlives the
        // deletion of one of them and goes only with the last.
        let alsoNine = schedule("Insurance", 90, dueAt: nineToday)
        XCTAssertEqual(
            try banner(for: alsoNine, showDetails: false).identifier, hiddenBanner.identifier,
            "the two schedules are due at the same moment and must coalesce, or the case below is not the case"
        )
        XCTAssertEqual(
            stale([hiddenBanner], [alsoNine, gym], showDetails: false), [],
            "deleting one of two schedules due at the same moment took down the banner for both"
        )
        XCTAssertEqual(
            stale([hiddenBanner], [gym], showDetails: false), [hiddenBanner.identifier],
            "the last schedule behind a coalesced banner went and the banner stayed"
        )

        // A schedule that has stopped producing reminders at all.
        for (name, mutate) in [
            ("completed", { (s: inout RecurringTransaction) in s.completedAt = nineToday }),
            ("deactivated", { (s: inout RecurringTransaction) in s.isActive = false }),
            ("silenced", { (s: inout RecurringTransaction) in s.notificationsEnabled = false }),
            ("ended", { (s: inout RecurringTransaction) in s.endDate = nineToday.addingTimeInterval(-86_400) }),
        ] {
            var changed = rent
            mutate(&changed)
            XCTAssertEqual(
                stale([rentBanner], [changed, gym]), [rentBanner.identifier],
                "a \(name) schedule left its banner on the lock screen"
            )
        }

        // Never touch what this service does not own — another app's banner, or the other
        // platform's, both of which `deliveredNotifications()` can hand back.
        let foreign = RecurringNotificationService.DeliveredReminder(
            identifier: "wealth-compass-mac-recurring-\(UUID().uuidString)",
            title: "Recurring Expense due", body: "Rent: €1.450,00"
        )
        XCTAssertEqual(
            stale([foreign, rentBanner], [rent, gym]), [],
            "the teardown reached a banner filed under another prefix"
        )
        XCTAssertEqual(
            stale([foreign], []), [],
            "the teardown reached another prefix's banner even with no schedules of its own"
        )

        // The cap is a pending-request budget, not a statement about which banners are accurate.
        let limit = RecurringNotificationService.pendingRequestLimit
        let crowd = try (0..<(limit + 5)).map { offset in
            schedule("c\(offset)", 100, dueAt: try XCTUnwrap(
                calendar.date(byAdding: .day, value: offset, to: nineToday)
            ))
        }
        let last = try XCTUnwrap(crowd.last)
        XCTAssertEqual(
            stale([try banner(for: last)], crowd), [],
            """
            A banner belonging to the \(limit + 5)th schedule was read as one nothing stands behind, \
            because the accuracy check inherited `sync`'s \(limit)-request cap. The cap is about \
            what may be posted, not about which schedules exist.
            """
        )

        // The rent fixture is used unmutated throughout; this pins that.
        rent.updatedAt = nineToday
        XCTAssertEqual(
            stale([rentBanner], [rent, gym]), [],
            "an `updatedAt` bump — what a CloudKit push or a reorder produces — dismissed the banner"
        )
    }

    /// Fails if Privacy Mode takes down a reminder about thirty seconds after it fires.
    ///
    /// The coalesced identifier is derived from the fire moment, and
    /// `processDueRecurringTransactions` **advances** `nextDueDate` the moment a schedule comes due
    /// — writing the array back, which fires `.onChange(of: finance.data.recurringTransactions)` at
    /// `ContentView.swift:110` and re-runs `sync`. The rebuilt set then files the schedule under its
    /// *next* moment, nothing carries the delivered banner's identifier any more, and the teardown
    /// read that as "nothing stands behind this". The 30-second timer reaches it, and so does
    /// `didReceive` → `.recurringTransactionNotificationReceived`, which is the tap the user makes
    /// on the banner itself.
    ///
    /// Measured against HEAD, the two branches disagreed on the same event:
    ///
    /// | state | detailed | Privacy Mode |
    /// | --- | --- | --- |
    /// | schedule advanced to its next occurrence | kept | **removed** |
    /// | advanced, another schedule still due at that moment | — | kept |
    ///
    /// Privacy Mode is the one mode in which the banner is the user's only trace that something
    /// fired, so the branch that dropped it is the branch where dropping it costs most.
    ///
    /// Every date here is in the past on purpose. `staleDelivered` takes `now` with a `Date()`
    /// default and the fixtures never pass it, so this exercises the same defaulted clock production
    /// does — and it means the test compiles unchanged against the pre-fix service, which is what
    /// lets it be run red.
    func testASpentPrivacyModeBannerSurvivesItsScheduleAdvancing() throws {
        let calendar = Calendar.current
        let june = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2020, month: 6, day: 15, hour: 9))
        )
        let july = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2020, month: 7, day: 15, hour: 9))
        )
        // Far enough ahead that no plausible clock reads it as spent.
        let distant = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2099, month: 6, day: 15, hour: 9))
        )

        func schedule(_ category: String, dueAt due: Date) -> RecurringTransaction {
            RecurringTransaction(
                type: .expense, category: category, amount: 1_450, description: category,
                startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
            )
        }
        func banner(
            for schedule: RecurringTransaction, showDetails: Bool
        ) throws -> RecurringNotificationService.DeliveredReminder {
            let requests = RecurringNotificationService.requests(
                for: [schedule],
                convertedAmounts: [schedule.id: schedule.amount],
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
            return RecurringNotificationService.DeliveredReminder(try XCTUnwrap(requests.first))
        }
        func stale(
            _ delivered: [RecurringNotificationService.DeliveredReminder],
            _ schedules: [RecurringTransaction],
            showDetails: Bool
        ) -> [String] {
            RecurringNotificationService.staleDelivered(
                delivered,
                schedules: schedules,
                convertedAmounts: Dictionary(
                    uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }
                ),
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        let rent = schedule("Rent", dueAt: june)
        let hiddenBanner = try banner(for: rent, showDetails: false)
        let detailedBanner = try banner(for: rent, showDetails: true)

        // `processDueRecurringTransactions` recorded June's occurrence and moved the schedule on.
        var advanced = rent
        advanced.nextDueDate = july
        advanced.updatedAt = july

        XCTAssertNotEqual(
            try banner(for: advanced, showDetails: false).identifier, hiddenBanner.identifier,
            """
            The advance did not rename the coalesced identifier, so the case this test is about does \
            not exist and every assertion below is vacuous.
            """
        )
        XCTAssertEqual(
            stale([hiddenBanner], [advanced], showDetails: false), [],
            """
            Under Privacy Mode the app took down its own unread reminder the moment the schedule \
            advanced past the occurrence the reminder was for. The banner had already fired; \
            nothing about it had changed; and it says two constants, so there is nothing in it that \
            could have gone stale. Under Privacy Mode that banner is the only trace the user has \
            that anything was due at all.
            """
        )
        XCTAssertEqual(
            stale([detailedBanner], [advanced], showDetails: true), [],
            "the detailed branch stopped keeping a spent banner, which is the behaviour being matched"
        )

        // Spent is the whole discriminator, so a coalesced banner whose moment is still ahead and
        // which nothing stands behind still goes — that is the case `48c64af` pinned as removable.
        let future = schedule("Rent", dueAt: distant)
        let futureBanner = try banner(for: future, showDetails: false)
        XCTAssertEqual(
            stale([futureBanner], [], showDetails: false), [futureBanner.identifier],
            """
            A coalesced banner naming a moment that has not arrived, with no schedule behind it, was \
            left on the lock screen — so the rule is "keep every hidden banner" rather than "keep a \
            spent one".
            """
        )

        // Nor is this "keep anything filed under `due-`". A payload that describes a schedule is a
        // disclosure whatever it is filed under, and Privacy Mode is exactly when it must go.
        let disguised = RecurringNotificationService.DeliveredReminder(
            identifier: hiddenBanner.identifier,
            title: detailedBanner.title,
            body: detailedBanner.body
        )
        XCTAssertEqual(
            stale([disguised], [advanced], showDetails: false), [disguised.identifier],
            """
            A banner spelling out the schedule survived Privacy Mode because it happened to be filed \
            under a coalesced identifier. The identifier says where a banner sits; the payload is \
            what the lock screen draws.
            """
        )
        // And a `due-` identifier whose stamp is not a moment cannot be judged spent, so it is
        // judged the old way.
        let unparsable = RecurringNotificationService.DeliveredReminder(
            identifier: "\(Self.reminderIdentifierPrefix)due-not-a-moment-at-all",
            title: hiddenBanner.title,
            body: hiddenBanner.body
        )
        XCTAssertEqual(
            stale([unparsable], [advanced], showDetails: false), [unparsable.identifier],
            "an identifier whose stamp does not read back as a moment was treated as spent anyway"
        )

        // 73e3b22's fix, restated for the spent case: turning Privacy Mode on must still take the
        // detailed banner down, spent or not.
        XCTAssertEqual(
            stale([detailedBanner], [advanced], showDetails: false), [detailedBanner.identifier],
            "a spent banner spelling out \"Rent: €1.450,00\" survived Privacy Mode being switched on"
        )
        XCTAssertEqual(
            stale([hiddenBanner], [advanced], showDetails: true), [hiddenBanner.identifier],
            "a spent coalesced banner survived Privacy Mode being switched off"
        )
        // Another platform's spent banner is still none of this service's business.
        let foreign = RecurringNotificationService.DeliveredReminder(
            identifier: "wealth-compass-mac-recurring-due-2020-6-15-9-0",
            title: hiddenBanner.title,
            body: hiddenBanner.body
        )
        XCTAssertEqual(
            stale([foreign], [advanced], showDetails: false), [],
            "the teardown reached a spent banner filed under another prefix"
        )
    }

    /// Fails if the set of ways a spent Privacy Mode banner outlives its schedule changes size.
    ///
    /// `staleDelivered`'s doc comment used to concede one case — "a spent hidden banner whose
    /// schedule was **deleted** after it fired". Deletion is not the way in, it is one of five: the
    /// keep turns on there being no rebuilt entry under the identifier, and every route to that
    /// lands in the same branch. This enumerates them so the concession cannot quietly become six,
    /// and so the doc comment's list is checked rather than asserted.
    ///
    /// None of the five is a leak — the third condition checks the payload is exactly the two
    /// constants `hiddenContent` builds, which is what the last case here is for. What is being
    /// pinned is the *width* of a trade, not its safety.
    func testASpentHiddenBannerIsKeptWhateverSilencedItsSchedule() throws {
        let calendar = Calendar.current
        let due = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2020, month: 6, day: 15, hour: 9))
        )
        let prefix = Self.reminderIdentifierPrefix

        var base = RecurringTransaction(
            type: .expense, category: "Rent", amount: 1_450, description: "flat",
            startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
        )
        base.updatedAt = due

        let banner = RecurringNotificationService.DeliveredReminder(try XCTUnwrap(
            RecurringNotificationService.requests(
                for: [base], convertedAmounts: [:], currencyCode: "EUR", showDetails: false,
                appLanguage: nil, identifierPrefix: prefix
            ).first
        ))
        func stale(
            _ delivered: [RecurringNotificationService.DeliveredReminder],
            _ schedules: [RecurringTransaction]
        ) -> [String] {
            RecurringNotificationService.staleDelivered(
                delivered,
                schedules: schedules,
                convertedAmounts: Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }),
                currencyCode: "EUR",
                showDetails: false,
                appLanguage: nil,
                identifierPrefix: prefix
            )
        }

        // The five routes to "no live schedule rebuilds this identifier".
        var completed = base
        completed.completedAt = due
        var deactivated = base
        deactivated.isActive = false
        var silenced = base
        silenced.notificationsEnabled = false
        var ended = base
        ended.endDate = due.addingTimeInterval(-86_400)

        let cases: [(name: String, schedules: [RecurringTransaction])] = [
            ("deleted", []),
            ("completed", [completed]),
            ("deactivated", [deactivated]),
            ("notifications switched off", [silenced]),
            ("past its endDate", [ended]),
        ]
        for probe in cases {
            XCTAssertEqual(
                stale([banner], probe.schedules), [],
                """
                A spent Privacy Mode banner was taken down because its schedule was \
                \(probe.name). All five routes to "no rebuilt entry under this identifier" are meant \
                to keep it — the banner has already fired, says two constants, and under Privacy \
                Mode is the user's only trace that anything was due. If this is now deliberate, \
                `staleDelivered`'s doc comment lists the five and has to lose one.
                """
            )
        }
        XCTAssertEqual(
            cases.count, 5,
            "the enumeration has changed size; `staleDelivered`'s doc comment names five cases"
        )

        // And no recency bound: `moment <= now` is as true of a stamp from 2001 as of one from a
        // minute ago, so age alone never takes a hidden banner down.
        let ancient = RecurringNotificationService.DeliveredReminder(
            identifier: "\(prefix)due-0",
            title: banner.title,
            subtitle: banner.subtitle,
            body: banner.body
        )
        XCTAssertEqual(
            stale([ancient], []), [],
            "a hidden banner stamped at the reference date was taken down for its age alone"
        )
        // The payload is still the whole of the safety argument, in every one of those cases.
        let disclosing = RecurringNotificationService.DeliveredReminder(
            identifier: banner.identifier,
            title: "Recurring Expense due",
            body: "Rent: €1.450,00"
        )
        XCTAssertEqual(
            stale([disclosing], []), [disclosing.identifier],
            """
            A banner spelling out the schedule was kept by the same branch that keeps the spent \
            hidden ones. The five-case concession is tolerable only because the payload is checked.
            """
        )
    }

    /// Fails if a coalesced identifier is a calendar *rendering* of the fire moment rather than the
    /// moment itself.
    ///
    /// The identifier used to stamp `due-<Y-M-D-H-M>` and read it back with
    /// `Calendar.current.date(from:)` — the calendar and time zone **at read time**, not the ones
    /// that wrote it. A string that has to be interpreted by a calendar names different instants to
    /// different readers, and both consequences were measured with a probe replicating the two
    /// functions verbatim:
    ///
    /// - `due-2026-9-1-9-0` stamped in Tokyo names 2026-09-01T00:00Z; read in London the same string
    ///   names 2026-09-01T08:00Z. Thirty seconds after the banner fires, `moment <= now` flips from
    ///   true to false and `staleDelivered` takes down a banner that has just arrived — `81c2fca`'s
    ///   thirty-second take-down, back again while travelling. Up to ±26 h across the offset range.
    /// - Under a Chinese `Calendar.current` a leap month and the ordinary month of the same number
    ///   render to the same five numbers, so two schedules a leap month apart collided in
    ///   `posted.insert(identifier)` and the second reminder was never posted at all.
    ///
    /// Neither is reachable from this host — `Calendar.current` is what it is, and there is no
    /// supported way to make the test bundle read another one — so what is asserted here is the
    /// property that makes both impossible rather than either symptom: **the stamp is a number of
    /// seconds, so reading it consults no calendar.** A reader with no calendar cannot disagree with
    /// the writer, and two distinct instants cannot share a stamp.
    ///
    /// The last block is the mechanism the leap-month half leans on, pinned because it is Foundation
    /// behaviour this code depends on silently: `dateComponents(_:from:)` fills in `isLeapMonth`
    /// even though `fireComponents` does not ask for it, and `date(from:)` honours it. That is what
    /// makes the *moment* distinct in the case where the five numbers are not.
    func testACoalescedIdentifierNamesAnInstantRatherThanACalendarRendering() throws {
        let calendar = Calendar.current
        let prefix = Self.reminderIdentifierPrefix
        let marker = "\(prefix)due-"

        func schedule(_ category: String, dueAt due: Date) -> RecurringTransaction {
            RecurringTransaction(
                type: .expense, category: category, amount: 1_450, description: category,
                startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
            )
        }
        func identifiers(_ schedules: [RecurringTransaction]) -> [String] {
            RecurringNotificationService.requests(
                for: schedules,
                convertedAmounts: [:],
                currencyCode: "EUR",
                showDetails: false,
                appLanguage: nil,
                identifierPrefix: prefix
            ).map(\.identifier)
        }

        let due = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9, minute: 0))
        )
        // The instant the trigger fires, built the way the service builds it. `fireComponents` is
        // what carries WC-L5's 00:00 → 09:00 pin, so the moment has to come through it.
        let fireInstant = try XCTUnwrap(
            calendar.date(from: RecurringNotificationService.fireComponents(for: due))
        )

        let identifier = try XCTUnwrap(identifiers([schedule("Rent", dueAt: due)]).first)
        let stamp = String(identifier.dropFirst(marker.count))
        XCTAssertTrue(identifier.hasPrefix(marker), "\(identifier) is not a coalesced identifier")
        XCTAssertEqual(
            stamp, String(Int(fireInstant.timeIntervalSinceReferenceDate.rounded())),
            """
            The coalesced identifier stamps \"\(stamp)\" where the fire instant is \
            \(fireInstant.timeIntervalSinceReferenceDate) seconds after the reference date. A stamp \
            that is not the instant is a rendering of it, and a rendering has to be read back \
            through a calendar — the calendar the reader happens to have, which is how the same \
            string came to name 00:00Z in Tokyo and 08:00Z in London.
            """
        )
        XCTAssertNotNil(
            Int(stamp),
            """
            The stamp \"\(stamp)\" does not read as a whole number of seconds, so something has to \
            interpret it. Whatever does the interpreting is a time zone and a calendar the writer \
            did not choose.
            """
        )

        // Coalescing is the property the stamp exists to provide, and it has to survive the change:
        // same moment, one banner; different moments, two.
        let together = identifiers([schedule("Rent", dueAt: due), schedule("Gym", dueAt: due)])
        XCTAssertEqual(
            together.count, 1, "two schedules due at the same moment stopped sharing one banner"
        )
        let apart = identifiers([
            schedule("Rent", dueAt: due),
            schedule("Gym", dueAt: due.addingTimeInterval(3_600)),
        ])
        XCTAssertEqual(
            Set(apart).count, 2, "two schedules due an hour apart collapsed into one banner"
        )

        // Migration. Banners delivered under the old form are on lock screens now and their
        // identifiers cannot be rewritten, so the reader still has to understand one — an old stamp
        // that fails to parse would be judged stale and swept, which would make the upgrade itself
        // take down the unread Privacy Mode banners this teardown exists to spare.
        let legacy = RecurringNotificationService.DeliveredReminder(
            identifier: "\(marker)2020-6-15-9-0",
            title: AppLocalization.string("Reminder", appLanguage: nil),
            body: AppLocalization.string("Open Wealth Compass Tracker to review.", appLanguage: nil)
        )
        XCTAssertEqual(
            RecurringNotificationService.staleDelivered(
                [legacy],
                schedules: [],
                convertedAmounts: [:],
                currencyCode: "EUR",
                showDetails: false,
                appLanguage: nil,
                identifierPrefix: prefix
            ),
            [],
            """
            A spent banner stamped under the superseded `<Y-M-D-H-M>` form was swept. Those banners \
            exist on real lock screens and cannot be re-identified, so the reader has to keep \
            understanding the old form until they age out.
            """
        )

        // Why the leap-month collision is gone: the components already carry the distinction, so
        // resolving them to an instant keeps it even though the five stamped numbers did not.
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var ordinary = DateComponents()
        ordinary.era = 78
        ordinary.year = 42
        ordinary.month = 6
        ordinary.day = 8
        ordinary.hour = 9
        ordinary.minute = 0
        ordinary.isLeapMonth = false
        var leapMonth = ordinary
        leapMonth.isLeapMonth = true
        let ordinaryDate = try XCTUnwrap(chinese.date(from: ordinary))
        let leapDate = try XCTUnwrap(chinese.date(from: leapMonth))
        XCTAssertNotEqual(ordinaryDate, leapDate, "the fixture is not a leap-month pair")
        // Exactly the field set `fireComponents` asks for — and `isLeapMonth` comes back anyway.
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        for (name, date) in [("ordinary", ordinaryDate), ("leap", leapDate)] {
            let components = chinese.dateComponents(fields, from: date)
            XCTAssertEqual(
                chinese.date(from: components), date,
                """
                A \(name) Chinese-calendar date did not survive the round trip through the field \
                set `fireComponents` extracts. The coalesced identifier is the resolved instant, so \
                if that round trip stops being exact the leap-month collision comes back — two \
                schedules a leap month apart sharing one identifier, and the second reminder never \
                posted.
                """
            )
        }
    }

    /// Fails if a field the lock screen draws can move without the teardown noticing.
    ///
    /// `DeliveredReminder` decides whether a delivered banner still matches what the app would
    /// publish, and it used to compare `identifier`/`title`/`subtitle`/`body` only. Everything else
    /// `UNMutableNotificationContent` can carry was outside the comparison, so an edit setting
    /// `content.threadIdentifier = schedule.category` — the exact injection the builder's own doc
    /// comment records as having survived a green suite once already — would put the category on the
    /// lock screen as the notification group's header and leave the teardown unable to see it
    /// change. The sibling lock-screen test archives the whole payload and *would* see it; this
    /// could not. That gap is now load-bearing, because `staleDelivered` keeps a spent banner on the
    /// strength of its payload being the hidden one.
    ///
    /// Each case moves exactly one field away from a baseline and asserts the verdict, so the three
    /// deliberate exclusions are recorded here as decisions rather than left to be discovered.
    func testTheDeliveredComparisonSeesEveryFieldAScheduleCouldReach() throws {
        func reminder(
            _ configure: (UNMutableNotificationContent) -> Void = { _ in }
        ) -> RecurringNotificationService.DeliveredReminder {
            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = "Open Wealth Compass Tracker to review."
            content.sound = .default
            configure(content)
            return RecurringNotificationService.DeliveredReminder(
                UNNotificationRequest(identifier: "wc-probe", content: content, trigger: nil)
            )
        }

        let baseline = reminder()
        XCTAssertEqual(baseline, reminder(), "the same payload built twice compared unequal")

        // Every field here is a string the schedule could be poured into, and every one of them is
        // rendered or filed on by the system.
        let seen: [(name: String, mutate: (UNMutableNotificationContent) -> Void)] = [
            ("title", { $0.title = "Recurring Expense due" }),
            ("subtitle", { $0.subtitle = "flat" }),
            ("body", { $0.body = "Rent: €1.450,00" }),
            ("threadIdentifier", { $0.threadIdentifier = "Rent" }),
            ("categoryIdentifier", { $0.categoryIdentifier = "Rent" }),
            ("badge", { $0.badge = 7 }),
        ]
        for probe in seen {
            XCTAssertNotEqual(
                baseline, reminder(probe.mutate),
                """
                `content.\(probe.name)` moved and the teardown could not tell. A banner set from a \
                schedule through this field would keep describing the old value on the lock screen \
                after the schedule changed — and under Privacy Mode it would keep describing the \
                schedule at all.
                """
            )
        }

        // The exclusions. Each is out because a *delivered* notification is not the request that
        // produced it, and a field the system rewrites on delivery would mark every banner stale —
        // reinstating 73e3b22's all-or-nothing sweep by accident.
        let excluded: [(name: String, why: String, mutate: (UNMutableNotificationContent) -> Void)] = [
            (
                "sound",
                "not drawn, and two `.default` sounds are two objects with no documented value equality",
                { $0.sound = UNNotificationSound.defaultCritical }
            ),
            (
                "userInfo",
                "app-private, never rendered, and it carries the schedule's UUID by design",
                { $0.userInfo = ["recurringTransactionID": UUID().uuidString] }
            ),
        ]
        for probe in excluded {
            XCTAssertEqual(
                baseline, reminder(probe.mutate),
                """
                `content.\(probe.name)` is inside the comparison. It is meant to be outside it — \
                \(probe.why) — so this is either a deliberate widening that should update the doc \
                comment on `DeliveredReminder`, or a field that will now take down live banners.
                """
            )
        }

        // The other half of the decision to compare `threadIdentifier`, `categoryIdentifier` and
        // `badge`: **nothing sets them today**. `DeliveredReminder`'s doc comment rests on that, and
        // until now it was a claim rather than a check.
        //
        // The lock-screen test cannot supply this. It asks whether the *hidden* branch's payloads
        // are identical across schedules, and a `threadIdentifier` set from the schedule on the
        // **detailed** branch leaves that assertion untouched — detailed payloads are supposed to
        // differ. Measured, not supposed: injecting `content.threadIdentifier = schedule.category`
        // into `content(for:…)` leaves the lock-screen test green and fails only here.
        let probe = RecurringTransaction(
            type: .expense, category: "Rent", amount: 1_450, description: "flat",
            startDate: Date(), frequency: .monthly,
            nextDueDate: Date().addingTimeInterval(86_400), endDate: nil, currency: .eur
        )
        for showDetails in [true, false] {
            let built = RecurringNotificationService.requests(
                for: [probe],
                convertedAmounts: [probe.id: probe.amount],
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
            let branch = showDetails ? "detailed" : "Privacy Mode"
            XCTAssertEqual(built.count, 1, "the \(branch) branch built no request to check")
            for request in built {
                XCTAssertEqual(
                    request.content.threadIdentifier, "",
                    """
                    The \(branch) branch sets `threadIdentifier`, which the lock screen draws as the \
                    notification group's header. Whatever is in it is published; if it came from the \
                    schedule that is a disclosure under Privacy Mode and a value the teardown has to \
                    track under the other branch. Re-read `DeliveredReminder`'s doc comment before \
                    relaxing this — the comparison already covers the field, but the decision to \
                    compare it was taken on the strength of nothing setting it.
                    """
                )
                XCTAssertEqual(
                    request.content.categoryIdentifier, "",
                    "the \(branch) branch sets `categoryIdentifier`; see the message above"
                )
                XCTAssertNil(
                    request.content.badge,
                    """
                    The \(branch) branch sets `badge`. A count on the app icon is the multiplicity \
                    disclosure 5265c96 closed for banners, on the one surface that survives the \
                    banner being dismissed.
                    """
                )
            }
        }
    }

    /// The stripped `code` view of the notification service, which both lints below read.
    private static func notificationServiceCode() throws -> [[Character]] {
        let service = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Shared/Services/RecurringNotificationService.swift")
        return Self.stripped(try String(contentsOf: service, encoding: .utf8)).code
    }

    /// One line of whitespace-normalised source, so a reformat cannot change a verdict.
    private static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The index of the bracket closing the one at `open`, over a stripped `code` view.
    ///
    /// Only `(` / `)` and `{` / `}` are tracked, and that is enough here because the view it reads
    /// has already blanked comments and string bodies — a brace in `let brace = "{"` cannot move a
    /// boundary.
    private static func closingBracket(from open: String.Index, in text: String) -> String.Index? {
        let pairs: [Character: Character] = ["(": ")", "{": "}"]
        guard let closer = pairs[text[open]] else { return nil }
        let opener = text[open]
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == opener { depth += 1 }
            if text[index] == closer {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// The variable and body of the first `for <name> in <callee>…{ … }`, or `nil` if there is none.
    ///
    /// The variable comes out of the header rather than being assumed, so a rule written against it
    /// holds however the loop names it — and notices when the body binds that name to something
    /// else, which is the whole point of asking.
    private static func loopBody(over callee: String, in text: String) -> (variable: String, body: String)? {
        guard let header = try? NSRegularExpression(pattern: #"\bfor\s+(\w+)\s+in\s+\#(NSRegularExpression.escapedPattern(for: callee))"#),
              let match = header.firstMatch(
                  in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let nameRange = Range(match.range(at: 1), in: text),
              let callRange = Range(match.range, in: text)
        else { return nil }

        // `callee` ends in its own `(`, so the argument list opens on the match's last character.
        // Stepping forward to the next `(` instead would land inside the arguments.
        let openParen = text.index(before: callRange.upperBound)
        guard text[openParen] == "(",
              let closeParen = closingBracket(from: openParen, in: text),
              let openBrace = text[closeParen...].dropFirst().firstIndex(of: "{"),
              // Nothing may sit between the call and the loop's brace. Taking the brace as "the
              // next `{`" accepted anything chained onto the call that contains no brace of its
              // own: `for request in Self.requests(…).map(Self.tampered) { … }` still produced a
              // body reading `try? await center.add(request)`, and every check below passed while
              // the value posted came from `tampered`. A trailing *closure* was caught only by
              // accident — its own `{` became this one — so the rule was never about chaining.
              text[text.index(after: closeParen)..<openBrace].allSatisfy(\.isWhitespace),
              let closeBrace = closingBracket(from: openBrace, in: text)
        else { return nil }
        return (String(text[nameRange]), String(text[text.index(after: openBrace)..<closeBrace]))
    }

    /// The name a `let` binds, when its initialiser is a call to `callee` and **nothing else**.
    ///
    /// The "nothing else" is the substance. `let x = Self.f(…)` and
    /// `let x = Self.f(…).filter { … }` both take their value from `f`, and a check that only asked
    /// where a value came from would accept the second — which is exactly how an erase path is
    /// written that consults the schedules while still routing through the unconditional helper.
    private static func soleCallBinding(of callee: String, in body: String) -> String? {
        guard let binding = try? NSRegularExpression(pattern: #"\blet\s+(\w+)\s*=\s*\#(NSRegularExpression.escapedPattern(for: callee))\s*\("#),
              let match = binding.firstMatch(
                  in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)
              ),
              let nameRange = Range(match.range(at: 1), in: body),
              let matched = Range(match.range, in: body)
        else { return nil }

        let open = body.index(before: matched.upperBound)
        guard let close = closingBracket(from: open, in: body) else { return nil }
        // Nothing may be chained onto the call: the next thing in the statement has to be the end
        // of a line, not a `.`.
        let rest = body[body.index(after: close)...].prefix { $0 != "\n" }
        guard rest.allSatisfy(\.isWhitespace) else { return nil }
        return String(body[nameRange])
    }

    /// Every `func` line at any nesting, paired with the text from it to the next one.
    ///
    /// Coarse, and enough for the one file the two notification lints read: it declares a single
    /// type and nests no function inside a function. Reading the stripped `code` view means a doc
    /// comment naming an API cannot satisfy a rule written against it.
    private static func functionBodies(in code: [[Character]]) throws -> [(name: String, line: Int, body: String)] {
        let declaration = try NSRegularExpression(
            pattern: #"^\s*(?:(?:private|fileprivate|internal|public|static|nonisolated|final|override|mutating)\s+)*func\s+(\w+)"#
        )
        var declarations: [(name: String, index: Int)] = []
        for (index, line) in code.enumerated() {
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = declaration.firstMatch(in: text, range: range),
                  let nameRange = Range(match.range(at: 1), in: text) else { continue }
            declarations.append((String(text[nameRange]), index))
        }
        return declarations.enumerated().map { position, current in
            let end = position + 1 < declarations.count ? declarations[position + 1].index : code.count
            return (
                current.name,
                current.index + 1,
                code[current.index..<end].map { String($0) }.joined(separator: "\n")
            )
        }
    }

    /// Fails if anything can reach `UNUserNotificationCenter.add` other than the one builder the
    /// lock-screen test asserts on.
    ///
    /// This is the rule the last two regressions broke, in both directions. `866b3c7` made the
    /// lock-screen test assert on a whole `UNNotificationRequest` so that no later line could
    /// rewrite a rendered field unseen — and `5265c96`, the very next commit, moved the Privacy Mode
    /// production path onto a *second* builder the test did not call. Nothing was rewritten after
    /// the fact; the payload simply stopped being built where the test was looking. Pinning the
    /// return value of a function is worth nothing if production can stop calling it, and no
    /// assertion about a returned object can notice that happening.
    ///
    /// So this pins the other end: whatever `sync` hands to the notification centre must have come
    /// out of `requests(for:…)`, which is the function the lock-screen test archives. Add a second
    /// `center.add` — or feed the existing one anything other than the loop variable — and this
    /// fails, which is the signal to bring the new path under the same assertions rather than to
    /// relax this.
    ///
    /// A source lint, and it has to be: the test host is never granted an authorization
    /// (`authorizationStatus.rawValue == 0`) and `center.add` retains 0 of 5 requests, so `sync`
    /// returns before its loop and no runtime observation of this is possible at all.
    ///
    /// Its first version asked four questions, and three spellings walked straight through all four
    /// while the suite stayed at 309 / 0:
    ///
    /// - `UNUserNotificationCenter.current().add(…)` written inside `sync` — posting the schedule's
    ///   `description` as the subtitle and its category as the body and thread, for every schedule,
    ///   *regardless of Privacy Mode*. The checks counted the substring `center.add(`, which that
    ///   spelling does not contain, so the count stayed at 1 and the posting-function list stayed
    ///   `["sync"]`. A full lock-screen leak, worse than the bug this file exists for, invisible.
    /// - `for request in Self.requests(…) { let request = Self.tampered(request); … }` — the loop
    ///   header is still there, the call is still `center.add(request)`, and the `request` being
    ///   posted is a different value.
    /// - Anything at all in another file, which the sweep did not read.
    ///
    /// A later round found two more, both measured, both leaving the suite at 313 / 0:
    ///
    /// - `for request in Self.requests(…).map(Self.tampered) { … }` — a **named** transform between
    ///   the builder and the loop. `loopBody` took the body's opening brace as the next `{` after
    ///   the call, so anything chained on that contains no brace was stepped over and the extracted
    ///   body still read `try? await center.add(request)`. A trailing closure was caught only
    ///   because its own `{` became the one found; the rule was never about chaining. `loopBody` now
    ///   requires whitespace and nothing else between the call and the brace.
    /// - `let backdoor = center; let post = backdoor.add; try? await post(…)` — a **method
    ///   reference**. The pattern was `\.\s*add\s*\(`, which wants a paren straight after `add` and
    ///   so does not match `backdoor.add` on its own line; and the second-handle check counts the
    ///   text `UNUserNotificationCenter`, which `let backdoor = center` never spells. The same
    ///   spelling worked inside `RecurringTransactionNotificationService.swift`, which is on the
    ///   sibling lint's allow-list and policed by the same pattern. Both now match `\.\s*add\b`:
    ///   `add` cannot be called or referenced without being named after a dot, whatever holds it.
    ///
    /// Each hole was a *textual* assumption standing in for a semantic property, so each question is
    /// now asked about the property. What may reach the notification centre is one call, on the
    /// service's one handle to it, inside `sync`, whose argument is the loop variable of a loop over
    /// `Self.requests(…)` and whose body is that call and nothing else — and no other source file
    /// may hold a handle at all.
    ///
    /// **These are still textual checks, and one class of evasion stays open**: a post site written
    /// without the token `add` after a dot — a `@dynamicMemberLookup` shim, a key path, an
    /// Objective-C selector, a C function pointer. Nothing in this project is shaped that way and
    /// none of it is idiomatic, but a regex cannot rule it out, and the honest statement of what
    /// this lint buys is "no *ordinary* second post site", not "no second post site".
    func testEveryReminderReachingTheNotificationCentreComesFromOneBuilder() throws {
        let code = try Self.notificationServiceCode()
        let functions = try Self.functionBodies(in: code)
        XCTAssertGreaterThanOrEqual(
            functions.count, 5,
            "found \(functions.count) function(s) in RecurringNotificationService.swift — the sweep has lost the file"
        )

        let text = code.map { String($0) }.joined(separator: "\n")
        // Any receiver, any spacing: `center.add(`, `self.center.add(`,
        // `UNUserNotificationCenter.current().add(`. The old check counted one spelling of one name.
        let posts = try NSRegularExpression(pattern: #"\.\s*add\b"#)
        let addSites = posts.numberOfMatches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        XCTAssertEqual(
            addSites, 1,
            """
            \(addSites) call(s) to `.add(` in RecurringNotificationService.swift. The lock-screen \
            test archives what `requests(for:…)` returns, and that is only the same thing as "what \
            the lock screen draws" while exactly one call site posts, out of exactly that \
            function's output.
            """
        )

        // One handle on the centre — the stored property. A second one is how a second post site is
        // written without ever naming the first.
        let handles = text.components(separatedBy: "UNUserNotificationCenter").count - 1
        XCTAssertEqual(
            handles, 1,
            """
            \(handles) reference(s) to `UNUserNotificationCenter` in the service, where there should \
            be exactly one — the stored `center`. A second handle is a second way to post that does \
            not have to mention the first, which is how `UNUserNotificationCenter.current().add(…)` \
            slipped past a check counting the substring `center.add(`.
            """
        )

        let posting = functions.filter { current in
            posts.numberOfMatches(
                in: current.body,
                range: NSRange(current.body.startIndex..<current.body.endIndex, in: current.body)
            ) > 0
        }
        XCTAssertEqual(
            posting.map(\.name), ["sync"],
            "the notification centre is fed from \(posting.map(\.name)) rather than from `sync` alone"
        )

        // The loop, and what is inside it. Binding the variable from the header rather than
        // expecting the name `request` means renaming it is free and rebinding it is not.
        let loop = try XCTUnwrap(
            Self.loopBody(over: "Self.requests(", in: text),
            """
            Nothing in the service loops over `Self.requests(…)` directly any more, so whatever the \
            single post site is feeding the notification centre did not come from the builder the \
            lock-screen test archives. This also fires when something is *chained* onto the call — \
            `Self.requests(…).map(Self.tampered)` — because the loop is then over the transform's \
            output and the builder's return value is no longer what reaches the lock screen.
            """
        )
        let expected = try NSRegularExpression(
            pattern: #"^try\? await [A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\.add\(\#(NSRegularExpression.escapedPattern(for: loop.variable))\)$"#
        )
        let body = Self.squeezed(loop.body)
        XCTAssertEqual(
            expected.numberOfMatches(in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)),
            1,
            """
            The loop over `Self.requests(…)` does more than post `\(loop.variable)`:

              \(body)

            Every statement between the builder and `add` is a statement that can rewrite the \
            payload — `let \(loop.variable) = Self.tampered(\(loop.variable))` shadows the loop \
            variable and satisfies every check that only asks whether the loop and the call are \
            still spelled the same way. Under Privacy Mode what it posts instead is drawn on a \
            locked screen.
            """
        )
    }

    /// Fails if any source outside the notification service can reach the notification centre.
    ///
    /// The lint above reads one file, so until now a post path anywhere else was out of scope by
    /// construction — the strongest possible guarantee about `RecurringNotificationService.swift`
    /// says nothing about a `UNUserNotificationCenter.current().add(…)` in a view.
    ///
    /// Scoped by *type* rather than by call, which is what keeps it from firing on everything: a
    /// blanket sweep for `.add(` reports `engine.state.add(pendingRecordZoneChanges:)` in
    /// `CloudKitSyncService`, which has nothing to do with notifications. What is asked instead is
    /// which files may name `UNUserNotificationCenter` or `UNNotificationRequest` at all. Two
    /// platform delegates have to — they assign `.delegate` on launch — and they are listed here
    /// with the further requirement that they post nothing.
    func testNoSourceOutsideTheNotificationServiceReachesTheNotificationCentre() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        /// The one file that builds and posts reminders, and the two that only register a delegate.
        let builder = "Shared/Services/RecurringNotificationService.swift"
        let delegates: Set<String> = [
            "iOS/Services/RecurringTransactionNotificationService.swift",
            "macOS/MacAppDelegate.swift",
        ]
        let posts = try NSRegularExpression(pattern: #"\.\s*add\b"#)

        var reaching: [String] = []
        var posting: [String] = []
        var filesRead = 0

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()

            for file in swiftFiles {
                filesRead += 1
                let path = "\(directory)/\(file)"
                let code = Self.stripped(
                    try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                ).code.map { String($0) }.joined(separator: "\n")
                guard code.contains("UNUserNotificationCenter") || code.contains("UNNotificationRequest")
                else { continue }
                if path != builder, !delegates.contains(path) { reaching.append(path) }
                let range = NSRange(code.startIndex..<code.endIndex, in: code)
                if delegates.contains(path), posts.numberOfMatches(in: code, range: range) > 0 {
                    posting.append(path)
                }
            }
        }

        XCTAssertGreaterThan(
            filesRead, 20, "only \(filesRead) Swift file(s) read — the sweep has lost the source tree"
        )
        XCTAssertEqual(
            reaching, [],
            """
            \(reaching.count) source(s) outside the notification service reach the notification \
            centre. Everything the lock-screen test guarantees is about payloads built in \
            `\(builder)`; a request posted from anywhere else is drawn on the same lock screen with \
            nothing asserting on it:
            \(reaching.map { "  " + $0 }.joined(separator: "\n"))
            """
        )
        XCTAssertEqual(
            posting, [],
            """
            \(posting.count) platform delegate(s) call `.add(`. They are listed here to assign \
            `UNUserNotificationCenter.current().delegate` on launch and for nothing else:
            \(posting.map { "  " + $0 }.joined(separator: "\n"))
            """
        )
    }

    /// Fails if the erase path can be made to spare a banner.
    ///
    /// "Erase local data" means the schedules are gone, so no banner describing one can still be
    /// accurate and there is nothing left to compare against — which is why this path stays
    /// all-or-nothing while `sync`'s is scoped. The lint that used to hold it asked whether
    /// `clearScheduledReminders`'s body contained the literal `staleDelivered`, and a teardown that
    /// caches the schedules in `sync` and keeps the banners still backed by them satisfies that
    /// check verbatim, under any name at all.
    ///
    /// So the decision is a function now, and this asserts its values. There is no parameter through
    /// which a schedule could arrive, so no caller can feed it one.
    ///
    /// This test's doc comment used to add "and no actor state a `nonisolated static` could read, so
    /// making it consult the data is a signature change this test will not compile against — which
    /// is a stronger guarantee than any spelling of a lint over its body". That is **false about
    /// Swift**. `nonisolated` excludes the actor's *instance* state and nothing more; static storage
    /// is not instance state. A `nonisolated(unsafe) static var lastSyncedSchedules`, written in
    /// `sync` and read by `everyReminder` to filter identifiers out, compiles, changes no signature,
    /// and passes every assertion below — the schedule list is empty in these fixtures, so the
    /// filter does nothing here and everything in production, where erase runs against the banners
    /// of data the user has just wiped.
    ///
    /// So the signature is only half of it, and the other half is the storage check at the end: this
    /// type may declare no mutable static or file-scope storage for such a cache to live in. That is
    /// a textual check over one file, with the limits every textual check in this suite has — it
    /// does not reach a cache parked in another file, and it is recorded as a known hole rather than
    /// dressed up as a structural guarantee.
    func testTheErasePathNamesEveryReminderItOwns() {
        let prefix = Self.reminderIdentifierPrefix
        let pending = ["\(prefix)\(UUID().uuidString)", "\(prefix)due-2031-6-15-9-0"]
        let delivered = ["\(prefix)\(UUID().uuidString)", "\(prefix)due-2031-6-15-20-0"]
        let foreign = ["wealth-compass-mac-recurring-\(UUID().uuidString)", "com.someone.else.reminder"]

        XCTAssertEqual(
            Set(RecurringNotificationService.everyReminder(
                pending: pending + foreign, delivered: delivered + foreign, identifierPrefix: prefix
            )),
            Set(pending + delivered),
            """
            The erase path either spared a reminder this service owns — leaving the user's schedules \
            describing themselves on a device they just wiped, which is the bug 73e3b22 fixed — or \
            reached one it does not own.
            """
        )
        XCTAssertEqual(
            RecurringNotificationService.everyReminder(
                pending: [], delivered: [], identifierPrefix: prefix
            ),
            [],
            "the erase path invented an identifier out of two empty queues"
        )
        // A delivered banner is by definition no longer pending, so the two lists have to be read
        // separately — `cancelAll` used to filter the pending queue and hand *that* list to
        // `removeDeliveredNotifications`, which could never name a delivered banner.
        XCTAssertEqual(
            RecurringNotificationService.everyReminder(
                pending: [], delivered: delivered, identifierPrefix: prefix
            ),
            delivered,
            "a banner already on the lock screen is unreachable unless the delivered queue is read"
        )

        // The half the signature does not give. `everyReminder` is pure only while there is nowhere
        // for a cache to live: a `nonisolated(unsafe) static var lastSyncedSchedules` set in `sync`
        // and read here would filter the still-backed banners out of erase without changing one
        // signature. So the service may declare no mutable static or file-scope storage at all.
        //
        // Read over the stripped `code` view, so a doc comment naming `static var` cannot fail this.
        // Function-local `var`s are fine and are what the indentation test lets through — they
        // cannot survive between two calls, which is the whole property being bought.
        let lines = try! Self.notificationServiceCode().map { String($0) }
        let mutableStorage = try! NSRegularExpression(pattern: #"\bstatic\b[^\n]{0,60}?\bvar\b"#)
        let unsafeGlobal = try! NSRegularExpression(pattern: #"\bnonisolated\s*\(\s*unsafe\s*\)"#)
        let fileScopeVar = try! NSRegularExpression(pattern: #"^(?!\s)(?:[A-Za-z@(){},\s]*\s)?var\s"#)

        var storage: [String] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let why = [
                (mutableStorage, "mutable static storage"),
                (unsafeGlobal, "`nonisolated(unsafe)`"),
                (fileScopeVar, "a file-scope `var`"),
            ].filter { $0.0.numberOfMatches(in: line, range: range) > 0 }.map(\.1)
            guard !why.isEmpty else { continue }
            storage.append("  :\(index + 1) — \(why.joined(separator: ", "))\n      \(line.trimmingCharacters(in: .whitespaces))")
        }
        XCTAssertGreaterThan(
            lines.count, 200, "only \(lines.count) line(s) of service read — the sweep has lost the file"
        )
        XCTAssertEqual(
            storage, [],
            """
            \(storage.count) place(s) in RecurringNotificationService.swift where state could \
            survive between two calls. `everyReminder` decides what "erase local data" removes, and \
            it is trustworthy only while there is nowhere for the schedules to be cached behind its \
            back — a `nonisolated(unsafe) static var` set in `sync` and read there filters the \
            still-backed banners out of erase, changing no signature and passing every assertion \
            above, which leaves the user's wiped data describing itself on the lock screen:
            \(storage.joined(separator: "\n"))
            """
        )
    }

    /// Fails if the 60-request cap can drop the wrong reminders.
    ///
    /// `requests(for:…)` documented "in due-date order" and did nothing to produce it: the order
    /// held only because `sync` happened to call `.sorted` on the line above. Since the order is
    /// what decides which schedules survive `pendingRequestLimit`, an unsorted array — a second
    /// caller, or an edit that moved `sync`'s filter around — would have posted an arbitrary 60 and
    /// silently dropped real reminders, with the doc comment still claiming otherwise. The sort now
    /// lives in the function that makes the promise.
    ///
    /// Reversed rather than shuffled so the failure is deterministic: with the sort in the caller
    /// only, this posts the *latest* 60 of 70 and every early reminder goes missing.
    func testTheRequestCapKeepsTheEarliestRemindersWhateverOrderTheyArriveIn() throws {
        let calendar = Calendar.current
        let limit = RecurringNotificationService.pendingRequestLimit
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2031, month: 6, day: 15, hour: 9)))

        let byDate = try (0..<(limit + 10)).map { offset in
            RecurringTransaction(
                type: .expense, category: "c\(offset)", amount: 100, description: "c\(offset)",
                startDate: start, frequency: .monthly,
                nextDueDate: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start)),
                endDate: nil, currency: .eur
            )
        }
        func requests(_ schedules: [RecurringTransaction], showDetails: Bool) -> [UNNotificationRequest] {
            RecurringNotificationService.requests(
                for: schedules,
                convertedAmounts: Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }),
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        let expected = byDate.prefix(limit).map {
            RecurringNotificationService.notificationIdentifier(for: $0.id, prefix: Self.reminderIdentifierPrefix)
        }
        XCTAssertEqual(
            requests(Array(byDate.reversed()), showDetails: true).map(\.identifier), expected,
            """
            Handed the same schedules latest-first, the cap kept a different 60 — so which reminders \
            are posted depends on the order the caller happens to pass, and the ten it drops are not \
            the ten furthest away.
            """
        )
        XCTAssertEqual(
            requests(byDate, showDetails: true).map(\.identifier), expected,
            "already-sorted input no longer yields the earliest \(limit) reminders in due-date order"
        )

        // Privacy Mode caps moments rather than schedules, and picks them the same way.
        let hidden = requests(Array(byDate.reversed()), showDetails: false).map(\.identifier)
        XCTAssertEqual(
            hidden, requests(byDate, showDetails: false).map(\.identifier),
            "the coalesced set depends on the order the caller passes"
        )
        XCTAssertEqual(hidden.count, limit, "one moment per day, capped at \(limit)")
    }

    /// Fails if Privacy Mode posts one banner per schedule when several are due at the same moment.
    ///
    /// With the details hidden every reminder is the same two constants, so a bystander cannot read
    /// *what* is due — and can count *how much* of it there is. Five schedules due on the same day
    /// put five identical "Reminder / Open Wealth Compass Tracker to review." banners on the lock
    /// screen, and five is the number of schedules. The multiplicity was the disclosure.
    ///
    /// Not a corner case. WC-L5 pins every date-only or imported schedule's 00:00 to 09:00 local,
    /// so it is not "N due in the same minute" but "N date-only schedules due on the same day" —
    /// which is what a JSON backup or a broker statement brings in.
    ///
    /// Unlike the rest of the lock-screen work this is directly observable: `requests(for:…)` is a
    /// pure function of the schedule set, so the whole request set can be built and counted without
    /// the notification centre the test host never authorizes.
    ///
    /// New coverage rather than a regression test — `requests(for:…)` did not exist before the fix
    /// and there was nothing to call. What it pins is stated as separate facts on purpose: dropping
    /// the coalescing fails the first, and getting there by changing what Privacy Mode *says* or
    /// *when it fires* fails the others.
    func testPrivacyModePostsOneReminderPerMomentRatherThanPerSchedule() throws {
        let calendar = Calendar.current
        // Mid-June, so no zone shifts its clocks across the midnight WC-L5 keys off.
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2031, month: 6, day: 15)))
        let evening = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2031, month: 6, day: 15, hour: 18, minute: 30))
        )

        func schedule(_ category: String, dueAt due: Date) -> RecurringTransaction {
            RecurringTransaction(
                type: .expense, category: category, amount: 100, description: category,
                startDate: due, frequency: .monthly, nextDueDate: due, endDate: nil, currency: .eur
            )
        }
        func requests(_ schedules: [RecurringTransaction], showDetails: Bool) -> [UNNotificationRequest] {
            RecurringNotificationService.requests(
                for: schedules,
                convertedAmounts: Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0.amount) }),
                currencyCode: "EUR",
                showDetails: showDetails,
                appLanguage: nil,
                identifierPrefix: Self.reminderIdentifierPrefix
            )
        }

        // The shape an import produces: date-only schedules, all pinned to 09:00 by WC-L5.
        let sameDay = ["Rent", "Gym", "Insurance", "Streaming", "Phone"].map { schedule($0, dueAt: day) }

        let open = requests(sameDay, showDetails: true)
        XCTAssertEqual(
            open.count, sameDay.count,
            "Privacy Mode OFF must still post one reminder per schedule — each of them says something different"
        )
        XCTAssertEqual(
            Set(open.map(\.identifier)).count, sameDay.count,
            """
            With Privacy Mode off two schedules were filed under the same identifier, so one \
            silently replaces the other and a reminder goes missing.
            """
        )

        let hidden = requests(sameDay, showDetails: false)
        XCTAssertEqual(
            hidden.count, 1,
            """
            Privacy Mode posted \(hidden.count) identical banners for \(sameDay.count) schedules due \
            at the same moment. Nobody can read what is due; anybody can count how many.
            """
        )
        let coalesced = try XCTUnwrap(hidden.first)

        // A second fire time is a second reminder. Coalescing collapses duplicates, not reminders.
        let twoMoments = sameDay + [schedule("Rates", dueAt: evening)]
        XCTAssertEqual(
            Set(requests(twoMoments, showDetails: false).map(\.identifier)).count, 2,
            "a schedule due at its own time of day lost its reminder to the 09:00 batch"
        )

        // Same schedules in, same requests out. `sync` re-runs on every schedule edit, currency
        // change and Privacy Mode toggle; the identifiers must not churn underneath it.
        XCTAssertEqual(
            hidden.map(\.identifier), requests(sameDay, showDetails: false).map(\.identifier),
            "the coalesced identifier is not a pure function of the fire time"
        )

        // The one banner says what a single hidden reminder says, and fires when it would fire.
        let single = RecurringNotificationService.request(
            for: sameDay[0], convertedAmount: nil, currencyCode: "EUR",
            showDetails: false, appLanguage: nil, identifierPrefix: Self.reminderIdentifierPrefix
        )
        XCTAssertEqual(
            [coalesced.content.title, coalesced.content.body],
            [single.content.title, single.content.body],
            "the coalesced banner and the per-schedule one no longer say the same thing"
        )
        XCTAssertEqual(
            (coalesced.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
            (single.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
            "the coalesced banner fires at a different moment than the schedules it stands for"
        )

        // The cap is on requests, not schedules, so coalescing frees the budget it saves for the
        // dates after today instead of spending it on duplicates of today.
        let limit = RecurringNotificationService.pendingRequestLimit
        let manyOneDay = (0..<(limit * 3)).map { schedule("c\($0)", dueAt: day) }
        XCTAssertEqual(
            requests(manyOneDay, showDetails: true).count, limit,
            "the \(limit)-request cap stopped applying with Privacy Mode off; iOS keeps 64 and drops the rest"
        )
        XCTAssertEqual(
            requests(manyOneDay, showDetails: false).count, 1,
            "\(limit * 3) schedules due at one moment still produced more than one banner"
        )
        let manyDays = try (0..<(limit * 3)).map { offset in
            schedule("c\(offset)", dueAt: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day)))
        }
        XCTAssertEqual(
            requests(manyDays, showDetails: false).count, limit,
            "distinct fire times must each get a reminder, up to the cap"
        )
    }

    // MARK: - Sweep internals

    /// The spellings of a percentage this codebase can produce. Anything else — a renamed wrapper,
    /// a `NumberFormatter`, a percentage assembled from parts — is invisible to the sweep, which is
    /// the main reason the test above promises a lint rather than a guarantee.
    private struct PercentagePattern {
        let name: String
        let regex: NSRegularExpression
        /// `.formatted(` and its `.percent` are routinely split across two lines.
        let joinsNextLine: Bool
        /// Which stripped view to match against. Only the printf spelling lives inside a string
        /// literal; matching the two call spellings there as well would report
        /// `let note = "use formattedPercent(…)"` as a render.
        let insideStringBodies: Bool
    }

    private static let percentagePatterns: [PercentagePattern] = [
        // `formattedPercent (x)` with a space compiles and prints the same thing as without.
        PercentagePattern(name: "formattedPercent(",
                          regex: try! NSRegularExpression(pattern: #"\bformattedPercent\s*\("#),
                          joinsNextLine: false, insideStringBodies: false),
        // The formatter `formattedPercent` itself wraps, called directly.
        PercentagePattern(name: ".formatted(.percent",
                          regex: try! NSRegularExpression(pattern: #"\.formatted\(\s*\.percent"#),
                          joinsNextLine: true, insideStringBodies: false),
        // `%%` in a Swift string literal is a printf-escaped percent sign and nothing else.
        PercentagePattern(name: #"a "%%" format string"#,
                          regex: try! NSRegularExpression(pattern: #""[^"\n]*%%"#),
                          joinsNextLine: false, insideStringBodies: true),
    ]

    /// Where the first percentage spelling starts on this line, if any. Columns are the same in
    /// both stripped views — the stripper replaces, never removes — so the caller can use the
    /// returned one against `code` whichever view matched.
    private static func percentageMatch(at index: Int, in source: StrippedSource) -> (column: Int, pattern: String)? {
        for pattern in percentagePatterns {
            let lines = pattern.insideStringBodies ? source.scan : source.code
            let line = String(lines[index])
            let subject = pattern.joinsNextLine && index + 1 < lines.count
                ? line + " " + String(lines[index + 1])
                : line
            let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
            guard let match = pattern.regex.firstMatch(in: subject, range: range),
                  let matched = Range(match.range, in: subject) else { continue }
            let column = subject.distance(from: subject.startIndex, to: matched.lowerBound)
            guard column < line.count else { continue }   // it began on the joined line
            return (column, pattern.name)
        }
        return nil
    }

    /// Two line-for-line views of a file, so that reformatting cannot change a verdict.
    ///
    /// Both blank comment bodies, so `formattedPercent(` written in a comment is never a render.
    /// They differ on string literals: `code` blanks their bodies too, so a `{` in a comment or in
    /// `let brace = "{"` cannot move a block boundary, and it is what the two call spellings and all
    /// the brace and paren walking are matched against. `scan` keeps string bodies, and only the
    /// `"%.1f%%"` pattern reads it, because that spelling *is* a string. Code inside a `\(…)`
    /// interpolation survives in both: `LocalizedStringKey("\(formattedPercent(…))")` is a real
    /// render site in two of the views.
    private struct StrippedSource {
        let scan: [[Character]]
        let code: [[Character]]
    }

    private static func stripped(_ text: String) -> StrippedSource {
        let chars = Array(text)
        var scan: [Character] = []
        var code: [Character] = []
        scan.reserveCapacity(chars.count)
        code.reserveCapacity(chars.count)

        // Strings and their `\(…)` interpolations nest arbitrarily, so this is a stack.
        enum Frame {
            case string(hashes: Int, multiline: Bool)
            case interpolation(hashes: Int, multiline: Bool, parens: Int)
        }
        var frames: [Frame] = []
        var blockComment = 0
        var i = 0

        func hashRun(at j: Int) -> Int {
            var n = 0
            while j + n < chars.count, chars[j + n] == "#" { n += 1 }
            return n
        }
        func keep(_ n: Int) {                    // real code: verbatim in both
            for k in 0..<n where i + k < chars.count { scan.append(chars[i + k]); code.append(chars[i + k]) }
            i += n
        }
        func keepScanOnly(_ n: Int) {            // string body: text in `scan`, blank in `code`
            for k in 0..<n where i + k < chars.count {
                let c = chars[i + k]
                scan.append(c); code.append(c == "\n" ? "\n" : " ")
            }
            i += n
        }
        func blank(_ n: Int) {                   // comment: blank in both
            for k in 0..<n where i + k < chars.count {
                let replacement: Character = chars[i + k] == "\n" ? "\n" : " "
                scan.append(replacement); code.append(replacement)
            }
            i += n
        }

        while i < chars.count {
            let c = chars[i]

            if blockComment > 0 {                                        // Swift block comments nest
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" { blockComment += 1; blank(2); continue }
                if c == "*", i + 1 < chars.count, chars[i + 1] == "/" { blockComment -= 1; blank(2); continue }
                blank(1); continue
            }

            if case .string(let hashes, let multiline) = frames.last {
                if c == "\\", hashRun(at: i + 1) == hashes {
                    if i + 1 + hashes < chars.count, chars[i + 1 + hashes] == "(" {
                        keepScanOnly(1 + hashes)                         // the `\` and its `#`s
                        keep(1)                                          // the `(` that reopens code
                        frames.removeLast()
                        frames.append(.interpolation(hashes: hashes, multiline: multiline, parens: 1))
                        continue
                    }
                    keepScanOnly(min(2 + hashes, chars.count - i))       // `\"` must not close the string
                    continue
                }
                if c == "\"" {
                    let quoteCount = multiline ? 3 : 1
                    let closes = (0..<quoteCount).allSatisfy { i + $0 < chars.count && chars[i + $0] == "\"" }
                    if closes, hashRun(at: i + quoteCount) == hashes {
                        keepScanOnly(quoteCount + hashes)
                        frames.removeLast()
                        continue
                    }
                }
                if c == "\n", !multiline { frames.removeLast() }         // unterminated: resynchronise
                keepScanOnly(1)
                continue
            }

            // Code, either top level or inside an interpolation.
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                var n = 0
                while i + n < chars.count, chars[i + n] != "\n" { n += 1 }
                blank(n); continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" { blockComment = 1; blank(2); continue }

            let hashes = c == "#" ? hashRun(at: i) : 0
            if c == "\"" || (hashes > 0 && i + hashes < chars.count && chars[i + hashes] == "\"") {
                let quote = i + hashes
                let multiline = quote + 2 < chars.count && chars[quote + 1] == "\"" && chars[quote + 2] == "\""
                keepScanOnly(hashes + (multiline ? 3 : 1))
                frames.append(.string(hashes: hashes, multiline: multiline))
                continue
            }

            if case .interpolation(let hashes, let multiline, let parens) = frames.last {
                if c == "(" {
                    frames.removeLast()
                    frames.append(.interpolation(hashes: hashes, multiline: multiline, parens: parens + 1))
                } else if c == ")" {
                    frames.removeLast()
                    if parens == 1 {
                        frames.append(.string(hashes: hashes, multiline: multiline))
                        keep(1); continue
                    }
                    frames.append(.interpolation(hashes: hashes, multiline: multiline, parens: parens - 1))
                }
            }
            keep(1)
        }

        func split(_ buffer: [Character]) -> [[Character]] {
            var out: [[Character]] = [[]]
            for c in buffer { if c == "\n" { out.append([]) } else { out[out.count - 1].append(c) } }
            return out
        }
        return StrippedSource(scan: split(scan), code: split(code))
    }

    private static let declarationPattern = try! NSRegularExpression(
        pattern: #"^\s*(@\w+\s+)*((private|fileprivate|internal|public|open|static|final)\s+)*(func|var)\s+\w+"#
    )

    /// A `-> String` member is a formatter, not a render: only what a `View` body prints reaches the
    /// screen, and a formatter's callers are where the gating belongs. At the time of writing that
    /// exempts five lines in four declarations — `formattedPercent` itself
    /// (`DesignSystem.swift:372`, and its body's own `.formatted(.percent` at `:374`),
    /// `AppSettings.privatePercent`'s body (`AppSettings.swift:365`), `AllocationChart`'s
    /// share-of-total helper (`DesignSystem.swift:561`) and the Sankey node's VoiceOver value
    /// builder (`SankeyDiagramView.swift:481`). It is also the widest hole in the sweep: move a
    /// render into a `-> String` helper and it stops being visible here.
    private static func isStringHelper(at index: Int, in code: [[Character]]) -> Bool {
        guard let declaration = enclosingDeclaration(at: index, in: code) else { return false }
        // The return clause can land a line or two below the name on a wrapped signature.
        return (declaration...min(declaration + 2, code.count - 1))
            .map { String(code[$0]) }
            .joined(separator: " ")
            .contains("-> String")
    }

    private static func enclosingDeclaration(at index: Int, in code: [[Character]]) -> Int? {
        for i in stride(from: index, through: 0, by: -1) {
            let line = String(code[i])
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if declarationPattern.firstMatch(in: line, range: range) != nil { return i }
        }
        return nil
    }

    /// `isPrivacyModeOn`, `ExportOptionsView`'s spelling of the same flag, matches on the prefix.
    private static let gateToken = "isPrivacyMode"

    /// A privacy check found in some text, and which way round it reads.
    ///
    /// Both sweeps used to ask only whether the flag was *named*, which is not the same question.
    /// Changing `AllocationChart`'s `} else if settings.isPrivacyMode {` to
    /// `} else if !settings.isPrivacyMode {` — one character — makes the true-proportion ring draw
    /// only in Privacy Mode and the cover appear only when privacy is off, and the whole suite
    /// stayed green. A branch swap is a realistic regression; naming the flag is not evidence.
    ///
    /// Only the negations this codebase can write are understood: a `!` in front of the flag
    /// (through an optional `(`, so `!(settings.isPrivacyMode)` reads correctly, and not confused
    /// by a force-unwrap), and a trailing `== false`. A flag copied into a `let` and tested later,
    /// `!= true`, or a negation spelled by a helper all read as positive. It is a lint.
    private struct PrivacyGate {
        /// Where the flag's own token starts, in the string it was found in.
        let offset: Int
        let isNegated: Bool
    }

    /// The privacy check nearest `before`, or the first one if `before` is `nil`.
    private static func privacyGate(in text: String, before limit: Int? = nil) -> PrivacyGate? {
        let chars = Array(text)
        let token = Array(gateToken)
        var found: Int?
        var i = 0
        while i + token.count <= chars.count {
            if Array(chars[i..<(i + token.count)]) == token {
                if let limit, i >= limit { break }
                found = i
                if limit == nil { break }
            }
            i += 1
        }
        guard let start = found else { return nil }

        // Left, over the receiver path (`settings.`), whitespace, and an optional `(`.
        var j = start - 1
        while j >= 0, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "." { j -= 1 }
        while j >= 0, chars[j] == " " { j -= 1 }
        if j >= 0, chars[j] == "(" {
            j -= 1
            while j >= 0, chars[j] == " " { j -= 1 }
        }
        // `settings!.isPrivacyMode` is a force-unwrap, not a negation.
        var negated = j >= 0 && chars[j] == "!" && !(j + 1 < chars.count && chars[j + 1] == ".")

        // …and right, for `== false`.
        let tail = String(chars[min(start + token.count, chars.count)...])
            .trimmingCharacters(in: .whitespaces)
        if tail.hasPrefix("== false") { negated.toggle() }

        return PrivacyGate(offset: start, isNegated: negated)
    }

    /// Whether a visible privacy gate covers this render.
    ///
    /// Two places count, and only two: the header of the block the render sits in — which is where
    /// `if !settings.isPrivacyMode {` lives — and the render's own expression. A gate anywhere else
    /// in the block is a *sibling's* gate. Accepting those is what let a live `MetricCard(… value:
    /// formattedPercent(…))` be dropped into `CryptoView`'s `LazyVGrid` with the suite still green,
    /// gated by nothing but the Holdings card's unrelated check three lines up.
    ///
    /// Both places are polarity-aware. The render sits in the block the header opens, so the header
    /// has to carry the *negated* form — a positive `if settings.isPrivacyMode { … }` around a live
    /// percentage prints it only while privacy is on, which is the leak, not the gate. (`guard`
    /// inverts that: the block a `guard` opens is its `else`.) In an expression the render has to
    /// land on the arm the check does not take — after the `:` of
    /// `settings.isPrivacyMode ? settings.redactionToken : formattedPercent(…)`, the codebase's own
    /// idiom, or before it if the condition is negated.
    private static func isPrivacyGated(at index: Int, column: Int, in code: [[Character]]) -> Bool {
        let opener = enclosingBlockOpener(at: index, column: column, in: code)
        let header = blockHeader(openedAt: opener, in: code)
            .map { String(code[$0]) }
            .joined(separator: " ")
        if let gate = privacyGate(in: header) {
            let isGuard = header.trimmingCharacters(in: .whitespaces).hasPrefix("guard")
            return gate.isNegated != isGuard
        }

        let start = expressionStart(at: index, column: column, in: code, notBefore: opener)
        var expression = String(code[start.line].dropFirst(start.column))
        var renderOffset = column - start.column
        if start.line < index {
            for line in (start.line + 1)...index {
                if line == index { renderOffset = expression.count + 1 + column }
                expression += " " + String(code[line])
            }
        }
        guard let gate = privacyGate(in: expression, before: renderOffset),
              let colon = ternaryColon(after: gate.offset, in: expression) else { return false }
        return (renderOffset > colon) != gate.isNegated
    }

    /// The `:` belonging to the ternary whose condition holds the gate at `offset`, as an offset
    /// into the same string. `??` is not a ternary, a `:` inside a nested group is an argument
    /// label or a dictionary, and a nested `? :` has to cancel out before the outer `:` counts.
    private static func ternaryColon(after offset: Int, in expression: String) -> Int? {
        let chars = Array(expression)

        func scan(from start: Int, stoppingAtColon: Bool) -> Int? {
            var depth = 0
            var pending = 0
            var i = start
            while i < chars.count {
                switch chars[i] {
                case "(", "[":
                    depth += 1
                case ")", "]":
                    if depth == 0 { return nil }      // walked out of the gate's own group
                    depth -= 1
                case "?" where depth == 0:
                    if i + 1 < chars.count, chars[i + 1] == "?" { i += 1; break }
                    if !stoppingAtColon { return i }
                    pending += 1
                case ":" where depth == 0 && stoppingAtColon:
                    if pending == 0 { return i }
                    pending -= 1
                default:
                    break
                }
                i += 1
            }
            return nil
        }

        guard let question = scan(from: offset, stoppingAtColon: false) else { return nil }
        return scan(from: question + 1, stoppingAtColon: true)
    }

    /// The proportional-geometry spellings this codebase can draw. The test's own doc comment
    /// carries the inventory these came from, and the ones deliberately left out.
    ///
    /// `SectorMark (` with a space compiles and draws the same wedge as without, so the space is
    /// part of every mark spelling here.
    private static let geometryPatterns: [(name: String, regex: NSRegularExpression)] = [
        ("SectorMark(", try! NSRegularExpression(pattern: #"\bSectorMark\s*\("#)),
        ("BarMark(", try! NSRegularExpression(pattern: #"\bBarMark\s*\("#)),
        // `.trimmingCharacters(` does not match: the `(` has to follow `trim` directly.
        (".trim(", try! NSRegularExpression(pattern: #"\.trim\s*\("#)),
        // A measured container length scaled by something that is not a literal — the shape of
        // `DashboardView.swift:553`'s spending bar, and of any hand-built proportional bar. The
        // trailing `[^0-9.\s]` is what excludes the decorative `* 0.95` / `* 0.34` cases; a
        // negative lookahead cannot, because `\s*` simply backtracks to nothing in front of it.
        ("a data-scaled .frame",
         try! NSRegularExpression(pattern: #"\.frame\((?:width|height):.*\b(size\.(?:width|height))\s*\*\s*[^0-9.\s]"#)),
    ]

    /// Where a proportion is drawn on this line, if one is.
    ///
    /// A pattern with a capture group reports *that* group's column rather than the match's, so the
    /// column names the proportional expression itself. `.frame(width: settings.isPrivacyMode ? 0 :
    /// geometry.size.width * …)` carries its gate in the middle of the match, and a gate check
    /// anchored at `.frame(` would be looking to the left of it.
    private static func geometryMatch(at index: Int, in code: [[Character]]) -> (column: Int, pattern: String)? {
        let line = String(code[index])
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for (name, regex) in geometryPatterns {
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            let reported = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let matched = Range(reported, in: line) else { continue }
            return (line.distance(from: line.startIndex, to: matched.lowerBound), name)
        }
        return nil
    }

    /// Whether a Privacy-Mode conceal branch encloses this chart.
    ///
    /// Deliberately more generous than `isPrivacyGated`, and for a reason that is specific to
    /// charts. A percentage's gate belongs on the percentage, so looking past its own block is how
    /// a sibling's check gets mistaken for its own. A chart's gate cannot sit that close: the mark
    /// is inside `Chart { … }`, which is inside the `else` of `if settings.isPrivacyMode { cover }
    /// else { chart }`, so the flag is always two or more blocks out. So this walks outward through
    /// the enclosing *block headers* — never sibling statements, which is what keeps the sibling
    /// hole closed — and resolves an `else` opener back to the branch the chain hangs off, since
    /// that is the line naming the flag. It stops at the enclosing declaration: a conceal written in
    /// a different computed property is not this chart's.
    ///
    /// **Polarity.** Reaching a header that names the flag is not the verdict; which arm the chart
    /// is on is. `inElse` records whether the walk got here by resolving an `else`, so a chart is
    /// concealed by the `else` of a positive check or by the body of a negated one, and reported
    /// under either of the other two. See `PrivacyGate`.
    ///
    /// **Brace style.** The resolution is written against the *header*, not against the opener
    /// line, so both styles read the same. `} else {` puts the `}`, the `else` and the `{` on one
    /// line; Allman puts each on its own, and the earlier version — which only resolved when the
    /// opener line itself started with `}` — walked straight past the `else` chain to the enclosing
    /// `VStack` and reported a false positive on behaviour-identical code.
    private static func isConcealed(at index: Int, column: Int, in code: [[Character]]) -> Bool {
        let declaration = enclosingDeclaration(at: index, in: code) ?? 0
        var opener = enclosingBlockOpener(at: index, column: column, in: code)
        /// Whether the block the walk came from is the `else` arm of the header it is now reading.
        var inElse = false

        for _ in 0..<24 {
            let header = blockHeader(openedAt: opener, in: code)
            let text = header.map { String(code[$0]) }.joined(separator: " ")
            if let gate = privacyGate(in: text) {
                return gate.isNegated != inElse
            }
            guard opener > declaration else { return false }

            let head = String(code[header.lowerBound]).trimmingCharacters(in: .whitespaces)
            if head.hasPrefix("}") || head.hasPrefix("else"),
               let keyword = elseKeyword(in: header, of: code),
               let closer = closingBrace(before: keyword, in: code) {
                // `} else {` / `} else if … {`, in either brace style: step to the branch this
                // chain hangs off, from a position just inside the `}` that closed it.
                opener = enclosingBlockOpener(at: closer.line, column: closer.column, in: code)
                inElse = true
            } else if let brace = String(code[opener]).firstIndex(of: "{") {
                let line = String(code[opener])
                opener = enclosingBlockOpener(
                    at: opener, column: line.distance(from: line.startIndex, to: brace), in: code
                )
                inElse = false
            } else {
                return false
            }
        }
        return false
    }

    /// The privacy covers this codebase draws. Two are dedicated views; `MacCashFlowView` and
    /// `SankeyDiagramView` reuse `EmptyState` with the eye-slash glyph instead, so the third
    /// spelling is an `EmptyState` whose title says so. Those are matched against `scan`, where
    /// string bodies survive — in `code` the titles have been blanked away.
    ///
    /// The last pattern matches the *title*, not the view, because `f3fac7c` and `fb5272c` drew the
    /// same cover through four different views: `EmptyState` on iOS and macOS Cash Flow,
    /// `ContentUnavailableView` on the macOS Investments and Crypto pages, and
    /// `DashboardEmptyState` on the macOS Dashboard — and three of those put the title on a line of
    /// its own, where a per-line regex anchored to the constructor cannot reach it. Matching the
    /// string is also the honest rule: a view that says "Hidden by Privacy Mode" **is** a cover,
    /// whatever type draws it. Before this, none of those thirteen sites was swept at all, which
    /// left every macOS edit in that pair of commits with no coverage of any kind.
    private static let coverPatterns: [(name: String, regex: NSRegularExpression)] = [
        ("PrivacyChartCover(", try! NSRegularExpression(pattern: #"\b(?:Mobile)?PrivacyChartCover\s*\("#)),
        ("an EmptyState cover", try! NSRegularExpression(pattern: #"\bEmptyState\s*\([^)]*concealed"#)),
        ("a \"Hidden by Privacy Mode\" cover", try! NSRegularExpression(pattern: #""Hidden by Privacy Mode""#)),
    ]

    /// Where a privacy cover is drawn on this line, if one is.
    private static func coverMatch(at index: Int, in source: StrippedSource) -> (column: Int, pattern: String)? {
        let line = String(source.scan[index])
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for (name, regex) in coverPatterns {
            guard let match = regex.firstMatch(in: line, range: range),
                  let matched = Range(match.range, in: line) else { continue }
            return (line.distance(from: line.startIndex, to: matched.lowerBound), name)
        }
        return nil
    }

    /// Whether nothing at all is evaluated ahead of this cover.
    ///
    /// Two things have to hold. The block the cover sits in is opened by an un-negated privacy
    /// check that starts its own chain — not `} else if settings.isPrivacyMode {`, because whatever
    /// the chain tested first renders while Privacy Mode is on. And no *enclosing* block may be
    /// conditional either: `CashFlowView` and `MacDashboardView` both used to nest the privacy
    /// check inside the `else` of an emptiness test, which reads as a chain-opening `if` when you
    /// only look at the line above the cover, and hides the same leak one level out.
    private static func privacyIsCheckedFirst(at index: Int, column: Int, in code: [[Character]]) -> Bool {
        let declaration = enclosingDeclaration(at: index, in: code) ?? 0
        var opener = enclosingBlockOpener(at: index, column: column, in: code)
        let header = blockHeader(openedAt: opener, in: code)
        guard let gate = privacyGate(in: header.map { String(code[$0]) }.joined(separator: " ")),
              !gate.isNegated,
              !isBranchContinuation(header, in: code) else { return false }

        for _ in 0..<24 {
            guard opener > declaration else { return true }
            let line = String(code[opener])
            guard let brace = line.firstIndex(of: "{") else { return true }
            opener = enclosingBlockOpener(
                at: opener, column: line.distance(from: line.startIndex, to: brace), in: code
            )
            guard opener > declaration else { return true }
            if isConditionalHeader(blockHeader(openedAt: opener, in: code), in: code) { return false }
        }
        return true
    }

    /// Statement keywords that make a block conditional on something. `ForEach { }` is a call, not
    /// one of these — a cover inside one would be a different mistake and is not what this asks.
    private static let conditionalKeywords = ["if ", "if(", "else", "guard ", "switch ", "case ", "default:", "for ", "while "]

    private static func isConditionalHeader(_ header: ClosedRange<Int>, in code: [[Character]]) -> Bool {
        if isBranchContinuation(header, in: code) { return true }
        let head = String(code[header.lowerBound]).trimmingCharacters(in: .whitespaces)
        return conditionalKeywords.contains { head.hasPrefix($0) }
    }

    private static func isBranchContinuation(_ header: ClosedRange<Int>, in code: [[Character]]) -> Bool {
        let head = String(code[header.lowerBound]).trimmingCharacters(in: .whitespaces)
        return head.hasPrefix("}") || head.hasPrefix("else")
    }

    private static let elsePattern = try! NSRegularExpression(pattern: #"\belse\b"#)

    /// Where the `else` sits in a block header, if the header has one.
    private static func elseKeyword(in header: ClosedRange<Int>, of code: [[Character]]) -> (line: Int, column: Int)? {
        for i in header {
            let line = String(code[i])
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = elsePattern.firstMatch(in: line, range: range),
                  let matched = Range(match.range, in: line) else { continue }
            return (i, line.distance(from: line.startIndex, to: matched.lowerBound))
        }
        return nil
    }

    /// The position of the `}` immediately before `position`, skipping whitespace and blank lines —
    /// the brace that closed the branch an `else` continues, wherever the style put it.
    private static func closingBrace(before position: (line: Int, column: Int), in code: [[Character]])
        -> (line: Int, column: Int)?
    {
        var i = position.line
        var slice = Array(code[i].prefix(position.column))
        while true {
            if let last = slice.lastIndex(where: { !$0.isWhitespace }) {
                return slice[last] == "}" ? (i, last) : nil
            }
            i -= 1
            if i < 0 { return nil }
            slice = code[i]
        }
    }

    /// The line carrying the `{` that opens the block this render sits in, found by walking upwards
    /// and letting closed blocks cancel out.
    private static func enclosingBlockOpener(at index: Int, column: Int, in code: [[Character]]) -> Int {
        var depth = 0
        var slice = Array(code[index].prefix(column))
        var i = index
        while true {
            for character in slice.reversed() {
                if character == "}" {
                    depth += 1
                } else if character == "{" {
                    if depth == 0 { return i }
                    depth -= 1
                }
            }
            i -= 1
            if i < 0 { return 0 }
            slice = code[i]
        }
    }

    /// A block's header: the opener line, plus the lines above it carrying the rest of the same
    /// header. Allman style puts the `{` on a line of its own, which would otherwise hide the
    /// `if !settings.isPrivacyMode` sitting one line above it, and a long condition can wrap onto
    /// `&&` / `||`. Nothing else extends a header — `.chartBackground { proxy in` opens a block
    /// whose header is that one line, not the four modifier lines chained above it.
    private static func blockHeader(openedAt opener: Int, in code: [[Character]]) -> ClosedRange<Int> {
        var first = opener
        var budget = 4
        while first > 0, budget > 0 {
            var head = String(code[first]).trimmingCharacters(in: .whitespaces)
            if head.hasPrefix("{") { head = String(head.dropFirst()).trimmingCharacters(in: .whitespaces) }
            let wraps = head.isEmpty || ["&&", "||"].contains { head.hasPrefix($0) }
            guard wraps, !String(code[first - 1]).trimmingCharacters(in: .whitespaces).isEmpty else { break }
            first -= 1
            budget -= 1
        }
        return first...opener
    }

    /// Tokens that leave a line syntactically unfinished, and the tokens that resume one.
    ///
    /// A leading `.` is deliberately not among them. It would make a chained
    /// `.accessibilityValue(formattedPercent(…))` inherit the gate of the `Text(settings.isPrivacyMode
    /// ? … )` it hangs off, and that chain is a leak: the label redacts, the VoiceOver value does not.
    private static let leavesStatementOpen = ["(", "[", "{", ",", "?", ":", "=", "&&", "||", "+", "-", "*", "/", "->", "."]
    private static let resumesStatement = [")", "]", ",", "?", ":", "&&", "||", "+", "*", "/"]

    /// Where the render's own expression starts, walking back from the match.
    ///
    /// A `,` or `;` at the render's own nesting level ends the walk: that is a sibling argument's
    /// territory. An enclosing `(` or `[` does *not*, because the inline idiom
    /// `Text(settings.isPrivacyMode ? … : formattedPercent(…))` puts the gate one group out.
    /// Crossing onto the line above needs that line to be syntactically unfinished, which is what
    /// keeps the walk from wandering into the sibling statements of a `ViewBuilder` block.
    private static func expressionStart(at index: Int, column: Int, in code: [[Character]], notBefore floor: Int)
        -> (line: Int, column: Int)
    {
        var depth = 0
        var slice = Array(code[index].prefix(column))
        var i = index
        while true {
            var offset = slice.count
            for character in slice.reversed() {
                offset -= 1
                switch character {
                case ")", "]": depth += 1
                case "(", "[": if depth > 0 { depth -= 1 }
                case ",", ";": if depth == 0 { return (i, offset) }
                default: break
                }
            }
            guard i - 1 >= floor else { return (i, 0) }
            let here = String(code[i]).trimmingCharacters(in: .whitespaces)
            let above = String(code[i - 1]).trimmingCharacters(in: .whitespaces)
            let unfinished = leavesStatementOpen.contains { above.hasSuffix($0) }
                || resumesStatement.contains { here.hasPrefix($0) }
            guard unfinished else { return (i, 0) }
            i -= 1
            slice = code[i]
        }
    }
}


/// An in-memory `FinancePersistence` preloaded with one dataset, so `FinanceStore.init` — which
/// loads synchronously — comes up holding exactly the fixture the render is supposed to react to.
private final class SeededPersistence: FinancePersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FinancialData?

    init(_ data: FinancialData) { stored = data }

    var locationDescription: String { "in-memory (privacy render test)" }

    func load() throws -> FinancePersistenceLoad? {
        lock.lock(); defer { lock.unlock() }
        return stored.map { FinancePersistenceLoad(data: $0) }
    }

    func save(_ data: FinancialData) throws {
        lock.lock(); defer { lock.unlock() }
        stored = data
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
