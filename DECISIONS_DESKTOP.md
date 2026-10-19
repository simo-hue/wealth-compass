# Decisions needed — iPad and Mac

Found by a deep scan on 2026-09-03. Everything here is **verified against source** and is a real defect
or a real inconsistency. It is in this file rather than fixed because the fix changes a working
feature's design, or has more than one defensible answer. Nothing already in `TO_SIMO_DO.md` is repeated.

Remember `Sources/Desktop/` compiles into **both** app targets: it is the Mac app, and it is what an iPad
runs. Items marked ⇄ also affect iPhone and appear in `DECISIONS_MOBILE.md`.

---

## 1. Money Flow draws a blank ~280pt rectangle when a period has income but no expenses

**P2, iPad + Mac.** `Sources/Shared/UI/SankeyLayout.swift:243-273`, reached from
`Sources/Desktop/Views/MacDashboardView.swift:948-976`.

Pick a period with money in and nothing spent — a brand-new user who has recorded a salary, or "Last 7
Days" in a quiet week. The card renders its heading, its period picker, then **~280pt of empty space**,
then "TOTAL CASH FLOW EUR 3,000.00". No diagram, no empty state, no explanation. Switching to a period
with any expense makes it reappear, so it reads as an intermittent rendering failure.

Reproduced by compiling `SankeyLayout.swift` and `CashFlowSankey.swift` verbatim and calling `resolve` at
24 real card sizes — every one returned 0 nodes, 0 ribbons, 0 labels.

**Mechanism:** `AnalyticsEngine.cashFlowSankey` balances an income-only period by appending a `.surplus`
node, so `sankey.isEmpty` is `false` and the card's empty-state guard at `MacDashboardView.swift:949`
never fires. `resolve` then removes both columns — `.fanOut` drops the income side (`:243`) and `.surplus`
is never drawn (`:257`) — so `columnLoads` is empty and the guard at `:273` returns an empty `Resolved`.
`.full` mode is unaffected. `Tests/SankeyLayoutTests.swift` covers `.fanOut` only with a case that still
contains real expenses, which is why the suite is green.

**Options:** ① extend the empty-state branch to also fire when nothing is drawable
(`sankey.outflows.allSatisfy { $0.role == .surplus }`), with wording that says nothing was *spent* rather
than the current "No cash flow in this period", which would be false — costs one new string in 35 locales;
② fall back to `mode: .full` so the income column and hub are drawn — keeps the numbers on screen, costs
the narrow-card ribbon run `.fanOut` was chosen for; ③ scale `.fanOut` from `total` so the hub bar alone
draws — cheapest, but a lone bar with no ribbons is not obviously better than an empty state.

**Recommendation: ①.** It matches how the rest of the app handles "nothing to draw here", and the new
string is one line of honest copy. Whichever you pick, the blank box has to go.

---

## 2. The whole Desktop layer runs with Dynamic Type uncapped; the iPhone UI does not

**P3, iPad only** (macOS has no Dynamic Type).

`pageChrome()`'s A1 cap (`Sources/Shared/UI/DesignSystem.swift:785-803`) is applied to all four iPhone
pages and to **no** Desktop page. `metricCardColumns` collapses the iPhone grid to one column at
accessibility sizes; the Desktop grids are width-only (`MacDashboardView.swift:116-119` and three
`fillingFlexibleColumns` call sites). Nothing in `Sources/Desktop/` reads
`@Environment(\.dynamicTypeSize)` — grep returns zero.

At accessibility sizes on an iPad the metric cards clip. `MetricCard.value` has a `minimumScaleFactor`
floor of 0.62; its `detail` caption is `lineLimit(1)` with **no** scale factor at all
(`DesignSystem.swift:290-301`), so captions like "Income less expenses" truncate outright. The
fixed-height chart frames (238/244/210/200) don't grow either.

**Options:** **A** — apply the A1 cap to the Desktop pages; one line each, matches iPhone, lowest risk,
but an iPad user at AX4/AX5 then gets *less* enlargement than an iPhone user. **B** — make the Desktop
grids type-aware (thread `dynamicTypeSize` into `fillingFlexibleColumns` and `MacDashboardView.keyMetrics`);
better outcome, but it touches Mac layout, so it must be a verified no-op there.

**Recommendation: A now** — it stops the clipping today and is trivially reversible — **and B when the
Desktop grids are next opened.** A capped iPad is a regression against an uncapped one only in theory;
a clipped caption is a regression in practice.

---

## 3. Transaction list includes future-dated rows on iPad/Mac and excludes them on iPhone ⇄

**P2.** `MacCashFlowView.swift:1101-1150` keeps its own upper bound — `.all` returns `nil` (unbounded),
`.yearToDate` returns 31 Dec 23:59:59 — while the iPhone routes through the shared predicate
(`FinanceModels.swift:282-289`), which clamps at today unconditionally. Enter a transaction dated next
month: the iPad reads `Showing 8 of 8`, the iPhone `Showing 7 of 8`. The shared model file names the
disagreement in a comment, so it was known and never resolved.

