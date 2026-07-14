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

### macOS — collapsible sidebar + toolbar page-switcher (refined)
- **Collapse the sidebar**: click the native **sidebar-toggle button** in the toolbar (or **View ▸ Hide Sidebar / ⌃⌘S**). The **icon+label page-switcher pill** now appears **in the centre of the grey toolbar** (not floating over the content) listing all 5 pages — Dashboard, Cash Flow, Investments, Crypto, **Settings**; clicking a segment switches page. Confirm it **no longer overlaps** each page's own top selector (Cash Flow's Overview/Transactions etc.), and that the toolbar's empty centre is now filled. Expand the sidebar again → the pill disappears and the page-name title returns in the toolbar. When collapsed, the toolbar title is intentionally blank (the switcher names the page).
- The collapsed/expanded state **persists** across relaunch.
- **Settings is a page** (not a separate window): it shows in the sidebar and the toolbar pill; **⌘,** (App ▸ Settings) *and* **⌘5** both jump to it; the "Refresh Data" toolbar button is hidden while on Settings. Confirm Settings still works fully inline (currency, language, biometric lock, iCloud, API keys, import/export).

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

---

## [2026-07-13] Broker CSV Import (Revolut + Trade Republic) — manual follow-ups

**1. Build + test on a machine with Xcode (required — this environment only has Command Line Tools, so `xcodebuild` couldn't run).** The parser logic was verified standalone with `swiftc` against your two real sample CSVs and against the synthetic test fixtures (all green), but the full app build + XCTest still need Xcode:
```bash
cd apple
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WealthCompassTests/BrokerStatementImportServiceTests
```
Then smoke-test: Settings → **Import Data…** → pick a Revolut/Trade Republic CSV on both iPhone and Mac; confirm the summary names the detected format and the counts look right.

**2. New UI strings — TRANSLATED (done).** All 11 new/orphaned user-facing strings ("Import Data", "Import Data...", "Detected format: %@.", the CSV/PDF read errors, the unsupported-PDF and no-records errors, plus 3 previously-untranslated iCloud-deletion messages) were translated into **all 34 app languages** and written into `Localizable.xcstrings` (placeholders + brand names preserved, verified). Just **re-open the catalog in Xcode once** so it re-normalizes the file to its canonical spacing (my JSON writer used standard `": "` instead of Xcode's `" : "` — harmless, valid JSON, but Xcode will tidy the diff on save). The detected-format *names* ("Trade Republic account statement (PDF)", etc.) remain English brand/format identifiers by design. *(Number-format handling is also DONE — English `1,234.56` and European `1.234,56` both parse.)*

**3. Trade Republic provenance — confirm against a real TR export.** Per your instruction I treated `Transaction export.csv` as the Trade Republic format and built + labeled the parser accordingly. Heads-up: that file's row contents read like a **Revolut** trading export (they literally contain "Sent from Revolut", `STOCKPERK`, `TAX_OPTIMIZATION`). The parser is driven by the header signature (`datetime,account_type,asset_class,…`), so it works on files of that exact shape. **If your actual everyday Trade Republic CSV has different columns, the auto-detector won't recognize it** — send me one real TR export and I'll add its signature + mapping (a few minutes of work).

**4. Don't commit `IMPORT_TEMPLATE/`.** It holds real financial PII (IBANs, full merchant history) and is now in `.gitignore`. It was never committed (untracked), so nothing to scrub — just leave it ignored.

**5. Verify the imported-holding ticker backfill (build + one manual check).** Imported holdings already price via Yahoo's ISIN search (keyless). A new change persists the resolved ticker back to the holding so it stops showing the raw ISIN. This touches `FinanceStore.refreshMarketPrices` + `MarketDataService.resolvedQuote`, which I can't compile standalone — so **build both targets** (it syntax-parses clean, but confirm it type-checks) and run `WealthCompassTests` (esp. `MarketDataServiceTests`). Then a quick manual check: import a broker CSV → tap **Refresh Prices** → confirm (a) the ETF + stocks get live values and (b) their ticker column changes from the ISIN to a real symbol (`GOOGL`, `VWCE.DE`, …).

**6. Trade Republic PDF import — DONE, needs your build to confirm.** Built + **verified against your real `Account statement.pdf` and `Net Worth.pdf`** via a Swift+PDFKit harness (5 transactions with correct signs/categories; 3 holdings totalling €6.958,80; cash €5.521,75). The parsing logic (pure text→data) is fully tested; the PDFKit extraction runs in the app. Two things to confirm in Xcode:
  - **PDFKit linking**: `BrokerStatementImportService.swift` now `import PDFKit`. Swift should auto-link it, but if the build fails with a PDFKit linker error, add PDFKit to the target's "Link Binary With Libraries" (both `WealthCompassMobile` and `WealthCompassMac`).
  - **Manual check**: Settings → Import Data → pick `Account statement.pdf` (expect ~5 transactions) and `Net Worth.pdf` (expect **one net-worth snapshot** — a point on the net-worth history chart dated 13 Jul, €12.480,55 — *not* holdings/cash). Summary should name "Trade Republic account statement (PDF)" / "…net-worth statement (PDF)".
  - The **Revolut PDF is intentionally rejected** with a helpful message ("PDF statements are supported for Trade Republic only — import the CSV instead"); use `consolidated_statement.csv` for Revolut.
  - **No more cash double-count**: after the professional-review pass, the Net Worth PDF imports as a `NetWorthSnapshot` (not holdings + cash), so it composes cleanly with the transaction CSV. Your actual TR holdings (with cost basis) come from `Transaction export.csv`; the Net Worth PDF just adds a net-worth history point. A user who *only* has the Net Worth PDF gets the snapshot but no individual holdings — that's expected.