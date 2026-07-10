# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

1. Risolvere discrepanze tra macOS e iOS ( hanno feature diverse a parità di versioni ad esempio la possibilità di impostare la currency nelle transazioni )

2. **Verify iOS↔macOS parity — Batch A** (SYNC-01, EDIT-01/DA-H06, EDIT-02/DA-M08, EDIT-06) — from `apple/IOS_MACOS_DIVERGENCE_REPORT.md`. Implemented on `main`, **not built here** (CommandLineTools only). Build both schemes + run tests from `apple/`:
   ```bash
   xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
     -destination 'platform=macOS' build
   xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
     -destination 'generic/platform=iOS Simulator' build
   xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
     -destination 'platform=iOS Simulator,name=iPhone 16'
   ```
   Smoke checks (each should now behave like the other platform):
   - **SYNC-01 (iOS):** schedule a recurring item with a visible amount, then enable Privacy Mode → the already-queued notification body should no longer show the amount (before: it still did). Also change the base currency → pending reminders should show the new currency.
   - **EDIT-01 (macOS):** import a backup containing a non-default category, then edit that transaction in Cash Flow → the category must be preserved, not blanked or rewritten to another value on save.
   - **EDIT-02 (macOS):** in the Cash Flow editor, choose "Custom…", type a name, then flip Income↔Expense → the typed name must be preserved.
   - **EDIT-06 (macOS):** add a new investment → the currency picker must default to EUR (before: USD).

   Report anything red (build error, warning, or a failed smoke check) and it gets fixed forward on `main`.

3. **Verify iOS↔macOS parity — Batch B** (VIEW-01, VIEW-02, SET-01, SET-02) — from `apple/IOS_MACOS_DIVERGENCE_REPORT.md`. Implemented on `main`, **not built here**. Same build/test commands as §2. Smoke checks:
   - **VIEW-01 (macOS):** the Dashboard now shows a Liabilities card + a current-month Net Savings card just below the net-worth chart.
   - **VIEW-02 (iOS):** the Investments tab now shows three allocation charts — Sector, Type, and Geography.
   - **SET-01 (iOS):** Settings → tap a market-data API key → when a key is configured, a red "Remove Key" appears; tapping it and confirming clears the key (status returns to "Not Set").
   - **SET-02 (iOS):** import a backup containing a recurring schedule whose next-due date is in the past → the due transaction(s) land in Cash Flow and the import summary shows an "N due recurring transaction(s) were added" note.
   - ⚠️ **One diagnostic to watch:** single-file analysis here reported `SettingsView.swift:42 "unable to type-check this expression in reasonable time."` Assessed as a false positive — it's an unedited pre-existing line and co-occurs with the cross-module `cannot find WCColor/Currency/AppSettings` cascade that makes the local type-checker give up. **If the real Xcode build reports the same timeout on `SettingsView`, tell me** — the fix is to extract the "Region & Language"/"Privacy" sections into computed subviews (fix-forward). If the build is green, ignore it.
   - Note: SET-01 adds two new English strings ("…removed from Keychain." / "…deleted from Keychain."); they render in English until the string catalog is regenerated on a build.

   Report anything red and I'll fix-forward on `main`.

4. **Verify iOS↔macOS parity — Batch C** (SET-03, SET-04, EDIT-04, EDIT-05, EDIT-08, VIEW-08, VIEW-09) — from `apple/IOS_MACOS_DIVERGENCE_REPORT.md`. Implemented on `main`, **not built here**. Same build/test commands as §2. All strings reuse existing catalog keys (no new strings). Smoke checks:
   - **SET-03 (iOS):** the normal market-data refresh still succeeds with a valid key; a Keychain read failure now shows an "Unable to Refresh Market Data" alert instead of a silent keyless refresh (hard to force by hand — mainly confirm the happy path still works).
   - **SET-04 (macOS):** set an in-app language different from the system language → the iCloud "Status" title (e.g. "Up to Date") renders in the chosen language, matching the detail line below it.
   - **EDIT-04 (iOS):** in the transaction + recurring editors, the built-in category names in the picker appear in the in-app language (not English).
   - **EDIT-05 (iOS):** in the investment editor, the Sector/Geography picker values appear localized.
   - **EDIT-08 (iOS):** in the recurring editor, set an end date before the start date (or a past first occurrence) → a yellow warning row now explains why Save is disabled.
   - **VIEW-08 (iOS):** Dashboard "Top Expense Categories" rows now show a percentage next to each amount.
   - **VIEW-09 (iOS):** Dashboard "Recent Activity" rows now show the transaction's note (or its type) under the category, with the date under the amount.
   - Same `SettingsView.swift:42` single-file type-check-timeout note as §3 applies (assessed false positive; SET-03 edits are outside the view body, so unchanged — watch the real Xcode build).

   Report anything red and I'll fix-forward on `main`.

5. **Verify iOS↔macOS parity — Batch D** (VIEW-03/04/05/06/07/10/15) — from `apple/IOS_MACOS_DIVERGENCE_REPORT.md`. Implemented on `main`, **not built here** — this is the **largest** batch (7 files, 187 insertions), so build both schemes carefully. All user-visible strings reuse existing catalog keys. Same commands as §2. Smoke checks:
   - **VIEW-03 (iOS):** the Dashboard cash-flow card has a 3M/6M/12M segmented control that redraws the chart + the "N NET" figure.
   - **VIEW-04 (iOS):** "Top Expense Categories" has a period menu (7d / 30d / 3m / YTD / All) that re-filters the list.
   - **VIEW-05 (iOS):** the net-worth chart shows date labels along the bottom and an emphasized dot when you scrub to a point. ⚠️ **If the X-axis looks cluttered on the phone, tell me and I'll revert just that part** — the report flagged it as possibly an intentional iPhone space trade-off (the PointMark dot is uncontroversial; only the axis is the judgment call).
   - **VIEW-06 (iOS):** the Crypto tab shows a Top Performer / Biggest Loser card (only when you hold a gaining and/or losing asset).
   - **VIEW-07 (iOS):** the Crypto + Investments summaries show a Performance % card and a "Status • N Coins/Sectors" card (Performance hides in Privacy Mode).
   - **VIEW-10 (macOS):** the Crypto/Investments Holdings tables list largest-value-first.
   - **VIEW-15 (both):** a high-precision crypto quantity shows up to 8 decimals and an investment quantity up to 6 — the same on iPhone and Mac (iOS was previously 6 / 4).

   Report anything red and I'll fix-forward on `main`.
