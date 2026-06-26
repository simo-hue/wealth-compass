# Audit Implementation Progress — `IOS_MACOS_BUG_AUDIT.md`

Branch: `audit-fixes`. Implementing **all 51 items**. No Xcode here (CommandLineTools only) →
verify via the steps in `TO_SIMO_DO.md` (items 22–25). Per-theme commits.

## Design decisions (from the grill session)
- WC-A1: `Double`→`Decimal` for money **and quantity**; aggregate totals Decimal. Chart structs
  (`NetWorthPoint`/`AllocationSlice`/`CashFlowMonth`/`CategoryTotal`), FX rates, and all %/ratios stay `Double`.
- Decimal→Double only at (1) Swift Charts plot points and (2) inside FX conversion. Helper:
  `Decimal.doubleValue` + `MoneyParser` in `Sources/Shared/Models/MoneyDecimal.swift` (NEW FILE).
- WC-M1: `currency` on `Transaction`/`RecurringTransaction` (optional; `nil`=legacy, read as `?? base`,
  one-time backfill in `FinanceStore.load`). Currency **picker** in editors; convert per-tx before summing.
- Behavior changes to apply: WC-L2 (passcode fallback), WC-L3 (auth to disable lock), WC-L26
  (blur on .inactive + lock on .background), WC-L5 (9am for date-only notifs). KEEP Mac sidebar Settings
  (WC-M12 → only remove stray "Refresh Data" button).

## DONE (Batch 1 — shared core, Decimal migration)
- [x] `MoneyDecimal.swift` (new): `Decimal.doubleValue`/`isFinite`/`init?(finite:)`, `MoneyParser` (verified w/ swift).
- [x] `FinanceModels.swift`: all money+quantity → Decimal; `currency` added to Transaction/Recurring; gainLossPercent/savingsRate use `.doubleValue`.
- [x] `CurrencyConverter.swift`: Decimal `convert` overloads.
- [x] `AppSettings.swift`: Decimal convert/format/private overloads; WC-L22 (reset clears biometric key) + WC-L23 (language picker locale+sort).
- [x] `AnalyticsEngine.swift`: per-tx currency conversion (WC-M1), Decimal sums→Double at chart boundary; WC-L12 (deleted spendingTimeline).
- [x] `SnapshotEngine.swift`: liquidityDelta Decimal; WC-L9 (backfill most-recent days).
- [x] `FinanceStore.swift`: Decimal signatures (add/update/delete tx now take `currency`), recurring inherits currency, snapshot deltas FX-converted, market price Double→Decimal at boundary, WC-M1 backfill in load()+init, deleted spendingTimeline wrapper.
- [x] `FinanceImportService.swift`: wrap construction args in `Decimal(...)`; liquidity uses Decimal convert.
- [x] `RecurringNotificationService.swift`: Decimal currency format; WC-L31 (hoist appLanguage read).
- [x] `MarketDataService.swift`: no change needed (network DTOs stay Double).

## DONE (Batch 1 — VIEWS migrated)
- [x] iOS: `Forms.swift` (MoneyParser + finite guard WC-H1/M9; currency picker in tx + recurring editors),
  `CashFlowView`, `DashboardView`, `CryptoView`, `InvestmentsView` (ValueDelta `.doubleValue`, reduce `Decimal(0)`),
  `SettingsView` (convert(1) → `: Double` to break overload ambiguity). All `addTransaction`/`updateTransaction`/
  analytics call sites thread `currency:`/`settings:`.
- [x] macOS: `MacEditorSheet` (3 editors + tx currency picker + save `>0` guard closing WC-H1), `MacCashFlowView`
  (duplicate editor + WC-M10 localize category), `MacRecurringTransactionEditor`, `MacDashboardView`,
  `MacInvestmentsView`, `MacCryptoView`, `MacSettingsView` (convert(1) ambiguity).
- [x] `RecurringScheduleBuilder.build` takes `amount: Decimal` + `currency`.
- [x] `project.pbxproj`: `MoneyDecimal.swift` wired into BOTH targets (Python insert, plutil OK). Backup at `.bak`.
- [x] Verified: 0 leftover `Double(...replacingOccurrences)` parses; all 6 tx-calls + 2 builder-calls carry `currency:`;
  no bare-literal ambiguity in format overloads; notification services handle no money.

## NEXT STEP (immediate)
**Batch 11 — Tests**: update the 7 XCTest files (Double money literals → Decimal) + add regressions for
WC-H1 (MoneyParser rejects inf/nan), WC-M1 (per-currency conversion in calculateTotals), WC-M9 (locale parse),
WC-H3 (undecodable remote record skipped). Tests reference `@testable import WealthCompassMobile`.
Then the remaining batches: **sync hardening** (WC-H3/H4/M2/M3/L29 in CloudKitSyncService), **persistence perf**
(WC-M4 cached coders/formatters, L27, L28), **services** (L5/L6/L7/L8/L10/L11), **localization** (WC-H2 SettingsRow,
M11, L4, L18, L19, L21 regen), **security/lock** (L2/L3/L26/M6), **macOS dedup** (M5/M8/M12-partial/L16/L17/A2),
**iOS perf/a11y** (M13/L1/L24/L25/L15), **shared UI** (L13/L14/L20), **docs** (WC-A3).

## Notes
- SourceKit diagnostics here are SINGLE-FILE: any "Cannot find X in scope" / "has no member doubleValue"
  for a cross-file symbol is a FALSE POSITIVE. Only same-file Decimal/Double mismatches are real.
- The 4 transaction-type import models all used `amount: amount,` → bulk-converted to `Decimal(amount)`.
