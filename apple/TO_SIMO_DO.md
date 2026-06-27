# Manual Actions Required

> **⚠️ Items 1–2 below are OBSOLETE as of the P1 fix H1 (2026-06-22).** The app no
> longer uses the Cloudflare Worker proxy — `ExchangeRateService`/`MarketDataService`
> now call Frankfurter/Finnhub/CoinGecko directly. You do **not** need to deploy or
> point at the proxy anymore. See the P1 section (item 7) for the optional proxy retirement.

1. ~~**Deploy the Cloudflare Worker**~~ *(obsolete — proxy removed in H1)*:
   - Open your terminal and navigate to `/Users/simo/Developer/wealth-compass/proxy`
   - Run `npx wrangler deploy`
   - Copy the URL provided in the terminal output (e.g., `https://wealthcompass-api-proxy.YOUR_USERNAME.workers.dev`).

2. ~~**Update the Swift App Configuration**~~ *(obsolete — proxy removed in H1)*:
   - Open `/Users/simo/Developer/wealth-compass/apple/WealthCompass/Sources/Shared/Services/APIConfiguration.swift`.
   - Replace the `proxyBaseURL` value with the URL you copied from step 1.
   - Build and test the app to ensure data still loads correctly.

## P0 audit fixes (2026-06-22) — follow-ups

3. **Build both schemes in Xcode (could not be done in the agent environment — no Xcode, CommandLineTools only).**
   - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build`
   - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build`
   - Source edits passed `swiftc -parse` and plists passed `plutil -lint`, but a full type-checked build still needs confirming before shipping.

4. **Review and commit the staged changes.** The P0 work is left uncommitted: the `build/` untrack (6,646 staged deletions) plus modified Swift/plist/pbxproj files. Review `git status` / `git diff --cached`, then commit (consider branching off `main` first).

5. **Provisioning (C4):** the `aps-environment` (Push) entitlement was removed from both targets. With automatic signing this is seamless; if you use **manual** provisioning profiles, regenerate them without the Push Notifications capability. (CloudKit/iCloud is unchanged.)

6. **Optional cleanup:** the on-disk `apple/WealthCompass/build/` folder is now untracked + gitignored; you can delete it to reclaim space (`rm -rf apple/WealthCompass/build`).

## P1 audit fixes (2026-06-22) — follow-ups