Note the Desktop's own screen is internally inconsistent too: the row is listed, but Money Flow, the five
metric cards and Recorded Cash beside it all exclude it.

**Options:** **A** — both clamp at today; the list then agrees with everything else on the screen, at the
cost of future-dated entries disappearing from every period. **B** — both use the wider bound and render
future rows in grey; the PDF report already has a `%lld future-dated entries are listed in grey…` key.

**Recommendation: B.** A transaction the user deliberately dated ahead should not silently disappear from
"All Time", and the report already established the idiom.

---

## 4. Privacy Mode makes finished recurring schedules permanently undeletable ⇄

**P2.** `MacCashFlowView.swift:598` gates the **Completed** section on `!settings.isPrivacyMode`, and the
delete affordance inside it (`:788-793`) is the only route to `deleteRecurringTransaction` for a finished
schedule. Under Privacy Mode the record is stuck in the database and in iCloud until Privacy Mode is
turned off. Live schedules stay deletable, so the two halves of the same card disagree. Identical gate on
iPhone (`CashFlowView.swift:373`).

**Recommendation: draw the section header unconditionally** so its presence carries no information, with
redacted rows inside. It is the only option that closes both the existence leak and the trap. Full
options in `DECISIONS_MOBILE.md` §2.

---

## 5. Custom-category hint lowercases the localized noun on iPad/Mac only ⇄

**P3.** Four Desktop sites apply `.lowercased(with:)` to the *localized* noun
(`MacEditorSheet.swift:177`, `MacRecurringTransactionEditor.swift:161`, `MacCashFlowView.swift:1275,1430`);
the three iPhone sites do not. German on an iPad reads *"…für zukünftige ausgabe Transaktionen"*.

**Both Settings screens already ruled the other way on this exact construction**
(`MacSettingsView.swift:647-649`, `SettingsView.swift:582-587`): lowercasing the *localized* noun is wrong
in languages that capitalize nouns.

**Recommendation: drop `.lowercased(with:)` from the four Desktop sites**, matching the ruling and the
iPhone, and treat per-type full-sentence keys as the later, better fix. Full options in
`DECISIONS_MOBILE.md` §8.

---

## 6. "Total Cash" on iPad/Mac is "Recorded Cash" on iPhone ⇄

**P3.** Same `totalLiquidity` figure, two names. Worse, the iPhone captions it *"Income less expenses"*,
which on the Desktop is the caption of a **different** card — Net Savings (`MacDashboardView.swift:147`).

**Recommendation: keep "Total Cash"** (two Desktop pages use it; 35 catalog entries against 6) and change
the iPhone side. Flagged rather than fixed because it changes user-visible wording.

---

## Two things worth knowing that are not decisions

**`TO_SIMO_DO.md` has three checkboxes that are already done.** Verified against current source today:

- `MacCryptoView.swift:185` — the fixed 400pt performance card now reflows at `width >= 760` (`:152-186`).
- `MacCashFlowView.swift:661-737` — `transactionFilters` now has a three-rung `ViewThatFits` ladder
  (`:807-847`).
- `FinancePersistence.swift:72-81` — H08-skipped records surviving the next save: `save(_:preserving:)`
  and `encodeFinancialData(_:preserving:from:)` now exist and `PersistenceCoordinator` threads the skip
  set through both write paths.

**Two backlog entries cite files that no longer exist.** `MacPlatformServices.swift` was split into
`MacAppDelegate.swift` + `MacLockView.swift`, and the `WealthCompassMacApp.swift:60-94` commands moved to
`DesktopCommands.swift`. **Both underlying defects are still live** — only the paths are stale, so don't
read "file not found" as "fixed".

**`.disabled(...)` does not work in a `Commands` struct — this one cost a real detour and belongs in
`apple/CLAUDE.md`.** Proved with a signed throwaway `.app` driving real ⌘-key equivalents through
`NSMenu.performKeyEquivalent`: a menu item built by `.commands { }` is configured **once** and never
re-applied — not its `isEnabled`, not even its title — even though the builder demonstrably re-runs when
the observed value changes. It fails identically for `@ObservedObject`, a plain `Bool` read in
`App.body`, and `@FocusedValue`, and for both `CommandGroup(replacing:)` and `CommandMenu`.

That means the pre-existing `.disabled(finance.loadState != .loaded)` guards on every command were
already frozen at their launch value, and a first attempt to close the lock-screen hole the same way was
worse than the bug: because `BiometricLockStore.init` sets `isUnlocked = !isLockEnabled`, **every launch
for a user with the lock on** starts locked, which would have frozen ⌘N, ⌘⇧I, ⌘⇧K, ⌘E, ⌘1–5 and ⌘,
dead for the entire session on Mac *and* iPad.

The shipped fix gates inside each action closure at press time instead, which reads live state and
repairs the older WC-LOCK1 guard as a side effect. The cost is the greyed-out affordance — which never
actually worked. **Do not "restore" `.disabled` to those commands.**
