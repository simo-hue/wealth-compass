# Wealth Compass (Apple) — iOS ↔ macOS Divergence Report

**Produced:** 2026-07-10 · **Basis:** current `main` source (verified line-by-line, not from the older audit docs)
**Purpose:** a focused, implementation-ready catalogue of the places where the **iOS** and **macOS**
targets actually *diverge in behaviour* — so the next iteration can implement the fixes and verify them
on real Xcode. This is a **parity** report, not a general bug audit.

---

## 0. How to read this

- Scope is **iOS `Sources/iOS` vs macOS `Sources/macOS`**. The shared brain (`Sources/Shared`) compiles
  into both targets and therefore *cannot* diverge — it is covered only in §2 (what's aligned).
- Each finding lists the exact `file:line` on **both** platforms, the concrete user impact, the
  **reference platform** (the side whose behaviour should win), and a suggested fix.
- **Every line number was verified against the current source** during this pass. Line numbers drift —
  re-read the cited code before editing.
- **Cross-refs:** where a finding maps to the pre-existing `IOS_MACOS_DEEP_AUDIT.md` (`DA-…`) or the
  completed `IOS_MACOS_BUG_AUDIT.md` (`WC-…`), it is tagged. **Two of those are the headline discovery:**
  `DA-H06` was marked "High tier 100% done" but is **still present**, and `DA-M08` was marked done but
  the fix **missed the editor users actually hit**. See §6.

### Severity key
- **🔴 High** — wrong money shown, silent data rewrite/loss, or a privacy leak.
- **🟠 Medium** — a whole data view / affordance exists on one platform only, or a silent failure vs a surfaced one.
- **🟡 Low** — cosmetic, copy, or duplicate-translation-key drift.

### Counts
| Severity | Count |
|---|---|
| 🔴 High | 4 |
| 🟠 Medium | 23 |
| 🟡 Low | 19 |
| **Total** | **46** |

Plus 12 divergences that are **intentional / platform-idiomatic — do NOT fix** (§3).

---

## 1. TL;DR verdict

**The core is aligned; the divergence is entirely in the view + lifecycle layer.** The CloudKit sync
engine (`CloudKitSyncService`, 2 158 lines, **zero** `#if os()`), every `FinanceStore` mutation, the
`save()`→sync pipeline, persistence, and recurring-generation are shared code and run identically on both
platforms. A transaction added on either platform diffs, persists, records its changeset, and notifies
CloudKit through one path. So **iCloud sync cannot silently disagree between the two apps.**

What *does* diverge is how each platform's **UI and lifecycle drive** that shared core:

- **4 genuine correctness/privacy gaps** — the iOS notification privacy leak (SYNC-01), the macOS
  category-picker data-loss on edit (EDIT-01 / `DA-H06`), the macOS dashboard never showing liabilities
  (VIEW-01), and iOS missing two whole allocation charts (VIEW-02).
- **A long tail of "one platform is a superset"** — macOS has selectable chart ranges, extra allocation
  breakdowns, a performance leaderboard, and an inline recurring-validation message; iOS has a Position
  metric grid, a granular refresh counter, and an in-sheet delete. Each is a one-sided feature.
- **String/formatting drift** — the same event worded two ways, precision and date-granularity that differ
  between the two apps, and category names that localize on macOS but not iOS.

---

## 2. What is provably aligned (reassurance — do not re-audit)

Verified identical / shared this pass:

- **CloudKit sync engine** — `Shared/Services/CloudKitSyncService.swift`, no platform branches; same record
  types (`WCTransaction`…), zone (`WealthCompassZone`), container (`iCloud.com.wealthcompasstracker`),
  conflict resolution, tombstones. Both targets even share bundle id `com.wealthcompass.mobile`.
- **Sync orchestration** — `setICloudSyncEnabled` / `ensureICloudSyncRunning` / `requestICloudSync` /
  `syncForRemotePush` / `handleRemoteCloudKitPush` / `forceICloudSync` / `applyRemoteMutations`
  (`FinanceStore.swift:1302-1418`) are shared and called identically from both roots.
- **The save→sync pipeline** — every mutation (`addTransaction`/`updateTransaction`/`deleteTransaction`/
  `upsert*`/recurring ops, `FinanceStore.swift:274-376`) ends in `save()` (`:1272`), which *is* the sync
  trigger. Same code both platforms.
- **Recurring generation** — `processDueRecurringTransactions` (`:385-511`): shared, deterministic, same
  60-day catch-up, same `(schedule, day)` dedup.
- **`handleAppBecameActive` ordering** — identical: guard-unlocked → ensure sync → register push (if on) →
  request sync → process recurring → refresh FX/market (iOS `ContentView.swift:116-129`; macOS
  `MacRootView.swift:156-176`).
- **Timers & scene phase** — both: 30 s recurring timer + 5 h FX timer with identical `scenePhase ==
  .active && appLock.isUnlocked` guards; hard-lock only on `.background`; privacy shield when not active.
  The shield views are identical.
- **Biometric lock** — all `LAContext` logic + M17 enrollment baseline is shared
  (`Shared/Services/BiometricLockStore.swift`); platform subclasses differ only by `defaultsKey`.
- **CloudKit push (`DA-M31`)** — now **fully wired on both** (both `.entitlements` carry `aps-environment`;
  iOS `Info.plist` has the `remote-notification` background mode; both delegates route to
  `handleRemoteCloudKitPush()`). *The roadmap still lists M31 as "deferred" — that is stale.*
- **In-view privacy redaction** — clean; every displayed money value on both platforms routes through
  `privateCurrency` / `privateNumber` / `redactionToken`. (The one gap is notifications — SYNC-01 — which
  lives outside the view layer.)
- **Localization dual-API core usage** — consistent; both use `Text(enum.title)` in pickers and
  `localizedTitle(appLanguage:)` for resolved strings, and inject `.appLanguage(...)` at the right roots.
  Only *copy keys* drift (SYNC-02, VIEW-13, several SET-*).
- **Error surfacing** — symmetric: `PersistenceErrorBanner` and CloudKit-sync error rows wired identically.
- **No `TODO`/`FIXME`/`HACK`** markers in either platform tree.

> ⚠️ **The audit docs lag the code.** `DA-M03` (macOS privacy shield), `DA-H01–H04` (lock/privacy),
> `DA-L15` (Settings in sidebar), and `DA-M31` (push) are all already implemented in current source
> despite how the roadmap reads. This report is driven by the **code**, not those docs.

---

## 3. Intentional divergences — DO NOT "fix"

Confirmed deliberate and platform-correct; changing them would be wrong:

1. **Navigation shell** — iOS 5-tab `TabView`; macOS 4-item `NavigationSplitView` sidebar + Settings as the
   native ⌘, scene. Same 5 sections reachable on both.
2. **Remote-push handler shape** — iOS `didReceiveRemoteNotification … async -> UIBackgroundFetchResult`
   returns `.newData`; macOS fires `Task { … }` (AppKit has no background-fetch result). Same shared sync.
3. **Notification identifier prefixes** — `wealth-compass-recurring-` (iOS) vs `wealth-compass-mac-recurring-`
   (macOS). Per-device local notifications; distinct prefixes are required.
4. **Biometric-lock `UserDefaults` keys** — `wc_mobile_…` vs `wc_mac_…`. Independent per-device lock state.
5. **Editor-dismiss-on-lock** — macOS nils its root-level editor sheet on lock (`MacRootView.swift:99`);
   iOS needs no equivalent because its editor sheets live inside the tab subtree that is torn down under
   the lock screen. Both correct.
6. **UN delegate assignment phase** — `applicationWillFinishLaunching` (macOS) vs
   `didFinishLaunchingWithOptions` (iOS). Both run before any notification can arrive.
7. **Input affordances** — iOS `.keyboardType(.decimalPad)` / `.textInputAutocapitalization`; macOS ⌘S save
   shortcut. AppKit has no keyboardType; UIKit has no key equivalents.
8. **Export flow** — macOS `NSSavePanel` (writes to a chosen path, reports it); iOS `ShareLink`. Platform idiom.
9. **Onboarding shell** — iOS paged `TabView` vs macOS slide-transition `ZStack`; different title sizes /
   content widths / body fonts. Intended sizing.
10. **Onboarding Dynamic-Type cap** — iOS caps at `.accessibility3`; macOS has no Dynamic-Type slider, so no cap.
11. **"on your device" (iOS) vs "on your Mac" (macOS)** copy in onboarding + erase dialogs. Correct per platform.
12. **Bundle id shared, dark-only, iPhone portrait-only** — all deliberate (per `DA` "Do NOT fix" list).

---

## 4. Divergence catalogue (High + Medium — full detail)

### SYNC / LIFECYCLE / NOTIFICATIONS

#### 🔴 SYNC-01 — iOS never rebuilds recurring notifications on Privacy-Mode or currency change (money leaks to the lock screen)
- **iOS:** `iOS/ContentView.swift:74-76` — the *only* re-sync observer is `.onChange(of: finance.data.recurringTransactions)`. No `settings.isPrivacyMode` / `settings.currency` observer.
- **macOS:** `macOS/MacRootView.swift:117-125` — has the `recurringTransactions` observer **plus** `.onChange(of: settings.currency)` and `.onChange(of: settings.isPrivacyMode)`, each calling `syncRecurringNotifications()`.
- **Divergence:** `syncRecurringNotifications()` bakes `showAmounts: !settings.isPrivacyMode` and the converted amount/currency into each scheduled notification body (`Shared/Services/RecurringNotificationService.swift:73-86`). macOS reschedules pending notifications the instant privacy or currency changes; iOS leaves them stale until a schedule edit or the next auto-insertion (the 30 s timer only re-syncs when `insertedCount > 0`, `ContentView.swift:146-147`).
- **Impact:** User enables Privacy Mode on iPhone; a queued "Rent: €1,200.00" reminder **still shows the amount** on the lock screen for up to a month. Currency change shows the old currency for days.
- **Reference:** macOS.
- **Fix:** After `ContentView.swift:76`, add the two macOS observers verbatim.
- **Cross-ref:** not a distinct `DA` item — **new**. (This is finding #1 from both the plumbing and completeness passes.)

---

### EDITORS

#### 🔴 EDIT-01 — macOS Cash-Flow editor's category Picker drops legacy/imported categories → silent rewrite on edit
- **iOS:** `iOS/Views/Forms.swift:118-120` — keeps an out-of-list category selectable: `if category != Self.customCategoryTag && !categories.contains(category) { Text(category).tag(category) }`.
- **macOS:** `macOS/Views/MacCashFlowView.swift:1123-1129` (the inline `MacCashFlowTransactionEditor`) — **this fallback branch is missing**. The guarded version *does* exist in the sibling editors (`MacEditorSheet.swift:95-97`, `MacRecurringTransactionEditor.swift:136-138`).
- **Divergence:** Editing a transaction whose stored category isn't in the current type's list (JSON import is intentionally lossy) leaves the Picker with no matching tag → SwiftUI logs "selection is invalid", shows a blank category, and can coerce `$category` to the first entry on re-render, **silently rewriting the saved category** on save. The user also can't reselect the original.
- **Impact:** Edit an imported "Groceries" transaction (not in defaults) → category blanks → a stray re-render rewrites it to "Food".
- **Reference:** iOS / `MacTransactionEditor`.
- **Fix:** Insert the guarded fallback tag as the first Picker child at `MacCashFlowView.swift:1123`, copying `MacEditorSheet.swift:95-97`.
- **Cross-ref:** **`DA-H06`** — *listed as High-tier "100% done" but omitted from every implementation commit and confirmed STILL PRESENT this pass.* Highest-confidence real bug in this report.

#### 🟠 EDIT-02 — macOS Cash-Flow editor still wipes the in-progress custom category on type toggle
- **iOS:** `iOS/Views/Forms.swift:92-96` — guarded: `if !isCustomCategorySelected { customCategory = ""; … }`.
- **macOS:** `macOS/Views/MacCashFlowView.swift:1104-1110` — the reset at `:1108-1109` is **unconditional** (no `!isCustomCategorySelected` guard). The guarded version exists in `MacEditorSheet.swift:75-80` and `MacRecurringTransactionEditor.swift:115-119`.
- **Impact:** Pick "Custom…", type "Freelance", flip Expense→Income → the typed name blanks (only on this editor).
- **Reference:** iOS / `MacTransactionEditor`.
- **Fix:** Wrap `MacCashFlowView.swift:1108-1109` in `if !isCustomCategorySelected { … }`.
- **Cross-ref:** **`DA-M08`** — *marked done ("all four editors"), but the fix missed the inline Cash-Flow editor — the one users actually hit for edits.* iOS side (`DA-L08`) is correctly fixed.

#### 🟠 EDIT-03 — Editor topology: macOS has 3 transaction editors (one is a drifted fork); iOS has 1
- **iOS:** `iOS/Views/Forms.swift:3-202` — `TransactionFormView` handles add **and** edit+delete.
- **macOS:** `MacTransactionEditor` (`MacEditorSheet.swift:18-189`, add-only, global menu), `MacCashFlowTransactionEditor` (`MacCashFlowView.swift:1036-1190`, add+edit — the drifted fork behind EDIT-01/02/07), `MacRecurringTransactionEditor`.
- **Impact:** Root cause of EDIT-01/02/07 — the most-used macOS edit path is the least-maintained fork.
- **Reference:** iOS (single source of truth).
- **Fix:** Collapse the two macOS one-time editors into one; at minimum port EDIT-01/02/07 into the inline editor.
- **Cross-ref:** `WC-M8` (deferred editor merge), `DA-L18` (duplicated editor bodies).

#### 🟠 EDIT-04 — iOS transaction/recurring category Picker labels are not localized
- **iOS:** `Forms.swift:119,122` (`TransactionFormView`) and `:324,327` (`RecurringTransactionFormView`) — plain `Text(category)`.
- **macOS:** `LocalizedStringKey(category)` in all three editors (`MacEditorSheet.swift:96,99`; `MacRecurringTransactionEditor.swift:137,141`; `MacCashFlowView.swift:1126`).
- **Impact:** Built-in category names ("Food", "Rent"…) render in English on iOS pickers for a user who set a non-English in-app language; localized on macOS.
- **Reference:** macOS.
- **Fix:** `Text(category)` → `Text(LocalizedStringKey(category))` at `Forms.swift:119,122,324,327`. (Custom names fall through verbatim.)
- **Cross-ref:** same class as `WC-M10` (which fixed the macOS side only).

#### 🟠 EDIT-05 — iOS investment Sector/Geography pickers not localized
- **iOS:** `Forms.swift:522,525` — `Text($0)`.
- **macOS:** `MacEditorSheet.swift:282,287` — `Text(LocalizedStringKey($0))`.
- **Impact:** Sector/Geography names ("Technology", "Emerging Markets") English on iOS, localized on macOS.
- **Reference:** macOS. **Fix:** wrap `Forms.swift:522,525` in `LocalizedStringKey($0)`.

#### 🟠 EDIT-06 — New investment defaults to USD on macOS, EUR on iOS
- **iOS:** `Forms.swift:478` — `investment?.currency ?? .eur` (explicit `WC-A2` comment: `.usd` "was an outlier").
- **macOS:** `MacEditorSheet.swift:229` (`MacInvestmentEditor`) — `investment?.currency ?? .usd`. Neither investment editor adopts `settings.currency` in `onAppear`, so this literal stands.
- **Impact:** A euro-based user adding a stock on macOS gets USD pre-selected; if unnoticed, the cost basis is tagged USD and net-worth conversion is wrong.
- **Reference:** iOS (`.eur`, per `WC-A2`).
- **Fix:** `MacEditorSheet.swift:229` → `?? .eur` (consider adopting `settings.currency` in `onAppear` for both investment editors).

#### 🟠 EDIT-07 — macOS Cash-Flow editor uses a static custom-category hint instead of the 3-state hint
- **iOS:** `Forms.swift:61-72` (rendered `:144`) — 3 states: empty prompt / "`X` already exists and will be selected." / "will be added".
- **macOS:** `MacTransactionEditor` has the 3-state hint (`MacEditorSheet.swift:172-188`), but the inline `MacCashFlowTransactionEditor` shows one static string (`MacCashFlowView.swift:1145`).
- **Impact:** On the macOS Cash-Flow editor, typing an existing custom name ("food") gives no "already exists" feedback → user may think they're duplicating.
- **Reference:** iOS / `MacTransactionEditor`. **Fix:** port the `customCategoryHint` property to the inline editor.

#### 🟠 EDIT-08 — iOS recurring editor blocks Save with no explanation; macOS shows an inline validation message
- **iOS:** `Forms.swift:275-283` computes `isSaveDisabled` and disables Save (`:391-393`) but renders no message.
- **macOS:** `MacRecurringTransactionEditor.swift:84-98` computes `validationMessage` (4 cases) and renders a warning `Label` (`:196-202`).
- **Impact:** iOS user sets end-date before start-date → Save greys out with no reason; macOS explains it.
- **Reference:** macOS. **Fix:** port `validationMessage` + its Section into `RecurringTransactionFormView` after `Forms.swift:383`.

---

### DASHBOARD / CRYPTO / INVESTMENTS

#### 🔴 VIEW-01 — macOS dashboard never shows total Liabilities or current-month Net Savings
- **iOS:** `iOS/Views/DashboardView.swift:42` renders `positionSection` (`:288-342`) — a 6-card grid incl. **Liabilities** (`totals.totalLiabilities`, `:323`) and **Net Savings** (`currentMonthCashFlow.netSavings`, `:330-339`).
- **macOS:** `MacDashboardView.swift:31-81` has no metric grid. Investments/Crypto/Cash/Total-Assets appear inside the allocation ring, but **Liabilities total is shown nowhere** (only baked into net worth) and **monthly Net Savings** is reachable only by hovering the current-month cash-flow bar.
- **Impact:** A macOS user with credit-card/loan debt never sees their total liabilities on the dashboard, and can't see this month's savings at a glance — both are one-tap on iPhone.
- **Reference:** iOS. **Fix:** add a metric grid to `MacDashboardView` (after `netWorthHero`, `:41`) with at least Liabilities + Net Savings cards; `totals` already exists at `:19`, add a `currentMonthCashFlow` like iOS `:21-23`.
- **Cross-ref:** **new** (not in the `DA` audit).

#### 🔴 VIEW-02 — iOS Investments shows 1 allocation chart; macOS shows 3 (Type & Geography missing on iPhone)
- **iOS:** `InvestmentsView.swift:21` — single `AllocationChart` (Sector).
- **macOS:** `MacInvestmentsView.swift:43-63` — Sector **+ Type** (`investmentTypeAllocation`) **+ Geography** (`investmentGeographyAllocation`).
- **Divergence:** Both store methods exist and are fully implemented (`AnalyticsEngine.swift:287,:310`) — this is a pure view-layer omission on iOS.
- **Impact:** iPhone users cannot see how their portfolio splits by asset type or geography — two whole diversification views absent.
- **Reference:** macOS. **Fix:** add two more `AllocationChart` instances after `InvestmentsView.swift:21`.
- **Cross-ref:** **new**.

#### 🟠 VIEW-03 — Cash-flow window: iOS fixed 6 months; macOS 3/6/12M picker
- iOS `DashboardView.swift:345` (`months: 6`, title hard-coded `:352`) vs macOS `MacDashboardView.swift:501` (`cashFlowRange.rawValue` + `DashboardSegmentedPicker` `:512`, enum `:1088-1109`). **Reference:** macOS. **Fix:** add `@State cashFlowRange` + picker to iOS; hoist `CashFlowTimeframe` to `Shared/`.

#### 🟠 VIEW-04 — Expense period: iOS fixed 30 days; macOS 7d/30d/3m/YTD/All picker
- iOS `DashboardView.swift:434` (`.thirtyDays`, subtitle `:440`) vs macOS `MacDashboardView.swift:637` (`expensePeriod` + `.menu` picker `:644-650`). **Reference:** macOS. **Fix:** add `@State expensePeriod` + picker to iOS.

#### 🟠 VIEW-05 — Net-worth chart: macOS shows dated X-axis + selected PointMark; iOS hides both
- iOS `DashboardView.swift:252` `.chartXAxis(.hidden)`, RuleMark only (`:199-219`) vs macOS `MacDashboardView.swift:316-323` (`AxisMarks`) + `PointMark` (`:306-312`). **Reference:** macOS (flag the hidden-axis as a possible intentional iPhone trade-off). **Fix:** replace `:252` with `AxisMarks` (fewer ticks) + add a `PointMark`.

#### 🟠 VIEW-06 — Crypto performance leaderboard (Top Performer / Biggest Loser): macOS only
- macOS `MacCryptoView.swift:150-210`; no iOS equivalent (`CryptoView.swift:20-22`). **Reference:** macOS. **Fix:** optional — add a compact best/worst section to `CryptoView` using `max/min by gainLossPercent`.

#### 🟠 VIEW-07 — Crypto/Investments summary: macOS adds Performance + Status(recency + diversification count) cards; iOS folds performance into a subtitle
- iOS 4 cards (`CryptoView.swift:52-63`, `InvestmentsView.swift:52-63`) vs macOS up to 6 (`MacCryptoView.swift:84-125`, `MacInvestmentsView.swift:112-153`, incl. Performance card shown only when not privacy, + Status card with last-update + `uniqueCryptoCount`/`sectorCount`). Also **privacy rule differs**: macOS drops the Performance card in privacy mode; iOS keeps a "Performance hidden" figure. **Reference:** macOS for the extra data; unify the privacy rule. **Fix:** add Status/Performance cards to iOS `summary` grids.

#### 🟠 VIEW-08 — Top Expense categories: macOS shows the per-category %; iOS shows only the bar
- iOS `DashboardView.swift:447-480` (bar only; `%` not rendered as text) vs macOS `MacDashboardView.swift:681-684` (`Text(privatePercent(item.percentage))`). **Reference:** macOS. **Fix:** add a `privatePercent(item.percentage)` `Text` to the iOS row `HStack` (~`:459`); iOS already has `privatePercent` at `:547-551`.

#### 🟠 VIEW-09 — Recent Activity row: macOS shows the transaction description; iOS shows only category + date
- iOS `DashboardView.swift:511-519` (no description) vs macOS `ActivityRow` `MacDashboardView.swift:920-940` (description w/ fallback `:925`, + date). **Impact:** two same-category same-day transactions are indistinguishable in iOS Recent Activity. **Reference:** macOS. **Fix:** add a description line to `DashboardView.swift:511-519`.

#### 🟠 VIEW-10 — Holdings/Positions lists: iOS value-sorted; macOS full tables unsorted (insertion order)
- iOS `CryptoView.swift:75` / `InvestmentsView.swift:75` (`.sorted { $0.currentValue > $1.currentValue }`) vs macOS `MacCryptoView.swift:250` / `MacInvestmentsView.swift:194` (`ForEach(finance.data.*)`, no sort). **Impact:** same portfolio reads in a different order on each device; small holdings can appear above large ones on macOS. **Reference:** iOS. **Fix:** add `.sorted { $0.currentValue > $1.currentValue }` to the two macOS `ForEach`es.

#### 🟠 VIEW-15 — Crypto/investment quantity precision differs between the two apps' list rows
- iOS crypto `CryptoView.swift:116` (6 dp) / investment `InvestmentsView.swift:128` (4 dp) vs macOS crypto `MacCryptoView.swift:296` (8 dp) / investment `MacInvestmentsView.swift:244` (6 dp).
- **Note:** the *editors* do **not** diverge — both seed via the shared `AmountInputFormatter` (`min(max(8,scale),20)`); the divergence is display-only in the list rows. **Reference:** macOS crypto (8 dp = satoshi precision); pick one for investments. **Fix:** centralize `cryptoQuantityDigits`/`investmentQuantityDigits` in `Shared` and use on both.

---

### SETTINGS / ONBOARDING

#### 🟠 SET-01 — iOS has no "Remove Key" for stored market-data credentials
- **macOS:** `MacSettingsView.swift:1023-1026` — destructive "Remove Key" button → `removeMarketDataCredential` (`:683-698`) → `KeychainCredentialStore.shared.delete(...)` (`MarketDataService.swift:237`).
- **iOS:** `SettingsView.swift:763-821` — `MarketDataCredentialEditor` has only cancel/save; no delete path anywhere.
- **Impact:** an iOS user who pasted a wrong/expired/compromised key can only *overwrite* it (validation requires a live quote, so it can't be blanked) — the only way to clear it is "Erase Everything".
- **Reference:** macOS. **Fix:** add `onRemove`/`isConfigured` to the iOS editor + a confirmation dialog + `removeMarketDataCredential`, mirroring `MacSettingsView.swift:980-1055`.
- *(Agent rated High as a security/feature gap; scored Medium here — no data at risk, key is replaceable — but it is a real missing affordance.)*

#### 🟠 SET-02 — iOS JSON import doesn't materialize due recurring transactions, re-sync notifications, or show an import note
- **macOS:** `MacSettingsView.swift:751-766` — after `importBackup`: `processDueRecurringTransactions` (`:752`) + `syncRecurringNotifications` (`:753`) + `importSummaryNote` (`:757-765`, shown via `ImportSummaryView`).
- **iOS:** `SettingsView.swift:580-586` — none of these; summary shown with no note.
- **Impact:** restoring a backup on iOS shows recurring schedules present but their due Cash-Flow transactions missing (and no notifications) until the next foreground/timer pass runs `processDueRecurringTransactions` — a delay + a missing confirmation, not permanent loss.
- **Reference:** macOS. **Fix:** after `SettingsView.swift:582`, call `processDueRecurringTransactions` + `RecurringTransactionNotificationService.shared.sync(...)`, set an `importSummaryNote`, pass it into `ImportSummaryView`.

#### 🟠 SET-03 — iOS silently swallows Keychain read errors on price refresh; macOS surfaces them
- iOS `SettingsView.swift:612-619` (`currentStoredAPIKey` `catch { return "" }` → refresh proceeds keyless, no error) vs macOS `MacSettingsView.swift:700-729` (`storedAPIKey` throws; `refreshMarketPrices` shows "Unable to Refresh Market Data"). **Impact:** an iOS user with a valid key but a transient Keychain error gets stale/keyless prices + a misleading "success". **Reference:** macOS. **Fix:** make the read throw and wrap `refreshMarketPrices` in do/catch with a `SettingsAlertState`.

#### 🟠 SET-04 — macOS cloud-sync status *title* ignores the in-app language override
- macOS `MacSettingsView.swift:503` — `Text(finance.cloudSyncStatus.title)` (LocalizedStringKey, follows environment locale); the adjacent *detail* line uses the resolved API (`:511`), so it is internally inconsistent. iOS `SettingsView.swift:104` uses `localizedTitle(appLanguage:)`. **Impact:** a macOS user with a non-system in-app language can see the status title ("Up to Date") in the system language while its detail renders in the chosen language. **Reference:** iOS. **Fix:** `MacSettingsView.swift:503` → `localizedTitle(appLanguage: settings.appLanguage)`.

#### 🟠 SET-06 — Import "Replace" safety: macOS sticky Picker vs iOS per-import warning
- iOS `SettingsView.swift:256-273` (`.alert` forcing Merge/Replace each import + a warning sentence) vs macOS `MacSettingsView.swift:423-435` (persistent `importMode` Picker, no per-action warning). **Impact:** a macOS user can leave the Picker on "Replace" and later import without a confirmation, risking an unintended local wipe. **Reference:** iOS for the destructive path. **Fix:** gate the macOS "Replace" branch behind a confirmation or surface the iOS warning copy near the Picker.

---

### CROSS-CUTTING / COMPONENT DRIFT

#### 🟠 XCUT-01 — macOS dashboard re-implements the shared `AllocationChart` inline
- iOS dashboard uses the shared `AllocationChart` (`DashboardView.swift:44`); macOS dashboard builds its own donut (`MacDashboardView.swift:362-389`, custom hit-testing `:841`) even though macOS Crypto/Investments use the shared component. **Impact:** latent — any fix to `AllocationChart` (privacy, empty slices, colours, VoiceOver, `DA-M29`/`DA-M30`) reaches every allocation surface **except** the macOS dashboard. **Reference:** iOS. **Fix:** replace the inline chart with `AllocationChart`, or extract a shared pie body.

#### 🟠 XCUT-02 — iOS Cash-Flow transaction list capped at 40; macOS unbounded
- iOS `CashFlowView.swift:40,383,423-424` (cap 40 + "N more … hidden") vs macOS `MacCashFlowView.swift:743` (`ForEach(filteredTransactions)`, no cap). **Impact:** an iOS user with >40 matches cannot reach rows 41+ (no "show more"); the same account scrolls fully on macOS — data appears "missing" on iOS. **Reference:** judgment (iOS cap is likely a perf guard). **Fix:** add a "Show all / Load more" control on iOS, or a matching cap+notice on macOS.

---

## 5. Low-severity / cosmetic drift (compact)

Same-event copy, formatting, colour, and count drift. Each is a small edit; grouped to keep the file navigable.

| ID | Divergence | iOS | macOS | Fix / reference |
|---|---|---|---|---|
| SYNC-02 | Recurring auto-insertion **alert wording** differs (2 key pairs) | `ContentView.swift:148-150` "scheduled … automatically added" | `MacRootView.swift:227-229` "due … added" | Consolidate to one key pair |
| EDIT-09 | In-sheet **Delete** button (edit): iOS yes, macOS inline editor no | `Forms.swift:150-163` | `MacCashFlowView.swift:1158-1169` | Optional — add to macOS inline editor |
| EDIT-10 | Custom-category hint **casing** of the type noun | `Forms.swift:62,349` capitalized | `MacEditorSheet.swift:176` `.lowercased(with:)` | macOS is more correct; apply to iOS |
| EDIT-11 | Editor **titles/labels**: "Add" vs "New", "Coin ID" vs "CoinGecko ID", fee footer | `Forms.swift:165,564,723,762` | `MacEditorSheet.swift:132,324,483,524` | Normalize to one lexicon |
| VIEW-11 | Recent-Activity count | `DashboardView.swift:489` `prefix(5)` | `MacDashboardView.swift:721` `prefix(6)` | Share a `recentActivityCount` const |
| VIEW-12 | Crypto allocation **legend** hidden on macOS | `CryptoView.swift:21` (legend on) | `MacCryptoView.swift:133-138` `showLegend:false` | Design choice (macOS relocates to Top Holdings) |
| VIEW-13 | Freshness **"Just now"/"just now"** key casing | `DashboardView.swift:566` | `MacDashboardView.swift:818` | Unify one key |
| VIEW-14 | Investments **accent** + row chrome | `InvestmentsView.swift:53` `.cyan` + monogram/badge | `MacInvestmentsView.swift:117` `.blue`, plain | Tokenize `WCColor.investmentAccent` (cyan) |
| VIEW-16 | "Last updated"/snapshot/scrub **date granularity** | date-only (`CryptoView.swift:143`, `InvestmentsView.swift:150`, `DashboardView.swift:207,277`) | date **+ time** (`MacCryptoView.swift:365`, `MacInvestmentsView.swift:313`, `MacDashboardView.swift:289,350`) | Standardize in a shared helper |
| SET-05 | Market-refresh label: iOS "Updating X of Y" | `SettingsView.swift:655-663` | `MacSettingsView.swift:395-400` (binary) | macOS: read `marketRefreshProgress` |
| SET-07 | Erase cleanup: iOS also clears `backupURL` | `SettingsView.swift:567` | `MacSettingsView.swift:835-847` (no equiv state) | Fine as-is (macOS has no backupURL) |
| SET-08 | Category-delete **confirmation copy/verb** | `SettingsView.swift:851-869` "Delete" + lead sentence | `MacSettingsView.swift:957-975` "Remove", no lead | Align to one verb/copy |
| SET-09 | macOS shows **storage path**; iOS doesn't | `SettingsView.swift:197-240` | `MacSettingsView.swift:461-465` | Optional — add caption row to iOS |
| SET-10 | "Verified before stored" **caption** macOS only | `SettingsView.swift:455-489` | `MacSettingsView.swift:414-416` | Optional — add to iOS section |
| SET-11 | Privacy-toggle **subtitle** + section grouping | `SettingsView.swift:52-74` (no subtitle, split sections) | `MacSettingsView.swift:245-262` (subtitle, combined) | Optional — add iOS subtitle |
| SET-12 | Storage **row labels** ("Recurring"/"Crypto" vs full) | `SettingsView.swift:211,223` | `MacSettingsView.swift:449,453` | Standardize labels |
| SET-13 | Onboarding **validation fallback** localization | `OnboardingView.swift:56-60` (LocalizedStringKey) | `MacOnboardingView.swift:59` (`settings.localized`) | iOS → `settings.localized("Invalid API Key")` |
| XCUT-03 | **Privacy chart cover**: 2 components; macOS CashFlow cover has no message | `MobilePrivacyChartCover` (`DashboardView.swift:358`) | `PrivacyChartCover` (`MacDashboardView.swift:534`) + bare `EmptyState` (`MacCashFlowView.swift:281`) | Promote one shared component |
| XCUT-04 | **Empty-state** components + copy differ; CTA button macOS dashboard only | shared `EmptyState` (`CryptoView.swift:72`, `InvestmentsView.swift:72`) | `ContentUnavailableView` (`MacCrypto/InvestmentsView`), `DashboardEmptyState` w/ CTA (`MacDashboardView.swift:946`) | Reconcile copy; decide if iOS wants the CTA |

---

## 6. Cross-reference to the existing audits (discrepancies matter)

| This report | Existing ID | Audit status | **Reality in current code** |
|---|---|---|---|
| EDIT-01 | `DA-H06` | "High tier 100% done" | **STILL OPEN** — omitted from every implementation commit; verified present |
| EDIT-02 | `DA-M08` | "done (all four editors)" | **PARTIAL** — fix missed the inline `MacCashFlowTransactionEditor` |
| EDIT-03 | `WC-M8`, `DA-L18` | deferred refactor | still 3 macOS editors |
| EDIT-04 | (class of `WC-M10`) | macOS fixed | iOS side still unlocalized |
| EDIT-06 | `WC-A2` | iOS fixed | macOS `MacInvestmentEditor` still `.usd` |
| VIEW-15 | `DA-M01`/`M13` | Medium "done" | editors fixed; **list-row display** precision still diverges |
| XCUT-01 | `DA-M29`/`M30` | Medium "done" (shared chart) | macOS dashboard bypasses the shared chart → fixes don't reach it |
| SYNC-01, VIEW-01, VIEW-02, SET-01, SET-02 | — | not in `DA` audit | **new** divergences |
| (context) | `DA-M03`, `DA-H01–H04`, `DA-L15`, `DA-M31` | listed open/deferred | **already implemented** — docs are stale |

> The `DA-Low` tier (`DA-L01…L62`) is untouched and largely orthogonal to parity (shared perf/latent traps).
> A handful overlap this report: `DA-L08` (iOS type-toggle — fixed), `DA-L17` (future-dated rows under
> filters), `DA-L20` (Mac editor amount-label currency code), `DA-L23` (currency relabel — present &
> identical in all four holding editors, so *not* a divergence), `DA-L49` (notification amount locale).

---

## 7. Suggested implementation order (for the next iteration)

Batches are grouped so each is independently buildable + testable on real Xcode.

1. **Batch A — correctness & privacy (do first).** SYNC-01, EDIT-01 (`DA-H06`), EDIT-02 (`DA-M08` tail),
   EDIT-06. Small, high-value, low-risk edits. *This is the batch that fixes actual wrong/leaked data.*
2. **Batch B — iOS feature parity (missing data views).** VIEW-01 (Liabilities/Net-Savings on macOS
   dashboard), VIEW-02 (Type/Geography charts on iOS), SET-01 (Remove Key), SET-02 (import→recurring).
3. **Batch C — surfaced-vs-silent + i18n.** SET-03, SET-04, EDIT-04, EDIT-05, EDIT-08, VIEW-08, VIEW-09.
4. **Batch D — selectable ranges & summaries (larger view work).** VIEW-03, VIEW-04, VIEW-05, VIEW-06,
   VIEW-07, VIEW-10, VIEW-15.
5. **Batch E — structural de-drift.** EDIT-03 (merge macOS editors), XCUT-01 (shared AllocationChart),
   XCUT-02 (list cap), plus hoisting the copy-pasted dashboard helpers into `Shared/` (kills the whole
   VIEW-13/SYNC-02 drift class at the root).
6. **Batch F — cosmetic tail (§5 table).** Copy/colour/count/date-granularity unification.

**Per-batch workflow (from `DEEP_AUDIT_IMPLEMENTATION_ROADMAP.md` §3):** feature branch → you build/test on
your Mac → fix to green → conventional commit (`fix(apple):`, **no** `Co-Authored-By` trailer) → `git
merge --ff-only` to `main`. Append a dated entry to `apple/DOCUMENTATION.md` per batch.

## 8. Verification (you run these on the Mac with full Xcode)

```bash
# Build both targets
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
  -destination 'platform=macOS' build
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'generic/platform=iOS Simulator' build

# Tests (hosted by the Mobile target)
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Manual smoke checks worth adding per batch:**
- SYNC-01 → schedule a recurring item with amount visible, enable Privacy Mode, confirm the *already-queued*
  notification body loses the amount on iOS (currently it does not).
- EDIT-01 → import a backup with a non-default category, edit that transaction on macOS Cash Flow, confirm
  the category is preserved (currently it can silently rewrite).
- EDIT-06 → add a new investment on macOS as a EUR-base user, confirm the currency default.
- VIEW-01/02 → eyeball the macOS dashboard for a Liabilities figure and the iOS Investments tab for
  Type/Geography charts.

---

*Generated from a line-by-line pass over current `main`. Line numbers drift — re-read before editing.*
