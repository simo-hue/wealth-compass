# Wealth Compass (Apple) — Testing Guide

Step-by-step verification for the **P1** and **P2** audit work. None of this could be built or run
in the agent environment (no Xcode — Command Line Tools only), so everything below is for you to run.
Work top to bottom: **Phase 0 → 1 → 2 → 3**. Stop and report back if anything in Phase 0/1 fails.

Each manual check is tagged with its audit ID (e.g. `[H2]`) so you can cross-reference `CODE_AUDIT.md`.

---

## Phase 0 — Project integrity (validates the hand-edited `project.pbxproj`)

I added **9 new files** to `project.pbxproj` by hand (5 source + 4 test). Confirm the project still
parses and the files are in the right targets.

1. Open `WealthCompass/WealthCompass.xcodeproj` in Xcode. **It must open without a "damaged project" error.**
2. In the Project Navigator, confirm these appear and are members of the right targets (File Inspector → Target Membership):
   - `Sources/Shared/Models/CurrencyConverter.swift` → **WealthCompassMobile + WealthCompassMac**
   - `Sources/Shared/Services/SnapshotEngine.swift` → Mobile + Mac
   - `Sources/Shared/Services/AnalyticsEngine.swift` → Mobile + Mac
   - `Sources/Shared/Services/RecurringScheduleBuilder.swift` → Mobile + Mac
   - `Sources/Shared/UI/PieSliceHitTester.swift` → Mobile + Mac
   - `Tests/CurrencyConverterTests.swift`, `Tests/SnapshotEngineTests.swift`, `Tests/RecurringScheduleBuilderTests.swift`, `Tests/AnalyticsEngineTests.swift` → **WealthCompassTests** only

If the project won't open, the pbxproj edit is the cause — tell me and I'll fix it (it passed `plutil -lint`
+ a reference-consistency check, so this is unlikely).

---

## Phase 1 — Builds

```bash
cd apple

# macOS
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
  -destination 'platform=macOS' build

# iOS (use a simulator that exists on your machine)
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Both must succeed. I type-checked **all Shared + macOS** sources with `swiftc` (0 errors) and parse-checked
the iOS-only files, but the full iOS SDK build is unverified by me. Most-likely failure points if any:
the iOS views I touched — `iOS/Views/Forms.swift`, `iOS/Views/CashFlowView.swift`, `iOS/Views/OnboardingView.swift`,
`iOS/ContentView.swift`.

---

## Phase 2 — Unit tests

```bash
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Runs all suites: the pre-existing `CloudSyncCoreTests` plus the 4 new ones (`CurrencyConverterTests`,
`SnapshotEngineTests`, `RecurringScheduleBuilderTests`, `AnalyticsEngineTests`).

⚠️ **I could not run these.** The logic is sound, but a few assertions encode my own date/count reasoning
(esp. `SnapshotEngineTests.testBackfillsMissingDays` expecting 5 and `testBackfillCapsAt60Days` expecting 62,
and the monthly-anchoring date in `RecurringScheduleBuilderTests`). If one of those fails on an off-by-one,
it's almost certainly the **test expectation**, not the engine — paste me the failure and I'll correct it.

---

## Phase 3 — Manual smoke tests

Run on **both iOS and macOS** unless noted. For each: do the steps, confirm the expected result.

### P1 — data integrity / security / privacy

- **[H1] Direct API calls (proxy removed).** Settings → enter your Finnhub + CoinGecko keys → add an
  investment (e.g. symbol `AAPL`) and a crypto holding (coin id `bitcoin`) → tap Refresh.
  *Expect:* live prices populate; no errors. Also open onboarding (see [H6]) and read the **privacy screen** —
  it should say data stays on-device/iCloud and prices come **directly** from Frankfurter/Finnhub/CoinGecko
  (no mention of a central server).
- **[H2] Crypto cost-basis currency.** Add a crypto holding → **pick a currency** in the new picker →
  enter avg buy price + a fee. *Expect:* the "Calculated Fee" shows that currency. Now tap Refresh prices.
  *Expect:* the holding's currency **does not change** and its cost basis / P&L stay sensible (this was the bug).
  Edit an existing holding → its currency is preserved.
- **[H3] Many currencies.** Open any investment or crypto editor's **Currency** picker.
  *Expect:* ~31 currencies (EUR/USD/GBP/CHF first, then alphabetical). Set an asset to e.g. **JPY**, then
  Refresh exchange rates (Settings). *Expect:* the dashboard total reflects a JPY→base conversion (not a raw number).
- **[H5] Save never crashes.** Just use the app normally (add/edit/delete a few records).
  *Expect:* no crash, data persists. (The new save-error **banner** only appears on a real disk-write failure,
  which is hard to force — you can skip trying to trigger it.)
