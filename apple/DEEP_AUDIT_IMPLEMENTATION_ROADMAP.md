# Deep-Audit Implementation Roadmap (Apple app)

**Purpose.** This is the single source of truth for *continuing* the remediation of the findings in
[`IOS_MACOS_DEEP_AUDIT.md`](./IOS_MACOS_DEEP_AUDIT.md). It captures what's done, what's next, the
decisions already locked, and the exact workflow to follow — so any agent can pick up mid-stream with
full context. Read this **and** [`apple/CLAUDE.md`](./CLAUDE.md) before touching code. Per-finding
problem/impact/fix detail lives in `IOS_MACOS_DEEP_AUDIT.md` (IDs `DA-H##`, `DA-M##`, `DA-L##`).

---

## 1. Status at a glance

- **High tier (14 findings): ✅ 100% done and merged to `main`** (`origin/main` @ `647a92f`), in three commits:
  - `fix(apple): deep-audit High money-correctness batch (H05,H07,H09,H11,H13,H14)`
  - `fix(apple): deep-audit High decode/data-loss batch (H08,H10,H12)`
  - `fix(apple): deep-audit High lock/privacy batch (H01,H02,H03,H04)`
- **Medium tier (31 findings):** 9 implemented + 2 already-fixed by the High work = **11/31**; **20 remain** (one of which, M31, is deferred). Remaining ≈ **19 to implement**.
- **Low tier (62 findings):** not started; all documented as `DA-L01…L62` in `IOS_MACOS_DEEP_AUDIT.md`. Future work.

### Medium — done (9), on branch `fix/medium-a11y-privacy` (NOT yet built or merged)
Branch has 4 commits off `main`, **not pushed to origin**, **not yet verified on a real build**:
| Commit | Findings |
|---|---|
| `09e7c48` | **M05** (macOS card VoiceOver), **M07** (segmented-picker a11y+keyboard), **M30** (privacy-mode share-% redaction) |
| `da41371` | **M08** (custom category preserved on type toggle, 4 editors), **M10** (individual-holding gain/loss % uses `abs(costBasis)` + zero-guard) |
| `a95e920` | **M09** (holdings never save with a zero current price — blank falls back to cost, both-blank blocked, 4 editors) |
| `1855d0a` | **M06** (memoized transaction sort keyed by `dataVersion`), **M25** (CoinGecko `/search` pacing 0.5s), **M26** (snapshot/save only on a real price change via `didChangeData`) |

### Medium — already fixed by the High batches (no work)
- **M03** (macOS privacy shield) → done by Batch 3 (`MacPrivacyShield` + lock-only-on-`.background`).
- **M12** (`Decimal(finite:)` returns NaN) → done by H09.

---

## 2. ⚠️ IMMEDIATE NEXT ACTION

The 9 Medium fixes on `fix/medium-a11y-privacy` are **implemented but unverified**. First:
1. Check out `fix/medium-a11y-privacy` and **build both schemes + run the test suite** (commands in §4). Fix any compile errors (these were written on a CommandLineTools-only box — see §4).
2. Smoke-test the UI-affecting ones (M05/M07 VoiceOver, M30 Privacy Mode, M08/M09 editors).
3. When green, **land the branch on `main`** using the clean flow in §3, then continue with the next batch (§6, start with **M4**).

---

## 3. Workflow & git rules (follow exactly — this is how the whole audit has been run)

- **Feature branch per themed batch; never commit directly to `main`.** Implement → the human builds/tests on their Mac → fix to green → commit the theme → land on `main`.
- **Verify-then-commit.** Do not consider a batch done until the human confirms a green build/test on real Xcode.
- **Landing on `main` (clean fast-forward, no merge commits, no history pollution):**
  ```bash
  git commit --amend -F <clean-msg>   # if the tip commit has a throwaway message; else skip
  git checkout main
  git merge --ff-only <branch>        # main must be a linear ancestor; these branches are
  git push origin main                # normal push (fast-forward)
  git branch -D <branch>              # delete local
  git push origin --delete <branch>   # delete remote (if it was pushed)
  ```
