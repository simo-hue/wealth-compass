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
- [ ] **Verify the iCloud sync status-UX batch on Xcode** (status-severity model + CKError taxonomy). 
  - Build both schemes; run `xcodebuild test -scheme WealthCompassMobile -only-testing:WealthCompassTests/CloudSyncCoreTests -destination 'platform=iOS Simulator,name=iPhone 16'` (new `testSyncStatusRoutesEachCategoryToTheRightToneAndSeverity` + extended `testFailureCategoryMapsCKErrorCodes`).
  - **Visual check** in Settings on both platforms: the status row now shows an SF Symbol + severity color. Confirm the layout is fine with the new `Label`/`LabeledContent` shape. Best smoke test: turn on Airplane Mode with sync enabled → the status should read a calm grey **"Waiting to Sync" / "You're offline…"**, NOT a red "Sync Error".
  - **Localize new strings** in `Sources/Shared/Resources/Localizable.xcstrings` (~40 languages): `"Waiting to Sync"`, `"Action Needed"`, and the new `.waiting`/`.actionNeeded` message copy (offline / connection-lost / temporarily-unavailable / busy / preparing / storage-full / restricted). Until translated they fall back to English.
- [ ] **Verify the sync write-hygiene batch on Xcode** (#11 snapshot amplification + #12 metadata compaction).
  - Run `xcodebuild test -scheme WealthCompassMobile -only-testing:WealthCompassTests/SnapshotEngineTests -only-testing:WealthCompassTests/AnalyticsEngineTests -only-testing:WealthCompassTests/CloudSyncCoreTests -destination 'platform=iOS Simulator,name=iPhone 16'`.
  - **Eyeball the net-worth chart** (Dashboard, all ranges, both platforms): it must still be **continuous and flat across inactivity** — the carry-forward now happens at render instead of from stored rows. A gap longer than ~60 days now renders flat (previously it sloped); confirm that reads correctly. Existing users keep their already-stored backfill rows (harmless duplicates on flat runs); only new gaps are render-filled.
  - *(Optional)* Note the metadata file (`wealth-compass-cloud-sync.json`) is now minified and self-compacts settled tombstones on each write — its size should stop growing with churn.
- [ ] **Verify the sync dedup (#13) on two devices** — this is engine-event-driven, so it can't be unit-tested (only the pure gate is). Confirm:
  - **Foregrounding still pulls remote changes**: change data on device A; bring device B to the foreground; B should still reflect A's change (the opportunistic sync must not be permanently suppressed). Status should reach "Up to Date".
  - **Force Sync always works**, even while a sync is already running (it's intentionally not gated).
  - The dedup itself is invisible (just fewer redundant fetch/send round-trips) — the thing to watch for is a *regression*: if foregrounding ever stops pulling changes, the `engineSyncActivity` counter may not be balancing against real CKSyncEngine will/did events (it resets on engine teardown / app relaunch as a safety net).


---