7. **Retire the Cloudflare Worker proxy (`../proxy/`) — optional, your call.** H1 made the
   app call providers directly, so the worker is now unused by the Apple apps. I did **not**
   delete it (it's shared infra outside `apple/`, and deletion is hard to reverse). If nothing
   else depends on it, you can `npx wrangler delete` it and remove `../proxy/`. The
   `CLAUDE.md` note about "update both if you change `proxyBaseURL`" no longer applies.

8. **Build both schemes in Xcode — I could NOT run a full build (no Xcode here, CommandLineTools only).**
   - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build`
   - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'`
   - What I *did* verify: a full Swift **type-check of the entire macOS target + all Shared code passed with 0 errors** (`swiftc -typecheck` against the macOS SDK), and the 3 iOS-only changed files passed `swiftc -parse`. Confirm the real iOS build before shipping.

9. **New user-facing strings need translation.** I added strings (e.g. "Save Failed", "Configured",
   "Enter a new key to replace…", the rewritten privacy/onboarding copy, the persistence-error
   message). Open the project in Xcode once and build so the string catalog
   (`Sources/Shared/Resources/Localizable.xcstrings`) auto-extracts them, then translate. They work
   untranslated (English shows as the fallback) but won't be localized until added to ~40 languages.

10. **Finnhub stock currency is still assumed to match the user's selection.** Finnhub `/quote`
    doesn't return a currency, so an investment's live price is interpreted in whatever currency the
    user picked in the investment form (the form already has a currency picker — the user controls it).
    If you want automatic detection later, add a `/stock/profile2` lookup (one extra call per symbol —
    weigh against the existing rate-limit/perf concerns in M7). Documented, not changed, under H3.

11. **Review and commit the P1 changes.** Left uncommitted on `main`. Files touched:
    `Shared/Models/FinanceModels.swift`, `Shared/Services/{APIConfiguration,ExchangeRateService,MarketDataService}.swift`,
    `Shared/Stores/FinanceStore.swift`, `Shared/UI/DesignSystem.swift`,
    `iOS/{ContentView,Views/Forms,Views/OnboardingView}.swift`,
    `macOS/{MacRootView,Views/MacEditorSheet,Views/MacOnboardingView}.swift`. Consider branching off `main` first.

## P2 audit fixes (2026-06-22) — partial, follow-ups

12. **Build both schemes AND run the new unit tests.** I added **11 new Swift source files + 5 new test files** to
    `project.pbxproj` by hand (validated with `plutil -lint` + a reference-consistency script — no Xcode here).
    **Open the project once to confirm it still opens and builds**, then run the tests:
    `xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'`.
    The 5 new suites (`CurrencyConverterTests`, `SnapshotEngineTests`, `RecurringScheduleBuilderTests`, `AnalyticsEngineTests`, `FinanceImportServiceTests`)
    were written + parse-checked but **never executed** (the test target `@testable import`s the iOS module, unbuildable in this env) —
    a few date/backfill-count assertions are my best reasoning and may need tweaking on first run.

13. **P2 is COMPLETE** (M1, M2, M3, M5, M6, M7, M8 + tests T1–T5). **M4** (incremental SwiftData/SQLite store) is the only
    deferred item, by your earlier choice — tackle it as a standalone effort when ready. Onboarding + settings now share
    `OnboardingViewModel` / `SettingsViewModel` (logic only; native presentation kept per platform).

14. **macOS Settings is now ⌘, only (M6).** Settings is no longer a sidebar row — confirm you're happy reaching it via the
    standard ⌘, / "Wealth Compass ▸ Settings…" menu. The ⌘5 shortcut was removed.

15. **Smoke-test the deduplicated platform services (M2) — I can't run them.**
    - **Notifications:** create a recurring transaction with "Notify When Due" + a near-future date on **both** iOS and macOS; confirm the local notification still fires and tapping it opens the app. Note: macOS now also **requests badge permission** and a notification body has minor reworded text (both intentional convergence onto the shared `RecurringNotificationService`).
    - **Biometric lock:** enable the lock in Settings, background/relaunch, and confirm Face ID/Touch ID unlock still works on **both** platforms. iOS and macOS keep **separate** lock settings (different UserDefaults keys), so enabling on one must not affect the other.
    - **Onboarding (`OnboardingViewModel`):** run onboarding on **both** platforms — paste a valid + an invalid API key, confirm validation/save/"Configured" badge/skip all behave as before. The state now lives in the shared view model.
    - **Settings credential editor (`SettingsViewModel`):** in Settings, add/replace a Finnhub + CoinGecko key on **both** platforms; confirm the "live quote/price" success message and the failure alert still appear (validation logic is now shared).

## iCloud sync crash fix (2026-06-22 20:56) — follow-ups

16. **Rebuild + verify the iCloud-sync crash fix on a real iCloud device — I could NOT build or run it here (no Xcode, CommandLineTools only).**
    - The fix is a one-liner in `Sources/Shared/Services/CloudKitSyncService.swift` (`stopAfterFatalError`): `cancelOperations()` is now wrapped in `Task.detached`. It compiles only with Xcode.
    - Build both schemes:
      - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build`
      - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build`
    - **Runtime test (the real verification):** on a device/Mac signed into iCloud with existing Wealth Compass data in the cloud, toggle iCloud sync **on** on **both** macOS and iOS. Before: instant crash (`EXC_BREAKPOINT`, CKSyncEngine re-entrancy). After: no crash — sync either completes or, if a record handler still throws, shows a non-fatal "Sync Error" status.
    - This was an App Store build (1.0.5/6); ship the rebuilt binary (bump `CURRENT_PROJECT_VERSION`) so affected users stop crashing.

17. **Recommended next: make sync resilient, not just non-crashing (`WealthCompass/TO_IMPROVE.md` #6).** The crash fix stops the process abort, but `handleEvent` still tears the engine down on ANY thrown error (e.g. one remote record that fails to decode / has no `payload`). If your Mac was crashing because an iPhone/web-uploaded record won't decode, sync will now *stop with an error* instead of working. Implement #6 (log+skip a bad record instead of `throw`) so a single bad record can't halt sync. I did not do this (it changes sync semantics and I can't runtime-test it here).

## iCloud sync error classification (2026-06-23) — follow-up

18. **Translate the 3 new sync-error strings (`WealthCompass/TO_IMPROVE.md` #14).** Added to
    `Sources/Shared/Resources/Localizable.xcstrings` as English-only source entries — they fall
    back to English until translated (same as the existing `Exchange Rate Error` / `Keychain
    Error` titles):
    - `"The connection to iCloud was lost. Your changes are saved and will sync automatically when it is restored."`
    - `"iCloud is temporarily limiting sync requests. Sync will resume automatically in a moment."`
    - `"iCloud is still preparing your sync data. This usually resolves on the next sync."`
    Translate to the catalog languages when convenient (the sibling sync-error messages —
    network / quota / sign-in — already carry ar/de/es/fr/it/zh-Hans). Purely localization; no
    code or build action needed.

## Import summary popup (2026-06-23) — follow-up

19. **Translate the 5 new import-summary strings.** Added to
    `Sources/Shared/Resources/Localizable.xcstrings` as English-only source entries for the new
    "Import Complete" stats sheet (English fallback until translated): `"Done"`,
    `"Records imported"`, `"New categories"`, `"Records skipped"`, `"Snapshot generated"`. The
    category tile labels (Transactions/Recurring/Investments/Crypto/Liabilities/Snapshots) reuse
    existing translated keys. Purely localization; no code or build action needed.

## "Erase Everything" factory reset (2026-06-23) — follow-ups

20. **Verify the iCloud zone deletion end-to-end on a real signed-in device — I could only
    unit-test it against a mocked CloudKit database.** The new "Erase Everything" button
    (Settings → Data on iOS, Settings → Data → Danger Zone on macOS) deletes the whole
    `WealthCompassZone` server-side via `CKDatabase.deleteRecordZone`. To confirm the live
    behaviour: on a device signed in to iCloud with **sync ON and real data present**, open the
    CloudKit console (or a second device) to confirm the zone/records exist, tap **Erase
    Everything → confirm**, then verify (a) local data is gone and the app returns to onboarding,
    (b) the `WealthCompassZone` is gone from the CloudKit **private database**. Also test the
    offline path: turn on Airplane Mode with sync ON, tap Erase Everything, and confirm the
    "Couldn't Delete iCloud Data" dialog appears with **Retry** / **Delete This Device Only**
    (and that "Delete This Device Only" wipes locally while leaving the toggle/data abort intact).
    No CloudKit **schema** change is required — we only delete, no new record types.

21. **Translate the new "Erase Everything" strings (English-only source entries for now).** The
    UI strings (`"Erase Everything"`, `"Erase Everything?"`, the long confirmation messages,
    `"Couldn't Delete iCloud Data"`, `"Delete This Device Only"`, `"Retry"`) were auto-extracted
    into `Sources/Shared/Resources/Localizable.xcstrings` by the build; the three runtime
    `CloudSyncError` messages were added by hand with `extractionState: manual`
    (`"Couldn't reach iCloud to delete your data. Check your connection and try again."`,
    `"The iCloud data couldn't be deleted. Check your connection and try again."`,
    `"You're not signed in to iCloud, so there's no iCloud copy to delete."`). All fall back to
    English until translated. Purely localization; no code or build action needed.

## Full audit implementation — `IOS_MACOS_BUG_AUDIT.md` (2026-06-26, branch `audit-fixes`)

> This pass implements **all 51 items** from `IOS_MACOS_BUG_AUDIT.md`, including the big
> **`Double`→`Decimal` money migration (WC-A1)** and **per-transaction currency (WC-M1)**.
> I have **NO Xcode in this environment** (CommandLineTools only — `xcodebuild` unavailable,
> no simulators). I validated pure logic with the standalone `swift` compiler and used
> single-file SourceKit diagnostics to catch same-file type errors, but **a full build and the
> test suite could not be run here.** The items below are the verification you need to do.

22. **Build BOTH schemes in Xcode — REQUIRED before anything else.** The Decimal migration
    touches ~30 files; the first real cross-file type-check happens on your machine.
    - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build`
    - `xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build`
    - Expect a few residual `Decimal`/`Double` mismatches the single-file linter couldn't see
      across files. Paste any compiler errors back to me and I'll fix them.

23. **Run the unit tests** (updated to Decimal + new regressions for WC-H1/H3/M1/M9):
    - `xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'`

24. **A new shared source file was added: `Sources/Shared/Models/MoneyDecimal.swift`** (Decimal
    helpers + `MoneyParser`). It must be in BOTH app targets' Compile Sources. I will wire it into
    `project.pbxproj` by hand; confirm Xcode sees it in both targets when you open the project.

25. **Runtime-verify the money migration on a device with REAL existing data + iCloud sync:**
    - Existing transactions/investments load with correct amounts (Decimal decodes old JSON numbers).
    - Net worth / totals match what they were before.
    - Change base currency in Settings → confirm cash/liquidity now re-converts (the WC-M1 fix).
    - First launch after update performs a one-time currency backfill (legacy rows stamped with
      base currency) and re-syncs those records once to iCloud — expect a small one-time sync.

26. **New localizable strings (WC-L18) need translation.** Two singular/plural keys were added for
    the macOS "Recurring Transactions Added" alert: `"1 due transaction was added to Cash Flow."`
    and `"%lld due transactions were added to Cash Flow."` They fall back to English until added to
    `Localizable.xcstrings`. Build once so Xcode auto-extracts them. (WC-L4 added no new keys; WC-L21
    tab translations live in `scripts/add_tab_bar_localizations.py` and are already generated — some
    Latin-script locales still show English "Investments", left as fallback rather than guessed.)

27. **More new localizable strings (Medium batches) need translation.** English-only until added
    to `Localizable.xcstrings` (build once to auto-extract): `"Turn off app protection for Wealth
    Compass."` (WC-L3 disable-lock prompt). The privacy shield, a11y labels, and toolbar changes
    add no user-facing copy beyond existing keys.
