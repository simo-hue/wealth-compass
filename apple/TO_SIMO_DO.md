# Manual Actions Required

Actions that need you (or a real Mac / Xcode / App Store Connect) — Claude can't do these.

## From the 2nd-pass bug-audit remediation (2026-07-06)

- [ ] **Build both schemes + run the test suite** with the 8 new fixes (commit `fe37a65`). Not built
  here (CommandLineTools only). Paste anything red and I'll fix-and-reland.
      ```
      xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build
      xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build
      xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'
      ```
- [ ] **(Optional, safe) Delete the orphaned proxy:** `git rm -r proxy/` from the repo root. The
  `../proxy/` Cloudflare Worker is unused by the Apple app (only a historical comment references it),
  by the web app (`src/lib/api.ts` uses `corsproxy.io`), and by CI. Closes WC-A3. Left for you because
  it's a web-repo asset, not an Apple-app file.

## Still-open verification from earlier work (M31 / sync)

- [ ] **On-device 2-device iCloud sync smoke test** — change data on device A (backgrounded), confirm
  device B updates via the M31 background push within a few minutes; plus the general sync trio
  (partial-failure stays "Up to Date", no full-dataset re-encode per batch). See `TO_IMPROVE.md`
  "Manual verification".

## Optional post-release follow-ups (deferred, non-blocking — details in `IOS_MACOS_BUG_AUDIT.md` Resolution)

- [ ] **WC-L28** — make `LocalFinancePersistence.load()` read-only (move legacy-migration + date-heal
  writes into an explicit pre-load step). Deferred: unverifiable migration-path refactor pre-release.
- [ ] **WC-M8 / WC-A2 dedup** — extract one shared mac transaction editor + de-duplicate the
  notification-sync / chart-card / iOS form logic. Pure refactor; the divergences/currency bug are fixed.
- [ ] **WC-L21 "Settings" word** — translate "Settings" for the ~15 locales where the string catalog
  holds an English placeholder (native-reviewed). Investments tab is already localized.
- [ ] **Arch #26 / #27** — incremental local persistence / snapshot-model redesign (large, scale-only).
