# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository orientation

This directory (`apple/`) is the **native Apple implementation** of Wealth Compass, a personal net-worth / finance tracker. It is one Xcode project with two independent native app targets plus a test target:

- `WealthCompassMobile` — SwiftUI, iPhone, iOS 17+
- `WealthCompassMac` — native SwiftUI for macOS 14+ (no Mac Catalyst; built against the macOS SDK with sidebar navigation, tables, menus, keyboard shortcuts, an in-window Settings page, and sandbox entitlements)
- `WealthCompassTests` — XCTest unit tests

The **sibling directory** (`../web-app/`) is a separate React + Vite + Supabase web app that shares the product but no code; it is built and deployed entirely from within that directory (`cd web-app && npm run deploy` — manual, no CI workflow) and nothing in it touches this one. The **parent directory** (`../`) is just the container holding both platforms plus repo-wide docs. The JSON backup format is the interchange point between the web and Apple apps (see the import path in `FinanceStore`).

There is **no** Swift Package Manager / CocoaPods and there are no third-party dependencies — everything is Apple frameworks (SwiftUI, CloudKit, CryptoKit, Security, OSLog, UIKit/AppKit).

## Build & test

All `xcodebuild` commands assume the current directory is `apple/` (this folder).

```bash
# Build macOS
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
  -destination 'platform=macOS' build

# Build iOS
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'generic/platform=iOS Simulator' build
```

Tests are hosted by the Mobile app (`TEST_HOST` → `WealthCompassMobile.app`, `@testable import WealthCompassMobile`) and are wired only into the **WealthCompassMobile** scheme, so they run on an iOS Simulator:

```bash
# Run all tests (use a concrete simulator name/id that exists on this machine)
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

A destination that doesn't exist on the machine exits **70** with "Unable to find a device matching the
provided destination specifier" — check `xcrun simctl list devices available` rather than assuming a name.

⚠️ **Do not narrow with `-only-testing:` in this project.** The per-method form
`-only-testing:WealthCompassTests/<Class>/<method>` selects **zero** tests here and still prints
`** TEST SUCCEEDED **` — a test containing an unconditional `XCTFail` "passes" under it. Any
before/after check run that way is vacuous. **Run the full suite** for every verification, especially
for proving a new test fails against the pre-fix code; it takes about two minutes and it actually
executes the tests. (The class-level form is no safer to trust.) See `TO_SIMO_DO.md` → "A trap worth
knowing about".

⚠️ **Trust the test count, not the exit status, and not the log.** Both other signals have been caught
lying on this project: a run with a genuine failure **exited 0 while printing `** TEST FAILED **`**, and
individual `Test case … passed` lines drop intermittently from the output, so scraping the log has twice
read 277 against a true 278. Get the authoritative numbers from the result bundle:

```bash
xcrun xcresulttool get test-results summary --path <path>.xcresult
```

A fix is only proven when the count moves the way you predicted — one new test failing before, passing
after, with every other test unchanged.

**`build` and `test` do not touch `Localizable.xcstrings`. `-exportLocalizations` does.** Both halves
are load-bearing, and an earlier version of this section had the first half right for the wrong reason
and did not mention the second at all.

Building and testing leave the catalog alone, despite `SWIFT_EMIT_LOC_STRINGS = YES` on all four
configurations. Measured five ways, checking the file's SHA **and** `git status` before and after each:

| run | catalog |
| --- | --- |
| full `xcodebuild test`, warm DerivedData | unchanged |
| full `xcodebuild test`, scratch `-derivedDataPath` (cold, the command above verbatim) | unchanged |
| `xcodebuild build` (Mobile, `generic/platform=iOS Simulator`), scratch `-derivedDataPath` | unchanged |
| the same, plus a brand-new `Text("…")` literal absent from the catalog | unchanged |
| `xcodebuild build` (Mac, `platform=macOS`), scratch `-derivedDataPath`, same new literal | unchanged |

The fourth and fifth rows are the ones that matter: a *new* string is the case that would make a
write-back necessary, and it still does not happen. What those rows show is that **`SWIFT_EMIT_LOC_STRINGS`
only emits `.stringsdata` into DerivedData** — merging that back into the source catalog is a separate
step, the one `xcrun xcstringstool sync <xcstrings> --stringsdata …` exposes, and a build never runs it.

**`xcodebuild -exportLocalizations` runs it.** Run three times: once on a pristine tree with zero
source changes, which is the row in the table below, and twice more with a handful of entries marked
`manual` to find out what protects a key.

```
xcodebuild -exportLocalizations -project WealthCompass/WealthCompass.xcodeproj \
  -localizationPath <dir> -exportLanguage en
