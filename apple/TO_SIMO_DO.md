# Manual Actions Required

## macOS wide-screen layout change (2026-07-14)
- [ ] **Build & visually verify in Xcode.** This machine has only Command Line Tools (no Xcode), so `xcodebuild -scheme WealthCompassMac` could not be run and the change is unverified at runtime. In Xcode: build the `WealthCompassMac` scheme, then on a large / external display confirm the **Cash Flow**, **Crypto**, and **Investments → Overview** tabs and the **Settings** page now fill the window width (summary cards stretch edge-to-edge; no dead right margin). Also confirm a normal MacBook-sized window looks unchanged, and sanity-check **Privacy Mode** on Crypto/Investments (Performance card hidden → 5 cards should still fill with no empty slot).
- [ ] **Build & visually verify in Xcode.** The app has been renamed to "Wealth Compass Tracker" across all languages. Please verify the build and translations on a real device or simulator since Xcode is not available on this machine.
- [ ] **App Store Connect Upload.** App version has been bumped to 1.1.4 (build 20) for both iOS and macOS targets. You can now build the archives and upload them to App Store Connect.
- [x] **Fastlane Metadata Delivery.** The `release_notes.txt` ("What's New") has been updated and translated for all 39 supported languages with the text "Added PDF export functionality.". Since App Store Connect authentication requires your input (e.g. 2FA or specific password), please manually run the following commands to deliver the metadata:
  ```bash
  cd apple/WealthCompass
  fastlane ios metadata
  fastlane mac metadata
  ```

## Money Flow Sankey diagram (2026-07-29)
- [ ] **Build both schemes in Xcode on the Mac mini.** This machine has only Command Line Tools, so no `.app` could be linked. Everything was verified as far as is possible here: `swiftc -typecheck` over all of `Sources/Shared` + `Sources/macOS` exits clean, a 1657-assertion harness linking the real shared sources passes, and both test files type-check against a module built from `Sources/Shared`. What that does *not* cover is linking, asset catalogs, entitlements and signing.
- [ ] **Confirm the three new files appear in Xcode.** `CashFlowSankey.swift`, `SankeyLayout.swift` and `SankeyDiagramView.swift` were added to `project.pbxproj` by hand (both app targets); `SankeyLayoutTests.swift` was added to the test target. The file parses (`plutil -lint` clean) and target membership was verified by parsing the project, but it is worth a glance in the Project Navigator.
- [ ] **Run the test suite.** XCTest cannot run here (no test host / simulator):
  ```bash
  cd apple
  xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
- [ ] **Visually check the two cards.** Cash Flow → Overview (full-width diagram, and confirm you are happy the `Expense Categories` donut is gone) and the Dashboard (compact card where `Top Expense Categories` used to be) — ideally at a *narrow* window too, around 1020pt, which is where the 2-up row is tightest. Also check hover dimming, clicking a node (should land on Transactions with a removable category chip), and Privacy Mode (whole diagram should conceal).
- [ ] **Export a PDF report** and check the new `Money Flow` block in the Cash Flow section prints legibly, including in greyscale.
- [ ] **Review the new translations.** 15 new keys were added to `Localizable.xcstrings` across all 34 non-source languages and marked `translated`. They are my translations, not a professional pass — the financial terms in particular ("Surplus", "Drawn from Savings", "Smaller categories") are worth a skim in the languages you read.
- [ ] **Discard the spun-off `expensesByCategory` NaN task if it is still open.** That fix was applied directly in the main session (`AnalyticsEngine.expensesByCategory` now filters non-finite sums, with a regression test in `AnalyticsEngineTests`), so a second session working on it would conflict.

## Money Flow — hover fix + visual pass (2026-07-30)
- [ ] **Re-check hover on the Mac mini.** The 2.5pt-ribbon problem is fixed and measured headlessly, but pointer feel is the one thing a harness cannot judge. Confirm that sweeping the pointer down the right-hand side steps cleanly through Food → Transport → Surplus, that the left side steps through the income sources, and that clicking still drills through to the filtered transaction list.
- [ ] **Sanity-check the new card height.** It is now `0.30 × width` (clamped 280–520pt), so the Cash Flow page got noticeably taller. If it pushes Recent Activity / Recurring too far down for your taste, the multiplier is one number in `SankeyDiagramView.diagramHeight`.
- [ ] **Look at the greyscale PDF again.** The income ramp is new and was chosen for luminance separation, but only a real print will confirm Dividends vs Salary vs Freelance stay distinguishable.
