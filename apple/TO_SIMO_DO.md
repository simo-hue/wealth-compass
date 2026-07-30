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

## Money Flow — surplus removed from the pipes (2026-07-30)
- [ ] **Check the unspent tail reads correctly on a normal month.** The reference data is an extreme case (93.6% unspent), so the spent part of the hub is a sliver. On a month where you spent 40–60% it should look far more balanced — worth confirming.
- [ ] **Hovering the empty lower-right.** With only two expense categories, the void where the surplus pipe used to be is now nearest to the bottom-most expense, so hovering there lights that category. It follows the "nearest flow, always one lit" rule you chose, but tell me if it feels wrong — the alternative is to resolve that region to the surplus instead.
- [ ] **The tail is labelled "Surplus", not "Unspent".** I kept the existing word: it is already translated into all 34 languages and means the same thing. Say the word if you want "Unspent" and I will add the key.

## Money Flow — surplus removed entirely (2026-07-30)
- [ ] **Decide whether the thin spending band is acceptable.** With one shared scale and no surplus, your 30-day spending (6.4% of income) is a narrow band in the middle of the card. That is honest arithmetic, not a bug. If you want the categories to fill the height instead, say so and I will scale each side independently — the trade-off is that a €100 income ribbon and a €100 expense ribbon would no longer be the same thickness.
- [ ] **The surplus number is no longer shown on this card at all.** The footer still reads TOTAL CASH FLOW. Tell me if you want the surplus back as a footer stat.

## Money Flow — adaptive label sizing (2026-07-30)
- [ ] **Check the collapsed labels read well at your window size.** Name and amount now share one line for any flow thinner than 32pt. On a narrow pane a long category ("Entertainment", "Smaller categories") plus its amount may truncate — the amount is protected, the name shrinks first. If truncation is common at your width, the fix is to widen `preferredLabelWidth` or drop the name to `.caption` in the collapsed form.
- [ ] **Confirm the leader lines look right.** They only appear now when a pipe is too thin for even one line, so they should be rare — but that also means they are the only cue for the very smallest flows.

## Money Flow — widget overflow fix + All Time default (2026-07-30)
- [ ] **Re-check the Dashboard widget.** The hub should now be exactly as tall as the flows leaving it and stay well inside the card, with the title clear. This was reproduced and fixed against your exact figures, but it is worth a look at your real window size.
- [ ] **Cash Flow now opens on All Time.** The Dashboard's compact card still opens on Last 30 Days. Tell me if you want them consistent.
