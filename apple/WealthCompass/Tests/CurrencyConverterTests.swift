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
        XCTAssertEqual(converter.convert(42, from: .usd, to: .usd), 42)
    }

    func testNilSourceReturnsValue() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertEqual(converter.convert(42, from: nil, to: .usd), 42)
    }

    func testZeroRateGuardReturnsValueUnconverted() {
        // A zero rate must not yield Inf/NaN (which would corrupt chart geometry).
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 0]))
        XCTAssertEqual(converter.convert(100, from: .usd, to: .eur), 100)
    }

    func testNonFiniteValueReturnsUnchanged() {
        let converter = CurrencyConverter(snapshot: snapshot(["USD": 1.1]))
        XCTAssertTrue(converter.convert(.nan, from: .eur, to: .usd).isNaN)
        XCTAssertEqual(converter.convert(.infinity, from: .eur, to: .usd), .infinity)
    }

    func testFallsBackToOfflineSeedWithoutSnapshot() {
        let converter = CurrencyConverter(snapshot: nil)
        let expected = 100.0 / 1.0 * Currency.usd.fallbackUnitsPerEuro
        XCTAssertEqual(converter.convert(100, from: .eur, to: .usd), expected, accuracy: 0.0001)
    }
}