```

| | before | after |
| --- | --- | --- |
| keys | 791 | **727** (64 removed) |
| `extractionState: "stale"` | 42 | 66 (24 newly marked) |
| translated bodies | 20558 | 20558 |

Read those three rows together, because the headline number is the least important of them. **No
translation is lost**: every one of the 64 removed keys carries zero localizations, and the 24 keys the
sync could not find in the `.stringsdata` that *do* carry translations are marked `stale` and kept
verbatim. What is destroyed is 64 English key registrations — and **60 of the 64 are
`ReportDocumentBuilder.swift`'s**, reached through its `L(_ key: String)` wrapper (`:200`), which takes a
plain `String` and builds the `String.LocalizationValue` at runtime. The extractor sees a `String`
argument at those call sites, not a localizable literal, so as far as the sync is concerned those 60
strings are used by nobody. The export half-says so, twice, and it is easy to read past — though note
what it actually names, which is `AppLocalization.string`'s own `String(localized: key, …)` and not the
60 call sites. It tells you non-literal keys exist; it does not tell you which strings they cost you:

```
WARNING: …/AppLocalization.swift:11:24:3 Skipping extraction of localizable string with non-literal key
```

The effect is measured; the mechanism is inferred. `xcstringstool` does not appear anywhere in the
export's log, so what is verified is that `-exportLocalizations` performs that sync, not that it shells
out to that binary to do it.

**So, in order of preference:**

1. **Don't run `-exportLocalizations` as part of anything.** It is not a build step and not a test step;
   nothing in this repo needs it. The catalog is hand-maintained and spliced additively.
2. **If you need an `.xcloc` for a translator**, run it on a clean tree, then restore the catalog
   deliberately and read the diff first — `git diff --stat` then `git checkout -- …/Localizable.xcstrings`.
   That is a considered one-off, not a script step.
3. **The durable fix is `"extractionState" : "manual"`** on the keys the extractor cannot see. Verified
   both ways: marking three of the doomed report keys `manual` dropped the removals from 64 to 61 and
   all three survived, and marking two translated report keys `manual` kept them out of the `stale`
   sweep as well (42 → 64 rather than 42 → 66). The catalog already carries 127 `manual` keys and the
   sync did not touch one of them. Doing this for all 60 would take the hazard off the table for good.

And the warning that has not changed: **do not add a blanket `git checkout -- …/Localizable.xcstrings`
step to a build or test script.** Catalog edits are ordinary source changes — the commit that stopped 13
locales renaming the app is 88 lines of them — and a blanket restore would silently throw yours away.
If the catalog turns up dirty after a `build` or a `test`, that is still the signal it always was: find
out what wrote it before discarding anything.

Signing uses `DEVELOPMENT_TEAM = 8528AN28A3`. Version numbers live in `project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) — bump them there. Both app targets currently share the bundle id `com.wealthcompass.mobile`; the CloudKit container is `iCloud.com.wealthcompasstracker`.

## Source layout

- `Sources/Shared/` — the brain: `Models/`, `Persistence/`, `Services/`, `Stores/`, `UI/`. All finance calculations, persistence, sync, networking, and reusable views live here and compile into both apps.
- `Sources/iOS/` — mobile lifecycle + `TabView` UI.
- `Sources/macOS/` — desktop lifecycle + sidebar/table/menu UI, `MacAppModel` navigation, and `MacSettingsView` (an in-window Settings destination, not a separate Settings scene).

## Architecture (the parts that span multiple files)

### State: two `@MainActor` stores injected as environment objects
Each app's `@main` App constructs `AppSettings` first, then `FinanceStore(settings:)`, and injects them (plus a platform `AppLock`, and `MacAppModel` on Mac) via `.environmentObject`.

- `AppSettings` — preferences (currency, privacy mode, in-app language, onboarding, iCloud toggle, custom categories) backed by `UserDefaults` (keys prefixed `wc_mobile_`), plus exchange-rate snapshot + refresh/backoff state. Owns currency conversion.
- `FinanceStore` — owns the single `FinancialData` value and is the **only** place finance data is mutated.

