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

    /// Directories holding files that draw figures for a user who may be in Privacy Mode.
    ///
    /// `Shared/Stores` is in because a percentage built in an `AppSettings` extension renders on
    /// screen exactly like one built in a view. `Shared/Export` is in because it is not only the
    /// report renderer: `ExportOptionsView` is a user-facing SwiftUI sheet that *is* privacy-aware
    /// (`isPrivacyModeOn` at its `:14` and `:91`). `Shared/Models`, `Shared/Services` and
    /// `Shared/Persistence` are out because they spell no percentage at all; `Shared/Resources`
    /// holds no Swift.
    private static let scannedDirectories = ["iOS", "macOS", "Shared/UI", "Shared/Stores", "Shared/Export"]

    /// The files that compose the exported report. A PDF or JSON export is an explicit act on the
    /// user's part and redacts nothing at all, deliberately — `ReportDocumentBuilder.swift:676` and
    /// `:679` print live shares next to live amounts, and nothing there is masked, so there is no
    /// masked amount for a percentage to give away. `ExportOptionsView.swift:91` shows a warning
    /// before the user commits. Scanning these files would report those two lines forever.
    private static let excludedFiles: Set<String> = [
        "ReportDocumentBuilder.swift", "ReportChartRenderer.swift",
        "PDFReportRenderer.swift", "ReportPaginator.swift", "PDFDrawingContext.swift",
    ]

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
    /// live card dropped into a `LazyVGrid` beside a redacted one is precisely the bug.
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
    /// the label beside it says `••••`. `SankeyDiagramView.swift:50-52` states the rule in prose and
    /// `PrivacyChartCover`'s own message states it to the user — "Values and proportions are hidden."
    ///
    /// **What it actually checks**, with the same two caveats as the percentage sweep: it greps the
    /// working tree via `#filePath`, not the binary under test, and it is a lint, so it only sees
    /// the one spelling it looks for. `SectorMark` is the only proportional-geometry primitive in
    /// this codebase — there is no `Gauge`, `.trim(from:to:)` arc, `Canvas` ring or sparkline
    /// anywhere — so the spelling is complete today and would need extending alongside a new kind
    /// of chart.
    ///
    /// **The gate a donut has to sit under** is an enclosing `isPrivacyMode` branch: `isConcealed`
    /// walks outward through the block headers around the mark, resolving `} else {` back to the
    /// `if` it belongs to, and stops at the enclosing declaration so a conceal written in some
    /// other computed property never counts as this one's.
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

            for file in swiftFiles {
                let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                let source = Self.stripped(text)
                filesRead += 1

                for index in source.code.indices {
                    guard let column = Self.donutMatch(at: index, in: source.code) else { continue }
                    guard !Self.isConcealed(at: index, column: column, in: source.code) else { continue }
                    offenders.append(PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1, pattern: "SectorMark(",
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
        // Ungated, in both spellings that compile.
        for (name, call) in ["plain": "SectorMark(angle: .value(\"Value\", slice.value))",
                             "space before paren": "SectorMark (angle: .value(\"Value\", slice.value))"] {
            let fixture = [
                "var body: some View {",
                "    Chart(slices) { slice in",
                "        " + call,
                "    }",
                "}",
            ]
            let code = Self.stripped(fixture.joined(separator: "\n")).code
            guard let column = Self.donutMatch(at: 2, in: code) else {
                XCTFail("the sweep no longer sees a donut in the \(name) fixture: \(call)")
                continue
            }
            XCTAssertFalse(
                Self.isConcealed(at: 2, column: column, in: code),
                "the sweep called an unconcealed \(name) donut concealed"
            )
        }

        // The two conceal shapes the codebase uses: the flat `else if` chain (`AllocationChart`,
        // `CashFlowView`) and the `ZStack` + inner `if` (`MacDashboardView`).
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
        ]
        for (name, (fixture, line)) in concealed {
            let code = Self.stripped(fixture.joined(separator: "\n")).code
            guard let column = Self.donutMatch(at: line, in: code) else {
                XCTFail("the sweep no longer sees the donut in the \(name) fixture")
                continue
            }
            XCTAssertTrue(
                Self.isConcealed(at: line, column: column, in: code),
                "the sweep would now report the \(name) conceal, which is the codebase's own"
            )
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
        let siblingCode = Self.stripped(sibling.joined(separator: "\n")).code
        guard let siblingColumn = Self.donutMatch(at: 4, in: siblingCode) else {
            return XCTFail("the sweep no longer sees the sibling-gate fixture's donut")
        }
        XCTAssertFalse(
            Self.isConcealed(at: 4, column: siblingColumn, in: siblingCode),
            "a privacy check on a sibling row counts as the chart's gate"
        )

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
        let elsewhereCode = Self.stripped(elsewhere.joined(separator: "\n")).code
        guard let elsewhereColumn = Self.donutMatch(at: 8, in: elsewhereCode) else {
            return XCTFail("the sweep no longer sees the other-declaration fixture's donut")
        }
        XCTAssertFalse(
            Self.isConcealed(at: 8, column: elsewhereColumn, in: elsewhereCode),
            "a conceal written in another computed property counts as this chart's gate"
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
    /// share-of-total helper (`DesignSystem.swift:555`) and the Sankey node's VoiceOver value
    /// builder (`SankeyDiagramView.swift:476`). It is also the widest hole in the sweep: move a
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

    /// Whether a visible privacy gate covers this render.
    ///
    /// Two places count, and only two: the header of the block the render sits in — which is where
    /// `if !settings.isPrivacyMode {` lives — and the render's own expression. A gate anywhere else
    /// in the block is a *sibling's* gate. Accepting those is what let a live `MetricCard(… value:
    /// formattedPercent(…))` be dropped into `CryptoView`'s `LazyVGrid` with the suite still green,
    /// gated by nothing but the Holdings card's unrelated check three lines up.
    private static func isPrivacyGated(at index: Int, column: Int, in code: [[Character]]) -> Bool {
        let opener = enclosingBlockOpener(at: index, column: column, in: code)
        if blockHeader(openedAt: opener, in: code).contains(where: { String(code[$0]).contains(gateToken) }) {
            return true
        }

        let start = expressionStart(at: index, column: column, in: code, notBefore: opener)
        var expression = String(code[start.line].dropFirst(start.column))
        if start.line < index {
            expression += " " + (start.line + 1...index).map { String(code[$0]) }.joined(separator: " ")
        }
        return expression.contains(gateToken)
    }

    /// The only proportional-geometry primitive this codebase draws. `SectorMark (` with a space
    /// compiles and draws the same wedge as without, so the space is part of the spelling.
    private static let donutPattern = try! NSRegularExpression(pattern: #"\bSectorMark\s*\("#)

    /// Where a donut wedge is drawn on this line, if it is.
    private static func donutMatch(at index: Int, in code: [[Character]]) -> Int? {
        let line = String(code[index])
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = donutPattern.firstMatch(in: line, range: range),
              let matched = Range(match.range, in: line) else { return nil }
        return line.distance(from: line.startIndex, to: matched.lowerBound)
    }

    /// Whether a Privacy-Mode conceal branch encloses this chart.
    ///
    /// Deliberately more generous than `isPrivacyGated`, and for a reason that is specific to
    /// charts. A percentage's gate belongs on the percentage, so looking past its own block is how
    /// a sibling's check gets mistaken for its own. A chart's gate cannot sit that close: the mark
    /// is inside `Chart { … }`, which is inside the `else` of `if settings.isPrivacyMode { cover }
    /// else { chart }`, so the flag is always two or more blocks out. So this walks outward through
    /// the enclosing *block headers* — never sibling statements, which is what keeps the sibling
    /// hole closed — and resolves a `} else {` opener back to the `if` that opened the chain, since
    /// that is the line naming the flag. It stops at the enclosing declaration: a conceal written in
    /// a different computed property is not this chart's.
    private static func isConcealed(at index: Int, column: Int, in code: [[Character]]) -> Bool {
        let declaration = enclosingDeclaration(at: index, in: code) ?? 0
        var opener = enclosingBlockOpener(at: index, column: column, in: code)

        for _ in 0..<24 {
            if blockHeader(openedAt: opener, in: code).contains(where: { String(code[$0]).contains(gateToken) }) {
                return true
            }
            guard opener > declaration else { return false }

            let line = String(code[opener])
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("}") {
                // `} else {` / `} else if … {`: step to the `if` this chain hangs off.
                opener = enclosingBlockOpener(at: opener, column: 0, in: code)
            } else if let brace = line.firstIndex(of: "{") {
                opener = enclosingBlockOpener(at: opener, column: line.distance(from: line.startIndex, to: brace), in: code)
            } else {
                return false
            }
        }
        return false
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
