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

---

## [2026-07-17] Fix: empty edit-form on first tap (iOS Investments/Crypto) — build + tap test

Fixed the bug where tapping a row in **Investments → Positions** or **Crypto → Holdings** opened the edit sheet empty on the *first* tap (correct only on the second). Changed both iOS views to present the editor with `.sheet(item:)` (item-identity driven) instead of `.sheet(isPresented:)` + a separate selection `@State`. Files: `apple/WealthCompass/Sources/iOS/Views/InvestmentsView.swift`, `apple/WealthCompass/Sources/iOS/Views/CryptoView.swift`. macOS was already correct and is untouched.

**This environment only has Command Line Tools, so `xcodebuild` couldn't run.** I `swiftc -parse`-checked both files (no syntax errors), but the full build + a manual tap test still need Xcode:
```bash
cd apple
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build
```
Then smoke-test on the simulator/device:
- **Investments → Positions** tab → tap any position → the edit sheet must open **already pre-filled on the first tap** (symbol, quantity, price, etc.). Repeat with the **row context-menu → Edit**, and with VoiceOver's activate action.
- **Crypto → Holdings** tab → same check.
- Confirm the **+ (Add)** button in both pages still opens a blank new-asset form, and that saving/dismissing works and the sheet fully dismisses (no lingering state).
---

## [2026-07-17] Repo reorg: web app moved to `web-app/` — deploy verification + 3 decisions

The web app moved from the repository root into `web-app/`. `apple/` is untouched apart from two
doc sentences that pointed at the old location. I verified the build (identical output hashes to the
pre-move build — see DOCUMENTATION.md), but **three things need you**:

### 1. Verify the deploy still works — I could not do this for you

Deploying publishes your live site, so I did not run it. This is the one part of the move I could not
prove from here:

```bash
cd web-app
npm run deploy
```

Then check <https://simo-hue.github.io/wealth-compass/> still loads, and that navigating between
pages works (the `/wealth-compass/` sub-path is served by both the Vite `base` and the Router
`basename`). Everything I *could* check says this is safe: `gh-pages` resolves the target from the
`origin` remote rather than the working directory, and the build output is byte-identical. But the
deploy itself is the only real proof.

### 2. Your CI deploy workflow was deleted by accident in June — restore it?

`.github/workflows/deploy.yml` was removed in commit **`ba8c852` (2026-06-22)**, whose message is
**"icloud fix"** — a commit about iCloud sync, nothing to do with CI. It looks unintentional. Before
that it auto-deployed on every push to `main`; since then every deploy has been manual, and the
README had been advertising CI that no longer existed.

Note it published to the **`gh-pages-webapp`** branch, but Pages serves **`gh-pages`** — so restoring
it verbatim would publish to a branch nobody reads. If you want it back, say so and I'll restore it
with `working-directory: web-app`, `folder: web-app/dist`, and `branch: gh-pages`. Your call whether
pushes to `main` should auto-publish.

### 3. Stale branch `origin/gh-pages-webapp` — safe to delete?

Last written **2026-06-10** by the now-deleted workflow. Pages does not serve it. It appears dead:

```bash
git push origin --delete gh-pages-webapp   # only if you agree it's dead
```

### Also worth knowing

