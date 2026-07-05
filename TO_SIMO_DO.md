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

<!-- BATCH SMOKE TESTS APPENDED BELOW AS EACH BATCH LANDS -->
