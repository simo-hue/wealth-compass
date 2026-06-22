# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository orientation

This directory (`apple/`) is the **native Apple implementation** of Wealth Compass, a personal net-worth / finance tracker. It is one Xcode project with two independent native app targets plus a test target:

- `WealthCompassMobile` — SwiftUI, iPhone, iOS 17+
- `WealthCompassMac` — native SwiftUI for macOS 14+ (no Mac Catalyst; built against the macOS SDK with sidebar navigation, tables, menus, keyboard shortcuts, a Settings scene, and sandbox entitlements)
- `WealthCompassTests` — XCTest unit tests

The **parent directory** (`../`) is a separate React + Vite + Supabase web app that shares the product but no code; its `.github/workflows/deploy.yml` only builds/deploys that web app. The JSON backup format is the interchange point between the web and Apple apps (see the import path in `FinanceStore`).

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
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:WealthCompassTests/CloudSyncCoreTests/testChangeSetDetectsUpdatesAndDeletes
```

Signing uses `DEVELOPMENT_TEAM = 8528AN28A3`. Version numbers live in `project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) — bump them there. Both app targets currently share the bundle id `com.wealthcompass.mobile`; the CloudKit container is `iCloud.com.wealthcompasstracker`.

## Source layout

- `Sources/Shared/` — the brain: `Models/`, `Persistence/`, `Services/`, `Stores/`, `UI/`. All finance calculations, persistence, sync, networking, and reusable views live here and compile into both apps.
- `Sources/iOS/` — mobile lifecycle + `TabView` UI.
- `Sources/macOS/` — desktop lifecycle + sidebar/table/menu UI, `MacAppModel` navigation, and `MacSettingsView` (the Settings scene).

## Architecture (the parts that span multiple files)

### State: two `@MainActor` stores injected as environment objects
Each app's `@main` App constructs `AppSettings` first, then `FinanceStore(settings:)`, and injects them (plus a platform `AppLock`, and `MacAppModel` on Mac) via `.environmentObject`.

- `AppSettings` — preferences (currency, privacy mode, in-app language, onboarding, iCloud toggle, custom categories) backed by `UserDefaults` (keys prefixed `wc_mobile_`), plus exchange-rate snapshot + refresh/backoff state. Owns currency conversion.
- `FinanceStore` — owns the single `FinancialData` value and is the **only** place finance data is mutated.

### Persistence: local-first, single JSON file
- `FinancePersistence` is the storage boundary; `LocalFinancePersistence` writes one JSON DB to `Application Support/Wealth Compass/wealth-compass-local-data.json` (atomic, file-protected). It migrates a legacy Documents-based DB and runs schema migration (writing a one-time `.pre-cloudkit-backup`). `FinanceJSONCoding` centralizes the encoder/decoder.
- Every mutating `FinanceStore` method ends in `save()`, and **`save()` is the sync pipeline**: it diffs previous vs. current per-entity snapshots (`FinancialData.cloudSyncRecords()`, SHA256 per record), persists locally, records the changeset into `CloudSyncMetadataStore`, then notifies the CloudKit service when anything changed.
- Net-worth history: `appendSnapshot` carry-forward-backfills missing days (capped at 60) and `adjustHistoricalSnapshots` retroactively rewrites past snapshots when a transaction's amount/date changes.

### CloudKit sync (opt-in)
`CloudKitSyncService` is an `actor` implementing `CKSyncEngineDelegate`: one CloudKit record per entity (record types `WCTransaction`, `WCInvestment`, … in custom zone `WealthCompassZone`), tombstones for deletes, a bootstrap merge with deterministic conflict resolution (`bootstrapDecision`), and account-change protection that disables sync if the iCloud user changes. Sync metadata persists in `wealth-compass-cloud-sync.json`. Toggled by `AppSettings.isICloudSyncEnabled`; remote mutations are applied back through a `@MainActor` handler on `FinanceStore`. Design notes and remaining work are in `ICLOUD_SYNC.md` and `WealthCompass/TO_IMPROVE.md`.

### External data goes through a Cloudflare Worker proxy
`ExchangeRateService` and `MarketDataService` never call third-party APIs directly — they hit `APIConfiguration.proxyBaseURL` at `/api/rates` (Frankfurter, base EUR), `/api/quote` (Finnhub), and `/api/price` (CoinGecko). The worker source is in `../proxy/` (deploy with `npx wrangler deploy`); if you change `proxyBaseURL`, update both. Finnhub/CoinGecko keys are user-entered and stored in the Keychain via `KeychainCredentialStore` (service `com.wealthcompass.mobile.marketdata`) — they are **never** synced to iCloud. Exchange rates auto-refresh on a 12h staleness window with exponential backoff, persisted via `ExchangeRatePersistence`.

### Localization — the dual-API pattern (important)
The app supports an **in-app language override** (`AppSettings.appLanguage`) that is independent of the system language. Because of this, model enums expose strings two ways and you must pick the right one:

- `var title: LocalizedStringKey` — only safe inside a SwiftUI `Text(...)` that honors the environment locale.
- `func localizedTitle(appLanguage:)` / `AppLocalization.string(_:appLanguage:)` — use everywhere you need a resolved `String`, passing `settings.appLanguage`.

New user-facing strings go into `Sources/Shared/Resources/Localizable.xcstrings` (~40 languages). **Tab/sidebar labels are special**: they are generated into `Sources/Shared/Services/TabBarLabelResolver.swift` by `scripts/add_tab_bar_localizations.py` (the Xcode string-catalog sync would otherwise drop them, and they must fit a length cap). That Swift file is generated — re-run the script instead of editing it by hand. Per-locale App Store metadata lives in `fastlane/metadata/`.

## Conventions & gotchas

- **Remove the debug instrumentation before shipping.** `CloudKitSyncService.swift` and `FinanceStore.swift` contain `// #region agent log` blocks and a `wcDebugLog(...)` helper that POSTs to `http://127.0.0.1:7504/...`, and `ContentView` runs `I18nDebugLog` audits. These are temporary; per `WealthCompass/TO_IMPROVE.md` they must not ship (localhost HTTP logging spams the network stack on a real device).
- Concurrency: `FinanceStore` and `AppSettings` are `@MainActor`; `CloudKitSyncService` is an `actor`. Keep finance mutations on the main actor and route remote applies through the existing `@MainActor` handler.
- Currency conversion in `AppSettings.convert` deliberately guards against zero / NaN / Inf rates because the results feed Swift Charts geometry (a NaN propagates into CoreGraphics and logs errors). Preserve those guards.
- Both apps force `.preferredColorScheme(.dark)` and re-`.id(...)` the root view on language change to force a full re-render.
- JSON import (the `Imported*` decoders in `FinanceStore`) is intentionally lossy/forgiving (`LossyArray`, multiple date formats, legacy web shapes such as `income` / `expenses` / `liquidity`). Extend those decoders rather than tightening them.
