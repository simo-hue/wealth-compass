# Wealth Compass (Apple) — iOS & macOS Bug & Improvement Audit (2nd pass)

A fresh, file-by-file review of the **iOS** (`WealthCompassMobile`) and **macOS** (`WealthCompassMac`)
targets plus the shared core, focused on real bugs and unprofessional code. Produced for a follow-up
agent to fix top-down.

**How to use this file:** every item has a stable ID (`WC-H#` / `WC-M#` / `WC-L#`), a severity, a
platform tag (`[iOS]`, `[macOS]`, `[Shared]`), exact `file:line` locations, why it matters, and a
concrete fix. Tick the checkbox when done. Items are ordered by severity, then roughly by blast radius.
Each finding was verified by reading the surrounding code; low-confidence items say so explicitly.

> **IDs here are independent of `CODE_AUDIT.md`.** That earlier audit (`C#/H#/M#/L#/A#/T#`) is a
> *different* document and most of its items are already ticked `[x]`. Do not cross-reference the two
> numbering schemes.

---

## ⚠️ Read first — stale assumptions corrected during this audit

These save you from chasing ghosts. All verified against the current source:

1. **The localhost debug instrumentation is already gone.** `apple/CLAUDE.md` ("Conventions & gotchas")
   still warns about `wcDebugLog(...)`, `// #region agent log`, `http://127.0.0.1:7504`, and
   `I18nDebugLog`. A tree-wide grep finds **none of these in any `.swift` file** — they survive only in
   Markdown docs. (`CODE_AUDIT.md` C1 confirms they were removed 2026-06-22.) → **Action: update
   `apple/CLAUDE.md` and `WealthCompass/TO_IMPROVE.md` #23 so they stop describing removed code.**
2. **The Cloudflare Worker proxy is no longer used.** `apple/CLAUDE.md` says external APIs go through
   `APIConfiguration.proxyBaseURL`. The current `APIConfiguration.swift:11-20` hits Frankfurter,
   Finnhub, and CoinGecko **directly** (keys sent as request headers over HTTPS — handled correctly, no
   key leakage into URLs/logs). The `proxyBaseURL` symbol no longer exists. → **Action: update the docs;
   the `../proxy/` directory can be retired.**
3. **No `wcDebugLog` / `print` / `fatalError` / `try!` / `as!` were found** in the audited Swift sources.
   The codebase is genuinely clean on crash-prone primitives; the findings below are subtler.

---

## Severity index

| ID | Sev | Platform | One-liner |
|----|-----|----------|-----------|
| WC-H1 | High | iOS + macOS | Non-finite money input (`Inf`/`NaN`) is accepted, persisted & synced |
| WC-H2 | High | macOS | `SettingsRow` renders titles verbatim → Settings screen ignores in-app language |
| WC-H3 | High | Shared (sync) | One undecodable remote record tears down the whole CloudKit engine |
| WC-H4 | High | Shared (sync) | `makeRecord` re-encodes the entire dataset per record, on the main actor |
| WC-M1 | Med | Shared | Cash/liquidity total is never currency-converted → mixed-currency net worth |
| WC-M2 | Med | Shared (sync) | Transient disk error during sync is treated as fatal → sync self-disables |
| WC-M3 | Med | Shared (sync) | Metadata store holds an `NSLock` across full-file disk writes |
| WC-M4 | Med | Shared | New `JSONEncoder`/`ISO8601DateFormatter` allocated per call / per date |
| WC-M5 | Med | macOS | Picking a language during onboarding resets it to page 1 & drops entered keys |
| WC-M6 | Med | macOS | iCloud/market/recurring work + alert run while the app is locked |
| WC-M7 | Med | Shared | Keychain save failure swallowed in onboarding → "configured" but no key stored |
| WC-M8 | Med | macOS | Two divergent transaction editors; the global one skips validation |
| WC-M9 | Med | iOS + macOS | Locale-unaware decimal parsing silently yields `0` on grouped input |
| WC-M10 | Med | macOS | Category picker not localized in 2 of 3 editors |
| WC-M11 | Med | macOS | `LocalizedStringKey(runtimeString)` metric-card titles never localize |
| WC-M12 | Med | macOS | Settings exists twice (sidebar destination + Settings scene) |
| WC-M13 | Med | iOS + macOS | Transaction list re-sorted/re-filtered 6–8× per render (uncached) |
| WC-L1…L31 | Low | mixed | Polish, latent traps, minor localization & a11y, dead code (see below) |

---

## HIGH — fix before the next release

### WC-H1 — [iOS + macOS] Non-finite money input (`Inf`/`NaN`) is accepted, persisted and synced
- [ ] **Severity:** High · **Confidence:** HIGH · **Category:** Validation / Money
- **Locations (all the same pattern):**
  - macOS transactions: `Sources/macOS/Views/MacEditorSheet.swift:49-55` and `save()` `:122-142` (no `>0` guard at all)
  - macOS investments: `MacEditorSheet.swift:204-216` (`isSaveDisabled` checks only `parsedQuantity <= 0`; average/current **price never validated**) → `save()` `:295-326`
  - macOS crypto: `MacEditorSheet.swift:369-381`, `:445`
  - macOS Cash Flow editor: `MacCashFlowView.swift:1036-1042`; recurring: `MacRecurringTransactionEditor.swift:62-64`
  - iOS: `Sources/iOS/Views/Forms.swift:68-70` & `guard parsedAmount > 0` `:160`; `:236-238`/`:353`; investment/crypto `:503`,`:543-545`,`:654`,`:685-687` (prices not validated)
