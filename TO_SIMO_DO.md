# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

## 1. Manual product / provisioning actions
- [ ] Onboarding tutorial for inserting the API KEY for the tracking of the assets (both macOS and iOS).

### ⚑ M31 CloudKit push — REQUIRED provisioning before the app will build/sign
The M31 code is landed (entitlements now declare `aps-environment`), so **signing will fail until you
enable Push on the App ID and regenerate the profile.** Steps:

**Apple Developer portal** (developer.apple.com → Certificates, Identifiers & Profiles):
- [ ] Identifiers → App ID `com.wealthcompass.mobile` → enable **Push Notifications** (keep iCloud/CloudKit on) → Save.
  _(Both targets share this bundle id per `apple/CLAUDE.md`; if the Mac app ever gets its own App ID, enable Push there too.)_
- [ ] Regenerate the provisioning profile(s) — or just let Xcode's automatic signing do it (next step).

**Xcode** (open `WealthCompass.xcodeproj`):
- [ ] **WealthCompassMobile** + **WealthCompassMac** targets → Signing & Capabilities → **+ Capability → Push Notifications**
  (Xcode picks up the `aps-environment` entitlement I added).
- [ ] **WealthCompassMobile** → **+ Capability → Background Modes** → tick **Remote notifications**
  (matches the `UIBackgroundModes` I added to `Resources/iOS/Info.plist`).
- [ ] With **Automatically manage signing** on, Xcode regenerates the profile including Push → clean build.
  For an App Store archive, Xcode auto-remaps `aps-environment` `development` → `production`.

**Smoke test (needs 2 devices on the same iCloud account, sync ON):**
- [ ] Add/edit a transaction on device A while device B is **backgrounded** (not force-quit). Within a
  minute or so (CloudKit push latency), B should reflect the change **without** being foregrounded/force-synced.
  Check Console.app for the `CloudKitPush` category log lines ("Registered for remote notifications",
  "Received remote notification — triggering CloudKit sync").
- [ ] _Note: a push that wakes the app from a **force-quit** state may not sync until next foreground
  (documented edge); CKSyncEngine catches up then. Backgrounded (not terminated) is the real-time path._

---

## 2. Build & test (run from `apple/`, after pulling latest `main`)

