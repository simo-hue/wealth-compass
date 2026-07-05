import XCTest
@testable import WealthCompassMobile

/// T1 — currency conversion incl. the NaN/Inf/zero-rate guards (M1 extraction).
final class CurrencyConverterTests: XCTestCase {
    private func snapshot(_ rates: [String: Double]) -> ExchangeRateSnapshot {
        ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: rates,
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "test"
        )
    }

    func testConvertsThroughEuroBase() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertEqual(converter.convert(100, from: .eur, to: .usd), 110, accuracy: 0.0001)
        XCTAssertEqual(converter.convert(110, from: .usd, to: .eur), 100, accuracy: 0.0001)
    }

    func testCrossRateBetweenTwoNonBaseCurrencies() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1, "GBP": 0.85]))
        // 110 USD -> EUR(100) -> GBP(85)
        XCTAssertEqual(converter.convert(110, from: .usd, to: .gbp), 85, accuracy: 0.0001)
    }

    func testSameCurrencyIsUnchanged() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertEqual(converter.convert(Double(42), from: .usd, to: .usd), 42)
    }

    func testNilSourceReturnsValue() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertEqual(converter.convert(Double(42), from: nil, to: .usd), 42)
    }

    func testZeroRateGuardReturnsValueUnconverted() {
        // A zero rate must not yield Inf/NaN (which would corrupt chart geometry).
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 0]))
        XCTAssertEqual(converter.convert(Double(100), from: .usd, to: .eur), 100)
    }

    func testNonFiniteValueReturnsUnchanged() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertTrue(converter.convert(Double.nan, from: .eur, to: .usd).isNaN)
        XCTAssertEqual(converter.convert(Double.infinity, from: .eur, to: .usd), Double.infinity)
    }

    func testFallsBackToOfflineSeedWithoutSnapshot() {
        let converter = CurrencyConverter(snapshot: nil)
        let expected = 100.0 / 1.0 * Currency.usd.fallbackUnitsPerEuro
        XCTAssertEqual(converter.convert(100, from: .eur, to: .usd), expected, accuracy: 0.0001)
    }

    // MARK: - Decimal overload (WC-A1)

    func testDecimalConvertCrossesViaDoublePath() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertEqual(converter.convert(Decimal(100), from: .eur, to: .usd).doubleValue, 110, accuracy: 0.0001)
        // Same currency short-circuits, so it stays exactly equal (no Double round-trip).
        XCTAssertEqual(converter.convert(Decimal(42), from: .usd, to: .usd), Decimal(42))
    }

    func testDecimalConvertZeroRateReturnsValueUnconverted() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 0]))
        XCTAssertEqual(converter.convert(Decimal(100), from: .usd, to: .eur), Decimal(100))
    }

    // MARK: - MoneyParser (WC-H1 / WC-M9)

    func testMoneyParserRejectsNonFiniteAndEmpty() {
        for invalid in ["inf", "infinity", "nan", "1e400", "", "   ", "abc"] {
            XCTAssertNil(MoneyParser.decimal(from: invalid), "\(invalid) must be rejected")
        }
    }

    func testMoneyParserHonorsLocaleAndGrouping() {
        let expected = Decimal(string: "1234.56")
        XCTAssertEqual(MoneyParser.decimal(from: "1234.56", locale: Locale(identifier: "en_US")), expected)
        XCTAssertEqual(MoneyParser.decimal(from: "1,234.56", locale: Locale(identifier: "en_US")), expected)
        XCTAssertEqual(MoneyParser.decimal(from: "1.234,56", locale: Locale(identifier: "de_DE")), expected)
    }

    // MARK: - Decimal(finite:) result guard (deep-audit H9)

    func testDecimalFiniteRejectsNonFiniteDoubles() {
        XCTAssertNil(Decimal(finite: Double.nan))
        XCTAssertNil(Decimal(finite: Double.infinity))
        XCTAssertNil(Decimal(finite: -Double.infinity))
    }

    func testDecimalFiniteRejectsOverflowingFiniteDouble() {
        // 1e300 is a finite Double, but Decimal(1e300) is NSDecimalNumber.notANumber. Before the fix
        // this non-finite Decimal was accepted and could poison stored/synced money and chart geometry.
        XCTAssertNil(Decimal(finite: 1e300))
        XCTAssertNil(Decimal(finite: -1e300))
    }

    func testDecimalFiniteAcceptsRepresentableValues() {
        XCTAssertEqual(Decimal(finite: 1234.5), Decimal(1234.5))
        XCTAssertEqual(Decimal(finite: 0), Decimal(0))
    }

    // MARK: - Editor seed round-trips through MoneyParser (deep-audit H7)

    func testEditorSeedRoundTripsAcrossLocales() {
        // The seed string an editor pre-fills must parse back to the SAME Decimal under the SAME
        // locale. Pre-fix the seed was always POSIX ('.'), so in comma-decimal locales an untouched
        // 0.125 was re-parsed as 125 on first save. The app seeds and parses via Locale.current;
        // here we inject a locale into both ends to exercise the round-trip deterministically.
        let values = [Decimal(string: "0.125")!, Decimal(string: "1234.5")!, Decimal(string: "0.00000001")!]
        for id in ["it_IT", "de_DE", "en_US", "fr_FR"] {
            let locale = Locale(identifier: id)
            for value in values {
                let seed = AmountInputFormatter.string(value, locale: locale)
                XCTAssertEqual(
                    MoneyParser.decimal(from: seed, locale: locale), value,
                    "seed '\(seed)' for \(value) did not round-trip in \(id)"
                )
            }
        }
    }

    func testItalianSeedUsesCommaDecimalAndDoesNotInflate() {
        let locale = Locale(identifier: "it_IT")
        let seed = AmountInputFormatter.string(Decimal(string: "0.125")!, locale: locale)
        XCTAssertEqual(seed, "0,125", "it_IT seed must use a comma decimal separator")
        XCTAssertEqual(MoneyParser.decimal(from: seed, locale: locale), Decimal(string: "0.125"))
    }
}
