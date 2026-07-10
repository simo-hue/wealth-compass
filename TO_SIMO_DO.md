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
