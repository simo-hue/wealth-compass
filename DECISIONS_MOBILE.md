# Decisions needed — iPhone

Found by a deep scan on 2026-09-03. Everything here is **verified against source** and is a real defect
or a real inconsistency. It is in this file rather than fixed because the fix changes a working
feature's design, or has more than one defensible answer. Nothing already in `TO_SIMO_DO.md` is repeated.

Items marked ⇄ also affect iPad/Mac and appear in `DECISIONS_DESKTOP.md`.

---

## 1. Amount entry parses in the *system* locale while everything on screen uses the *in-app* locale ⇄

**P1 — silent 1000× money error. This is the most serious item in either file.**

`Sources/iOS/Views/Forms.swift:31,75,239,267,696,700,887,891` — all eight call sites take the default
`locale:` of `MoneyParser.decimal` / `AmountInputFormatter.string`
(`Sources/Shared/Models/MoneyDecimal.swift:44,86`), which is `Locale.current`. Every *display* path pins
`settings.effectiveLocale` instead (`AppSettings.swift:131`), and `effectiveLocale` is built from the
**bare language code**, discarding the region.

On a **US-region iPhone with the in-app language set to Deutsch** the app prints `1.234,56 €`. In any
editor:

- typing `1.234,56` — the exact string the app just printed — leaves **Save greyed out**, and the
  recurring editor shows the *wrong* reason ("Enter an amount greater than zero.");
- typing `1.234`, meaning one thousand two hundred thirty-four, **saves 1.234** and redisplays as
  `1,23 €`. Silent, no warning, and it propagates into totals, snapshots and the iCloud copy.

Reproduced end to end in a script. The reverse configuration (German device, English in-app) fails the
same way, and a Swiss-German device (`de_CH`) whose owner picks "Deutsch" breaks with no language
mismatch at all. With **no** in-app override everything agrees — so this is strictly the override case,
which is a headline feature of the app.

Also affects the four Desktop editors, which call the same two helpers the same way.

**Why this is your call and not a patch:** on iOS the `.decimalPad` keyboard (`Forms.swift:99`) shows the
**system** locale's decimal separator and cannot be told otherwise. Parsing in the in-app locale would
put the parser out of step with the keys the user is actually given.

| Option | What it does | Cost |
|---|---|---|
| **A. Thread `effectiveLocale` into both helpers** at all 14 sites | Field matches every figure around it | On a US phone set to German, the keypad offers `.` while the field wants `,` |
| **B. Make `effectiveLocale` region-aware** — `Locale("\(lang)_\(Locale.current.region)")` | Display follows the device's number conventions, text follows the chosen language; keyboard stays honest | Changes how money *prints* for every override user |
| **C. Make the parse separator-agnostic** — last-separator-wins | Accepts `1.234,56` and `1,234.56` | Does **not** resolve bare `1.234`, which is genuinely ambiguous — must be paired with A or B |

**Recommendation: B, then C.** B is the smallest change that removes the contradiction without fighting
the keyboard, and C then makes paste and hardware-keyboard entry forgiving. `BrokerImportParsing.flexibleDecimal`
already implements C's rule in this codebase, and `TO_SIMO_DO.md` already wants it applied to the sibling
import defect at `FinanceImportService.swift:962` — so C closes both with one rule.

---

## 2. Privacy Mode makes finished recurring schedules permanently undeletable ⇄

**P2.** `Sources/iOS/Views/CashFlowView.swift:373` — the **Completed** disclosure is gated
`if !completed.isEmpty, !settings.isPrivacyMode`. Long-press → Delete inside that section is the *only*
route to `deleteRecurringTransaction` for a finished schedule (`finance.recurringTransactions` filters
`!$0.isCompleted`, so the live list can never offer it). Turn on Privacy Mode and the section vanishes
entirely — not covered, not tokenised, **absent** — and the record is stuck in the database and in iCloud
until Privacy Mode is turned back off. Live schedules stay deletable, so the two halves of the same card
disagree. Same gate on iPad/Mac (`MacCashFlowView.swift:598`).

The gate is doing real work — the section's *presence* announces that finished schedules exist — but it
re-creates, for the duration of Privacy Mode, exactly the irreversibility the section was added to
remove. The doc comment at `:363-367` says so in its own words.

**Options:** ① draw the section with redacted rows (control stays reachable, but a section that only
appears when something is finished is still an existence tell); ② draw the *header* unconditionally so
its presence carries no information, redacted rows inside; ③ add a delete route that does not depend on
the section — a swipe action, or a "Finished schedules" row in Settings; ④ accept and record it.

**Recommendation: ②.** It is the only option that closes both the leak and the trap. ③ is more work and
adds a surface; ① still leaks.

---

## 3. Transaction list includes future-dated rows on iPad/Mac and excludes them on iPhone ⇄

**P2.** `Sources/Shared/Models/FinanceModels.swift:282-289` clamps the upper bound unconditionally, and
iPhone routes through it (`CashFlowView.swift:640-662`). The Desktop keeps its own wider bound
(`MacCashFlowView.swift:1101-1150`). Enter a transaction dated next month: under **All Time** or **Year
to Date** the iPhone reads `Showing 7 of 8` and the iPad reads `Showing 8 of 8`. One dataset, two lists,
two counts. The shared model file names the disagreement in a comment, so it was known at the time and
never resolved.