```bash
cd apple
# Pick a simulator that actually exists on this machine, then use its name below:
xcrun simctl list devices available | grep -i iphone

# Build macOS
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
  -destination 'platform=macOS' build

# Build iOS
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'generic/platform=iOS Simulator' build

# Test suite (swap the simulator name for one from the list above)
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

If any build/test is **red**, paste the first compile error to Claude — it'll fix on a branch and
re-land.

---

## 3. Manual smoke tests (UI-affecting fixes — the build/tests can't catch these)

Tick each once you've eyeballed it. Logic-only fixes (no UI) are covered by the build + test suite
and are **not** listed here.

### Already on `main` — 9 Medium fixes, not yet verified on a real build
- [ ] **M05** (macOS) — With VoiceOver on, focus a transaction *card*: it must be announced as a
  button and activating it (VO + Space) must open the editor.
- [ ] **M07** (iOS + macOS) — With VoiceOver on, the dashboard segmented picker (range selector):
  each segment is announced with its label + selected state, and it's operable by keyboard
  (arrow keys / Tab on macOS).
- [ ] **M30** (iOS + macOS) — Turn on **Privacy Mode**, open an allocation donut, hover/select a
  slice: the center overlay must **not** reveal the slice's share percentage (redacted like other
  amounts).
- [ ] **M08** (iOS + macOS, all 4 editors) — In a transaction editor, pick "Custom…" category and
  type a name, then toggle the **Type** (income ⇄ expense): the typed custom-category name must be
  **preserved**, not wiped.
- [ ] **M09** (iOS + macOS, investment + crypto editors) — Leave **current price** blank and save:
  the holding saves at its cost/average price (not zeroed). Leave **both** average and current price
  blank: Save is blocked.

_Logic-only, covered by build+tests (no manual smoke needed): M06 (sort memo), M10 (gain/loss %),
M25 (CoinGecko pacing), M26 (snapshot only on real price change)._

### Batch M4 (money / import / correctness) — landed on `main`, not yet built
_Logic-only fixes are covered by the build + unit tests (M18 and M22/M23 have unit tests;
M28 needs a corrupt local DB to trigger). The rest are worth an eyeball:_
- [ ] **M11** — Set base currency to **EUR**. Import a JSON backup containing a crypto (or
  investment) holding with a value but **no `currency` field**. It must show at its native value
  (no ~8% USD→EUR haircut) and the net-worth total must reflect that.
- [ ] **M19** — Edit a transaction today, then **merge-import** an older backup that still contains
  that transaction's UUID (older `updatedAt`). Today's edit must **survive** (the stale backup row
  must not overwrite it). A genuinely newer imported row should still win.
- [ ] **M20** (iOS + macOS) — Create a recurring transaction in a **foreign currency** (e.g. 100 GBP)
  with display currency **EUR**, notifications on. The due reminder must show the **converted EUR**
  amount with the **EUR** symbol — not "€100.00".
- [ ] **M21** — Let a recurring schedule lapse (end date passes → auto-deactivates). Re-open its
  editor, push the **end date** out (don't touch frequency/start), Save. It must become **active
  again** and generate occurrences.
- [ ] **M24** — Import a backup containing recurring schedules **plus** their already-generated past
  occurrences (ideally from the web app / a lossy source). On the next foreground, those past
  occurrences must **not** be duplicated in the ledger.
- [ ] **M01/M13** (iOS + macOS, crypto/investment editor) — Open a holding whose quantity has **>8
  decimals** (e.g. `0.123456789012345`), change only the name, Save. The quantity must **not** be
  truncated/rounded.
- [ ] **M29** (iOS + macOS) — Hold the **same crypto symbol in two entries** (e.g. BTC in two
  wallets). In the allocation donut, hovering/tapping one BTC wedge must highlight **only that
  wedge** (not both), and the legend must show both rows with no console duplicate-id warnings.

### Batch M5 (security) — landed on `main`, not yet built
- [ ] **M02** (macOS, needs the app-lock enabled) — Lock the app, then click to another app and back
  **repeatedly**. The Touch ID / passcode sheet must **not** re-present unsolicited on every focus
  regain (at most one auto-prompt per lock episode). While a prompt is up, the **Unlock** button is
  disabled (no double-prompt). Same check on iOS after backgrounding/foregrounding.
- [ ] **M17** (device, needs the app-lock enabled) — With the lock on, go to system Settings and
  **add a fingerprint** (or re-enroll Face ID), then return to Wealth Compass and unlock. It must show
  **"Biometric enrollment changed. Unlock again to confirm it's you."** and **not** unlock on that
  first attempt; a second unlock then succeeds. A normal unlock (no enrollment change) is unaffected.
- [ ] **M14** — _Not manually verifiable without a forensic/attribute check._ Covered by build. (The
  migrated legacy DB now gets `.completeFileProtectionUnlessOpen` instead of the copied file's weaker
  class — only relevant if you migrate from a very old build.)

### Optional follow-up (localization)
- [ ] The M17 warning string ("Biometric enrollment changed. Unlock again to confirm it's you.") is a
  **new** catalog entry; Xcode extracts it on build and it shows in English until translated in
  `Localizable.xcstrings`. Not blocking — add translations when convenient.

### Batch M3-rest (perf / charts) — landed on `main`, not yet built
- [ ] **M04** (macOS, the visible one) — On the Cash Flow tab set the range to **12 months** during a
  month when the window straddles two years (i.e. any month except December). Bars for the two
  same-named months (e.g. two "Jul") must be **distinct columns**, hovering each must show **that**
  month's income/expense/net (not the other year's), and the x-axis must still read "Jul", "Aug", …
- [ ] **M15/M16** (perf, both platforms) — With a **multi-year** account (import old snapshots), open
  the dashboard net-worth chart at range **All**. It should render/scroll smoothly (no jank) and not
  rebuild on every interaction. Shorter ranges (1W…1Y) still show daily detail.
- [ ] **M27** (perf, both platforms) — Hover/drag across the expenses pie and (macOS) resize the
  window: no stutter. Then add a transaction and confirm the cash-flow numbers update (cache
  invalidates on data change). _Perf-only; correctness is covered by the build + tests._

### Low Tier 1 (correctness / data-loss) — landing batch-by-batch on `main`, verify at the Tier-1 checkpoint
_I'll tell you when all Tier-1 batches have landed; then build + run these. Batch 1 (analytics):_
- [ ] **L07** — On a dashboard where net worth crosses ~0 within the selected range (e.g. -100 → +50),
  the change badge shows the absolute change with a sane / 0 %, not a huge percentage.
- [ ] **L34** — With an investment whose bucket nets to 0, the investment allocation legend shows no
  empty/phantom row.
- [ ] **L51** — Add a transaction dated in the **future** (e.g. next week). Today's net-worth total must
  **not** include it yet; it appears once that day arrives. (Also covered by a unit test.)

_Batch 2 (dates / timezone / import):_
- [ ] **L05** — Change the device timezone, reopen the app, check a period filter (7-day / 30-day / YTD):
  transactions right at the range's day boundary must not drop.
- [ ] **L42** — Import a backup whose recurring schedule has a **date-only endDate on the same day** as a
  timed startDate: the schedule must import (not be silently dropped) and keep its final occurrence.
- [ ] _L32 (cash-flow month bucketing) and L43 (import parse safety) are logic-only — covered by build + tests._

_Batch 3 (recurring editor):_
- [ ] **L09** — In the recurring-transaction editor (iOS + macOS), set the start date to **today** at a
  time earlier than now. Save must be **enabled** (not silently stuck disabled), and the saved schedule's
  first occurrence clamps forward. A genuinely **past day** still blocks Save with the validation message.
- [ ] _L25 (save-time re-validation) is logic-only — covered by build. (L10 was already fixed by M09.)_

_Batch 4 (persistence / metadata error-handling) — all error-path/robustness, covered by build:_
- [ ] _L29 (clear a corrupt exchange-rate cache), L30 (migration backup is best-effort, won't abort load),
  L38 (metadata reset writes empty file instead of deleting). Hard to smoke manually; rely on build._

_Batch 5 (concurrency / cleanup) — logic/latent, covered by build:_
- [ ] _L50 (backoff counter clamped in storage), L61 (masonry layout guards a non-finite width — latent),
  L54 (market-price refresh throttle now survives relaunch). L06 assessed and left (safe fire-and-forget)._

**Deferred bucket — RESOLVED (decisions made 2026-07-06), now being implemented this push:**
- **L33** → clamp negative cash to 0 in the asset donut + conditional footnote quantifying the excluded liability.
- **L23** → on a currency change on an existing holding, prompt **Convert (default) / Keep numbers** across all 4 editors.
- **L40** → minimal seed-rate indicator: Settings → Exchange Rates row naming affected held currencies + subtle dashboard caption.
- **L37 / L52 / L39** → all three fixed (L39 grounded in a careful tombstone read), each with a unit test. **Still needs on-device sync smoke afterward.**
- **L44 / L06** → documented only, no behavior change (changing L44 would desync web-app UTC import).
- **M31** → deferred to its own next prompt (needs your provisioning-profile / entitlement change first).

---

## 4. Low Tier 2/3 smoke tests (landing batch-by-batch on `main`)

### Batch T2-1a (editors: L13, L20) — landed, not yet built
- [ ] **L13** (iOS + macOS) — On the onboarding API-key page, type a key into Finnhub or CoinGecko, then tap
  **Skip for now**. It must now show a confirm ("Unsaved API Key — Save & Continue / Discard / Cancel"),
  **not** silently drop the key. "Save & Continue" validates + stores it; "Discard" proceeds without it.
  With **both** fields empty, Skip proceeds immediately (no dialog).
- [ ] **L20** (iOS + macOS) — In the transaction, investment, and crypto editors, the Amount / Average Buy
  Price / Current Price field labels now show the active **currency code** (e.g. "Amount (USD)"), matching
  the recurring editor. Changing the Currency picker updates the code in the labels.
- [ ] _New catalog strings (English fallback until translated): "Unsaved API Key", "Save & Continue",
  "Discard", "You entered an API key but haven't saved it…", plus the interpolated
  "Average Buy Price (%@)" / "Current Price (%@)" labels._

### Batch T2-1b (persist fee mode L22 + currency convert prompt L23) — landed, not yet built
- [ ] **L22** (iOS + macOS, investment + crypto editors) — Add a holding with **Fee Type = Percent** (e.g. 0.5%),
  save. Reopen it: the editor must reopen in **Percent** mode showing 0.5 (not Fixed with an absolute amount).
  Now **double the quantity** and save: the fee (and cost basis) must **scale** with the larger position.
  Legacy holdings (added before this build) still open in **Fixed** mode showing their absolute fee.
- [ ] **L22 (no-churn check)** — A pre-existing holding you *don't* edit must not spontaneously re-sync
  (the new fields are omitted from its JSON until you actually edit it). Nothing to see; just confirming no
  surprise iCloud activity.
- [ ] **L23** (iOS + macOS, investment + crypto editors) — Open an **existing** holding priced in, say, USD.
  Change the **Currency** picker to EUR: a prompt appears — **Convert Amounts** (default) converts the
  avg/current price (+ a fixed fee) at today's rate; **Keep Numbers** leaves the digits and just relabels;
  **Cancel** reverts the picker to USD. A **new** holding shows **no** prompt when you pick a currency.
- [ ] _New catalog strings: "Change Currency", "Convert Amounts", "Keep Numbers", "Convert the entered
  amounts from %@ to %@ at today's exchange rate…"._

### Batch T2-2 (localization: L19, L21, L26, L41, L49) — landed, not yet built
_Mostly logic/localization; verify with an **in-app language different from the system language**
(Settings → set app language to e.g. Italian on an English device):_
- [ ] **L26** — Trigger an **import failure** (import a non-backup file) with app language ≠ system language:
  the alert **title and body must both be in the app language** (previously the body was system-locale English).
- [ ] **L49** — With app language set to a locale using different separators (e.g. Italian: "1.234,56"),
  a recurring-transaction **notification** amount must use those separators/symbol placement, matching the sentence.
- [ ] **L19** (macOS) — Crypto + Investments overview "Status • N Coins/Sectors" cards still render correctly
  (no change expected; this removed a redundant double-localization). Also check no `Text` shows a raw key.
- [ ] **L41** — Force an **exchange-rate refresh failure** (airplane mode + stale rates): the failure message
  reads as one coherent sentence (the "…continue using the last cached rates." clause is no longer half-English
  in non-English locales). _New English-fallback keys until translated._
- [ ] **L21** — In a non-English app language, the "future <income/expense> transactions" / "No custom
  <type> categories yet." hints lowercase correctly (Turkish especially). _Known residual: German-style noun
  capitalization isn't fixed by this (would need full-sentence templates + translations) — CHECKPOINT QUESTION below._

**⚑ Checkpoint decision (L21):** fully fixing noun capitalization (e.g. German "Einkommen" mid-sentence)
needs per-type/per-frequency **full-sentence catalog keys + ~40-language translations**, and would regress the
currently-translated `%@`-frame strings to English until re-translated. I did the safe, no-regression
locale-aware-casing fix. **Want the full-template version too?** (It's a translation-content investment.)

**⚑ Translation follow-up:** new English-fallback strings added this push (need translation when convenient):
L13 (Unsaved API Key / Save & Continue / Discard / message), L23 (Change Currency / Convert Amounts /
Keep Numbers / message), L41 (the two "…continue using …" full sentences). M17's earlier warning string too.

### Batch T2-3a (biometric lock: L11/L35, L14/L36) — landed, not yet built
_Needs the app-lock enabled; iOS + macOS:_
- [ ] **L14/L36** — With the lock on, open the lock screen (or the Settings → Security section) and
  **deliberately cancel** the Face ID / Touch ID sheet. There must be **no persistent red error**
  ("Canceled by user/system") left on screen; a genuine failure (e.g. too many wrong attempts) still shows.
  Re-locking / retrying clears any prior message.
- [ ] **L11/L35** — Perf/behavior sanity: the lock screen and Settings Security section still show the
  correct biometry name + icon (Face ID / Touch ID). No functional change expected (this just caches the
  biometry type instead of re-probing on every render).

### Batch T2-3b (chart domain / cash-flow filter / layout / Mac Settings: L31, L17, L24, L15) — landed, not yet built
- [ ] **L31** — On a brand-new account (net worth 0) or one near break-even, the dashboard net-worth chart
  shows a **readable y-axis** (roughly -1…1), not an absurd sub-penny scale (-0.01, 0, 0.01). Also covered by a unit test.
- [ ] **L17** (macOS) — Add a **future-dated** transaction (e.g. rent next week). With Period = **Year to Date**
  (or All) it must appear in the cash-flow **table**; under rolling windows (7/30/90 days) it's correctly absent
  (it's not in the "last N days"). The chart/totals still don't count it until it's realized.
- [ ] **L24** (macOS) — On the Investments **Overview**, drag the sidebar to make the detail pane **narrow**:
  the three allocation charts must **reflow** (wrap to fewer columns / stack) with readable legends, not squeeze
  into three skinny truncated columns.
- [ ] **L15** (macOS) — **Settings** is no longer in the sidebar (⌘5 removed). Open it via **⌘,** or
  WealthCompass ▸ Settings… (the native window). Confirm the sidebar shows only Dashboard/Cash Flow/Investments/Crypto,
  and **⌘R Refresh Data** works on all of them.

### Batch: Deferred bucket (L33 asset-pie, L40 seed-rate, L44/L06 doc-only) — landed, not yet built
- [ ] **L33** (iOS + macOS) — Make **Cash net-negative** (record more cash liabilities than assets, or an
  overdraft). On the dashboard **Asset Allocation** ring, a footnote must appear: "Chart shows gross assets;
  <amount> in net cash liabilities is excluded." (amount redacted in Privacy Mode). With non-negative cash,
  no footnote.
- [ ] **L40** (iOS + macOS) — Hold a position in a currency the rate provider doesn't return (rare; or simulate
  by editing a holding to an exotic currency). Settings → **Exchange Rates** shows "Rates may be incomplete: <codes>…",
  and the dashboard net-worth hero shows a subtle "Rates may be incomplete" ⚠︎ caption. With all held currencies
  covered, neither appears. _New English-fallback strings until translated._
- [ ] _L44 (parseDateOnly UTC comment) and L06 (fire-and-forget Task comment) are **doc-only** — no behavior change._

### Batch: Sync trio (L37, L39, L52) — landed, needs **ON-DEVICE SYNC** verification (not just a build)
_These are the "verify sync on a real device" items you agreed to. Two devices on one iCloud account:_
- [ ] **General sync sanity** — Add/edit/delete transactions/holdings on device A → they appear on device B, and
  vice-versa; deletes propagate (no zombie records reappearing). This exercises L39's tombstone-reconcile path.
- [ ] **L52** — With iCloud sync ON, immediately after a cold launch do **Settings → Erase Everything** (factory
  reset). Afterwards the CloudKit engine must be **off** and `isICloudSyncEnabled` false — the wipe must not be
  "undone" by a late init task restarting sync. (Very narrow timing window; hard to hit manually — mainly a
  code-correctness fix. If you can, background/relaunch right at erase time.)
- [ ] **L37** — No behavior change (comment only): the metadata persist ordering was investigated and left as-is
  (reordering would deadlock). Nothing to test; noted for completeness.
- [ ] _L39 is defensive against a concurrent tombstone race the audit marked "confirm at runtime." If during
  heavy two-device concurrent editing you ever see a deleted record reappear, tell me — but the fix should prevent it._

### Batch: Tier 3 part 1 (cosmetic / a11y / perf: L01,L45,L46,L56,L57,L58,L59,L60,L62) — landed, not yet built
- [ ] **L56** (iOS + macOS) — Investments Overview → "Allocation by Geography": the wedges/legend should now
  use **distinct colors** (no two near-identical oranges), readable for the two largest regions.
- [ ] **L59** (iOS + macOS, VoiceOver) — On an allocation donut, VoiceOver should announce each slice **once**
  (from the chart), not twice (the legend is now hidden from VoiceOver).
- [ ] **L60** (macOS) — The dividers between the segmented-selector tabs render as a subtle light hairline
  (not the default system separator color).
- [ ] **L62** — API-key onboarding/guide step text renders normally (token cleanup; ~no visible change).
- [ ] _Logic/perf (covered by build): **L45** (shared JSON decoder), **L46** (adds a diagnostic log for a
  CoinGecko format drift — only visible in Console.app), **L57** (background animation pauses off-screen),
  **L58** (allocation legend no longer re-renders on hover), **L01** (explicit ATS plist stance)._

### Batch: Tier 3 part 2 (refresh/recurring perf: L47, L53) — landed, not yet built
- [ ] _Both logic/perf, covered by build — behavior-preserving:_
  - **L53** — recurring-transaction catch-up no longer does an O(n) scan per occurrence (Set dedup); the
    same-day dedup behavior (M24) is preserved. Optional check: import a backup with recurring schedules +
    their past occurrences → no duplicate ledger rows on next foreground (same as M24's test).
  - **L47** — with a **Finnhub** key and many US holdings, if Finnhub rate-limits (429) during a price
    refresh, the rest of the USD holdings should fall back to Yahoo instead of each retrying Finnhub 3×
    (fewer requests, faster give-up). Hard to trigger deliberately; mainly a code-efficiency fix.

**⚑ One Tier-3 item DEFERRED (needs your call): L55** — moving the manual **Backup export / Import** off
the main thread (they currently encode/parse the whole dataset synchronously, so a very large DB briefly
freezes the UI on Prepare Backup / Import). I did **not** do it: the import parse takes the `@MainActor`
settings, so an off-main hop has real Swift-concurrency (Sendable) friction, and it's a rare manual op on
the data-critical import path — not worth the regression risk at the tail of this push. **Want it?** I'll
do it carefully as a focused follow-up (it's the last remaining audit item).

<!-- BATCH SMOKE TESTS APPENDED BELOW AS EACH BATCH LANDS -->