- **Commit messages:** conventional (`fix(apple):`, `perf(apple):`, `chore(apple):`). **Never** add a `Co-Authored-By:` / "Generated with" trailer (repo owner's standing rule).
- **Never commit build/test artifacts.** `apple/.gitignore` already ignores `*.xcresult`, `*.xcresult.zip`, `/TESTS/`, `build/`, `DerivedData/`. A 195 MB `apple/TESTS` xcresult folder was accidentally committed once and had to be purged with a force-push — do not let it recur. Keep an eye on `git status` before every `git add`; prefer explicit `git add <paths>` over `git add -A`.
- **Update `apple/DOCUMENTATION.md`** with a dated entry per batch (append at the top; existing format).
- **`TO_SIMO_DO.md`** (repo root): only append if the human must take a *manual* action (env var, provisioning profile, API key). Otherwise leave it.

---

## 4. Build / test constraints & gotchas

- **This repo is developed on two machines.** The agent's box has **CommandLineTools only** (no full Xcode) → **cannot `xcodebuild`**. All builds/tests happen on the human's Mac. Hand them exact commands.
- **SourceKit "Cannot find type 'X' in scope" diagnostics are almost always noise** here — single-file analysis can't see other files in the same module (`FinanceStore`, `AppSettings`, `WCColor`, `AllocationSlice`, etc. all resolve in a real build). A genuine error looks different (wrong arg label, missing member on a type that *is* in-file). If a SwiftUI view body ever reports *"unable to type-check this expression in reasonable time,"* that can be real on a large body — break it up.
- **Build & test commands (run from `apple/`):**
  ```bash
  xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
    -destination 'platform=macOS' build
  xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
    -destination 'generic/platform=iOS Simulator' build
  xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
  Tests are hosted by `WealthCompassMobile` (XCTest, `@testable import WealthCompassMobile`).
- **Edit precisely.** Many editors share identical lines (e.g. `isSaveDisabled`, `parsedCurrentPrice`); use `replace_all` deliberately or add unique surrounding context. There are **four** transaction/holding editors that often need the same change: `MacEditorSheet` (MacInvestmentEditor + MacCryptoEditor), `MacRecurringTransactionEditor`, and iOS `Forms.swift` (TransactionFormView, RecurringTransactionFormView, InvestmentFormView, CryptoFormView).

---

## 5. Decisions already locked (do NOT re-litigate)

- **M31 (CloudKit push sync): DEFERRED** — it's a feature (re-add `aps-environment` entitlement → provisioning-profile change, `remote-notification` background mode, `registerForRemoteNotifications` + `didReceiveRemoteNotification` → `CKSyncEngine`, BGTask refresh). Do it as its own focused effort, not in a bug-fix batch. Sync works on foreground/manual today.
- **M22/M23 (retroactive snapshot FX): "same-currency deltas only"** — apply `adjustHistoricalSnapshots` deltas only when the transaction currency equals the snapshot's captured base currency (no-op FX case). For a genuine foreign-currency back-dated edit, **skip the historical mutation** and let H11's render-time reconversion (each `NetWorthSnapshot` now carries a `currency`) handle display.
- **M17 (biometric enrollment change): "require passcode re-confirm"** — on unlock, if `evaluatedPolicyDomainState` differs from the stored baseline, require the device passcode / app password once, then re-baseline.
- **Minor defaults (confirmed):** M01/M13 → derive `maximumFractionDigits` from the value's own scale (cap ~18–20); M11/M20 → convert using the record's own currency; M15/M16 → memoize + downsample long ranges to ~365 pts; M25 → mirror the investments-loop pacing (done); M29 → stable unique slice id, keep per-holding wedges.
- **M09 shape (already implemented):** blank current price falls back to the entered average/cost price on save (holding shows at cost until a refresh); both-prices-blank is blocked. **M10 shape:** individual-holding gain/loss % divides by `abs(costBasis)` with a `!= 0` guard; aggregate summaries sum non-negative cost bases so their `> 0` guard was left as-is.

### Intentional design decisions — DO NOT "fix" these (they are not bugs)
- iOS + macOS intentionally share bundle id `com.wealthcompass.mobile`.
- Dark-only; iPhone portrait-only; `.preferredColorScheme(.dark)` + re-`.id(...)` on language change are intentional.
- JSON import decoders (`Imported*`, `LossyArray`) are intentionally lossy/forgiving — **extend, don't tighten**.
- External APIs (Frankfurter/Finnhub/CoinGecko, + Yahoo keyless fallback) are called **directly** from the device; keys travel as request headers over HTTPS by design.
- Money is `Decimal`; drop to `Double` only at Swift Charts plot points and inside FX conversion. The zero/NaN/Inf guards in `AppSettings.convert` and `CurrencyConverter` are intentional.

---

## 6. Remaining Medium work (≈19 findings, in suggested batch order)

Full detail per finding is in `IOS_MACOS_DEEP_AUDIT.md`. Locations below are relative to
`apple/WealthCompass/` and were accurate at audit time — **re-read the cited code before editing**,
line numbers drift.

### Batch M4 — money / import / correctness (do first; mostly clean, high value)
- **M11** `Sources/Shared/Services/FinanceImportService.swift` — imported currency-less crypto/investment holdings default to USD. **Fix:** thread `settings.currency` into `ImportedCryptoHolding.model()` / `ImportedInvestment.model()` so a missing currency defaults to the base currency (mirror how `Liability`/`Transaction` import already do it).
- **M19** `FinanceImportService.swift:~171` — merge-import always overwrites existing rows because imported transactions get `updatedAt = import time`. **Fix:** preserve the imported record's *original* `updatedAt` from the source JSON so `mergedByID` recency comparison is meaningful. (Stay forgiving — extend the decoder.)
- **M20** `Sources/Shared/Services/RecurringNotificationService.swift:~73` — due-notification stamps the *display* currency code onto the schedule's amount and never converts. **Fix:** convert `schedule.amount` from `schedule.currency` to the display currency at the `@MainActor` call sites (via `settings.convert`) and label in display currency.
- **M21** `Sources/Shared/Services/RecurringScheduleBuilder.swift:~50` — editing a lapsed (auto-deactivated) schedule doesn't reactivate it unless frequency/startDate changes. **Fix:** on saving an edit, reactivate (recompute `nextDueDate`, set active) regardless of which field changed.
- **M24** `Sources/Shared/Stores/FinanceStore.swift:~389` — recurring dedupe's 1-second tolerance misses re-imported occurrences → double-generates transactions + double-adjusts snapshots. **Fix:** match on `recurringTransactionID` + occurrence *day* (or a wider tolerance) instead of a 1s window.
- **M22 / M23** `FinanceStore.swift:~244` (`adjustHistoricalSnapshots`) — see locked decision in §5 (**same-currency deltas only**; use the new per-snapshot `currency`).
- **M28** `FinanceStore.swift:~907` (`importBackup`) — mutates in-memory data and reports success even when a load-time `localPersistenceError` makes `save()` a silent no-op. **Fix:** check for the persistence error and surface a real failure instead of false success.
- **M01 / M13** `Sources/Shared/Models/MoneyDecimal.swift:~78` (`AmountInputFormatter.string(Decimal)`) — hardcoded `maximumFractionDigits = 8` truncates high-precision crypto/investment quantities on a no-op editor round-trip. **Fix (default):** derive `maximumFractionDigits` from the value's own scale, e.g. `max(8, -value.exponent)` clamped to ~18–20. (Also consider not overwriting an *unedited* stored high-precision `Decimal` on save; minimal fix is the cap.)
- **M18** `Sources/Shared/Services/CloudKitSyncService.swift:~1836` — `.serverRejectedRequest` lumped into `.recordGone` → unbounded clear+requeue loop reported as "Up to Date". **Fix:** separate `.serverRejectedRequest` from `.recordGone`; treat a persistent rejection as a real, bounded failure (surface it) rather than looping.
- **M29** `Sources/Shared/UI/DesignSystem.swift:~283` (`AllocationChart`) — slice *name* used as identity → duplicate-named crypto slices double-highlight on hover and collide in the legend `ForEach`. **Fix (default):** give `AllocationSlice` a stable unique `id` (UUID / source holding id) and key chart+legend+hover on it.

### Batch M5 — security
- **M02** `Sources/macOS/MacPlatformServices.swift:~95` + `Sources/Shared/Services/BiometricLockStore.swift` — `MacLockView.task` auto-fires the biometric prompt on every appearance and races the manual Unlock button. **Fix:** one-shot `hasAutoPrompted` guard on the `.task`; `.disabled` the Unlock button while authenticating; `isAuthenticating` serialization flag in `BiometricLockStore.unlock/authenticate`. Apply the same to iOS `LockView.swift`.
- **M14** `Sources/Shared/Persistence/FinancePersistence.swift:~87` — legacy-file-migration `copyItem` doesn't apply complete-until-open file protection. **Fix:** set `.completeFileProtectionUnlessOpen` on the migrated DB (match `write()`).
- **M17** `BiometricLockStore.swift:~110` — see locked decision in §5 (**passcode re-confirm on enrollment change**); store `evaluatedPolicyDomainState` as the baseline.

### Batch M3-rest — performance / charts (more involved; do carefully)
- **M04** `Sources/macOS/Views/MacCashFlowView.swift:~320` — cash-flow BarMarks + hover key on the short `"MMM"` `monthLabel`, collapsing same-month-different-year columns on the 12M range and mis-reporting hover. **Fix:** key the chart on a unique value (the month's `Date` or `monthKey` "yyyy-MM") and use `monthLabel` only for the axis label (temporal axis, or `.chartXAxis` custom `AxisValueLabel`). `AnalyticsEngine.cashFlowTrend` already computes the month `Date`; thread it into `CashFlowMonth`. **Check iOS `CashFlowView` for the same chart.**
- **M15 / M16** `Sources/Shared/Services/AnalyticsEngine.swift:~140` (`carryingForwardDailyGaps`) — materializes one point per calendar day over *full* history on every dashboard render for range `.all` (uncapped, uncached). **Fix:** cap/downsample long spans (e.g. > ~365 days → weekly/monthly buckets or stride to ~365 points) **and** memoize `snapshotsForChart` on `FinanceStore` keyed by `(dataVersion, currency, rateStamp, range)` (mirror `cachedTotals`).
- **M27** `FinanceStore.swift:~756` — `monthlyCashFlow` / `expensesByCategory` / `cashFlowTrend` are recomputed on every hover/resize (uncached). **Fix:** memoize each on `FinanceStore` keyed by `(dataVersion, currency, rateStamp, period/month)` like `cachedTotals`. (M06 already cached the transaction sort, which partially helps.)

### Deferred — feature
- **M31** — CloudKit push sync. See §5. Its own effort; needs a provisioning-profile change (note in `TO_SIMO_DO.md` when tackled).

### After Medium → Low tier
62 findings `DA-L01…L62` in `IOS_MACOS_DEEP_AUDIT.md` (polish, latent traps, minor localization/a11y, dead code). Batch by theme the same way; most are mechanical.

---

## 7. Architecture pointers (see `apple/CLAUDE.md` for the full version)

- Two SwiftUI targets + shared core: `Sources/Shared/` (Models/Persistence/Services/Stores/UI) compiles into both; `Sources/iOS/` (TabView), `Sources/macOS/` (sidebar + `MacAppModel`).
- State: `@MainActor` `AppSettings` (prefs + FX + owns currency conversion) and `FinanceStore` (the *only* place `FinancialData` is mutated; every mutating method ends in `save()`, and `save()` **is** the sync pipeline). `CloudKitSyncService` is an `actor`.
- `dataVersion` on `FinanceStore` bumps on every `data` mutation — the correct cache-invalidation key (used by `cachedTotals`, `cachedCloudSyncSnapshot`, and now `cachedSortedTransactions`). Reuse it for M15/M16/M27 caches.
- Localization dual-API: `var title: LocalizedStringKey` only inside `Text(...)`; use `AppLocalization.string(_:appLanguage:)` / `func localizedTitle(appLanguage:)` everywhere a resolved `String` is needed (pass `settings.appLanguage`).
- Money is `Decimal` end-to-end; `NetWorthSnapshot` now carries an optional `currency` (H11) — use it for M22/M23.
