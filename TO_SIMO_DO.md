# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

## 1. Manual product / provisioning actions
- [ ] Onboarding tutorial for inserting the API KEY for the tracking of the assets (both macOS and iOS).

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

<!-- BATCH SMOKE TESTS APPENDED BELOW AS EACH BATCH LANDS -->
