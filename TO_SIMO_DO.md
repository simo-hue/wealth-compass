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