**Options:** **A** — both clamp at today (iPhone's rule): the list then agrees with the analytics, the
Money Flow diagram and Recorded Cash on the same screen; cost is that future-dated entries vanish from
every period, which is the defect the Desktop deliberately avoided. **B** — both use the wider bound and
render future rows in grey; the PDF report already carries a
`%lld future-dated entries are listed in grey…` key for exactly this.

**Recommendation: B.** A transaction the user deliberately dated ahead should not silently disappear
from "All Time", and the report already established the grey-row idiom.

---

## 4. Per-row dates render in the clear under Privacy Mode

**P3.** `CashFlowView.swift:438`, `:687` and `DashboardView.swift:700` call the unredacted
`settings.date(…)`. With Privacy Mode on a row reads `Rent · Monthly · Next: 1 Oct 2026 at 09:00 · ••••`
— amount masked, exact date and time of day not. Two tabs over, Investments and Crypto rows mask theirs
to `••••` via `settings.privateDate(…)`, whose own doc says "a 'last updated' timestamp is itself data
about the account."

No DECIDED entry covers dates — your ruling was about ranked lists and their *order*, which is a
different thing — but it is close enough that I did not want to extend it on my own.

**Options:** route all three through `privateDate` (mechanical, matches the four sites `52c062a`
converted), or record that row dates are deliberately in the clear.

**Recommendation: redact them.** A schedule's due *time* is the finest-grained of the four and the one
`privateDate`'s comment singles out.

---

## 5. The iPhone recurring row hides the schedule's end date

**P3.** `CashFlowView.swift:419-446` shows category, frequency and next date. `MacCashFlowView.swift:693-723`
also shows `Ends 31 Dec 2026` / `No end date`, and the schedule's description. The end date is editable in
both editors and displayed on only one platform, so an iPhone-only user cannot see it without opening the
editor.

**Options:** add the end-date caption to the iPhone row (one line, both keys already exist), or record
that the iPhone row is deliberately the compact form.

**Recommendation: add it.** The end date is the one schedule property with no other read-only surface on
iPhone.

---

## 6. Money Flow, node drill-through and the category filter exist only on iPad/Mac

**P3 — product scope, not a defect.** The iPhone has no Sankey, no drill-through, and **no category
filter at all**: its transaction filters are type, period and free text only. Meanwhile the iPhone
Dashboard keeps a *Top Expense Categories* leaderboard that the Desktop retired when the Sankey landed
(`MacDashboardView.swift:922-924`) — so the two dashboards answer "where did the money go" with different
widgets.

Nothing blocks a port: `finance.cashFlowSankey(period:maxNodesPerSide:settings:)` is already in
`Sources/Shared`, `SankeyDiagramView` compiles for both platforms with its own privacy branch, and the
Desktop's category predicate is one line (`MacCashFlowView.swift:1117`).

**Options:** ① leave it — an iPhone column is genuinely poor for a Sankey; ② ship the **category filter
without the diagram** — the chip plus the predicate is the useful half and is screen-size-agnostic;
③ full parity.

**Recommendation: ②.** It closes the real gap (an iPhone user cannot filter by category at all) without
committing a Sankey to a 390pt column.

---

## 7. The same figure is called "Recorded Cash" on iPhone and "Total Cash" on iPad/Mac ⇄

**P3.** `DashboardView.swift:357-370` vs `MacDashboardView.swift:178-185` and `MacCashFlowView.swift:269-274`
— all three render the same `calculateTotals(settings:).totalLiquidity`. iPhone captions it *"Income less
expenses"*; on the Desktop that exact phrase is the caption of a **different** card, Net Savings
(`MacDashboardView.swift:147`). So one phrase names two different quantities depending on which device
you are holding.

**Recommendation: standardise on "Total Cash"** — two Desktop pages already use it and it carries 35
catalog entries against "Recorded Cash"'s 6 — and give the iPhone card a caption that is not the
Desktop's Net Savings phrase. Flagged rather than fixed because it changes user-visible wording.

---

## 8. Custom-category hint: iPhone capitalises the noun, iPad/Mac lowercases it ⇄

**P3.** The Desktop applies `.lowercased(with:)` to the *localized* noun at four sites
(`MacEditorSheet.swift:177`, `MacRecurringTransactionEditor.swift:161`, `MacCashFlowView.swift:1275,1430`);
the iPhone does not (`Forms.swift:62,367`, `CashFlowView.swift:772`). German on an iPad reads
*"…für zukünftige ausgabe Transaktionen"* — a German noun lowercased mid-sentence.

**Both of your Settings screens already ruled on this exact construction, the other way**
(`SettingsView.swift:582-587`, `MacSettingsView.swift:647-649`): "now that it is the **localized** noun,
lowercasing is wrong in the languages that capitalize nouns."

**Options:** **A** — drop `.lowercased(with:)` from the four Desktop sites, matching the ruling and the
iPhone; cost is a mid-sentence capital in English. **B** — keep it and add per-type full-sentence catalog
keys, which the Desktop comment says is the real answer; larger, a translation job.

**Recommendation: A now, B later.** What must not stand is one app doing each.