- **Problem:** every amount/price/quantity is parsed as `Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0`, then gated by `parsedX <= 0` (or `guard parsedX > 0`). `Double("inf")`, `Double("infinity")`, and overflow such as `Double("1e400")` all produce `+Inf`, for which `+Inf <= 0` is `false` and `+Inf > 0` is `true` — so they pass every guard. Where there is **no** `> 0` guard (the global Mac transaction editor, and all price/quantity-secondary fields), even `NaN` flows through (`NaN <= 0` is `false`).
- **Impact:** A user typing a very long number (or literally `inf`/`nan`) writes a non-finite value into `FinancialData`. It is saved to the local JSON DB **and synced to iCloud**, then flows into `calculateTotals`, allocation slices, and Swift Charts. The repo's own `CLAUDE.md` warns NaN/Inf "propagates into CoreGraphics and logs errors" — here it corrupts net-worth/allocation geometry across every synced device, not just locally.
- **Fix:** Add a finiteness check everywhere money is parsed. Centralize it: `func parseAmount(_ s: String) -> Double? { let v = Double(s.replacingOccurrences(of: ",", with: ".")); guard let v, v.isFinite else { return nil }; return v }`. Then require `parsed*.isFinite && parsed* > 0` in every `isSaveDisabled`, and add an explicit `guard parsedQuantity.isFinite, parsedQuantity > 0 …` in `MacInvestmentEditor.save()`, `MacCryptoEditor.save()`, and `MacTransactionEditor.save()` (the last has no guard today). Validate prices/quantities, not just the primary amount. (See also WC-M9, the locale half of this same parser.)

### WC-H2 — [macOS] `SettingsRow` renders titles/subtitles verbatim → the Settings screen ignores the in-app language
- [ ] **Severity:** High · **Confidence:** HIGH (overload resolution compile-tested) · **Category:** Localization
- **Location:** struct `Sources/macOS/Views/MacSettingsView.swift:49-99`; call sites `:213, :226, :240, :280, :402, :421-433, :456, :472`
- **Problem:** `SettingsRow` declares two non-generic inits — `init(title: LocalizedStringKey, …)` and `init(title: String, …)`. For a **string literal** argument, Swift's overload resolution picks the `String` overload (string literals default to `StringLiteralType == String`). The `String` path stores `titleString` and the body renders `Text(titleString)` (`:78-80`) — the **verbatim, non-localizing** `Text` initializer. So `SettingsRow(title: "Language")`, `"Base Currency"`, `"Privacy Mode"`, `"Source"`, `"Import Behavior"`, `"Sync Data with iCloud"`, `"Status"`, etc. all display in English regardless of `appLanguage`. (Contrast `SettingsSection`, whose `String` init re-wraps via `LocalizedStringKey(title)` at `:29` — so section headers *are* localized; only the rows are broken. Call sites that pass an already-resolved `settings.localized(...)` string, e.g. `:248-249`, are intentionally verbatim and correct.)
- **Impact:** Pervasive — nearly every row label/subtitle across General/Data/iCloud settings tabs stays English when a non-English in-app language is selected, while the rest of the app localizes. This is the single most visible localization defect found.
- **Fix:** Make `SettingsRow` localize the `String` overload the way `SettingsSection` does — `self.titleKey = LocalizedStringKey(title)` — **or** (cleaner) remove the `String` overload entirely and force the two genuinely-pre-localized call sites to pass through an explicit `Text(verbatim:)`/dedicated parameter. Same fix for `subtitle`.

### WC-H3 — [Shared/sync] A single undecodable / forward-incompatible remote record tears down the entire sync engine
- [ ] **Severity:** High · **Confidence:** HIGH · **Category:** Error-handling / Sync availability
- **Location:** `Sources/Shared/Services/CloudKitSyncService.swift:266-269` (strict decode + id-mismatch throw) propagating via `applyCloudSyncMutations` → `handleFetchedRecordZoneChanges` `:1108-1110` (the `try await remoteMutationHandler(mutations)` is **not** wrapped) → `handleEvent` catch-all `:859-863` → `stopAfterFatalError` `:1571`
- **Problem:** Applying remote mutations decodes each payload with the *strict* `FinanceJSONCoding.decode`, throwing `CloudSyncError.invalidRecord` on an id mismatch and throwing on any malformed/forward-incompatible payload. That throw is uncaught up to `handleEvent`'s catch-all, which calls `stopAfterFatalError` (sets `syncRequested = false`, disables the engine). The earlier fix for a *payloadless* record (`remoteSnapshot` returning `nil` and being skipped, `:953-961`) does **not** cover the far more likely *undecodable-payload* case — e.g. an older app version fetching a record written by a newer schema.
- **Impact:** One bad or forward-incompatible CloudKit record permanently kills sync on that device; re-enabling re-fetches the same poison record and kills it again. The whole fetched batch is dropped, not just the offender. This is the realistic failure mode the moment two app versions with different schemas coexist on a user's devices.
- **Fix:** Decode each mutation defensively inside `applying`/`applyCloudSyncMutations` and skip-with-log on decode/id-mismatch failure (mirror the `nil`-skip used for missing payloads). At minimum, wrap the `remoteMutationHandler` call so a decode failure quarantines that one record's key instead of routing to `stopAfterFatalError`.

