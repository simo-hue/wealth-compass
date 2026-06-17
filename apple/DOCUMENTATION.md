# Documentation

- [2026-06-12 08:14]: Cloudflare Worker BFF Proxy Integration
  - *Details*: Abstracted the hardcoded external API URLs for Frankfurter, Finnhub, and CoinGecko into a Cloudflare Worker Proxy backend.
  - *Tech Notes*:
    - Created a Cloudflare Worker (`proxy/` directory) acting as an API Gateway.
    - Added `APIConfiguration.swift` to `WealthCompass/Sources/Shared/Services/` to store the Base URL.
    - Updated `ExchangeRateService.swift` and `MarketDataService.swift` to route requests through `/api/rates`, `/api/quote`, and `/api/price` endpoints using `APIConfiguration.proxyBaseURL`.
- [2026-06-12 08:17]: Proxy Backend Deployment
  - *Details*: Deployed the Cloudflare worker and injected the production URL into the Swift codebase.
  - *Tech Notes*: `APIConfiguration.proxyBaseURL` is now mapped to `https://wealthcompass-api-proxy.mattioli-simone-10.workers.dev`.
- [2026-06-12 18:40]: Exchange Rate System — 7 Improvements
  - *Details*: Comprehensive hardening of the exchange rate refresh pipeline across iOS and macOS. Addressed: periodic background refresh, file-based persistence, exponential backoff, persisted retry state, safe URL construction, and code deduplication via shared helper.
  - *Tech Notes*:
    - **New file**: `ExchangeRatePersistence.swift` in `Shared/Persistence/` — file-based persistence in Application Support, with auto-migration from the old UserDefaults key.
    - **Periodic timer**: 5-hour `Timer.publish` on both iOS (`ContentView.swift`) and macOS (`MacRootView.swift`) ensures staleness checks run even when the app stays open for days.
    - **Exponential backoff**: `shouldAutoRefreshExchangeRates()` now uses `15min × 2^min(failures, 4)` retry intervals, capping at ~4 hours. Failure count persisted to UserDefaults.
    - **Persisted retry timestamp**: `lastExchangeRateRefreshAttemptAt` now saved to UserDefaults, surviving force-quit within retry window.
    - **Safe URL**: Force-unwrap `URLComponents(string:)!` replaced with `guard let` throwing `ExchangeRateError.invalidURL`.
    - **Shared helper**: `AppSettings.refreshExchangeRatesAndRecalculate(finance:showResult:)` consolidates the "refresh → didChangeRates → takeSnapshot" pattern previously duplicated in 4 views.
    - **Xcode project**: `ExchangeRatePersistence.swift` registered in both `WealthCompassMobile` and `WealthCompassMac` targets.

- [2026-06-17 08:49:00]: Version Bump
  - *Details*: Aggiornata la versione dell'app per iOS e macOS.
  - *Tech Notes*: Modificato `project.pbxproj` per impostare `MARKETING_VERSION = 1.0.4` e `CURRENT_PROJECT_VERSION = 5`.
