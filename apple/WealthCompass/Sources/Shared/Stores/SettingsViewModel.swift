import Foundation

/// Shared settings logic for iOS + macOS (M2, logic-first consolidation).
///
/// The settings *screens* are intentionally platform-specific (iOS `Form` vs macOS
/// grouped sections) and most of their state is already backed by the shared
/// `AppSettings`. The one genuinely-duplicated, self-contained, testable piece is
/// market-data credential validation (fetch a live quote, return a localized success
/// message), which both credential editors now delegate here.
enum SettingsViewModel {
    enum MarketDataProvider {
        case finnhub
        case coingecko
    }

    /// Validates an API key by fetching a live quote from its provider, returning a
    /// localized success message. Throws (provider/auth/network error) if invalid.
    static func validateMarketDataKey(
        _ provider: MarketDataProvider,
        apiKey: String,
        appLanguage: String?
    ) async throws -> String {
        switch provider {
        case .finnhub:
            let quote = try await FinnhubQuoteClient(apiKey: apiKey).testConnection()
            // `quote.currency` rather than a hardcoded USD: `MarketPriceQuote` carries the
            // currency the provider actually answered in precisely so callers need not guess.
            return successMessage(
                .finnhub,
                price: quote.price,
                currency: quote.currency ?? .usd,
                appLanguage: appLanguage
            )
        case .coingecko:
            let quote = try await CoinGeckoPriceClient(apiKey: apiKey).testConnection()
            // CoinGecko is asked for EUR (`CoinGeckoPriceClient.currencies` defaults to
            // `[.eur]`), so formatting the answer as USD put a euro amount behind a dollar sign.
            return successMessage(
                .coingecko,
                price: quote.price,
                currency: quote.currency ?? .eur,
                appLanguage: appLanguage
            )
        }
    }

    /// The localized confirmation sentence for a validated key.
    ///
    /// Split out from the network call above so the *rendering* can be asserted without a live
    /// provider — the fetch is the only reason `validateMarketDataKey` is `async throws`, and
    /// nothing about the sentence depends on it.
    static func successMessage(
        _ provider: MarketDataProvider,
        price: Decimal,
        currency: Currency,
        appLanguage: String?
    ) -> String {
        // `.locale(...)` is load-bearing. Without it the figure resolves against
        // `Locale.autoupdatingCurrent` — the *system* language, which the in-app language override
        // deliberately does not follow — while the sentence around it is resolved for `appLanguage`,
        // so an Italian confirmation came back reading `$1,234.56`.
        // `RecurringNotificationService.content(for:…)` already does this (the L49 fix).
        let amount = price.formatted(
            .currency(code: currency.rawValue)
                .locale(AppLocalization.effectiveLocale(appLanguage: appLanguage))
        )
        switch provider {
        case .finnhub:
            return AppLocalization.string(
                "Finnhub returned a live AAPL quote at \(amount).",
                appLanguage: appLanguage
            )
        case .coingecko:
            return AppLocalization.string(
                "CoinGecko returned a live Bitcoin price at \(amount).",
                appLanguage: appLanguage
            )
        }
    }
}
