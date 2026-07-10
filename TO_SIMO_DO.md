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
