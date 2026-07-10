# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

## New features (Cash Flow Transactions + macOS responsive layout) — implemented on `main`, not built here

Build both schemes (as before), then:

### iOS — Cash Flow Overview / Transactions
- The Cash Flow tab now has an **Overview | Transactions** segmented control at the top.
- **Overview** = the summary cards + recurring + spending analytics (as before, minus the list).
- **Transactions** = the type filter (All / Income / Expense) + the period menu + a **search field** (type part of a category or a description → the list filters live) + the **full transaction list with the 40-row cap removed** (header reads "Showing N of M"). Confirm a long list scrolls smoothly (it's lazy).

### macOS — responsive full-width layout (resize the window / use an external monitor)
- **Dashboard**: below the net-worth chart there's now a **5-card row** — Monthly Income, Monthly Expenses, Net Savings, Savings Rate, Liabilities. On a wide window/monitor they sit in **one row filling the full width**; narrowing the window reflows them to 3 → 2 → 1.
- **Investments**: the three allocation charts (Sector / Type / Geography) now **fill the full width** (3 across on a wide window, reflowing to 2 → 1).
- **Full-screen fill**: on a **large external monitor**, Dashboard, Investments, and Crypto content now stretches edge-to-edge (no dead space on the right — the old ~1440/1520 caps were removed). Sanity-check the big net-worth / cash-flow charts still look OK when very wide; if any single chart looks too stretched, tell me and I'll cap just that one.

---

## iCloud sync — token/data drift self-heal (implemented on `main`, not built here)

**What changed:** a device whose persisted `CKSyncEngine` change token drifts *ahead* of its local data (a kill between the token write and the data write, or an out-of-band local-DB loss/reset/corruption) used to (a) silently show "Up to Date" while missing records forever, and (b) worse, push a **server delete** for each "missing" record on next launch — propagating one device's local loss to every device. Now that mismatch discards the token and **re-fetches** from iCloud instead of deleting. This changes sync **semantics**, so a clean build is necessary but **not** sufficient — it needs a real multi-device test.

Build both schemes + run the offline suite first:
```bash
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WealthCompassTests/CloudSyncCoreTests
```
Expect the two new tests green: `testReconcileLocalInventoryReFetchesOnDriftInsteadOfDeleting`, `testReconcileLocalInventoryKeepsRecordedDeleteAndDoesNotTreatItAsDrift`.

Then the 2-device drift smoke test (two devices on the SAME iCloud account, sync ON):
1. Get A + B in sync (add a few transactions on each; both read "Up to Date").
2. On B: quit the app, then delete ONLY `…/Application Support/Wealth Compass/wealth-compass-local-data.json`, leaving `wealth-compass-cloud-sync.json` (the token) in place. Relaunch B. (A debug build on a Mac is easiest for reaching the file; the point is to lose the data while keeping the token.)
3. Expected on B: Console shows "Local finance data drifted from the persisted CloudKit change token …" (and `SyncDiagnosticsLog` "WARN token/data drift"); B re-fetches and the transactions REAPPEAR.
4. **Safety check (the important one):** A is UNAFFECTED — nothing deleted on A. (The old code would have deleted B's "missing" records on every device.)
5. **Regression:** a normal delete still works — delete a transaction on A, confirm it disappears on B.

Report anything red.
