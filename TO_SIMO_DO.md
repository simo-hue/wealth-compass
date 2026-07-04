# TO SIMO DO

This document tracks manual actions and considerations for you to address.

- [ ] Onboarding tutorial for inserting the API KEY for the tracking of the assets for both macOS and iOS.

- [ ] **Verify the Yahoo ETF-price fallback on Xcode** (this machine has only Command Line Tools, so `xcodebuild`/XCTest could not run). Steps:
  - Build both schemes: `WealthCompassMobile` and `WealthCompassMac`.
  - Run the new tests: `xcodebuild test -scheme WealthCompassMobile -only-testing:WealthCompassTests/MarketDataServiceTests -destination 'platform=iOS Simulator,name=iPhone 16'`.
  - Smoke-test a real refresh: with a Finnhub key set and VWCE in the portfolio, trigger a price update and confirm it now reports **3 updated** (not 2). The decoder/scorer logic was already verified green with the standalone `swift` toolchain, but the live Yahoo endpoints (unofficial) should be confirmed against the real API.
- [ ] **Verify the sync-audit batch on Xcode** (same build constraint). After building + running `MarketDataServiceTests`, smoke-test these live behaviours:
  - **"Last updated" now moves**: refresh prices and confirm the per-row date on the investments page updates to today (the bug you reported). Note: with the sync-churn guard (I1), a row whose price *didn't* change won't move its date — that's intended.
  - **Crypto "S" resolves**: the `S` holding that previously showed "CoinGecko ID missing" should now price via CoinGecko `/search` (confirm the live `/search` actually returns the coin you hold for the ticker `S` — verify it picked the right coin, since tickers collide).
  - **Keyless Yahoo (I3)**: temporarily clear the Finnhub key and confirm investments still update via Yahoo (instead of all being skipped).
- [ ] **Verify the professional-hardening batch on Xcode** (same build constraint). 
  - Run the full sync suite: `xcodebuild test -scheme WealthCompassMobile -only-testing:WealthCompassTests/CloudSyncCoreTests -destination 'platform=iOS Simulator,name=iPhone 16'` (includes the new `testBootstrapDecisionTieBreakIsConvergentAcrossDevices`), plus `MarketDataServiceTests`.
  - **Currency unification — no regression**: confirm a USD holding priced by Finnhub and a EUR holding priced by Yahoo both still show correct values after a refresh (the conversion now runs through one `storedPrice` boundary; `nil`/same-currency must be a no-op). Standalone Swift verified the rule (11/11), but confirm against live data.
- [ ] *(Optional, improves accuracy)* Set VWCE's ISIN to `IE00BK5BQT80` in the investment editor. Not required — the bare-symbol search already resolves it — but the ISIN makes the listing lookup exact. Likewise, for any crypto whose ticker is ambiguous, setting an explicit Coin ID avoids the `/search` guess.


---
