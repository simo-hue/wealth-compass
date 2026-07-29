# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

- [ ] How to sync the cards' transactions automatically 
---

## PDF Report Export (added 2026-07-27)

The whole feature was written and verified without Xcode (this machine has Command Line Tools
only). What I could verify, and what I could not:

**Needs you, at a Mac with Xcode**
- [ ] **Build the iOS target.** `Sources/iOS/Views/SettingsView.swift` is the one file I could not
      typecheck — there is no iOS SDK here, so UIKit is unavailable. Its changes mirror the macOS
      ones exactly (export coordinator, two sheets, `performExport()`, plus a small
      `ExportShareSheet` `UIViewControllerRepresentable`), but it has never been compiled.
- [ ] **Build the macOS target** to confirm the asset catalogue compiles with the new
      `BrandMark.imageset` and that `NSImage(named: "BrandMark")` resolves at runtime.
- [ ] **Run the test suite** on a simulator:
      `xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'`
- [ ] **Eyeball the export sheet** on both platforms. The sheet itself was never rendered — only
      typechecked. Check the macOS fixed frame (460×560) is not clipping, and that the iOS sheet
      scrolls properly with "Choose Sections" expanded.
- [ ] **Check the share sheet / save panel** actually receive the file, and that the PDF opens in
      Preview / Files with the sidebar outline present.
- [ ] **Watch for sheet chaining on iOS specifically.** A PDF export dismisses the options sheet,
      may present the progress sheet ~400 ms later, then presents the share sheet when it finishes
      — up to three sheets in sequence. UIKit has historically dropped the second presentation when
      one begins before the previous dismissal animation completes. If the share sheet fails to
      appear on a fast export, the fix is to delay presenting `exportedFile` until the options
      sheet's dismissal completes. I could not reproduce or rule this out without an iOS runtime.
- [ ] **Translate the 81 new strings.** They are in `Localizable.xcstrings` as English-only
      entries; every non-English locale will currently show the English key. Open the catalogue in
      Xcode and translate, or run them through your usual translation pass.
- [ ] Optional: regenerate samples any time with
      `swiftc -swift-version 5 -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 $(find Sources/Shared -name '*.swift') scripts/render_sample_report.swift -o /tmp/rsr && /tmp/rsr /tmp/samples`

### Review pass (2026-07-27)

A six-dimension adversarial review found 14 confirmed bugs, all now fixed and re-verified here
(clean typecheck, six sample renders, pagination swept over 2,400 table shapes, reconciliation
checked across three date ranges with mixed currencies). Two notes for you:

- [ ] **The PDF can differ from the app's screen by one cent per foreign-currency record.** This is
      deliberate. The report books each posting at its rounded value so its own columns add up;
      `AnalyticsEngine` sums unrounded conversions and rounds once. They cannot both be used in one
      document — that was the bug. If you would rather the PDF match the screen exactly, the change
      is to drop `recordValue`'s rounding, and the cost is a statement whose printed opening +
      income + expenses no longer equals its printed closing.
- [ ] **`Tests/ReportRenderingTests.swift` is new** and registered in the project (slot `CA`). It
      has never been run — no XCTest on this machine — but every assertion in it was executed
      against the real code through a standalone driver first.