### WC-H4 — [Shared/sync] `makeRecord` re-encodes (and SHA-256s) the entire dataset once per record in every send batch, on the main actor
- [ ] **Severity:** High · **Confidence:** HIGH · **Category:** Performance
- **Location:** `CloudKitSyncService.swift:904-909` (the `.save` case calls `try? await snapshotProvider()[key]`), batch provider `:874-877`; provider wired at `FinanceStore.swift:139-141` as `{ try self.data.cloudSyncRecords() }`
- **Problem:** `nextRecordZoneChangeBatch` builds the batch via a per-record provider closure that calls `makeRecord` once per pending change. For each `.save`, `makeRecord` calls `snapshotProvider()` and then subscripts `[key]`. `snapshotProvider` is `@MainActor` and its body is `data.cloudSyncRecords()`, which **JSON-encodes and SHA-256-hashes every transaction, investment, crypto holding, liability, recurring schedule and snapshot** — then throws all of it away except the one key. So a send batch of *B* records over a dataset of *N* records performs *B × N* encodes, each hopping onto and **blocking the main actor**.
- **Impact:** For a user with thousands of records, one sync send batch performs hundreds of full-dataset encodes on the main thread — seconds to tens of seconds of UI-blocking work, risking visible jank and watchdog termination. This is the most serious *shipping* performance risk found.
- **Fix:** Compute the snapshot dictionary **once** per batch (or per send pass) and pass it into `makeRecord` instead of calling `snapshotProvider()` per record. Better still, cache the encoded `cloudSyncRecords()` keyed by `FinanceStore.dataVersion` so it isn't recomputed when the data hasn't changed. (Compounds with WC-M4.)

---

## MEDIUM — correctness, performance, and professionalism

### WC-M1 — [Shared] Cash/liquidity total is never currency-converted → net worth mixes currencies after a base-currency change
- [ ] **Severity:** Medium · **Confidence:** MEDIUM · **Category:** Money
- **Location:** `Sources/Shared/Services/AnalyticsEngine.swift:31-46`; `Transaction` has no `currency` field (`FinanceModels.swift:220-231`); importer converts liquidity to `settings.currency` at import time (`FinanceImportService.swift:390`); `AppSettings.currency` setter persists the new code with no re-conversion (`AppSettings.swift:11-13`).
- **Problem:** `calculateTotals()` converts investments, crypto and liabilities into the display currency, but `totalLiquidity` is a **raw sum of `transaction.amount`** with no conversion. Transactions are implicitly in whatever currency was active when entered/imported. Switching `AppSettings.currency` re-converts the asset buckets but leaves the cash ledger at its old magnitude.
- **Impact:** A user holding cash entered in EUR who switches display currency to USD sees the "Cash" total keep its EUR number summed into a USD net worth — net worth and the cash allocation slice become silently wrong. Medium confidence because it may be a deliberate "transactions are base-currency-anchored" design — but nothing documents or enforces that.
- **Fix:** Either store a per-transaction currency and convert liquidity like the other buckets, or re-base all transaction amounts when `AppSettings.currency` changes. At absolute minimum, document the constraint and disable/guard currency switching when a cash ledger exists.

### WC-M2 — [Shared/sync] A transient disk-write error during sync is treated as fatal and disables sync
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Error-handling
- **Location:** `CloudKitSyncService.swift:859-863` (catch-all) + `stopAfterFatalError` `:1571-1597`; each event case does `try metadataStore.update { … }` (e.g. `:828-829`, `:848`), and `update`→`persist` writes the whole file (`:443-450`).
- **Problem:** Every `handleEvent` case persists metadata synchronously; a transient throw (disk full, file-protection-while-locked, I/O blip) is caught and routed to `stopAfterFatalError`, which disables sync entirely. No distinction between "engine genuinely broken" and "one disk write hiccuped."
- **Impact:** A momentary storage condition permanently stops sync until the user notices and re-enables. With WC-H3, the engine is far too eager to self-destruct on recoverable conditions.
- **Fix:** Classify errors in the catch (reuse `failureCategory`): only tear down for genuinely fatal cases (account changed, unrecoverable engine state); for transient persistence/network errors, `report(_:)` and let `CKSyncEngine` retry.

### WC-M3 — [Shared/sync] `CloudSyncMetadataStore` holds an `NSLock` across full-file synchronous disk writes
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Performance / Concurrency
- **Location:** `CloudKitSyncService.swift:348-356` (`update`), `:443-450` (`persist`). The same store instance is shared between the `CloudKitSyncService` actor and the off-main `PersistenceCoordinator` (both built from `syncMetadataStore`).
- **Problem:** `update` calls `persist` — `createDirectory` + a full-file atomic JSON write of *all* records and hashes — **while holding the lock**. So (a) the actor's executor thread blocks on disk I/O during every metadata mutation, and (b) a coordinator-side `recordLocalChanges` write can stall the actor's `read()/update()` on the shared lock. A single sync pass issues many `update`s (conflict loops `:1243`, `:1284`, `:1331`, `:1373`), each rewriting the whole file.
- **Impact:** At scale, sync contends with the user-facing save pipeline through a lock held during disk writes, adding latency to both.
- **Fix:** Snapshot the value under the lock, release it, then persist outside the critical section (serialize writes on a dedicated queue/actor). Avoid rewriting the entire file for single-record state transitions.

