import Foundation

/// Direct endpoints for the third-party data providers Wealth Compass contacts.
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
}
