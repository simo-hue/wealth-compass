import SwiftUI
import XCTest
@testable import WealthCompassMobile

/// Privacy Mode has to redact percentages as well as amounts.
///
/// The leak is never in `AppSettings` — it is always at a call site. A row that masks its amount to
/// `••••` and then prints the live percentage beside it has handed the amount straight back: anyone
/// who knows one position's size can divide their way to the rest. So the load-bearing test in this
/// file is `testNoViewRendersAnUnguardedPercentage`, which reads the view sources and fails if any
/// render site reaches for the raw formatter again. The three above it pin the rule that test
/// enforces; only the source sweep can see the nine places the rule is actually applied.
///
/// Why a source sweep rather than a view test: `ValueDelta`, the donut centres and the Sankey
/// detail row are SwiftUI `View` bodies, and this project has no view-introspection dependency, so
/// there is no supported way to read back the `Text` a body produced. Asserting on
/// `settings.privatePercent(…)` in a test instead would only restate the helper — which is exactly
/// what the previous version of this file did, and why restoring the leak at all six `ValueDelta`
/// call sites still left the suite green.
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

    /// Directories whose files draw figures for a user who may be in Privacy Mode.
    ///
    /// `Shared/Export` is deliberately absent: a PDF or JSON export is an explicit act on the
    /// user's part and redacts nothing at all — it never mentions `isPrivacyMode` — so there is no
    /// masked amount there for a percentage to give away.
    private static let scannedDirectories = ["iOS", "macOS", "Shared/UI"]

    private struct PercentRender: CustomStringConvertible {
        let file: String
        let line: Int
        let source: String
        var description: String { "\(file):\(line): \(source)" }
    }

    /// Fails if any view prints a percentage that Privacy Mode does not cover.
    ///
    /// The rule a render site must satisfy is one of the two idioms already in the codebase: go
    /// through `settings.privatePercent(…)` — in which case there is no `formattedPercent(` here to
    /// find — or sit under a visible `isPrivacyMode` gate, whether an inline
    /// `settings.isPrivacyMode ? settings.redactionToken : …` or an enclosing
    /// `if !settings.isPrivacyMode { … }`.
    ///
    /// Limits worth knowing: it is a text sweep, so it reads braces literally (a `{` inside a
    /// string literal would mislead it) and it trusts an `isPrivacyMode` mention anywhere in the
    /// render's own block. It also needs the checked-out sources, which it finds relative to
    /// `#filePath`; it asserts it actually read them rather than skipping, because a sweep that
    /// silently scans nothing is worse than no sweep at all.
    func testNoViewRendersAnUnguardedPercentage() throws {
        let sources = URL(fileURLWithPath: #filePath)   // …/Tests/PrivacyRedactionTests.swift
            .deletingLastPathComponent()                // …/Tests
            .deletingLastPathComponent()                // …/WealthCompass
            .appendingPathComponent("Sources")

        var scanned: [PercentRender] = []
        var offenders: [PercentRender] = []

        for directory in Self.scannedDirectories {
            let root = sources.appendingPathComponent(directory)
            let swiftFiles = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "read no Swift files under \(root.path) — the sweep is not seeing the source tree"
            )

            for file in swiftFiles {
                let lines = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                    .components(separatedBy: "\n")
                for (index, line) in lines.enumerated() where line.contains("formattedPercent(") {
                    guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                    guard !Self.isStringHelper(at: index, in: lines) else { continue }

                    let render = PercentRender(
                        file: "Sources/\(directory)/\(file)", line: index + 1,
                        source: line.trimmingCharacters(in: .whitespaces)
                    )
                    scanned.append(render)
                    if !Self.isPrivacyGated(at: index, in: lines) { offenders.append(render) }
                }
            }
        }

        XCTAssertGreaterThanOrEqual(
            scanned.count, 8,
            "only \(scanned.count) percentage renders inspected — the sweep has stopped reaching the call sites"
        )
        XCTAssertEqual(
            offenders.map(\.description), [],
            """
            \(offenders.count) percentage(s) render live beside an amount Privacy Mode redacts. \
            Route each through `settings.privatePercent(…)`:
            \(offenders.map { "  " + $0.description }.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Sweep internals

    private static let declarationPattern = try! NSRegularExpression(
        pattern: #"^\s*(@\w+\s+)*((private|fileprivate|internal|public|open|static|final)\s+)*(func|var)\s+\w+"#
    )

    /// A `-> String` member is a formatter, not a render: `formattedPercent` itself, the two
    /// share-of-total helpers whose callers do the gating, and the VoiceOver value builders. Only
    /// what a `View` body prints can leak to the screen.
    private static func isStringHelper(at index: Int, in lines: [String]) -> Bool {
        guard let declaration = enclosingDeclaration(at: index, in: lines) else { return false }
        // The return clause can land a line or two below the name on a wrapped signature.
        return lines[declaration...min(declaration + 2, lines.count - 1)]
            .joined(separator: " ")
            .contains("-> String")
    }

    private static func enclosingDeclaration(at index: Int, in lines: [String]) -> Int? {
        for i in stride(from: index, through: 0, by: -1) {
            let line = lines[i]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if declarationPattern.firstMatch(in: line, range: range) != nil { return i }
        }
        return nil
    }

    private static func isPrivacyGated(at index: Int, in lines: [String]) -> Bool {
        let opener = enclosingBlockOpener(at: index, in: lines) ?? 0
        return lines[opener...index].contains { $0.contains("isPrivacyMode") }
    }

    /// The line carrying the `{` that opens the block this line sits in, found by walking upwards
    /// and letting closed blocks cancel out.
    private static func enclosingBlockOpener(at index: Int, in lines: [String]) -> Int? {
        var depth = 0
        for i in stride(from: index, through: 0, by: -1) {
            for character in lines[i].reversed() {
                if character == "}" {
                    depth += 1
                } else if character == "{" {
                    if depth == 0 { return i }
                    depth -= 1
                }
            }
        }
        return nil
    }
}