### WC-M4 — [Shared] Fresh `JSONEncoder`/`JSONDecoder` per call and a new `ISO8601DateFormatter` per date
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Performance
- **Location:** `Sources/Shared/Persistence/FinanceJSONCoding.swift:4-12` (encoder), `:14-30` (decoder), `:48-52` (`format` builds a formatter **per date**), `:54-63` (`parse` builds up to two **per date**)
- **Problem:** Every `encode`/`decode` builds a brand-new coder, and the custom date strategies construct a new `ISO8601DateFormatter` for every date value — formatter creation is notoriously expensive. Because `cloudSyncRecords()` encodes each entity separately, one dataset encode already creates O(entities) coders and O(dates) formatters; WC-H4 multiplies that by batch size.
- **Impact:** Significant avoidable CPU on every save and sync.
- **Fix:** Use `static let` cached encoder/decoder and `static let` ISO8601 formatters (they're thread-safe).

### WC-M5 — [macOS] Choosing a language during onboarding resets it to page 1 and discards entered API keys
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** SwiftUI state
- **Location:** root `.id(settings.appLanguage ?? "system")` at `Sources/macOS/WealthCompassMacApp.swift:26`; onboarding language `Picker` bound to `$settings.appLanguage` at `MacOnboardingView.swift:165`; `@State currentTab` and `@StateObject viewModel` at `MacOnboardingView.swift:5,7`.
- **Problem:** The "Personalize" page's language picker mutates `appLanguage`, which changes the root `.id`, forcing SwiftUI to destroy and recreate the whole `MacRootView` subtree — including `MacOnboardingView`, whose `currentTab` resets to `0` and whose view-model (entered Finnhub/CoinGecko keys) is recreated.
- **Impact:** A user who picks their language on page 2 is bounced back to Welcome and loses any keys they'd typed.
- **Fix:** Don't gate onboarding behind the language-`id` reset — apply `.id()` only to the post-onboarding split view, or drive the onboarding step from a store that survives the re-`id`.

### WC-M6 — [macOS] iCloud/market/recurring work and an info alert run while the app is locked
- [ ] **Severity:** Medium · **Confidence:** MEDIUM · **Category:** Privacy / Error-handling
- **Location:** `Sources/macOS/MacRootView.swift:65-74` (`.task`/scenePhase handlers on the outer `Group`) vs the lock gate `:18-19`; `processRecurringTransactions` `:175-184`. (The two `Timer` `onReceive` handlers *do* guard `appLock.isUnlocked`; these two entry points don't.)
- **Problem:** The lock screen is the `if isLockEnabled && !isUnlocked` branch, but `.task { await handleAppBecameActive() }` and the `scenePhase == .active` handler are attached to the outer container, so they run even while locked. `handleAppBecameActive` triggers iCloud sync, market refresh, and `processRecurringTransactions`, which can set `alert` → the "Recurring Transactions Added (N)" alert can appear over the lock screen before biometric auth.
- **Impact:** Data mutation and an information-bearing alert surface before authentication.
- **Fix:** Guard `handleAppBecameActive()` and the scenePhase-active path on `!appLock.isLockEnabled || appLock.isUnlocked`, consistent with the timers.

### WC-M7 — [Shared] Keychain save failure is swallowed during onboarding → "configured" but nothing stored
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Error-handling
- **Location:** `Sources/Shared/Stores/OnboardingViewModel.swift:49` and `:53` (`try? KeychainCredentialStore.shared.save(...)`; `save` is `throws`, see `MarketDataService.swift:188`)
- **Problem:** After a successful live-quote validation, the key is persisted with `try?`, discarding any Keychain error (e.g. device-locked first-unlock, access-group/entitlement issue). `submit` then returns `true`, onboarding completes, and `validationError` is never set. `hasFinnhubKey`/`hasCoinGeckoKey` are also not updated after a successful save, so the "Configured" badge is stale.
- **Impact:** The user believes market data is configured, but no credential was stored; price refresh silently fails forever until they re-enter the key in Settings.
- **Fix:** Use `try` inside the existing `do/catch` so a Keychain failure flows into `validationError` and returns `false`; set `hasFinnhubKey`/`hasCoinGeckoKey = true` on success.

### WC-M8 — [macOS] Two divergent transaction editors (global Cmd+N vs Cash Flow); the global one skips validation
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Duplication / Validation
- **Location:** `MacEditorSheet.swift:18-158` (`MacTransactionEditor`, add-only, no `>0` guard) vs `MacCashFlowView.swift:990-1129` (`MacCashFlowTransactionEditor`, add+edit, guards).
- **Problem:** Two near-identical editors that have diverged: the global one (Cmd+N / dashboard "Add Transaction") only adds, has no `guard parsedAmount > 0` in `save()`, and localizes the category picker differently. The NaN/Inf hole in WC-H1 is worst here precisely because of the missing guard.
- **Impact:** Inconsistent UX/validation depending on entry point; a maintenance hazard.
- **Fix:** Extract one shared transaction editor parameterized by an optional `Transaction` + a save closure; delete the duplicate.

### WC-M9 — [iOS + macOS] Locale-unaware decimal parsing silently yields `0` (or a wrong value) on grouped input
- [ ] **Severity:** Medium · **Confidence:** MEDIUM · **Category:** Money / Validation
- **Location:** every `Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0`: macOS `MacEditorSheet.swift:49-51,328-330,470-472`, `MacCashFlowView.swift:1037`, `MacRecurringTransactionEditor.swift:63`; iOS `Forms.swift:68-70,236-238,543-545,685-687`.
- **Problem:** Replacing `,`→`.` handles a single decimal comma but breaks on grouping separators: pasted `"1,234.56"` → `"1.234.56"` → `nil` → `0`; a German `"1.234,56"` → `"1.234.56"` → `0`; `"1.000"` (one thousand) → `1.0`. The failure is silent — the only feedback is the Save button disabling. (Typed `.decimalPad` input rarely includes groupings, so this mainly bites pasted/locale input.)
- **Impact:** A user pasting a grouped number sees the amount silently treated as `0`/wrong with no explanation.
- **Fix:** Parse with a locale-aware `NumberFormatter` / `Decimal(string:locale:)` (the inverse of the existing `AmountInputFormatter`), and surface an inline "Enter a valid amount" instead of only disabling Save. Fold the finiteness check from WC-H1 into the same shared parser.

### WC-M10 — [macOS] Category picker not localized in Cash Flow & Recurring editors (inconsistent with the global editor)
- [ ] **Severity:** Medium · **Confidence:** MEDIUM · **Category:** Localization
- **Location:** `MacCashFlowView.swift:1070` (`Text(verbatim: category)`), `MacRecurringTransactionEditor.swift:120` (`Text(category)` → verbatim `String` overload), vs the correct `MacEditorSheet.swift:79` (`Text(LocalizedStringKey($0))`).
- **Problem:** Built-in category names ("Food", "Transport", …) have catalog entries and localize in the global editor but render English in the other two.
- **Fix:** Use `Text(LocalizedStringKey(category))` consistently for built-ins in all three editors (custom categories fall through to verbatim, which is correct).

### WC-M11 — [macOS] `LocalizedStringKey(runtimeString)` summary-card titles never localize
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Localization
- **Location:** `MacInvestmentsView.swift:142-146`, `MacCryptoView.swift:121-125` ("Status • N Sectors/Coins"); `MetricCard.title` is `LocalizedStringKey` (`DesignSystem.swift:175`).
- **Problem:** `LocalizedStringKey("Status • \(privateCount(sectorCount)) Sectors")` builds a Swift `String` first (number already substituted) and wraps it with `LocalizedStringKey(_ value: String)`, producing a key with no format placeholders — the whole runtime string becomes the lookup key, which doesn't exist in the catalog and renders verbatim English. A literal interpolation would have produced a proper `"Status • %lld Sectors"` key.
- **Fix:** Pass an interpolated `LocalizedStringKey` literal directly (not `LocalizedStringKey(aString)`), or build via `settings.localized(...)` and pass through an explicit verbatim path. (Same anti-pattern as WC-L4.)

### WC-M12 — [macOS] Settings exists twice (sidebar destination + Settings scene)
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Duplication / HIG
- **Location:** Settings scene `WealthCompassMacApp.swift:79-87`; sidebar `.settings` case `MacAppModel.swift:9` rendered at `MacRootView.swift:122-123`; the sidebar instance also inherits the detail toolbar's "Refresh Data" button (`MacRootView.swift:35-46`).
- **Problem:** `MacSettingsView` shows both as a sidebar row (Cmd+5, in the split-view detail) and via the standard macOS Settings window (Cmd+,) — two independent instances with separate `@State`, plus an incongruous "Refresh Data" toolbar button on the settings page.
- **Impact:** Non-idiomatic on macOS (HIG expects Settings in the Settings window), duplicated state, stray toolbar button.
- **Fix:** Drop `.settings` from `MacDestination` and rely on the Settings scene (or deliberately keep one location only).

### WC-M13 — [iOS + macOS] Transaction list re-sorted and re-filtered 6–8× per render
- [ ] **Severity:** Medium · **Confidence:** HIGH · **Category:** Performance
- **Location:** iOS `Sources/iOS/Views/CashFlowView.swift:419-432, 462-476`; `finance.transactions` sorts on every access (`FinanceStore.swift:185-190`). Milder on `DashboardView.swift:314-317` (re-evaluates uncached `monthlyCashFlow` 3×) and the Mac dashboards.
- **Problem:** `finance.transactions` is a computed property that sorts the whole array (O(n log n)) on every read, and `filteredTransactions` filters it. Per body render the header + list + hidden-count helpers re-derive these ~6–8× (the sort) and ~5–6× (the filter). Unlike `calculateTotals` (memoized via `cachedTotals`), these aren't cached, and the body re-renders on every state change.
- **Impact:** Avoidable O(n log n) work multiplied per frame → jank with a large history.
- **Fix:** Compute once per render — hoist `let all = finance.transactions`, `let filtered = filteredTransactions`, `let visible = Array(filtered.prefix(limit))` into the list builder and pass them down. Consider memoizing a sorted/filtered view on the store keyed by `dataVersion`.

---

## LOW — polish, latent traps, minor localization / a11y, dead code

### Security / privacy
- [ ] **WC-L2** [Shared] Biometric lock uses `.deviceOwnerAuthenticationWithBiometrics` with fallback suppressed (`BiometricLockStore.swift:92-112`, `localizedFallbackTitle = ""` `:94`). After repeated failures, biometry enters lockout with **no in-app passcode path** — the user can only recover by unlocking the *device*. Use `.deviceOwnerAuthentication` (biometrics + automatic passcode fallback) or handle `LAError.biometryLockout` explicitly. *(Confidence: MEDIUM)*
- [ ] **WC-L3** [Shared] `disableLock()` (`BiometricLockStore.swift:70-75`) turns the lock off with **no auth challenge**, while `enableLock` requires biometrics — asymmetric. Require a successful `authenticate(...)` before disabling. *(Confidence: MEDIUM)*
- [ ] **WC-L26** [iOS] App locks on `.inactive` *and* `.background` (`ContentView.swift:51-57`), so Control Center / Notification Center / incoming calls / the Share-Backup sheet all trigger a re-auth on return (`LockView.swift:67-69`). Show a blur/cover overlay on `.inactive` for snapshot privacy and only `lock()` on `.background`. *(Confidence: MEDIUM; may be intentional)*

### Dates & notifications
- [ ] **WC-L1** [iOS + macOS] Recurring notifications are fully torn down and rescheduled every 30 s while foregrounded: the timer calls `processRecurringTransactions()` which **always** calls `syncRecurringNotifications()` regardless of whether anything changed (iOS `ContentView.swift:61-64,126-145`; macOS `MacRootView.swift:75-78,175-184`; `RecurringNotificationService.swift:45-92` removes+re-adds up to 60 requests). An `.onChange` already covers real edits. Only sync when `insertedCount > 0`. *(Confidence: MEDIUM-HIGH)*
- [ ] **WC-L5** [Shared] Recurring notifications fire at the schedule's clock time (`RecurringNotificationService.swift:81-85` uses `[.year,.month,.day,.hour,.minute]`), which is **00:00** for date-only / imported schedules → midnight pings. Pin to a sensible hour (e.g. 9:00). *(Confidence: MEDIUM)*
- [ ] **WC-L6** [Shared/import] `parseDateOnly` applies `Calendar.current.startOfDay` to a UTC instant (`FinanceImportService.swift:778-797`), so an ISO datetime near midnight UTC lands on the wrong local day → wrong month bucket in cash-flow charts. Parse the `date` field in a fixed (UTC) calendar, or extract Y/M/D from the original string. *(Confidence: MEDIUM; only ISO-datetime inputs shift — pure `yyyy-MM-dd` is stable)*
- [ ] **WC-L31** [Shared] `RecurringNotificationService.sync` hardcodes `"wc_mobile_app_language"` and re-reads it every loop iteration (`:68`) — brittle literal divorced from `AppSettings.Keys`. Read once, source the key from `Keys`. *(Confidence: HIGH)*

### Import & analytics
- [ ] **WC-L7** [Shared/import] `skippedRecords` is tallied *before* `.uniquedByID()` runs (`FinanceImportService.swift:76-96, 866-873`), so records dropped for duplicate UUIDs aren't counted — the post-import "N skipped" summary under-reports. Fold dropped-duplicate counts in after uniquing. *(Confidence: MEDIUM)*
- [ ] **WC-L8** [Shared/import] `decodeImportedStringIfPresent` coerces JSON numbers/bools into strings (`FinanceImportService.swift:805-819`), so a number in a `name`/`description` field becomes `"123.0"` / `"true"`. Restrict numeric→string coercion to id/currency fields. *(Confidence: MEDIUM)*
- [ ] **WC-L9** [Shared/analytics] On a gap > 60 days, `SnapshotEngine` backfills the **oldest** 60 missing days and leaves the most-recent gap empty (`SnapshotEngine.swift:30-54` loops `1...backfillDays` from the last snapshot). Intent is the opposite. Cosmetic today (all backfilled days carry the same value) but the logic is inverted. *(Confidence: HIGH behavior / negligible impact)*
- [ ] **WC-L12** [Shared/analytics] `spendingTimeline` (`AnalyticsEngine.swift:155-164`, wrapped by `FinanceStore.swift:652-653`) is **dead** (no UI consumer) *and* buggy if revived: buckets keyed `"MMM dd"` with no year and `.sorted { $0.name < $1.name }` sort alphabetically, scrambling across month boundaries and colliding same-day-different-year. Delete it, or group/sort by an actual `Date`. *(Confidence: HIGH)*

### Networking
- [ ] **WC-L10** [Shared/net] `NetworkRetry` ignores the `Retry-After` header on HTTP 429 (`NetworkRetry.swift:36-37,59-62`) and uses fixed exponential backoff with no jitter, so a retry can fire before the provider's stated cooldown and waste one of only 3 attempts. Honor `Retry-After` (clamped to `maxDelay`); add jitter. *(Confidence: HIGH)*
- [ ] **WC-L11** [Shared/net] Finnhub/CoinGecko price fetches use `.useProtocolCachePolicy` (`MarketDataService.swift:286,401`) while the rates fetch correctly uses `.reloadRevalidatingCacheData` (`ExchangeRateService.swift:143`) — so an explicit "refresh prices" can be served stale from `URLCache`. Use `.reloadRevalidatingCacheData` for manual refreshes. *(Confidence: LOW — depends on provider `Cache-Control`)*
- [ ] **WC-L30** [Shared/net] **Verify the live Frankfurter payload shape.** The decoder expects a flat `[FrankfurterRateResponse]` (`ExchangeRateService.swift:151-164,198-203`); the classic Frankfurter `/latest` returns an object with a nested `rates` map. If `/v2/rates` differs, decode throws and FX **silently** falls back to offline seed rates forever (systematically wrong conversions). Confirm against a live `https://api.frankfurter.dev/v2/rates?base=EUR` response and add an object/`rates`-map decoder if needed. *(Confidence: LOW — needs a live check; HIGH impact if wrong)*

### Latent traps (currently unreachable, trivially hardened)
- [ ] **WC-L13** [Shared/UI] `abs(hash)` in `CryptoIconView` (`DesignSystem.swift:562`) can trap on `Int.min` (hash accumulates with wrapping `&*`/`&+`). Use `colors[Int(hash.magnitude % UInt(colors.count))]`. *(Confidence: MEDIUM; unreachable for normal tickers)*
- [ ] **WC-L14** [Shared/UI] `DynamicMasonryLayout` (`DynamicMasonryLayout.swift:11`, mirror `:29`) computes `Int((width + spacing) / …)` with `width = proposal.width ?? 0` — handles `nil` but not infinite proposals (`Int(.infinity)` traps). All current call sites are width-bounded, so latent. Clamp `width.isFinite`. *(Confidence: MEDIUM)*

### Dead code & inconsistency
- [ ] **WC-L15** [iOS + macOS + Shared] Dead `total:` parameter in the pie-slice hit-test helper — `slice(at:in:total:)` / `categorySlice(at:in:total:categories:)` never uses `total` (`PieSliceHitTester.sliceIndex` recomputes it): `DesignSystem.swift:392` (+ call sites `:333,:345`), `iOS/Views/CashFlowView.swift:621-624` (+ caller `:202`), `MacDashboardView.swift:828-831`. Remove the parameter and arguments. *(Confidence: HIGH)*
- [ ] **WC-L16** [macOS] Dead state/code from a removed `Table`: `@State selection` only ever set to `nil`, and `selectedTransaction`/`selectedInvestment`/`selectedHolding` computed props never read (`MacCashFlowView.swift:77,850-853`; `MacInvestmentsView.swift:19,284-287`; `MacCryptoView.swift:19,343-346`). Also unused `currentMonthCashFlow` (`MacDashboardView.swift:23-25`) and `MacDestination.localizedTitle` (`MacAppModel.swift:23-31`). Delete or wire up. *(Confidence: HIGH)*
- [ ] **WC-L17** [macOS] Inconsistent minus glyph for signed amounts: U+2212 `−` on the Dashboard (`MacDashboardView.swift:797`) vs ASCII `-` on Cash Flow / cards (`MacCashFlowView.swift:603,771,893`). Centralize signed-amount formatting on `AppSettings`. *(Confidence: HIGH)*
- [ ] **WC-L20** [Shared/UI] `DesignSystem.swift` inlines raw `.white.opacity(...)` literals its own doc comment (`:12-15`) says to replace with tokens — `:305` (`0.6`, exactly `WCColor.textTertiary`), `:235` (`0.64`), `:372` (`0.76`), `:498` (`0.82`). Route through the tokens. *(Confidence: HIGH)*

### Localization (minor)
- [ ] **WC-L4** [iOS] Dashboard "Net Savings" month subtitle uses `LocalizedStringKey(Date().formatted(.dateTime.month(.wide)))` (`DashboardView.swift:317`) — a runtime string becomes the key, so it renders in the *system* locale and ignores `appLanguage`. Resolve the month with the effective locale and pass it as data, not a key. *(Confidence: HIGH)*
- [ ] **WC-L18** [macOS] Plurals built by string concatenation: `settings.localized("\(n) due transaction\(n == 1 ? " was" : "s were") added…")` (`MacRootView.swift:180-183`) bakes English grammar into a `%@` placeholder. Use a `.xcstrings` plural rule or two explicit keys (as `MacSettingsView.swift:721-726` already does). *(Confidence: MEDIUM)*
- [ ] **WC-L19** [macOS] `settings.localized("\(exchangeMessage)\n\n\(marketMessage)")` (`MacRootView.swift:156`, also `MacSettingsView.swift:626`) runs two already-localized strings through a `"%@\n\n%@"` lookup and emits stray leading newlines when one is empty. Concatenate directly: `[a,b].filter{!$0.isEmpty}.joined(separator:"\n\n")`. *(Confidence: MEDIUM)*
- [ ] **WC-L21** [Shared] `TabBarLabelResolver.swift` (GENERATED) falls back to English for many major locales — `.settings` is English for ru/ja/ko/he/nl/pl/uk/zh-Hant (`:168`); `.investments` for ar/nl/sv/pt-BR/pt-PT (`:94`) — so one Latin tab sits among localized ones (e.g. `Панель / Поток / Инвестиции / Крипто / Settings`). **Fix in `scripts/add_tab_bar_localizations.py` and re-run**; do not hand-edit the Swift file. *(Confidence: MEDIUM)*
- [ ] **WC-L23** [Shared] Language picker: `languageName(for:)` resolves via `Locale.current` (system, not `appLanguage`), and `availableLanguages` sorts by raw ISO code, not display name (`AppSettings.swift:96-102`); `.capitalized` is locale-fragile. Build names from a `Locale(identifier: appLanguage)` (or autonyms) and sort by display name. *(Confidence: MEDIUM)*

### Accessibility
- [ ] **WC-L24** [iOS + macOS] Tappable rows use `.onTapGesture` (no `.isButton` trait/exposed action) so the primary "tap to edit" affordance is invisible to VoiceOver/Switch Control/keyboard: iOS `CashFlowView.swift:385-390`, `CryptoView.swift:151-156`, `InvestmentsView.swift:158-162`; macOS cards `MacInvestmentsView.swift:264`, `MacCryptoView.swift:323`, `MacCashFlowView.swift:731-734`. The iOS Cash Flow "+" `Menu` label is also a bare `Image` with no `.accessibilityLabel` (`CashFlowView.swift:58-66`), unlike the Dashboard add button. Wrap rows in `Button`/add `.accessibilityAction`; label the menu. *(Confidence: MEDIUM-HIGH)*

### Misc correctness / quality
- [ ] **WC-L22** [Shared] `resetToDefaults` doc (`AppSettings.swift:145-149`) claims it clears "all `wc_mobile_*` keys" but `wc_mobile_biometric_lock_enabled` (owned by `AppLockStore.swift:8`) survives both `resetToDefaults` and `FinanceStore.wipeLocalState()` (`:713-735`). Decide whether the lock pref *should* survive a factory wipe; fix the code or correct the comment. *(Confidence: MEDIUM)*
- [ ] **WC-L25** [iOS] `ContentView.init()` mutates the global `UITabBar.appearance()` proxy (`ContentView.swift:14-30`); since the App body reads `settings.appLanguage`, any `@Published` change re-runs `init()` and re-applies it. Move to app launch (`didFinishLaunching`) or a one-time flag. *(Confidence: MEDIUM)*
- [ ] **WC-L27** [Shared/persistence] `ExchangeRatePersistence` swallows all encode/write/remove errors via `try?` (`:41-45,49-52,70,75`); a failed `clear()` silently leaves a stale rate cache after a factory reset. Log failures (OSLog); consider a throwing `clear()`. *(Confidence: HIGH)*
- [ ] **WC-L28** [Shared/persistence] `LocalFinancePersistence.load()` performs two non-transactional disk writes (migration backup + migrated DB) as a side effect of a read (`FinancePersistence.swift:45-55,90-99`). Move migration write-back into an explicit startup step; keep `load()` read-only. *(Confidence: MEDIUM)*
- [ ] **WC-L29** [Shared/sync] On `CKError.partialFailure`, `synchronize()` sets `lastSyncAt` (via error-swallowing `try?`) and reports `.upToDate` (`CloudKitSyncService.swift:794-800`), so genuinely-rejected records can surface to the user as "Up to Date." Only report `.upToDate` when all item errors are the known retryable/conflict cases. *(Confidence: MEDIUM)*

---

## Cross-cutting / architectural (bigger efforts — discuss before doing)

- [ ] **WC-A1 — Money is `Double` everywhere.** `Transaction.amount`, `Investment.*`, `CryptoHolding.*`, snapshots, totals — all `Double` (`FinanceModels.swift`). This is the root cause of the WC-H1 NaN/Inf class and of accumulation/rounding error in sums. Consider migrating *stored* money to `Decimal` (Codable-friendly) and converting to `Double` only at the Swift-Charts boundary. Large migration touching persistence, sync payloads, and import — scope carefully; may be acceptable to defer if WC-H1/WC-M9 validation is added.
- [ ] **WC-A2 — iOS ↔ macOS view duplication.** Beyond the editor duplication (WC-M8), Mac duplicates `syncRecurringNotifications()` across three views (`MacRootView.swift:186-192`, `MacCashFlowView.swift:927-933`, `MacSettingsView.swift:789-795`), the cash-flow chart card across two (`MacDashboardView.cashFlowCard` vs `MacCashFlowView.cashFlowTrendCard`), and iOS `InvestmentFormView`/`CryptoFormView` duplicate parse/format/fee/summary logic (`Forms.swift:421-545` vs `552-692`). Also a real inconsistency: `InvestmentFormView` hardcodes a new holding's currency to `.usd` (`Forms.swift:413`) while `CryptoFormView` uses `settings.currency` (`:640-644`). Move shared logic (notification sync onto the service/`FinanceStore`, a `FeeCalculator`, a shared summary component, a shared chart view).
- [ ] **WC-A3 — Documentation drift.** Update `apple/CLAUDE.md` and `WealthCompass/TO_IMPROVE.md` to drop the removed debug instrumentation and the retired proxy (see "Read first"). Retire `../proxy/` if nothing else depends on it.

---

## Appendix — verified NOT bugs (don't waste time re-investigating)

These were checked and are correct as written:
- `LocalizedStringKey("\(count) positions")` and `"\(pct)% performance"` **do** resolve to the catalog keys `%lld positions` / `%@%% performance` (compile-tested) — iOS `DashboardView.swift:289/296/310`, `CryptoView`/`InvestmentsView:61` are fine.
- `settings.localized("…\(x)…")` is correct: the parameter is `String.LocalizationValue`, so interpolations become format placeholders that honor `appLanguage`.
- `AmountInputFormatter.string` round-trips safely (`en_US_POSIX`, no grouping) — pre-filling editors is not affected by WC-M9.
- `calculateTotals` is memoized via `cachedTotals` keyed on data version + currency + rate stamp (`FinanceStore.swift:99-102,598-609`).
- `PieSliceHitTester` angle math is correct (12 o'clock origin, clockwise, `[0,2π)`); empty input and `total == 0` are guarded.
- `CurrencyConverter` / `AppSettings.convert` zero/NaN/Inf guards are intact — **preserve them** (they protect Swift-Charts geometry).
- `MarketDataAPIKeyGuide` `URL(string:)!` force-unwraps are on compile-time-constant valid literals — idiomatic.
- `@StateObject` (owned stores) vs `@EnvironmentObject` (injected) usage is correct throughout; the deferred `@FocusState` writes wrapped in `Task { @MainActor }` are a legitimate workaround.
- No `wcDebugLog` / localhost HTTP logging / `print` / `fatalError` / `try!` / `as!` remain in the audited Swift sources.

---

*Generated 2026-06-26 by a multi-agent review pass (5 subsystem reviewers + manual verification of every High/Medium finding). Confidence levels reflect how strongly each item was verified; `LOW` items warrant a second look before fixing.*