### Persistence: local-first, single JSON file
- `FinancePersistence` is the storage boundary; `LocalFinancePersistence` writes one JSON DB to `Application Support/Wealth Compass/wealth-compass-local-data.json` (atomic, file-protected). It migrates a legacy Documents-based DB and runs schema migration (writing a one-time `.pre-cloudkit-backup`). `FinanceJSONCoding` centralizes the encoder/decoder.
- Every mutating `FinanceStore` method ends in `save()`, and **`save()` is the sync pipeline**: it diffs previous vs. current per-entity snapshots (`FinancialData.cloudSyncRecords()`, SHA256 per record), persists locally, records the changeset into `CloudSyncMetadataStore`, then notifies the CloudKit service when anything changed.
- Net-worth history: `appendSnapshot` deliberately does **not** materialize days with no activity (`SnapshotEngine.swift:12-16`, tag WC-#11) — there is no carry-forward backfill on write. Gaps are filled at render time by `AnalyticsEngine.snapshotsForChart`. `adjustHistoricalSnapshots` retroactively rewrites past snapshots when a transaction's amount/date changes.

### CloudKit sync (opt-in)
`CloudKitSyncService` is an `actor` implementing `CKSyncEngineDelegate`: one CloudKit record per entity (record types `WCTransaction`, `WCInvestment`, … in custom zone `WealthCompassZone`), tombstones for deletes, a bootstrap merge with deterministic conflict resolution (`bootstrapDecision`), and account-change protection that disables sync if the iCloud user changes. Sync metadata persists in `wealth-compass-cloud-sync.json`. Toggled by `AppSettings.isICloudSyncEnabled`; remote mutations are applied back through a `@MainActor` handler on `FinanceStore`. Design notes and remaining work are in `WealthCompass/TO_IMPROVE.md`.

### External data is fetched directly from the providers
`ExchangeRateService` and `MarketDataService` call Frankfurter (`/v2/rates`, base EUR), Finnhub (`/quote`), CoinGecko (`/simple/price`), and Yahoo (`yahooChartURL` / `yahooSearchURL`, `APIConfiguration.swift:30,34`) **directly** from the device — see `APIConfiguration` for the endpoints. Quote routing is **not** "Finnhub first, Yahoo on failure" (`FinanceStore.swift:732-737`): Finnhub prices USD listings and only with a key configured, every **non-USD** holding goes straight to Yahoo without asking Finnhub at all (its `/quote` reports no currency, tag H13), and Yahoo additionally takes over on `.noQuote` and `.rateLimited`. With no Finnhub key set Yahoo is the sole source for every **investment**, which is why those still auto-update keyless (tag I3, and `apple/README.md:17`). Crypto is a separate path that never touches Yahoo — without a CoinGecko key those holdings are skipped entirely (`FinanceStore.swift:831`). There is no intermediary proxy. Finnhub/CoinGecko keys are user-entered and stored in the Keychain via `KeychainCredentialStore` (service `com.wealthcompass.mobile.marketdata`) — they are **never** synced to iCloud and travel only as request headers over HTTPS to the issuing provider. Exchange rates auto-refresh on a 12h staleness window with exponential backoff, persisted via `ExchangeRatePersistence`. (The old `../proxy/` Cloudflare Worker is retired and no longer used by the app.)

### Localization — the dual-API pattern (important)
The app supports an **in-app language override** (`AppSettings.appLanguage`) that is independent of the system language. Because of this, model enums expose strings two ways and you must pick the right one:

- `var title: LocalizedStringKey` — only safe inside a SwiftUI `Text(...)` that honors the environment locale.
- `func localizedTitle(appLanguage:)` / `AppLocalization.string(_:appLanguage:)` — use everywhere you need a resolved `String`, passing `settings.appLanguage`.

New user-facing strings go into `Sources/Shared/Resources/Localizable.xcstrings` (35 locales — English plus 34 others). **Tab/sidebar labels are special**: they are generated into `Sources/Shared/Services/TabBarLabelResolver.swift` by `scripts/add_tab_bar_localizations.py` (the Xcode string-catalog sync would otherwise drop them, and they must fit a length cap). That Swift file is generated — re-run the script instead of editing it by hand. Per-locale App Store metadata lives in `fastlane/metadata/`.

## Conventions & gotchas

- **Debug instrumentation has been removed — do not reintroduce it.** Earlier builds had `// #region agent log` blocks, a `wcDebugLog(...)` helper, and an `I18nDebugLog` audit that POSTed app data to `http://127.0.0.1:7504/...`. These were deliberately deleted and must stay gone: cleartext localhost logging spams the network stack on a real device and trips ATS / App Review.
- Concurrency: `FinanceStore` and `AppSettings` are `@MainActor`; `CloudKitSyncService` is an `actor`. Keep finance mutations on the main actor and route remote applies through the existing `@MainActor` handler.
- Currency conversion in `AppSettings.convert` deliberately guards against zero / NaN / Inf rates because the results feed Swift Charts geometry (a NaN propagates into CoreGraphics and logs errors). Preserve those guards.
- Both apps force `.preferredColorScheme(.dark)` and re-`.id(...)` the root view on language change to force a full re-render.
- JSON import (the `Imported*` decoders, all in `Sources/Shared/Services/FinanceImportService.swift`) is intentionally lossy/forgiving (`LossyArray`, multiple date formats, legacy web shapes such as `income` / `expenses` / `liquidity`). Extend those decoders rather than tightening them — with one hard constraint: **money must never round-trip through `Double`**. Commits `c4e73ed` / `29db601` made all 22 money and quantity fields `Decimal` end to end, pinned by exact-value tests; decode straight to `Decimal` (via the string form) and any extension stays correct.
