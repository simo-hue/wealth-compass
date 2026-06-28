# TO SIMO DO

This document tracks manual actions and considerations for you to address.

- [ ] Onboarding tutorial for inserting the API KEY for the tracking of the assets for both macOS and iOS.

- [ ] **Verify the Yahoo ETF-price fallback on Xcode** (this machine has only Command Line Tools, so `xcodebuild`/XCTest could not run). Steps:
  - Build both schemes: `WealthCompassMobile` and `WealthCompassMac`.
  - Run the new tests: `xcodebuild test -scheme WealthCompassMobile -only-testing:WealthCompassTests/MarketDataServiceTests -destination 'platform=iOS Simulator,name=iPhone 16'`.
  - Smoke-test a real refresh: with a Finnhub key set and VWCE in the portfolio, trigger a price update and confirm it now reports **3 updated** (not 2). The decoder/scorer logic was already verified green with the standalone `swift` toolchain, but the live Yahoo endpoints (unofficial) should be confirmed against the real API.
- [ ] *(Optional, improves accuracy)* Set VWCE's ISIN to `IE00BK5BQT80` in the investment editor. Not required — the bare-symbol search already resolves it — but the ISIN makes the listing lookup exact.


---
