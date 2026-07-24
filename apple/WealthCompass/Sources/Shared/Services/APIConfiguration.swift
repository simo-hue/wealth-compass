import Foundation

/// Direct endpoints for the third-party data providers Wealth Compass Tracker contacts.
///
/// There is **no** intermediary server. Each request goes straight from the device
/// to the provider that issued the user's API key, so no developer-operated hop can
/// observe the user's keys, IP, or which symbols/coins they look up. This makes the
/// onboarding promise ("connect directly to data providers") literally true.
/// See H1 in `CODE_AUDIT.md`. The previous Cloudflare Worker proxy (`../proxy/`) is
/// no longer used by the app and can be retired.
enum APIConfiguration {
    /// ECB reference FX rates via Frankfurter (EUR base). Keyless, HTTPS.
    static let frankfurterRatesURL = "https://api.frankfurter.dev/v2/rates"

    /// Finnhub stock quotes. Authenticated with the user's `X-Finnhub-Token` header.
    static let finnhubQuoteURL = "https://finnhub.io/api/v1/quote"

    /// CoinGecko simple price. Authenticated with the user's `x-cg-demo-api-key` header.
    static let coinGeckoSimplePriceURL = "https://api.coingecko.com/api/v3/simple/price"

    /// CoinGecko coin search — resolves a ticker/name to a CoinGecko coin id when a holding has
    /// no explicit Coin ID and isn't in the built-in common map. Authenticated like /simple/price.
    static let coinGeckoSearchURL = "https://api.coingecko.com/api/v3/search"

    /// Yahoo Finance chart endpoint (keyless, HTTPS). Used as a fallback for instruments
    /// Finnhub's free tier can't price — notably European-listed ETFs (e.g. `VWCE.MI`).
    /// The resolved exchange-qualified symbol is appended to the path. Returns the live
    /// price *and* its native currency in `chart.result[0].meta`, so the refresh stores
    /// the value in the holding's own currency instead of assuming USD.
    static let yahooChartURL = "https://query1.finance.yahoo.com/v8/finance/chart/"

    /// Yahoo Finance symbol search (keyless, HTTPS). Resolves a bare symbol or ISIN to a
    /// concrete exchange-qualified listing when the holding doesn't already carry a suffix.
    static let yahooSearchURL = "https://query1.finance.yahoo.com/v1/finance/search"
}
