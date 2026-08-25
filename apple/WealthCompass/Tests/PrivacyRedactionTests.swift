import SwiftUI
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
        "iOS", "macOS",
        "Shared/UI", "Shared/Stores", "Shared/Export",
        "Shared/Models", "Shared/Services", "Shared/Persistence",
    ]

    /// The files that compose the exported report. A PDF or JSON export is an explicit act on the
    /// user's part and redacts nothing at all, deliberately — `ReportDocumentBuilder.swift:676` and
    /// `:679` print live shares next to live amounts, and nothing there is masked, so there is no
    /// masked amount for a percentage to give away. `ExportOptionsView.swift:91` shows a warning
    /// before the user commits. Scanning these files would report those two lines forever.
    private static let excludedFiles: Set<String> = [
        "ReportDocumentBuilder.swift", "ReportChartRenderer.swift",
        "PDFReportRenderer.swift", "ReportPaginator.swift", "PDFDrawingContext.swift",
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
                .filter { !Self.excludedFiles.contains(($0 as NSString).lastPathComponent) }
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
                .filter { !Self.excludedFiles.contains(($0 as NSString).lastPathComponent) }
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
                .filter { !Self.excludedFiles.contains(($0 as NSString).lastPathComponent) }
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
    /// spelling is an `EmptyState` whose title says so. That one is matched against `scan`, where
    /// string bodies survive — in `code` the word "concealed" has been blanked away.
    private static let coverPatterns: [(name: String, regex: NSRegularExpression)] = [
        ("PrivacyChartCover(", try! NSRegularExpression(pattern: #"\b(?:Mobile)?PrivacyChartCover\s*\("#)),
        ("an EmptyState cover", try! NSRegularExpression(pattern: #"\bEmptyState\s*\([^)]*concealed"#)),
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
