import XCTest
@testable import WealthCompassMobile

/// Yahoo prices every non-USD holding outright (Finnhub's `/quote` reports no currency, H13) and
/// takes over on `.noQuote` — the VWCE / European-ETF case. Covers the JSON decoders, the
/// GBp(pence) normalization, and the candidate disambiguation. The network cascade itself is thin
/// glue over these pure parts.
final class MarketDataServiceTests: XCTestCase {
    private func json(_ string: String) -> Data { string.data(using: .utf8)! }

    // MARK: - Chart decode

    func testDecodeChartReadsPriceCurrencyAndTime() throws {
        let quote = try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":[{"meta":{"currency":"EUR","symbol":"VWCE.MI","regularMarketPrice":123.45,"regularMarketTime":1717621200}}],"error":null}}"#),
            requestedSymbol: "VWCE.MI"
        )
        XCTAssertEqual(quote.price, Decimal(string: "123.45"))
        XCTAssertEqual(quote.currency, .eur)
        XCTAssertEqual(quote.asOf, Date(timeIntervalSince1970: 1_717_621_200))
        XCTAssertEqual(quote.provider, "Yahoo Finance")
    }

    func testDecodeChartNormalizesLondonPenceToMajorUnits() throws {
        // Yahoo quotes some LSE listings in pence ("GBp"); the stored price must not be 100× off.
        let quote = try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":[{"meta":{"currency":"GBp","regularMarketPrice":9000.0,"regularMarketTime":1717621200}}]}}"#),
            requestedSymbol: "VWRL.L"
        )
        XCTAssertEqual(quote.price, Decimal(string: "90"), "pence must divide exactly, with no binary drift")
        XCTAssertEqual(quote.currency, .gbp)
    }

    /// A provider price must reach storage with every digit intact (WC-A1).
    ///
    /// `MarketPriceQuote.price` was a `Double`, and the refresh wrote it through `Decimal(Double)`
    /// — which is not exact for ordinary money. Each literal below is one `Decimal(Double)` mangles;
    /// `1234.56` becomes `1234.5599999999997952`. That value was then stored in the database and
    /// written to the user's backup, and it is the exact corruption class `FinanceJSONCoding` was
    /// rewritten to eliminate, reintroduced at the market-data ingest point.
    ///
    /// Asserted with `Decimal(string:)`, never a float literal: `Decimal`'s
    /// `ExpressibleByFloatLiteral` conformance goes through `Double`, so `Decimal` written as
    /// `1234.56` in source *is* the mangled value and the assertion would pass either way.
    func testDecodeChartKeepsThePriceExact() throws {
        for literal in ["1234.56", "105.07", "0.1", "99999999.99", "1.005"] {
            let quote = try YahooQuoteClient.decodeChart(
                json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":\#(literal)}}]}}"#),
                requestedSymbol: "X"
            )
            XCTAssertEqual(
                quote.price, Decimal(string: literal),
                "\(literal) did not survive the decode exactly"
            )
            // The drift this guards against is ~1e-13, far below any `accuracy:` an assertion
            // would plausibly use, so compare the rendered digits too.
            XCTAssertEqual("\(quote.price)", literal, "\(literal) decoded as \(quote.price)")
        }
    }

    /// The I1 no-churn guard compares the stored price against the incoming one, so drift also
    /// meant a hand-entered price never matched its own refreshed value — every refresh rewrote
    /// the record, bumped `updatedAt` and re-uploaded it to CloudKit.
    func testARefreshedPriceMatchesTheSameHandEnteredPrice() throws {
        let handEntered = Decimal(string: "1234.56")!
        let quote = try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":1234.56}}]}}"#),
            requestedSymbol: "X"
        )
        XCTAssertEqual(quote.price, handEntered, "an unchanged price must compare equal, or it churns")
        XCTAssertNotEqual(
            handEntered, Decimal(1234.56),
            "sanity: the old Double bridge really does produce a different value"
        )
    }

    func testDecodeChartThrowsOnProviderError() {
        XCTAssertThrowsError(try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":null,"error":{"code":"Not Found","description":"delisted"}}}"#),
            requestedSymbol: "X"
        ))
    }

    func testDecodeChartThrowsOnZeroPrice() {
        // Same guard Finnhub uses: a zero/blank quote is "no usable quote", not a price of 0.
        XCTAssertThrowsError(try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":0}}]}}"#),
            requestedSymbol: "X"
        ))
    }

    func testDecodeChartThrowsOnUnknownCurrency() {
        // An unmodelled currency fails cleanly (a safe no-update) rather than storing a wrong value.
        XCTAssertThrowsError(try YahooQuoteClient.decodeChart(
            json(#"{"chart":{"result":[{"meta":{"currency":"ZZZ","regularMarketPrice":10}}]}}"#),
            requestedSymbol: "X"
        ))
    }

    // MARK: - Search decode + disambiguation

    private let vwceSearchJSON = #"""
    {"quotes":[
     {"symbol":"VWCE.MI","quoteType":"ETF","shortname":"VANG FTSE AW","longname":"Vanguard FTSE All-World UCITS ETF","exchange":"MIL","currency":"EUR"},
     {"symbol":"VWCE.DE","quoteType":"ETF","shortname":"VANG FTSE AW","longname":"Vanguard FTSE All-World UCITS ETF USD Accumulating Shares","exchange":"GER","currency":"EUR"},
     {"symbol":"VWCE.SW","quoteType":"ETF","longname":"Vanguard FTSE All-World UCITS ETF","currency":"CHF"},
     {"symbol":"VWCE-NEWS","quoteType":"News"}
    ],"news":[]}
    """#

    func testDecodeSearchAndDisambiguationPicksMatchingEuroListing() throws {
        let candidates = try YahooQuoteClient.decodeSearch(json(vwceSearchJSON))
        XCTAssertEqual(candidates.count, 4)

        let best = YahooQuoteClient.bestCandidate(candidates, preferredCurrency: .eur, name: "VWCE All World")
        XCTAssertEqual(best?.symbol, "VWCE.MI")          // closest name among the EUR listings
        XCTAssertEqual(best?.currency, "EUR")            // currency match preferred (avoids an FX hop)
        XCTAssertEqual(best?.quoteType?.uppercased(), "ETF") // the News row is never selected
    }

    func testDisambiguationFiltersNonEquityTypes() throws {
        let candidates = try YahooQuoteClient.decodeSearch(json(vwceSearchJSON))
        XCTAssertEqual(candidates.first { $0.symbol == "VWCE-NEWS" }?.isEquityLike, false)
    }

    func testDisambiguationFallsBackToNameWhenNoCurrency() {
        // Yahoo search often omits currency; selection must still find the right fund by name.
        let candidates = [
            YahooSearchCandidate(symbol: "VWCE.MI", quoteType: "ETF", shortName: nil, longName: "Vanguard FTSE All-World UCITS ETF", currency: nil),
            YahooSearchCandidate(symbol: "FOO", quoteType: "EQUITY", shortName: nil, longName: "Foo Incorporated", currency: nil)
        ]
        XCTAssertEqual(YahooQuoteClient.bestCandidate(candidates, preferredCurrency: .eur, name: "VWCE All World")?.symbol, "VWCE.MI")
    }

    func testBestCandidateReturnsNilForEmptyPool() {
        XCTAssertNil(YahooQuoteClient.bestCandidate([], preferredCurrency: .eur, name: "x"))
    }

    func testNameSimilarityRewardsTokenOverlap() {
        let strong = YahooQuoteClient.nameSimilarity("Vanguard FTSE All-World UCITS ETF", "VWCE All World")
        let none = YahooQuoteClient.nameSimilarity("Apple Inc", "VWCE All World")
        XCTAssertGreaterThan(strong, none)
        XCTAssertEqual(none, 0, accuracy: 0.0001)
    }

    // MARK: - CoinGecko symbol resolution (I2)

    func testCoinGeckoSearchDecodeAndResolveMostProminent() throws {
        let coins = try CoinGeckoPriceClient.decodeSearch(json(#"""
        {"coins":[
         {"id":"sonic-3","name":"Sonic","symbol":"S","market_cap_rank":50},
         {"id":"some-other-s","name":"Some Other S","symbol":"S","market_cap_rank":1200},
         {"id":"sui","name":"Sui","symbol":"SUI","market_cap_rank":15}
        ]}
        """#))
        XCTAssertEqual(coins.count, 3)
        XCTAssertEqual(coins.first { $0.id == "sonic-3" }?.marketCapRank, 50) // snake_case decoded
        // Ticker "S" collides; pick the highest-ranked (lowest number), case-insensitively.
        XCTAssertEqual(CoinGeckoPriceClient.bestCoinID(coins, symbol: "s", name: "Sonic"), "sonic-3")
        XCTAssertNil(CoinGeckoPriceClient.bestCoinID(coins, symbol: "ZZZ", name: ""))
    }

    func testCoinGeckoResolutionFallsBackToUniqueName() {
        let coins = [
            CoinGeckoSearchCoin(id: "unique-coin", symbol: "UQ", name: "Unique Coin", marketCapRank: 900),
            CoinGeckoSearchCoin(id: "other", symbol: "OT", name: "Other", marketCapRank: nil)
        ]
        XCTAssertEqual(CoinGeckoPriceClient.bestCoinID(coins, symbol: "NOPE", name: "Unique Coin"), "unique-coin")
    }

    func testCoinGeckoResolutionRefusesAmbiguousName() {
        // Two coins share the name → don't guess; return nil so the holding is skipped, not mispriced.
        let coins = [
            CoinGeckoSearchCoin(id: "a", symbol: "AAA", name: "Token", marketCapRank: nil),
            CoinGeckoSearchCoin(id: "b", symbol: "BBB", name: "Token", marketCapRank: nil)
        ]
        XCTAssertNil(CoinGeckoPriceClient.bestCoinID(coins, symbol: "NOPE", name: "Token"))
    }
}
