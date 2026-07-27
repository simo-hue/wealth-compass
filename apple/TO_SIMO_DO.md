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
