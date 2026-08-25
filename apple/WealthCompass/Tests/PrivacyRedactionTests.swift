import XCTest
@testable import WealthCompassMobile

/// Privacy Mode has to redact percentages as well as amounts.
///
/// The gain/loss rows in Investments and Crypto print an amount and a performance percentage as one
/// pair. While only the amount was redacted, the pair gave the hidden figure straight back: `••••
/// (+12.4%)` beside a position whose size the reader knows is an arithmetic exercise, not a secret.
/// `privatePercent` is the rule the summary cards already applied inline, in one place, so the
/// shared `ValueDelta` row can follow it too.
@MainActor
final class PrivacyRedactionTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
    }

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

    func testPrivatePercentFormatsNormallyWhilePrivacyModeIsOff() {
        let settings = makeSettings()
        settings.isPrivacyMode = false

        // Compared against the shared formatter rather than a literal, so the assertion holds in
        // whatever locale the test host runs under.
        XCTAssertEqual(
            settings.privatePercent(12.4),
            formattedPercent(12.4, locale: settings.effectiveLocale)
        )
        XCTAssertNotEqual(settings.privatePercent(12.4), settings.redactionToken)
    }

    /// The leak was in the pair, not in either half alone: both sides of a gain/loss row have to go
    /// at once, or the surviving one reconstructs the other.
    func testGainLossPairLeavesNothingLegible() {
        let settings = makeSettings()
        settings.isPrivacyMode = true

        let amount = settings.privateCurrency(Decimal(1_234.56), sourceCurrency: .eur)
        let percent = settings.privatePercent(12.4)

        XCTAssertEqual(amount, settings.redactionToken)
        XCTAssertEqual(percent, settings.redactionToken)
        // The exact string `ValueDelta` composes from the two.
        XCTAssertFalse(
            "\(amount) (\(percent))".contains(where: \.isNumber),
            "a digit reached the rendered delta while Privacy Mode was on"
        )
    }
}
