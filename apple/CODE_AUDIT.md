# Wealth Compass (Apple) — Code Audit & Improvement Backlog

A deep, file-by-file review of the iOS (`WealthCompassMobile`) and macOS (`WealthCompassMac`) apps,
aimed at making the product more professional across correctness, security/privacy, architecture,
performance, UX, accessibility, App Store readiness, and testing.

**How to use this file:** each item has a stable ID (`C#`, `H#`, `M#`, `L#`, `A#`, `T#`), a severity, the
location(s), why it matters, and a concrete fix. A future iteration can work top-down and tick the
checkboxes. Items are ordered by severity within each section.

> **Confirmed design decisions (do NOT "fix"):**
> - iOS and macOS intentionally share the bundle id `com.wealthcompass.mobile`.
> - The app is intentionally dark-only and (on iPhone) portrait-only — listed below only as polish/a11y context, not as bugs.

---

## P0 — Critical (ship-blockers / correctness)

- [x] **C1 — Remove all debug instrumentation before shipping.** ✅ Done 2026-06-22 — deleted `I18nDebugLog.swift`, all `wcDebugLog`/`#region agent log` blocks, and the 4 call sites.
  `wcDebugLog(...)` and `// #region agent log` blocks POST app data to `http://127.0.0.1:7504/...` from
  `Sources/Shared/Stores/FinanceStore.swift` and `Sources/Shared/Services/CloudKitSyncService.swift`.
  `Sources/Shared/Services/I18nDebugLog.swift` additionally writes to a **hardcoded absolute path** from
  another machine (`/Users/simo/Downloads/DEV/wealth-compass/...`) and POSTs to localhost; it is called from
  `iOS/ContentView.swift` and `macOS/MacRootView.swift`.
  *Why it matters:* ships a cleartext-HTTP logger that spams the network stack on real devices, leaks
  financial data/sync metadata to a local endpoint, and the hardcoded `/Users/simo/...` path is dead on any
  other machine. Cleartext localhost also trips ATS expectations and App Review.
  *Fix:* delete `I18nDebugLog.swift`, all `wcDebugLog` helpers + `// #region agent log` blocks, and every
  call site (`I18nDebugLog.auditTabBarLabels`, `I18nDebugLog.log`). Already flagged in `WealthCompass/TO_IMPROVE.md`.

- [x] **C2 — Build artifacts are committed to git.** ✅ Done 2026-06-22 — added `apple/.gitignore` (covers `build/`, `DerivedData/`, `xcuserdata`) and `git rm -r --cached` the 6,646 tracked `build/` files; committed on branch `code-audit`.
  `apple/WealthCompass/build/` (DerivedData, intermediates, `.o`, generated entitlements) is tracked; the
  root `.gitignore` only ignores `DerivedData/`, not `build/`.
  *Why it matters:* bloats the repo, leaks local build paths/derived entitlements, and causes noisy diffs.
  *Fix:* add `build/` (and `*.xcodeproj/project.xcworkspace/xcuserdata/`) to `.gitignore`, then
  `git rm -r --cached apple/WealthCompass/build`.

- [x] **C3 — Crypto icons never load (escaped string interpolation).** ✅ Done 2026-06-22 — `CryptoIconView` now renders the colored-letter avatar only; remote `AsyncImage`/CoinCap fetch removed (privacy + reliability).
  `Sources/Shared/UI/DesignSystem.swift:537`:
  `URL(string: "https://assets.coincap.io/assets/icons/\\(symbol.lowercased())@2x.png")`
  The `\\(` is an escaped backslash, so the URL contains the literal text `\(symbol.lowercased())` instead of
  the symbol — every crypto icon silently falls back to the letter placeholder. Separately, the CoinCap
  `assets.coincap.io` icon endpoint is deprecated/unreliable.
  *Fix:* use real interpolation (`"...icons/\(symbol.lowercased())@2x.png"`) and switch to a maintained icon
  source (or bundle a small set / use CoinGecko image URLs already available from the price API).

