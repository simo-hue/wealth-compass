# Wealth Compass (Apple) — iOS & macOS Deep Code Audit

_A fresh, file-by-file review of the **current** Swift source for the two native app targets (`WealthCompassMobile`, `WealthCompassMac`) and their shared core. Every item below was found by reading the current code and then **independently re-verified** by a second agent against that same code — items that were already fixed or turned out to be false positives were dropped. This file is written to be implemented top-down by a follow-up coding agent: each finding is self-contained (exact `file:line`, the current code, what is wrong, why it matters, and a concrete fix)._

## How this was produced

- **16 review lenses** ran in parallel: 12 owned a specific subsystem and read it in full (money/models/persistence, `FinanceStore`, `AppSettings` + FX, `CloudKitSyncService`, market/analytics, import/recurring/biometric, shared UI, iOS views, macOS views), plus 4 cross-cutting lenses (concurrency & data races, end-to-end money correctness, security/privacy, SwiftUI lifecycle/performance).
- **Adversarial verification:** all 156 raw findings were re-checked one-by-one against the current source. 48 were dropped as already-handled or false, leaving **107** confirmed/near-certain findings (14 High, 31 Medium, 62 Low).
- One finding is marked **⚠️ UNCERTAIN** — treat it as a lead to confirm at runtime, not a proven bug.

## How to use this file

1. Work **top-down by severity** (High → Medium → Low). Within a severity, items are ordered by file then line.
2. Each finding has a stable ID (`DA-H01`, `DA-M01`, `DA-L01`, …). **These IDs are local to this document** and are independent of the `WC-*` / `C#/H#/M#` schemes in `CODE_AUDIT.md` and `IOS_MACOS_BUG_AUDIT.md`.
3. The **Current code** block is quoted from the source at the time of the audit — re-read the cited lines before editing, as line numbers may have shifted.
4. After fixing, verify with the build/test commands in `apple/CLAUDE.md` (`xcodebuild build` for each scheme; `xcodebuild test -scheme WealthCompassMobile` for the XCTest suite).

## Do NOT "fix" these (intentional design decisions)

These are deliberate and must not be reported/changed as bugs:

- iOS and macOS intentionally share the bundle id `com.wealthcompass.mobile`.
- The app is intentionally **dark-only** and (on iPhone) **portrait-only**; both apps force `.preferredColorScheme(.dark)` and re-`.id(...)` the root on language change.
- The JSON import decoders (`Imported*`) are intentionally **lossy/forgiving** — do not tighten them.
- External APIs (Frankfurter / Finnhub / CoinGecko) are called **directly** from the device; keys travel as request headers over HTTPS by design.
- Money is `Decimal`; dropping to `Double` only at Swift Charts plot points and inside FX conversion is intended.
- The zero/NaN/Inf guards in `AppSettings.convert` are intentional (they feed Swift Charts geometry).

## Summary

| Severity | Count |
|---|---|
| High | 14 |
| Medium | 31 |
| Low | 62 |
| **Total** | **107** |

**By platform:** Shared 47 · iOS+macOS 23 · macOS 22 · iOS 15

**By category:** Correctness 29 · UX 15 · Performance 15 · DataLoss 8 · Bug 6 · Concurrency 5 · Accessibility 5 · CodeQuality 5 · Localization 5 · ErrorHandling 5 · Privacy 3 · Architecture 3 · Security 3

## Index

| ID | Sev | Category | Platform | Location | Title |
|---|---|---|---|---|---|
| DA-H01 | H | Concurrency | iOS | `iOS/ContentView.swift:67` | Recurring-notification handler mutates and syncs finance data while the app is locked |
| DA-H02 | H | Privacy | macOS | `macOS/MacRootView.swift:65` | Root editor sheet stays presented over the macOS lock screen when the app locks |
| DA-H03 | H | UX | macOS | `macOS/MacRootView.swift:74` | macOS re-locks the app on every focus loss (Cmd+Tab / occlusion), forcing constant re-authentication |
| DA-H04 | H | UX | macOS | `macOS/MacRootView.swift:78` | macOS locks the app and forces biometric re-auth every time the window loses focus (scenePhase .inactive treated as lock) |
| DA-H05 | H | Correctness | macOS | `macOS/Views/MacCashFlowView.swift:891` | Transaction rows/cards and recurring rows render the raw amount with the display-currency symbol, skipping the transaction's own currency |
| DA-H06 | H | Architecture | macOS | `macOS/Views/MacCashFlowView.swift:1074` | Cash Flow's macOS transaction editor breaks the category Picker for imported/legacy categories (diverged from the sibling MacEditorSheet editor) |
| DA-H07 | H | Correctness | iOS+macOS | `macOS/Views/MacEditorSheet.swift:356` | Editor seed uses en_US_POSIX '.' but parse tries Locale.current first: 3-fraction-digit values (e.g. crypto quantity 0.125) corrupt 1000x on edit in it_IT/de_DE/etc. |
| DA-H08 | H | DataLoss | Shared | `Shared/Models/FinanceModels.swift:466` | Unknown enum rawValue in the local DB file fails the whole FinancialData decode, making the entire dataset appear empty |
| DA-H09 | H | DataLoss | Shared | `Shared/Models/MoneyDecimal.swift:23` | Decimal(finite:) returns a non-finite (NaN) Decimal instead of nil for large finite Doubles, defeating its sanitization contract and poisoning stored/synced money |
| DA-H10 | H | DataLoss | Shared | `Shared/Persistence/FinanceJSONCoding.swift:97` | Explicit JSON null on a non-optional record field aborts the whole-file decode; migration only heals absent (not null) updatedAt |
| DA-H11 | H | Correctness | Shared | `Shared/Services/AnalyticsEngine.swift:29` | Net-worth history snapshots store base-frozen values with no captured currency; a base-currency change leaves the whole stored history mis-scaled against a single live-reconverted "today" point |
| DA-H12 | H | DataLoss | Shared | `Shared/Services/CloudKitSyncService.swift:1171` | Bootstrap fetch of a remote tombstone deletes a newer local edit with no recency or origin check |
| DA-H13 | H | Correctness | Shared | `Shared/Stores/FinanceStore.swift:658` | Finnhub USD quote stored verbatim into a non-USD holding currency, silently corrupting value (no FX applied) |
| DA-H14 | H | Correctness | Shared | `Shared/Stores/FinanceStore.swift:929` | Merge-import (and remote sync) creates duplicate same-day snapshots that adjustHistoricalSnapshots double-corrects |
| DA-M01 | M | DataLoss | iOS | `iOS/Views/Forms.swift:78` | AmountInputFormatter's hardcoded 8-fraction-digit cap truncates high-precision crypto/investment quantities and prices on every editor round-trip, silently corrupting synced data |
| DA-M02 | M | UX | macOS | `macOS/MacPlatformServices.swift:95` | MacLockView.task auto-fires the biometric prompt on every appearance and can race the manual Unlock button |
| DA-M03 | M | Privacy | macOS | `macOS/MacRootView.swift:57` | macOS has no privacy shield: financial data stays composited when the app deactivates (window snapshot / Mission Control / screenshot leak) |
| DA-M04 | M | Bug | macOS | `macOS/Views/MacCashFlowView.swift:320` | macOS cash-flow chart keys bars/hover on short "MMM" label, collapsing same-month-different-year columns on the 12M range |
| DA-M05 | M | Accessibility | macOS | `macOS/Views/MacCashFlowView.swift:732` | macOS transaction card's tap-to-edit gesture is not exposed to VoiceOver/Switch Control |
| DA-M06 | M | Performance | macOS | `macOS/Views/MacCashFlowView.swift:838` | Transactions tab re-sorts + re-filters the full transaction array ~4x per render on every search keystroke |
| DA-M07 | M | Accessibility | macOS | `macOS/Views/MacDashboardView.swift:1101` | Custom DashboardSegmentedPicker segments are invisible to VoiceOver and not keyboard-operable |
| DA-M08 | M | UX | iOS+macOS | `macOS/Views/MacEditorSheet.swift:75` | Toggling transaction Type silently wipes the in-progress custom-category name in all four transaction editors |
| DA-M09 | M | Correctness | iOS+macOS | `macOS/Views/MacEditorSheet.swift:237` | Investment/crypto editors let a holding save with a blank/zero current price, silently zeroing its net-worth contribution |
| DA-M10 | M | Correctness | Shared | `Shared/Models/FinanceModels.swift:386` | gainLossPercent / savingsRate / category percentage use `> 0` guard, silently returning 0% for a negative denominator |
| DA-M11 | M | Correctness | Shared | `Shared/Models/FinanceModels.swift:397` | Imported currency-less crypto/investment holdings default to USD and get FX-mangled for non-USD base users |
| DA-M12 | M | Correctness | Shared | `Shared/Models/MoneyDecimal.swift:23` | Decimal(finite:) returns .some(NaN) for a finite Double that overflows Decimal's range, silently violating its no-NaN contract |
| DA-M13 | M | Correctness | Shared | `Shared/Models/MoneyDecimal.swift:78` | AmountInputFormatter.string(Decimal) caps at 8 fraction digits, silently truncating high-precision crypto/investment quantities on a no-op editor save |
| DA-M14 | M | Security | iOS | `Shared/Persistence/FinancePersistence.swift:87` | Legacy-file migration copyItem does not apply complete-until-open file protection to the finance DB |
| DA-M15 | M | Performance | Shared | `Shared/Services/AnalyticsEngine.swift:140` | carryingForwardDailyGaps materializes one point per calendar day over full history on every dashboard render (range .all, uncapped, uncached) |
| DA-M16 | M | Performance | Shared | `Shared/Services/AnalyticsEngine.swift:140` | carryingForwardDailyGaps materializes an uncapped one-point-per-day array for a wide 'ALL' range on the un-memoized chart hot path |
| DA-M17 | M | Security | iOS+macOS | `Shared/Services/BiometricLockStore.swift:110` | Biometric enrollment changes are not detected: a newly-added fingerprint/face silently unlocks the app |
| DA-M18 | M | Bug | Shared | `Shared/Services/CloudKitSyncService.swift:1836` | .serverRejectedRequest lumped into .recordGone → unbounded clear+requeue loop silently reported as Up-to-Date |
| DA-M19 | M | DataLoss | Shared | `Shared/Services/FinanceImportService.swift:171` | Merge import of Transaction records always overwrites existing rows because imported transactions get updatedAt = import time |
| DA-M20 | M | Correctness | iOS+macOS | `Shared/Services/RecurringNotificationService.swift:73` | Recurring-due notification stamps the amount with the display currency code, not the schedule's own currency, and never converts it |
| DA-M21 | M | UX | Shared | `Shared/Services/RecurringScheduleBuilder.swift:50` | Editing a lapsed (auto-deactivated) recurring schedule does not reactivate it unless frequency or startDate changes |
| DA-M22 | M | Correctness | Shared | `Shared/Stores/FinanceStore.swift:244` | Retroactive snapshot edits stamp back-dated foreign-currency deltas at today's FX rate, mixing rate epochs in net-worth history |
| DA-M23 | M | Correctness | Shared | `Shared/Stores/FinanceStore.swift:244` | Back-dated foreign-currency transactions fold a today-rate delta into historical snapshots frozen at capture-time rates |
| DA-M24 | M | Correctness | Shared | `Shared/Stores/FinanceStore.swift:389` | Recurring dedupe's 1-second date tolerance misses re-imported occurrences, double-generating transactions and double-adjusting snapshots |
| DA-M25 | M | Performance | Shared | `Shared/Stores/FinanceStore.swift:605` | CoinGecko /search resolution loop fires sequential requests with no proactive pacing, tripping the demo-tier rate limit |
| DA-M26 | M | Performance | Shared | `Shared/Stores/FinanceStore.swift:687` | refreshMarketPrices runs appendSnapshot + full save even when no price actually changed |
| DA-M27 | M | Performance | iOS+macOS | `Shared/Stores/FinanceStore.swift:756` | Uncached cash-flow/category analytics (monthlyCashFlow, expensesByCategory, cashFlowTrend) plus an O(n) re-sorting transactions.filter().count recompute on every hover/resize body invalidation |
| DA-M28 | M | DataLoss | Shared | `Shared/Stores/FinanceStore.swift:907` | importBackup mutates in-memory data and reports success even when a load-time localPersistenceError makes save() a silent no-op |
| DA-M29 | M | Bug | iOS+macOS | `Shared/UI/DesignSystem.swift:283` | AllocationChart uses slice name as identity, so duplicate-named crypto slices double-highlight on hover and collide in the legend ForEach |
| DA-M30 | M | Privacy | iOS+macOS | `Shared/UI/DesignSystem.swift:303` | AllocationChart center overlay leaks slice share percentage in Privacy Mode |
| DA-M31 | M | Architecture | iOS+macOS | `WealthCompassMobile.entitlements:9` | CloudKit push entitlement (aps-environment) and remote-notification background mode missing — CKSyncEngine subscription pushes are never delivered |
| DA-L01 | L | Security | iOS | `Resources/iOS/Info.plist:4` | iOS Info.plist declares no explicit App Transport Security stance for the key-carrying finance API hosts |
| DA-L02 | L | Bug | iOS | `iOS/ContentView.swift:12` | 5-hour exchangeRateRefreshTimer is effectively dead: its scenePhase==.active guard means it can only fire after 5h continuous foreground, and the foreground handler already refreshes rates |
| DA-L03 | L | CodeQuality | iOS+macOS | `iOS/ContentView.swift:70` | Recurring-notification sync runs twice on a due-generation pass (explicit call + onChange observer overlap) |
| DA-L04 | L | Performance | iOS | `iOS/Views/CashFlowView.swift:142` | Spending-pie drag gesture re-runs the un-memoized expensesByCategory (filter+group+sort) on every touch sample |
| DA-L05 | L | Correctness | iOS | `iOS/Views/CashFlowView.swift:499` | YTD (and rolling) transaction filter compares startOfDay-stored dates against a timezone-recomputed boundary, dropping day-boundary items after a timezone shift |
| DA-L06 | L | Concurrency | iOS+macOS | `iOS/Views/CashFlowView.swift:551` | Unstructured fire-and-forget Tasks in CashFlow view methods are unowned and never cancelled |
| DA-L07 | L | Correctness | iOS | `iOS/Views/DashboardView.swift:524` | Net-worth change percentage explodes when the range's baseline snapshot is a tiny non-zero value |
| DA-L08 | L | UX | iOS | `iOS/Views/Forms.swift:92` | Type-toggle wipes in-progress custom category text and dismisses the keyboard while picker stays on "Custom..." |
| DA-L09 | L | Correctness | iOS | `iOS/Views/Forms.swift:274` | New recurring schedule's future-only Save guard uses render-time Date(), silently blocks same-day past times with no feedback |
| DA-L10 | L | Correctness | iOS | `iOS/Views/Forms.swift:547` | Investment/Crypto Save allows zero or garbage price (and zero avg buy price), creating degenerate positions |
| DA-L11 | L | Performance | iOS | `iOS/Views/LockView.swift:26` | biometryName / biometrySymbolName allocate a fresh LAContext and call canEvaluatePolicy on every SwiftUI body pass |
| DA-L12 | L | Concurrency | iOS | `iOS/Views/LockView.swift:110` | BiometricLockStore.authenticate has no in-flight guard, so LockView's auto-.task and Unlock button can launch two concurrent LAContext evaluations |
| DA-L13 | L | UX | iOS | `iOS/Views/OnboardingView.swift:322` | Onboarding 'Skip for now' silently discards a just-typed API key without saving or warning |
| DA-L14 | L | UX | iOS | `iOS/Views/SettingsView.swift:65` | Deliberate user-cancel of the biometric prompt sets lastError, surfacing a persistent red 'error' in the Settings Security section |
| DA-L15 | L | Architecture | macOS | `macOS/MacRootView.swift:132` | Settings is reachable via both a sidebar destination and the native Settings scene, so the two MacSettingsView instances keep divergent local UI state |
| DA-L16 | L | Bug | macOS | `macOS/Views/MacCashFlowView.swift:320` | Cash-flow chart joins hover to bars by the localized month label instead of the stable monthKey id |
| DA-L17 | L | UX | macOS | `macOS/Views/MacCashFlowView.swift:842` | Future-dated transactions vanish from the cash-flow table under every period filter except 'All' |
| DA-L18 | L | CodeQuality | macOS | `macOS/Views/MacCashFlowView.swift:993` | Cash-flow chart body and Mac transaction editor duplicated near-verbatim across dashboard and cash-flow views (plus divergent custom-category sentinels) |
| DA-L19 | L | Localization | macOS | `macOS/Views/MacCryptoView.swift:120` | Redundant double-localization: MetricCard status titles wrap an already-resolved String in LocalizedStringKey |
| DA-L20 | L | UX | iOS+macOS | `macOS/Views/MacEditorSheet.swift:79` | Mac transaction/investment/crypto editors omit the active currency code from their amount/price field labels (inconsistent with the recurring editor) |
| DA-L21 | L | Localization | iOS+macOS | `macOS/Views/MacEditorSheet.swift:168` | Interpolating a lowercased localized type/frequency noun into %@ localization templates mangles capitalization and grammar (e.g. German lowercase noun) |
| DA-L22 | L | UX | iOS+macOS | `macOS/Views/MacEditorSheet.swift:199` | Fee mode (fixed vs percent) is not persisted, so percent fees reopen as a frozen fixed amount and stop scaling on re-edit |
| DA-L23 | L | Correctness | macOS | `macOS/Views/MacEditorSheet.swift:341` | Changing the Currency picker on an existing investment/crypto holding relabels the money to the new currency without converting quantity/price, silently misvaluing the position |
| DA-L24 | L | UX | macOS | `macOS/Views/MacInvestmentsView.swift:40` | Three AllocationCharts in a fixed HStack squeeze and truncate legends on narrow detail panes (macOS) |
| DA-L25 | L | Correctness | macOS | `macOS/Views/MacRecurringTransactionEditor.swift:222` | Recurring editor saveSchedule() does not re-validate the 'first occurrence in the future' guard it advertises via the disabled state (impact bounded by downstream forward-clamp) |
| DA-L26 | L | Localization | macOS | `macOS/Views/MacSettingsView.swift:838` | Settings error-alert bodies bypass appLanguage: errorMessage(_:) uses errorDescription (system locale) while titles use settings.localized, yielding mixed-language alerts |
| DA-L27 | L | Correctness | Shared | `Shared/Models/CurrencyConverter.swift:53` | Decimal(finite:) can return a NaN Decimal for extreme finite Doubles, so convert(Decimal)'s `?? value` fallback never fires |
| DA-L28 | L | Correctness | Shared | `Shared/Models/FinanceModels.swift:386` | gainLossPercent uses `costBasis > 0` guard, silently returning 0% for zero- or negative-cost-basis positions |
| DA-L29 | L | ErrorHandling | Shared | `Shared/Persistence/ExchangeRatePersistence.swift:38` | load() leaves a corrupt/invalid exchange-rate file in place instead of clearing it (blocks legacy migration; delays self-heal) |
| DA-L30 | L | ErrorHandling | Shared | `Shared/Persistence/FinancePersistence.swift:51` | Best-effort pre-CloudKit migration backup failure aborts an already-successful load() |
| DA-L31 | L | UX | Shared | `Shared/Services/AnalyticsEngine.swift:163` | chartYDomain over-zooms to a sub-penny hairline band for all-zero or near-zero net-worth series |
| DA-L32 | L | Correctness | Shared | `Shared/Services/AnalyticsEngine.swift:169` | cashFlowTrend uses DateFormatters with no fixed timeZone, so its month bucketing diverges from monthlyCashFlow's calendar-granularity bucketing whenever a non-system-timezone calendar is injected |
| DA-L33 | L | UX | Shared | `Shared/Services/AnalyticsEngine.swift:212` | assetAllocation() silently drops negative net cash, so the allocation pie omits cash and its TOTAL contradicts the NET WORTH header |
| DA-L34 | L | Correctness | iOS+macOS | `Shared/Services/AnalyticsEngine.swift:215` | Investment allocation builders omit the value>0 filter that crypto/asset allocations apply, yielding phantom legend rows |
| DA-L35 | L | Performance | iOS+macOS | `Shared/Services/BiometricLockStore.swift:25` | biometryName()/biometrySymbolName() build a new LAContext and re-probe LocalAuthentication on every SwiftUI body evaluation instead of caching the fixed biometry type |
| DA-L36 | L | UX | iOS+macOS | `Shared/Services/BiometricLockStore.swift:100` | Lock screen shows a persistent red error on benign biometric cancel because unlock() never clears lastError and authenticate() stores every LAError including cancellations |
| DA-L37 | L | DataLoss | Shared | `Shared/Services/CloudKitSyncService.swift:417` | Metadata persist failure commits in-memory state before disk write; if app is killed before the next update, the advance is lost on relaunch |
| DA-L38 | L | ErrorHandling | Shared | `Shared/Services/CloudKitSyncService.swift:444` | CloudSyncMetadataStore.reset() wipes memory then removes the file without re-persisting an empty one, so a removeItem failure leaves stale metadata on disk to resurrect next launch |
| DA-L39 | L | Concurrency | Shared | `Shared/Services/CloudKitSyncService.swift:1306` | Reconcile after fetched-batch await guards only on pending-revision equality; a both-nil case could overwrite a concurrently-applied tombstone (finding's local-delete trigger is incorrect) |
| DA-L40 | L | Correctness | Shared | `Shared/Services/ExchangeRateService.swift:18` | A held currency absent from an otherwise-valid, time-fresh rate snapshot silently converts via its compile-time seed with no staleness signal or forced refresh |
| DA-L41 | L | Localization | Shared | `Shared/Services/ExchangeRateService.swift:67` | Exchange-rate failure message splices an English-only clause ('the last cached rates') into a translated frame in 28 locales |
| DA-L42 | L | Correctness | Shared | `Shared/Services/FinanceImportService.swift:251` | Imported recurring schedule with a date-only endDate on the same day as a timed startDate is dropped (and its final occurrence skipped for notifications) |
| DA-L43 | L | CodeQuality | Shared | `Shared/Services/FinanceImportService.swift:823` | Unnecessary force-unwrap of trimmedForImport in parseDateOnly relies on a non-local parse invariant |
| DA-L44 | L | Correctness | Shared | `Shared/Services/FinanceImportService.swift:823` | parseDateOnly resolves offset-bearing ISO datetimes against a hardcoded UTC calendar, shifting near-midnight records to the wrong day |
| DA-L45 | L | Performance | Shared | `Shared/Services/MarketDataService.swift:302` | JSONDecoder allocated per decode call instead of reused across MarketDataService response types |
| DA-L46 | L | ErrorHandling | Shared | `Shared/Services/MarketDataService.swift:838` | CoinGeckoSimplePriceResponse.init decodes each currency key with `try?`, silently dropping type-mismatched values as if the currency were absent (no diagnostic) |
| DA-L47 | L | Performance | Shared | `Shared/Services/NetworkRetry.swift:22` | NetworkRetry's attempt cap is per-request, so the per-symbol Finnhub investment loop can multiply requests ~3xN during a provider rate-limit event |
| DA-L48 | L | ErrorHandling | Shared | `Shared/Services/NetworkRetry.swift:74` | Retry-After parser handles only delta-seconds; HTTP-date form is ignored and falls back to exponential backoff (impact bounded by the 8s maxDelay clamp) |
| DA-L49 | L | Localization | iOS+macOS | `Shared/Services/RecurringNotificationService.swift:73` | Notification amount formats in the system locale, ignoring the in-app language override |
| DA-L50 | L | CodeQuality | Shared | `Shared/Stores/AppSettings.swift:268` | consecutiveExchangeRateFailures is incremented and persisted uncapped; only the read site clamps it |
| DA-L51 | L | Correctness | Shared | `Shared/Stores/FinanceStore.swift:38` | Future-dated transaction immediately inflates today's net-worth snapshot because calculateTotals has no date filter while adjustHistoricalSnapshots does |
| DA-L52 | L | Concurrency | Shared | `Shared/Stores/FinanceStore.swift:200` | Untracked init-time sync-enable Task can resurrect the CloudKit engine after a factory reset |
| DA-L53 | L | Performance | Shared | `Shared/Stores/FinanceStore.swift:375` | processDueRecurringTransactions does O(occurrences × (transactions + snapshots)) synchronous MainActor work during catch-up, with a per-occurrence linear transaction scan and full snapshot-array rewrite |
| DA-L54 | L | CodeQuality | Shared | `Shared/Stores/FinanceStore.swift:503` | Market-price auto-refresh throttle (lastMarketPriceRefreshAttemptAt) is in-memory only, so it resets on every launch |
| DA-L55 | L | Performance | Shared | `Shared/Stores/FinanceStore.swift:858` | exportBackupURL / importBackup do synchronous full-dataset encode/parse + file I/O on the MainActor |
| DA-L56 | L | Accessibility | iOS+macOS | `Shared/UI/DesignSystem.swift:48` | chartGeography palette duplicates adjacent oranges and is warm-only, hurting slice/legend distinguishability and colorblind safety |
| DA-L57 | L | Performance | iOS+macOS | `Shared/UI/DesignSystem.swift:95` | ScreenBackground runs a perpetual repeatForever animation behind every screen and restarts it on each language-driven root recreation |
| DA-L58 | L | Performance | iOS+macOS | `Shared/UI/DesignSystem.swift:263` | AllocationChart recomputes total and reallocates value arrays on every hover tick, re-rendering the full card including the legend |
| DA-L59 | L | Accessibility | iOS+macOS | `Shared/UI/DesignSystem.swift:366` | AllocationChart legend re-announces slice data as fragmented, duplicate VoiceOver elements |
| DA-L60 | L | Bug | macOS | `Shared/UI/DesignSystem.swift:600` | MacSelectorIsland divider tint applied via .background does not recolor the divider hairline |
| DA-L61 | L | Correctness | macOS | `Shared/UI/DynamicMasonryLayout.swift:13` | DynamicMasonryLayout collapses to a zero-width single column when proposed a non-finite/nil width (latent; no current call site triggers it) |
| DA-L62 | L | Accessibility | iOS+macOS | `Shared/UI/MarketDataAPIKeyGuide.swift:109` | Step text inlines raw .white.opacity(0.74) instead of the WCColor text token (consistency, not a contrast regression) |

---

## 🔴 High severity (14)

### DA-H01 — Recurring-notification handler mutates and syncs finance data while the app is locked

- **High** · Concurrency · iOS · confidence: High
- **Location:** `Sources/iOS/ContentView.swift:67`

**Current code**
```swift
        .onReceive(NotificationCenter.default.publisher(for: .recurringTransactionNotificationReceived)) { _ in
            Task { await processRecurringTransactions() }
        }
```

**Problem.** The `.onReceive(NotificationCenter.default.publisher(for: .recurringTransactionNotificationReceived))` handler in ContentView (line 67-69) fires `Task { await processRecurringTransactions() }` with no `appLock.isUnlocked` guard, unlike the two timer handlers immediately above it (lines 60 and 64) which both `guard scenePhase == .active, appLock.isUnlocked else { return }`. `processRecurringTransactions()` calls `finance.processDueRecurringTransactions(settings:)`, which appends due transactions, rewrites snapshot history, and calls `save()` — the local-persistence + CloudKit sync pipeline — then queues `recurringInsertionAlert`. The explicit design comment at lines 112-115 says exactly this work must not run while the lock screen is up.

**Impact.** A recurring-transaction local notification presenting (`willPresent`, line 47) or being tapped (`didReceive`, line 56) while the app is showing LockView (`appLock.isLockEnabled && !appLock.isUnlocked`) triggers this handler. It generates due transactions, writes them to the local JSON DB, records a changeset, and notifies CloudKit — mutating and syncing finance data without the user ever authenticating, defeating the app-lock guarantee. If occurrences were generated, `recurringInsertionAlert` is also queued to appear the instant the lock is dismissed (and may present over the lock/privacy shield during some transitions), leaking that transactions changed before auth.

**Fix.** Add the same lock guard the timer handlers use. Change the handler at line 67-69 to: `.onReceive(NotificationCenter.default.publisher(for: .recurringTransactionNotificationReceived)) { _ in guard appLock.isUnlocked else { return }; Task { await processRecurringTransactions() } }`. Deferring is safe: the `onChange(of: appLock.isUnlocked)` handler (line 51-55) already calls `handleAppBecameActive()` on unlock, which runs `processRecurringTransactions()` (line 118), so any occurrences that came due while locked are generated immediately after the user authenticates. (Do not gate on `scenePhase == .active` here as the timers do — the notification path can legitimately fire on foreground transition; the `appLock.isUnlocked` check alone is the correct and minimal guard, matching `handleAppBecameActive`'s own guard at line 115.)

<details><summary>Verification (checked against current source)</summary>

Verified against current ContentView.swift. Line 67 opens `.onReceive(NotificationCenter.default.publisher(for: .recurringTransactionNotificationReceived))` and line 68 runs `Task { await processRecurringTransactions() }` with NO `appLock.isUnlocked` guard. The two handlers directly above (recurringCheckTimer at line 60, exchangeRateRefreshTimer at line 64) both `guard scenePhase == .active, appLock.isUnlocked else { return }`, so the omission is clearly inconsistent. `processRecurringTransactions()` (line 127) calls `finance.processDueRecurringTransactions(settings:)`, which I confirmed mutates `data.transactions`/`data.recurringTransactions`, calls `adjustHistoricalSnapshots`/`appendSnapshot`, and ends in `save()` (FinanceStore.swift line 445) — and `save()` is the sync pipeline (persists locally, records changeset, notifies CloudKit). It then sets `recurringInsertionAlert` (line 137) if occurrences were generated. `AppNotificationDelegate` posts this notification from both `willPresent` (line 47) and `didReceive` (line 56) in RecurringTransactionNotificationService.swift, so it fires when a notification is presented or tapped while the app is showing LockView. The design comment at lines 112-115 explicitly states sync/recurring/alert must NOT run while the lock screen is up, and `handleAppBecameActive()` re-invokes `processRecurringTransactions()` on unlock (line 118, driven by the `onChange(appLock.isUnlocked)` at line 54), so adding the guard loses nothing — pending occurrences are picked up right after unlock. Finding is accurate on all points; primary line is 67 (the `.onReceive`), with the offending call on line 68.

</details>

---

### DA-H02 — Root editor sheet stays presented over the macOS lock screen when the app locks

- **High** · Privacy · macOS · confidence: High
- **Location:** `Sources/macOS/MacRootView.swift:65`

**Current code**
```swift
.sheet(item: $appModel.editor) { editor in
    MacEditorSheet(editor: editor)
        .environmentObject(finance)
        .environmentObject(settings)
        .appLanguage(settings.appLanguage)
}
```

**Problem.** In MacRootView.swift the `.sheet(item: $appModel.editor)` (line 65) is attached to the outermost `Group` (line 17) that also renders `MacLockView()` in its locked branch (lines 18-20). When the app locks — `appLock.lock()` fires from `onChange(of: scenePhase)` (lines 74-80) on any non-active phase such as minimize/hide/background — `BiometricLockStore.lock()` only sets `isUnlocked = false` (BiometricLockStore.swift lines 95-98) and never clears `appModel.editor`. Since `appModel` is a persistent `@StateObject` environment object, the sheet binding stays non-nil, so an open MacEditorSheet (a transaction/investment/crypto form pre-filled with the user's financial data) remains presented on top of the lock screen. (MacCashFlowView's own local `@State` editor sheet is not affected — it unmounts with the detail subtree; only the root-level `$appModel.editor` sheet leaks.)

**Impact.** The lock screen exists to hide finance data behind biometric auth. A sheet left open over it defeats that: an unauthenticated person who triggers the lock (e.g. the owner minimizes/hides the window) still sees the pre-filled financial form on top of MacLockView, and can keep editing and saving records — a direct privacy leak and lock bypass for exactly the data the lock protects.

**Fix.** Dismiss any presented editor when the app locks. Simplest: add an observer in MacRootView that clears the editor whenever the app becomes locked, e.g. `.onChange(of: appLock.isUnlocked) { _, unlocked in if !unlocked { appModel.editor = nil } }` (this can be merged into the existing `onChange(of: appLock.isUnlocked)` at lines 81-84 by handling the `else` case). Alternatively clear it at the lock site: in the `onChange(of: scenePhase)` else branch (line 78) do `appModel.editor = nil` right before/after `appLock.lock()`. For defense in depth, also move the `.sheet(item: $appModel.editor)` modifier from the outer Group onto the unlocked/onboarded branch (inside the `else` at lines 24-55) so it can never present while `MacLockView` is showing.

<details><summary>Verification (checked against current source)</summary>

Verified against current source. MacRootView.swift line 65 attaches `.sheet(item: $appModel.editor)` to the OUTER `Group` (opened at line 17) — the same Group whose body switches to `MacLockView()` at lines 18-20 when `appLock.isLockEnabled && !appLock.isUnlocked`. Because the sheet modifier sits on the Group (not inside the unlocked branch), its presentation is governed solely by the `$appModel.editor` binding, independent of which branch the Group renders. `BiometricLockStore.lock()` (BiometricLockStore.swift lines 95-98) only sets `isUnlocked = false`; it does NOT touch `appModel.editor`. `appModel` is a `@StateObject` on the App (WealthCompassMacApp.swift line 8) injected as an environment object (line 22), so it survives the lock transition and keeps the sheet presented. I searched all of Sources/macOS/ and found NO code path that sets `appModel.editor = nil` on lock. The trigger is real: `onChange(of: scenePhase)` at MacRootView.swift lines 74-80 calls `appLock.lock()` on any non-`.active` phase (minimize/hide/background). The MacEditorSheet it presents (MacEditorSheet.swift) is a transaction/investment/crypto form pre-filled with the user's finance data. Note: MacCashFlowView has its own separate local `@State editor` sheet (MacCashFlowView.swift line 174) which IS torn down on lock because that view unmounts with the detail subtree — only the root-level `$appModel.editor` sheet leaks. Finding, line citation (65), and High severity are all accurate.

</details>

---

### DA-H03 — macOS re-locks the app on every focus loss (Cmd+Tab / occlusion), forcing constant re-authentication

- **High** · UX · macOS · confidence: High
- **Location:** `Sources/macOS/MacRootView.swift:74`

**Current code**
```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await handleAppBecameActive() }
            } else {
                appLock.lock()
            }
        }
```

**Problem.** In MacRootView.swift the scenePhase observer is `if phase == .active { … } else { appLock.lock() }` (lines 74-80). On macOS, SwiftUI reports `scenePhase == .inactive` whenever the app merely loses active/key-window status — i.e. every Cmd+Tab to another app, click into another app's window, or window occlusion — not just when the app is truly backgrounded. Because the handler treats every non-`.active` phase identically via the bare `else`, any of these transitions calls `appLock.lock()`, which (when biometric lock is enabled) sets `isUnlocked = false` and swaps the root to `MacLockView`, demanding a Touch ID / passcode re-auth on return. The iOS view (ContentView.swift lines 41-50) intentionally hard-locks ONLY on `.background` and covers transient `.inactive` with an opaque `PrivacyShield` overlay for exactly this reason; the macOS view has neither the gating nor the shield.

**Impact.** A Mac user with app-lock enabled who briefly Cmd+Tabs to Safari to copy a stock symbol and then Cmd+Tabs back is forced to re-authenticate every single time — the app deactivates, `scenePhase` goes `.inactive`, and `lock()` fires. This makes the lock feature effectively unusable on Mac and is a stark, undocumented behavioral divergence from the deliberate iOS design (whose WC-L26 comments explicitly call out avoiding re-auth after harmless interruptions). Meanwhile the macOS window still exposes financial data during the transient `.inactive` period because there is no privacy shield.

**Fix.** Mirror the iOS approach. In MacRootView.swift change the handler to hard-lock only on `.background`: `.onChange(of: scenePhase) { _, phase in if phase == .active { Task { await handleAppBecameActive() } } else if phase == .background { appLock.lock() } }`. Then add an opaque privacy overlay so occluded/inactive windows still hide financial data without forcing a re-auth: attach `.overlay { if scenePhase != .active { PrivacyShield() } }` to the root Group (alongside the existing `.overlay(alignment: .top)`). The `PrivacyShield` view already exists privately in ContentView.swift (lines 182-194); the clean move is to promote it to Sources/Shared/UI (it uses only `WCColor`, which is shared) and use it from both platforms rather than duplicating it. Verify by building the Mac target and confirming Cmd+Tab away/back no longer shows MacLockView while the shield covers the window during inactivity.

<details><summary>Verification (checked against current source)</summary>

MacRootView.swift lines 74-80 read `.onChange(of: scenePhase) { _, phase in if phase == .active { Task { await handleAppBecameActive() } } else { appLock.lock() } }`. The bare `else` fires `appLock.lock()` on ANY non-active phase, including `.inactive`. `MacAppLockStore` inherits `lock()` from BiometricLockStore.swift (lines 95-98): when `isLockEnabled`, it sets `isUnlocked = false`, which flips MacRootView's `body` (line 18) to show `MacLockView`, forcing a biometric/passcode re-auth via `unlock()`. On macOS SwiftUI, `scenePhase` transitions to `.inactive` on app deactivation (Cmd+Tab away, clicking another app's window, occlusion) — not only on true backgrounding — so every such transition re-locks the app. The iOS counterpart (ContentView.swift lines 41-50) deliberately hard-locks ONLY on `.background` and covers transient `.inactive` with an opaque `PrivacyShield` overlay (lines 34-40, 182-194), with a comment (lines 42-44) explicitly stating this avoids re-auth after harmless interruptions. macOS has neither the `.background`-only gating nor any privacy shield. Finding is real and present; line 74 is the correct anchor for the `.onChange(of: scenePhase)` handler (the offending `else`/`lock()` is at lines 77-79).

</details>

---

### DA-H04 — macOS locks the app and forces biometric re-auth every time the window loses focus (scenePhase .inactive treated as lock)

- **High** · UX · macOS · confidence: High
- **Location:** `Sources/macOS/MacRootView.swift:78`

**Current code**
```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active {
        Task { await handleAppBecameActive() }
    } else {
        appLock.lock()
    }
}
```

**Problem.** In MacRootView.swift the scenePhase observer (lines 74-80) locks the app on any phase that is not `.active`. On macOS, `scenePhase` transitions to `.inactive` whenever the app stops being frontmost — clicking another app, opening Spotlight, switching Spaces — which routes into the `else` branch and calls `appLock.lock()`. `BiometricLockStore.lock()` (lines 95-98) sets `isUnlocked = false` when the lock is enabled, and MacRootView's top-level `if appLock.isLockEnabled && !appLock.isUnlocked` (line 18) then replaces the entire UI with `MacLockView`. There is no distinction between transient `.inactive` and a real `.background`/terminate, and macOS has no privacy-cover overlay. The iOS ContentView (lines 34-50) already solves this correctly: it hard-locks only on `.background` and covers `.inactive` with an opaque PrivacyShield, so a harmless interruption never forces re-auth. macOS lacks both mechanisms.

**Impact.** A Mac user with app-lock enabled who clicks over to Safari (or opens Spotlight, or switches Spaces) to copy a number, then clicks back to Wealth Compass, is met by the lock screen and must re-authenticate with Touch ID / password on every single focus change. This makes the app-lock feature effectively unusable on macOS and is a hard behavioral regression relative to the correct iOS handling — the exact case iOS was explicitly fixed to avoid (WC-L26).

**Fix.** Stop locking on `.inactive` on macOS. Mirror the iOS approach: only hard-lock on a genuine background/terminate signal, and cover transient `.inactive` with an opaque overlay instead of tearing down the UI. Concretely, change the observer to gate on `.background` only, e.g. `.onChange(of: scenePhase) { _, phase in switch phase { case .active: Task { await handleAppBecameActive() } case .background: appLock.lock() case .inactive: break @unknown default: break } }`, and add an `.overlay { if scenePhase != .active { MacPrivacyShield() } }` (an opaque cover view, analogous to iOS PrivacyShield at ContentView.swift lines 184-194) so financial data isn't exposed while the window is unfocused without forcing re-auth. If a true "lock on screen lock / logout" behavior is desired, drive it from `NSWorkspace.willSleepNotification` / screen-lock distributed notifications rather than from `scenePhase == .inactive`. Note macOS `scenePhase` semantics for `.background` are less crisp than iOS, so verify the `.background` case actually fires on window close/hide before relying on it alone; at minimum, removing the `.inactive` → lock behavior resolves the reported bug.

<details><summary>Verification (checked against current source)</summary>

MacRootView.swift lines 74-80 read: `.onChange(of: scenePhase) { _, phase in if phase == .active { Task { await handleAppBecameActive() } } else { appLock.lock() } }`. The `else` branch fires for EVERY non-active phase, including `.inactive`. On macOS, SwiftUI drives `scenePhase` to `.inactive` when the app resigns frontmost (user clicks another app, opens Spotlight, switches Space), not only `.background`. `appLock.lock()` (BiometricLockStore.swift lines 95-98) sets `isUnlocked = false` whenever `isLockEnabled` is true, and MacRootView line 18 (`if appLock.isLockEnabled && !appLock.isUnlocked { MacLockView() }`) then tears down the whole detail UI and shows the lock screen, forcing biometric/passcode re-auth. The iOS side deliberately does the opposite: ContentView.swift lines 41-50 hard-lock ONLY on `.background` and cover transient `.inactive` with an opaque PrivacyShield overlay (lines 34-40, 184-194). macOS has neither the `.background`-only gate nor any privacy shield, and there is no other scenePhase handling in the macOS sources (grep confirms MacRootView is the only place). The finding is real and present. Cited line 74 points at the `.onChange` opener; the actual lock call is line 78.

</details>

---

### DA-H05 — Transaction rows/cards and recurring rows render the raw amount with the display-currency symbol, skipping the transaction's own currency

- **High** · Correctness · macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:891`

**Current code**
```swift
    private func signedAmount(for transaction: Transaction) -> String {
        guard !settings.isPrivacyMode else { return settings.redactionToken }
        let prefix = transaction.type == .income ? "+" : "−"
        return prefix + settings.privateCurrency(transaction.amount)
    }
```

**Problem.** In MacCashFlowView.swift the per-transaction and per-schedule amount formatters drop the entity's currency. transactionCard (line 773) and signedAmount(for:) (line 891) call `settings.privateCurrency(transaction.amount)` and recurringTransactionRow (line 605) calls `settings.privateCurrency(schedule.amount)`, none passing `sourceCurrency:`. AppSettings.privateCurrency(_:sourceCurrency:) defaults sourceCurrency to nil (AppSettings.swift:337), and AppSettings.convert(_:from:) treats a nil source as already-in-base — no FX is applied. The same defect exists in MacDashboardView.signedAmount (MacDashboardView.swift:791, `settings.formatCurrency(transaction.amount)`), which feeds the Recent Activity list. As a result a transaction/schedule entered in a currency other than the base renders its raw numeric amount labelled with the base-currency symbol. The totals path is correct — AnalyticsEngine.displayAmount converts each transaction from its own currency (AnalyticsEngine.swift:30) — so summary cards and cash-flow/category charts disagree with the individual rows. The editor supports arbitrary per-transaction currencies (MacEditorSheet.swift:80-82,161), so this is reachable for ordinary new data, not just legacy rows.

**Impact.** User base currency = EUR adds a $100 USD expense (via the editor's Currency picker). Recent Activity (dashboard) and the Cash Flow transaction card/list render "−€100.00" with no FX applied, while the Monthly Expenses metric and the cash-flow chart correctly show the converted ~€92. Every foreign-currency transaction and recurring schedule shows a wrong, inconsistent amount in its row while the summary numbers are right, so the user cannot reconcile the two and may misjudge their spending. The larger the FX spread, the larger the discrepancy.

**Fix.** Pass the entity's own currency into the formatter at each row renderer. In MacCashFlowView.swift: line 891 `return prefix + settings.privateCurrency(transaction.amount, sourceCurrency: transaction.currency ?? settings.currency)`; line 773 `Text("\(prefix)\(settings.privateCurrency(transaction.amount, sourceCurrency: transaction.currency ?? settings.currency))")`; line 605 `Text("\(prefix)\(settings.privateCurrency(schedule.amount, sourceCurrency: schedule.currency ?? settings.currency))")`. In MacDashboardView.swift line 791 `return prefix + settings.formatCurrency(transaction.amount, sourceCurrency: transaction.currency ?? settings.currency)` (and any ActivityRow that formats a raw amount). Passing `?? settings.currency` is equivalent to passing nil (convert no-ops on a base/nil source), so `sourceCurrency: transaction.currency` alone is also acceptable. Best to extract one shared helper (mirroring AnalyticsEngine.displayAmount) so all row renderers stay consistent with the analytics conversion.

<details><summary>Verification (checked against current source)</summary>

Verified against current source. Transaction.currency and RecurringTransaction.currency are Currency? fields (FinanceModels.swift:230, 334). The cited row/card renderers call the formatter WITHOUT sourceCurrency: MacCashFlowView.swift line 605 `Text("\(prefix)\(settings.privateCurrency(schedule.amount))")` (recurring row), line 773 `Text("\(prefix)\(settings.privateCurrency(transaction.amount))")` (transaction card), line 891 `return prefix + settings.privateCurrency(transaction.amount)` (signedAmount); and MacDashboardView.swift line 791 `return prefix + settings.formatCurrency(transaction.amount)` (ActivityRow feed). AppSettings.privateCurrency/formatCurrency default sourceCurrency to nil (AppSettings.swift:298,307,329,337), and convert(_:from:) with a nil source performs no FX (routes through CurrencyConverter treating value as already-in-base). Meanwhile AnalyticsEngine.displayAmount DOES convert per transaction from `transaction.currency ?? displayCurrency` to displayCurrency (AnalyticsEngine.swift:30), and all totals/charts/category breakdowns use it (lines 40-41, 74-77, 178-179, 193). So summary metrics apply FX while individual rows do not. The bug is reachable for real user data, not just legacy rows: MacEditorSheet exposes a Currency Picker over Currency.allCases (MacEditorSheet.swift:80-82) and passes the chosen currency into the new Transaction (line 161), so a EUR-base user can enter a $100 USD expense whose row shows −€100.00 while Monthly Expenses shows the converted ~€92. The WC-M1 backfill (FinanceStore.backfillingCurrencies) only stamps nil legacy rows to base, so it does not mask this for foreign-currency entries.

</details>

---

### DA-H06 — Cash Flow's macOS transaction editor breaks the category Picker for imported/legacy categories (diverged from the sibling MacEditorSheet editor)

- **High** · Architecture · macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:1074`

**Current code**
```swift
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { category in
                            // Localize built-in category names; custom user ones fall through verbatim (WC-M10).
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        Text("Custom...").tag(Self.customCategoryTag)
                    }
```

**Problem.** There are two near-identical ~120-line transaction editors that have diverged. MacCashFlowView.MacCashFlowTransactionEditor (Sources/macOS/Views/MacCashFlowView.swift:986) is presented from the Cash Flow sheet and is used for BOTH creating (editor = .transaction(nil), line 159) and editing existing transactions (lines 733, 803, 825 pass a real Transaction). MacEditorSheet.MacTransactionEditor (Sources/macOS/Views/MacEditorSheet.swift:18) is presented from MacRootView for the Dashboard/sidebar 'Add Transaction'. They duplicate the type/amount/currency/category/custom-category logic and even use different custom-category sentinel strings (`__wealth_compass_mac_custom_category__` at MacCashFlowView.swift:993 vs `__wealth_compass_custom_category__` at MacEditorSheet.swift:23). Critically, MacEditorSheet's category Picker keeps an out-of-list current category selectable via a guard at MacEditorSheet.swift:90-92, but MacCashFlowTransactionEditor's Picker (MacCashFlowView.swift:1073, ForEach at 1074-1077) only renders `categories` (defaults + custom) plus a 'Custom...' row. AppSettings.transactionCategories(for:) (AppSettings.swift:127-133) returns only defaults + custom and does NOT include imported/legacy categories that live on transactions (e.g. the web-app 'Groceries', which is not one of the default keys at AppSettings.swift:6). Editing such a transaction in the Cash Flow editor gives the `$category` binding a value with no matching Picker tag.

**Impact.** User imports a JSON backup with a transaction categorized 'Groceries' (not a default expense category, not in the custom list), then edits it from the Transactions tab on macOS. The `$category` binding equals 'Groceries' but no Picker row has that tag, so SwiftUI logs 'Picker: the selection "Groceries" is invalid' and the control renders blank/mismatched. On Save (finance.updateTransaction), the user can silently overwrite the original imported category with whatever the Picker fell back to — a data-loss risk. The exact same transaction edited from the Dashboard 'Add' path (MacEditorSheet) behaves correctly thanks to its guard, producing inconsistent behavior for identical data. The divergence and mismatched sentinels also make the codebase harder to maintain — a fix applied to one editor is easily missed in the other (as already happened here).

**Fix.** At minimum, port the MacEditorSheet.swift:90-92 guard into MacCashFlowView.swift's category Picker so an out-of-list current category stays selectable. Insert before the ForEach at MacCashFlowView.swift:1074: `if category != Self.customCategoryTag && !categories.contains(category) { Text(LocalizedStringKey(category)).tag(category) }`. Note that MacCashFlowTransactionEditor uses a different sentinel constant name (`Self.customCategoryTag` = `__wealth_compass_mac_custom_category__`), so reference `Self.customCategoryTag` as written there. Better: consolidate to a single reusable transaction editor view used by both entry points (parameterize with an optional Transaction and an onSave closure), so this class of divergence cannot recur; the MacEditorSheet.MacTransactionEditor variant is the more correct starting point but currently lacks the transaction-init for editing, so merge the two initializers.

<details><summary>Verification (checked against current source)</summary>

Verified against current source. Two near-identical macOS transaction editors exist: MacCashFlowView.MacCashFlowTransactionEditor (line 986, presented from the Cash Flow sheet at line 174-201) and MacEditorSheet.MacTransactionEditor (MacEditorSheet.swift:18, presented from MacRootView). The custom-category sentinels differ verbatim: `__wealth_compass_mac_custom_category__` (MacCashFlowView.swift:993) vs `__wealth_compass_custom_category__` (MacEditorSheet.swift:23). MacEditorSheet's Picker DOES carry the out-of-list guard at MacEditorSheet.swift:90-92 (`if category != Self.customCategoryTag && !categories.contains(category) { Text(LocalizedStringKey(category)).tag(category) }`), while MacCashFlowTransactionEditor's Picker (MacCashFlowView.swift:1073 Picker, ForEach at 1074-1077, custom tag at 1078) renders ONLY `categories` + 'Custom...' with no such guard. AppSettings.transactionCategories(for:) (AppSettings.swift:127-133) returns exactly `defaults + custom` and does NOT include imported/legacy categories carried on transactions. Default expense keys (AppSettings.swift:6) are Housing/Food/Transport/Utilities/Fuel/Entertainment/Shopping/Health/Other — 'Groceries' is not among them. The Cash Flow editor IS used to edit existing transactions: lines 733, 803, 825 set `editor = .transaction(transaction)` with a real transaction, and the save closure (line 177-188) calls finance.updateTransaction when `original` is non-nil. So editing an imported 'Groceries' transaction from the Transactions tab gives the Picker a `$category` selection ('Groceries') with no matching tag → SwiftUI 'selection is invalid' warning and a blank/mismatched control, and Save can silently overwrite the category. The exact same data edited via the Dashboard/sidebar path (MacEditorSheet) behaves correctly. All claims hold.

</details>

---

### DA-H07 — Editor seed uses en_US_POSIX '.' but parse tries Locale.current first: 3-fraction-digit values (e.g. crypto quantity 0.125) corrupt 1000x on edit in it_IT/de_DE/etc.

- **High** · Correctness · iOS+macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:356` (also: `Sources/Shared/Models/MoneyDecimal.swift:71`, `Sources/macOS/Views/MacRecurringTransactionEditor.swift:38`, `Sources/iOS/Views/Forms.swift:459`)

**Current code**
```swift
// MacEditorSheet.swift:351-358
private func parse(_ value: String) -> Decimal {
    // Finite, locale-aware parse (WC-H1/M9); inf/nan/garbage → 0, blocked by `> 0` guards.
    MoneyParser.decimal(from: value) ?? 0
}

private static func input(_ value: Decimal) -> String {
    AmountInputFormatter.string(value)   // -> en_US_POSIX '.' seed
}

// MoneyDecimal.swift:71-80  AmountInputFormatter.string
formatter.locale = Locale(identifier: "en_US_POSIX")   // always '.'
// MoneyDecimal.swift:46-47  MoneyParser.decimal step 1
formatter.locale = locale   // Locale.current: in it_IT/de_DE, '.' == grouping
```

**Problem.** AmountInputFormatter.string(_:) (Sources/Shared/Models/MoneyDecimal.swift:71-80) pre-fills editor text fields from the stored Decimal using a hard-coded Locale(identifier: "en_US_POSIX"), so it always emits a '.' decimal separator with no grouping and up to 8 fraction digits. MoneyParser.decimal(from:) (MoneyDecimal.swift:37-60) parses the field back using Locale.current FIRST (step 1) and only falls back to a POSIX '.'-decimal parse (step 2) if step 1 returns nil. In locales where '.' is the grouping separator and ',' is the decimal (it_IT, de_DE, fr_FR, es_ES, ...), step 1's NumberFormatter treats a lone '.' as a thousands separator whenever the fractional part is exactly 3 digits (the grouping group size). So a seed string like "0.125", "1.234", "2.505" or "0.001" is parsed by step 1 as 125 / 1234 / 2505 / 1, dropping the decimal point — a 1000x inflation — BEFORE the correct POSIX fallback can run. Note: the original finding's example "1234.56" is NOT affected (2 fraction digits fail step 1 and are correctly rescued by step 2); the corruption is specific to values whose fractional digit count equals the locale grouping size (3). Every seeded field opened for EDIT is exposed: MacEditorSheet investment quantity/averagePrice/currentPrice/feeValue (seeded via input() -> AmountInputFormatter.string at line 356; parse() at 351-354), crypto equivalents (parse() at 494-497, input() at 499-501), MacRecurringTransactionEditor amount (line 38, parsedAmount at 65-67), and the iOS Forms editors (formatInput seeds at Forms.swift:458-462 and 621-625, with their parse()). New (unseeded) entries are unaffected because their fields start empty and the user types in their own locale, which step 1 handles.

**Impact.** An Italian or German user opens an existing crypto holding of 0.125 BTC (or an investment with a 3-decimal quantity/price) merely to fix a typo in the name and taps Save. parse("0.125") returns 125 via the Locale.current step, so quantity/cost-basis/current-value are recomputed off 125 units instead of 0.125 — a 1000x inflation of that position, silently corrupting net worth. The `parsedQuantity > 0` / finite guards do not catch it because 125 is finite and positive. The corrupted value is persisted to the local JSON DB and pushed to iCloud (CloudKit) via FinanceStore.save(), so it propagates to the user's other devices. Any stored money/quantity whose fractional part is exactly 3 significant digits triggers it, which is routine for crypto quantities and fractional-share counts.

**Fix.** Make seed and parse use the same convention. Cleanest: have MoneyParser.decimal ALWAYS anchor the seeded round-trip to POSIX. Option A (preferred, minimal): when seeding editor fields, keep AmountInputFormatter.string on en_US_POSIX, but change the editor parse helpers to call MoneyParser.decimal(from: value, locale: Locale(identifier: "en_US_POSIX")) so the machine-generated seed is interpreted with the same separators it was produced with — but this breaks free user typing in comma locales. Option B (better for both machine seed and human typing): reorder MoneyParser.decimal so the '.'-as-decimal POSIX interpretation is tried in a way that doesn't let a lone '.' be swallowed as grouping — e.g. in step 1 set formatter.usesGroupingSeparator = false (or reject step-1 results when the input contains a single '.' with a trailing group whose length != 3 handling), OR try the POSIX '.'-decimal parse FIRST for strings that contain '.' but no ',', then fall back to the locale parse. Option C (simplest and symmetric): change AmountInputFormatter.string to format with Locale.current (the same default MoneyParser.decimal uses in step 1) so the seed and the primary parse agree; the fields already accept the user's own separators for typed input, so this makes the whole round-trip consistent. Whichever option, add a unit test that round-trips Decimals with 1..8 fraction digits (especially exactly-3-digit fractions like 0.125, 1.234, 0.001) through AmountInputFormatter.string -> MoneyParser.decimal under Locale it_IT/de_DE and asserts equality.

<details><summary>Verification (checked against current source)</summary>

Confirmed via empirical Swift test, but the finding's mechanism/example is WRONG and must be corrected. AmountInputFormatter.string (MoneyDecimal.swift:71-80) hard-codes Locale(identifier: "en_US_POSIX") and emits '.' as decimal separator with up to 8 fraction digits, no grouping. MoneyParser.decimal (MoneyDecimal.swift:37-60) tries Locale.current FIRST (step 1), then a POSIX '.'-fallback (step 2). I traced which step wins per input. The finding's headline example "1234.56" -> 123456 is FALSE: values with 1, 2, or 4+ fraction digits fail step 1 in it_IT/de_DE and are rescued by the step-2 POSIX fallback, round-tripping correctly. The REAL bug: a seed whose fractional part is EXACTLY 3 digits (matching the locale's 3-digit grouping pattern) is accepted by step 1's it_IT/de_DE formatter, which reads the '.' as a THOUSANDS separator and drops the fraction entirely — 0.125 -> 125, 1.234 -> 1234, 2.505 -> 2505, 0.001 -> 1 (a 1000x inflation). Verified output: stored=0.125 seed="0.125" it_IT parse=125 CORRUPT; stored=1.234 -> 1234 CORRUPT; stored=0.001 -> 1 CORRUPT; while stored=100.25 and 1234.56 round-trip OK. This is common: crypto quantities and share counts frequently have 3 decimals. Corruption passes the `>0` / finite validation and is persisted + iCloud-synced. All cited seed sites are real and confirmed: MacEditorSheet.swift:356 (AmountInputFormatter.string via input()) feeding parse() at 351-354 and 494-497; MacRecurringTransactionEditor.swift:38; iOS Forms.swift formatInput at 458-462 and 621-625 feeding its parse(). Bug affects both platforms.

</details>

---

### DA-H08 — Unknown enum rawValue in the local DB file fails the whole FinancialData decode, making the entire dataset appear empty

- **High** · DataLoss · Shared · confidence: High
- **Location:** `Sources/Shared/Models/FinanceModels.swift:466`

**Current code**
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
    recurringTransactions = try container.decodeIfPresent([RecurringTransaction].self, forKey: .recurringTransactions) ?? []
    investments = try container.decodeIfPresent([Investment].self, forKey: .investments) ?? []
    crypto = try container.decodeIfPresent([CryptoHolding].self, forKey: .crypto) ?? []
    liabilities = try container.decodeIfPresent([Liability].self, forKey: .liabilities) ?? []
    snapshots = try container.decodeIfPresent([NetWorthSnapshot].self, forKey: .snapshots) ?? []
}
```

**Problem.** Currency (FinanceModels.swift:12), TransactionType (:115), InvestmentType (:135) and RecurringTransactionFrequency (:237) are String-backed Codable enums that use only the compiler-synthesized init(from:), which throws DecodingError.dataCorrupted for any rawValue not among the declared cases. FinancialData.init(from:) (:466-474) decodes every collection with the synthesized array decoder (decodeIfPresent([Transaction].self, forKey:)), so a throw inside ANY single element aborts that entire array and the whole FinancialData decode. The local-DB load path is strict end-to-end: LocalFinancePersistence.load (FinancePersistence.swift:45) -> FinanceJSONCoding.decodeFinancialData (FinanceJSONCoding.swift:40; its only pre-decode step backfills updatedAt and does not sanitize enum values) -> decode(FinancialData.self). FinanceStore.load() (FinanceStore.swift:985-996) then catches, sets localPersistenceError, leaves self.data at the empty default (assigned only on success at :969), and returns [:]. Net effect: a single record with an unknown currency/type/frequency string anywhere in wealth-compass-local-data.json makes the user's entire finance dataset appear empty until the file is repaired. Note: the file was written atomically and the failing path does not overwrite it, so the on-disk data is recoverable — the loss is of visibility, not (yet) of bytes. This is distinct from the import path, which is deliberately lossy (LossyArray in FinanceImportService) and does drop just the bad record.

**Impact.** The FinancialData JSON is the shared schema between the Apple app and other producers/versions. If the on-disk local DB ever contains an enum rawValue this build does not know — most realistically because the file was written by a NEWER build that added a Currency/InvestmentType/frequency case and the user then runs an OLDER build (downgrade / TestFlight rollback / multi-device version skew), or because the file was hand-edited or restored from an external source — the whole dataset silently reads as empty. The user sees a blank net-worth app with no explanation of which record is bad, even though their data is intact on disk. Every subsequent load re-fails the same way, so the app is stuck empty until the JSON is manually fixed. Because save() is gated behind a successful load baseline, this also blocks writes/sync, compounding the confusion.

**Fix.** Make the local-DB decode tolerant of one poisoned record instead of failing the whole dataset. Preferred (mirrors the existing forgiving-import stance): in FinancialData.init(from:) decode each collection element-by-element with a lossy wrapper — e.g. reuse/parallel the LossyArray pattern from FinanceImportService.swift:709 (an UnkeyedDecodingContainer loop that try?-decodes each element and skips failures), so a single bad Transaction/Investment/etc. is dropped rather than losing all records of that type. Alternatively (or additionally), give the four enums a custom init(from:) that maps an unknown rawValue to a safe sentinel: add `case other`-style fallbacks for TransactionType/InvestmentType/RecurringTransactionFrequency, and default Currency to the app base currency (EUR) or add an explicit `case unknown`; but per-element lossy decoding is the more robust and consistent fix because it also survives non-enum corruption in a single record. Whichever is chosen, surface a non-fatal count of skipped records (like the import path's skippedRecords) rather than silently zeroing the dataset, and add a unit test decoding a FinancialData JSON containing one record with an unknown currency (e.g. {"transactions":[{"id":"...","type":"income","currency":"RUB",...}]}) asserting the other records still load.

<details><summary>Verification (checked against current source)</summary>

Mechanism confirmed against current source. The String-backed Codable enums (Currency line 12, TransactionType line 115, InvestmentType line 135, RecurringTransactionFrequency line 237) have ONLY the synthesized init(from:) — no @unknown/sentinel — so an out-of-set rawValue throws DecodingError.dataCorrupted. FinancialData.init(from:) (lines 466-474) decodes each collection with the synthesized array decoder via decodeIfPresent([Transaction].self, forKey:), so one bad element aborts the whole array and thus the whole FinancialData decode. The local-DB load path is strict: LocalFinancePersistence.load (FinancePersistence.swift:45-55) -> FinanceJSONCoding.decodeFinancialData (FinanceJSONCoding.swift:40-46, whose only pre-decode step migrateLegacyFinancialDataJSON just backfills updatedAt and does NOT sanitize enum rawValues) -> decode(FinancialData.self). FinanceStore.load() (FinanceStore.swift:958-996) catches, sets localPersistenceError, leaves self.data at the empty default (assigned only on the success path at line 969), and returns [:] — so a single poisoned record makes the entire dataset appear empty. IMPORTANT CORRECTION to the original finding's whyItMatters: the web-app JSON backup does NOT hit this strict path. Import runs through FinanceImportService (ImportedFinancialData at FinanceImportService.swift:28 using LossyArray + per-record compactMap, entry FinanceStore.importBackup line 907), which skips bad records and normalizes to valid Apple enums before save — so an import cannot poison the local DB with an unknown currency. The CloudKit remote-apply path (CloudKitSyncService.swift:311) also decodes per-record and is caught per-record (skip/log), not whole-file. The realistic trigger vectors are therefore narrower than 'any import': (a) a hand-edited local JSON file, (b) a local DB written by a NEWER app build that added an enum case this build lacks (downgrade / forward-compat), or (c) a future schema addition. The whole-dataset-loss mechanism is real; only the likelihood/entry-vector was overstated, which is why I set severity to High rather than Critical.

</details>

---

### DA-H09 — Decimal(finite:) returns a non-finite (NaN) Decimal instead of nil for large finite Doubles, defeating its sanitization contract and poisoning stored/synced money

- **High** · DataLoss · Shared · confidence: High
- **Location:** `Sources/Shared/Models/MoneyDecimal.swift:23`

**Current code**
```swift
    init?(finite value: Double) {
        guard value.isFinite else { return nil }
        self = Decimal(value)
    }
```

**Problem.** `init?(finite value: Double)` in MoneyDecimal.swift guards only the input Double's finiteness (`guard value.isFinite`) and then does `self = Decimal(value)`. But `Decimal(Double)` produces `NSDecimalNumber.notANumber` (prints "NaN", `.isFinite == false`) for finite Doubles whose magnitude exceeds Decimal's representable range (empirically above ~1e128; confirmed for 1e300 and Double.greatestFiniteMagnitude). The initializer never re-checks the resulting Decimal, so it returns a non-finite Decimal as a non-nil success. Its documented promise of "rejecting NaN/Inf" only actually covers Inf and NaN *inputs*, not finite inputs that overflow Decimal.

**Impact.** Two code paths rely on `Decimal(finite:)` returning nil to reject bad money. In FinanceStore.storedPrice (line 708), the callers at lines 658/673 use `guard let price = storedPrice(...) else { continue }` to DROP a bad market price; a large-but-finite converted value (e.g. a mis-fetched or manipulated Finnhub/CoinGecko quote, or a huge quantity*price product) instead yields a NaN Decimal that is written to a holding's `currentPrice` and `currentValue` (line 663-664). In CurrencyConverter.convert (CurrencyConverter.swift:53), `Decimal(finite: converted) ?? value` is meant to fall back to the original value on garbage, but the `?? value` guard never triggers, returning a NaN Decimal. Either way the non-finite Decimal poisons totals, cost-basis and net-worth math, silently fails later `.isFinite` guards, and is persisted to the local JSON DB and synced to iCloud.

**Fix.** In MoneyDecimal.swift, after constructing the Decimal, re-check its finiteness before assigning: replace `self = Decimal(value)` with `let d = Decimal(value); guard d.isFinite else { return nil }; self = d`. The existing `Decimal.isFinite` helper (line 19) correctly detects the notANumber case, so this guard closes the gap and restores the documented contract. No changes are needed at the call sites — they already handle nil correctly (drop the quote / fall back to the original value).

<details><summary>Verification (checked against current source)</summary>

Verified empirically and by tracing call sites. `init?(finite:)` (MoneyDecimal.swift:23-26) guards only `value.isFinite` on the input Double, then does `self = Decimal(value)`. A Swift test confirms `Decimal(1e300)` (and `Decimal(Double.greatestFiniteMagnitude)`) yields a Decimal that prints `NaN`, whose `.isFinite` helper returns false, and which `== NSDecimalNumber.notANumber` — yet the initializer returns it non-nil. So the documented contract ("Builds a finite Decimal ... rejecting NaN/Inf", line 21) is broken: it can hand back a non-finite Decimal for any finite Double above roughly 1e128 in magnitude. Both consumers rely on the nil-return: (1) FinanceStore.storedPrice (line 708) returns `Decimal(finite: converted)` and its two callers (lines 658, 673) use `guard let ... else { continue }` to DROP a bad quote — with a NaN Decimal returned non-nil, the drop is defeated, and lines 663-664 write `currentPrice = <NaN Decimal>` and `currentValue = quantity * price` (also NaN), which then persist and sync to iCloud. (2) CurrencyConverter.convert (CurrencyConverter.swift:53) does `Decimal(finite: converted) ?? value`, intending to keep the original value on garbage — but the `?? value` fallback never fires for the large-finite case, so a NaN Decimal is returned instead. The proposed fix (re-check `Decimal.isFinite` on the constructed value) is correct: the existing `Decimal.isFinite` helper (line 19) correctly detects the NaN case. Trigger requires an extreme finite value (~>1e128), unreachable with legitimate market data but reachable via a malformed/manipulated Finnhub/CoinGecko response (fetched directly, no proxy validation), keeping this High but not Critical.

</details>

---

### DA-H10 — Explicit JSON null on a non-optional record field aborts the whole-file decode; migration only heals absent (not null) updatedAt

- **High** · DataLoss · Shared · confidence: High
- **Location:** `Sources/Shared/Persistence/FinanceJSONCoding.swift:97`

**Current code**
```swift
        for index in records.indices where records[index]["updatedAt"] == nil {
            guard let fallbackValue = fallbacks.lazy.compactMap({ records[index][$0] }).first else {
                continue
            }
            records[index]["updatedAt"] = fallbackValue
            changed = true
        }
```

**Problem.** addUpdatedAt (FinanceJSONCoding.swift:97) backfills `updatedAt` only when the key is truly absent — its guard `records[index]["updatedAt"] == nil` is false for a JSON `null`, which JSONSerialization represents as `NSNull` (NSNull is not == nil in Swift, test-confirmed). So a record carrying `"updatedAt": null` is left untouched. The record structs (Transaction, RecurringTransaction, Investment, CryptoHolding, Liability, NetWorthSnapshot) use synthesized Codable, which ignores stored-property defaults and calls `decode(Date.self, forKey:)`; that throws `valueNotFound` on the null. Because FinancialData.init(from:) decodes plain (non-element-lossy) `[Transaction]` arrays via decodeIfPresent, one throwing element aborts the entire FinancialData decode. The same applies to any non-optional, non-defaulted field decoded as null (amount, date, name, symbol, currency, etc.). Note: the app's own encoder never emits null on these non-optional fields, so the realistic trigger is a legacy/web JSON export (the documented web<->Apple interchange format) or a partially-written/hand-edited file where a JSON `null` lands on a non-optional field.

**Impact.** A legacy or web-exported backup (the documented JSON interchange point between the web app and the Apple app) that contains an explicit `"updatedAt": null` — or a null on any other non-optional field — fails the whole-file decode. FinanceStore.load's catch then leaves the in-app dataset empty and shows the "The local database could not be loaded" banner: the user sees zero transactions/investments/etc. The on-disk file is preserved (load only rewrites on migration, and the throw precedes any write), so the data is recoverable — but if the user, seeing an empty app, adds or edits anything, save() persists the empty-plus-new dataset over the good file, at which point the original records are permanently lost. The addUpdatedAt migration was written specifically to heal missing timestamps so the file still decodes, but it misses the null-present shape it is meant to protect against.

**Fix.** Two-part fix. (1) In addUpdatedAt (FinanceJSONCoding.swift:97), treat NSNull as missing so the fallback backfill also fires for null-present timestamps: change the loop guard to `for index in records.indices where records[index]["updatedAt"] == nil || records[index]["updatedAt"] is NSNull` (and set `records[index]["updatedAt"] = fallbackValue` as today). (2) For robustness against null on OTHER non-optional fields (amount/date/name/symbol/currency), make the top-level collection decodes element-lossy so a single unrecoverable record is dropped instead of aborting the entire file. Introduce a LossyArray-style wrapper that decodes each element in its own do/catch, and use it in FinancialData.init(from:) (FinanceModels.swift:468-473) — e.g. `transactions = (try container.decodeIfPresent(LossyArray<Transaction>.self, forKey: .transactions))?.elements ?? []`. Together these ensure a foreign/partial file still loads with as much valid data as possible rather than showing an empty dataset. Add a unit test that decodes a FinancialData JSON containing one record with `"updatedAt": null` and asserts the other records survive.

<details><summary>Verification (checked against current source)</summary>

Verified against current source and empirically with a standalone Swift 6.3.2 test. (1) Line 97 guard `records[index]["updatedAt"] == nil` is `false` for a JSON `null`: JSONSerialization stores it as `NSNull`, and `["updatedAt": NSNull()] == nil` evaluates to `false` (test-confirmed), so `addUpdatedAt` skips null-present records and never heals them. (2) The record types Transaction (FinanceModels.swift:220), RecurringTransaction (:322), Investment (:367), CryptoHolding (:390), Liability (:411), NetWorthSnapshot (:420) all use SYNTHESIZED Codable — only FinancialData has a custom init(from:) (:466). Synthesized decoders do NOT honor stored-property default values; `var updatedAt: Date = Date()` still decodes via `decode(Date.self)`, which throws `valueNotFound: Expected value of type Date but found null` on a JSON null (test-confirmed). This is also why the migration exists: even an ABSENT updatedAt throws keyNotFound, so addUpdatedAt is load-bearing — it just misses the null-present shape. (3) FinancialData.init(from:) (:468-473) decodes plain `[Transaction]` via decodeIfPresent — NOT element-lossy — so one throwing element aborts the whole file decode. (4) LocalFinancePersistence.load (FinancePersistence.swift:45-55) rethrows; FinanceStore.load outer catch (FinanceStore.swift:985-996) leaves `data` at the empty initial FinancialData() and shows an error banner. Correction to the finding: it is NOT fully silent (an error message is surfaced) and the on-disk file is preserved (load only rewrites when wasMigrated, and the throw happens before any write) — so the dataset appears empty in-app but the original JSON is recoverable until the user makes an edit that saves the empty state over it. This is the local load path, not the intentionally-lossy Imported* import decoders, so it is in scope.

</details>

---

### DA-H11 — Net-worth history snapshots store base-frozen values with no captured currency; a base-currency change leaves the whole stored history mis-scaled against a single live-reconverted "today" point

- **High** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:29`

**Current code**
```swift
private func displayAmount(_ transaction: Transaction) -> Decimal {
    converter.convert(transaction.amount, from: transaction.currency ?? displayCurrency, to: displayCurrency)
}
// ... calculateTotals() sums displayAmount()/convert() live at current displayCurrency,
// while snapshotsForChart(currentNetWorth:) splices that live total onto stored history:
//   points[lastIndex] = NetWorthPoint(date: now, value: currentNetWorth)   // line 119
// Stored history was frozen by SnapshotEngine.adjustingHistoricalSnapshots:
//   snapshots[index].netWorth += liquidityDelta   // liquidityDelta = settings.convert(delta, from: currency) at edit time
```

**Problem.** NetWorthSnapshot persists absolute netWorth/liquidity/totalAssets as plain Decimals with no field recording which currency or exchange rate they were captured in. Two write paths bake in the current display currency: appendSnapshot stores calculateTotals() (live-converted at capture time), and adjustHistoricalSnapshots rewrites past rows by a delta already converted via settings.convert(delta, from: currency) at edit time. At read time, AnalyticsEngine.snapshotsForChart returns the frozen stored history but replaces/appends today's point with currentNetWorth from calculateTotals(), which re-converts ALL current holdings live at the current display currency and current FX rates (AnalyticsEngine.swift displayAmount line 30, calculateTotals lines 37-52, today-point override lines 116-123). Because changing the base currency (SettingsView.swift:45 / MacSettingsView.swift:233 → AppSettings.currency didSet at AppSettings.swift:11-12) only writes UserDefaults and triggers no snapshot re-derivation, the stored history keeps the OLD base's numeric magnitude while the live terminal point is computed in the NEW base. The two ends of the chart are then on different currency bases. Even without a base change, a foreign-currency-holding user gets a live-reconverted "today" point adjacent to rate-frozen stored history, so the last segment can move from FX drift alone.

**Impact.** After the user changes their base/display currency (e.g. JPY → EUR), the net-worth chart renders the entire stored history at the previous currency's magnitude (values ~100x larger) while only the final live point sits at the new currency's magnitude. The result is a grossly mis-scaled line and y-axis domain (chartYDomain is driven by those mixed-magnitude values), i.e. the history looks like a near-vertical cliff down to today's point that corresponds to no real change in wealth. In the milder same-base case (foreign-currency assets, rates refreshed), the latest point re-converts at today's rates while the immediately preceding stored point is frozen at its capture-time rate, producing a spurious jump. Either way the displayed history no longer represents the user's actual wealth trajectory in a single consistent currency.

**Fix.** Unify the two paths onto one consistent conversion. Preferred: recompute the historical liquidity series from transactions at read time using the current converter/displayCurrency (the same live conversion calculateTotals uses), exactly as carryingForwardDailyGaps already reconstructs gaps at render time — then no stored per-row currency is needed and history + today are always on one base. If stored snapshots must remain the source of truth for investments/crypto/liabilities, add a captured base Currency + the capture-time rate snapshot (or store each snapshot component already normalized to a canonical currency, e.g. EUR, and convert to displayCurrency only at read time in snapshotsForChart/snapshots) so a later base change re-derives all points consistently. Also drive the terminal "today" point through the same conversion as the stored series rather than mixing a live-converted total with base-frozen history. Concretely: stop adjusting stored snapshots by a display-converted delta (adjustHistoricalSnapshots) and stop storing display-converted totals (appendSnapshot) in a currency-ambiguous way; instead persist a canonical/base-tagged value and convert once, in AnalyticsEngine at read time.

<details><summary>Verification (checked against current source)</summary>

Verified end to end. NetWorthSnapshot (FinanceModels.swift:420-431) stores absolute netWorth/liquidity/totalAssets as plain Decimals with NO captured base currency or FX rate. Transaction edits push a delta into stored history via adjustHistoricalSnapshots(liquidityDelta: settings.convert(delta, from: currency)) (FinanceStore.swift:244,254,266,270) — the delta is converted to the CURRENT display currency at edit time and baked in permanently (SnapshotEngine.swift:50-54 mutates liquidity/totalAssets/netWorth by that frozen number). At render, snapshotsForChart (FinanceStore.swift:764-767) reads those frozen stored points AND splices in a live "today" point = currentNetWorth from calculateTotals, which re-converts every transaction live at current rates and current displayCurrency (AnalyticsEngine.swift:29-31 displayAmount → converter.convert(..., to: displayCurrency); :37-43 totalLiquidity; :99-123 today's point overwrite). The base-currency picker on both platforms binds directly to $settings.currency (iOS SettingsView.swift:45, MacSettingsView.swift:233), whose didSet (AppSettings.swift:11-12) only writes UserDefaults; MacRootView.swift:99 onChange(of: settings.currency) only re-syncs recurring notifications. NOTHING re-derives data.snapshots on a base-currency change. So after switching base currency, the entire stored history keeps OLD-base numeric magnitudes while only the live terminal point is in the NEW base — a real, present discontinuity. The finding is if anything understated: for a base change it is not a one-day cliff but the whole history line left mis-scaled versus a single new-base terminal point, which also corrupts chartYDomain (AnalyticsEngine.swift:158-166). The milder same-base FX-drift variant also holds because adjacent stored-vs-live points can diverge on rate movement alone.

</details>

---

### DA-H12 — Bootstrap fetch of a remote tombstone deletes a newer local edit with no recency or origin check

- **High** · DataLoss · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:1171`

**Current code**
```swift
            if remoteIsDeleted {
                let shouldKeepLocalSave: Bool
                if case .save(_, _, _, let allowsResurrection)? = state.pending {
                    shouldKeepLocalSave = allowsResurrection
                } else {
                    shouldKeepLocalSave = false
                }

                if shouldKeepLocalSave {
                    state.isTombstone = false
                    pendingToRequeue.insert(key)
                } else {
                    state.pending = nil
                    state.isTombstone = true
                    state.deletedAt = record["deletedAt"] as? Date ?? record.modificationDate ?? Date()
                    metadata.knownLocalHashes.removeValue(forKey: key.storageKey)
                    mutations.append(
                        CloudSyncRemoteMutation(
                            key: key,
                            payload: nil,
                            expectedPendingRevision: originalMetadata.records[key.storageKey]?.pending?.revision
                        )
                    )
                }
                metadata.records[key.storageKey] = state
                continue
            }
```

**Problem.** In handleFetchedRecordZoneChanges, the remoteIsDeleted branch (lines 1171-1197) resolves a fetched soft-delete tombstone purely from the local pending save's allowsResurrection flag, entirely bypassing bootstrapDecision. Because reconcileLocalInventory (lines 456-471, called from start() at line 727 before the first fetch) stamps every locally-present record with pending = .save(origin: .inventory, allowsResurrection: state.isTombstone) and a present record has isTombstone == false, allowsResurrection is false. So when the tombstone arrives, shouldKeepLocalSave is false and the else branch (lines 1182-1194) clears pending, marks the record a tombstone, and applies the delete back to FinanceStore — with no comparison of the tombstone's deletedAt against the local snapshot's updatedAt, and no check of the pending origin. Deletes are soft (makeRecord lines 1069-1077 set isDeleted=true), so this branch is the actual delete-propagation path. Notably even a deliberate local edit routed through recordLocalChanges (origin .localChange) is destroyed here, although bootstrapDecision (line 1618) treats .localChange as an unconditional local win. allowsResurrection is true only for a record that was itself a local tombstone being resurrected, so it never protects a genuine local edit against a remote delete.

**Impact.** Device B deletes transaction X and syncs its tombstone. Device A (fresh install / never synced, offline) edits X — a strictly newer change. On A's first sync, start() reconciles X as pending .save with allowsResurrection=false, then fetches B's tombstone. The remoteIsDeleted branch deletes A's locally-edited X unconditionally, with no updatedAt-vs-deletedAt comparison. The user's newer edit is silently and irrecoverably lost, even though every non-deleted conflict on the sibling path goes through bootstrapDecision's newer-local-wins logic. This is exactly the class of first-sync data loss bootstrapDecision was built to prevent, but the delete case was never routed through it.

**Fix.** During bootstrap (metadata.bootstrapCompleted == false), route the remote-delete-vs-local case through the same recency/origin logic as bootstrapDecision instead of relying only on allowsResurrection. Concretely, in the remoteIsDeleted branch: read the tombstone's deletedAt (record["deletedAt"]) and, when a localSnapshot exists, keep the local value (set shouldKeepLocalSave = true → state.isTombstone = false, pendingToRequeue.insert(key)) if the pending origin is .localChange or .delete, OR if localSnapshot.updatedAt > tombstone deletedAt. Only apply the delete (the current else branch) when the tombstone is at least as new as the local value and the local pending is not a deliberate edit. Leave the post-bootstrap path (bootstrapCompleted == true, where remote wins by design) unchanged. Add a CloudSyncCoreTests case asserting that a bootstrap tombstone with deletedAt older than a local .inventory/.localChange edit resolves to keep-local (requeue), and that an older local value is still deleted.

<details><summary>Verification (checked against current source)</summary>

The remoteIsDeleted branch in handleFetchedRecordZoneChanges (lines 1171-1197) runs before, and completely independent of, bootstrapDecision. It decides whether to keep the local value SOLELY from the pending save's allowsResurrection flag (line 1173-1177); it never consults bootstrapDecision, never compares the tombstone's deletedAt (available at line 1185 / record["deletedAt"]) against the local snapshot's updatedAt, and never checks the pending origin (.inventory vs .localChange).

I confirmed the trigger conditions: deletes are SOFT deletes (makeRecord, lines 1069-1077, sets isDeleted=true + deletedAt and no payload), so a remote delete arrives on the receiving device as a modification in event.modifications and hits this exact branch — not the hard-deletion path at 1259. On a first sync (bootstrapCompleted==false), localRecords is fully populated (line 1146-1148), and start() calls reconcileLocalInventory(currentRecords) at line 727 before any fetch. For a locally-present record, reconcileLocalInventory (lines 456-471) sets pending = .save(..., origin: .inventory, allowsResurrection: state.isTombstone). Since a normal present record has state.isTombstone == false, allowsResurrection == false. When the tombstone is then fetched, shouldKeepLocalSave == false, so the else branch (lines 1182-1194) executes: state.pending = nil, state.isTombstone = true, and a delete mutation is applied back to FinanceStore — silently discarding the local edit with zero recency comparison. The behavior is even broader than the finding states: a deliberate local edit that went through recordLocalChanges (origin .localChange, line 494-499) ALSO carries allowsResurrection == false, so it too is deleted here, whereas bootstrapDecision (line 1618) treats .localChange as an unconditional local win. allowsResurrection is true only when the local record was itself already a tombstone being re-created, so it never protects a legitimate local edit against a remote delete. No test in CloudSyncCoreTests covers the remote-tombstone-vs-local-edit bootstrap case, so this is not documented intended behavior. Line numbers in the finding are accurate (branch at 1171; reconcile logic at 460-467). Severity High is appropriate: silent, unrecoverable user-data loss on first sync.

</details>

---

### DA-H13 — Finnhub USD quote stored verbatim into a non-USD holding currency, silently corrupting value (no FX applied)

- **High** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:658`

**Current code**
```swift
guard let price = storedPrice(quote.price, from: quote.currency, to: data.investments[index].currency, settings: settings) else { continue }
// ...
private func storedPrice(
    _ price: Double,
    from sourceCurrency: Currency?,
    to holdingCurrency: Currency,
    settings: AppSettings
) -> Decimal? {
    let converted = settings.convert(price, from: sourceCurrency ?? holdingCurrency, to: holdingCurrency)
    return Decimal(finite: converted)
}
```

**Problem.** Finnhub's /quote never reports a currency, so FinnhubQuoteClient.quote returns MarketPriceQuote.currency == nil (MarketDataService.swift:317). In the refresh apply loop, storedPrice(quote.price, from: quote.currency, to: holding.currency, ...) is called at FinanceStore.swift:658 with a nil source currency, and storedPrice (lines 701-709) maps nil to the holding's own currency (`sourceCurrency ?? holdingCurrency`), making settings.convert a no-op. Finnhub is queried FIRST for every investment (line 556), only falling back to Yahoo on a Finnhub noQuote error (lines 559-563). Because Finnhub /quote prices are quoted in the listing's native trading currency (USD for US listings), a US-listed stock tracked in a non-USD holding (e.g. AAPL in a holding whose currency is EUR) gets the raw USD price written straight into currentPrice/currentValue as the holding currency with no FX conversion. The H2 "never re-base a holding's currency" comments assume the raw Finnhub number is already in the holding currency — true only when holding currency == listing currency, false for any mismatched-currency holding.

**Impact.** A user holding AAPL with currency=EUR: Finnhub returns c≈190.0 (USD). storedPrice converts EUR→EUR (no-op) and stores 190.0 as EUR, so currentValue = quantity * 190 EUR. The true value (~175 EUR) is off by the full USD/EUR spread (~8-9%). Since Finnhub carries US listings, the request succeeds and never falls through to the Yahoo path that would convert correctly. Net worth, allocation charts, and the synced iCloud copy are all wrong, and each refresh silently overwrites any previously-correct manually-entered price. The error is invisible to the user because no failure is reported.

**Fix.** Finnhub /quote is denominated in the listing's trading currency, which /quote does not return but /stock/profile2 does (`currency` field). Preferred: fetch and cache each symbol's listing currency (via /stock/profile2) and set MarketPriceQuote.currency to it so storedPrice performs the correct FX hop. Alternatively (b) tag a nil Finnhub currency as .usd (the dominant case for Finnhub's free US coverage) instead of nil, so storedPrice at least converts USD→holding for the common case — but this is wrong for the minority of non-USD Finnhub listings. Or (c) only use Finnhub for holdings whose currency is .usd and route non-USD holdings straight to the Yahoo fallback (which returns the native currency at MarketDataService.swift:712 and converts correctly). Document whichever guarantee is chosen and update the H2 comments at FinanceStore.swift:655-657 and 697-699 and MarketDataService.swift:314-316, which currently misstate that a nil Finnhub currency is safe to treat as the holding's currency.

<details><summary>Verification (checked against current source)</summary>

Traced the full path. FinnhubQuoteClient.quote returns MarketPriceQuote(price: price, currency: nil, ...) at MarketDataService.swift:317 — Finnhub's /quote genuinely reports no currency. In FinanceStore.refreshMarketPrices, Finnhub is tried FIRST for every investment regardless of the holding's currency (line 556: `investmentQuotes[investment.id] = try await finnhubClient.quote(...)`), with Yahoo used only as a fallback on a Finnhub `noQuote` error (lines 559-563). The apply loop calls `storedPrice(quote.price, from: quote.currency, to: data.investments[index].currency, ...)` at line 658 with quote.currency == nil. storedPrice (lines 701-709) does `settings.convert(price, from: sourceCurrency ?? holdingCurrency, to: holdingCurrency)` — mapping nil to the holding's own currency, making the conversion a no-op. Finnhub /quote prices are denominated in the listing's native trading currency (USD for US listings), so a US-listed stock (which Finnhub does carry, so it never falls through to Yahoo) tracked in a non-USD holding stores the raw USD figure as the holding currency with no FX applied. The Yahoo fallback (decodeChart, line 712) does return the native currency and would convert correctly — confirming the discrepancy is Finnhub-specific. The extensive H2 comments defend the nil→holding-currency mapping as intentional, but that assumption is only valid when holding currency == listing currency; it silently corrupts value when they differ. This is not one of the documented intentional design decisions. The cited line 658 is accurate.

</details>

---

### DA-H14 — Merge-import (and remote sync) creates duplicate same-day snapshots that adjustHistoricalSnapshots double-corrects

- **High** · Correctness · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:929`

**Current code**
```swift
// FinanceStore.swift:929 (merge import — UUID-keyed merge, no per-day dedup)
        case .merge:
            data = data.merged(with: normalized.data).sortedForStorage()

// FinanceModels.swift:536-548 (mergedByID — appends any new UUID)
    func mergedByID(with incoming: [Element]) -> [Element] {
        var merged = self
        for item in incoming {
            if let index = merged.firstIndex(where: { $0.id == item.id }) {
                if item.updatedAt > merged[index].updatedAt { merged[index] = item }
            } else {
                merged.append(item)   // foreign-UUID same-day snapshot appended here
            }
        }
        return merged
    }

// SnapshotEngine.swift:50 (delta applied to EVERY same-day row)
        for index in snapshots.indices where snapshots[index].date >= startOfDay {
            snapshots[index].liquidity += liquidityDelta
            snapshots[index].totalAssets += liquidityDelta
            snapshots[index].netWorth += liquidityDelta
        }
```

**Problem.** Snapshot identity is inconsistent across code paths. The normal write path (SnapshotEngine.appendingSnapshot, SnapshotEngine.swift:33) treats a snapshot's identity as its calendar DAY, upserting via calendar.isDate(_, inSameDayAs:). But the merge-import path treats identity as the UUID `id`: FinancialData.merged (FinanceModels.swift:559) calls Array.mergedByID (FinanceModels.swift:536-548), which appends any incoming snapshot whose UUID isn't already present. Imported backups carry their own UUIDs, so merging a backup whose snapshot for, e.g., 2026-06-01 differs in UUID from the local 2026-06-01 row produces TWO rows for that day. sortedForStorage() (FinanceStore.swift:1242-1258) only sorts snapshots by date and does not dedupe, so both rows persist. The CloudKit remote-apply path has the same defect: CloudKitSyncService.applying (line 315) upserts snapshots by value.id, so a foreign-UUID same-day snapshot syncing in also creates a duplicate-day row. The concrete harm then surfaces through SnapshotEngine.adjustingHistoricalSnapshots (SnapshotEngine.swift:50), which applies a liquidity delta to EVERY row with date >= startOfDay(from) — so both same-day rows receive the delta and the retroactive correction is double-applied. This is invoked on every recurring-transaction backfill (FinanceStore.swift:396) and on transaction add/edit/delete (lines 244, 254, 266, 270). Note: snapshotsForChart (AnalyticsEngine.swift:102-112) DOES dedupe to one point per day, so the chart does not show two points — the bug is stored-data corruption of the surviving row's value, plus an inflated snapshots count in Settings.

**Impact.** Import (mode .merge) a backup that contains a snapshot dated 2026-06-01 with a UUID different from the local 2026-06-01 snapshot. After merge, data.snapshots holds two rows for 2026-06-01. Now add/edit/delete any transaction dated on or before 2026-06-01, or let a recurring backfill run for an occurrence on/before that date: adjustHistoricalSnapshots iterates both same-day rows and adds the liquidity delta to each. snapshotsForChart keeps the latest-by-timestamp of the two rows, so the chart's 2026-06-01 net-worth value is now off by exactly one delta (double-corrected) for every retroactive edit — silent, cumulative history corruption. The same duplicate-day state can also arise purely from CloudKit sync of a foreign-UUID snapshot. Settings' snapshot count is also inflated.

**Fix.** Collapse snapshots to one-per-day after any UUID-keyed merge. In FinancialData.merged, post-process the merged snapshots array: group by Calendar.current.startOfDay(for: $0.date) and keep one per day (prefer the greater updatedAt; tie-break on the later date). Alternatively add a day-keyed reducer helper and call it from both importBackup (.merge, FinanceStore.swift:929) and the CloudKit remote-apply integration point where remote snapshots land, so foreign-UUID same-day snapshots are folded into the existing day rather than appended. A defensive belt-and-suspenders option is to make adjustingHistoricalSnapshots operate on distinct days, but the correct fix is to never store more than one snapshot per day, matching the invariant appendingSnapshot already enforces. Add a unit test: merge a FinancialData whose snapshots share a day (different UUID) with the local set, assert exactly one snapshot per day survives, then run adjustHistoricalSnapshots and assert the delta is applied once per day.

<details><summary>Verification (checked against current source)</summary>

Verified against current source. FinancialData.merged (FinanceModels.swift:552-560) merges snapshots via Array.mergedByID (line 536-548), which matches on UUID `id` and appends any snapshot whose id isn't already present (line 543-544). NetWorthSnapshot's canonical id is a fresh UUID (FinanceModels.swift:421), so a merge-imported backup carrying its own UUIDs will append a second row for any day already present locally. Everywhere else the app treats a snapshot's identity as its calendar DAY: SnapshotEngine.appendingSnapshot upserts by calendar.isDate(_, inSameDayAs:) (SnapshotEngine.swift:33), and adjustingHistoricalSnapshots iterates every row with date >= startOfDay (SnapshotEngine.swift:50). sortedForStorage() only sorts snapshots by date with no dedup (FinanceStore.swift:1256). So merge import genuinely produces two same-day snapshot rows with different UUIDs, and there is no collapse step. The real corruption is confirmed: adjustHistoricalSnapshots (called on every recurring backfill at FinanceStore.swift:396 and on transaction add/edit/delete at lines 244/254/266/270) applies the liquidity delta to BOTH same-day rows, doubling the retroactive correction for that day. The CloudKit remote-apply path is also UUID-keyed (CloudKitSyncService.swift:315 upserts by value.id), so a foreign-UUID same-day snapshot arriving via sync creates the same duplicate condition. ONE correction to the original finding: the claim that snapshotsForChart 'now sees two points for that day' is FALSE — AnalyticsEngine.snapshotsForChart (lines 102-112) explicitly dedupes to one point per calendar startOfDay, keeping the latest by timestamp, so the chart never renders two points for one day. The genuine harm is the stored-snapshot corruption (double-applied deltas), which then flows into the chart as a wrong netWorth value, not as a duplicate point. finance.data.snapshots.count (SettingsView.swift:234, MacSettingsView.swift:442) also reflects the inflated count.

</details>

---

## 🟠 Medium severity (31)

### DA-M01 — AmountInputFormatter's hardcoded 8-fraction-digit cap truncates high-precision crypto/investment quantities and prices on every editor round-trip, silently corrupting synced data

- **Medium** · DataLoss · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/Forms.swift:78`

**Current code**
```swift
// Sources/Shared/Models/MoneyDecimal.swift L71-80
static func string(_ value: Decimal) -> String {
    guard value.isFinite, value != 0 else { return "0" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 8   // <-- caps precision; contradicts the "isn't truncated" docstring
    return formatter.string(from: value as NSDecimalNumber) ?? "0"
}
// Sources/iOS/Views/Forms.swift L621-623 (crypto seed) and L722-723 (blind overwrite on save)
_quantity = State(initialValue: holding.map { Self.formatInput($0.quantity) } ?? "")
let rawAverage = holding.map { $0.quantity > 0 ? max(0, (($0.avgBuyPrice * $0.quantity) - $0.fees) / $0.quantity) : 0 } ?? 0
_avgBuyPrice = State(initialValue: holding == nil ? "" : Self.formatInput(rawAverage))
// ... item.quantity = parsedQuantity ; item.avgBuyPrice = effectiveAverage
```

**Problem.** AmountInputFormatter.string(_ value: Decimal) hardcodes maximumFractionDigits = 8 (Sources/Shared/Models/MoneyDecimal.swift L78), contradicting its own docstring which promises a lossless pre-fill. Both iOS editors use it to seed their text fields from stored Decimals: CryptoFormView seeds quantity via Self.formatInput($0.quantity) (Forms.swift L621) and seeds avgBuyPrice by reconstructing (($0.avgBuyPrice * $0.quantity) - $0.fees) / $0.quantity then formatting it (L622-623); InvestmentFormView does the analogous thing for quantity and a (costBasis - fees)/quantity average (L458-461). formatInput -> AmountInputFormatter.string (Forms.swift L737-739). On Save both views unconditionally re-parse those seeds and overwrite the stored model: CryptoFormView.save() sets item.quantity = parsedQuantity and item.avgBuyPrice = effectiveAverage (Forms.swift L722-723); InvestmentFormView.save() sets item.quantity = parsedQuantity and item.costBasis = (parsedQuantity * parsedAverage) + calculatedFee (L574-575). There is no "field untouched -> keep original Decimal" guard, so a no-op edit of an unrelated field (e.g. renaming the symbol) round-trips quantity and per-unit price through the 8-digit format and back. Any holding whose quantity or reconstructed average has more than 8 fraction digits is silently truncated. The reconstruct-by-division at Forms.swift L622 and L459 makes this worse: dividing by quantity commonly yields a non-terminating decimal that the 8-digit cap rounds even when the underlying value was exact. Because FinanceStore.save() diffs SHA256 per record, the truncated values are recorded as a real changeset, persisted to the local JSON DB, and (if iCloud sync is on) pushed to CloudKit, overwriting the precise stored copy everywhere. The identical formatter is also used by the macOS editors (MacEditorSheet.swift L357/L500), so the corruption is not iOS-only.

**Impact.** A user with an 18-decimal token position of quantity 0.123456789012345 opens the holding just to fix a typo in the name and taps Save. quantity is reseeded as "0.12345679", parsed back, and written over the stored Decimal, permanently losing 7+ digits; the cost basis (quantity * avgBuyPrice) and every downstream total, gain/loss, and net-worth snapshot shift. The reconstructed average adds a second drift: e.g. a stored avgBuyPrice of 41234.123456789 reseeds as 41234.12345679. The change is invisible in the UI (both old and new render the same at display precision), is written to the synced iCloud copy, and accumulates on every subsequent edit round-trip — classic silent, cumulative data corruption of money records.

**Fix.** Do not let the seed formatter cap precision below what is actually stored. Two complementary fixes: (1) In AmountInputFormatter.string(_ value: Decimal) (MoneyDecimal.swift L71-80) derive maximumFractionDigits from the Decimal's own scale instead of hardcoding 8 — e.g. let exponent = value.exponent; formatter.maximumFractionDigits = max(8, exponent < 0 ? -exponent : 0) — so a value with N stored fraction digits round-trips losslessly (guard against a pathological huge scale by clamping to a sane ceiling like 20). (2) Stop the destructive reconstruct-by-division and blind overwrite: for an existing holding, only recompute quantity/avgBuyPrice/costBasis from the parsed text when the user actually changed that field. Track per-field edited flags, and in save() keep the original stored Decimal (holding.quantity, holding.avgBuyPrice, investment.costBasis) for any field left untouched, so a no-op edit can never mutate the underlying value. Apply the same seed/save fix to the macOS editors (MacEditorSheet.swift L357/L500 and the corresponding save paths), since they share AmountInputFormatter.string.

---

### DA-M02 — MacLockView.task auto-fires the biometric prompt on every appearance and can race the manual Unlock button

- **Medium** · UX · macOS · confidence: Medium
- **Location:** `Sources/macOS/MacPlatformServices.swift:95`

**Current code**
```swift
        .task {
            await appLock.unlock(appLanguage: settings.appLanguage)
        }
    }
}
```

**Problem.** MacLockView (Sources/macOS/MacPlatformServices.swift) attaches `.task { await appLock.unlock(appLanguage:) }` (lines 94-96) that automatically presents the LAContext biometric/passcode sheet whenever the lock view appears, in addition to the manual "Unlock" button (lines 72-78) that calls the same `unlock`. Because MacRootView locks on any non-active scene phase (`.onChange(of: scenePhase)` → `appLock.lock()`, MacRootView.swift line 78) and re-renders MacLockView from scratch via its `if !isUnlocked` conditional (MacRootView.swift lines 18-19), the `.task` re-fires and re-presents the auto prompt every time the app regains focus on macOS — with no user intent. Compounding this, `BiometricLockStore.unlock` → `authenticate` builds a fresh `LAContext()` on each call (BiometricLockStore.swift line 114) and there is no guard against a second in-flight `unlock()`. If the user taps "Unlock" while the auto-prompt is still up, two `evaluatePolicy` calls run concurrently on separate contexts; a failed/cancelled attempt only records `lastError` and does nothing to stop the prompt re-firing on the next appearance. The identical pattern exists in iOS LockView (Sources/iOS/Views/LockView.swift lines 67-69 and 39-40).

**Impact.** On macOS the user is shown an unsolicited system Touch ID / device-passcode sheet every time the app window regains focus (e.g. after clicking away to another app and back), which is intrusive. If they tap the visible Unlock button while the auto prompt is already presented, two authentication requests race and can produce a confusing double prompt or a spurious error string in `lastError`. Because nothing gates re-firing on failure, a cancelled prompt simply pops again on the next refocus.

**Fix.** Make auto-prompting one-shot per lock episode and serialize unlock attempts. Concretely: (1) In MacLockView add `@State private var hasAutoPrompted = false` and guard the `.task` with `guard !hasAutoPrompted else { return }; hasAutoPrompted = true` before calling `unlock`, and reset it via `.onChange(of: appLock.isUnlocked) { _, unlocked in if !unlocked { hasAutoPrompted = false } }` so the next lock episode auto-prompts once. Alternatively drop the auto `.task` entirely and rely on the explicit Unlock button. (2) Add a concurrency guard in BiometricLockStore: e.g. an `@Published private(set) var isAuthenticating` set true at the start of `unlock`/`authenticate` and false on completion, early-return if already true, and disable the Unlock button (`.disabled(appLock.isAuthenticating)`) while a request is in flight. Apply the same fix to iOS LockView for parity.

---

### DA-M03 — macOS has no privacy shield: financial data stays composited when the app deactivates (window snapshot / Mission Control / screenshot leak)

- **Medium** · Privacy · macOS · confidence: High
- **Location:** `Sources/macOS/MacRootView.swift:57`

**Current code**
```swift
        .overlay(alignment: .top) {
            if let persistenceError = finance.persistenceError {
                PersistenceErrorBanner(message: persistenceError)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // ...no `if scenePhase != .active { PrivacyShield() }` overlay exists...
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await handleAppBecameActive() }
            } else {
                appLock.lock()   // guard isLockEnabled else { return } => no-op when lock is off
            }
        }
```

**Problem.** iOS ContentView overlays an opaque PrivacyShield (ContentView.swift:182-194) whenever `scenePhase != .active` (lines 34-40), covering the app-switcher snapshot and transient interruptions regardless of whether the biometric lock is enabled. MacRootView has no equivalent: its only `.overlay` (MacRootView.swift:57-63) is the persistence-error banner, and its sole reaction to leaving `.active` (lines 74-80) is `appLock.lock()`. Because `lock()` is `guard isLockEnabled else { return }` (BiometricLockStore.swift:95-98), when the app-lock is disabled deactivation does nothing and the full dashboard (balances, holdings) remains the window's composited content — visible in Mission Control, App Exposé, the Dock window preview, screen recordings, and window screenshots. Even with the lock enabled, `lock()` only flips a @Published flag; MacLockView appears only after SwiftUI re-renders the `Group`, a race against AppKit's window-image capture on deactivation, and there is no NSWindow occlusion or `applicationWillResignActive` hook (MacAppDelegate, MacPlatformServices.swift:13-35, has none) to force the cover in first.

**Impact.** A macOS user who has NOT enabled the biometric lock (the common case, since the lock is opt-in) gets zero deactivation privacy: switching apps, triggering Mission Control/Exposé, hovering the Dock icon for a window preview, or taking a windowed screenshot all show their full net worth and holdings. The iOS build treats this exact exposure as a real threat and closes it with the shield; macOS leaves it open. Even users who DID enable the lock get only best-effort protection because the SwiftUI re-render races the window-snapshot capture, so the cached/composited image can still be the data rather than the lock screen.

**Fix.** Add a privacy overlay to MacRootView mirroring iOS. After the existing banner overlay (around MacRootView.swift:57-63), add `.overlay { if scenePhase != .active { MacPrivacyShield() } }`, and define a macOS shield (opaque `WCColor.background` ZStack with a `lock.shield.fill` glyph, `.ignoresSafeArea()`) analogous to ContentView's private PrivacyShield. Gate it on `scenePhase != .active` only (not on `appLock.isLockEnabled`) so it protects even when the lock is off. Because AppKit captures the window image on deactivation, back it with an AppKit hook that hides window content synchronously before backgrounding — e.g. in MacAppDelegate observe `NSApplication.willResignActiveNotification` and set the key window's `contentView?.isHidden = true` (restore on `didBecomeActiveNotification`), or drive an `@State isObscured` flag from those notifications so the shield is in place before the snapshot is taken rather than after a SwiftUI re-render.

---

### DA-M04 — macOS cash-flow chart keys bars/hover on short "MMM" label, collapsing same-month-different-year columns on the 12M range

- **Medium** · Bug · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:320`

**Current code**
```swift
// line 286 / 297 (chart x-values):
x: .value("Month", month.monthLabel),
...
x: .value("Month", month.monthLabel),

// line 318-321 (hover resolution):
if let monthLabel: String = proxy.value(atX: x) {
    withAnimation(.easeInOut(duration: 0.15)) {
        hoveredCashFlowMonth = trend.first { $0.monthLabel == monthLabel }
    }
}
```

**Problem.** In `cashFlowTrendCard`, both BarMarks set their x-value to `month.monthLabel` (lines 286 and 297), and the hover overlay resolves the hovered month via `trend.first { $0.monthLabel == monthLabel }` (line 320). `monthLabel` comes from AnalyticsEngine.cashFlowTrend where `labelFormatter.dateFormat = "MMM"` (AnalyticsEngine.swift:172), so it is a bare month name ("Jan", "Feb", …) with no year. When `cashFlowRange == .twelveMonths` (a first-class picker option) and `now` is not December, the rolling 12-month window spans two calendar years and repeats a month name (e.g. two "Jul" entries). Swift Charts groups the two identically-labeled string categories into one x-axis column, so the two months' bars are drawn stacked in a single column instead of two, and because `cashFlowTrend` returns the array oldest→newest, `trend.first { ... }` always resolves the OLDER of the two — hovering the newer July highlights and reports the older July's income/expense/net (lines 292/303/341/346/353/362).

**Impact.** On the default 6M range this never triggers (a 6-month window cannot repeat a month name). But 12M is a first-class option and, for most of the year, its window straddles two years and duplicates a month name. In that case the chart merges two distinct months into one bar column (visually hiding a month of data) and the hover legend/NET readout shows the wrong year's figures, materially misrepresenting the user's cash flow.

**Fix.** Key the chart on the unique `monthKey` ("yyyy-MM") instead of `monthLabel`. Change both BarMarks to `x: .value("Month", month.monthKey)` (lines 286, 297) and resolve the hover with `trend.first { $0.monthKey == key }` where `key: String = proxy.value(atX: x)` (line 318/320). Restore the human-readable axis labels with a `.chartXAxis { AxisMarks { value in AxisValueLabel { if let key = value.as(String.self), let m = trend.first(where: { $0.monthKey == key }) { Text(m.monthLabel) } } } }` so the x-axis still shows "Jul" etc. This makes each month a distinct column and makes hover resolution exact, with no id changes needed since CashFlowMonth.id is already monthKey. (Note: the iOS DashboardView cash-flow chart uses months:6 with no hover so it is unaffected, but the same monthKey-based keying would be a safe consistency improvement there.)

---

### DA-M05 — macOS transaction card's tap-to-edit gesture is not exposed to VoiceOver/Switch Control

- **Medium** · Accessibility · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:732`

**Current code**
```swift
ForEach(filteredTransactions) { transaction in
    transactionCard(for: transaction)
        .onTapGesture {
            editor = .transaction(transaction)
        }
}
```

**Problem.** In MacCashFlowView.transactionTable, each card gets `.onTapGesture { editor = .transaction(transaction) }` (line 732) as its primary edit affordance, but the card is not a Button and carries no `.accessibilityAddTraits(.isButton)` or `.accessibilityAction`. A bare onTapGesture is not surfaced to VoiceOver or Switch Control, so the whole-card tap-to-edit interaction is unavailable to assistive-tech users. The card does have a `.contextMenu` and interior Edit/Delete buttons (reachable via VoiceOver), so editing is still technically possible, but the primary discoverable interaction sighted users rely on is not announced as actionable. The team already solved this exact pattern on iOS (CashFlowView.swift lines 398-406, comment WC-L24) with combined accessibility element + .isButton trait + .accessibilityAction; the macOS view was simply never given the same treatment. Secondarily, there is no hover/pressed visual state, so there is no visual cue the card is clickable.

**Impact.** A VoiceOver or Switch Control user navigating the cash-flow list perceives each card as static content plus two small icon buttons; the 'click the card to edit' interaction that the UI is primarily built around is not announced and cannot be activated via the card element. This is a real, inconsistent accessibility regression relative to the iOS app, which handles the identical card list correctly.

**Fix.** Mirror the iOS fix (CashFlowView.swift lines 398-406). On the card in transactionTable, add the same modifiers the iOS view uses: `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits(.isButton)`, and `.accessibilityAction { editor = .transaction(transaction) }` (keep the existing `.onTapGesture` for mouse users, and note the card already sets `.contentShape(Rectangle())` internally). Alternatively wrap the card in a `Button { editor = .transaction(transaction) } label: { transactionCard(for: transaction) }.buttonStyle(.plain)`, which gives the button trait for free. As a secondary polish, add an `.onHover`-driven visual state (e.g. subtle background/scale change) so the clickable affordance is visible to sighted users.

---

### DA-M06 — Transactions tab re-sorts + re-filters the full transaction array ~4x per render on every search keystroke

- **Medium** · Performance · macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:838`

**Current code**
```swift
// MacCashFlowView.swift:702
Text("Showing \(filteredTransactions.count) of \(finance.transactions.count)")
// :722
if filteredTransactions.isEmpty {
// :730
ForEach(filteredTransactions) { transaction in
// :838
private var filteredTransactions: [Transaction] {
    finance.transactions.filter { transaction in
        let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
        let matchesPeriod = transactionStartDate.map { transaction.date >= $0 && transaction.date <= Date() } ?? true
        let matchesSearch = searchText.isEmpty
            || transaction.category.localizedCaseInsensitiveContains(searchText)
            || transaction.description.localizedCaseInsensitiveContains(searchText)
        return matchesType && matchesPeriod && matchesSearch
    }
}
// FinanceStore.swift:211
var transactions: [Transaction] {
    data.transactions.sorted { lhs, rhs in
        if lhs.date == rhs.date { return lhs.createdAt > rhs.createdAt }
        return lhs.date > rhs.date
    }
}
```

**Problem.** In the macOS Cash Flow "Transactions" tab, the filtered list is recomputed several times per body pass and each recompute triggers a full sort of the backing array. `filteredTransactions` (MacCashFlowView.swift:838) reads `finance.transactions`, which itself performs a full `.sorted` on every access (FinanceStore.swift:211-216, no caching). Within one body pass `filteredTransactions` is evaluated at line 702 (`.count`), line 722 (`.isEmpty`), and line 730 (`ForEach`); line 702 additionally reads `finance.transactions.count`, adding another independent sort. Because `searchText`, `transactionTypeFilter`, and `transactionPeriod` are all `@State`, every keystroke/toggle re-runs `body`, and every FinanceStore publish does too. Result: roughly 4 O(n log n) sorts plus 3 full O(n) filter passes (each doing up to two `localizedCaseInsensitiveContains` per row) over the entire transaction set on each keystroke — entirely redundant work.

**Impact.** With a large transaction library (a few thousand rows), typing in the search field or flipping a filter re-sorts and re-filters the whole dataset ~4 times per character, causing visible input latency/stutter on the Transactions tab. localizedCaseInsensitiveContains is comparatively expensive per call, and it runs on every non-early-rejected row on every one of the repeated passes. All of the repeated sorting/filtering is wasted — the result is identical across the three-plus evaluations in a single render.

**Fix.** Compute the filtered list exactly once per render and reuse it. Simplest: extract the Transactions tab into a subview (e.g. `TransactionsTabView`) that computes `let all = finance.transactions` (one sort) and derives `let filtered = all.filter { ... }` once, then passes `all.count` / `filtered` into the filter bar, empty-state check, and ForEach. This collapses the four `finance.transactions` sorts and three filter passes down to one sort + one filter per render. Optionally hoist the sort out of the FinanceStore.transactions computed property (or memoize it) so callers do not each pay for a fresh sort. If profiling still shows cost at scale, pre-lowercase `category`/`description` (or compare against a lowercased `searchText` with `range(of:options:.caseInsensitive)`), but computing once is the primary win.

---

### DA-M07 — Custom DashboardSegmentedPicker segments are invisible to VoiceOver and not keyboard-operable

- **Medium** · Accessibility · macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacDashboardView.swift:1101`

**Current code**
```swift
ForEach(items) { item in
    let isSelected = selection == item
    Text(labelProvider(item))
        .font(.caption.weight(isSelected ? .bold : .medium))
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
        .frame(minWidth: 44)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = item
            }
        }
}
```

**Problem.** DashboardSegmentedPicker<SelectionValue> (Sources/macOS/Views/MacDashboardView.swift, 1091-1132) draws each option as a plain Text with .contentShape(Rectangle()) + .onTapGesture to mutate the binding. The segments carry no accessibility semantics: no Button, no .accessibilityAddTraits(.isButton), no .isSelected trait, no .accessibilityLabel/.accessibilityValue, and the control is not focusable so it never enters the macOS key-view loop. The picker is used for the net-worth TimeRange (MacDashboardView.swift:214), the dashboard cash-flow window (MacDashboardView.swift:493), and the cash-flow window in MacCashFlowView (MacCashFlowView.swift:274). The same views use native Picker controls elsewhere (MacDashboardView.swift:625; MacCashFlowView.swift:385/654/693), which are natively accessible — highlighting the regression this custom control introduces.

**Impact.** On macOS, a VoiceOver user hears the segments as static text with no activation, and a keyboard-only user cannot Tab to or arrow through the control. Both are therefore unable to change the net-worth time range or the cash-flow window from these pickers at all, while all the surrounding native controls remain operable — an inconsistent, WCAG-failing accessibility gap for a control that is otherwise a core dashboard filter.

**Fix.** Give each segment button semantics and make the control focusable. Minimal change: replace the `Text(...).contentShape(Rectangle()).onTapGesture { ... }` (lines 1101, 1114-1119) with a `Button { withAnimation(...) { selection = item } } label: { Text(labelProvider(item)) ... }` using `.buttonStyle(.plain)` to preserve the visual capsule design, then add `.accessibilityAddTraits(isSelected ? [.isSelected] : [])` and an `.accessibilityLabel(Text(labelProvider(item)))` per segment. Buttons are keyboard-focusable on macOS so this restores the key-view loop and .isButton trait automatically. If preserving the exact tap animation without Button chrome is required, instead wrap each Text in `.accessibilityElement(children: .ignore)` + `.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)` + `.accessibilityLabel(...)` + `.accessibilityAction { withAnimation(...) { selection = item } }` and add `.focusable()` (with a FocusState-driven keyboard handler) so it joins the focus loop.

---

### DA-M08 — Toggling transaction Type silently wipes the in-progress custom-category name in all four transaction editors

- **Medium** · UX · iOS+macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:75` (also: `Sources/macOS/Views/MacEditorSheet.swift:70`, `Sources/macOS/Views/MacRecurringTransactionEditor.swift:107`)

**Current code**
```swift
.onChange(of: type) { _, newType in
    // Only reset category when changing type if the current one isn't valid for the new type (L7)
    if !settings.transactionCategories(for: newType).contains(category) && !isCustomCategorySelected {
        category = settings.transactionCategories(for: newType).first ?? ""
    }
    customCategory = ""
    isCustomCategoryFocused = false
}
```

**Problem.** In the onChange(of: type) handler, the guard that reassigns `category` is correctly skipped when "Custom..." is selected (`&& !isCustomCategorySelected`), so `category` stays on the customCategoryTag sentinel. But the following two statements — `customCategory = ""` and `isCustomCategoryFocused = false` — run UNCONDITIONALLY, so flipping the Type segment while "Custom..." is chosen erases whatever custom name the user has typed. Since `category` itself does not change, the onChange(of: category) handler never fires to compensate. The picker still shows "Custom..." selected and the custom TextField stays visible, but its text is now empty. `selectedCategoryName`/`currentCategoryName` becomes "", so Save is disabled. This exact pattern is present in four places: MacEditorSheet.swift MacTransactionEditor (defect line 75), MacRecurringTransactionEditor.swift (line 112), and iOS Forms.swift in both the transaction editor (line 92) and the recurring editor (line 292). On the Mac transaction editor the only feedback is a passive hint ("Enter a category name...") from customCategoryHint; the Mac recurring editor surfaces a validationMessage; but in every case the typed text is destroyed with no undo.

**Impact.** A user types a custom category such as "Consulting", realizes it should be Income instead of Expense, and flips the Type segment. Their typed category vanishes and Save greys out — on the Mac transaction editor with only a passive greyed hint rather than an active error against the field. They must notice the empty field and retype the name. This is avoidable data-entry friction plus a confusing dead Save button; the type toggle is a natural thing to do mid-entry precisely because Type and Category are adjacent in the form.

**Fix.** Only clear the in-progress custom name when the type change actually resets the category — i.e. do NOT clear it while "Custom..." is selected. In each of the four onChange(of: type) handlers, move `customCategory = ""` / `isCustomCategoryFocused = false` inside the same `if` that reassigns `category`, or guard them with `if !isCustomCategorySelected { customCategory = ""; isCustomCategoryFocused = false }`. Concretely in MacTransactionEditor (MacEditorSheet.swift ~70-77): `if !settings.transactionCategories(for: newType).contains(category) && !isCustomCategorySelected { category = settings.transactionCategories(for: newType).first ?? ""; customCategory = ""; isCustomCategoryFocused = false }`. Apply the mirror change to MacRecurringTransactionEditor.swift (~107-114) and to both editors in iOS Forms.swift (~87-94 and ~287-294). This preserves the typed custom name across Type toggles while keeping the existing reset behavior for the non-custom case.

---

### DA-M09 — Investment/crypto editors let a holding save with a blank/zero current price, silently zeroing its net-worth contribution

- **Medium** · Correctness · iOS+macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:237` (also: `Sources/macOS/Views/MacEditorSheet.swift:403`, `Sources/iOS/Views/Forms.swift:700`)

**Current code**
```swift
// MacEditorSheet.swift:237-239 (MacInvestmentEditor)
private var isSaveDisabled: Bool {
    symbol.trimmed.isEmpty || name.trimmed.isEmpty || parsedQuantity <= 0
}
// MacEditorSheet.swift:403-405 (MacCryptoEditor) — identical predicate
// Forms.swift:547 (InvestmentFormView): .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0)
// Forms.swift:700 (CryptoFormView): same three-term .disabled(...)
```

**Problem.** In all four holding editors — macOS MacInvestmentEditor (MacEditorSheet.swift:237-239) and MacCryptoEditor (403-405), plus iOS InvestmentFormView (Forms.swift:547) and CryptoFormView (Forms.swift:700) — the Save-disabled predicate only checks that symbol and name are non-empty and quantity > 0. It never validates currentPrice or averagePrice. The private parse(_:) helpers coerce blank or unparseable input to 0 (MacEditorSheet.swift:351-354, 494-497; Forms.swift:587-591, 731-735), and every price field defaults to an empty string on a fresh add. Consequently a user can enable Save with the Current Price (and/or Average Buy Price) box empty. save() then persists currentValue = parsedQuantity * parsedCurrentPrice = 0 (MacEditorSheet.swift:326/339, Forms.swift:556/563), and a blank average collapses costBasis down to just the fee (MacEditorSheet.swift:319/470, Forms.swift:555/708). The model layer does not crash — Investment/CryptoHolding.gainLossPercent guard costBasis>0 and return 0 (FinanceModels.swift:385-387, 406-408) — but the position is now indistinguishable from a genuinely worthless one.

**Impact.** A user adds a stock or coin, fills symbol + name + quantity, but leaves the current price blank (easy to do on a fresh add before any market refresh). Save is enabled, the holding persists with currentValue = 0, and dashboard net worth silently drops by the real value of that position — with no inline warning — until a market refresh corrects it, which only happens if a valid Finnhub/CoinGecko API key exists and the symbol/coinId resolves. If it never resolves, the holding stays at 0 indefinitely and looks like a 100%-loss or worthless position the user never intended.

**Fix.** Extend the Save-disabled predicate in all four editors to also require a positive current price, and ideally a positive average buy price so cost basis is meaningful. Concretely: in MacEditorSheet.swift change MacInvestmentEditor.isSaveDisabled (237-239) and MacCryptoEditor.isSaveDisabled (403-405) to add `|| parsedCurrentPrice <= 0 || parsedAveragePrice <= 0`; in Forms.swift add the same `|| parsedCurrentPrice <= 0 || parsedAverage <= 0` terms to the `.disabled(...)` expressions at line 547 (InvestmentFormView) and line 700 (CryptoFormView). If a 0 current price is intentionally permitted pre-refresh, at minimum gate on averagePrice > 0 and surface an inline validation message (as RecurringTransactionFormView does via isSaveDisabled/validation) so the user is told the price is missing rather than silently saving a zero-valued holding.

---

### DA-M10 — gainLossPercent / savingsRate / category percentage use `> 0` guard, silently returning 0% for a negative denominator

- **Medium** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Models/FinanceModels.swift:386`

**Current code**
```swift
    var gainLoss: Decimal { currentValue - costBasis }
    var gainLossPercent: Double {
        costBasis > 0 ? (gainLoss.doubleValue / costBasis.doubleValue) * 100 : 0
    }
```

**Problem.** Investment.gainLossPercent (FinanceModels.swift:386), CryptoHolding.gainLossPercent (:407), and MonthlyCashFlow.savingsRate (:492) all guard the denominator with `costBasis > 0` / `monthlyIncome > 0` and return 0 otherwise; AnalyticsEngine.expensesByCategory (AnalyticsEngine.swift:200) does the same with `total > 0`. The `> 0` test protects against divide-by-zero but also swallows the legitimate negative-denominator case. When costBasis or monthlyIncome is negative (a pasted negative value in an editor field, or a refund/correction booked as negative income summing a month's income below zero), these computed properties report 0.0% as if flat, even when the numerator is large and non-zero. The same `> 0` divide pattern is duplicated in the aggregate cards at InvestmentsView.swift:50, CryptoView.swift:50, MacInvestmentsView.swift:103, and MacCryptoView.swift:82. Note import already clamps investment costBasis to non-negative (FinanceImportService.swift:497), so the primary reachable vector is pasted-in negative editor input and negative-amount income transactions, making this an edge case rather than a common path.

**Impact.** A holding whose cost basis has gone negative (mis-entered/pasted `-100`) but whose currentValue is +€5000 has gainLoss = +€5100, yet the dashboard shows "0.0%" gain instead of a meaningful figure — a silently wrong performance number on a finance app. Likewise, a month whose income transactions net negative (refunds booked as income) reports a 0% savings rate instead of surfacing the anomaly. It is not a crash, but the user is shown a plausible-looking-but-wrong money metric with no indication anything is off.

**Fix.** Guard only against zero and non-finite denominators, not sign, and decide the negative-denominator semantics explicitly instead of collapsing to 0. For Investment/CryptoHolding gainLossPercent: `costBasis.isFinite && costBasis != 0 ? (gainLoss.doubleValue / costBasis.doubleValue) * 100 : 0`. For savingsRate: `monthlyIncome.isFinite && monthlyIncome != 0 ? (netSavings.doubleValue / monthlyIncome.doubleValue) * 100 : 0`. For expensesByCategory percentage: `total != 0 ? (value.doubleValue / total.doubleValue) * 100 : 0`. Apply the identical change to the duplicated view-layer computations (InvestmentsView.swift:50, CryptoView.swift:50, MacInvestmentsView.swift:103, MacCryptoView.swift:82). If negative cost basis is considered invalid data, prefer preventing it at input (reject/clamp negative parsed values in the editors) rather than only masking it in the percentage math.

---

### DA-M11 — Imported currency-less crypto/investment holdings default to USD and get FX-mangled for non-USD base users

- **Medium** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Models/FinanceModels.swift:397`

**Current code**
```swift
// FinanceModels.swift:397
var currency: Currency = .usd
// FinanceImportService.swift:587 (ImportedCryptoHolding.model())
currency: Currency.imported(currency, default: .usd),
// FinanceImportService.swift:513 (ImportedInvestment.model()) — same bug
currency: Currency.imported(currency, default: .usd),
// AnalyticsEngine.swift:47-49
let totalCrypto = data.crypto.reduce(Decimal(0)) {
    $0 + convert($1.currentValue, from: $1.currency)
}
```

**Problem.** CryptoHolding.currency is a non-optional `Currency` defaulting to `.usd` (FinanceModels.swift:397). When a JSON backup (web export or old build) contains a crypto holding with a missing/blank `currency` field, ImportedCryptoHolding.model() stamps it `.usd` via `Currency.imported(currency, default: .usd)` (FinanceImportService.swift:587). Investment has the identical bug at line 513. AnalyticsEngine.calculateTotals then FX-converts every crypto and investment holding from its stored `currency` to the display currency (AnalyticsEngine.swift:44-49). So a currency-less holding whose stored amount was really the user's base currency is assumed to be USD and FX-converted by the full USD/base spread. This diverges from how transactions handle legacy missing currency: Transaction/RecurringTransaction use `Currency?` (default nil), are backfilled to the base currency by FinancialData.backfillingCurrencies(base:) on load (FinanceStore.swift:1228-1240), and — until backfill — AnalyticsEngine treats a nil-currency transaction as already-in-display-currency with NO FX (AnalyticsEngine.swift:26-31). There is no equivalent nil-safe/backfill path for crypto or investment; the hardcoded `.usd` also differs from Liability's `defaultCurrency` (line 640) and Transaction's `settings.currency` (line 411) import defaults.

**Impact.** Concrete failure: a user whose base currency is EUR imports a JSON backup containing a crypto holding of 10,000 (which they meant as EUR) with no `currency` field. It decodes as USD. Dashboard totalCrypto and netWorth then show ~10,000 * (USD→EUR rate) ≈ 9,200 EUR instead of 10,000 EUR — a silent ~8% error with no warning, and the same distortion applies to any currency-less investment. Because the wrong currency is persisted, every subsequent net-worth snapshot, allocation pie, and FX-exposure calculation inherits the error. Only USD-base users are unaffected (USD→USD is a no-op).

**Fix.** Align the legacy/missing-currency handling for crypto and investment with the transaction approach. Preferred: in the import layer, default missing crypto/investment currency to the user's base currency rather than a hardcoded `.usd` — change FinanceImportService.swift:587 and :513 from `Currency.imported(currency, default: .usd)` to use the settings base currency (thread `settings.currency` into ImportedCryptoHolding.model()/ImportedInvestment.model(), matching how ImportedLiability uses `defaultCurrency` at line 640 and ImportedTransaction uses `settings.currency` at line 411). More robust alternative: make CryptoHolding.currency and Investment.currency Optional (`var currency: Currency? = nil`), extend FinancialData.backfillingCurrencies(base:) (FinanceStore.swift:1228-1240) to stamp nil crypto/investment currencies with base on load, and update AnalyticsEngine/other read sites to treat nil as `displayCurrency` (no FX) exactly as transactions already do at AnalyticsEngine.swift:30 — this also fixes the synthesized-Codable keyNotFound throw when a locally-decoded record is missing the non-optional currency key. Either way, do NOT leave the hardcoded `.usd` default, and apply the same treatment to Investment since it shares the defect.

---

### DA-M12 — Decimal(finite:) returns .some(NaN) for a finite Double that overflows Decimal's range, silently violating its no-NaN contract

- **Medium** · Correctness · Shared · confidence: High
- **Location:** `Sources/Shared/Models/MoneyDecimal.swift:23`

**Current code**
```swift
    init?(finite value: Double) {
        guard value.isFinite else { return nil }
        self = Decimal(value)
    }
```

**Problem.** `init?(finite value: Double)` in MoneyDecimal.swift (lines 23-26) checks only that the incoming Double is finite (`value.isFinite`), then executes `self = Decimal(value)` and returns the result without re-validating it. When `value` is finite but larger in magnitude than what `Decimal(_:Double)` can represent (empirically once it exceeds roughly 1e148), the conversion produces `NSDecimalNumber.notANumber` — a NaN Decimal. The initializer therefore returns `.some(NaN)` even though its documentation says it "rejects NaN/Inf (WC-H1)". This is the app's single sanctioned Double->money boundary; a NaN Decimal escaping it would be treated as valid finite money by every caller. (The finding's original example of 1e39 is incorrect — Decimal handles values that large fine; the actual overflow point is far higher, near 1e148+.)

**Impact.** If an astronomically large but finite Double ever reaches this boundary, it becomes a NaN Decimal that callers believe is finite money. storedPrice() (FinanceStore.swift:708) would write NaN into an investment/crypto currentPrice, after which AnalyticsEngine totals, NetWorthSnapshot, and finally the `.doubleValue` chart points would all be poisoned — the exact NaN-into-CoreGraphics outcome the Decimal scheme exists to prevent. In CurrencyConverter.convert(_:Decimal) (line 53) the `?? value` fallback is defeated: because the initializer returns `.some(NaN)` instead of `nil`, the NaN propagates instead of falling back to the original value. In practice the trigger requires a garbage payload of magnitude ~1e148+, which no real market quote or FX product reaches, so real-world impact is low; but the function is precisely the defensive boundary that is supposed to make such input impossible, and it currently does not honor that contract.

**Fix.** Re-validate the produced Decimal before assigning: change the body of `init?(finite value: Double)` to `guard value.isFinite else { return nil }; let decimal = Decimal(value); guard decimal.isFinite else { return nil }; self = decimal`. The `Decimal.isFinite` computed property already defined in this same file (line 19) correctly returns `false` for the notANumber case, so it catches the overflow. This makes CurrencyConverter.convert's `?? value` fallback (line 53) engage as intended and makes storedPrice (FinanceStore.swift:708) return nil so the bad quote is dropped, not stored.

---

### DA-M13 — AmountInputFormatter.string(Decimal) caps at 8 fraction digits, silently truncating high-precision crypto/investment quantities on a no-op editor save

- **Medium** · Correctness · Shared · confidence: High
- **Location:** `Sources/Shared/Models/MoneyDecimal.swift:78`

**Current code**
```swift
    static func string(_ value: Decimal) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8   // <-- truncates >8-decimal quantities
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
```

**Problem.** `AmountInputFormatter.string(_ value: Decimal)` in MoneyDecimal.swift sets `maximumFractionDigits = 8`, so any stored quantity with more than 8 fractional digits is rounded when the editor pre-fills its text field — contradicting the method's own doc comment ("a precise stored value isn't truncated"). Both the iOS crypto/investment forms (Forms.swift) and the macOS editor (MacEditorSheet.swift) seed the Quantity field with this formatter and, on Save, re-parse the field and write `item.quantity = parsedQuantity`. So merely opening such a holding and pressing Save — which the user perceives as making no change — rewrites the quantity to a rounded value. High-precision quantities are reachable in practice: JSON import decodes `quantity` as a Double and stores `Decimal(quantity)` (up to ~15-17 significant digits), and manual entry via MoneyParser has no digit cap, while common tokens use 8 (BTC) to 18 (ETH) decimals.

**Impact.** A user editing an existing high-precision crypto/investment holding and tapping Save (intending no change) silently mutates the stored quantity. Because cost basis (quantity*avgBuyPrice) and current value (quantity*currentPrice) are derived from quantity, the rounding corrupts cost basis and gain/loss figures, and because the record's SHA256 snapshot now differs, save() records a changeset and pushes a spurious CloudKit sync of the corrupted record to all the user's devices. The wrong precision persists in the JSON store even though local persistence itself preserves full Decimal precision — only the editor seed loses it.

**Fix.** In the Decimal overload of `AmountInputFormatter.string` (MoneyDecimal.swift:71-80), stop capping precision. Either remove the `maximumFractionDigits = 8` line entirely (NumberFormatter defaults are typically fine for emitting the full Decimal significand, but verify it doesn't reintroduce rounding), or set `formatter.maximumFractionDigits` high enough to preserve any stored quantity — at least 18 to cover ETH-style tokens (e.g. `formatter.maximumFractionDigits = Int.max` or a generous constant like 30). Since the input string round-trips through MoneyParser on save, emitting the full significand is safe. Keep the Double overload at CurrencyConverter.swift:72-81 as-is (it is inherently Double-limited and used for money amounts, not raw quantities), and update the doc comment at MoneyDecimal.swift:69-70 so it accurately reflects the chosen precision. Optionally, guard save() so it does not rewrite quantity when the parsed value is unchanged from the stored one, to avoid spurious mutations more broadly.

---

### DA-M14 — Legacy-file migration copyItem does not apply complete-until-open file protection to the finance DB

- **Medium** · Security · iOS · confidence: Medium
- **Location:** `Sources/Shared/Persistence/FinancePersistence.swift:87`

**Current code**
```swift
        try createStorageDirectoryIfNeeded()
        try fileManager.copyItem(at: legacyURL, to: storageURL)
```

**Problem.** `migrateLegacyFileIfNeeded()` copies the legacy Documents-directory finance DB to the Application Support location with `fileManager.copyItem(at:legacyURL,to:storageURL)` (line 87) and never sets a protection class on the destination. `copyItem` propagates the source file's data-protection attribute instead of the `.completeFileProtectionUnlessOpen` class that every other write in this file applies (backup line 93, main write line 98). The only in-`load()` opportunity to re-write with protection is `write(decoded.data)` at line 52, but it is gated by `if decoded.wasMigrated`, and `wasMigrated` is true only when the JSON schema migration actually changed bytes (adding missing `updatedAt` fields — FinanceJSONCoding lines 40-45). A legacy file already in the current schema therefore skips the protected re-write, and FinanceStore.load() does not force an immediate `save()` unless a currency backfill was needed, so the copied file can remain at a weaker protection class indefinitely.

**Impact.** The migrated file holds the user's full net-worth database. iOS default data protection for a file created in the app's Documents container is `CompleteUntilFirstUserAuthentication` — the file becomes readable after the first post-boot unlock and stays readable while the device is subsequently locked, unlike the intended `completeUnlessOpen` class which keeps it inaccessible while locked. A locked-but-booted device that is imaged/backed up (forensic extraction, malicious backup) can expose the finance DB during this window. For a user who migrates from the legacy build and then only reads the app (never triggers a save), the weakened protection persists for the lifetime of that file, defeating the file-protection guarantee the rest of the persistence layer maintains.

**Fix.** Do not rely on `copyItem` for the protection class. Read the legacy bytes and write them through the protected path, matching the pattern already used in ExchangeRatePersistence.swift line 85: in `migrateLegacyFileIfNeeded()`, replace `try fileManager.copyItem(at: legacyURL, to: storageURL)` with `let bytes = try Data(contentsOf: legacyURL); try bytes.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])`. Alternatively (less robust) keep the copy but immediately follow it with `try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: storageURL.path)`. The Data-write approach is preferred because it is atomic and guarantees the class at creation time rather than after the file already exists unprotected.

---

### DA-M15 — carryingForwardDailyGaps materializes one point per calendar day over full history on every dashboard render (range .all, uncapped, uncached)

- **Medium** · Performance · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:140`

**Current code**
```swift
private func carryingForwardDailyGaps(_ points: [NetWorthPoint]) -> [NetWorthPoint] {
    guard points.count > 1, let first = points.first, let last = points.last else { return points }
    let byDay = Dictionary(points.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
    var result: [NetWorthPoint] = []
    var cursor = calendar.startOfDay(for: first.date)
    let endDay = calendar.startOfDay(for: last.date)
    var lastValue = first.value
    while cursor <= endDay {
        if let real = byDay[cursor] {
            result.append(real)
            lastValue = real.value
        } else {
            result.append(NetWorthPoint(date: cursor, value: lastValue))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return result
}
```

**Problem.** AnalyticsEngine.snapshotsForChart → carryingForwardDailyGaps (Sources/Shared/Services/AnalyticsEngine.swift:133-151) fills every missing calendar day between the first point and the last point by carrying the previous value forward, one NetWorthPoint per day. For range == .all the cutoff in snapshots(range:) is .distantPast (line 88), so `first` is the earliest snapshot in the whole account history and `last` is today's `now` (appended at lines 116-122). The while-loop at lines 140-149 thus iterates once per calendar day from account start to today with no cap. This is invoked with no caching: FinanceStore.snapshotsForChart (FinanceStore.swift:766) builds a fresh AnalyticsEngine per call, and both dashboards call it inside the `netWorthHero` computed view property (DashboardView.swift:118, MacDashboardView.swift:171), which SwiftUI re-evaluates on every body render. The comment at SnapshotEngine.swift:12-16 documents that this render-time fill replaced a materialized carry-forward that was capped at 60 rows; the replacement has no equivalent bound.

**Impact.** A 2-3 year old account viewed at range .all rebuilds ~730-1100+ points from scratch on every dashboard body re-render (scroll, state change, range toggle, live total update), each pass allocating a fresh array that is then handed to Swift Charts to plot. The previous stored carry-forward was capped at 60 rows; this render-time replacement is unbounded and grows one point per day forever, so cost strictly increases with account age. On older devices this shows up as chart jank and wasted main-actor CPU on a hot path (the @MainActor store method runs synchronously in the view body).

**Fix.** Bound and/or cache the output. Concrete options: (1) Cap the point count — after building the gap-filled array (or while building), downsample to at most ~365 evenly spaced points for long ranges so Swift Charts never receives more than a screen's worth of detail; the carry-forward flat-line shape is preserved because collapsed runs are flat anyway. (2) Skip per-day gap-filling entirely once (endDay − firstDay) exceeds a threshold (e.g. > 400 days) and instead emit only the real points plus synthetic points immediately before each real point to keep the flat-then-step visual, avoiding the day-by-day materialization. (3) Memoize in FinanceStore keyed by (a data-version counter bumped on every save, range, and rounded currentNetWorth) so unrelated re-renders reuse the cached array instead of recomputing. Option (1) or (3) is lowest-risk; combining a cap with the cache is best. Whatever the approach, keep the today-alignment (lines 116-122) and the isFinite filtering intact.

---

### DA-M16 — carryingForwardDailyGaps materializes an uncapped one-point-per-day array for a wide 'ALL' range on the un-memoized chart hot path

- **Medium** · Performance · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:140`

**Current code**
```swift
private func carryingForwardDailyGaps(_ points: [NetWorthPoint]) -> [NetWorthPoint] {
    guard points.count > 1, let first = points.first, let last = points.last else { return points }
    let byDay = Dictionary(points.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
    var result: [NetWorthPoint] = []
    var cursor = calendar.startOfDay(for: first.date)
    let endDay = calendar.startOfDay(for: last.date)
    var lastValue = first.value
    while cursor <= endDay {
        if let real = byDay[cursor] {
            result.append(real)
            lastValue = real.value
        } else {
            result.append(NetWorthPoint(date: cursor, value: lastValue))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return result
}
```

**Problem.** In AnalyticsEngine.snapshotsForChart, when the user selects TimeRange.all the cutoff is .distantPast (line 88), so snapshots(range:) returns every stored snapshot. carryingForwardDailyGaps (lines 133-151) then fills gaps by walking calendar day-by-day from the first snapshot's day to the last (the `while cursor <= endDay` loop, lines 140-149), appending one NetWorthPoint per day with no cap. If the earliest snapshot is years old (imported history via ImportedSnapshot, a back-dated first entry, or a long-lived account), this constructs thousands of points. The array is rebuilt from scratch on every call because snapshotsForChart is not memoized (FinanceStore.swift:764-767), unlike calculateTotals which caches via cachedTotals (FinanceStore.swift:723-734). Both dashboards invoke it from a computed property (DashboardView.swift:118, MacDashboardView.swift:171) that re-evaluates on every body render.

**Impact.** A user with a ~5-year-old first snapshot who selects the "ALL" range (a real picker option on both platforms) forces construction of ~1,825 NetWorthPoint values, plus a full re-sort and Dictionary build, on every dashboard re-render — currency change, market-data refresh, privacy toggle, or tab switch. Swift Charts must then plot all of them. On iPhone this is a visible frame hitch, and because there is no memoization the whole array is rebuilt each time even when nothing changed. It also silently defeats the WC-#11 design decision (documented in SnapshotEngine.swift:14-16) that stopped storing one row per inactive day to avoid exactly this O(days) growth.

**Fix.** Bound the number of carried-forward days before/while building the result. Options, cheapest first: (1) short-circuit the span — if endDay is more than a threshold (e.g. ~730 days) after the first point's day, downsample instead of emitting daily points: bucket by week once the span exceeds ~180 days and by month once it exceeds ~730 days, carrying the last value forward at bucket boundaries so the flat-during-inactivity shape is preserved; (2) alternatively, cap total output points (e.g. max ~365-730) and stride the cursor by `max(1, spanDays / maxPoints)` days; (3) at minimum, guard the loop with a hard iteration ceiling so a pathological span cannot allocate unboundedly. Whichever is chosen, keep the current behavior for short ranges (oneWeek..oneYear) where daily granularity is cheap and desirable. Separately consider memoizing snapshotsForChart in FinanceStore keyed on (dataVersion, currency, rateStamp, range) the way calculateTotals is, so identical re-renders reuse the result.

---

### DA-M17 — Biometric enrollment changes are not detected: a newly-added fingerprint/face silently unlocks the app

- **Medium** · Security · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Services/BiometricLockStore.swift:110`

**Current code**
```swift
private func authenticate(reason: String, appLanguage: String?) async -> Bool {
    let context = LAContext()

    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        lastError = error?.localizedDescription
            ?? AppLocalization.string("Biometric authentication is not available on this device.", appLanguage: appLanguage)
        return false
    }

    return await withCheckedContinuation { continuation in
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
            Task { @MainActor in
                if let authenticationError {
                    self.lastError = authenticationError.localizedDescription
                }
                continuation.resume(returning: success)
            }
        }
    }
}
```

**Problem.** `BiometricLockStore.authenticate()` evaluates `.deviceOwnerAuthentication` on a fresh `LAContext` without ever inspecting `context.evaluatedPolicyDomainState`. No domain-state baseline is captured when the lock is enabled (`enableLock`, lines 56-68, persists only a Bool), and none is compared on unlock. Consequently the store cannot detect when the enrolled biometric set changes — e.g. someone who knows the device passcode adds a new fingerprint or re-enrolls Face ID. A repo-wide search confirms no `evaluatedPolicyDomainState` handling exists anywhere, and neither the iOS nor macOS subclass adds any. Note the app intentionally uses `.deviceOwnerAuthentication` (biometrics + automatic passcode fallback, per the WC-L2 comment), which already means passcode holders can unlock; the gap is that a newly-enrolled biometric then unlocks silently on every subsequent attempt without any re-confirmation.

**Impact.** On a shared or family device where the owner enabled the biometric lock specifically to keep balances private from others who know the passcode, an added/enrolled biometric will subsequently unlock Wealth Compass with no warning and no forced re-confirmation, because the app never invalidates its trust on enrollment change. This defeats the intended protection for exactly the threat model the lock exists to cover. It is defense-in-depth (a passcode holder can already unlock once via fallback), but the missing check lets a newly-trusted biometric unlock repeatedly and silently.

**Fix.** Capture a domain-state baseline when the lock is enabled and compare it on each unlock. In `enableLock`, after a successful `authenticate`, read the context's `evaluatedPolicyDomainState` and persist it (base64) alongside the enabled flag in UserDefaults. To do this cleanly, have `authenticate` return the `LAContext` (or the domain-state Data) it used rather than just a Bool, since `evaluatedPolicyDomainState` is only populated after a successful `evaluatePolicy`. In `unlock`, after a successful evaluation, compare the new `context.evaluatedPolicyDomainState` to the stored baseline; if it differs (or the stored baseline is nil for a lock enabled by a prior build), surface a warning / require re-confirmation before setting `isUnlocked = true`, then update the stored baseline. Store the baseline in the same subclass-specific `defaultsKey` namespace so iOS and macOS remain independent. Handle the nil domain-state case (e.g. passcode-only devices) by treating nil==nil as unchanged.

---

### DA-M18 — .serverRejectedRequest lumped into .recordGone → unbounded clear+requeue loop silently reported as Up-to-Date

- **Medium** · Bug · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:1836`

**Current code**
```swift
        // "recordChangeTag specified, but record not found" — the local systemFields carry a
        // stale changeTag for a record the server no longer has (deleted out-of-band, zone
        // reset, etc.). Clearing systemFields lets the next attempt create a fresh record.
        if errorCode == .unknownItem || errorCode == .serverRejectedRequest {
            return .recordGone
        }
        return errorIsRetryable ? .retryableRequeue : .fatal
```

**Problem.** In sentRecordFailureResolution (CloudKitSyncService.swift:1836-1837), CKError.serverRejectedRequest is mapped to .recordGone together with .unknownItem. The .recordGone case (lines 1398-1409) clears the record's systemFields and re-enqueues it for a fresh save. .unknownItem ('record not found') genuinely means the server record is gone, so clearing systemFields is correct there. But .serverRejectedRequest (CKError code 15) is CloudKit's nonspecific server-rejection catch-all — returned for schema/index problems, per-record constraint/validation rejections, policy refusals, atomic-batch companion failures, and transient server refusals — NOT specifically 'record not found'. When the server persistently rejects a specific record for a non-changeTag reason, this code clears its systemFields and re-enqueues it, the server rejects it again for the same underlying reason, and the cycle repeats indefinitely: CloudSyncRecordState (lines 341-346) has no attempt counter, so nothing bounds the loop, and wealth-compass-cloud-sync.json is rewritten every cycle. Compounding this, partialFailureIsBenign (line 1786) also lists .serverRejectedRequest, so synchronize() returns .upToDate while the record is permanently stuck — the failure never surfaces to the user. (Note: because recordName is deterministic per entity — type:uuid, lines 143-148 — a recreate reuses the same recordID, so a still-existing record collides as .serverRecordChanged and self-corrects rather than producing a duplicate; the duplicate-record concern in the original finding does not materialize.)

**Impact.** A single entity whose CKRecord persistently triggers .serverRejectedRequest for a non-'record-gone' reason (e.g. a schema/index change or a per-record server-side constraint) is clear-systemFields → requeued → rejected on every sync cycle, forever, with no bound and no user-visible signal. Each cycle rewrites the sync metadata file and re-arms CKSyncEngine, while the app UI shows 'Up to Date'. That entity silently never syncs to iCloud, and the app cannot distinguish this stuck state from a healthy one. The blast radius is limited (it requires a persistent per-record rejection, and it cannot corrupt or duplicate data because recordIDs are deterministic), but the failure is fully masked, which is the dangerous part.

**Fix.** Split .serverRejectedRequest off from .unknownItem. Keep only .unknownItem (the true 'record not found', i.e. the stale-changeTag-for-a-server-deleted-record case the comment at 1833-1835 describes) on the .recordGone path. Route .serverRejectedRequest to .fatal so it surfaces via synchronize() instead of looping — OR, to keep transient serverRejectedRequest recoverable, add a bounded attempt counter to CloudSyncRecordState (e.g. `var recreateAttempts = 0`) that the .recordGone side-effect (lines 1404-1409) increments, and once it exceeds a small cap (say 3) stop clearing/requeuing and throw so the error surfaces / the record is quarantined. In lock-step (as the comments at 1806-1813 and 1765-1774 require), remove `|| ckError.code == .serverRejectedRequest` from partialFailureIsBenign (line 1786) so a batch containing only serverRejectedRequest failures no longer reports .upToDate. Update the mirrored unit tests: Tests/CloudSyncCoreTests.swift:670,673 (change the expected resolution for .serverRejectedRequest) and the benign-set assertions around lines 580-584/687.

---

### DA-M19 — Merge import of Transaction records always overwrites existing rows because imported transactions get updatedAt = import time

- **Medium** · DataLoss · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/FinanceImportService.swift:171`

**Current code**
```swift
        return Transaction(
            id: id ?? UUID(),
            type: transactionType,
            category: category ?? "Other",
            amount: Decimal(amount),
            description: description ?? "",
            date: date,
            createdAt: ImportDateParser.parse(createdAt) ?? date,
            recurringTransactionID: recurringTransactionID,
            recurringOccurrenceDate: ImportDateParser.parse(recurringOccurrenceDate)
        )   // no updatedAt passed -> defaults to Date() (import time) via memberwise init
```

**Problem.** The four Transaction-producing import builders omit `updatedAt` when constructing the model, so it defaults to `Date()` (import time) via Transaction's synthesized memberwise init (FinanceModels.swift:232). ImportedTransaction.model() (FinanceImportService.swift:171-182) sets id/type/category/amount/description/date/createdAt but not updatedAt; likewise ImportedIncomeEntry.transaction() (307-315), ImportedExpenseEntry.transaction() (365-373), and ImportedLiquidityAccount.transaction() (419-427). FinanceStore.importBackup(mode:.merge) calls data.merged(with:) (FinanceStore.swift:929), whose Array.mergedByID keeps the incoming record only when `item.updatedAt > merged[index].updatedAt` (FinanceModels.swift:540). Because the incoming updatedAt is always 'now', an imported Transaction with a colliding UUID ALWAYS beats the existing one, defeating the last-writer-wins-by-recency intent. NOTE: contrary to the original finding, ImportedInvestment/ImportedCryptoHolding/ImportedLiability already carry a real updatedAt from the backup and are NOT affected; the defect is confined to Transaction-shaped imports. Also unlike those types, ImportedTransaction/Income/Expense have no updatedAt field to decode yet.

**Impact.** A user who edits a transaction (or income/expense/liquidity-derived transaction) today and then merges a month-old backup that still contains that transaction's UUID silently loses today's edit: the stale backup value wins because its updatedAt was stamped at import time. Merge is meant to be last-writer-wins by real recency, but for transactions import is always the winner, so an accidental re-import of an old backup can overwrite current transaction data (amount, category, date, description) with no warning.

**Fix.** Carry a real updatedAt into the four Transaction builders so mergedByID compares true recency. Add an `updatedAt: String?` field + CodingKey to ImportedTransaction, ImportedIncomeEntry, and ImportedExpenseEntry (ImportedLiquidityAccount already decodes `updatedAt`). In each builder, pass `updatedAt: ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? date` (for liquidity use the already-computed importedDate: `updatedAt: importedUpdatedAt` where importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? Date(), mirroring how the investment/crypto builders do it). This makes the imported updatedAt reflect the backup's real age rather than import time. Where a source updatedAt genuinely can't be recovered, the createdAt/date fallback keeps behavior sane; on a true tie mergedByID already keeps the existing record (strict >), which is the safe default.

---

### DA-M20 — Recurring-due notification stamps the amount with the display currency code, not the schedule's own currency, and never converts it

- **Medium** · Correctness · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Services/RecurringNotificationService.swift:73`

**Current code**
```swift
if showAmounts {
    // `schedule.amount` is Decimal (WC-A1); use the Decimal currency format style.
    let amount = schedule.amount.formatted(
        .currency(code: currencyCode)
    )
    content.body = AppLocalization.string("\(schedule.category): \(amount). Wealth Compass records it automatically when the app is active.", appLanguage: appLanguage)
}
```

**Problem.** In RecurringNotificationService.sync, the notification body formats `schedule.amount` with `.currency(code: currencyCode)`, where every caller passes `settings.currency.rawValue` (the display/base currency). However `schedule.amount` is denominated in the schedule's own `RecurringTransaction.currency` (FinanceModels.swift:334), which the rest of the app treats as authoritative: FinanceStore.processDueRecurringTransactions generates the occurrence Transaction with `currency: scheduleCurrency` and applies it to liquidity via `settings.convert(delta, from: scheduleCurrency)` (FinanceStore.swift:394-408). The notification neither converts the value nor labels it with the schedule currency, so the number and the currency symbol/code disagree with each other and with what the app actually records. This affects only schedules whose currency differs from the current display currency (legacy schedules with `currency == nil` fall back to the base currency and are unaffected).

**Impact.** A user whose display currency is EUR with a recurring 100 GBP subscription gets a reminder reading "€100.00" — the raw GBP figure mislabeled as euros and not converted. The number is wrong and the symbol is wrong. When the occurrence is actually generated, the app converts 100 GBP to the correct EUR amount and posts that to liquidity, so the reminder contradicts the ledger entry it foretells. Severity is Medium rather than High because it only misstates a reminder string (no data corruption — the stored transaction and liquidity math are correct) and only for schedules whose currency differs from the display currency.

**Fix.** Make the numeric value and the currency label agree. Preferred (also fixes the value): convert on the @MainActor before calling the actor. At each call site compute a converted display amount, e.g. `let displayAmount = settings.convert(schedule.amount, from: schedule.currency)` (uses the existing `AppSettings.convert(_ value: Decimal, from: Currency?) -> Decimal` at AppSettings.swift:321, which treats nil as the base currency), pass it alongside `currencyCode: settings.currency.rawValue`, and format that converted amount. This makes the reminder match the display currency AND the value the app will actually post. Minimal alternative (label-only, still shows unconverted native amount): format with the schedule's own currency inside sync — `let code = (schedule.currency ?? Currency(rawValue: currencyCode) ?? .eur).rawValue` then `schedule.amount.formatted(.currency(code: code))`. Either way the number and the code must refer to the same currency; do not keep the current mismatch.

---

### DA-M21 — Editing a lapsed (auto-deactivated) recurring schedule does not reactivate it unless frequency or startDate changes

- **Medium** · UX · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/RecurringScheduleBuilder.swift:50`

**Current code**
```swift
        var saved = seed
        if saved.isCompleted {
            saved.isActive = false
        } else if !scheduleChanged, let existing {
            saved.nextDueDate = existing.nextDueDate
        } else if let nextDueDate = seed.firstOccurrence(onOrAfter: now) {
            saved.nextDueDate = nextDueDate
        } else {
            saved.isActive = false
        }

        if let endDate = saved.endDate, saved.nextDueDate > endDate {
            saved.isActive = false
        }
        return saved
```

**Problem.** RecurringScheduleBuilder.build computes scheduleChanged (lines 25-27) as true only when frequency differs or startDate shifts by >= 1 second. When it is false, and the existing schedule is not completed, the builder takes the `else if !scheduleChanged, let existing` branch (line 50) which merely copies existing.nextDueDate. Because isActive is seeded from `existing?.isActive ?? true` (line 41), a schedule that was previously auto-deactivated (isActive == false, completedAt == nil) keeps isActive == false. Auto-deactivation happens in FinanceStore.processDueRecurringTransactions when the endDate passes (lines 376-379, 433-436) or when frequency.nextDate returns nil (line 421). If the user re-opens the editor and only extends the endDate (or edits amount / category / description / notifications) without touching frequency or startDate, the builder never recomputes a fresh nextDueDate via firstOccurrence and never flips isActive back to true. The trailing endDate guard (lines 58-60) can only turn isActive off, never on. Neither the iOS editor (Forms.swift, Schedule section lines 345-364) nor the macOS editor exposes an isActive toggle, so there is no other in-editor path to revive the schedule — the only reactivation route is the separate list-level setRecurringTransactionActive toggle.

**Impact.** A user whose monthly subscription/bill schedule lapsed (its end date passed and the app auto-deactivated it) opens the editor, pushes the end date out a year, and taps Save — reasonably expecting the recurring transaction and its reminders to resume. Instead the schedule is saved still inactive: processDueRecurringTransactions skips it (`guard schedule.isActive` at line 352), no occurrences are generated, no notifications fire, and no error or visual cue tells the user it is still dead. The editor visibly lets you set a future endDate on an existing schedule, so this silently contradicts the feature's evident intent and causes missed expected transactions.

**Fix.** In RecurringScheduleBuilder.build, when the existing schedule is not completed but inactive, re-derive activation from the inputs instead of inheriting the stale flag. Simplest robust fix: change the branch order so that whenever a schedule is not completed, isActive is recomputed from firstOccurrence within the (new) endDate window. For example, seed isActive optimistically (or leave line 50's fast-path only for still-active schedules) and in the fall-through case set `if let nextDueDate = seed.firstOccurrence(onOrAfter: now) { saved.nextDueDate = nextDueDate; saved.isActive = true } else { saved.isActive = false }`. Concretely: gate the `!scheduleChanged` fast path on `existing.isActive` too (`else if !scheduleChanged, let existing, existing.isActive`), so an inactive existing schedule falls through to the firstOccurrence recomputation at line 52 and gets reactivated when a future occurrence exists. Keep the completed short-circuit (lines 48-49) and the endDate guard (lines 58-60) as-is. Add a unit test: an inactive, non-completed schedule whose endDate is extended past a future occurrence must come back with isActive == true and nextDueDate == firstOccurrence(onOrAfter: now).

---

### DA-M22 — Retroactive snapshot edits stamp back-dated foreign-currency deltas at today's FX rate, mixing rate epochs in net-worth history

- **Medium** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:244`

**Current code**
```swift
// FinanceStore.swift 241-244
// Snapshots store liquidity in the display currency, so convert the transaction's
// own-currency delta before adjusting history (WC-M1; no-op when currency == base).
let delta: Decimal = type == .income ? amount : -amount
adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: settings.convert(delta, from: currency))

// SnapshotEngine.swift 43-56
func adjustingHistoricalSnapshots(_ snapshots: [NetWorthSnapshot], from date: Date, liquidityDelta: Decimal) -> [NetWorthSnapshot] {
    let startOfDay = calendar.startOfDay(for: date)
    var snapshots = snapshots
    for index in snapshots.indices where snapshots[index].date >= startOfDay {
        snapshots[index].liquidity += liquidityDelta
        snapshots[index].totalAssets += liquidityDelta
        snapshots[index].netWorth += liquidityDelta
    }
    return snapshots
}
```

**Problem.** Net-worth snapshots store liquidity/assets/netWorth in the display currency. When a foreign-currency transaction is added, edited, deleted, or generated from a recurring schedule, FinanceStore computes the display-currency delta with settings.convert(delta, from: currency) (FinanceStore.swift lines 244, 254, 266, 270, 398), which uses the CURRENT exchange-rate snapshot (AppSettings.convert -> CurrencyConverter(snapshot: exchangeRateSnapshot)). SnapshotEngine.adjustingHistoricalSnapshots (SnapshotEngine.swift lines 43-56) then adds that single today-rate-converted delta to every snapshot on/after the transaction date. Because each historical snapshot row was originally frozen at the display-currency value that was current on the day it was written, injecting a today-rate delta into old rows mixes FX rate epochs. This is a no-op when transaction currency == display currency, but produces subtly wrong historical net-worth values for any foreign-currency user. Note the live net worth (calculateTotals) is also computed at today's rate, so this affects the history chart's consistency across days, not the current total.

**Impact.** A user with display currency EUR adds a back-dated USD 1000 income. adjustHistoricalSnapshots injects delta = today's USD/EUR * 1000 into every snapshot on/after that date, even though the snapshot rows for those days were written at a different USD/EUR rate. The net-worth history line therefore shows a jump sized at today's rate placed onto days whose other liquidity was recorded at a different rate, so the plotted history is internally inconsistent for foreign-currency users and the error grows with rate volatility and with the number of back-dated foreign-currency edits. It is a no-op for same-currency users, so it never affects the common case and never corrupts stored source transactions or current net worth.

**Fix.** This is a modeling limitation of storing snapshots in a mutable display currency without per-day FX. Options, in increasing effort: (1) Document the limitation clearly at the adjustHistoricalSnapshots call sites and in the SnapshotEngine doc comment (the WC-M1 comment at FinanceStore line 241 already hints at it but understates that the conversion uses TODAY's rate, not the historical rate). (2) When the transaction currency differs from the display currency, instead of applying a single today-rate delta, recompute the affected snapshots (those on/after the tx date) from source data via calculateTotals-style recomputation so at least the whole affected range is internally consistent at today's rate. (3) Full fix: store liquidity/assets in a rate-stable base currency and convert at read/plot time, OR persist the FX rate snapshot per snapshot day so retroactive deltas can be converted at the historical rate. Given the app has no per-day historical rates at all, option (2) is the pragmatic improvement; option (3) is the correct long-term design.

---

### DA-M23 — Back-dated foreign-currency transactions fold a today-rate delta into historical snapshots frozen at capture-time rates

- **Medium** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:244`

**Current code**
```swift
// FinanceStore.addTransaction (line 243-244)
let delta: Decimal = type == .income ? amount : -amount
adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: settings.convert(delta, from: currency))

// SnapshotEngine.adjustingHistoricalSnapshots (lines 50-54)
for index in snapshots.indices where snapshots[index].date >= startOfDay {
    snapshots[index].liquidity += liquidityDelta
    snapshots[index].totalAssets += liquidityDelta
    snapshots[index].netWorth += liquidityDelta
}
```

**Problem.** When a non-base-currency transaction is added, edited, or deleted, FinanceStore converts the own-currency delta with settings.convert(delta, from: currency), which uses AppSettings' single live exchange-rate snapshot (today's rate). It then passes that single Decimal to adjustHistoricalSnapshots, which adds it to liquidity/totalAssets/netWorth of every NetWorthSnapshot on/after the transaction date (SnapshotEngine.adjustingHistoricalSnapshots, lines 50-54). But each stored snapshot's amounts were originally computed by AnalyticsEngine.calculateTotals at whatever FX rate was live when that snapshot was captured (converter.convert in displayAmount), and NetWorthSnapshot persists no per-day rate. Mixing a today-rate delta into a total frozen at a different capture-time rate makes the retroactively-adjusted net-worth history internally inconsistent for any non-base-currency transaction. The same defect is on all three mutating paths: add (line 244), delete (line 254), and update (lines 266 and 270). The same-currency case is exact (convert is a no-op at rate 1); the current live net-worth total is unaffected because it is always recomputed from raw amounts.

**Impact.** User's base is EUR. On a day when EUR/USD was 1.05 a snapshot was captured using that day's rate. The user later back-dates a $1000 income to that day while EUR/USD is now 1.20. The store adds the today-rate conversion of $1000 into a snapshot whose other components were valued at the earlier rate, so the net-worth history line shows a figure that never existed at any single point in time. The larger the FX drift and the longer the back-date window, the more the historical line diverges from truth. It never corrupts the live current total or causes data loss, but it silently degrades the accuracy of the net-worth history chart for anyone transacting in a foreign currency.

**Fix.** Preferred: stop retroactively mutating stored snapshots for currency-converted deltas. Recompute the historical liquidity/net-worth series from the transaction list at render time (consistent with the existing carry-forward-at-render philosophy in AnalyticsEngine.snapshotsForChart), converting each transaction with a per-day/best-available rate rather than baking a single today-rate scalar into frozen totals. If retroactive mutation must stay, at minimum only apply exact same-currency deltas retroactively (delta where transaction.currency == settings.currency, no conversion) and either (a) skip retroactive adjustment for foreign-currency deltas, letting the next appendSnapshot recompute the current point, or (b) persist the transaction's own-currency delta plus its currency alongside snapshots so the series can be reconstructed. Whichever path is chosen, document in SnapshotEngine that stored snapshots are frozen at capture-time rates and that converting foreign deltas is a known approximation.

---

### DA-M24 — Recurring dedupe's 1-second date tolerance misses re-imported occurrences, double-generating transactions and double-adjusting snapshots

- **Medium** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:389`

**Current code**
```swift
                let alreadyGenerated = data.transactions.contains { transaction in
                    guard
                        transaction.recurringTransactionID == schedule.id,
                        let generatedDate = transaction.recurringOccurrenceDate
                    else {
                        return false
                    }
                    return abs(generatedDate.timeIntervalSince(occurrence)) < 1
                }
```

**Problem.** In `processDueRecurringTransactions`, the `alreadyGenerated` guard (FinanceStore.swift:389) compares the stored `transaction.recurringOccurrenceDate` against the schedule's freshly-recomputed `occurrence` using `abs(generatedDate.timeIntervalSince(occurrence)) < 1`. Generated occurrences are stored with the schedule's real time-of-day (line 410 stores raw `occurrence`; nextMonthlyDate/nextYearlyDate copy hour/minute/second from `startDate`, and the default new-schedule startDate is `Date()+1h`, so occurrences are almost never at midnight). On import, `recurringOccurrenceDate` is parsed by `ImportDateParser.parse` (FinanceImportService.swift:180), which returns the raw parsed instant and — for date-only or coarser-precision interchange values — collapses to local midnight or a truncated time. When the imported `recurringOccurrenceDate` differs by ≥1s from the schedule's recomputed occurrence (as happens with the web-app/lossy backup interchange, since Apple→Apple round-trips are lossless), the dedupe fails: `processDueRecurringTransactions` (run on foreground at ContentView.swift:128, MacRootView.swift:191, MacSettingsView.swift:734) re-appends the occurrence as a duplicate transaction and calls `adjustHistoricalSnapshots` a second time, corrupting net-worth history.

**Impact.** Import a backup (e.g. from the web app, the documented JSON interchange partner) that contains recurring schedules plus their already-generated transactions, where `recurringOccurrenceDate` was serialized date-only or at a precision that reparses ≥1s away from the schedule's startDate time-of-day, and whose `nextDueDate` is still at/before the current date. On the next foreground `processDueRecurringTransactions`, every such past occurrence fails the 1-second dedupe and is regenerated: the user sees duplicated income/expense entries, and each duplicate re-runs `adjustHistoricalSnapshots`, double-counting the amount into the historical net-worth snapshots. This silently corrupts both the ledger and the wealth chart. (Apple app's own native backups round-trip losslessly and do not trigger this, so it is a cross-source/lossy-import defect, not an everyday one.)

**Fix.** Match generated occurrences by calendar day rather than a 1-second window, mirroring the fact that generated transactions already store a day-granular `date` (`occurrenceStartOfDay = calendar.startOfDay(for: occurrence)`, line 393/407). Replace line 389 `return abs(generatedDate.timeIntervalSince(occurrence)) < 1` with `return calendar.isDate(generatedDate, inSameDayAs: occurrence)` (the `calendar` local is already in scope at line 339). This makes the dedupe robust to any time-of-day/sub-second drift introduced by import round-trips while remaining exact for a daily schedule (at most one occurrence per calendar day). If sub-day recurrence is ever added this would need revisiting, but the current frequencies (daily/weekly/monthly/yearly) are all ≥1-day-granular, so same-day matching is safe.

---

### DA-M25 — CoinGecko /search resolution loop fires sequential requests with no proactive pacing, tripping the demo-tier rate limit

- **Medium** · Performance · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:605`

**Current code**
```swift
for holding in data.crypto where lookups[holding.id] == nil {
    // Non-fatal: a search miss/error just leaves the holding unresolved → skipped below.
    if let resolved = try? await searchClient.searchCoinID(symbol: holding.symbol, name: holding.name) {
        lookups[holding.id] = resolved
    }
}
```

**Problem.** In refreshMarketPrices, the loop resolving crypto holdings to CoinGecko coin ids (FinanceStore.swift:605-610) calls searchClient.searchCoinID(symbol:name:) once per unmapped holding in a tight sequential loop with NO inter-request delay. Only holdings whose symbol is one of the 20 hardcoded commonCoinGeckoIDs (MarketDataService.swift:871-892) or that carry an explicit coinId skip this /search call; every other holding issues its own CoinGecko /search HTTP request back-to-back. This contrasts with the investments quote loop (FinanceStore.swift:552, 569-571, 588-590), which paces requests at interRequestDelay = 0.3s and multiplies that delay (cap 3s) whenever a .rateLimited error is seen. The crypto /search loop has no such throttle and no rate-limit-driven backoff between iterations. NetworkRetry (NetworkRetry.swift) does retry an individual 429 up to 3 attempts with jittered exponential backoff and honors Retry-After, so the burst becomes partially self-limiting only AFTER the first failures occur.

**Impact.** CoinGecko's demo/free tier allows roughly 10-30 requests/minute. A user holding several less-common coins (e.g. 8-10 not in commonCoinGeckoIDs and without stored coinIds) issues ~10 back-to-back /search calls. Once HTTP 429 is returned, NetworkRetry burns its 3 attempts (with backoff) on each affected call, then searchCoinID returns nil (swallowed by `try?`), so the holding is added to result.skippedCrypto as ':symbol: no matching CoinGecko coin' (FinanceStore.swift:612-615) — a misleading message implying the coin doesn't exist when it was actually just rate-limited. It also consumes the shared per-minute budget before the subsequent /simple/price batch call (line 622) runs, so even correctly-mapped coins can then fail. The result is a confusing partial refresh failure that is hard for the user to diagnose.

**Fix.** Throttle the /search loop the same way as the investments loop: introduce a local `var interRequestDelay: UInt64 = 300_000_000`, sleep it between iterations (skip after the last), and multiply it (cap ~3s) when searchCoinID surfaces a rate-limit condition. Note searchCoinID currently swallows the error via `try?`, so to back off on rate limits you must catch the thrown MarketDataError.rateLimited explicitly (change the call to a do/catch) rather than relying on `try?`. Better still, persist resolved coinIds back onto the holding (data.crypto[index].coinId) after a successful /search so subsequent refreshes hit the coinGeckoID short-circuit and skip /search entirely — the apply loop at FinanceStore.swift:674-679 already backfills coinId when it was empty, so consider also caching the /search-resolved id there. Minimally, cap or dedupe /search calls per symbol within a single refresh pass.

---

### DA-M26 — refreshMarketPrices runs appendSnapshot + full save even when no price actually changed

- **Medium** · Performance · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:687`

**Current code**
```swift
        if result.updatedRecordCount > 0 {
            appendSnapshot(settings: settings)
            save()
        }
```

**Problem.** In `refreshMarketPrices`, the per-holding counters `result.updatedInvestments` (FinanceStore.swift:667) and `result.updatedCrypto` (line 684) are incremented for EVERY holding that received a valid quote, unconditionally — outside the `if ... != price` mutation guards (lines 662-666 and 677-683) that actually write data. Because `updatedRecordCount = updatedInvestments + updatedCrypto` (MarketDataService.swift:25-27), it becomes > 0 whenever any quote was fetched, even if all resolved prices are identical to what is already stored. The gate at line 687 (`if result.updatedRecordCount > 0`) then always fires `appendSnapshot(settings:)` + `save()`. `appendSnapshot` -> `SnapshotEngine.appendingSnapshot` overwrites today's snapshot with a fresh timestamp (SnapshotEngine.swift:34) or appends a brand-new same-day snapshot record (line 36), so `data.snapshots` mutates regardless; `save()` then runs a full JSON encode + SHA256 per-record diff. The per-holding `updatedAt` guards correctly avoid re-syncing the holding records, but the top-level snapshot/save path is gated on `updatedRecordCount` (a "we fetched a quote" count) rather than on whether any data actually changed.

**Impact.** A user refreshing prices when nothing moved — a refresh moments after the previous one, or over a weekend/holiday when markets are closed — still pays a full save cycle (whole-dataset JSON encode + SHA256 diff) and a snapshot mutation on every refresh. On the first refresh of a new day with no price change, a brand-new net-worth snapshot record is materialized even though net worth is unchanged, and because the snapshot record's date/contents change it also generates a CloudKit changeset for that record — the exact CloudKit churn the code comments at lines 659-661 and 675-676 say they intend to avoid. This is write amplification and unnecessary sync traffic rather than data loss; the encode/hash runs off the main actor so the UI is not blocked, which keeps the impact at Medium.

**Fix.** Introduce a real `didMutate` flag instead of relying on `updatedRecordCount`. Set it inside each mutation branch: in the investments loop set `didMutate = true` inside `if data.investments[index].currentPrice != price { ... }` (lines 662-666); in the crypto loop set it inside `if data.crypto[index].currentPrice != price || coinIDWasEmpty { ... }` (lines 677-683). Then change the gate at line 687 from `if result.updatedRecordCount > 0` to `if didMutate`. Keep `result.updatedInvestments`/`updatedCrypto` incrementing where they are if the UI's "Updated N investments and M crypto holdings" message is meant to report every re-priced holding (MarketDataService.swift:56); otherwise, if that message should reflect only genuine changes, move those increments inside the guards as well. This makes `appendSnapshot` + `save()` fire only when a stored price or coinId actually changed, matching the stated CloudKit-churn intent.

---

### DA-M27 — Uncached cash-flow/category analytics (monthlyCashFlow, expensesByCategory, cashFlowTrend) plus an O(n) re-sorting transactions.filter().count recompute on every hover/resize body invalidation

- **Medium** · Performance · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:756`

**Current code**
```swift
// FinanceStore.swift:756-775 — uncached, unlike calculateTotals (723-734)
func monthlyCashFlow(for month: Date, settings: AppSettings) -> MonthlyCashFlow {
    analytics(settings).monthlyCashFlow(for: month)
}
func cashFlowTrend(months: Int = 6, settings: AppSettings) -> [CashFlowMonth] {
    analytics(settings).cashFlowTrend(months: months)
}
func expensesByCategory(period: AnalyticsPeriod, settings: AppSettings) -> [CategoryTotal] {
    analytics(settings).expensesByCategory(period: period)
}

// MacCashFlowView.swift:212-215 — O(n) re-sorting filter().count inside a body under GeometryReader
private var summaryCards: some View {
    let cashFlow = finance.monthlyCashFlow(for: Date(), settings: settings)
    let totals = finance.calculateTotals(settings: settings)
    let monthlyTransactionsCount = finance.transactions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
```

**Problem.** FinanceStore memoizes only calculateTotals (FinanceStore.swift:723-734, via cachedTotals keyed on dataVersion + currency + rateStamp). The sibling analytics methods monthlyCashFlow (756-758), cashFlowTrend (769-771), and expensesByCategory (773-775) are uncached: each constructs a fresh AnalyticsEngine through analytics(_:) (714-721) that copies the whole `data` value, then re-filters/re-groups all transactions with per-record Decimal FX conversion (AnalyticsEngine.swift:71-79, 168-188, 190-204). These are invoked directly inside computed `var` view bodies that SwiftUI inlines into the parent `body`, so any @State change re-runs the full pipeline. In iOS CashFlowView, summaryCards (CashFlowView.swift:118) calls monthlyCashFlow and analytics (142) calls expensesByCategory; hoveredExpenseCategory (@State, line 38) is written on every DragGesture.onChanged tick (line 205), re-running expensesByCategory on each hover update. MacCashFlowView is worse: summaryCards (MacCashFlowView.swift:212-215) recomputes monthlyCashFlow + calculateTotals AND an O(n) `finance.transactions.filter { ... }.count` where `finance.transactions` itself sorts the whole array on every access (FinanceStore.swift:211-216); cashFlowTrendCard (257-258) recomputes the whole trend. All of these live under a GeometryReader (line 103) that re-evaluates on window resize, and both hover-state properties (lines 85-86) invalidate the entire MacCashFlowView body.

**Impact.** During hover/drag over either pie or trend chart, each hover-state write invalidates the view body and re-runs the uncached analytics pipeline: a full copy of `data`, a re-sort of all transactions (macOS summaryCards' transactions.filter.count), and re-grouping with per-record Decimal FX conversion. Window resize on macOS triggers the same via the enclosing GeometryReader. On large transaction datasets this recompute happens per interaction frame and can drop frames / make the hover and resize animations stutter. It is purely a performance/interaction-smoothness issue, not a correctness or data-loss bug.

**Fix.** Cache monthlyCashFlow, cashFlowTrend, and expensesByCategory in FinanceStore the same way calculateTotals already is — memoize keyed on dataVersion + settings.currency + exchangeRateSnapshot?.fetchedAt plus the method-specific parameter (month / months / period), invalidating automatically when dataVersion bumps (didSet at FinanceStore.swift:95). Alternatively/additionally, hoist the per-render derived values in the views so transient hover state does not re-trigger the pipeline: compute categories/trend/monthlyCashFlow into @State that recomputes only via .onChange of the real inputs (data version, period, currency, rate stamp), not on every hover write. In MacCashFlowView.summaryCards (line 215) eliminate the O(n) re-sorting `finance.transactions.filter { ... }.count`: derive the month count from data without going through the sorting `transactions` accessor (e.g. iterate finance.data.transactions directly, or expose a cached monthly count), so it does not re-sort on every body evaluation.

---

### DA-M28 — importBackup mutates in-memory data and reports success even when a load-time localPersistenceError makes save() a silent no-op

- **Medium** · DataLoss · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:907`

**Current code**
```swift
    func importBackup(from url: URL, mode: FinanceImportMode, settings: AppSettings) throws -> FinanceImportResult {
        // ... (no localPersistenceError guard here) ...
        switch mode {
        case .replace:
            data = normalized.data.sortedForStorage()
        case .merge:
            data = data.merged(with: normalized.data).sortedForStorage()
        }
        // ...
        save()   // early-returns if localPersistenceError != nil -> write silently dropped
        return FinanceImportResult( ... )   // success reported regardless
    }

    private func save() {
        guard localPersistenceError == nil else {
            iCloudSyncError = AppLocalization.string(
                "Changes cannot be saved until the local database load error is resolved.",
                appLanguage: settings?.appLanguage
            )
            return
        }
        lastEnqueuedSaveGeneration += 1
        saveContinuation?.yield(lastEnqueuedSaveGeneration)
    }
```

**Problem.** `importBackup(from:mode:settings:)` (FinanceStore.swift:907) does not check `localPersistenceError` before mutating the single in-memory `FinancialData`. On mode `.replace` it assigns `data = normalized.data.sortedForStorage()` (line 927); on `.merge` it assigns `data = data.merged(with: normalized.data).sortedForStorage()` (line 929). It then calls `save()` (line 936) and returns a success `FinanceImportResult` (lines 938-950). However `save()` early-returns whenever `localPersistenceError != nil` (guard at line 1055), setting only `iCloudSyncError` and never enqueuing the write. `localPersistenceError` is set by `load()`'s catch block (line 987) when the local DB cannot be read at startup. Sibling mutators guard this exact condition — `setICloudSyncEnabled` (line 1105) and `applyRemoteMutations` (line 1130) — but `importBackup` does not. Result: with a load error present, the import changes visible in-memory state (and the diff baseline the next successful save would use) but persists nothing, while returning a success result. Neither the iOS caller (SettingsView.swift:560-563, sets `importSummary`) nor the macOS caller (MacSettingsView.swift:733) sees any error, so the UI reports "import completed".

**Impact.** A user whose local database is corrupt or unreadable (so `localPersistenceError` is set) is exactly the user most likely to try importing a JSON backup to recover. The import appears to succeed — the summary sheet shows the imported counts and the on-screen data updates — but `save()` silently no-ops, so nothing is written to disk. On the next launch the import is gone (the store reloads from the unchanged/broken local file), and the user has been actively misled into believing their data was restored, potentially deleting the backup file in the meantime. Because `.replace` mode replaces in-memory state without persisting, this also creates a confusing session where the visible data and the on-disk data disagree.

**Fix.** Add a guard at the top of `importBackup` mirroring `setICloudSyncEnabled`/`applyRemoteMutations`, before any mutation of `data`: `guard localPersistenceError == nil else { throw FinanceImportError.<newCase>(...) }`, where the new error case carries a localized message like "Cannot import until the local database load error is resolved." (reuse the string already used in save()'s guard). Throwing routes correctly through both callers' catch blocks, which show an "Import Failed" alert. Alternatively (or additionally), make the persistence no-op observable: have `save()` signal when it dropped a write and have `importBackup` throw in that case, so the success `FinanceImportResult` is never returned when nothing was persisted. Prefer the up-front guard for clarity and to avoid mutating in-memory `data` at all when persistence is known-broken.

---

### DA-M29 — AllocationChart uses slice name as identity, so duplicate-named crypto slices double-highlight on hover and collide in the legend ForEach

- **Medium** · Bug · iOS+macOS · confidence: Medium
- **Location:** `Sources/Shared/UI/DesignSystem.swift:283`

**Current code**
```swift
// DesignSystem.swift:283 (dim compares by id == name)
.opacity(hoveredSlice == nil || hoveredSlice?.id == slice.id ? 1.0 : 0.3)

// DesignSystem.swift:392-395 (hovered slice resolved positionally)
private func slice(at location: CGPoint, in rect: CGRect, total: Double) -> AllocationSlice? {
    PieSliceHitTester.sliceIndex(at: location, in: rect, values: slices.map(\.value), innerRadiusRatio: 0.72)
        .map { slices[$0] }
}

// FinanceModels.swift:511-516 (identity IS the name)
struct AllocationSlice: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var value: Double
    var color: Color
}

// AnalyticsEngine.swift:268-278 (crypto: no grouping, name = symbol)
func cryptoAllocation() -> [AllocationSlice] {
    data.crypto.enumerated().map { index, holding in
        AllocationSlice(name: holding.symbol, ...)
    }
    .filter { $0.value > 0 }
    .sorted { $0.value > $1.value }
}
```

**Problem.** AllocationSlice conforms to Identifiable with `var id: String { name }` (FinanceModels.swift:512). AllocationChart dims non-hovered wedges by comparing ids on DesignSystem.swift:283 (`hoveredSlice?.id == slice.id`), but the hovered slice is resolved positionally in slice(at:) at DesignSystem.swift:392-395 via PieSliceHitTester.sliceIndex(...).map { slices[$0] }. When two slices share a name their ids collide, so hovering one wedge lights up every wedge with that name. The legend `ForEach(slices)` on DesignSystem.swift:365 iterates the same Identifiable slices, so duplicate ids trigger SwiftUI's duplicate-id warning and can mis-diff/mis-animate legend rows. Duplicate names are reachable in practice: cryptoAllocation() (AnalyticsEngine.swift:268-278) maps data.crypto directly to slices named by holding.symbol with no per-symbol grouping or uniqueness constraint, so two holdings sharing a symbol produce two identically-named slices; investmentTypeAllocation() (AnalyticsEngine.swift:243-248) is a secondary path where multiple unknown InvestmentType rawValues collapse to `.other`'s localized title. (The sector/geography/asset allocations and CategoryTotal are built from Dictionary keys and are collision-free.)

**Impact.** A user who holds the same crypto symbol in two entries (e.g. BTC across two wallets/exchanges, different cost bases) sees hovering one BTC wedge highlight both BTC wedges, making the donut interaction visually wrong. The `ForEach(slices)` legend with duplicate ids emits SwiftUI runtime warnings and can drop, duplicate, or mis-animate legend rows on data changes. Data-dependent and cosmetic (no data corruption), but silently incorrect whenever duplicate names occur.

**Fix.** Give AllocationSlice a stable unique identity independent of its display name. Add an explicit `let id = UUID()` stored property (or carry the source entity's id, e.g. the CryptoHolding UUID) and remove `var id: String { name }`, keeping `name` as a display-only field. Update the three interacting sites so identity and hit-test agree: line 283 compares the unique id, slice(at:) (392-395) already returns the positional slice (its unique id will now be correct), and ForEach(slices) (365) iterates unique ids. Populate the id at each AllocationSlice construction site in AnalyticsEngine.swift (208-211, 227, 244-248, 264, 270-273). Alternatively, if same-named slices should never appear, aggregate them before charting (e.g. group cryptoAllocation by symbol like the other allocations do). Do NOT touch CategoryTotal / expensesByCategory — its names are unique Dictionary keys and it is not affected.

---

### DA-M30 — AllocationChart center overlay leaks slice share percentage in Privacy Mode

- **Medium** · Privacy · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/UI/DesignSystem.swift:303`

**Current code**
```swift
Text(percentage(hoveredSlice.value, total: total))
    .font(.caption2.monospacedDigit())
    .foregroundStyle(WCColor.textTertiary) // WC-L20: was raw .white.opacity(0.6)
```

**Problem.** In AllocationChart's pie-center overlay (chartBackground), when a slice is hovered or tapped, the amount at line 298 is correctly redacted via `settings.privateCurrency(hoveredSlice.value)` (returns "••••" in privacy mode), but the share line at line 303 is rendered as `Text(percentage(hoveredSlice.value, total: total))` with NO privacy check. `percentage(_:total:)` (lines 397-400) always returns a real formatted percentage. This is inconsistent with the legend's share text (line 378, `settings.isPrivacyMode ? settings.redactionToken : percentage(...)`) and the VoiceOver accessibilityValue (lines 403-406), both of which redact the ratio in privacy mode. Result: with Privacy Mode enabled, hovering/tapping a slice masks the currency amount but still displays the exact allocation ratio (e.g. "62.4%") in the chart center.

**Impact.** A user enables Privacy Mode to conceal financials before showing their screen to someone else. When they hover or tap a pie slice, the center overlay masks the amount to "••••" but still prints the precise share, e.g. "62.4%", disclosing portfolio composition ratios the mode is designed to hide — a leak the app deliberately guards against everywhere else (legend line 378, VoiceOver line 405). On iOS the tap gesture (lines 341-353) makes this trivially reachable; on macOS the hover (lines 328-339) does the same.

**Fix.** Mirror the legend/VoiceOver logic in the center overlay. Change line 303 to:
`Text(settings.isPrivacyMode ? settings.redactionToken : percentage(hoveredSlice.value, total: total))`.
Better: centralize this so it can't be forgotten again — add a helper to AppSettings alongside privateCurrency/privateNumber (around lines 307-314), e.g.
`func privatePercent(_ value: Double, total: Double) -> String { isPrivacyMode ? redactionToken : /* percentage formatting */ }`
and use it at both line 303 and line 378 (and reuse in accessibilityValue at line 405). Note `percentage(_:total:)` currently lives in the view (lines 397-400); if moving formatting into AppSettings, keep the same `.precision(.fractionLength(1))` format and the `total > 0` guard to preserve output.

---

### DA-M31 — CloudKit push entitlement (aps-environment) and remote-notification background mode missing — CKSyncEngine subscription pushes are never delivered

> **✅ RESOLVED (2026-07-13, commit `31c0dea`).** Push sync has since landed — see roadmap §5. `aps-environment` is now present in both entitlements, `remote-notification` is in `Resources/iOS/Info.plist`, and `registerForRemoteNotifications()` (iOS `ContentView.swift`, macOS `MacRootView.swift`) plus `didReceiveRemoteNotification` handlers route pushes into `CKSyncEngine` via `FinanceStore.syncForRemotePush()`. The "Current code" snapshot below is the pre-fix state at audit time. (Remaining: a one-time manual production Push Notifications provisioning-profile step — entitlements currently ship `aps-environment=development`.)

- **Medium** · Architecture · iOS+macOS · confidence: Medium
- **Location:** `WealthCompassMobile.entitlements:9`

**Current code**
```swift
// WealthCompassMobile.entitlements (lines 9-12) — no aps-environment
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>

// CloudKitSyncService.swift
600:    private static let subscriptionID = "WealthCompassSyncSubscription"
737:            configuration.automaticallySync = true
738:            configuration.subscriptionID = Self.subscriptionID
```

**Problem.** The app drives iCloud sync through CKSyncEngine (CloudKitSyncService.swift). The engine is configured with automaticallySync = true (line 737) and subscriptionID = "WealthCompassSyncSubscription" (lines 600, 738), which asks CloudKit to create a database subscription and push silent APNs notifications when a remote device writes a zone change. Delivering those pushes requires (a) the aps-environment entitlement and (b), on iOS, the remote-notification UIBackgroundMode plus registration for remote notifications so the app can forward pushes into the engine. None of these exist: WealthCompassMobile.entitlements and Resources/macOS/WealthCompassMac.entitlements both declare only com.apple.developer.icloud-services=CloudKit (no aps-environment), Resources/iOS/Info.plist declares no UIBackgroundModes, and there is no registerForRemoteNotifications / didReceiveRemoteNotification anywhere. project.pbxproj confirms these exact files are the ones signed/built and no push keys are injected. As a result the CloudKit server has no APNs channel to notify the app of zone changes; the configured subscription cannot drive delivery. The app instead relies on foreground polling via requestICloudSync()->requestSync(), wired to handleAppBecameActive() (iOS ContentView.swift:48, macOS MacRootView.swift:142).

**Impact.** Without the push channel, a transaction added on device B does not propagate to device A until device A is next foregrounded and its become-active handler polls (requestSync fetches/sends changes). There is no near-real-time cross-device sync and no background wake-to-sync at all. Users will perceive sync as stale/laggy across devices — the declared CloudKit capability is only half-wired. (It is not fully broken because automaticallySync=true also syncs opportunistically on app-driven sends and foregrounds, but the intended push-driven propagation the subscriptionID implies never happens.)

**Fix.** Either wire push properly or stop implying push works. To enable push: (1) add <key>aps-environment</key><string>development</string> (production for App Store builds) to BOTH WealthCompassMobile.entitlements and Resources/macOS/WealthCompassMac.entitlements; (2) add <key>UIBackgroundModes</key><array><string>remote-notification</string></array> to Resources/iOS/Info.plist; (3) call UIApplication.shared.registerForRemoteNotifications() at launch (and the AppKit equivalent on macOS) and implement application(_:didReceiveRemoteNotification:) to hand the CKNotification to the engine (CKSyncEngine consumes pushes automatically once registered, so mainly the entitlement + background mode + registration are needed). Also enable the Push Notifications capability in the target so provisioning includes it. If cross-device push sync is intentionally out of scope, drop configuration.subscriptionID (line 738), document the app as foreground-poll-only in ICLOUD_SYNC.md, and remove the implication that CKSyncEngine push delivery is active.

---

## 🟡 Low severity (62)

### DA-L01 — iOS Info.plist declares no explicit App Transport Security stance for the key-carrying finance API hosts

- **Low** · Security · iOS · confidence: Low
- **Location:** `Resources/iOS/Info.plist:4`

**Current code**
```swift
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.finance</string>
	<!-- no NSAppTransportSecurity key anywhere in the plist -->
	<key>LSRequiresIPhoneOS</key>
	<true/>
```

**Problem.** Resources/iOS/Info.plist has no NSAppTransportSecurity dictionary. The app sends the user's Finnhub (X-Finnhub-Token) and CoinGecko (x-cg-demo-api-key) keys as request headers directly to finnhub.io and api.coingecko.com, and also contacts api.frankfurter.dev and query1.finance.yahoo.com (APIConfiguration.swift:13-34) — all over HTTPS. Because no ATS dict is present and NSAllowsArbitraryLoads is absent, the app currently relies entirely on iOS's DEFAULT ATS policy, which already forbids cleartext and requires TLS 1.2+ with forward secrecy. So this is not a live vulnerability or a downgrade path — the default posture is already secure. It is purely the absence of an explicit, auditable ATS declaration for a security-sensitive finance app. Note the previously-removed cleartext localhost debug logging (http://127.0.0.1:7504) would have needed an ATS exception; keeping ATS at its strict default is what makes that regression visible if reintroduced.

**Impact.** There is no functional failure today: every endpoint is HTTPS and the default ATS already enforces TLS 1.2 + forward secrecy on the connections carrying the secret keys. The only concrete value of acting is defense-in-depth documentation/auditability — making the intended strict TLS posture explicit rather than implicit, and reducing the risk that a future dev adds NSAllowsArbitraryLoads or a broad exception without review. Left as-is, the posture is still secure; this is a hardening/hygiene gap, not a defect.

**Fix.** Optional hardening. If you want an explicit, auditable stance, add an NSAppTransportSecurity dict that keeps NSAllowsArbitraryLoads = false and sets NSAllowsArbitraryLoadsInWebContent = false. Prefer NOT adding per-domain NSExceptionDomains for finnhub.io / api.coingecko.com / api.frankfurter.dev / query1.finance.yahoo.com with TLSv1.2 + NSExceptionRequiresForwardSecrecy=true, because those merely restate the secure default and can weaken future posture if a provider moves to TLS 1.3-only. The higher-value change is a one-line code comment or CODE_AUDIT note asserting 'all endpoints HTTPS; ATS left at strict default deliberately — do not add exceptions' so the strict default is intentional and protected in review. Do NOT weaken ATS.

---

### DA-L02 — 5-hour exchangeRateRefreshTimer is effectively dead: its scenePhase==.active guard means it can only fire after 5h continuous foreground, and the foreground handler already refreshes rates

- **Low** · Bug · iOS · confidence: Medium
- **Location:** `Sources/iOS/ContentView.swift:12`

**Current code**
```swift
    private let exchangeRateRefreshTimer = Timer.publish(every: 5 * 60 * 60, on: .main, in: .common).autoconnect()
    // ...
        .onReceive(exchangeRateRefreshTimer) { _ in
            guard scenePhase == .active, appLock.isUnlocked else { return }
            Task { await refreshExchangeRatesIfNeeded() }
        }
```

**Problem.** `exchangeRateRefreshTimer` (ContentView.swift line 12) is `Timer.publish(every: 5 * 60 * 60, ...).autoconnect()` = a 5-hour repeating Combine timer. Its handler (lines 63-66) fires only when `scenePhase == .active && appLock.isUnlocked`, then calls `refreshExchangeRatesIfNeeded()`, which further gates on `settings.shouldAutoRefreshExchangeRates()` (12h staleness window, AppSettings.swift line 214). Combine `Timer.publish` does not tick while the app is backgrounded/suspended, and its first tick occurs ~5h after the publisher is created, never at t=0. So for this timer to ever fire, the app must remain foregrounded (and unlocked) continuously for 5+ hours — which realistically never occurs on iOS. Every practical exchange-rate refresh already happens through the foreground path: the `.onChange(of: scenePhase)`→`.active` branch (lines 47-49) and the unlock branch (line 54) both invoke `handleAppBecameActive()` → `refreshRemoteDataIfNeeded()` → `refreshExchangeRatesIfNeeded()`, plus the initial `.task` (line 57). The 5-hour timer therefore does no useful work and just schedules a repeating main-run-loop source. (Contrast line 11's `recurringCheckTimer = every: 30`, which is a genuinely useful in-session cadence.)

**Impact.** No user-facing data bug results — exchange-rate staleness is still fully handled by the foreground/unlock/initial-task refresh path, so rates stay fresh. The impact is code clarity and a small waste: the timer is effectively dead code for its stated purpose (it cannot fire under realistic iOS usage), yet it schedules a repeating main-run-loop timer source and reads as if it complements the 12h staleness window when it does not. A future maintainer may assume periodic in-session refresh works via this timer and build on that false premise, or waste time debugging why it never fires.

**Fix.** Prefer removing `exchangeRateRefreshTimer` (line 12) and its `.onReceive` handler (lines 63-66) entirely, since `handleAppBecameActive()` already covers refresh on foreground, unlock, and launch. If an in-session periodic refresh is genuinely wanted, shorten the interval to a value meaningful for a foreground session (e.g. `30 * 60` to `60 * 60`) so it can actually fire, and add a comment noting it is best-effort foreground-only (Combine timers do not run in the background). Do not leave it at 5h with the `.active` guard — under that combination it can never fire in practice.

---

### DA-L03 — Recurring-notification sync runs twice on a due-generation pass (explicit call + onChange observer overlap)

- **Low** · CodeQuality · iOS+macOS · confidence: Medium
- **Location:** `Sources/iOS/ContentView.swift:70`

**Current code**
```swift
// ContentView.swift:70-72
.onChange(of: finance.data.recurringTransactions) { _, _ in
    Task { await syncRecurringNotifications() }
}

// ContentView.swift:127-140 (processRecurringTransactions)
let insertedCount = finance.processDueRecurringTransactions(settings: settings)
guard insertedCount > 0 else { return }
await syncRecurringNotifications()   // <- redundant with the onChange above on a generation pass

// FinanceStore.swift:427-445 (generation always mutates the array, then saves)
occurrence = next
schedule.nextDueDate = next
schedule.updatedAt = now
schedulesChanged = true
...
if generatedCount > 0 || schedulesChanged { save() }
```

**Problem.** On both iOS (ContentView.swift) and macOS (MacRootView.swift), `processRecurringTransactions()` calls `syncRecurringNotifications()` explicitly whenever `insertedCount > 0`, and a separate `.onChange(of: finance.data.recurringTransactions)` observer also calls `syncRecurringNotifications()` whenever that array changes by Equatable. Because `processDueRecurringTransactions` always advances each due schedule's `nextDueDate`/`updatedAt` (FinanceStore.swift:427-428) and then calls `save()` (line 445), any generation pass mutates the recurring array — so both paths fire for the same mutation, running the notification sync (a full remove-then-rebuild of all pending recurring requests) twice. The explicit call inside the `insertedCount > 0` branch is redundant with the onChange on the generation path. Separately, the onChange runs a whole-array Equatable diff on every `finance.data` republish (every save anywhere in the app), though it only spawns the sync Task when the array actually differs.

**Impact.** Wasteful duplicated work whenever a scheduled transaction becomes due: `RecurringNotificationService.sync` reads `pendingNotificationRequests()`, removes all recurring requests, and re-adds up to 60 `UNCalendarNotificationTrigger` requests — doing this twice back-to-back for a single due-generation event. The service is an `actor`, so the two syncs serialize and each fully rebuilds; there is no dropped-reminder window, but roughly double the notification-center churn is performed for no benefit. Not corrupting and low-impact, but a clear efficiency/redundancy defect.

**Fix.** Remove the redundancy by deleting the explicit `syncRecurringNotifications()` call from the `insertedCount > 0` branch of `processRecurringTransactions()` (ContentView.swift:133 and MacRootView.swift:195), relying on the `.onChange(of: finance.data.recurringTransactions)` observer to trigger the single sync after `save()` republishes the mutated array. This is safe because a generation pass always advances `nextDueDate`/`updatedAt`, guaranteeing the observer fires. If you prefer to keep the sync driven explicitly rather than via onChange, do the inverse: drop the onChange observer and keep the explicit call, but then also handle the schedulesChanged-without-generation path (fast-forward/deactivation, where `processRecurringTransactions` returns early on `insertedCount == 0`). Additionally, to reduce the per-save Equatable cost, consider driving the observer from a narrower signal — e.g. a computed hash/version of only the notification-relevant fields (id, isActive, isCompleted, notificationsEnabled, nextDueDate, endDate, amount, category, type) — rather than deep-equality over the entire RecurringTransaction array on every republish.

---

### DA-L04 — Spending-pie drag gesture re-runs the un-memoized expensesByCategory (filter+group+sort) on every touch sample

- **Low** · Performance · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/CashFlowView.swift:142`

**Current code**
```swift
// CashFlowView.swift:142
let categories = finance.expensesByCategory(period: period, settings: settings)
// ...
// L203-207: drag mutates hoveredExpenseCategory, forcing `analytics` (and L142) to re-run
DragGesture(minimumDistance: 0)
    .onChanged { value in
        withAnimation(.easeInOut(duration: 0.15)) {
            hoveredExpenseCategory = categorySlice(at: value.location, in: frame, categories: categories)
        }
    }
// AnalyticsEngine.swift:190 — not memoized; runs full filter+convert+group+sort each call
func expensesByCategory(period: AnalyticsPeriod) -> [CategoryTotal] {
    let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
    let grouped = Dictionary(grouping: expenses, by: \.category)
        .mapValues { $0.reduce(Decimal(0)) { $0 + displayAmount($1) } }
    // ... percentages + .sorted { $0.value > $1.value }
}
```

**Problem.** In CashFlowView, the `analytics` view property computes `let categories = finance.expensesByCategory(period: period, settings: settings)` at L142. That store method (FinanceStore.swift:773) is not memoized (unlike calculateTotals): each call constructs a fresh AnalyticsEngine and, in AnalyticsEngine.expensesByCategory (AnalyticsEngine.swift:190-204), filters every transaction, currency-converts each with displayAmount, groups them into a Dictionary, derives percentages, and sorts — an O(n) pass. Because `analytics` reads the `hoveredExpenseCategory` @State (L156 and L166), the pie's DragGesture.onChanged (L203-207) — which sets `hoveredExpenseCategory` inside withAnimation on every finger-move callback — invalidates the view and re-evaluates the whole `analytics` body, re-running L142 for each gesture sample. DashboardView.topExpenses (DashboardView.swift:419) also calls the same un-memoized expensesByCategory. Note the finding's broader claim that Dashboard's totals/assetAllocation are un-memoized is incorrect: FinanceStore.calculateTotals is cached (cachedTotals, keyed by dataVersion+currency+rateStamp), and assetAllocation routes through it, so the repeated `totals.*` metric-card reads are already cheap.

**Impact.** On a dataset with many transactions, dragging a finger across the spending pie fires onChanged many times per second, and each callback re-runs the full filter/group/sort (plus a Decimal→Double bridge per foreign-currency record) purely to update which slice is highlighted — work that does not depend on the hover position at all. This can produce frame drops during the drag. The effect is bounded: the categories array is identical across all samples in a single drag, and the common all-same-currency case skips the FX multiply (CurrencyConverter short-circuits when source==target), so on small/medium datasets the cost is modest — hence Low rather than a hard performance bug.

**Fix.** Decouple the hover state from the category recomputation so the drag gesture does not re-run expensesByCategory. Two viable approaches: (1) Compute `categories` once and cache it in @State keyed by (period, finance.dataVersion) — recompute only when the period picker changes or data mutates, and have the drag gesture merely index into the stored array. Since dataVersion is currently private, either expose a lightweight published token on FinanceStore or key the cache off period + finance.data.transactions.count/a hash. (2) Extract the hover-dependent chartBackground overlay into its own small subview that takes the already-computed `categories` array and the hovered id as parameters, so mutating the hover @State only re-renders that subview and never re-enters the property that calls expensesByCategory. Additionally, consider memoizing expensesByCategory in FinanceStore the same way calculateTotals is (a cache tuple keyed by dataVersion+currency+rateStamp+period), which would also benefit DashboardView.topExpenses (DashboardView.swift:419). Do not touch the calculateTotals path — it is already memoized.

---

### DA-L05 — YTD (and rolling) transaction filter compares startOfDay-stored dates against a timezone-recomputed boundary, dropping day-boundary items after a timezone shift

- **Low** · Correctness · iOS · confidence: Low
- **Location:** `Sources/iOS/Views/CashFlowView.swift:499`

**Current code**
```swift
private var filteredTransactions: [Transaction] {
    finance.transactions.filter { transaction in
        let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
        let matchesPeriod = transactionStartDate.map { transaction.date >= $0 && transaction.date <= Date() } ?? true
        return matchesType && matchesPeriod
    }
}
// ...
case .yearToDate:
    return calendar.date(from: calendar.dateComponents([.year], from: now))
```

**Problem.** `transactionStartDate` (CashFlowView.swift L487-503) derives each period boundary in the current calendar/timezone: `.yearToDate` (L499) returns Jan 1 00:00 of the current year, and `.sevenDays/.thirtyDays/.threeMonths` subtract from `now`. `filteredTransactions` (L478-484) then keeps transactions where `transaction.date >= startDate && transaction.date <= Date()`. Transactions are persisted as `Calendar.current.startOfDay(for: date)` (FinanceStore.swift L237), an absolute instant tied to the timezone in effect when they were created. Because the stored instant and the recomputed boundary are anchored to potentially different timezones, a transaction whose stored startOfDay sits on the period boundary day can fall on the wrong side of the comparison after the device crosses a timezone (or DST) boundary. The most visible case is a Jan 1 transaction viewed from a timezone west of where it was created: its stored instant precedes the recomputed Jan 1 00:00 boundary and it is filtered out of Year-to-Date.

**Impact.** A Jan 1 transaction silently drops out of the Year-to-Date list after the user travels to a more-western timezone (or across DST), making it look like data was lost even though the record is still stored. The same day-boundary off-by-one can spuriously include or exclude items at the 7/30/90-day cutoffs. Low impact because it is transient and display-only (no persisted data is lost), but it undermines trust in a finance app where users cross-check totals.

**Fix.** Normalize both sides of the comparison to calendar days rather than raw instants. In `filteredTransactions`, compare `calendar.startOfDay(for: transaction.date)` against the boundary, and compute the boundary once as a start-of-day value; make the upper bound `calendar.startOfDay(for: Date())` (inclusive of today) instead of the instantaneous `Date()`. Equivalently, filter with `calendar.isDate(transaction.date, inSameDayAs:)`/`calendar.compare(_:to:toGranularity: .day)` so the check is day-granular and timezone-shift tolerant. Since all stored transaction dates are already `startOfDay`, aligning the boundary to `calendar.startOfDay(for: boundary)` (and for YTD, `startOfDay` of Jan 1) removes the sub-day skew. Optionally hoist `Calendar.current` and the boundary out of the per-element closure so they are computed once per filter pass.

---

### DA-L06 — Unstructured fire-and-forget Tasks in CashFlow view methods are unowned and never cancelled

- **Low** · Concurrency · iOS+macOS · confidence: Medium
- **Location:** `Sources/iOS/Views/CashFlowView.swift:551`

**Current code**
```swift
private func saveRecurringTransaction(_ schedule: RecurringTransaction) {
    finance.upsertRecurringTransaction(schedule)

    Task {
        if schedule.notificationsEnabled {
            let authorized = await RecurringTransactionNotificationService.shared.requestAuthorization()
            if !authorized {
                finance.setRecurringNotificationsEnabled(id: schedule.id, isEnabled: false)
                activeAlert = .message(
                    title: settings.localized("Notifications Disabled"),
                    message: settings.localized("The schedule was saved, but notifications are not authorized. You can enable them in iOS Settings and then edit this schedule.")
                )
            }
        }
        await syncRecurringNotifications()
    }
}
```

**Problem.** saveRecurringTransaction (CashFlowView.swift:551), toggleRecurringTransaction (568), completeRecurringTransaction (573-575), and the delete-alert closure (604-606) each launch a bare `Task { ... }` that calls into RecurringNotificationService and, in the save path, mutates `finance` and sets the `activeAlert` @State after an await. MacCashFlowView.swift has the identical pattern (897-909, 914, 919-921). These Tasks are detached from the view's lifecycle (unlike `.task`/`.task(id:)`), are never stored, and are never cancelled, so if the tab/view is torn down while the async authorization request is in flight, the continuation still runs to completion. Note the finding's 'presents an alert on the dismissed sheet' framing is inaccurate: `activeAlert` is @State on CashFlowView (line 37) with `.alert(item: $activeAlert)` at line 114 — it lives on the list view, not the sheet, and presenting it after the sheet dismisses is the intended behavior. There is no data race here: FinanceStore/AppSettings are @MainActor, RecurringNotificationService is an `actor`, and these methods are MainActor-isolated, so a post-await @State write on a torn-down view is a harmless SwiftUI no-op.

**Impact.** The practical harm is limited. On the MainActor, a @State write to a view that is no longer rendered is silently ignored by SwiftUI (no crash, no corruption). The only observable effect of the unstructured Tasks is that a pending notification-authorization request and its follow-up sync keep running through view teardown, and the finance mutations persist regardless of navigation (which is generally the desired outcome). The value of fixing this is code clarity and structured-concurrency correctness — making the async work's lifetime explicit — rather than avoiding a concrete failure.

**Fix.** Optional cleanup, not a correctness fix. Where the async result drives view UI (the save path that sets `activeAlert`), prefer structured concurrency tied to lifecycle, e.g. trigger the authorization+sync from a `.task(id:)` keyed on the just-saved schedule, or store the returned Task in a @State and cancel it in `.onDisappear`. For the purely detached work (toggle/complete/delete just call `syncRecurringNotifications()` or `cancel(scheduleID:)`), leaving a fire-and-forget Task is acceptable, but consider centralizing notification-sync in the store so it survives view teardown intentionally rather than incidentally. No behavioral change is required for correctness.

---

### DA-L07 — Net-worth change percentage explodes when the range's baseline snapshot is a tiny non-zero value

- **Low** · Correctness · iOS · confidence: Low
- **Location:** `Sources/iOS/Views/DashboardView.swift:524`

**Current code**
```swift
private func netWorthChange(in points: [NetWorthPoint]) -> (value: Double, percentage: Double)? {
    guard let first = points.first, let last = points.last, first.date != last.date else {
        return nil
    }
    let change = last.value - first.value
    let percentage = first.value != 0 ? change / abs(first.value) * 100 : 0
    return (change, percentage)
}
```

**Problem.** In netWorthChange (DashboardView.swift:519-526), the percentage is computed as `change / abs(first.value) * 100` guarded only by `first.value != 0`. Using abs(first.value) as the denominator is fine for sign handling — the badge (lines 143-150) already normalizes the amount and percentage with abs() and conveys direction via the arrow/color from `rangeChange.value >= 0` — so there is NO sign-inversion bug. The real defect is the denominator: when the first snapshot in the selected range is a small but non-zero net worth (common right at a debt-to-solvency crossover, e.g. first.value = 1 or -3), the percentage explodes (e.g. -1000 → +100 over a baseline that dipped to +1 yields ~500000%). The `!= 0` check only catches exact zero, not the near-zero band, so an implausibly large percentage badge is rendered verbatim via privatePercent at line 145.

**Impact.** A user whose net worth crosses zero (climbing out of debt) can have a range whose starting snapshot is a tiny value near zero. The headline movement badge then shows an absurd percentage like 4000%+ next to a modest absolute change, which reads as a bug and undermines trust in the primary metric. It is not a correctness/data issue (the number is finite and the absolute-change amount shown alongside it is correct), so impact is cosmetic and confined to this crossover edge case — hence Low.

**Fix.** Suppress or clamp the percentage when abs(first.value) is below a small epsilon relative to the change (mirroring the existing `first.value == 0` handling). Concretely, change line 524 to gate on magnitude, e.g. `let percentage = abs(first.value) > 1 ? change / abs(first.value) * 100 : 0`, or better, return an optional percentage and have the badge (line 145) render \"—\" (or hide the percentage Text) when the baseline is within a tiny band around zero, keeping only the arrow and the absolute-change amount. Do not change the sign logic — it is already correct.

---

### DA-L08 — Type-toggle wipes in-progress custom category text and dismisses the keyboard while picker stays on "Custom..."

- **Low** · UX · iOS · confidence: High
- **Location:** `Sources/iOS/Views/Forms.swift:92`

**Current code**
```swift
.onChange(of: type) { _, newValue in
    // Only reset category when changing type if user hasn't selected a valid category for the new type
    if !settings.transactionCategories(for: newValue).contains(category) && !isCustomCategorySelected {
        category = settings.transactionCategories(for: newValue).first ?? ""
    }
    customCategory = ""
    isCustomCategoryFocused = false
}
```

**Problem.** In TransactionFormView.onChange(of: type) (Sources/iOS/Views/Forms.swift L87-94) and identically in RecurringTransactionFormView.onChange(of: type) (L287-294), the lines `customCategory = ""` and `isCustomCategoryFocused = false` run unconditionally whenever the Type segmented control changes. When the user has "Custom..." selected (isCustomCategorySelected == true) and is mid-typing a new category name, flipping Type keeps the "Custom..." selection (the guard `&& !isCustomCategorySelected` on L89/L289 short-circuits and does NOT reset `category`), yet still discards the typed draft and drops keyboard focus. The category onChange handler does not compensate because `category` never changes value in this path (it remains == customCategoryTag), so its else-branch that clears the draft never runs. Because currentCategoryName then resolves to the emptied custom text, isSaveDisabled silently flips back to true.

**Impact.** A user types "Freelance" into the custom-category field, realizes it should be Income rather than Expense, and taps the Type toggle. The picker correctly stays on "Custom...", but the typed text vanishes, the keyboard collapses, and the Save button silently re-disables (currentCategoryName becomes empty) with no visible reason. The user must re-focus the field and retype the entire name. Affects the add/edit flows for both one-off and recurring transactions on iOS.

**Fix.** Guard the draft-clear/unfocus so it only fires when the effective category actually leaves Custom, mirroring the existing L89/L289 guard. In both handlers replace:

    customCategory = ""
    isCustomCategoryFocused = false

with:

    if !isCustomCategorySelected {
        customCategory = ""
        isCustomCategoryFocused = false
    }

This preserves the in-progress custom name and keyboard focus while the picker remains on "Custom...", and still clears them when the type change moves the selection off Custom. Apply identically at Forms.swift L92-93 (TransactionFormView) and L292-293 (RecurringTransactionFormView).

---

### DA-L09 — New recurring schedule's future-only Save guard uses render-time Date(), silently blocks same-day past times with no feedback

- **Low** · Correctness · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/Forms.swift:274`

**Current code**
```swift
    private var isSaveDisabled: Bool {
        guard let amount = parsedAmount, amount > 0 else { return true }
        return currentCategoryName.isEmpty
            || (existingSchedule == nil && startDate <= Date())
            || (normalizedEndDate.map { $0 < startDate } ?? false)
    }
```

**Problem.** In `RecurringTransactionFormView.isSaveDisabled`, the branch `(existingSchedule == nil && startDate <= Date())` (Forms.swift line 274) requires a NEW schedule's first occurrence to be strictly in the future. Two problems: (1) It is a hard requirement with no explanation — the DatePicker (lines 352-356) shows both date and hour-and-minute, so if a user picks today at a time that has already passed (e.g. it is 20:00 and they pick today 09:00), Save is permanently greyed out with no visible reason. (2) `Date()` is captured only when SwiftUI recomputes the body; the `.disabled(isSaveDisabled)` modifier (line 383) is not driven by any Timer/TimelineView, so if the user leaves the sheet open (default start is now+1h, line 230) and the clock passes startDate, no state change triggers a recompute — Save stays enabled and `saveSchedule()` runs `RecurringScheduleBuilder.build` with a now-past startDate. The saved-with-past-start case is benign in data terms because `RecurringScheduleBuilder.build` already clamps the next due date forward via `firstOccurrence(onOrAfter: now)` (RecurringScheduleBuilder.swift line 52; FinanceModels.swift lines 345-364) and never back-dates, which is precisely why the strict guard is heavier-handed than the domain logic needs.

**Impact.** A user setting up a schedule to start "today" at a time that already passed (very common — it is evening and they pick this morning) sees Save greyed out with zero feedback and cannot understand why or how to proceed; the natural fix (allow same-day and let the builder clamp forward) is already supported by RecurringScheduleBuilder. Separately, because the disabled state is computed from a render-time Date() with no clock-driven refresh, the button can be stale relative to the real time, so its enabled/disabled state near "now" is inconsistent. No data corruption results (the builder clamps forward), so impact is confined to confusing UX and inconsistent button state.

**Fix.** Prefer relaxing the guard: since `RecurringScheduleBuilder.build` already clamps the next due date forward with `firstOccurrence(onOrAfter: now)` and deactivates rather than back-dating, allow a same-day or slightly-past startDate to save. For example drop the `startDate <= Date()` term from `isSaveDisabled` (keep the amount/category/end-date checks), letting the builder handle clamping. If a future-only rule must be kept for new schedules, (a) surface the reason with an inline caption in the Schedule section shown when `existingSchedule == nil && startDate <= Date()` (e.g. "First occurrence must be in the future"), and (b) drive the comparison off a clock source (wrap the relevant view in `TimelineView(.periodic(from: .now, by: 60))` or hold a `@State` `now` updated by a `Timer`) so the button state tracks the real clock instead of a stale render-time `Date()`.

---

### DA-L10 — Investment/Crypto Save allows zero or garbage price (and zero avg buy price), creating degenerate positions

- **Low** · Correctness · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/Forms.swift:547`

**Current code**
```swift
.disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0)
```

**Problem.** In Forms.swift, the Save button's `.disabled` predicate for both InvestmentFormView (L547) and CryptoFormView (L700) only rejects empty symbol/name and `parsedQuantity <= 0`. It does not validate the current price or the average buy price. Because `parse()` (L590/L734) coerces any unparseable input to 0 (`MoneyParser.decimal(from:) ?? 0`), a user can save a position with currentPrice = 0 (or typed garbage like "abc"), yielding currentValue = quantity * 0 = 0 (L556), or with avgBuyPrice = 0 plus a nonzero fee, yielding costBasis = fee only (L555). The comments at L588-589/L732-733 claim the `> 0` save guards block these zeros, but that guard applies only to quantity — price is never guarded. Downstream, gainLossPercent guards `costBasis > 0` (FinanceModels.swift L385-387/L406-408), so a zero-price row reports 0% instead of a total loss, silently distorting gain and allocation summaries.

**Impact.** A user who fat-fingers or blanks the Current Price field can save a holding that reports its entire value as 0 (a silent total loss) with no warning, deflating net worth and skewing asset-allocation and gain/loss charts. Similarly a 0 average buy price with a fee produces a nonsensical cost basis. Nothing in the UI signals the position is degenerate, and the misleading in-code comment implies the price is already guarded when it is not.

**Fix.** Extend the `.disabled` predicate at Forms.swift L547 and L700 to also require `parsedCurrentPrice > 0` so a zero/garbage price can never be saved. Where a meaningful cost basis is expected (a newly added lot), also require `parsedAverage > 0`; if you want to keep allowing an unknown/zero cost basis for gifted/airdropped assets, at minimum still block a zero current price. Better UX: keep Save enabled but surface inline validation on the Current Price / Average Buy Price fields (red helper text) so the user sees why the position is rejected. Also correct the now-misleading comments at L588-589 and L732-733, since only quantity is guarded by `> 0`, not price.

---

### DA-L11 — biometryName / biometrySymbolName allocate a fresh LAContext and call canEvaluatePolicy on every SwiftUI body pass

- **Low** · Performance · iOS · confidence: High
- **Location:** `Sources/iOS/Views/LockView.swift:26`

**Current code**
```swift
    func biometryName(appLanguage: String?) -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return AppLocalization.string("Face ID", appLanguage: appLanguage)
        ...
    func biometrySymbolName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
```

**Problem.** BiometricLockStore.biometryName(appLanguage:) (BiometricLockStore.swift lines 25-38) and biometrySymbolName() (lines 41-54) each allocate a new LAContext and call canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) synchronously before reading context.biometryType. LockView.body reads biometryName twice (LockView.swift lines 34 and 43) plus biometrySymbolName once (line 44), producing 3 LAContext allocations + 3 policy evaluations per body recompute. SettingsView.body also calls biometryName in the Security section label (SettingsView.swift line 61) on every settings recompute. The store is @MainActor, so all of this runs on the main thread. Biometry type is fixed for the running session, so recomputing it per body pass is wasted work.

**Impact.** LAContext.canEvaluatePolicy touches the biometry subsystem and is not free. SettingsView re-renders on every @Published AppSettings/FinanceStore change while the Settings tab is on screen (currency change, privacy toggle, sync-status update, etc.), and LockView re-renders on locale/error changes — so this runs repeatedly on the main thread to produce a value that never changes during the session. It is a needless main-thread cost and can generate biometry-subsystem log noise. No correctness impact, hence Low severity.

**Fix.** Resolve biometry type once and cache it in BiometricLockStore. Add a stored/lazy property, e.g. `private lazy var cachedBiometryType: LABiometryType = { let ctx = LAContext(); _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil); return ctx.biometryType }()` (the canEvaluatePolicy call is required before reading biometryType), then have both biometryName(appLanguage:) and biometrySymbolName() switch on `cachedBiometryType` instead of constructing a new LAContext per call. Biometry type does not change while the app runs, so a lazy-once cache is safe; the authenticate() path can keep its own fresh LAContext for the actual evaluation.

---

### DA-L12 — BiometricLockStore.authenticate has no in-flight guard, so LockView's auto-.task and Unlock button can launch two concurrent LAContext evaluations

- **Low** · Concurrency · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/LockView.swift:110`

**Current code**
```swift
    private func authenticate(reason: String, appLanguage: String?) async -> Bool {
        // WC-L2: `.deviceOwnerAuthentication` is biometrics WITH an automatic device-passcode
        // fallback ...
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription
                ?? AppLocalization.string("Biometric authentication is not available on this device.", appLanguage: appLanguage)
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                Task { @MainActor in
                    if let authenticationError {
                        self.lastError = authenticationError.localizedDescription
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
```

**Problem.** `LockView.task` (LockView.swift lines 67-69) auto-calls `await appLock.unlock(appLanguage:)` on appear, and the Unlock button (lines 39-40) spawns a Task calling the same `unlock`. Both reach `BiometricLockStore.authenticate` (BiometricLockStore.swift lines 110-133), which has no re-entrancy guard. Because `authenticate` is async and suspends at `await withCheckedContinuation` (line 123) while the biometric sheet is up, the `@MainActor` isolation no longer serializes callers — a button tap while the auto-prompt is displayed runs a second `authenticate`, creating a second `LAContext` and a second concurrent `evaluatePolicy(.deviceOwnerAuthentication)`. Two continuations then resume independently, each able to set `self.lastError` (line 127). The same guardless `authenticate` also backs `enableLock`, `confirmDisableLock`, and the macOS `MacLockView` (MacPlatformServices.swift lines 73, 94-95).

**Impact.** A user who taps "Unlock with Face ID/Touch ID" while the automatic prompt from `.task` is already displayed triggers two overlapping `evaluatePolicy` calls: a confusing double prompt, and a losing continuation that resumes with an authentication error and writes it to `lastError` (line 127) — potentially overwriting the cleared error state set by a concurrently-successful unlock (`unlock` clears `lastError` at line 106). The visible impact is limited because a successful unlock immediately removes LockView (ContentView.swift line 16), but the double biometric sheet and the error-state race are real and most likely to surface for Switch Control / VoiceOver users or anyone who taps during the prompt.

**Fix.** Add a re-entrancy guard in `BiometricLockStore.authenticate` so it protects all callers (unlock, enableLock, confirmDisableLock, and both platforms' lock views). Add `@Published private(set) var isAuthenticating = false` (or a plain flag) and at the top of `authenticate` (before creating the LAContext, ~line 114): `guard !isAuthenticating else { return false }`, set `isAuthenticating = true`, and reset it in a `defer { isAuthenticating = false }` (or right before returning on every path). Because the store is `@MainActor`, this set/check runs atomically within the synchronous prologue of each `authenticate` call, so the second caller returns early before starting a second `evaluatePolicy`. Optionally also disable/guard LockView's Unlock button while `isAuthenticating` is true for a cleaner UX (e.g. `.disabled(appLock.isAuthenticating)`), but the store-level guard is the load-bearing fix.

---

### DA-L13 — Onboarding 'Skip for now' silently discards a just-typed API key without saving or warning

- **Low** · UX · iOS · confidence: Medium
- **Location:** `Sources/iOS/Views/OnboardingView.swift:322`

**Current code**
```swift
                        Button(action: skipOnboarding) {
                            Text("Skip for now")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(WCColor.textSecondary)
                        }
                        .disabled(viewModel.isValidating)
// ...
    private func skipOnboarding() {
        completeOnboarding()
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            settings.hasSeenOnboarding = true
        }
    }
```

**Problem.** On the onboarding API-setup page, "Get Started" runs `viewModel.submit(...)` — the only code path that validates typed keys and persists them to the Keychain (OnboardingViewModel.submit, lines 28-64). "Skip for now" (OnboardingView.swift line 322) instead calls `skipOnboarding()` → `completeOnboarding()` (lines 357-365), which only sets `settings.hasSeenOnboarding = true` and never touches `submit`. If the user pastes/types a valid key into the Finnhub or CoinGecko SecureField and then taps "Skip for now" (both buttons are stacked and simultaneously visible), the typed value — held only in the @Published `finnhubKey`/`coinGeckoKey` on the @StateObject that is destroyed when the view goes away — is silently dropped and onboarding completes. The same code shape is present on macOS (MacOnboardingView.swift, skip button line 331).

**Impact.** A user pastes their Finnhub/CoinGecko key, then taps the adjacent "Skip for now" instead of "Get Started". The key is never written to the Keychain, market data silently stays stale/placeholder, and the user believes they configured it. To recover they must independently discover the Settings > Market Data path and re-enter the key. There is no error, no confirmation, and no visible signal that their input was thrown away.

**Fix.** In `skipOnboarding()`, if either draft field is non-empty after trimming, route through `viewModel.submit(appLanguage:)` (persisting/validating the typed keys) before completing, mirroring the "Get Started" handler; on success call `completeOnboarding()`, on failure show the existing validation alert. Alternatively, when either field has content, either (a) present a confirmation that typed keys will be discarded, or (b) disable/relabel the "Skip for now" button. Apply the same change to MacOnboardingView.swift's `skipOnboarding()` (line 365) so both platforms behave consistently.

---

### DA-L14 — Deliberate user-cancel of the biometric prompt sets lastError, surfacing a persistent red 'error' in the Settings Security section

- **Low** · UX · iOS · confidence: Low
- **Location:** `Sources/iOS/Views/SettingsView.swift:65`

**Current code**
```swift
// SettingsView.swift:65-73 (rendering)
if let error = appLock.lastError {
    Text(error)
        .font(.caption)
        .foregroundStyle(WCColor.destructive)
} else {
    Text("When enabled, Wealth Compass locks whenever the app leaves the foreground.")
        .font(.caption)
        .foregroundStyle(WCColor.textSecondary)
}

// BiometricLockStore.swift:126-128 (root cause — no cancel handling)
if let authenticationError {
    self.lastError = authenticationError.localizedDescription
}
```

**Problem.** `BiometricLockStore.authenticate` (Sources/Shared/Services/BiometricLockStore.swift:126-128) sets `self.lastError = authenticationError.localizedDescription` for ANY error the `LAContext` callback returns, without distinguishing genuine failures from user-initiated cancels (`LAError.userCancel`, `.systemCancel`, `.appCancel`). When the user taps the App Lock toggle in iOS Settings and then cancels the Face ID / Touch ID sheet on purpose, `enableLock`/`confirmDisableLock` return false and the Toggle correctly reflects the unchanged `isLockEnabled` state — but `lastError` is now populated. The Security section (Sources/iOS/Views/SettingsView.swift:65-73) renders that string in `WCColor.destructive` (red) in place of the neutral helper text. `lastError` is only cleared on a *successful* enable (line 64), disable (line 76), or unlock (line 106), so the red error persists across re-entry into Settings until the next successful authentication. The same unconditional-error rendering also affects LockView.swift:54 (cancelling the auto-triggered unlock prompt) and the macOS settings (MacSettingsView.swift:256), so the fix at the store level covers all surfaces. Note the finding's original title claim that the toggle 'leaves visually ON' after a cancelled disable is not itself a bug — the toggle tracks live `isLockEnabled` and behaves correctly; the real defect is the spurious error text.

**Impact.** A user taps the App Lock toggle, then deliberately dismisses the Face ID / Touch ID sheet. Nothing actually went wrong, yet the Security section now shows a red error string (e.g. localized 'Authentication canceled' / 'Canceled by user') as if the app failed. It persists every time they open Settings until they successfully authenticate elsewhere. This is misleading noise for an intentional, benign user action, and the same red banner appears on the lock screen (LockView) when a user dismisses the unlock prompt to, say, background the app.

**Fix.** Fix at the source in BiometricLockStore.authenticate (Sources/Shared/Services/BiometricLockStore.swift:123-132) so a deliberate cancel is not treated as an error. In the `evaluatePolicy` completion, inspect the error code before assigning `lastError`, e.g.:

```swift
if let authenticationError {
    let code = (authenticationError as NSError).code
    if code == LAError.userCancel.rawValue
        || code == LAError.systemCancel.rawValue
        || code == LAError.appCancel.rawValue {
        self.lastError = nil            // benign cancel — not an error
    } else {
        self.lastError = authenticationError.localizedDescription
    }
}
```

(`import LocalAuthentication` is already present.) This automatically fixes the iOS Settings Security section, LockView, and the macOS settings surfaces because they all just render `appLock.lastError`. Optionally, also clear `lastError` when the user re-enters Settings (e.g. an `.onAppear` on the Security section) so any stale genuine error doesn't linger indefinitely.

---

### DA-L15 — Settings is reachable via both a sidebar destination and the native Settings scene, so the two MacSettingsView instances keep divergent local UI state

> **✅ RESOLVED (2026-07-13).** The native `Settings { }` scene was removed from `WealthCompassMacApp.swift`; ⌘, is now remapped via `CommandGroup(replacing: .appSettings)` to select the single in-window `MacSettingsView` sidebar destination, so only one instance exists. The "Current code" snapshot below is the pre-fix state at audit time.

- **Low** · Architecture · macOS · confidence: Medium
- **Location:** `Sources/macOS/MacRootView.swift:132`

**Current code**
```swift
// MacRootView.swift (sidebar detail)
        case .settings:
            MacSettingsView()

// WealthCompassMacApp.swift (native Settings scene)
        Settings {
            MacSettingsView()
                .environmentObject(finance)
                .environmentObject(settings)
                .environmentObject(appLock)
                .preferredColorScheme(.dark)
                .appLanguage(settings.appLanguage)
                .id(settings.appLanguage ?? "system")
        }
```

**Problem.** MacSettingsView is instantiated in two independent places: (1) as the sidebar `detail` destination in MacRootView.swift line 133 (`case .settings: MacSettingsView()`), reached by clicking "Settings" in the split-view sidebar or via ⌘5, and (2) as the standard macOS `Settings` scene in WealthCompassMacApp.swift lines 81-89, reached via the app menu / ⌘,. These are two separate SwiftUI view instances, each holding its own copy of the ~18 `@State` properties declared in MacSettingsView.swift lines 111-127 (selectedTab, importMode, credentialDraft, activeCredentialEditor, settingsAlert, isRefreshingPrices, pendingDestructiveAction, etc.). Any transient UI state, in-progress API-key entry, alert presentation, or selected-tab position in one is not reflected in the other. The two copies also have divergent language-change lifecycles: the Settings-scene copy is `.id`-ed on language directly (WealthCompassMacApp.swift line 88) while the sidebar copy is `.id`-ed via the whole detail branch (MacRootView.swift line 54). Persisted preferences stay in sync (they live in the shared AppSettings store); only ephemeral view-local state diverges. Note the authors deliberately kept Settings as a sidebar destination — see the explicit comment at MacRootView.swift lines 37-38 — so this is a known trade-off, not an accidental duplicate.

**Impact.** A user can open Settings two different ways (⌘, and the sidebar/⌘5) and observe inconsistent local UI: e.g. select the "Data" tab and start typing a Finnhub API key in the sidebar Settings, then open the ⌘, Settings window and find it back on the "General" tab with an empty key draft. It is also redundant on macOS, where ⌘, is the platform convention for a dedicated Settings window and having a duplicate in-window Settings page is unusual. Impact is limited to transient view state — no data loss, and shared preferences remain consistent.

**Fix.** Pick one canonical Settings surface. Preferred macOS-idiomatic option: keep only the native `Settings` scene (⌘,) and remove Settings from the sidebar — drop the `.settings` case from `MacDestination` (MacAppModel.swift lines 9, 19, 29, and the `.settings` arm at line 62), remove the ⌘5 "Settings" command (WealthCompassMacApp.swift lines 72-75), remove `case .settings: MacSettingsView()` from the detail switch (MacRootView.swift lines 132-133), and simplify the now-unconditional refresh toolbar (MacRootView.swift line 39 `if appModel.selection != .settings` guard). Alternatively, if the in-window sidebar Settings is preferred for discoverability, remove the `Settings { ... }` scene from WealthCompassMacApp.swift lines 81-89 instead. If both surfaces must be retained, lift the shared transient UI state (at minimum `selectedTab`) into an `@StateObject`/observable owned above both instances so they don't diverge.

---

### DA-L16 — Cash-flow chart joins hover to bars by the localized month label instead of the stable monthKey id

- **Low** · Bug · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:320`

**Current code**
```swift
// MacCashFlowView.swift
BarMark(
    x: .value("Month", month.monthLabel),   // line 286 — keyed on localized "MMM" label
    y: .value("Amount", month.income)
)
...
if let monthLabel: String = proxy.value(atX: x) {
    withAnimation(.easeInOut(duration: 0.15)) {
        hoveredCashFlowMonth = trend.first { $0.monthLabel == monthLabel }  // line 320 — join by label, not id
    }
}
// CashFlowMonth (FinanceModels.swift:497): var id: String { monthKey }
```

**Problem.** In both macOS cash-flow cards, the BarMark x-value is `month.monthLabel` (a localized "MMM" abbreviation from AnalyticsEngine.cashFlowTrend, AnalyticsEngine.swift:172/183), while the stable identity `CashFlowMonth.id` is `monthKey` ("yyyy-MM", FinanceModels.swift:497). The onContinuousHover handler reads the categorical value under the cursor via `proxy.value(atX:)` and resolves the month with `trend.first { $0.monthLabel == monthLabel }` (MacCashFlowView.swift:320, MacDashboardView.swift:557), then the per-bar dimming compares by id (`hoveredCashFlowMonth?.id == month.id`, MacCashFlowView.swift:292/303, MacDashboardView.swift:529/540). Joining hover to data through the display label is fragile: it relies on the "MMM" abbreviation being unique across the plotted window and on the proxy returning a byte-identical string. It works today only because CashFlowTimeframe (MacDashboardView.swift:1068) caps the window at 12 months, so month abbreviations do not repeat.

**Impact.** This is a latent maintenance landmine rather than a currently-observable bug. If a CashFlowTimeframe case greater than 12 months is ever added (e.g. 24M), the same "MMM" label would appear for two different months in the window, and hovering one bar would highlight and report the other month's income/expense/net in the legend (the CashFlowLegendItem values at MacCashFlowView.swift:341/346 read hoveredCashFlowMonth). A stable join key (monthKey / id) already exists and would make the hover logic correct regardless of window size or locale.

**Fix.** Join hover to data by the stable id rather than the label. Since `proxy.value(atX:)` returns the categorical x value, plot the bar keyed on `month.monthKey` (`x: .value("Month", month.monthKey)`), add a `.chartXAxis` value-label transform that maps monthKey back to the display "MMM" for the axis, and resolve hover as `trend.first { $0.monthKey == key }`. Alternatively keep the visible label but resolve the hovered month by plot position/index rather than string equality. Apply the same change in both MacCashFlowView.swift (BarMark x at 286/297, hover at 320) and MacDashboardView.cashFlowCard (BarMark x at 523/534, hover at 557). Low-priority robustness cleanup, not urgent.

---

### DA-L17 — Future-dated transactions vanish from the cash-flow table under every period filter except 'All'

- **Low** · UX · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:842`

**Current code**
```swift
let matchesPeriod = transactionStartDate.map {
    transaction.date >= $0 && transaction.date <= Date()
} ?? true
```

**Problem.** In MacCashFlowView.swift, `filteredTransactions` (lines 838-848) filters each non-.all period with `transaction.date >= start && transaction.date <= Date()`. `transactionStartDate` (lines 852-868) is nil only for the .all period, so 7d/30d/3m/YTD all impose the `<= Date()` upper bound. The transaction editor DatePicker (line 1068; also MacEditorSheet.swift:117) has no `in:` range, so a user can save a transaction dated in the future. That transaction is then hidden under all four dated period filters and only reappears when Period is set to 'All'. The 'Showing X of Y' counter (line 702) reflects only filteredTransactions.count, so the row silently disappears with no indication of why.

**Impact.** A user post-dates a payment (e.g. next week's rent) and then cannot find it under the default period filters; the "Showing X of Y" counter offers no hint that it's hidden by the date window, so they may re-enter it, creating a duplicate. Note the future transaction is not lost — it persists and is visible under 'All' — so this is a visibility/UX defect, not data loss.

**Fix.** Decide whether future-dated transactions are allowed. Recommended: disallow them by bounding the editor's DatePicker: `DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)` at MacCashFlowView.swift:1068 (and the identical DatePicker in MacEditorSheet.swift:117, plus the iOS editor for parity). This keeps the table and AnalyticsEngine (which also clamps `<= now` at AnalyticsEngine.swift:289) consistent with no other change. If instead future transactions ARE intended to be visible, remove the `&& transaction.date <= Date()` clause at MacCashFlowView.swift:842 AND the matching `&& $0.date <= now` at AnalyticsEngine.swift:289 together so the table and dashboard agree; do not change only one.

---

### DA-L18 — Cash-flow chart body and Mac transaction editor duplicated near-verbatim across dashboard and cash-flow views (plus divergent custom-category sentinels)

- **Low** · CodeQuality · macOS · confidence: High
- **Location:** `Sources/macOS/Views/MacCashFlowView.swift:993`

**Current code**
```swift
// MacCashFlowView.swift:993
private static let customCategoryTag = "__wealth_compass_mac_custom_category__"
// MacEditorSheet.swift:23
private static let customCategoryTag = "__wealth_compass_custom_category__"
// MacCashFlowView.swift:355 and MacDashboardView.swift:599 (identical)
Text(settings.localized("\(cashFlowRange.localizedTitle(appLanguage: settings.appLanguage)) NET"))
```

**Problem.** The macOS cash-flow chart card is duplicated almost verbatim between MacDashboardView.cashFlowCard (MacDashboardView.swift:481-615) and MacCashFlowView.cashFlowTrendCard (MacCashFlowView.swift:257-371): same trend/hasCashFlow/totalIncome/totalExpense setup, same income+expense BarMarks with identical opacity/accessibility modifiers, the same .chartOverlay onContinuousHover block matching `trend.first { $0.monthLabel == monthLabel }`, the same CashFlowLegendItem(Income/Expenses) legend, and the same `settings.localized("\(cashFlowRange.localizedTitle(appLanguage:)) NET")` label and net-value computation. The only deltas are cosmetic (dashboard adds axis config, a 'View Cash Flow' button, and uses WCColor.textFaint instead of .secondary). Separately, the two functionally-identical Mac transaction editors define the custom-category Picker sentinel with DIFFERENT string literals: MacCashFlowView.swift:993 `__wealth_compass_mac_custom_category__` and MacEditorSheet.swift:23 `__wealth_compass_custom_category__`. (Each literal is self-contained and compared only against its own Self.customCategoryTag, so the divergence is a maintainability smell rather than a runtime bug.) The whole MacCashFlowTransactionEditor (MacCashFlowView.swift:986+) largely duplicates MacTransactionEditor (MacEditorSheet.swift:18+).

**Impact.** Any change to the cash-flow chart — currency display, hover keying, legend text, localization, accessibility labels, axis styling — must be applied in two places (dashboard + cash-flow view), and any change to the transaction editor must be applied in two more, making inconsistent application easy. This duplication is the mechanism behind observed editor drift and the two divergent sentinel literals are a concrete instance of that drift already present in the tree.

**Fix.** Extract a single reusable CashFlowChartCard SwiftUI view parameterized by (trend, cashFlowRange binding, and optional chrome such as axis config / trailing accessory button) and use it from both MacDashboardView.cashFlowCard and MacCashFlowView.cashFlowTrendCard. Extract a single shared Mac transaction editor used by both MacEditorSheet and the cash-flow add/edit flow, eliminating MacCashFlowTransactionEditor. Centralize the custom-category sentinel as one shared constant (e.g. a static on a shared type) so all editors reference the same literal; while doing so, unify the two Mac transaction-editor literals so they cannot drift.

---

### DA-L19 — Redundant double-localization: MetricCard status titles wrap an already-resolved String in LocalizedStringKey

- **Low** · Localization · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacCryptoView.swift:120`

**Current code**
```swift
// MacCryptoView.swift:118-123
let uniqueCryptoCount = Set(finance.data.crypto.map(\.symbol).filter(isNonEmpty)).count
MetricCard(
    title: LocalizedStringKey(settings.localized("Status • \(privateCount(uniqueCryptoCount)) Coins")),
    value: latestUpdate.map(formattedUpdate) ?? settings.localized("Never"),
    systemImage: "checkmark.circle"
)
// MacInvestmentsView.swift:141 — identical pattern with "Status • \(privateCount(sectorCount)) Sectors"
```

**Problem.** In MacCryptoView.swift:120 and MacInvestmentsView.swift:141, the status MetricCard title is built as `LocalizedStringKey(settings.localized("Status • \(count) Coins"/"Sectors"))`. `settings.localized(...)` already fully resolves the catalog entry (`Status • %@ Coins` / `Status • %@ Sectors`, which have real per-language translations) against the effective locale, returning a finished String. That String is then re-wrapped in `LocalizedStringKey`, and since `MetricCard.title: LocalizedStringKey` is rendered with `Text(title)` (DesignSystem.swift:197), SwiftUI performs a SECOND localization lookup, treating the already-translated text as a new catalog key. It renders correctly today only because the resolved string is not itself a catalog key and `Text` falls through to verbatim. This is redundant work that works by accident, not by design, and is fragile against future catalog additions. (Note: because the root sets both `\.appLanguage` and `\.locale` to the same effective locale, this is NOT a system-vs-app-locale mismatch as the original finding's whyItMatters implied.)

**Impact.** Today the visible text is correct (the second lookup misses and renders verbatim), so user-facing impact is currently nil. The risk is latent/robustness: the double lookup does redundant work, and if a resolved translation ever happens to coincide with another key in Localizable.xcstrings, `Text` would silently re-substitute it, producing wrong text with no compile-time warning. The pattern also confuses string-catalog extraction — the catalog already contains a garbled auto-generated key `"Status • %@) Coins"` — increasing maintenance risk.

**Fix.** Stop double-localizing already-resolved strings. Add a verbatim/String initializer to `MetricCard` (DesignSystem.swift:174) that stores the title as a `Text` or renders it via `Text(verbatim:)` so it is never re-localized, e.g. add `init(verbatimTitle: String, value: String, systemImage: String, accent: Color = WCColor.primary)` that keeps the title as a plain String and renders `Text(verbatim: titleString)`. Then change MacCryptoView.swift:120 to `MetricCard(verbatimTitle: settings.localized("Status • \(privateCount(uniqueCryptoCount)) Coins"), value: ..., systemImage: "checkmark.circle")` and MacInvestmentsView.swift:141 to the same for "Status • %@ Sectors". Alternatively, since the title needs a runtime-interpolated count that Text/LocalizedStringKey can localize directly, drop `settings.localized(...)` entirely and pass `LocalizedStringKey("Status • \(privateCount(...)) Coins")` — but note that only honors the SwiftUI environment locale, so the verbatim-String route is safer given the in-app language override. Audit for the same `LocalizedStringKey(settings.localized(...))` anti-pattern elsewhere.

---

### DA-L20 — Mac transaction/investment/crypto editors omit the active currency code from their amount/price field labels (inconsistent with the recurring editor)

- **Low** · UX · iOS+macOS · confidence: Low
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:79` (also: `Sources/macOS/Views/MacEditorSheet.swift:79`, `Sources/macOS/Views/MacRecurringTransactionEditor.swift:116`)

**Current code**
```swift
// MacEditorSheet.swift (MacTransactionEditor)
TextField("Amount", text: $amount)                       // line 79
Picker("Currency", selection: $currency) {               // line 80
    ForEach(Currency.allCases) { currencyOption in
        (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
    }
}

// MacRecurringTransactionEditor.swift (for comparison)
TextField("Amount (\(currency.rawValue))", text: $amount) // line 116
```

**Problem.** In MacEditorSheet.swift the MacTransactionEditor's Amount field is labeled just "Amount" (line 79) even though a Currency picker directly below it (lines 80-84) selects the currency the number is interpreted in. The same applies to the investment editor's "Average Buy Price"/"Current Price" fields (lines 273-274) and the crypto editor's price fields (lines 423-424), each of which sits next to a Currency picker. By contrast, MacRecurringTransactionEditor.swift:116 labels its field "Amount (\(currency.rawValue))", so the active currency is always visible beside the value. Switching the Currency picker does not (and correctly should not) convert the already-typed number — but with no currency shown in the label, a user who edits the picker after typing gets no visual cue that the same digits are now interpreted in a different currency. This is a pure UI-consistency gap, not a math or data-loss bug: `addTransaction`/`upsertInvestment`/`upsertCrypto` store the amount verbatim in the chosen currency, which is the intended semantics for a fresh entry.

**Impact.** A user types 1000 intending EUR, then adjusts the Currency picker to USD to correct the holding's currency. There is no conversion (by design) and, because the Amount label never shows the currency, no on-screen reminder that the 1000 is now 1000 USD. The recurring-transaction editor already avoids this ambiguity by embedding the currency code in the field label; the transaction, investment, and crypto editors do not, so the three most-used editors are the ones missing the cue. Impact is minor (a mis-entered currency, easily corrected), which is why this is Low severity.

**Fix.** For consistency with MacRecurringTransactionEditor.swift:116, change MacEditorSheet.swift line 79 from `TextField("Amount", text: $amount)` to `TextField("Amount (\(currency.rawValue))", text: $amount)`. Apply the same treatment to the investment price fields (lines 273-274: e.g. `TextField("Average Buy Price (\(currency.rawValue))", text: $averagePrice)` and `TextField("Current Price (\(currency.rawValue))", text: $currentPrice)`) and the crypto price fields (lines 423-424). Note these interpolated labels are non-localizable string keys, matching how MacRecurringTransactionEditor already does it, so no new xcstrings entry is required. Purely a display change — no logic in `save()` needs to change.

---

### DA-L21 — Interpolating a lowercased localized type/frequency noun into %@ localization templates mangles capitalization and grammar (e.g. German lowercase noun)

- **Low** · Localization · iOS+macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:168` (also: `Sources/macOS/Views/MacRecurringTransactionEditor.swift:154`, `Sources/macOS/Views/MacSettingsView.swift:560`, `Sources/macOS/Views/MacEditorSheet.swift:168`)

**Current code**
```swift
    private var customCategoryHint: String {
        let typeName = type.localizedTitle(appLanguage: settings.appLanguage).lowercased()
        if trimmedCustomCategory.isEmpty {
            return settings.localized("Enter a category name. It will be saved for future \(typeName) transactions.")
        }
        ...
        return settings.localized("This category will be added to your \(typeName) categories.")
    }
```

**Problem.** Several macOS hint/validation strings build `type.localizedTitle(appLanguage:).lowercased()` (or the frequency equivalent) and interpolate it into a `settings.localized(...)` template. Since the argument is a `String.LocalizationValue`, the interpolated value becomes a `%@` runtime argument and the catalog stores a `%@` template. Translators therefore receive a bare `%@` and, at runtime, a lowercased localized noun is substituted. In languages that capitalize nouns (German) or have locale-specific casing (Turkish I/İ), the composed sentence is grammatically/orthographically wrong, because Swift's parameterless `.lowercased()` is not locale-aware and blindly lowercases a translated noun. Confirmed at 5 sites, all in Sources/macOS/: MacEditorSheet.swift:168 (and reused at 170/179), MacRecurringTransactionEditor.swift:154, MacSettingsView.swift:560, MacCashFlowView.swift:949 (frequency name), MacCashFlowView.swift:1095. An analogous iOS variant exists at SettingsView.swift:507 (`Text("No custom \(title.lowercased()) categories yet.")`).

**Impact.** A German user sees "Die Kategorie wird für zukünftige einkommen-Transaktionen gespeichert." — "einkommen" is a lowercased noun where German grammar requires "Einkommen". The same applies to "Noch keine benutzerdefinierten einkommen-Kategorien." and to lowercased frequency names in MacCashFlowView. Because `.lowercased()` uses the root locale, casing in locales like Turkish is also handled incorrectly in the general case. Purely cosmetic (no data or correctness impact), but it degrades perceived polish across the ~40 shipped localizations, especially the noun-capitalizing ones.

**Fix.** Stop lowercasing a translated noun at runtime. Best fix: provide two fully-translated, self-contained templates per TransactionType (one for income, one for expense) — e.g. keys "This category will be saved for future income transactions." / "...expense transactions." selected in Swift via a `switch type` — so translators control the entire sentence including case and word order. Do the same for the frequency variant in MacCashFlowView.swift:949. If separate keys are undesirable, at minimum replace `.lowercased()` with locale-aware `.lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))` to fix Turkish-style casing — but note this still leaves German nouns lowercased, so it does not fully solve the problem. Apply consistently to all 5 macOS sites and the iOS SettingsView.swift:507 variant.

---

### DA-L22 — Fee mode (fixed vs percent) is not persisted, so percent fees reopen as a frozen fixed amount and stop scaling on re-edit

- **Low** · UX · iOS+macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:199` (also: `Sources/macOS/Views/MacEditorSheet.swift:373`, `Sources/iOS/Views/Forms.swift:470`)

**Current code**
```swift
// MacEditorSheet.swift:199 (MacInvestmentEditor) — same pattern at :373, and Forms.swift:442/:610
@State private var feeMode: FeeMode = .fixed
@State private var feeValue: String
// ...
_feeValue = State(initialValue: investment.map { Self.input($0.fees) } ?? "0")  // line 224: seeds from absolute fees
// ...
private var calculatedFee: Decimal {
    feeMode == .fixed
        ? parsedFeeValue
        : (parsedQuantity * parsedAveragePrice) * (parsedFeeValue / 100)   // lines 231-235
}
```

**Problem.** `Investment` and `CryptoHolding` (Sources/Shared/Models/FinanceModels.swift:367-388, :390-409) store only the computed absolute `fees: Decimal`. `FeeMode` (FinanceModels.swift:208) exists purely as editor UI state. All four editors — MacInvestmentEditor (MacEditorSheet.swift:199), MacCryptoEditor (MacEditorSheet.swift:373), InvestmentFormView (Forms.swift:442), CryptoFormView (Forms.swift:610) — hard-init `feeMode = .fixed` and seed `feeValue` from the absolute stored `fees` (MacEditorSheet.swift:224, :387; Forms.swift:462, :625). Consequently a fee originally entered as a percentage always reopens as Fee Type = Fixed with the field showing the absolute currency amount. `calculatedFee` (MacEditorSheet.swift:231-235, :397-401; Forms.swift:469-470, :635-636) then evaluates the `.fixed` branch, so on any subsequent edit of quantity or average price the fee no longer re-derives from position size — the original percentage intent is silently discarded. A plain re-save (e.g. after editing the name) is harmless because averagePrice is seeded net of fees and cost basis is reconstructed as `qty*avgPrice + calculatedFee`, keeping the total consistent.

**Impact.** A user sets a 0.5% commission on a position, later doubles the quantity, and expects the fee (and thus cost basis) to scale with the larger position as the broker actually charges. Instead the reopened editor is in Fixed mode holding the old absolute fee, so `calculatedFee` returns the stale amount and the recomputed cost basis understates the true commission — skewing gain/loss. The stored data is never corrupted on a no-op save; the issue only surfaces when the user re-edits position size assuming percent still applies, which the UI does not actually promise.

**Fix.** Make the entry-time vs edit-time representation a conscious, consistent choice. Preferred: persist the fee input mode and raw value so percent fees round-trip. Add `var feeMode: FeeMode = .fixed` and `var feeInput: Decimal = 0` (or a single `var feeRate: Decimal?` for the percentage) to `Investment` and `CryptoHolding` in FinanceModels.swift (both are `Codable` with defaulted fields, so existing JSON decodes cleanly). Seed the four editors' `@State feeMode`/`feeValue` from those persisted fields instead of hard-coding `.fixed` and the absolute `fees`, and on save write both the raw input+mode and the computed absolute `fees`. If percent round-tripping is deemed out of scope, instead make the current behavior explicit in the UI (e.g. relabel the reopened field so users understand fees are always stored/edited as an absolute amount) so there is no silent divergence between entered intent and displayed value. Apply the same change to all four editors (MacEditorSheet.swift:199/:373, Forms.swift:442/:610) to keep iOS and macOS consistent.

---

### DA-L23 — Changing the Currency picker on an existing investment/crypto holding relabels the money to the new currency without converting quantity/price, silently misvaluing the position

- **Low** · Correctness · macOS · confidence: Low
- **Location:** `Sources/macOS/Views/MacEditorSheet.swift:341` (also: `Sources/macOS/Views/MacEditorSheet.swift:254`, `Sources/macOS/Views/MacEditorSheet.swift:417`)

**Problem.** In MacInvestmentEditor (and identically in MacCryptoEditor), the Currency picker on an EXISTING holding is not backed by any conversion logic. On edit it is seeded from the stored currency (line 217) while the quantity/average/current price fields are seeded from the stored numeric magnitudes (lines 220-223), which are expressed in that stored currency. The picker (lines 254-258) is bound to `$currency` with no onChange handler that converts the entered figures (the only onChange handlers in the file, lines 70 and 98, are for `type` and `category`). On save the editor recomputes `value.currentValue = parsedQuantity * parsedCurrentPrice` (line 339) from the raw entered magnitudes and assigns `value.currency = currency` (line 341). Consequently, changing the picker from the holding's original currency to another currency keeps the original-currency-magnitude numbers but re-labels them as the new currency, with no FX conversion. Because market refreshes store prices in the holding's own currency (FinanceStore line 664), a position priced in USD that is re-tagged EUR in the editor becomes misvalued; net-worth conversion in AppSettings.convert then treats the USD-magnitude numbers as EUR. Unlike the recurring-transaction editor which surfaces a warning styling for its amount currency (MacRecurringTransactionEditor.swift line 194), the holding editors give no indication that changing currency is label-only.

**Impact.** A user edits an existing USD stock and switches the Currency picker to EUR intending to "match their base currency," expecting the figures to convert. Instead the raw USD-magnitude quantity/price are stored under the EUR label. AppSettings.convert then multiplies those EUR-labeled-but-USD-valued numbers by the EUR→display FX rate, mis-stating the position's value and therefore the total net worth. The error is silent: no warning, no conversion, and the internally-consistent `currentValue = quantity * price` recompute masks that anything went wrong.

**Fix.** On the Currency picker in both MacInvestmentEditor and MacCryptoEditor, when editing an EXISTING holding, either (a) attach an `.onChange(of: currency)` that converts the entered averagePrice / currentPrice (and thus derived fee/cost) from the previous currency to the newly selected one via settings' FX conversion, or (b) disable the picker for existing holdings, or (c) show an inline warning (matching the WCColor.warning styling used in MacRecurringTransactionEditor line 194) that changing currency does not convert the entered figures. Option (a) is the least surprising; if implementing it, track the previous currency in an @State and convert price fields on change, guarding against non-finite/zero rates as AppSettings.convert already does. At minimum, document in the section footer that currency change is label-only.

---

### DA-L24 — Three AllocationCharts in a fixed HStack squeeze and truncate legends on narrow detail panes (macOS)

- **Low** · UX · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacInvestmentsView.swift:40`

**Current code**
```swift
HStack(spacing: 24) {
    AllocationChart(
        title: LocalizedStringKey("Allocation by Sector"),
        slices: finance.investmentAllocation(settings: settings),
        settings: settings
    )
    AllocationChart(
        title: LocalizedStringKey("Allocation by Type"),
        slices: finance.investmentTypeAllocation(settings: settings),
        settings: settings
    )
    AllocationChart(
        title: LocalizedStringKey("Allocation by Geography"),
        slices: finance.investmentGeographyAllocation(settings: settings),
        settings: settings
    )
}
```

**Problem.** In MacInvestmentsView.swift the Overview tab lays out three `AllocationChart`s side by side in a plain `HStack(spacing: 24)` (lines 40-56) with no `ViewThatFits`, wrapping grid, or per-chart minimum width. Each AllocationChart expands with `.frame(maxWidth: .infinity, ...)` (DesignSystem.swift line 388), so all three share the pane width equally. The macOS detail pane can be as narrow as `minWidth: 520` (MacRootView.swift line 34) and the sidebar is user-resizable, so at the narrow end each chart collapses to roughly 140pt. The legend rows in AllocationChart (DesignSystem.swift lines 363-385) render slice names and values as `.subheadline` text in an HStack with a Spacer and no `minimumScaleFactor`, so those labels truncate. Note the crypto overview uses `ViewThatFits(in: .vertical)` (MacCryptoView.swift line 36), but that only adapts the vertical axis and does not solve this horizontal-squeeze problem — neither view reflows charts when the pane narrows.

**Impact.** On a narrowed window or a small display, the three allocation pie charts are each compressed to ~140pt, and their legend labels (slice names + monetary values) truncate, degrading readability of the core investment breakdown — the primary content of the Investments Overview.

**Fix.** Replace the fixed `HStack(spacing: 24)` at lines 40-56 with a width-adaptive container. Simplest: wrap the three charts in a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 480), spacing: 24)], alignment: .top, spacing: 24)` so they reflow to two rows (or one column) when the pane narrows — mirroring the adaptive `summaryColumns`/topHoldings grids already used elsewhere in this file. Alternatively use `ViewThatFits(in: .horizontal)` with the current HStack as the wide layout and a `VStack(spacing: 24)` fallback for narrow widths. Either approach keeps the charts readable at the `minWidth: 520` extreme.

---

### DA-L25 — Recurring editor saveSchedule() does not re-validate the 'first occurrence in the future' guard it advertises via the disabled state (impact bounded by downstream forward-clamp)

- **Low** · Correctness · macOS · confidence: Medium
- **Location:** `Sources/macOS/Views/MacRecurringTransactionEditor.swift:222` (also: `Sources/macOS/Views/MacRecurringTransactionEditor.swift:221`)

**Current code**
```swift
    private func saveSchedule() {
        guard let parsedAmount, parsedAmount > 0 else { return }
        // NOTE: no re-check of `existingSchedule == nil && startDate <= Date()`
        // nor the normalizedEndDate < startDate guard that isSaveDisabled (line 77-78)
        // and validationMessage (line 88-92) advertise.
```

**Problem.** In MacRecurringTransactionEditor.swift, isSaveDisabled (line 74-79) and validationMessage (line 88) enforce that a NEW schedule's startDate must be `> Date()`. These are computed properties whose Date() only re-evaluates when SwiftUI re-runs the body/property; there is no timer, so if the view does not re-render after the chosen start time passes, the Save button can remain enabled on a stale evaluation. saveSchedule() (line 221-222) then re-checks only `parsedAmount > 0` — it never re-validates the date invariant — so the save path does not enforce the precondition the disabled state advertises. This is a self-consistency gap between the advertised guard and the actual save path. Impact is bounded, not open-ended: RecurringScheduleBuilder.build clamps nextDueDate to firstOccurrence(onOrAfter: now) at build time, so a slightly-past startDate yields a future nextDueDate (next frequency step), and processDueRecurringTransactions already hardens against any past nextDueDate. Thus no past-dated schedule data is persisted and nothing fires immediately — contrary to the original finding's stated consequence.

**Impact.** The gap is a robustness/consistency defect, not a data-corruption bug. Realistic worst case: a user opens the editor, sets the first occurrence to 10:00, gets distracted, and hits Cmd-S at 10:05 while the button is still enabled from a stale render. saveSchedule() accepts it without re-checking the date, and RecurringScheduleBuilder pushes the first occurrence forward to the next frequency interval (e.g. next month) instead of the user's intended 'today at 10:00'. The user quietly gets a schedule whose first occurrence is one interval later than the UI implied — a minor UX surprise. No back-dated transactions are generated and no invariant on stored data is broken, because the builder and processDueRecurringTransactions both clamp/guard past dates.

**Fix.** Mirror the disabled-state preconditions inside saveSchedule() so the save path is authoritative and render-timing-independent. After the amount guard at line 222, add: `guard existingSchedule != nil || startDate > Date() else { return }` and re-apply the end-date check `guard normalizedEndDate.map({ $0 >= startDate }) ?? true else { return }`. Alternatively, gate on `guard !isSaveDisabled else { return }` to keep a single source of truth. This closes the consistency gap; note it does not change persisted behavior in the current codebase because the builder already forward-clamps, so treat it as a low-priority hardening/consistency fix rather than a correctness bug.

---

### DA-L26 — Settings error-alert bodies bypass appLanguage: errorMessage(_:) uses errorDescription (system locale) while titles use settings.localized, yielding mixed-language alerts

- **Low** · Localization · macOS · confidence: Low
- **Location:** `Sources/macOS/Views/MacSettingsView.swift:838` (also: `Sources/macOS/Views/MacSettingsView.swift:651`, `Sources/macOS/Views/MacSettingsView.swift:756`)

**Current code**
```swift
    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
```

**Problem.** MacSettingsView.errorMessage(_:) resolves an error's user-facing text via `(error as? LocalizedError)?.errorDescription`, which for app-defined errors is built against the system locale rather than the in-app language override (AppSettings.appLanguage). It is used for the MESSAGE body of import/export/keychain-credential failure alerts (lines 651, 680, 711, 755, 776, 797), whereas the alert TITLES at those same sites are localized with `settings.localized(...)` (appLanguage-aware). The concrete case: FinanceStore.importBackup throws FinanceImportError, a LocalizedError whose `errorDescription` delegates to `localizedDescription(appLanguage: nil)` (FinanceStore.swift:76-89); with appLanguage == nil, AppLocalization resolves to `.current` (the system locale). FinanceImportError already exposes an appLanguage-aware `localizedDescription(appLanguage:)` that errorMessage never uses. The same code and gap exist on iOS (SettingsView.swift:567 / errorMessage at 671-672). The CloudKit erase path (MacSettingsView.swift:824) already threads appLanguage correctly and is not affected.

**Impact.** A user who sets an in-app language different from their device language (e.g. app in Italian, system in English) and hits an import failure sees a translated title ("Importazione non riuscita") above an English body ("The selected file is not a valid Wealth Compass JSON backup."). Every app-defined LocalizedError surfaced through these Settings alerts renders its body in the wrong language, producing an inconsistent, unprofessional alert. It is purely cosmetic (no data impact) and only manifests when appLanguage differs from the system language.

**Fix.** Make errorMessage appLanguage-aware and call the appLanguage accessor for app-defined errors. Concretely, change the signature to `private static func errorMessage(_ error: Error, appLanguage: String?) -> String` and switch on known types before the generic fallback, e.g.: `if let e = error as? FinanceImportError { return e.localizedDescription(appLanguage: appLanguage) }; if let e = error as? CloudSyncError { return e.localizedDescription(appLanguage: appLanguage) }; return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription`. Update the six call sites (651, 680, 711, 755, 776, 797) to pass `settings.appLanguage`. Alternatively, add an appLanguage parameter to a shared helper. Apply the identical fix to Sources/iOS/Views/SettingsView.swift (errorMessage at 671-672, call site 618, and inline usage at 567). Generic framework/Foundation errors legitimately keep the system-locale fallback.

---

### DA-L27 — Decimal(finite:) can return a NaN Decimal for extreme finite Doubles, so convert(Decimal)'s `?? value` fallback never fires

- **Low** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Models/CurrencyConverter.swift:53`

**Current code**
```swift
        let converted = convert(value.doubleValue, from: source, to: target)
        return Decimal(finite: converted) ?? value
```

**Problem.** `convert(_ value: Decimal, from:to:)` at CurrencyConverter.swift:53 does `Decimal(finite: converted) ?? value`, trusting `Decimal(finite:)` to return nil for bad values. But `Decimal(finite:)` (MoneyDecimal.swift:23-26) only guards `value.isFinite` on the Double and never re-checks the Decimal it constructs; `Decimal(Double)` returns a NaN Decimal for finite Doubles whose magnitude exceeds Decimal.greatestFiniteMagnitude (~3.4e144). For such an input the initializer returns the NaN Decimal (non-nil), the `?? value` fallback is skipped, and a non-finite Decimal escapes. NOTE: contrary to the original finding, ordinary out-of-precision magnitudes (1e39-1e144, e.g. any realistic holding converted at IDR/KRW rates) do NOT trigger this — they round to valid finite Decimals. The threshold (~3.4e144) is only reachable with an input `value` around 1e140 given the app's ~20,000 max FX multiplier, so this is a defensive-hardening gap, not a bug realistic money data can hit.

**Impact.** If a corrupt or absurd near-infinite Decimal ever reached this path (or `Decimal(finite:)` were reused at a less-bounded boundary), the NaN Decimal would bypass the `?? value` guard and propagate into sums, stored money, and Swift Charts geometry — the exact NaN-into-CoreGraphics failure the codebase's guards exist to prevent. Under normal money values and FX rates it cannot occur, so real-world impact is negligible; the value is closing the latent hole so the guard is actually sound.

**Fix.** Fix the root cause in `Decimal(finite:)` (MoneyDecimal.swift:23-26) so it re-validates the constructed Decimal, e.g.:
```swift
init?(finite value: Double) {
    guard value.isFinite else { return nil }
    let decimal = Decimal(value)
    guard decimal.isFinite else { return nil }   // reject NaN Decimal from out-of-range Double
    self = decimal
}
```
With that, CurrencyConverter.swift:53 (`Decimal(finite: converted) ?? value`) and FinanceStore.swift:708 (`Decimal(finite: converted)`) become automatically correct — the nil branch fires and the original `value` / nil is returned. No change is needed at the call site itself.

---

### DA-L28 — gainLossPercent uses `costBasis > 0` guard, silently returning 0% for zero- or negative-cost-basis positions

- **Low** · Correctness · Shared · confidence: Low
- **Location:** `Sources/Shared/Models/FinanceModels.swift:386`

**Current code**
```swift
    var gainLoss: Decimal { currentValue - costBasis }
    var gainLossPercent: Double {
        costBasis > 0 ? (gainLoss.doubleValue / costBasis.doubleValue) * 100 : 0
    }
```

**Problem.** Investment.gainLossPercent (lines 385-387) and CryptoHolding.gainLossPercent (lines 406-408) both compute `costBasis > 0 ? (gainLoss.doubleValue / costBasis.doubleValue) * 100 : 0`. When costBasis == 0 (e.g. an airdrop or gifted holding, or a crypto lot with avgBuyPrice == 0 since CryptoHolding.costBasis is `quantity * avgBuyPrice` at line 403) the property returns 0 even though gainLoss (= currentValue - costBasis) is a real positive amount. A negative costBasis (a directly-stored Investment.costBasis edited/imported below zero) also collapses to 0 rather than a computed percent. The literal 0 return is indistinguishable in the UI from a genuine 0% return.

**Impact.** Holdings acquired at zero cost (airdrops, gifts, fully-fee-offset lots) display a misleading "+0.0%" return in the investment/crypto pills and best/worst-performer ranking (MacCryptoView.swift:152-169 sorts and filters on this value), understating their real performance even though the absolute gain is shown correctly. It is a correctness/UX inconsistency, not a crash or data-loss issue, hence Low.

**Fix.** The percentage is genuinely undefined when costBasis == 0, and for a negative costBasis the division produces a sign-flipped, misleading percent — so `costBasis != 0` alone is not sufficient. Preferred fix: change both properties to `Double?`, returning nil for `costBasis <= 0`, and update the consumers (InvestmentsView.swift:146, CryptoView.swift:139, MacInvestmentsView.swift:224, MacCryptoView.swift:152-169/203/283) to render "—" (or hide the pill) for the nil case and to exclude nil from best/worst ranking. If keeping a non-optional Double is required, at minimum document that the returned 0 means "not computable" rather than "no gain". Both the Investment and CryptoHolding copies must be changed identically.

---

### DA-L29 — load() leaves a corrupt/invalid exchange-rate file in place instead of clearing it (blocks legacy migration; delays self-heal)

- **Low** · ErrorHandling · Shared · confidence: Medium
- **Location:** `Sources/Shared/Persistence/ExchangeRatePersistence.swift:38`

**Current code**
```swift
guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
guard let data = try? Data(contentsOf: storageURL) else { return nil }
guard let snapshot = try? decoder.decode(ExchangeRateSnapshot.self, from: data),
      snapshot.isValid else { return nil }
return snapshot
```

**Problem.** In LocalExchangeRatePersistence.load() (Sources/Shared/Persistence/ExchangeRatePersistence.swift:37-39), when the snapshot file exists but Data(contentsOf:) fails, decode fails, or snapshot.isValid is false, the method returns nil but leaves the offending file on disk. Consequences: (1) every subsequent launch re-reads and re-rejects the same bad file; (2) migrateFromUserDefaultsIfNeeded() is gated on `!fileManager.fileExists(atPath: storageURL.path)` (line 71), so a present-but-corrupt file blocks the one-time UserDefaults→file migration from ever running while it sits there. A working clear() (lines 56-64) already implements the best-effort delete needed, but load() never calls it on the failure path, and it does not distinguish 'file absent' from 'file present but unreadable/invalid'. Note the app does recover on its own: a nil snapshot makes shouldAutoRefreshExchangeRates() return true, so the next successful network fetch's atomic save() overwrites the corrupt file — this is a robustness/hygiene gap, not a data-loss bug.

**Impact.** Until a network fetch succeeds, FX-converted totals fall back to the bundled offline seed rates even though a legacy or previously-cached valid snapshot might otherwise have been recoverable, and the legacy-UserDefaults migration is stuck as long as the corrupt file remains. On a device that is offline (or where the FX provider is unreachable) for an extended period after the file was corrupted, the app stays on approximate seed rates with no self-cleaning of the bad artifact. Impact is low because auto-refresh eventually overwrites the file and no user data is lost, but the failure is silent and the file never gets cleaned proactively.

**Fix.** In load(), separate 'file absent' from 'file present but bad'. Keep the early `return nil` when the file does not exist, but when the file exists and any of Data(contentsOf:)/decode/isValid fails, delete it best-effort before returning nil so the next launch/migration/fetch starts clean. Concretely, replace the guards at lines 37-39 with a form that, on failure, logs and removes the file, e.g.:
```
guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
guard let data = try? Data(contentsOf: storageURL),
      let snapshot = try? decoder.decode(ExchangeRateSnapshot.self, from: data),
      snapshot.isValid else {
    Self.logger.error("Discarding unreadable/invalid exchange-rate cache")
    clear() // best-effort delete so migration guard and next fetch aren't wedged
    return nil
}
return snapshot
```
Since migrateFromUserDefaultsIfNeeded() runs at the top of load() before these guards, on a corrupt file the migration is skipped this run but the clear() means the NEXT load() (next launch) will see no file and can migrate. clear() already logs and is a no-op when the file is absent, so it is safe to call here.

---

### DA-L30 — Best-effort pre-CloudKit migration backup failure aborts an already-successful load()

- **Low** · ErrorHandling · Shared · confidence: Medium
- **Location:** `Sources/Shared/Persistence/FinancePersistence.swift:51`

**Current code**
```swift
        if decoded.wasMigrated {
            try createMigrationBackupIfNeeded(sourceData)
            try write(decoded.data)
        }
```

**Problem.** In LocalFinancePersistence.load() (Sources/Shared/Persistence/FinancePersistence.swift), when the decoded data was schema-migrated (wasMigrated == true), createMigrationBackupIfNeeded(sourceData) is called with `try` at line 51 before write(decoded.data) at line 52. The backup is a best-effort safety copy of the pre-migration file, but its `try` propagates: if the backup write fails (disk full, transient I/O error, or completeFileProtectionUnlessOpen being unavailable while the device is locked), the whole load() throws even though FinanceJSONCoding.decodeFinancialData already succeeded on line 49 and the in-memory FinancialData is fully valid. The caller FinanceStore.load() (line 985) catches this into the generic error branch, sets localPersistenceError, and surfaces "The local database could not be loaded." NOTE: the original finding's headline rationale — that the storage directory is not guaranteed to exist — is incorrect. At the backup-write site the parent directory provably exists in both reachable paths (the normal path just read storageURL on lines 47-48; the legacy path called createStorageDirectoryIfNeeded on line 86 before copying). This is purely a best-effort-should-not-be-fatal error-handling issue, confined to the one-time migration branch (fires at most once per install).

**Impact.** On the one-time pre-CloudKit schema-migration load, a transient backup-write failure (disk full, I/O hiccup, or file protection unavailable because the app is launched while the device is still locked) turns a fully-successful in-memory decode into a total load failure: FinanceStore reports "The local database could not be loaded," the store keeps an empty FinancialData, and the user sees a blank UI despite their data being intact on disk. The failure is also self-inflicted by a copy the user never asked for, and it blocks the migrated schema from being written back.

**Fix.** Make the backup best-effort so its failure is logged but non-fatal, and only let the actual migrated-data write (line 52) propagate. Replace `try createMigrationBackupIfNeeded(sourceData)` on line 51 with a swallowed/logged variant, e.g. `try? createMigrationBackupIfNeeded(sourceData)` (or wrap in do/catch that logs via OSLog and continues). Keep `try write(decoded.data)` fatal, since persisting the migrated schema is the operation that must succeed. Do not restructure the reachable directory logic — the directory is already guaranteed present at this point.

---

### DA-L31 — chartYDomain over-zooms to a sub-penny hairline band for all-zero or near-zero net-worth series

- **Low** · UX · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:163`

**Current code**
```swift
        let spread = max(maximum - minimum, max(abs(maximum), 1) * 0.08)
        let padding = spread * 0.18
        return (minimum - padding)...(maximum + padding)
```

**Problem.** In AnalyticsEngine.chartYDomain (Sources/Shared/Services/AnalyticsEngine.swift:163), `spread = max(maximum - minimum, max(abs(maximum), 1) * 0.08)`. When every net-worth point is 0 (a brand-new user: snapshotsForChart always appends a finite currentNetWorth point of 0, so the series is non-empty and the chart renders instead of the EmptyState), maximum==minimum==0 gives spread = max(0, 1*0.08) = 0.08 and padding = 0.0144, producing a y-domain of -0.0144...0.0144 — a chart zoomed to a sub-penny band showing a flat line against an axis with meaningless tick labels. For a net worth that is small and negative (near break-even, liabilities slightly above assets, e.g. -0.5), the 8% relative floor is `max(abs(maximum), 1) * 0.08` = 0.08, giving domain -0.5144...-0.4856 — a band that is correctly centered on the value but over-zoomed, again showing an absurd micro-scale axis. Both iOS (DashboardView.swift:529) and macOS (MacDashboardView.swift:779) dashboards route through this shared static, so both are affected. No test currently pins this small-magnitude behavior as intended.

**Impact.** A new user with net worth 0, or a user underwater near break-even, sees a net-worth chart with an absurd micro-scale y-axis (tick labels like -0.01, 0, 0.01) instead of a sensible readable view. It reads as a rendering bug rather than an empty/near-zero state. Low severity: purely cosmetic/UX, affects a narrow edge cohort (exactly-zero or near-zero-negative net worth), no data loss, no crash (the non-finite path is separately hardened).

**Fix.** Add an absolute minimum spread floor and base the relative floor on both bounds so a zero or near-zero series yields a readable domain. Replace line 163 with something like:
```swift
let range = maximum - minimum
let relativeFloor = max(abs(maximum), abs(minimum), 1) * 0.08
let spread = max(range, relativeFloor, 1)   // absolute floor of 1 currency unit
```
Then keep `padding = spread * 0.18` and the same return. This makes an all-zero series yield roughly -1.18...1.18 (a zero-centered, readable band) and a near-zero-negative series yield a sensibly-scaled window rather than a sub-penny hairline. Add a unit test in Tests/AnalyticsEngineTests.swift asserting that chartYDomain(for: pts([0])) spans at least ~2 units and is centered on 0, and that chartYDomain(for: pts([-0.5])) has a lowerBound below -1.

---

### DA-L32 — cashFlowTrend uses DateFormatters with no fixed timeZone, so its month bucketing diverges from monthlyCashFlow's calendar-granularity bucketing whenever a non-system-timezone calendar is injected

- **Low** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:169`

**Current code**
```swift
    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"

        return stride(from: months - 1, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let monthKey = monthFormatter.string(from: date)
            let transactions = data.transactions.filter { monthFormatter.string(from: $0.date) == monthKey }
```

**Problem.** In AnalyticsEngine.cashFlowTrend (Sources/Shared/Services/AnalyticsEngine.swift:168-188), `monthFormatter` (yyyy-MM) and `labelFormatter` (MMM) are built with no `.timeZone`, so they default to `TimeZone.current`. Transactions are bucketed by comparing `monthFormatter.string(from: $0.date)` to a key derived from `calendar.date(byAdding: .month, ...)`. Meanwhile monthlyCashFlow (lines 71-79) buckets via `calendar.isDate(_:equalTo:toGranularity:.month)`, which honors `calendar.timeZone`. The two paths therefore use two different notions of "month" whenever the injected `calendar` has a timeZone other than `TimeZone.current`. That is exactly the case in the test harness (Tests/AnalyticsEngineTests.swift injects a UTC calendar via `calendar.timeZone = TimeZone(identifier: "UTC")`), so a boundary-dated transaction (e.g. midnight UTC on the 1st) can be attributed to different months by the two methods on any non-UTC test/CI machine. In the production app the divergence does not currently occur because the FinanceStore.analytics(_:) factory (FinanceStore.swift:714-721) does not inject a calendar, leaving the default `.current` whose timeZone matches the formatters' default `TimeZone.current` — so both paths agree. This is a latent correctness/fragility defect rather than a live production bug.

**Impact.** The dashboard cash-flow-trend bars (cashFlowTrend) and the header monthly income/expense figures (monthlyCashFlow) can attribute a boundary-dated transaction to different months once any caller passes an AnalyticsEngine whose `calendar` uses a non-system timezone. This is already the situation in the unit tests (UTC calendar) and would silently break if a future caller injects a fixed-timezone calendar for determinism. It does not affect end users on the current shipping build because production never injects such a calendar, so both paths default to TimeZone.current and agree. The concrete risk is inconsistent/incorrect month attribution in tests and brittleness against a reasonable future change, not a currently-visible discrepancy in the app.

**Fix.** Make cashFlowTrend share the calendar's timezone so both bucketing paths agree. Minimal fix: after creating each formatter, set `monthFormatter.timeZone = calendar.timeZone` and `labelFormatter.timeZone = calendar.timeZone` (and optionally `monthFormatter.calendar = calendar` / `labelFormatter.locale` if you want month labels to follow appLanguage). Better fix (eliminates the string-key bucketing entirely and guarantees one definition of "month"): replace the formatter-based filter with the same calendar-granularity comparison monthlyCashFlow uses — for each `date` in the stride, filter transactions with `calendar.isDate($0.date, equalTo: date, toGranularity: .month)`, and derive monthKey/monthLabel from a formatter that still has `timeZone`/`calendar` set from `calendar`. This keeps cashFlowTrend and monthlyCashFlow consistent under any injected calendar.

---

### DA-L33 — assetAllocation() silently drops negative net cash, so the allocation pie omits cash and its TOTAL contradicts the NET WORTH header

- **Low** · UX · Shared · confidence: Low
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:212`

**Current code**
```swift
    func assetAllocation() -> [AllocationSlice] {
        let totals = calculateTotals()
        return [
            AllocationSlice(name: localized("Investments"), value: totals.totalInvestments.doubleValue, color: .blue),
            AllocationSlice(name: localized("Crypto"), value: totals.totalCrypto.doubleValue, color: .orange),
            AllocationSlice(name: localized("Cash"), value: totals.totalLiquidity.doubleValue, color: .green)
        ].filter { $0.value > 0 }
    }
```

**Problem.** assetAllocation() (AnalyticsEngine.swift lines 206-213) builds Investments/Crypto/Cash slices then applies `.filter { $0.value > 0 }` (line 212). Cash's value is totalLiquidity = income − expense (calculateTotals lines 38-43), which is legitimately negative whenever tracked expenses exceed tracked income (common when a user logs mostly expenses). A negative Cash value is filtered out, so the allocation pie omits cash entirely. The pie's central "TOTAL" label (DesignSystem.swift lines 273/311) sums only the remaining positive slices, while the dashboard NET WORTH header (DashboardView.swift line 134) shows totals.netWorth, which DOES include the negative liquidity. The two numbers therefore disagree and the negative cash drag is invisible in the allocation view. The `.filter { $0.value > 0 }` guard itself is necessary — a Swift Charts SectorMark cannot render a negative angular value — so the fix is about signalling the exclusion, not removing the filter.

**Impact.** A user with −€2,000 net cash and €10,000 investments sees a pie that is 100% Investments with a center TOTAL of €10,000, implying their whole net worth is invested — while the NET WORTH header just above reads €8,000. The two figures visibly contradict each other and the €2,000 cash drag is nowhere in the allocation, so the user cannot tell from the pie that their spending is eroding their liquidity.

**Fix.** Keep the positive-only filter (negative sectors cannot be drawn), but eliminate the silent contradiction. Options: (1) When any candidate slice was dropped for being ≤ 0, show a small note/badge under the pie (e.g. "Cash excluded: −€2,000") so the omission is explicit; or (2) label the pie's center TOTAL as "Positive assets" rather than implying it equals net worth, so it no longer reads as contradicting the NET WORTH header. Since assetAllocation() already discards which slices were removed, capture that before filtering — e.g. compute the full `[AllocationSlice]` array, then split into `visible = all.filter { $0.value > 0 }` and `excluded = all.filter { $0.value <= 0 && $0.value != 0 }`, and thread `excluded` (or at least a boolean/summed-excluded-amount) through to AllocationChart so the legend/footer can surface it. Apply the same treatment on macOS (MacDashboardView.swift line 353 consumes the same function).

---

### DA-L34 — Investment allocation builders omit the value>0 filter that crypto/asset allocations apply, yielding phantom legend rows

- **Low** · Correctness · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:215`

**Current code**
```swift
    func investmentAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.sector)
            .mapValues { items in
                items.reduce(Decimal(0)) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                AllocationSlice(name: item.name, value: item.value.doubleValue, color: ColorPalette.chart[index % ColorPalette.chart.count])
            }
    }   // <- no .filter { $0.value > 0 }, unlike cryptoAllocation()/assetAllocation()
```

**Problem.** In AnalyticsEngine.swift, the three investment allocation builders — investmentAllocation() (215-229), investmentTypeAllocation() (231-250), investmentGeographyAllocation() (252-266) — group investments by sector/type/geography, sum convert(currentValue), and map each bucket to an AllocationSlice, but they do NOT apply `.filter { $0.value > 0 }`. assetAllocation() (line 212) and cryptoAllocation() (line 276) both do. A bucket that sums to exactly 0 — e.g. quantity 0, or a currentPrice of 0 after a failed Finnhub quote — produces a zero-value AllocationSlice. The AllocationChart legend (DesignSystem.swift line 365, `ForEach(slices)` with no filter) then renders a phantom row: the bucket name with a formatted `0` amount and `0.0%`, while the SectorMark draws no visible wedge. This diverges from the crypto/asset donuts, which cleanly hide empty buckets. (The originally-claimed hit-test angle shift does not actually occur: a 0 value adds nothing to the cumulative sum in PieSliceHitTester, so the zero slice is unreachable and later non-zero slices keep their mapping.)

**Impact.** When an investment's market price fetch fails and currentValue lands at 0 (a real, reachable state given direct Finnhub/CoinGecko calls with user-entered keys that can be missing/rate-limited), the investment donut charts show a legend entry for a sector/type/geography with a '0' value and '0.0%' but no visible pie wedge — a confusing, inconsistent presentation the crypto and top-level asset charts do not exhibit. A negative bucket value (theoretically possible) would additionally corrupt the percentage math the filter would otherwise exclude.

**Fix.** Append `.filter { $0.value > 0 }` to the returned array in all three builders, matching cryptoAllocation() (line 276) and assetAllocation() (line 212). Concretely, in investmentAllocation() add it after the `.map { index, item in AllocationSlice(...) }` closing (before line 229's `}`); same for investmentTypeAllocation() after line 249 and investmentGeographyAllocation() after line 265. Because the filter runs after `.enumerated()`, palette color indices are assigned before filtering — acceptable (crypto does the same) since colors need not be contiguous. If strictly contiguous colors are desired, filter the `(name, value)` tuples before `.enumerated()` instead.

---

### DA-L35 — biometryName()/biometrySymbolName() build a new LAContext and re-probe LocalAuthentication on every SwiftUI body evaluation instead of caching the fixed biometry type

- **Low** · Performance · iOS+macOS · confidence: Medium
- **Location:** `Sources/Shared/Services/BiometricLockStore.swift:25`

**Current code**
```swift
    func biometryName(appLanguage: String?) -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return AppLocalization.string("Face ID", appLanguage: appLanguage)
        ...

    func biometrySymbolName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
```

**Problem.** `BiometricLockStore.biometryName(appLanguage:)` (BiometricLockStore.swift:25) and `biometrySymbolName()` (:41) each allocate a fresh `LAContext()` and call `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)` purely to read `context.biometryType`, then map it to a localized name / SF Symbol. Both are invoked directly inside SwiftUI `body` computations: LockView.swift:34 and :43 call `biometryName` twice per render (subtitle + button label) and :44 calls `biometrySymbolName`; SettingsView.swift:61 calls `biometryName` in a Section label; MacPlatformServices.swift:68 (Mac lock view) and MacSettingsView.swift:255 call it too. SwiftUI re-evaluates these bodies on scenePhase transitions and @Published changes (e.g. `appLock.lastError`, `settings.appLanguage`), so the LAContext allocation + framework query runs repeatedly on the main thread even though the device's biometry type never changes at runtime.

**Impact.** Every re-render of the lock and Settings screens allocates a new LAContext and runs a synchronous LocalAuthentication capability query on the main thread — redundant work, since `biometryType` is fixed for the process lifetime. On the lock screen this happens up to ~3 times per body pass. `canEvaluatePolicy` is a synchronous enrollment/capability check (not a biometric authentication round-trip), so the impact is minor rather than a visible stall, but it is pure waste that is trivially eliminable and keeps the main thread busier than necessary during renders.

**Fix.** Resolve the biometry type once and cache it, then expose plain resolved values to views. Compute `LAContext().canEvaluatePolicy(...)` + `biometryType` a single time (lazily on first access or in `init`), store the resulting `LABiometryType` (or the derived symbol name), and have `biometrySymbolName()` and the switch in `biometryName(appLanguage:)` read the cached type. Only the localized-name lookup then depends on `appLanguage`; the framework probe runs once. Example: add `private lazy var cachedBiometryType: LABiometryType = { let c = LAContext(); _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil); return c.biometryType }()` and switch on `cachedBiometryType` in both methods. (This is @MainActor-isolated, so the lazy is safe.) The view call sites can stay unchanged.

---

### DA-L36 — Lock screen shows a persistent red error on benign biometric cancel because unlock() never clears lastError and authenticate() stores every LAError including cancellations

- **Low** · UX · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Services/BiometricLockStore.swift:100`

**Current code**
```swift
func unlock(appLanguage: String?) async {
    if await authenticate(
        reason: AppLocalization.string("Unlock your local Wealth Compass data.", appLanguage: appLanguage),
        appLanguage: appLanguage
    ) {
        isUnlocked = true
        lastError = nil
    }
}

// authenticate(...) completion handler:
context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
    Task { @MainActor in
        if let authenticationError {
            self.lastError = authenticationError.localizedDescription
        }
        continuation.resume(returning: success)
    }
}
```

**Problem.** `unlock(appLanguage:)` (BiometricLockStore.swift:100-108) sets `lastError = nil` only on success. `authenticate(reason:appLanguage:)` (lines 123-132) unconditionally stores `authenticationError.localizedDescription` into `lastError` for any non-nil LAError — including benign, non-failure codes like `LAError.userCancel`, `.appCancel`, `.systemCancel`, and `.userFallback`. Both lock screens auto-invoke `unlock()` from `.task` on appear (LockView.swift:67-69; MacPlatformServices.swift:94-96) AND expose a manual Unlock button that calls it again (LockView.swift:39-40; MacPlatformServices.swift:72-73). When the auto-presented biometric prompt is interrupted (user taps the manual button while the first sheet is up, the app is backgrounded, or the sheet is dismissed), the OS resolves the pending evaluation with a cancel error, whose localized string (e.g. "Canceled by system" / "Canceled by user") is stored in `lastError` and rendered in red (`WCColor.destructive`) under the button (LockView.swift:54-60; MacPlatformServices.swift:82-88). Because nothing resets `lastError` on view appear, on `lock()`, or at the start of a retry (grep confirms it is only cleared in the three success paths at lines 64, 76, 106), the scary red text persists across retries until a later successful unlock.

**Impact.** On a normal app launch the auto `.task` unlock and the manual button unlock can overlap; a benign cancel of the auto-presented prompt paints a red "Canceled by system"/"Canceled by user" message on the lock screen that stays there through subsequent attempts, making the security feature look broken or as if authentication failed when nothing actually went wrong. It is cosmetic (no data or security impact, and it clears on the next successful unlock), but it degrades perceived reliability of the very feature meant to inspire confidence.

**Fix.** In `authenticate()` (BiometricLockStore.swift:123-132), inspect the error before storing it: only assign `lastError` for genuine, actionable failures and swallow user/system-driven cancellations and fallbacks. E.g. `if let laErr = authenticationError as? LAError { switch laErr.code { case .userCancel, .appCancel, .systemCancel, .userFallback: self.lastError = nil; default: self.lastError = laErr.localizedDescription } } else if let authenticationError { self.lastError = authenticationError.localizedDescription }`. Additionally, clear `lastError = nil` at the start of every `unlock()` attempt (before calling `authenticate`) so any stale message is cleared on each retry. Optionally de-duplicate the auto-`.task` unlock and the manual button (e.g. an in-flight guard) so the two attempts cannot cancel each other on launch.

---

### DA-L37 — Metadata persist failure commits in-memory state before disk write; if app is killed before the next update, the advance is lost on relaunch

- **Low** · DataLoss · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:417`

**Current code**
```swift
        cached = updated
        // Hand-over-hand: take `writeLock` before releasing `dataLock` so concurrent updates
        // persist in the same order they committed in memory, then release `dataLock` so the
        // disk write happens outside its critical section (WC-M3). A persist failure throws
        // (surfaced by WC-M2 as a transient, non-fatal error); the in-memory value is already
        // committed and the next successful update re-persists it.
        writeLock.lock()
        dataLock.unlock()
        defer { writeLock.unlock() }
        try persist(updated)
        return result
```

**Problem.** In CloudSyncMetadataStore.update (Sources/Shared/Services/CloudKitSyncService.swift:401-428), `cached = updated` (line 417) commits the new metadata in memory BEFORE `try persist(updated)` (line 426). persist() can throw (createDirectory, encode, or the file-protected atomic write when protected data is unavailable / disk full). The throw reaches handleEvent's catch (lines 990-1007), which per WC-M2 treats any non-accountChanged error as non-fatal — it only logs and calls report(error) (line 1005) and leaves the sync engine running on the advanced in-memory `cached`. The store's comment (lines 421-422) relies on "the next successful update re-persists it," which is true within a session but not across a process kill: init (lines 387-394) reloads the stale on-disk file. So if the process terminates before any further successful `update`, the persisted metadata regresses to before the failed write. Concretely, handleSentRecordZoneChanges clears a record's pending (line 1348) after a successful upload; a failed persist here leaves disk still showing that record as pending. Same for engineState writes (line 951) and applied-remote bookkeeping (line 1287-1313).

**Impact.** After a successful upload, handleSentRecordZoneChanges clears the record's pending in memory but the persist fails silently (non-fatal per WC-M2) and the app is killed before any other metadata change. On relaunch the stale file still marks the record pending, so the engine re-enqueues and re-uploads an already-saved record (serverRecordChanged churn) or re-fetches/re-applies a just-applied remote mutation; a stale engineState makes CKSyncEngine re-fetch from an older change token. These recovery paths are idempotent (adopt-server-and-drop for identical uploads; identical re-applies; CKSyncEngine tolerates an older restored state), so the practical harm is redundant sync work and re-processing on next launch rather than finance-data loss — but it is a real memory/disk divergence that the current ordering makes silent.

**Fix.** Make persist-then-commit atomic: in update(), do not assign `cached = updated` before persisting. Instead capture `let previous = cached`, take writeLock / release dataLock as today, then `do { try persist(updated); dataLock.withLock { cached = updated } } catch { dataLock.withLock { cached = previous }; throw error }` — i.e. only advance the in-memory value after the disk write succeeds, and on failure leave `cached` unchanged so a persist failure is a true no-op instead of a silent divergence. (Preserve the hand-over-hand writeLock/dataLock ordering so concurrent updates still serialize; the second dataLock acquisition to commit `cached` after persist is cheap and outside the write.) Apply the same before-commit discipline to reset() (lines 434-445), which currently wipes `cached` before removeItem and can leave memory empty while the file remains if removeItem throws.

---

### DA-L38 — CloudSyncMetadataStore.reset() wipes memory then removes the file without re-persisting an empty one, so a removeItem failure leaves stale metadata on disk to resurrect next launch

- **Low** · ErrorHandling · Shared · confidence: Low
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:444`

**Current code**
```swift
    func reset() throws {
        dataLock.lock()
        cached = CloudSyncMetadata()
        // Same hand-over-hand discipline as `update`: wipe the in-memory value under
        // `dataLock`, then remove the file under `writeLock` (serialized with persists) so a
        // concurrent write can't race the removal, all without holding `dataLock` across I/O.
        writeLock.lock()
        dataLock.unlock()
        defer { writeLock.unlock() }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
```

**Problem.** reset() sets `cached = CloudSyncMetadata()` in memory, then under writeLock only removes the on-disk file; it never writes an empty metadata file. If `fileManager.removeItem(at: url)` throws (the file is persisted with `.completeFileProtectionUnlessOpen` at line 531 and can fail while open, when the device is locked, or on a protection/permission error), the throw propagates but in-memory `cached` is already empty, so memory (empty) and disk (old metadata) disagree. Unlike update() — which re-persists via `try persist(updated)` at line 426 and thus keeps disk == memory — reset() relies purely on "file absent == empty." On the next launch, init() (lines 387-394) decodes the surviving stale file back into `cached`, resurrecting the old accountRecordName, bootstrapCompleted flag, tombstones, and knownLocalHashes.

**Impact.** During a factory reset ("Erase Everything"), FinanceStore.wipeLocalState() (line 842) calls `try? syncMetadataStore.reset()`, which swallows a removeItem failure — the erase reports success even though the metadata file survived on disk. The local finance DB is cleared (line 841) but the stale sync metadata is not. On the next launch the store loads the un-removed file, so it starts with a stale accountRecordName and bootstrapCompleted=true. If the user re-onboards and re-enables sync (possibly against a different iCloud account), the stale account-change protection state and pre-populated tombstones/pending records can drive incorrect re-tombstoning or an unexpected account-changed lockout against the fresh account, instead of starting from a clean bootstrap.

**Fix.** Make reset() guarantee disk reflects the empty in-memory value before returning, rather than depending on a delete succeeding. Simplest robust fix: under writeLock, call `try persist(CloudSyncMetadata())` (which uses an atomic write and always overwrites) instead of removeItem — the resulting file is a valid empty-metadata document that init() decodes back to a clean slate. If you specifically want the file gone, persist the empty value first and then best-effort remove it (ignoring the remove error), so a failed remove still leaves a valid empty file on disk: e.g. `try persist(CloudSyncMetadata()); try? fileManager.removeItem(at: url)`. Either way, do not leave the old file as the sole source of truth after `cached` has been wiped.

---

### DA-L39 — Reconcile after fetched-batch await guards only on pending-revision equality; a both-nil case could overwrite a concurrently-applied tombstone (finding's local-delete trigger is incorrect)

- **Low** · Concurrency · Shared · confidence: Low · ⚠️ UNCERTAIN — confirm at runtime before fixing
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:1306`

**Current code**
```swift
                let expectedRevision = originalMetadata.records[storageKey]?.pending?.revision
                let currentRevision = currentMetadata.records[storageKey]?.pending?.revision
                let mutationWasApplied = !mutationKeys.contains(key) || appliedMutationKeys.contains(key)

                guard currentRevision == expectedRevision, mutationWasApplied else {
                    var currentState = currentMetadata.records[storageKey] ?? CloudSyncRecordState()
                    currentState.systemFields = plannedState.systemFields
                    currentMetadata.records[storageKey] = currentState
                    if currentState.pending != nil {
                        pendingToRequeue.insert(key)
                    }
                    continue
                }

                currentMetadata.records[storageKey] = plannedState
```

**Problem.** In handleFetchedRecordZoneChanges the post-await reconcile (Sources/Shared/Services/CloudKitSyncService.swift:1287-1312) captures a per-key plannedState before the `await remoteMutationHandler(mutations)` suspension (line 1284) and, when currentRevision == expectedRevision (line 1296, both may be nil), assigns the stale plannedState wholesale (line 1306) and restores knownLocalHashes from the stale plan (1307-1311). The guard only compares pending revisions; it does not compare isTombstone/deletedAt against originalMetadata. The finding's SPECIFIC scenario — a local delete completing and leaving pending==nil during the await — does not occur: recordLocalChanges (line 508) records a local delete as pending = .delete(revision: UUID()) with a NON-nil revision, and handleSentRecordZoneChanges clears pending to nil only for records that already had a pending delete; in both cases currentRevision becomes non-nil and the guard correctly rejects the stale plan. The only genuine both-nil path is two overlapping fetched batches for the same record in opposite delete states (batch A plans .remote for X while a reentrant batch B applies X's remote tombstone via lines 1183-1186). That path is real in principle because handleEvent (line 944) is a reentrant actor method with no in-flight guard, and applyRemoteMutations re-checks only pendingRevision (FinanceStore line 1147-1148), so nil==nil still lets the payload re-apply.

**Impact.** If CKSyncEngine ever delivers two overlapping fetchedRecordZoneChanges events for the same record with opposite delete states within one fetch cycle, the earlier-planned .remote state (isTombstone=false, remoteHash) can overwrite a tombstone that a reentrant batch just applied, re-inserting the record's hash tracking in sync metadata and — via applyRemoteMutations' nil==nil pending-revision match — potentially re-applying the record's payload to local finance data, undoing the remote deletion on this device. However, the finding's asserted trigger (a concurrent local delete) cannot cause this, and the viable trigger depends on unverified same-record concurrent event delivery from CKSyncEngine; if the engine coalesces per record and delivers events serially, the defect never manifests.

**Fix.** Strengthen the reconcile guard at Sources/Shared/Services/CloudKitSyncService.swift:1296 to also require the tombstone/deletedAt state to be unchanged since the plan was built: compute `originalTombstone = originalMetadata.records[storageKey]?.isTombstone` and `currentTombstone = currentMetadata.records[storageKey]?.isTombstone` (and the same for deletedAt) and add them to the guard so a differing current state falls into the safe branch (1297-1303) instead of blindly writing plannedState. Better still, re-derive the decision from currentMetadata inside the update block rather than assigning the pre-await plannedState: if currentMetadata now shows X as a tombstone (isTombstone=true or a delete pending), do not resurrect it with the remote payload/hash. Note the described local-delete scenario is already safe because a local delete carries a non-nil pending revision the guard catches; the fix targets the concurrent fetched-tombstone interleaving.

---

### DA-L40 — A held currency absent from an otherwise-valid, time-fresh rate snapshot silently converts via its compile-time seed with no staleness signal or forced refresh

- **Low** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/ExchangeRateService.swift:18`

**Current code**
```swift
// ExchangeRateService.swift:11-25
func unitsPerBaseCurrency(for currency: Currency) -> Double? {
    if currency == baseCurrency { return 1 }
    return rates[currency.rawValue]        // nil for any absent currency
}

var isValid: Bool {
    guard baseCurrency == .eur, !rates.isEmpty else { return false }
    return rates.values.allSatisfy { $0.isFinite && $0 > 0 }   // no completeness check
}

// CurrencyConverter.swift:19-21
func unitsPerEuro(for currency: Currency) -> Double {
    snapshot?.unitsPerBaseCurrency(for: currency) ?? currency.fallbackUnitsPerEuro
}

// AppSettings.swift:227-228 — staleness is purely time-based on fetchedAt
guard let exchangeRateSnapshot else { return true }
return now.timeIntervalSince(exchangeRateSnapshot.fetchedAt) >= staleAfter
```

**Problem.** `ExchangeRateSnapshot.isValid` (ExchangeRateService.swift:18-25) intentionally accepts a partial rate table — it only checks EUR base, non-empty rates, and that all PRESENT rates are finite/>0. `unitsPerBaseCurrency` (line 11-16) returns nil for any currency not in `rates`, and `CurrencyConverter.unitsPerEuro` (CurrencyConverter.swift:19-21) then falls back to `currency.fallbackUnitsPerEuro`, the hardcoded compile-time seed (e.g. TRY = 35 units/EUR at FinanceModels.swift:109). Because `AppSettings.shouldAutoRefreshExchangeRates` gauges staleness purely by `snapshot.fetchedAt` (AppSettings.swift:227-228), a snapshot that omits a currency the user actually holds is treated as fully valid and 'fresh': that holding is converted with the stale seed indefinitely, no re-fetch is triggered to fix it, and there is no per-currency 'using offline rate' indicator in the UI (the 'Offline fallback' Settings text only covers the whole-snapshot-nil case). The partial-table acceptance is a deliberate design choice; the actual gap is the absence of any observability/warning or corrective refresh when an ACTIVELY HELD currency is the one missing.

**Impact.** If the provider ever drops a volatile currency the user holds (e.g. TRY), its amounts are converted with a compile-time seed that can be badly wrong for a fast-drifting currency, and since the snapshot is time-fresh the 12h staleness refresh will not correct it — net worth is silently mis-stated with nothing surfaced to the user. In practice the likelihood is low: the client requests the full ECB table and ECB publishes TRY, so a mainstream held currency being absent is unusual; hence this is a robustness/observability improvement rather than a live correctness bug.

**Fix.** Add per-currency observability without reverting the intentional partial-table acceptance. Concretely: (a) expose a helper such as `CurrencyConverter.isUsingOfflineRate(for:)` (true when `snapshot?.unitsPerBaseCurrency(for:) == nil`) and surface a small 'using offline rate' indicator in the currency picker / dashboard for the display currency and any held currency lacking a live rate; and/or (b) have `shouldAutoRefreshExchangeRates` also return true when the display currency (or a currency present in the user's holdings) is missing from the current snapshot, so a corrective refresh is attempted rather than trusting the time window. At minimum, emit an OSLog warning at the converter boundary when falling back to a seed for a currency the live snapshot omitted, so the condition is diagnosable. Note the seed comment at FinanceModels.swift:74-77 ('used only before the first live ECB snapshot is cached') is now inaccurate and should be corrected to reflect per-currency fallback.

---

### DA-L41 — Exchange-rate failure message splices an English-only clause ('the last cached rates') into a translated frame in 28 locales

- **Low** · Localization · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/ExchangeRateService.swift:67`

**Current code**
```swift
if let errorMessage {
    let activeRates = snapshot == nil
        ? AppLocalization.string("the built-in offline fallback rates", appLanguage: appLanguage)
        : AppLocalization.string("the last cached rates", appLanguage: appLanguage)
    return AppLocalization.string("\(errorMessage)\n\nWealth Compass will continue using \(activeRates).", appLanguage: appLanguage)
}
```

**Problem.** In ExchangeRateService.localizedMessage (Sources/Shared/Services/ExchangeRateService.swift), the failure message is composed by interpolating a pre-localized fragment `activeRates` into a localized frame: `AppLocalization.string("\(errorMessage)\n\nWealth Compass will continue using \(activeRates).", appLanguage:)` (line 67). `activeRates` is one of two separately-localized sub-strings, `the built-in offline fallback rates` (line 65) or `the last cached rates` (line 66). Contrary to the original finding, the composite frame key `%@\n\nWealth Compass will continue using %@.` DOES exist in Localizable.xcstrings and is translated in 35 languages. The real defect is the inverse: the two sub-strings are translated in only 6 languages (ar, de, es, fr, it, zh-Hans). So for the 28 other non-English locales that DO have the frame translated (ca, cs, da, el, es-419, fi, he, hi, hr, hu, id, ja, ko, ms, nb, nl, pl, pt-BR, pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-Hant), the outer sentence renders in the user's language but the embedded clause falls back to English — a half-translated sentence. (The ECB effective-date branch on line 71 is fine: its `%@` argument is a locale-formatted date, not a pre-localized fragment.)

**Impact.** On a non-English in-app language (e.g. Japanese, Portuguese, Russian, Korean), a failed exchange-rate refresh surfaces an alert whose sentence frame is fully translated but with the English clause "the built-in offline fallback rates" or "the last cached rates" spliced into the middle — an obviously half-translated, unprofessional message shown at an already-degraded moment (rate refresh failed). It affects 28 shipped locales.

**Fix.** Restructure so the entire sentence is a single translation unit rather than composing pre-localized fragments. Replace the two `activeRates` sub-string lookups with two distinct full-sentence catalog keys and select between them, e.g. `let msg = snapshot == nil ? AppLocalization.string("\(errorMessage)\n\nWealth Compass will continue using the built-in offline fallback rates.", appLanguage:) : AppLocalization.string("\(errorMessage)\n\nWealth Compass will continue using the last cached rates.", appLanguage:)`. That makes the fallback clause part of the format string (one coherent translation unit) and passes only `errorMessage` as a `%@` argument. Then add/translate those two new full-sentence keys in Localizable.xcstrings for all shipped locales, and remove the now-orphaned `the built-in offline fallback rates` / `the last cached rates` entries. (Optional, related: resolve `errorMessage` with the same appLanguage so both %@ argument and frame share one language — currently errorMessage comes from `error.errorDescription` which uses the system locale.)

---

### DA-L42 — Imported recurring schedule with a date-only endDate on the same day as a timed startDate is dropped (and its final occurrence skipped for notifications)

- **Low** · Correctness · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/FinanceImportService.swift:251`

**Current code**
```swift
        let parsedEndDate = ImportDateParser.parse(endDate)
        let parsedCompletedAt = ImportDateParser.parse(completedAt)
        guard parsedEndDate.map({ $0 >= startDate }) ?? true else { return nil }
```

**Problem.** In FinanceImportService.model() (line 251), the guard `guard parsedEndDate.map({ $0 >= startDate }) ?? true else { return nil }` compares two Dates parsed by ImportDateParser. A date-only endDate string ("2024-06-15") is parsed by `dateOnlyFormatter`, which sets no timeZone and therefore resolves to LOCAL midnight (00:00:00). A timed startDate ("2024-06-15T09:00:00Z") is parsed by the ISO formatter to 09:00 UTC. On a device in UTC or a timezone behind it, local-midnight < 09:00-UTC on the same day, so `endDate >= startDate` is false and the whole schedule is discarded even though the user meant it to run through the end of June 15. The same midnight-vs-timed mismatch makes RecurringNotificationService.sync's filter (line 61) `schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true` exclude a legitimately-final occurrence when that occurrence's time is later in the endDate's calendar day. Scope: this only affects the import path fed by web/external backups that emit a bare 'yyyy-MM-dd' endDate — the Apple app's own exporter always writes timed ISO-8601 dates, so an Apple-to-Apple round-trip never hits it. The in-app editors already avoid this by normalizing endDate to 23:59:59 before storing (Forms.swift:268, MacRecurringTransactionEditor.swift:71).

**Impact.** Importing a web-app (or otherwise externally-generated) backup whose recurring rows carry a date-only endDate that falls on the same calendar day as a timed startDate silently drops those schedules on a device at/behind UTC — a data-fidelity/data-loss bug in the JSON interchange format, with no error surfaced to the user beyond the generic skipped-records count. In the narrower case where the schedule survives, its legitimately-final occurrence can be silently omitted from reminder notifications.

**Fix.** In ImportedRecurringTransaction.model(), when the imported endDate string carries no time component (no 'T'), normalize it to end-of-day before comparing and storing, mirroring the editors. For example, after `let parsedEndDate = ImportDateParser.parse(endDate)`, add a step that, when `endDate?.trimmedForImport?.contains("T") == false`, replaces the parsed value with `Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: parsedEndDate)`. Cleaner still: add an `ImportDateParser.parseEndOfDay(_:)` helper (analogous to `parseDateOnly`) that detects the 'T' presence exactly as `parseDateOnly` already does (line 823) and applies the end-of-day shift for date-only inputs, then use it for endDate. This makes the guard at line 251 compare end-of-day vs startDate on the same-day granularity the editors intend, and stores an endDate that keeps the final occurrence inside RecurringNotificationService's `nextDueDate <= endDate` window.

---

### DA-L43 — Unnecessary force-unwrap of trimmedForImport in parseDateOnly relies on a non-local parse invariant

- **Low** · CodeQuality · Shared · confidence: High
- **Location:** `Sources/Shared/Services/FinanceImportService.swift:823`

**Current code**
```swift
        if rawValue?.trimmedForImport!.contains("T") == true {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .current
            return utc.startOfDay(for: date)
        }
```

**Problem.** In `DateImportParser.parseDateOnly`, line 823 force-unwraps an optional-chained optional: `rawValue?.trimmedForImport!.contains("T")`. `trimmedForImport` returns `String?` (nil for empty/whitespace strings), so `rawValue?.trimmedForImport` is `String?` and the `!` unconditionally force-unwraps it. It does not crash today because control flow only reaches line 823 after `guard let date = parse(rawValue)` succeeds at line 817, and `parse` returns non-nil only when `rawValue?.trimmedForImport` was non-nil (guard at line 801). That safety is an implicit, non-local invariant — nothing at line 823 enforces it locally. Additionally, the trim is recomputed here even though `parse` already computed it.

**Impact.** If the `parse` path is ever broadened so it can return a non-nil Date without requiring `rawValue?.trimmedForImport` to be non-nil (e.g. adding a numeric-epoch-timestamp branch, or accepting a value that bypasses the line-801 guard), this `!` becomes a crash-on-import: a single malformed record traps the entire JSON import. It reads as an unguarded force-unwrap on an optional-chained optional, which is exactly the kind of fragility a reviewer flags. There is no correctness or crash risk in the current code — this is a latent-fragility / readability cleanup only.

**Fix.** Remove the force-unwrap by branching safely. Simplest: `if rawValue?.trimmedForImport?.contains("T") == true { ... }` (replace `!` with `?`) — same behavior, no trap possible. Cleaner still, compute once and reuse: `guard let value = rawValue?.trimmedForImport, let date = parse(value) else { return nil }` after changing `parse` to also accept a pre-trimmed `String` (or add an overload), then `if value.contains("T") { ... }`. Either keeps identical runtime behavior (nil rawValue / empty string already can't reach this line) while eliminating the `!`.

---

### DA-L44 — parseDateOnly resolves offset-bearing ISO datetimes against a hardcoded UTC calendar, shifting near-midnight records to the wrong day

- **Low** · Correctness · Shared · confidence: Low
- **Location:** `Sources/Shared/Services/FinanceImportService.swift:823`

**Current code**
```swift
        if rawValue?.trimmedForImport!.contains("T") == true {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .current
            return utc.startOfDay(for: date)
        }
        return Calendar.current.startOfDay(for: date)
```

**Problem.** In parseDateOnly (Sources/Shared/Services/FinanceImportService.swift:816-829), any value containing "T" has its calendar day taken with a fixed UTC calendar (lines 824-826). The ISO8601 formatters used by parse() (lines 780-790, .withInternetDateTime) accept explicit numeric offsets, so a value such as "2024-03-15T23:30:00-05:00" parses to the instant 2024-03-16T04:30:00Z and collapses to the UTC day Mar 16, whereas the author expressed Mar 15 in their own zone. The code's comment assumes the wire format is always UTC ("Z"), but the importer is intentionally forgiving of other sources, so offset-bearing datetimes reach this path. The day should be derived from the offset the string itself carries, not from a hardcoded UTC. "Z" values and pure "yyyy-MM-dd" values are unaffected, hence Low severity.

**Impact.** An imported transaction timestamped near local midnight with a non-UTC offset (e.g. 23:30 at -05:00) lands on the following UTC calendar day. Since parseDateOnly's result drives the cash-flow day/month bucketing at call sites 166, 302 and 360, that transaction is attributed to the wrong day and, at a month boundary, the wrong month — skewing monthly cash-flow totals. Impact is limited to non-"Z" offset-bearing datetimes from non-web-app sources, so it is a rare, low-severity correctness slip rather than a data-loss bug.

**Fix.** Resolve the calendar day using the offset the string itself carries rather than a hardcoded UTC zone. Concretely, when the value contains "T" and an explicit offset, extract that offset (e.g. via a regex/scan of the trailing "±HH:MM" or "Z") and set the gregorian calendar's timeZone to a TimeZone(secondsFromGMT:) built from it before calling startOfDay; for a "Z"/no-offset value keep UTC. Simpler and robust: bypass the absolute-instant round-trip for date-only extraction by pulling the leading "yyyy-MM-dd" date component directly out of the raw string (e.g. take the substring before "T" and parse it with dateOnlyFormatter), since the intended day is exactly the date portion the author wrote — this sidesteps any zone conversion entirely. If, instead, the design truly guarantees only "Z" input, keep UTC but tighten/validate that assumption in the comment. Prefer the substring-of-date-portion approach as it is the least surprising for all offsets.

---

### DA-L45 — JSONDecoder allocated per decode call instead of reused across MarketDataService response types

- **Low** · Performance · Shared · confidence: Low
- **Location:** `Sources/Shared/Services/MarketDataService.swift:302`

**Current code**
```swift
let quote = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)   // line 302
let payload = try JSONDecoder().decode([String: CoinGeckoSimplePriceResponse].self, from: data)   // line 435
let payload = try JSONDecoder().decode(CoinGeckoSearchResponse.self, from: data)   // line 496
let payload = try JSONDecoder().decode(YahooChartResponse.self, from: data)   // line 686
let payload = try JSONDecoder().decode(YahooSearchResponse.self, from: data)   // line 716
```

**Problem.** Each of the five JSON decode paths in MarketDataService.swift constructs a fresh JSONDecoder(): FinnhubQuoteResponse (line 302), the CoinGecko [String: CoinGeckoSimplePriceResponse] map (line 435), CoinGeckoPriceClient.decodeSearch (line 496), YahooQuoteClient.decodeChart (line 686), and YahooQuoteClient.decodeSearch (line 716). During a large-portfolio refresh these run once per holding (Finnhub/Yahoo) or per 100-coin chunk (CoinGecko). None configures a decoding strategy — every response type instead defines its own CodingKeys or a custom init(from:) — so there is no shared strategy to keep consistent today. This is a micro-allocation and consistency observation, not a correctness bug: the per-call JSONDecoder() init is trivial and is dwarfed by the preceding network round-trip in NetworkRetry.data.

**Impact.** Impact is minimal. The per-call JSONDecoder() allocation is negligible next to the HTTPS round-trip that always precedes it, and because each response type carries its own CodingKeys there is no shared decoding strategy that could silently drift. The only real payoff of consolidating is a single, mirrors-FinanceJSONCoding place to configure decoding if a strategy is ever needed, plus a trivial allocation saving on multi-holding refreshes.

**Fix.** Add one shared, unconfigured decoder and reuse it at all five sites, e.g. a file-private `enum MarketDataJSON { static let decoder = JSONDecoder() }` (or a static let on a shared type), then replace each `try JSONDecoder().decode(...)` at lines 302, 435, 496, 686, and 716 with `try MarketDataJSON.decoder.decode(...)`. An unconfigured JSONDecoder is safe to share across concurrent decode calls as long as its configuration is never mutated after construction. This mirrors FinanceJSONCoding's centralization. Treat as an optional cleanup given the negligible runtime impact.

---

### DA-L46 — CoinGeckoSimplePriceResponse.init decodes each currency key with `try?`, silently dropping type-mismatched values as if the currency were absent (no diagnostic)

- **Low** · ErrorHandling · Shared · confidence: Low
- **Location:** `Sources/Shared/Services/MarketDataService.swift:838`

**Current code**
```swift
        for key in container.allKeys {
            if key.stringValue == "last_updated_at" {
                updatedAt = try? container.decode(TimeInterval.self, forKey: key)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                collected[key.stringValue] = value
            }
        }
```

**Problem.** In the custom decoder for CoinGeckoSimplePriceResponse (Sources/Shared/Services/MarketDataService.swift, init at lines 831-844), each dynamic currency key is decoded with `else if let value = try? container.decode(Double.self, forKey: key)` (line 838) and last_updated_at with `try?` (line 837). The `try?` collapses two distinct cases into one: (a) a key genuinely absent, and (b) a key present but of an unexpected JSON type (e.g. a number returned as a string, or null). Case (b) is swallowed as a DecodingError and the price is dropped from `collected`. The init itself never throws, so if all currency keys for a coin are mis-typed, `prices` comes back empty; priceTable (lines 436-446) then produces an empty `resolved` map and compactMapValues drops the coin entirely (guard at line 443), so the holding is reported as having no quote. There is no logging anywhere in this file, so a genuine provider format change is indistinguishable from a legitimately missing currency and leaves no diagnostic trail.

**Impact.** If CoinGecko ever changes a value's encoding for the /simple/price endpoint (e.g. string-encoded numbers or a null), every affected holding silently fails to price and is reported as 'no price' rather than surfacing a clear, actionable decode error. Because there is no log, a developer investigating a mass pricing outage has no signal that the payload was actually present but mis-typed, versus the currency simply not being returned. This is a low-frequency but low-observability failure mode.

**Fix.** Distinguish 'absent key' from 'present-but-wrong-type'. Options, roughly in order of increasing strictness: (1) Minimal/recommended — when `try? container.decode(Double.self, forKey: key)` returns nil for a non-`last_updated_at` key, do a non-optional `try container.decode(Double.self, forKey: key)` (or catch the error) and log it via a Logger (none exists in this file yet — introduce one, e.g. `Logger(subsystem:category:)`), so a format change is observable while still tolerating the currency being absent from the payload entirely. (2) Stricter — decode with non-optional `try` and let a thrown DecodingError propagate out of priceTable so the caller's catch reports a real error instead of an empty quote; guard only `last_updated_at` for leniency. Keep leniency for last_updated_at (it is legitimately optional). Note: because the key set is dynamic (one per requested vs_currency), you cannot enumerate expected keys statically, so the log-on-mismatch approach is the pragmatic fix.

---

### DA-L47 — NetworkRetry's attempt cap is per-request, so the per-symbol Finnhub investment loop can multiply requests ~3xN during a provider rate-limit event

- **Low** · Performance · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/NetworkRetry.swift:22`

**Current code**
```swift
    static func data(
        for request: URLRequest,
        session: URLSession,
        policy: Policy = .default,
        retryableStatus: @Sendable (Int) -> Bool = { $0 == 429 || (500...599).contains($0) }
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            ...
            if retryableStatus(http.statusCode), attempt < policy.maxAttempts {
                try await backoff(attempt: attempt, policy: policy, retryAfter: Self.retryAfter(from: http))
                continue
            }
```

**Problem.** NetworkRetry.data retries up to policy.maxAttempts (3) with exponential backoff per REQUEST and holds no cross-call state (NetworkRetry.swift:12, 28-45). The investment refresh in FinanceStore.refreshMarketPrices loops over data.investments and issues one Finnhub quote(for:) per symbol (FinanceStore.swift:553-591; each goes through NetworkRetry.data at MarketDataService.swift:299). Because the retry budget is per request, a sustained 429 from Finnhub lets each of N investments independently exhaust up to 3 attempts before validate() surfaces .rateLimited, i.e. up to ~3xN provider requests across one refresh. (Contrary to a broader reading, the CRYPTO path is not affected the same way: CoinGecko is batched into 100-id chunks via priceTable and called once — MarketDataService.swift:371-396, FinanceStore.swift:622.) Existing partial mitigations: the investment loop is serialized with a 0.3s inter-request delay and triples that delay to 3s once .rateLimited surfaces (FinanceStore.swift:552,571,589). There is still no mechanism for one 429 to short-circuit the remaining per-symbol retries, nor a per-provider circuit breaker.

**Impact.** During a Finnhub rate-limit episode, a portfolio with many investments can send up to ~3x as many requests as it has holdings before giving up, deepening the rate-limit window and prolonging user-perceived refresh latency. Because requests are serialized with backoff plus jitter (up to maxDelay 8s each) and the inter-request delay grows to 3s, the total refresh can also stretch to many tens of seconds. Impact is bounded by serialization and the existing 3s cooldown, so this is a latency/efficiency concern rather than a correctness bug.

**Fix.** Introduce a lightweight per-provider cooldown that a surfaced 429 sets and that subsequent per-symbol calls check, so one rate-limit short-circuits the rest of the batch instead of each symbol re-running NetworkRetry's 3 attempts. Concretely: in FinanceStore's investment loop (FinanceStore.swift:553-591), when a .rateLimited is caught, set a boolean/deadline (e.g. finnhubCooldownUntil = Date().addingTimeInterval(cooldown)) and skip remaining Finnhub calls (append to skippedInvestments/failedInvestments) until it elapses, optionally still trying the keyless Yahoo fallback. Alternatively, thread an optional shared circuit-breaker/attempt-budget into NetworkRetry.Policy so a 429 observed on one request suppresses retries on the next within a cooldown window. Keep the change scoped to the Finnhub path; the CoinGecko batch already avoids the fan-out.

---

### DA-L48 — Retry-After parser handles only delta-seconds; HTTP-date form is ignored and falls back to exponential backoff (impact bounded by the 8s maxDelay clamp)

- **Low** · ErrorHandling · Shared · confidence: Medium
- **Location:** `Sources/Shared/Services/NetworkRetry.swift:74`

**Current code**
```swift
    /// Parses the delta-seconds form of a `Retry-After` header (the HTTP-date form is ignored).
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard
            let value = response.value(forHTTPHeaderField: "Retry-After"),
            let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces))
        else {
            return nil
        }
        return seconds
    }
```

**Problem.** retryAfter(from:) at Sources/Shared/Services/NetworkRetry.swift:74-82 returns nil unless the Retry-After header parses as a plain TimeInterval (delta-seconds). RFC 7231 also permits an HTTP-date form (e.g. "Wed, 21 Oct 2026 07:28:00 GMT"); for such a value TimeInterval() yields nil, so the function returns nil and backoff() (line 65-67) uses the exponential path policy.baseDelay * 2^(attempt-1) instead of the server-provided delay. The docstring on line 73 explicitly acknowledges the HTTP-date form is ignored. Note this is a bounded, low-impact gap: backoff() already clamps every Retry-After to policy.maxDelay = 8s (line 64), so even a correctly parsed HTTP-date could at most raise the wait to 8s, and maxAttempts=3 limits the loop to 2 delayed retries before the 429 is returned to the caller. Whether this ever triggers depends on the providers (Frankfurter/Finnhub/CoinGecko), which conventionally emit delta-seconds on 429, so in practice this path may rarely be hit.

**Impact.** If a provider returns 429 with an HTTP-date Retry-After, the client ignores the server's requested time and retries on its exponential schedule (roughly 0.25s-4s after jitter) rather than the clamped 8s it would use for a parsed delta-seconds value. Because backoff() already caps all waits at policy.maxDelay (8s), the practical harm is small — at worst one or two retries fire a few seconds earlier than the server suggested and re-hit the 429, then the loop exhausts its 3 attempts and returns the 429 to the caller. There is no data-loss or correctness risk; it is a minor politeness/robustness gap against RFC 7231-compliant servers that use the date form.

**Fix.** In retryAfter(from:), after the TimeInterval parse fails, also try the HTTP-date form before returning nil: parse the header with a DateFormatter configured for RFC 1123 ("EEE, dd MMM yyyy HH:mm:ss zzz"), locale en_US_POSIX, timeZone GMT, and return max(0, date.timeIntervalSinceNow) when the date is in the future. Keep the existing min(policy.maxDelay, ...) clamp in backoff() (line 64) — that clamp is intentional (see the comment on lines 62-63) and should still bound the honored value to 8s. Given the low impact, an acceptable alternative is to leave the behavior as-is and simply keep the docstring note; if changed, add a unit test for both header forms.

---

### DA-L49 — Notification amount formats in the system locale, ignoring the in-app language override

- **Low** · Localization · iOS+macOS · confidence: High
- **Location:** `Sources/Shared/Services/RecurringNotificationService.swift:73`

**Current code**
```swift
// Read the in-app language once, not once per schedule (WC-L31).
let appLanguage = UserDefaults.standard.string(forKey: "wc_mobile_app_language")
for schedule in upcoming {
    ...
    if showAmounts {
        // `schedule.amount` is Decimal (WC-A1); use the Decimal currency format style.
        let amount = schedule.amount.formatted(
            .currency(code: currencyCode)
        )
        content.body = AppLocalization.string("\(schedule.category): \(amount). ...", appLanguage: appLanguage)
```

**Problem.** In `RecurringNotificationService.sync(...)`, line 67 reads the in-app language override (`wc_mobile_app_language`) and every resolved string (title line 70, bodies lines 76/78) is localized through `AppLocalization.string(..., appLanguage: appLanguage)`, which resolves against the override's `effectiveLocale`. However the currency amount at lines 73-75, `schedule.amount.formatted(.currency(code: currencyCode))`, has no `.locale(...)` modifier. Swift's `Decimal.FormatStyle.Currency` defaults to `Locale.autoupdatingCurrent` (the process/system locale), so the amount's grouping separator, decimal separator, and symbol placement follow the system locale rather than the in-app override, while the surrounding sentence follows the override — an internal inconsistency.

**Impact.** A user who sets the in-app language to Italian on an English-system device gets a notification whose sentence is Italian but whose amount is grouped/separated per en_US (e.g. "1,234.56" instead of "1.234,56", and symbol placement like "$1,234.56" vs "1.234,56 $"). The number reads as unlocalized inside an otherwise localized sentence. It also silently ignores the override that the rest of the method deliberately honors.

**Fix.** Attach the effective locale to the format style, reusing the `appLanguage` already read at line 67: `let amount = schedule.amount.formatted(.currency(code: currencyCode).locale(AppLocalization.effectiveLocale(appLanguage: appLanguage)))`. `AppLocalization.effectiveLocale(appLanguage:)` (Sources/Shared/Services/AppLocalization.swift:5-7) returns `Locale(identifier: appLanguage)` when set and `.current` when nil, so users without an override keep today's behavior. Note the parameter is `currencyCode` (not `code`).

---

### DA-L50 — consecutiveExchangeRateFailures is incremented and persisted uncapped; only the read site clamps it

- **Low** · CodeQuality · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/AppSettings.swift:268`

**Current code**
```swift
            // Increment backoff counter on failure
            consecutiveExchangeRateFailures += 1
            userDefaults.set(consecutiveExchangeRateFailures, forKey: Keys.consecutiveExchangeRateFailures)
```

**Problem.** In AppSettings.refreshExchangeRates, the failure path increments and persists the backoff counter with no upper bound: line 268 `consecutiveExchangeRateFailures += 1` followed by line 269 writing the raw value to UserDefaults. The value is only clamped at its single read site, line 219 `pow(2.0, Double(min(consecutiveExchangeRateFailures, 4)))`. The stored `Int` (declared line 53, `private`) therefore drifts above the [0,4] domain that the backoff math actually uses. This is a latent code-quality smell rather than a live bug: the counter is private with no other consumer, so nothing currently misbehaves, and the exponential backoff caps retry cadence at ~4h so the value grows slowly (not 'thousands in weeks'). Int overflow is not a realistic concern.

**Impact.** No current functional breakage — line 219 already clamps every read. The value is purely internal-only latent risk: if a future consumer (a different backoff formula, telemetry, a UI indicator) reads the raw counter, it would inherit an out-of-domain number. Clamping at the store site keeps the persisted value consistent with the [0,4] range the code actually reasons about, removing that footgun. Note: this does not reduce disk writes — the UserDefaults.set on line 269 still fires on every failure.

**Fix.** Clamp when storing so the persisted value never exceeds the domain used by the backoff. Introduce a named constant, e.g. `private static let maxExchangeRateBackoffExponent = 4`, use it at line 219 (`min(consecutiveExchangeRateFailures, Self.maxExchangeRateBackoffExponent)`), and change lines 268-269 to `consecutiveExchangeRateFailures = min(consecutiveExchangeRateFailures + 1, Self.maxExchangeRateBackoffExponent); userDefaults.set(consecutiveExchangeRateFailures, forKey: Keys.consecutiveExchangeRateFailures)`. This keeps the stored value in-domain. (If reducing redundant disk writes is also desired, guard the `.set` with a check that the value actually changed, but that is a separate optional improvement.)

---

### DA-L51 — Future-dated transaction immediately inflates today's net-worth snapshot because calculateTotals has no date filter while adjustHistoricalSnapshots does

- **Low** · Correctness · Shared · confidence: Low
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:38`

**Current code**
```swift
// AnalyticsEngine.swift:37-43 — no date filter on the liquidity reduce
func calculateTotals() -> FinanceTotals {
    let totalLiquidity = data.transactions.reduce(Decimal(0)) { result, transaction in
        switch transaction.type {
        case .income:  return result + displayAmount(transaction)
        case .expense: return result - displayAmount(transaction)
        }
    }
    ...
}

// FinanceStore.swift:244-247 — adjust keyed off (future) transaction.date, then today's snapshot recomputed
adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: settings.convert(delta, from: currency))
data.transactions.append(transaction)
appendSnapshot(settings: settings)
```

**Problem.** `AnalyticsEngine.calculateTotals()` sums every transaction with no date filtering, so a transaction dated in the future is counted into `totalLiquidity` (and thus today's `netWorth`) the instant it is saved. `addTransaction`/`updateTransaction` never clamp the entered date to today (they only apply `Calendar.startOfDay(for: date)`), and the transaction `DatePicker`s (Forms.swift:104, MacEditorSheet.swift:117) impose no upper `in:` bound, so future dates are user-selectable. The two snapshot code paths then disagree: `adjustHistoricalSnapshots(from: futureDate,...)` applies the liquidity delta only to snapshots on/after the future date (none in the present), deliberately leaving today's snapshot unchanged — but `appendSnapshot` immediately overwrites today's snapshot from `calculateTotals`, which includes the future transaction. Net effect: entering a transaction dated tomorrow instantly changes the value stored for TODAY's net-worth snapshot, even though the retroactive-adjust logic was written to treat that entry as not-yet-effective. The inconsistency also affects deletes/edits of future-dated rows, where the retroactive path and the recompute path move today's number in opposite ways.

**Impact.** A user who post-dates an income/expense (e.g. logging next month's rent or an expected paycheck) sees today's net worth and the current dashboard snapshot immediately shift by an amount that has not yet occurred, contradicting the historical net-worth chart line for the intervening days (which adjustHistoricalSnapshots leaves flat until the future date). This is a silent divergence between the stored history and the "current" total, not a crash, and it self-corrects once the future date arrives and appendSnapshot runs again — hence Low severity — but it produces temporarily wrong current net-worth figures and an internally inconsistent snapshot series.

**Fix.** Make the two paths agree on the meaning of "as of today." Simplest: clamp the effective date used for liquidity math to not exceed today. In `addTransaction`/`updateTransaction`, compute the snapshot-adjust date as `min(transaction.date, Calendar.current.startOfDay(for: Date()))` and pass that to `adjustHistoricalSnapshots`, OR (preferred, single source of truth) add a date filter to `AnalyticsEngine.calculateTotals()` so its liquidity reduce excludes transactions with `date > now` (e.g. `where transaction.date <= calendar.startOfDay(for: now)` — reuse the injectable `now`/`calendar` already on the engine). If you filter in `calculateTotals`, also constrain the transaction `DatePicker`s with an `in: ...Date()` upper bound (Forms.swift:104, MacEditorSheet.swift:117) so users cannot post-date entries whose effect silently vanishes from the current total. Add a unit test that adds a future-dated transaction and asserts today's appended snapshot and calculateTotals both exclude it (or both include it, whichever policy you pick), verifying the retroactive-adjust and recompute paths stay consistent.

---

### DA-L52 — Untracked init-time sync-enable Task can resurrect the CloudKit engine after a factory reset

- **Low** · Concurrency · Shared · confidence: Low
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:200`

**Current code**
```swift
        if isSyncEnabled {
            Task { [weak self] in
                await self?.setICloudSyncEnabled(true, userInitiated: false)
            }
        }
```

**Problem.** FinanceStore.init spawns a fire-and-forget `Task { [weak self] in await self?.setICloudSyncEnabled(true, userInitiated: false) }` (lines 200-202) when the persisted iCloud-sync flag is on, but stores no handle to it. The generation guards inside CloudKitSyncService.start()/stop() protect the common interleaving (a stop() that lands while start() is mid-flight makes start() bail via isCurrent()). They do NOT protect the reverse ordering: if wipeLocalState()'s `cloudSyncService.stop()` (line 838) completes on the actor first and the still-pending init Task's start() runs afterward, start() unconditionally sets syncRequested = true and builds a new engine. start() never consults settings.isICloudSyncEnabled, so resetToDefaults() clearing that flag (AppSettings.swift:186) does not stop it. The FinanceStore side holds no reference to cancel or await this init task during eraseEverything/wipeLocalState.

**Impact.** During a factory reset (Settings → Erase Everything) issued within the first second or two of a cold launch, wipeLocalState() stops the sync service and resets metadata, but the untracked init Task may still be suspended waiting on the CloudKitSyncService actor. When it resumes it calls setICloudSyncEnabled(true) → start(), re-starting the engine after the wipe intended to disable sync. This leaves the CloudKit engine running (re-establishing the zone/subscription) while settings.isICloudSyncEnabled is false — an inconsistent state contrary to the erase intent. Damage is bounded (local data is already empty, and the false flag means it won't restart on the next launch), so this is a correctness/state-consistency defect rather than data loss.

**Fix.** Store the init-time task in a field, e.g. `private var initialSyncEnableTask: Task<Void, Never>?`, assign it in init, cancel it in deinit, and cancel + nil it at the top of wipeLocalState() (before `await cloudSyncService.stop()`). Because the task body is a single `await` that isn't cancellation-checked, also add a defensive re-check inside setICloudSyncEnabled for the non-userInitiated path — e.g. `guard isICloudSyncEnabledResolved else { return }` before calling start() — so a start() that arrives after the flag was cleared is a no-op. Alternatively, have start() itself refuse to run when the resolved enabled flag is false for the automatic (userInitiated == false) path. Cancelling the stored task is the minimal, targeted fix.

---

### DA-L53 — processDueRecurringTransactions does O(occurrences × (transactions + snapshots)) synchronous MainActor work during catch-up, with a per-occurrence linear transaction scan and full snapshot-array rewrite

- **Low** · Performance · Shared · confidence: Medium
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:375`

**Current code**
```swift
while occurrence <= now && processedOccurrences < 1_000 {
    if let endDate = schedule.endDate, occurrence > endDate {
        schedule.isActive = false
        schedulesChanged = true
        break
    }

    let alreadyGenerated = data.transactions.contains { transaction in
        guard
            transaction.recurringTransactionID == schedule.id,
            let generatedDate = transaction.recurringOccurrenceDate
        else {
            return false
        }
        return abs(generatedDate.timeIntervalSince(occurrence)) < 1
    }

    if !alreadyGenerated {
        let occurrenceStartOfDay = calendar.startOfDay(for: occurrence)
        let scheduleCurrency = schedule.currency ?? settings.currency
        let delta: Decimal = schedule.type == .income ? schedule.amount : -schedule.amount
        adjustHistoricalSnapshots(
            from: occurrenceStartOfDay,
            liquidityDelta: settings.convert(delta, from: scheduleCurrency)
        )
        // ... append Transaction ...
    }
    // ... advance occurrence ...
}
```

**Problem.** In FinanceStore.processDueRecurringTransactions the inner catch-up loop (line 375, `while occurrence <= now && processedOccurrences < 1_000`) does, for every generated occurrence: (1) an O(transactions) linear duplicate check via `data.transactions.contains { ... }` (lines 382-390), and (2) a call to adjustHistoricalSnapshots (lines 396-399) that — through SnapshotEngine.adjustingHistoricalSnapshots (SnapshotEngine.swift lines 43-56) — copies the whole snapshots array and rewrites every snapshot on/after the occurrence date, i.e. O(snapshots). The entire loop runs synchronously on the @MainActor FinanceStore across all active schedules. The 60-day catch-up floor (maxCatchUpDays=60) bounds the START of each schedule's loop, so a daily schedule generates ~60 occurrences (the 1_000 cap is only a pathological backstop, NOT the typical count). Realistic total work is therefore O(#schedules × occurrences × (transactions + activity-snapshots)), all on the main thread. Snapshots are not materialized for no-activity days (SnapshotEngine comment lines 12-16), so the snapshot factor is bounded by days-with-activity.

**Impact.** A user with several daily recurring schedules and a large transaction history opens the app after a ~2-month absence. processDueRecurringTransactions is called on the activation path (iOS ContentView line 128, driven by scenePhase/unlock; macOS MacRootView line 191) and blocks the @MainActor: each of ~60 occurrences per daily schedule performs a full-transaction-history linear scan plus a full copy-and-rewrite of the snapshot array before the UI can update. In the common case this is a brief stutter; with many schedules and thousands of transactions it can be a perceptible hang on the first frame after foregrounding. It is a genuine but modest performance hotspot, not a hard freeze.

**Fix.** Reduce the two nested-linear costs before considering off-main-actor work: (1) Before the per-schedule loop, precompute a Set of already-generated (scheduleID, occurrenceDay) keys once by iterating data.transactions a single time — e.g. build `let generated: Set<GeneratedKey> = Set(data.transactions.compactMap { t in t.recurringTransactionID.map { GeneratedKey($0, calendar.startOfDay(for: t.recurringOccurrenceDate ?? t.date)) } })` — and replace the per-occurrence `data.transactions.contains { ... }` (lines 382-390) with an O(1) `generated.contains(...)` lookup (keying on the occurrence start-of-day matches the existing <1s tolerance well enough). (2) Batch the snapshot mutation: instead of calling adjustHistoricalSnapshots once per generated occurrence (lines 396-399), accumulate per-start-of-day liquidity deltas into a dictionary while generating transactions, then apply a single pass over data.snapshots that adds, for each snapshot, the sum of all deltas whose date is on/after that snapshot's date — turning O(occurrences × snapshots) into O(occurrences + snapshots). Keep the final appendSnapshot/save() as-is (already done once, lines 441-446). This preserves behavior while collapsing the hot loop to roughly O(occurrences + transactions + snapshots).

---

### DA-L54 — Market-price auto-refresh throttle (lastMarketPriceRefreshAttemptAt) is in-memory only, so it resets on every launch

- **Low** · CodeQuality · Shared · confidence: High
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:503`

**Current code**
```swift
// FinanceStore.swift:141
private var lastMarketPriceRefreshAttemptAt: Date?

// FinanceStore.swift:486-490 (read)
func shouldAutoRefreshMarketPrices(staleAfter: TimeInterval = 15 * 60, retryAfter: TimeInterval = 5 * 60, now: Date = Date()) -> Bool {
    guard !data.investments.isEmpty || !data.crypto.isEmpty else { return false }
    if let lastMarketPriceRefreshAttemptAt, now.timeIntervalSince(lastMarketPriceRefreshAttemptAt) < retryAfter {
        return false
    }

// FinanceStore.swift:502-503 (write, in-memory only)
    isRefreshingMarketPrices = true
    lastMarketPriceRefreshAttemptAt = Date()
```

**Problem.** `FinanceStore.lastMarketPriceRefreshAttemptAt` (declared as a bare `private var` at FinanceStore.swift:141) is set purely in memory at line 503 in `refreshMarketPrices`, and `shouldAutoRefreshMarketPrices` reads it at line 488 to enforce a flat 5-minute retry-after window. Unlike `AppSettings.refreshExchangeRates`, which persists `lastExchangeRateRefreshAttemptAt` and a consecutive-failure counter to UserDefaults (AppSettings.swift:243, 255, 269) and restores them in init (lines 88-90) with exponential backoff (lines 218-220), the market-price attempt timestamp is never persisted and is lost on relaunch. There is also no failure-backoff counter for market refreshes — only a flat `retryAfter`.

**Impact.** The market-price auto-refresh has two gates: the lost attempt-throttle (line 488) and a `staleAfter` gate keyed on holdings' `updatedAt` (line 494). On a *successful* refresh the `updatedAt` bump keeps the staleness gate closed, masking the problem. But on a *failed* refresh — e.g. Finnhub free tier returning 429, or a transient network error — holdings' `updatedAt` is NOT bumped, so the staleness gate offers no protection. If the app is then relaunched (by the user or the OS), the in-memory throttle is gone and `shouldAutoRefreshMarketPrices` immediately returns true, firing another provider hit on every cold start and re-tripping the rate limit. There is no backoff to widen the window after repeated failures.

**Fix.** Persist `lastMarketPriceRefreshAttemptAt` and restore it on init, mirroring AppSettings' exchange-rate retry-state handling. Add a `wc_mobile_last_market_price_refresh_attempt` UserDefaults key (FinanceStore can reach UserDefaults via its `settings` reference, or take a `UserDefaults` in init): write the timestamp alongside the assignment at line 503, and read it back in `init` (after line 141's property is set) so the throttle survives relaunch. Additionally consider a consecutive-failure counter with exponential backoff (as AppSettings does at lines 218-220) so repeated 429s widen the retry window instead of retrying every 5 minutes flat; increment it in the failure path of `refreshMarketPrices` and reset it on success, persisting the counter too.

---

### DA-L55 — exportBackupURL / importBackup do synchronous full-dataset encode/parse + file I/O on the MainActor

- **Low** · Performance · Shared · confidence: Low
- **Location:** `Sources/Shared/Stores/FinanceStore.swift:858`

**Current code**
```swift
    func exportBackupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "wealth-compass-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let payload = try encoder.encode(data)          // encoder = makeEncoder(prettyPrinted: true)
        try payload.write(to: url, options: .atomic)    // synchronous, on @MainActor
        return url
    }
```

**Problem.** FinanceStore is @MainActor. exportBackupURL() (line 858) encodes the entire `data` value with a pretty-printed JSONEncoder (`encoder` is created with makeEncoder(prettyPrinted: true), line 188) and writes it with `payload.write(to:options:.atomic)` synchronously on the MainActor. importBackup() (line 907) does `Data(contentsOf: url)`, FinanceImportService.parse, a merge/sort (`data.merged(with:).sortedForStorage()`), an optional snapshot append, and save() — all synchronous on the MainActor. Both are invoked directly from synchronous SwiftUI button handlers (SettingsView.swift 142/560, MacSettingsView.swift 733/762) with no Task/await off-main hop, so they block the UI thread for the whole encode/parse/write. exportSyncDiagnosticsURL() also writes synchronously but its payload is tiny telemetry text and is not a meaningful concern.

**Impact.** A user with a large finance database taps Prepare Backup or imports a big JSON file. Because the pretty-printed full-dataset encode/write (export) or the read+parse+merge+sort+save (import) runs on the MainActor with no background hop, the UI thread is blocked for the whole operation: spinner/animation freeze on iOS, potential beachball on macOS. Pretty-printing further inflates both CPU time and file size for a file that is only machine-read.

**Fix.** Perform the heavy work off the MainActor and hop back only for @Published/state mutations. For exportBackupURL: capture `data`, then `let payload = try await Task.detached { try encoder.encode(dataCopy) }.value` (or move the encode+atomic write into a nonisolated helper) and make the method async; the write itself can also run off-main. Consider dropping `prettyPrinted: true` for the backup encoder since the file is machine-read — that cuts CPU and size. For importBackup: read the file and run FinanceImportService.parse off the MainActor (nonisolated/detached), then `await` back on the main actor to assign `data`, append the snapshot, and call save(). Keep the @Published mutations (data =, appendSnapshot, save()) on the MainActor. Callers already sit in closures that can be made async (wrap in Task) so the signature change is low-cost.

---

### DA-L56 — chartGeography palette duplicates adjacent oranges and is warm-only, hurting slice/legend distinguishability and colorblind safety

- **Low** · Accessibility · iOS+macOS · confidence: Medium
- **Location:** `Sources/Shared/UI/DesignSystem.swift:48`

**Current code**
```swift
    static let chartGeography: [Color] = [
        WCColor.warning,     // orange  RGB(0.95, 0.64, 0.16)
        .orange,             // ~orange (near-duplicate of the line above)
        WCColor.destructive, // red     RGB(0.95, 0.26, 0.26)
        .pink,
        .red,                // second red (family duplicate)
        .yellow,
        .brown
    ]
    // Consumed by AnalyticsEngine.swift:264 (index % count) -> AllocationSlice.color,
    // which drives both pie wedges (DesignSystem.swift:281) and legend swatches (:368).
```

**Problem.** `ColorPalette.chartGeography` (DesignSystem.swift lines 48-56) is `[WCColor.warning (orange RGB 0.95/0.64/0.16), .orange (system orange), WCColor.destructive (red 0.95/0.26/0.26), .pink, .red, .yellow, .brown]`. Two problems: (1) indices 0 and 1 are two near-identical oranges placed directly next to each other, and since geographies are colored by sorted `index % count` (AnalyticsEngine.swift line 264), the two largest geographies frequently get these two confusable oranges; (2) the entire ramp is warm (orange/orange/red/pink/red/yellow/brown) with no cool anchors, so it compresses heavily under red-green color-vision deficiencies. The color is the only differentiator: AllocationChart draws both the pie wedges (line 281) and the legend swatches (line 368) from `slice.color`, so ambiguous colors make both the chart and its legend hard to read. Note: the reds (`WCColor.destructive` at index 2 and `.red` at index 4) are separated by `.pink` at index 3, not adjacent as originally stated; and wedges do get a 2.5pt angular inset gap (line 279), so slices are physically separated — the defect is hue similarity, not merged shapes. Compare the sibling `chart` and `chartType` palettes, which deliberately span multiple hue families.

**Impact.** A portfolio with several investment geographies renders the two largest regions as two nearly identical orange wedges (and two orange legend swatches), so a user cannot reliably tell which wedge/legend entry maps to which region. For users with protanopia or deuteranopia the whole warm-only ramp collapses toward indistinguishable brown/olive tones, and because the wedges carry no on-chart text labels (only VoiceOver labels), color-blind users lose the ability to read the geography breakdown entirely.

**Fix.** Rework `chartGeography` (DesignSystem.swift line 48) to span distinct, color-blind-safe hue families instead of a warm-only ramp with duplicated oranges. Concretely: remove one of the adjacent oranges (drop `.orange` at index 1 or `WCColor.warning` at index 0) and one of the reds, and substitute cool/distinct hues so consecutive entries differ in hue AND lightness — e.g. borrow the spread strategy from `chartType` ([.blue, .indigo, .cyan, .purple, .mint, .teal]) or use an Okabe-Ito-style set (orange, sky-blue, bluish-green, yellow, blue, vermillion, reddish-purple). Keep exactly one warm accent rather than five. Optionally add a thin contrasting stroke on each SectorMark and/or a leading symbol/pattern in the legend so distinction does not rely on hue alone.

---

### DA-L57 — ScreenBackground runs a perpetual repeatForever animation behind every screen and restarts it on each language-driven root recreation

- **Low** · Performance · iOS+macOS · confidence: Low · flagged by 2 independent lenses
- **Location:** `Sources/Shared/UI/DesignSystem.swift:95`

**Current code**
```swift
    @State private var isAnimating = false
    // ...
                Circle()
                    .fill(WCColor.primary.opacity(0.07))
                    .frame(width: min(proxy.size.width * 0.95, 420))
                    .blur(radius: 80)
                    .offset(x: proxy.size.width * 0.4, y: -proxy.size.height * 0.38)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .rotationEffect(.degrees(isAnimating ? 5 : -5))
    // ...
        .onAppear {
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
```

**Problem.** ScreenBackground (Sources/Shared/UI/DesignSystem.swift:59-101) sits behind nearly every screen — via `pageChrome()` (line 514-533, used by the four iOS data tabs) and ~9 direct `.background(ScreenBackground())`/inline uses across iOS and macOS. Its `.onAppear` (line 95) starts a `repeatForever(autoreverses: true)` animation that drives `.scaleEffect`/`.rotationEffect` on two large blurred circles (`.blur(radius: 80)` at line 80, `.blur(radius: 72)` at line 88). Because `isAnimating` is `@State` (line 60), it resets to `false` whenever the view identity changes; iOS ContentView re-`.id(...)`s the `tabs` root on language change (ContentView.swift:23), which destroys and recreates ScreenBackground, re-running `.onAppear` and re-rasterizing the two Gaussian blurs. Note the animation itself is cheaper than the finding implies: `.blur` is applied to a static Circle and the animated transforms are chained after it (lines 80-83, 88-91), so SwiftUI blurs a fixed shape once and animates affine transforms over the cached result rather than re-blurring every frame. The real costs are the never-pausing animation (it does not stop when the tab is off-screen, when the app is backgrounded via scenePhase, or otherwise) and a fresh blur rasterization on every language-driven root recreation.

**Impact.** A repeatForever animation that never pauses keeps SwiftUI's render loop alive behind every screen; on lower-end iPhones a continuously-animating full-screen decorative layer is a measurable, avoidable battery/GPU cost that is paid whether or not the user is looking at motion. Each in-app language switch additionally forces a full re-rasterization of the two large-radius blurs app-wide. The impact is modest (the per-frame work is transform compositing, not re-blurring), which is why this is Low severity rather than higher.

**Fix.** Pause the animation when it isn't visible: gate `isAnimating` on `@Environment(\.scenePhase)` (stop on `.background`/`.inactive`, restart on `.active`) and/or reset it in `.onDisappear`, so off-screen tabs and the backgrounded app don't keep the render loop running. Since the animated transforms already sit after `.blur` on a static shape, keep that structure (do not move the blur inside the animated closure). Optionally reduce cost further by using a single blurred layer or a smaller blur radius. The language-driven recreation is intentional (root `.id(...)` on language change is a documented design decision) and cannot be removed, but pausing off-screen limits how often the perpetual animation is actually running.

---

### DA-L58 — AllocationChart recomputes total and reallocates value arrays on every hover tick, re-rendering the full card including the legend

- **Low** · Performance · iOS+macOS · confidence: Low
- **Location:** `Sources/Shared/UI/DesignSystem.swift:263`

**Current code**
```swift
@State private var hoveredSlice: AllocationSlice?

var body: some View {
    FinanceCard {
        VStack(alignment: .leading, spacing: 18) {
            ...
                let total = slices.reduce(0) { $0 + $1.value }   // line 273 — recomputed every hover tick
                ...
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: slices.map(\.value))  // line 358 — allocates [Double] every pass
...
private func slice(at location: CGPoint, in rect: CGRect, total: Double) -> AllocationSlice? {
    PieSliceHitTester.sliceIndex(at: location, in: rect, values: slices.map(\.value), innerRadiusRatio: 0.72)  // line 393 — allocates [Double] per sample
        .map { slices[$0] }
}
```

**Problem.** In `AllocationChart` (Sources/Shared/UI/DesignSystem.swift), `hoveredSlice` is `@State` on the whole view (line 263). Continuous hover on macOS (`onContinuousHover`, line 328) and the iOS `DragGesture(minimumDistance: 0)` (line 342) mutate `hoveredSlice` on every pointer sample, which re-evaluates the entire `body`. Each pass re-derives `let total = slices.reduce(...)` (line 273), rebuilds the `Chart`, re-renders the legend `ForEach(slices)` (line 365), and re-runs `.animation(..., value: slices.map(\.value))` (line 358) which allocates a fresh `[Double]` so SwiftUI can diff it. The hit-test `slice(at:in:total:)` allocates yet another `[Double]` via `slices.map(\.value)` on every sample (line 393). None of `total`, the value array, or the legend actually changes during a hover — only the center overlay text and per-slice opacity do. Note the recomputed arrays are small (a handful of slices), so absolute cost is low; each chart's `@State` is independent, so a hover only invalidates that one card, not the sibling charts.

**Impact.** Every hover/drag sample over a donut re-runs the full card body — recomputing `total`, reallocating two `[Double]` arrays, and re-rendering the legend rows — even though only the center overlay and slice opacities change during a hover. With small slice counts the wasted work is minor, but it is pure churn on a hot path (continuous pointer motion) and needlessly ties the legend's identity to hover state. On MacInvestmentsView three such cards are onscreen (each independent), so hovering across them repeatedly triggers these redundant recomputations.

**Fix.** Decouple hover-driven visuals from the stable per-`slices` data. (1) Precompute the values array and total once per `slices` change instead of per body pass — e.g. store `private var values: [Double] { slices.map(\.value) }` used by both `.animation(value:)` and the hit-tester, or better, cache them so `.animation(value:)` compares a stable identity (using `slices.count` or a cheap hash is not correct if values change, so cache-invalidate on `slices`). Pass the precomputed `values` into `PieSliceHitTester.sliceIndex` from `slice(at:)` instead of re-mapping each sample. (2) Move the hover-dependent center overlay into its own small subview that takes `hoveredSlice` as a parameter, and keep `hoveredSlice` state as local as possible so the legend `ForEach` (which never depends on hover) is not re-diffed on every tick — e.g. factor the legend into a separate subview whose inputs (`slices`, `total`, `settings`) don't change during a hover. `total` itself is cheap but should be hoisted alongside the values so it isn't tangled with hover-triggered passes.

---

### DA-L59 — AllocationChart legend re-announces slice data as fragmented, duplicate VoiceOver elements

- **Low** · Accessibility · iOS+macOS · confidence: Medium
- **Location:** `Sources/Shared/UI/DesignSystem.swift:366`

**Current code**
```swift
if showLegend {
    VStack(spacing: 12) {
        ForEach(slices) { slice in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(slice.color.gradient)
                    .frame(width: 10, height: 10)
                Text(slice.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WCColor.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(settings.privateCurrency(slice.value))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    Text(settings.isPrivacyMode ? settings.redactionToken : percentage(slice.value, total: total))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(WCColor.textFaint)
                }
            }
        }
    }
}
```

**Problem.** The Chart already exposes each slice to VoiceOver via per-SectorMark `.accessibilityLabel`/`.accessibilityValue` (lines 284-285) under an `.accessibilityElement(children: .contain)` group (line 360). The legend (lines 363-385) then renders the same name, amount, and percentage for every slice as separate `Text` views inside an ungrouped `HStack` (line 366). Because no `.accessibilityElement(children: .combine)` is applied to the legend row (nor `.accessibilityHidden(true)` to the legend as a whole), VoiceOver (a) announces every allocation twice — once from the chart element and once from the legend — and (b) reads each legend row's name, amount, and percentage as three disconnected fragments rather than one coherent statement. (The decorative color swatch, a bare `RoundedRectangle` with no text, is not itself a focusable element, so it does not add an extra unlabeled stop as the original finding claimed.)

**Impact.** A VoiceOver user navigating the allocation chart hears each portfolio slice announced twice — once as a chart element, once again in the legend — and within the legend must swipe through 'Cash', then '€12,340.00', then '38.2%' as three separate items per row instead of a single 'Cash, €12,340.00, 38.2%'. This makes the chart tedious and confusing to navigate, undercutting the accessibility labels the chart itself already provides. It affects both iOS and macOS since AllocationChart is shared UI.

**Fix.** Combine each legend row and hide the redundant swatch. On the row `HStack` at line 366 add `.accessibilityElement(children: .combine)` and a single label, e.g. `.accessibilityLabel(Text("\(slice.name), \(settings.privateCurrency(slice.value)), \(settings.isPrivacyMode ? settings.redactionToken : percentage(slice.value, total: total))"))`, and mark the `RoundedRectangle` swatch `.accessibilityHidden(true)` for clarity. To also eliminate the double announcement, apply `.accessibilityHidden(true)` to the whole legend `VStack` (line 364) since the chart already conveys the same per-slice data; if you keep the legend visible to VoiceOver, at minimum apply the `children: .combine` grouping so each row is one element. Prefer combining over hiding only if the chart's own per-slice elements are ever suppressed.

---

### DA-L60 — MacSelectorIsland divider tint applied via .background does not recolor the divider hairline

- **Low** · Bug · macOS · confidence: Low
- **Location:** `Sources/Shared/UI/DesignSystem.swift:600`

**Current code**
```swift
                if index < cases.count - 1 {
                    Divider()
                        .frame(height: 14)
                        .background(Color.white.opacity(0.2))
                        .padding(.horizontal, 6)
                }
```

**Problem.** In MacSelectorIsland (Sources/Shared/UI/DesignSystem.swift, lines 599-604), the separator between tab buttons is rendered as `Divider().frame(height: 14).background(Color.white.opacity(0.2))`. `.background(...)` layers the color BEHIND the divider, not on the divider's own hairline. On macOS a Divider draws its hairline using the system separator color, so the intended `.white.opacity(0.2)` tint is placed behind the line and has no visible effect — the divider renders in the default system color. (The finding's other claim — that the `matchedGeometryEffect(id: "selector_background")` pill can crash or emit "multiple inserted views" console spam with a single-case tab enum — does not apply to the current code: all four `MacSelectorTab` conformers have 2-3 cases, and the finding itself concedes it is safe for the current tabs. That part is speculative and is not reported here.)

**Impact.** Purely cosmetic. The dividers between the segmented-selector tabs render in the default macOS system separator color instead of the intended subtle `white.opacity(0.2)`, so the control does not match its intended visual design on the dark-only UI. No functional, data, or correctness impact.

**Fix.** Replace `.background(Color.white.opacity(0.2))` on the Divider with `.overlay(Color.white.opacity(0.2))` (Apple's documented way to recolor a Divider hairline). For example:

    if index < cases.count - 1 {
        Divider()
            .frame(height: 14)
            .overlay(Color.white.opacity(0.2))
            .padding(.horizontal, 6)
    }

Do not act on the matchedGeometry concern — no current tab enum has a single case, so there is nothing to guard against; adding a `cases.count > 1` guard would be dead defensive code.

---

### DA-L61 — DynamicMasonryLayout collapses to a zero-width single column when proposed a non-finite/nil width (latent; no current call site triggers it)

- **Low** · Correctness · macOS · confidence: Medium
- **Location:** `Sources/Shared/UI/DynamicMasonryLayout.swift:13`

**Current code**
```swift
let proposed = proposal.width ?? 0
let width = proposed.isFinite ? proposed : 0
let columns = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
```

**Problem.** In `sizeThatFits`, a nil proposed width falls to 0 via `?? 0` and a non-finite (infinite) proposed width is clamped to 0 via `proposed.isFinite ? proposed : 0`. Both cases then yield columns=1, columnWidth=0, measure every subview at width 0, and return `CGSize(width: 0, ...)`. The clamp-to-0 exists deliberately to avoid `Int(.infinity)` trapping (see the WC-L14 comment on lines 10-11), so the tradeoff is crash-avoidance vs. a degenerate zero-width, vertically-stacked, text-wrapped layout. This is a robustness/reuse hazard, not a live defect: all three usages (MacSettingsView generalSettings/dataSettings/syncSettings) live inside a vertical ScrollView that always proposes a finite width, so the degenerate branch is never hit in the current app.

**Impact.** If this layout is ever reused in a parent that proposes an unbounded width — a horizontal ScrollView, an HStack that offers `.infinity`, or under `.fixedSize(horizontal:)` — the masonry reports a 0-width single-column size and each card is measured at width 0, rendering as a zero-width sliver of tall, wrapped text instead of a normal grid. In current code it is fully latent (vertical ScrollView call sites propose finite widths), so there is no user-visible bug today; the value is hardening the reusable Layout against a foreseeable misuse.

**Fix.** When the proposed width is nil or non-finite, fall back to a sensible width instead of 0. Simplest robust option: compute the subviews' ideal widths and use them. E.g. replace lines 12-13 with a fallback such as: `let idealMax = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? minColumnWidth; let width = (proposal.width.map { $0.isFinite ? $0 : nil } ?? nil) ?? max(minColumnWidth, idealMax)`, so a nil/infinite proposal produces one column at `max(minColumnWidth, largest ideal subview width)` rather than width 0. This keeps the existing `Int(...)`-trap protection (width is always finite) while producing a usable single-column layout. No change is needed for the current app since the call sites never propose non-finite widths, but the guard makes the Layout safe to reuse.

---

### DA-L62 — Step text inlines raw .white.opacity(0.74) instead of the WCColor text token (consistency, not a contrast regression)

- **Low** · Accessibility · iOS+macOS · confidence: Medium
- **Location:** `Sources/Shared/UI/MarketDataAPIKeyGuide.swift:109`

**Current code**
```swift
Text(step)
    .font(.caption)
    .foregroundStyle(.white.opacity(0.74))
    .fixedSize(horizontal: false, vertical: true)
```

**Problem.** In MarketDataAPIProviderGuideCard the numbered API-key setup step text at line 109 uses `.foregroundStyle(.white.opacity(0.74))` rather than a `WCColor` text token, even though the adjacent subtitle text in this same file (lines 24 and 90) uses `WCColor.textSecondary`, and DesignSystem.swift lines 10-19 explicitly document that scattered raw `.white.opacity(...)` literals should be replaced by the text-color tokens ("Use these instead of inlining new faint whites"). This one instance was missed. Contrary to the original finding, this is NOT a contrast/accessibility regression: `WCColor.textSecondary` is `Color.white.opacity(0.70)`, so the inlined 0.74 is actually slightly higher opacity / higher contrast than the token — it clears (not falls below) the AA-tuned token. The real (and minor) issue is code consistency and maintainability: a magic opacity literal that drifts from the centralized token system, so a future change to the token would not reach this text.

**Impact.** Practically negligible for users — at 0.74 white the step text is marginally more opaque than the 0.70 `textSecondary` token, so it is not harder to read and is not below AA. The concrete cost is maintainability: this raw literal is exactly the anti-pattern DesignSystem.swift lines 10-19 were introduced to eliminate, so a global adjustment to the secondary text opacity (for a future contrast tune or theme) would silently skip this instruction text, producing a subtle inconsistency inside a single card.

**Fix.** Replace `.foregroundStyle(.white.opacity(0.74))` at line 109 with `.foregroundStyle(WCColor.textSecondary)` to match the adjacent subtitle usages (lines 24, 90) and the token convention documented in DesignSystem.swift lines 10-19. Note this drops the effective opacity from 0.74 to 0.70, which is intentional (aligning to the token) and remains above AA. Do not frame or justify this as an accessibility fix — it is a consistency cleanup.

---

## Appendix — test-coverage gaps (complementary note)

The XCTest suite (hosted by `WealthCompassMobile`, ~101 tests across 8 files *as of the 2026-07-05 audit; since grown to 147 tests across 9 files, adding `BrokerStatementImportServiceTests`*) covers `AnalyticsEngine`, the CloudSync core, `CurrencyConverter`, `FinanceImportService`, `MarketDataService`, `PersistenceCoordinator`, `RecurringScheduleBuilder`, and `SnapshotEngine`. There is **no dedicated test file** for several high-risk units that many findings above touch:

- **`FinanceStore`** — the single mutation hub and the `save()`→sync pipeline (only exercised indirectly via `PersistenceCoordinatorTests`). Add tests for snapshot backfill / `adjustHistoricalSnapshots`, changeset diffing, and per-transaction currency handling.
- **`AppSettings`** — currency conversion guards, 12h staleness + exponential-backoff refresh state machine.
- **`ExchangeRateService`** and **`NetworkRetry`** — retry/backoff caps and error classification.
- **`BiometricLockStore`** — lock/unlock state, biometric fallback, keychain key lifecycle.
- **`RecurringNotificationService`** / notification scheduling (the 9am date-only rule, identifiers, cancellation).

Several High/Medium findings below (lock-bypass, conversion, backfill, sync classification) are exactly the kind of logic that a regression test should pin once fixed.
