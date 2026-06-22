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