- [x] **C4 — Background capabilities are declared but never implemented.** ✅ Done 2026-06-22 — removed `UIBackgroundModes` + `BGTaskSchedulerPermittedIdentifiers`, the `aps-environment` entitlement on both targets, `APS_ENVIRONMENT`, and the Push/BackgroundModes target capabilities. CloudKit/iCloud kept; `CKSyncEngine.subscriptionID` left in place. Real background sync is now a separate P1 feature.
  `Resources/iOS/Info.plist` declares `UIBackgroundModes` = `remote-notification`, `fetch`, `processing` and
  `BGTaskSchedulerPermittedIdentifiers`, and entitlements include `aps-environment`. But there is **no**
  `BGTaskScheduler.register(...)`, **no** `UIApplication.registerForRemoteNotifications()`, and **no**
  `didReceiveRemoteNotification` handler anywhere in `Sources/`.
  *Why it matters:* (a) App Review rejects apps that declare background modes they don't use; (b) CloudKit
  silent-push sync and background refresh do **not** actually work — sync only runs on foreground/manual
  "Force Sync". This is the single biggest functional gap for a "syncs across your devices" claim.
  *Fix:* either implement push registration + `CKSyncEngine` push handling + BGTask refresh (see
  `TO_IMPROVE.md` P0 #5), **or** remove the unused `UIBackgroundModes`/`BGTaskScheduler*` keys and the APS
  entitlement until implemented.

---

## P1 — High (data integrity, security, privacy)

- [x] **H1 — Privacy/onboarding copy contradicts the actual network path.** ✅ Done 2026-06-22 — retired the proxy from the data path; `ExchangeRateService`/`MarketDataService` call Frankfurter/Finnhub/CoinGecko directly; onboarding + privacy copy rewritten on both platforms to describe the real path.
  Onboarding states *"We don't use central servers"* and *"connect directly to data providers"*
  (`iOS/Views/OnboardingView.swift`, `macOS/Views/MacOnboardingView.swift`), but **all** FX and market
  requests are routed through the developer-operated Cloudflare Worker at
  `APIConfiguration.proxyBaseURL` (`ExchangeRateService.swift`, `MarketDataService.swift`). The worker
  (`../proxy/src/index.js`) forwards the user's **API keys** (`X-Finnhub-Token`, `x-cg-demo-api-key`) and sees
  request metadata.
  *Why it matters:* for a finance app this is a materially misleading privacy claim and a real
  key-exposure surface (the proxy operator can log keys/IPs).
  *Fix:* either (a) correct the copy to disclose the proxy and what it can see, or (b) call providers
  directly from the app and drop the proxy. If keeping the proxy, document its data handling and consider not
  forwarding keys in a loggable header.

- [x] **H2 — Crypto cost basis silently changes currency after a price refresh.** ✅ Done 2026-06-22 — added a currency picker to `CryptoFormView` + `MacCryptoEditor` (defaults to app display currency); refresh resolves each holding's price in its own currency and no longer overwrites `holding.currency`.
  `CryptoHolding.currency` defaults to `.usd`; the crypto forms (`Forms.swift` `CryptoFormView`,
  `MacEditorSheet.swift` `MacCryptoEditor`) expose **no** currency picker and display the fee in hardcoded USD.
  But `FinanceStore.refreshMarketPrices` overwrites `holding.currency` with the CoinGecko quote currency
  (`settings.currency` or EUR fallback). After a refresh, the user-entered `avgBuyPrice` (entered as if USD) is
  re-interpreted through the new currency in `calculateTotals`/`costBasis`, producing wrong cost basis and P&L.
  *Fix:* decide a single source of truth for a holding's input currency: either add a currency picker to the
  crypto form and convert prices into it, or store buy-price currency separately from the live-quote currency
  and convert explicitly.

- [x] **H3 — Only four currencies are supported end-to-end.** ✅ Done 2026-06-22 — `Currency` is now the full ECB/Frankfurter set (31 ISO cases, `Locale`-driven names/symbols, JSON-compatible); the rate fetch requests the whole table and `isValid` was relaxed; CoinGecko price decode is dynamic. Finnhub stock-currency stays user-selected (documented).
  `Currency` is a 4-case enum (EUR/USD/GBP/CHF) and `ExchangeRateSnapshot.isValid` requires `base == .eur`.
  Imported investments/crypto/liabilities in any other currency fall back to a default
  (`Currency.imported(_:default:)`), silently misstating value; Finnhub quotes are assumed USD.
  *Why it matters:* a "track your investments" app that can't represent JPY/CAD/AUD/etc. mis-values real
  portfolios.
  *Fix:* make `Currency` data-driven (ISO 4217 list) and fetch the full rate table from the proxy, or clearly
  constrain/validate input to the supported set with a visible warning on import.

- [x] **H4 — Force-unwrapped URL construction in the market-data clients.** ✅ Done 2026-06-22 — both `URLComponents(...)!` sites in `MarketDataService` now use `guard … else { throw MarketDataError.invalidURL }`, matching `ExchangeRateService`.
  `MarketDataService.swift:261` and `:348` use `URLComponents(string: APIConfiguration.proxyBaseURL)!`
  while `ExchangeRateService.swift` guards the same value and throws `.invalidURL`.
  *Fix:* make the market-data clients use the same `guard let … else { throw .invalidURL }` pattern.

- [x] **H5 — Local-save failure crashes in DEBUG and is easy to miss in release.** ✅ Done 2026-06-22 — replaced the `assertionFailure` with `os.Logger` + a published `persistenceError`, surfaced app-wide by a `PersistenceErrorBanner` overlay on both root views.
  `FinanceStore.save()` ends with `assertionFailure("Failed to save local finance data: \(error)")`
  (`FinanceStore.swift:940`). In DEBUG this aborts the app on a disk error; in release it sets
  `iCloudSyncError` but that string is only surfaced in Settings, so a user editing on the Dashboard gets no
  feedback that their data didn't persist.
  *Fix:* replace the assertion with structured logging and a user-visible, app-wide error surface (e.g., a
  published `persistenceError` shown as a banner).

- [x] **H6 — Stored secrets are pre-filled into onboarding `SecureField`s, inconsistently.** ✅ Done 2026-06-22 — onboarding no longer loads keys into the fields; it shows a "Configured" badge (via `KeychainCredentialStore.contains`) and only writes a key when the user types one, matching Settings.
  `OnboardingView`/`MacOnboardingView` load existing keys from Keychain into plain `@State` and display them in
  `SecureField` (`onAppear`), while the Settings credential editors deliberately start blank. Pre-filling
  secrets is both a small exposure and a UX inconsistency.
  *Fix:* don't pre-load secrets into editable fields; show a "Configured" state instead (as Settings already does).

- [x] **H7 — Editing a recurring schedule can back-date `startDate` past the future-only guard.** ✅ Done 2026-06-22 — `processDueRecurringTransactions` fast-forwards occurrences older than a 60-day window instead of mass-generating them; `firstOccurrence(onOrAfter:)` now returns `nil` on iteration-cap exhaustion instead of a stale past date (defends against edits, gaps, sync, and import).
  The "first occurrence must be in the future" rule is only applied when `existingSchedule == nil`
  (`Forms.swift` / `MacRecurringTransactionEditor.swift` `isSaveDisabled`). Editing an existing schedule to a
  far-past start can mass-generate occurrences on next `processDueRecurringTransactions` (bounded only by the
  1,000/20,000 iteration caps).
  *Fix:* validate start/next-due bounds on edit too, or clamp generation to a sane lookback window.

---

## P2 — Medium (architecture, performance, UX)

- [x] **M1 — `FinanceStore` is a ~2,000-line god object.** ✅ Done 2026-06-22 — extracted `CurrencyConverter`, `SnapshotEngine`, `AnalyticsEngine`, and `FinanceImportService` as pure value types; `FinanceStore` (now 880 lines, was 1962) delegates to them. Market-refresh stayed in the store (refactored under M7) rather than a separate coordinator, as it's tied to the store's published state.
  It mixes the store, snapshot math (`appendSnapshot`/`adjustHistoricalSnapshots`), analytics
  (`expensesByCategory`, `*Allocation`, `cashFlowTrend`), the entire lossy JSON import parser
  (`Imported*` types), cloud-sync diffing, and market-refresh orchestration.
  *Fix:* extract `FinanceImportService`, `AnalyticsEngine`, `SnapshotEngine`, and a market-refresh
  coordinator. This is also the prerequisite for unit testing (see T-section).

- [x] **M2 — Large iOS/macOS duplication of non-UI logic.** ✅ Done 2026-06-22 — hoisted into `Shared/`: `PieSliceHitTester` (4→1), `RecurringScheduleBuilder` (2→1), `RecurringNotificationService` (one actor, id-prefix param; platform delegates stay), `BiometricLockStore` (one base; per-platform subclass with its own defaults key), `OnboardingViewModel` (shared onboarding state machine + key validation; both views adopt it via `@StateObject`), and `SettingsViewModel` (shared market-data credential validation). The settings/onboarding **presentation** stays native per-platform by design (TabView vs slide; Form vs grouped sections) — only the logic was consolidated.
  Two near-identical lock stores (`AppLockStore` / `MacAppLockStore`), two notification services
  (`RecurringTransactionNotificationService` / `MacRecurringTransactionNotificationService`), two onboarding
  flows, two settings screens, and duplicated recurring-save logic (`saveSchedule` exists in 2 files with
  identical body). Pie-chart hit-testing geometry is copy-pasted in 4 places
  (`AllocationChart`, iOS `CashFlowView`, `MacDashboardView`, `MacCashFlowView`).
  *Fix:* hoist platform-agnostic logic into `Shared/` (one biometric store with a platform `reason`, one
  notification service parameterized by id-prefix, one `RecurringScheduleBuilder`, one
  `PieSliceHitTester`). Big maintainability + consistency win.

- [x] **M3 — Derived data recomputed on every view render.** ✅ Done 2026-06-22 — `FinanceStore` memoizes `calculateTotals` (the hottest, multi-call-per-render path) keyed by `(dataVersion, currency, rate-snapshot timestamp)` — a provably complete key, invalidated via a `dataVersion` counter bumped in `data`'s `didSet`. (Other analytics remain O(n)-once-per-render; the engine extraction in M1 makes further memoization trivial if needed.)
  Dashboards/cards call `finance.calculateTotals`, `cashFlowTrend`, `expensesByCategory`, and `*Allocation`
  inside `body`/computed vars, each a full O(n) pass over transactions; several views call them multiple
  times per render. `CryptoView`/`InvestmentsView` also `.sorted` inside `ForEach`.
  *Fix:* compute once per change in the store (cache keyed by data version) or hoist into a view model;
  precompute sorted arrays.

- [x] **M4 — Whole-database rewrite + full re-hash on every mutation.** ✅ Done 2026-06-22 — added a serializing `PersistenceCoordinator` actor that owns persistence, the sync-metadata store, and the diff baseline (replacing `FinanceStore.persistedData`). `save()` is now non-blocking: it nudges a single long-lived `AsyncStream` consumer that reads the latest `data` live and runs encode → SHA-256 diff → disk-write → metadata-record off the main actor; remote applies route their write through the same coordinator so local/remote writes never interleave. Single-JSON-file format + `CloudSync*` model unchanged; the incremental/per-record/SQLite store stays deferred (see `TO_IMPROVE.md` #26). New `PersistenceCoordinatorTests` cover burst ordering, last-write-wins, failed-save baseline integrity, remote-apply baseline advance, and the H5 banner. (Implements `TO_IMPROVE.md` #10; partially addresses #9 and #25.)
  `FinanceStore.save()` re-encodes the entire `FinancialData` to pretty-printed JSON and SHA-256-hashes every
  record on each edit, on the main actor (`save()` → `cloudSyncRecords()` → `CloudSyncChangeSet.difference`).
  For large datasets this makes each add/edit increasingly expensive. (Partially noted for sync in
  `TO_IMPROVE.md`.)
  *Fix:* move encoding/diffing off the main actor, and/or move to an incremental store (per-record files or
  SQLite/SwiftData) so a single edit doesn't rewrite everything.

- [x] **M5 — Snapshot backfill + retroactive adjustment is intricate and unverified.** ✅ Done 2026-06-22 — extracted `SnapshotEngine` (pure) with T3 unit tests covering backfill, the > 60-day cap, and retroactive adjustment.
  `appendSnapshot` carry-forward-backfills up to 60 days and `adjustHistoricalSnapshots` rewrites all
  on/after a date; `processDueRecurringTransactions` interleaves both. Long gaps, edits to old transactions,
  and recurring catch-up can drift `liquidity`/`netWorth`.
  *Fix:* extract a `SnapshotEngine` with unit tests covering gaps > 60 days, back-dated edits, and bulk
  recurring catch-up.

- [x] **M6 — macOS exposes Settings two ways.** ✅ Done 2026-06-22 — removed the sidebar `.settings` destination (and the ⌘5 nav command); the `Settings {}` scene (⌘,) is now the single canonical surface.
  `MacSettingsView` is shown both as the sidebar `.settings` detail and as the `Settings { }` scene (⌘,) in
  `WealthCompassMacApp`. They can diverge and double-present.
  *Fix:* pick one canonical Settings surface (the `Settings` scene is the macOS-idiomatic choice) and remove
  the other, or make the sidebar item open the Settings scene.

- [x] **M7 — Serial market-price refresh with fixed 1s sleeps and no per-item progress.** ✅ Done 2026-06-22 — `FinanceStore` publishes `marketRefreshProgress (done, total)` (shown as "Updating x of N" in both refresh buttons), and the inter-request delay starts at 0.3s and backs off (×3, cap 3s) only when actually rate-limited.
  `refreshMarketPrices` fetches Finnhub quotes one-by-one with `Task.sleep(1s)` between each
  (`FinanceStore.swift`), so N investments take ≥ N seconds with only a single spinner.
  *Fix:* show progress (`x of N`), make the delay adaptive to 429s, and cap/parallelize within rate limits.

- [x] **M8 — Network requests have no offline/retry UX beyond exchange-rate backoff.** ✅ Done 2026-06-22 — added `NetworkRetry` (retry + exponential backoff on lost connectivity/timeout/429/5xx, immediate return for auth/other statuses); `ExchangeRateService` + both `MarketDataService` clients route through it.
  Market-price refresh has no backoff equivalent to exchange rates; failures surface only as alert text.
  *Fix:* unify a small networking layer with consistent timeout/retry/offline handling for both services.

---

## P3 — Low / Polish / Consistency

- [x] **L1 — App display name differs across platforms.** ✅ Done 2026-06-22 — unified on "Wealth Compass Tracker" (matches App Store metadata + iOS); set the macOS target's `INFOPLIST_KEY_CFBundleDisplayName` and removed the dead iOS `INFOPLIST_KEY_*` keys (`GENERATE_INFOPLIST_FILE = NO`), verified with `plutil -lint`.
  iOS shows **"Wealth Compass Tracker"** (`Resources/iOS/Info.plist` `CFBundleDisplayName`) while macOS shows
  **"Wealth Compass"** (`INFOPLIST_KEY_CFBundleDisplayName`). The `INFOPLIST_KEY_CFBundleDisplayName` on the
  mobile target is dead (mobile uses `GENERATE_INFOPLIST_FILE = NO`).
  *Fix:* pick one name; remove the dead mobile `INFOPLIST_KEY_*` settings.

- [x] **L2 — Inconsistent localized-string usage.** ✅ Done 2026-06-22 — removed the 32 stray-space `LocalizedStringKey( "…")` literals; the lone `Text(LocalizedStringKey(category))` that localized user-entered categories is now `Text(verbatim:)` (matching how categories render everywhere else).
  Many views wrap literals as `LocalizedStringKey( "Crypto assets")` (note the stray space) — e.g.
  `iOS/Views/CryptoView.swift`, `InvestmentsView.swift`, `macOS/Views/MacInvestmentsView.swift` — while most
  views pass plain literals. Mixed `Text(LocalizedStringKey(category))` for user-entered categories also
  tries to localize user text.
  *Fix:* standardize on plain string literals for `LocalizedStringKey` params; use `Text(verbatim:)` for
  user-entered content.

- [x] **L3 — Hardcoded, non-localized device/biometry strings.** ✅ Done 2026-06-22 — added `BiometricLockStore.biometrySymbolName()` (Face/Touch/Optic ID → matching SF Symbol) so `LockView` no longer hardcodes `"faceid"`; `MarketDataAPIKeySecurityNote` now derives the device noun (iPhone/iPad/Mac) from the running device instead of a per-call-site literal.
  `MarketDataAPIKeySecurityNote(deviceName: "iPhone" / "Mac")` is hardcoded; `LockView` always uses the
  `"faceid"` SF Symbol even on Touch ID / Optic ID devices.
  *Fix:* derive device/biometry symbol+name from `LAContext.biometryType` and localize.

- [x] **L4 — Amount fields seeded with `String(Double)`.** ✅ Done 2026-06-22 — added shared `AmountInputFormatter` (no grouping, no scientific notation, "." decimal, ≤8 fraction digits; round-trips with the forms' comma-normalizing `Double(...)` parse) and routed every amount-field seed (`String($0.amount)`) and the ad-hoc `%.8g` helpers through it.
  `String($0.amount)` (e.g. `Forms.swift:29`, `MacCashFlowView` editor) can produce scientific notation or
  locale-mismatched separators; editing uses `%.8g` elsewhere. Inconsistent.
  *Fix:* one shared number→input formatter used everywhere a numeric field is seeded.

- [x] **L5 — Dead code.** ✅ Done 2026-06-22 — deleted the unused `compactCurrency(_:)` (iOS + macOS dashboards) and `countLabel(_:singular:)` (macOS dashboard); confirmed no call sites first.
  `compactCurrency(_:)` (DashboardView & MacDashboardView) and `countLabel(_:singular:)` (MacDashboardView)
  appear unused; `selectedTransaction`/`selectedInvestment` selection state is largely vestigial.
  *Fix:* delete unused members.

- [x] **L6 — Onboarding can't go back and omits currency/language.** ✅ Done 2026-06-22 — added a "Personalize" step (base-currency + in-app-language pickers mirroring Settings) as the second onboarding page on both platforms, plus a 44pt back affordance shown on every page after the first.
  Both onboarding flows are forward-only and never let the user choose base currency or language up front
  (the most impactful settings for a finance app).
  *Fix:* add a back affordance and a currency (and optional language) step.

- [x] **L7 — Inconsistent category-reset behavior between forms.** ✅ Done 2026-06-22 — the two recurring editors and the Mac transaction editor now preserve a still-valid category on type change (the `!contains(category) && !isCustomCategorySelected` guard from `TransactionFormView`) instead of resetting unconditionally.
  `RecurringTransactionFormView`/Mac editors reset category on type change unconditionally, while
  `TransactionFormView` preserves a still-valid selection. Pick one behavior.

- [x] **L8 — Privacy mask string differs (`"****"` vs `"••••"`) across screens.** ✅ Done 2026-06-22 — added `AppSettings.redactionToken` ("••••") as the single source of truth and replaced every `"****"`/`"••••"` literal across the views.
  Standardize the redaction token in one helper on `AppSettings`.

---

## A — Accessibility

- [ ] **A1 — Fixed font sizes don't scale with Dynamic Type.**
  Pervasive `.font(.system(size: …))` (e.g. `PageHeader` 30pt, net-worth 35/42pt, metric values) plus heavy
  `minimumScaleFactor` means large-text users get clipped/shrunk UI rather than reflow.
  *Fix:* prefer semantic text styles (`.title`, `.headline`, …) or `@ScaledMetric`; reserve fixed sizes for
  decorative numerics only.

- [ ] **A2 — Charts are invisible to VoiceOver.**
  Net-worth, cash-flow, and allocation charts have no `accessibilityLabel`/`AXChartDescriptor`; the pie
  selection is pointer/drag-only.
  *Fix:* add chart accessibility descriptors and an accessible data summary; provide a non-pointer way to
  inspect slices.

- [ ] **A3 — Low-contrast text on dark background.**
  Frequent `.foregroundStyle(.white.opacity(0.35–0.45))` for captions likely fails WCAG AA contrast.
  *Fix:* audit secondary/tertiary text opacities against contrast targets; centralize as named tokens in
  `WCColor`.

- [ ] **A4 — Tap targets / hit areas.**
  Several icon-only buttons in dense rows (recurring row actions) are below the 44pt target.
  *Fix:* enforce minimum hit areas.

---

## T — Testing gaps

Only `Tests/CloudSyncCoreTests.swift` exists (cloud-sync record keys, change-set diff, mutation round-trip,
legacy migration, sync lifecycle). High-value pure logic is **untested**:

- [x] **T1 — Currency conversion** incl. the NaN/Inf/zero-rate guards in `AppSettings.convert`. ✅ written 2026-06-22 (`CurrencyConverterTests`) — pending first run in Xcode.
- [x] **T2 — Recurring date math** ✅ written 2026-06-22 (`RecurringScheduleBuilderTests`, pending first run): monthly/yearly anchoring, end-of-month clamping, DST boundaries,
  `firstOccurrence(onOrAfter:)`, and `processDueRecurringTransactions` catch-up + dedup.
- [x] **T3 — Snapshot engine** ✅ written 2026-06-22 (`SnapshotEngineTests`, pending first run): `appendSnapshot` backfill (incl. > 60-day gaps) and
  `adjustHistoricalSnapshots` after back-dated edits/deletes.
- [x] **T4 — Import parser** ✅ written 2026-06-22 (`FinanceImportServiceTests`, pending first run): lossy arrays, legacy web shapes (`income`/`expenses`/`liquidity`), multiple date
  formats, comma decimals, and skipped-record counting.
- [x] **T5 — Analytics** ✅ written 2026-06-22 (`AnalyticsEngineTests`, pending first run): `expensesByCategory`, `cashFlowTrend`, totals/allocations.
  *Prerequisite:* M1 (extract pure logic so it's testable without the `@MainActor` store).

---

## Notes / process

- `TO_IMPROVE.md` already tracks C1 (debug removal) and C4 (push wiring) — fold this audit into it or replace it.
- `DOCUMENTATION.md` is stale (references `MARKETING_VERSION 1.0.4`; project is now `1.0.6` / build `7`).
- Consider a SwiftLint config to catch force-unwraps (H4), `print`/debug logging (C1), and fixed-size fonts (A1) going forward.
