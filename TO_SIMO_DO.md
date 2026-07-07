# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

- **App Store Connect Submission**: The versions and metadata have been updated across all 38 languages. When you are ready to publish, run:
  ```bash
  cd apple/WealthCompass
  fastlane ios release
  ```
  *(Or if you only want to push the metadata first without binary: `fastlane ios metadata`)*