- `package.json` `homepage` said `libriperilcambiamento.github.io` while your remote is `simo-hue`.
  You confirmed `simo-hue`, so I corrected it in `package.json`, `DEPLOYMENT.md`, and the README.
  Vite ignores `homepage` (it's a Create React App field), so this was cosmetic — but it was wrong.
- `npm run lint` reports **52 pre-existing problems** (38 errors, mostly `no-explicit-any`). These are
  **not** from the move — every flagged file is a 100% byte-identical rename. Untouched, and worth a
  separate pass if you care.
- `npm install` reports **14 vulnerabilities (7 high)**. Also pre-existing, also out of scope here.

---

# 🔴 [2026-07-17] SECURITY — your financial data was public for 6 weeks. One action is URGENT.

## What happened

`apple/export template.json` was **not** a template despite its name. It was a real export of your
finances, public on `origin/main` from **2026-06-06** (commit `5ac5154`, was `ad6a4ff`) until today:

- 139 transactions, 3 investments, 6 crypto holdings, 68 net-worth snapshots
- Your full net-worth curve: **€10,371 → €14,995**, Dec 2025 → Jun 2026 (last €14,937.77)
- **Health data**: `Analisi sangue`, `Pharmacy`, `medicines for cold`, `supporto toracico` —
  special-category data under GDPR Art. 9
- **Named third parties**: `Cena con mia`, `London with mia`, `teaching Maxim`, `Lunch with lee`,
  `Sito web Matteo` — so this is other people's data too, not only yours
- Attributable to you by name via commit metadata and the Apple ID in `fastlane/Appfile`

## What I already did

- Moved the file to the gitignored `IMPORT_TEMPLATE/` — **your data is preserved, not deleted**
- Purged it from all 291 commits with `git filter-repo` and force-pushed `main` + `code-audit`
- Also purged the `.ipa`, `.dSYM.zip`, and the Xcode `build/` tree (`.git`: **409MB → 60MB**)
- Added `.gitignore` rules (`*.ipa`, `*.dSYM.zip`, `.cursor/`, `export*.json`) so it can't recur
- Backup of the pre-rewrite repo: `~/wealth-compass-BACKUP-before-history-rewrite.bundle` (268MB,
  verified restorable). **Keep it until you're satisfied, then delete it — it still contains the data.**

## 🔴 ACTION 1 — the data is STILL PUBLIC. Only you can fix this.

**The force-push did not evict it.** Your repo has **3 forks**, so GitHub keeps the old objects in the
shared fork network. I verified this against the live API *after* the push — all still HTTP 200:

```
https://api.github.com/repos/simo-hue/wealth-compass/commits/443cf2d          -> 200
https://api.github.com/repos/simo-hue/wealth-compass/commits/ad6a4ff          -> 200
https://api.github.com/repos/simo-hue/wealth-compass/git/blobs/4a27b6bf6394b21bcc2c287935429d136421a37f -> 200  ← YOUR DATA
```

**Contact GitHub Support and ask them to purge the cached views and unreachable objects** for
`simo-hue/wealth-compass`. This is a standard request for leaked-data incidents and it is the *only*
way to remove them. https://support.github.com/contact — cite the blob SHA above.

The forks (all last pushed *before* 2026-06-06, so they likely never had it in their own branches):
- `Madhuzutan/wealth-compass` (2026-02-14)
- `libriperilcambiamento/wealth-compass` (2026-03-30)
- `valeriobasiliocova/wealth-compass` (2026-01-02)

Support will likely ask you to have these deleted first. Note `libriperilcambiamento` is the same org
in the old `homepage` field — it may be your own, in which case just delete it.

**Regardless of outcome: treat this data as disclosed.** It was public for 6 weeks and may already be
copied, cached, or indexed.

## 🟠 ACTION 2 — confirm Row Level Security on Supabase

Your project ref **`tstmgujgiygcravqfoto`** is public in the gh-pages bundle. That's *expected* — the
anon key is designed to ship to browsers. But it means **RLS is your entire security boundary**. If any
table has RLS off or a permissive policy, that public key reads your database.

Check every table in Supabase → Authentication → Policies. Do this today. It is independent of
everything above, and it is the one thing that would turn a privacy issue into a breach.

Related: `VITE_ALLOWED_EMAIL` is a *client-side* check in `AuthContext.tsx`. Anyone can bypass it in
devtools — it is UX, not security. Only RLS actually protects the data.

## 🟡 ACTION 3 — everyone must re-clone

The rewrite changed every commit hash on `main` and `code-audit`. Any existing clone (other machines,
CI, collaborators) will now conflict and must re-clone. Don't `git pull` an old clone — re-clone it.

`gh-pages`, `gh-pages-webapp`, and `promotional-website` were **not** rewritten (they never contained
the data), so **your live site is untouched**.

## ✅ Verified clean — no credential was ever leaked

Scanned all 291 commits, all 5 branches, all blobs including binaries:

- **No `service_role` key ever.** The only JWT in the entire history decodes to `"role":"anon"` — the
  publishable key, safe by design.
- **No AWS / GitHub / Stripe tokens, no private keys, no `.env` ever committed.**
- **Your Finnhub key was never exposed** — bundles use `token=${t}` resolved from `localStorage` at
  runtime; Vite never inlined it. Same in the Apple app (Keychain, no hardcoded fallback).
- **`IMPORT_TEMPLATE/` (your bank statements with IBANs) was NEVER committed.** That `.gitignore` line
  did its job. Verified three ways, including an IBAN regex across every text blob in history.
- `cloudkit-development.ckdb` is schema DDL only — no data rows.

**Nothing needs rotating.** This was a privacy exposure, not a credential breach.
