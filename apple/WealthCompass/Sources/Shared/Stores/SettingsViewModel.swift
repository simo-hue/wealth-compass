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
            return AppLocalization.string(
                "Finnhub returned a live AAPL quote at \(quote.price.formatted(.currency(code: Currency.usd.rawValue))).",
                appLanguage: appLanguage
            )
        case .coingecko:
            let quote = try await CoinGeckoPriceClient(apiKey: apiKey).testConnection()
            return AppLocalization.string(
                "CoinGecko returned a live Bitcoin price at \(quote.price.formatted(.currency(code: Currency.usd.rawValue))).",
                appLanguage: appLanguage
            )
        }
    }
}
