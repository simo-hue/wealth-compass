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
}