- **[H6] Onboarding doesn't pre-fill secrets.** Settings → turn **Onboarding** back on (or delete + reinstall) →
  go to the API-keys step. *Expect:* the key fields are **empty**; if a key is already stored you see a
  **"Configured"** badge and a "replace" placeholder. Leaving a field blank keeps the existing key.
- **[H7] Recurring can't mass-generate.** Create a recurring **monthly** transaction with a **future** start →
  it saves and shows a future next-due. Then **edit** an existing schedule and move its start date **far into the
  past** → save, reopen the app / let it process. *Expect:* it does **not** create a flood of back-dated
  transactions (at most a bounded recent catch-up, or none) and the app doesn't hang.

### P2 — architecture / dedup

- **[M1/M5] Analytics regression (most important P2 check).** The totals/charts logic moved into engines but
  behavior should be **identical**. Verify on both platforms:
  - Dashboard: net worth, total assets, total liabilities, and the net-worth history chart look right.
  - Cash Flow: monthly income/expense + the category breakdown.
  - Investments & Crypto: allocation donuts + totals.
  - Add/edit/delete a transaction → totals and the net-worth snapshot update as before.
- **[M2] Pie/donut selection (the dedup'd hit-tester).** On **both** platforms:
  - Dashboard allocation donut → tap (iOS) / hover (macOS) a slice → it highlights and shows its detail.
  - Cash Flow category donut → same.
  *Expect:* selection still maps to the correct slice (all 4 charts use the shared `PieSliceHitTester` now).
- **[M2] Recurring create/edit (the dedup'd builder).** Create and then edit a recurring transaction on
  **both** platforms. *Expect:* next-due date is computed correctly and saving works (logic is now shared).
- **[M6] macOS Settings is an in-window page (sidebar + ⌘,).** On macOS: the sidebar shows **Dashboard /
  Cash Flow / Investments / Crypto / Settings**. Open Settings either by clicking the **Settings** sidebar
  row or by pressing **⌘,** (or "Wealth Compass ▸ Settings…") — both select the same in-window Settings
  page (no separate Preferences window).
  *Expect:* exactly one Settings surface; ⌘1–⌘5 switch sidebar sections (⌘5 = Settings).
- **[M7] Refresh progress.** With several investments + a Finnhub key, tap Refresh.
  *Expect:* the refresh button shows **"Updating x of N"** counting up as it fetches each stock (the crypto
  call is batched). It should feel snappier than before (0.3s spacing vs the old fixed 1s), and only slow down
  if you actually get rate-limited.
- **[M8] Network resilience.** Turn on Airplane Mode, then tap Refresh (or refresh exchange rates).
  *Expect:* it retries briefly then fails gracefully with an error message (no crash). Turn connectivity back
  on and refresh → it succeeds. (Optional/harder: a flaky connection should now recover via retry where it
  previously failed on the first hiccup.)
- **[M1] Import still works (parser extracted to `FinanceImportService`).** Settings → Import a JSON backup
  (both a current export and, if you have one, a legacy/web-format file). *Expect:* records import exactly as
  before (transactions, investments, crypto, liabilities, snapshots), the "skipped records" count looks right,
  and merge vs. replace behave as before. This exercises ~900 lines of moved code, so it's the key M1 regression check.
- **[M2 notifications] Recurring reminders still fire (shared `RecurringNotificationService`).** Create a recurring
  transaction with "Notify When Due" + a near-future time on **both** platforms; confirm the notification appears
  and tapping it opens the app. (macOS now also requests **badge** permission — intentional.)
- **[M2 lock] Biometric lock still works (shared `BiometricLockStore`).** Enable the lock in Settings, background +
  relaunch, confirm Face ID / Touch ID unlock works on **both** platforms. iOS and macOS keep **independent** lock
  settings (different keys) — enabling on one must not flip the other.
- **[M2 onboarding] Onboarding flow (shared `OnboardingViewModel`).** Run onboarding on **both** platforms: paste a
  valid key (validates + saves + completes), paste an invalid one (shows the failure alert), leave blank with a key
  already stored (shows "Configured", proceeds), and "Skip for now". All credential state now lives in the shared VM.
- **[M2 settings] Settings credential editor (shared `SettingsViewModel`).** In Settings, add/replace a Finnhub +
  CoinGecko key on **both** platforms → the "returned a live …" success message and the failure alert still appear
  (the validation logic is shared now; the editor UI stays native per platform).

---

## If something fails

- **Build error** → paste the file + error; most risk is in the iOS views I could only parse-check.
- **Test failure** → paste it; engine-logic vs. test-expectation is usually obvious (see the Phase 2 note).
- **Behavioral surprise** → tell me the step + what you saw vs. expected.

Remaining P2 work (not yet implemented) is queued in `DOCUMENTATION.md` → "REMAINING P2".
