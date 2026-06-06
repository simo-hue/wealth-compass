# Documentation

- [2026-06-06 14:38]: Mac Dashboard Position Section Update
  - *Details*: Added a "Total Assets" card to the `MacDashboardView` Position section to ensure the dashboard width is fully occupied, fixing the layout gap after "Net Savings".
  - *Tech Notes*: Included `PositionMetricCard` mapping to `totals.totalAssets` in `LazyVGrid`.

- [2026-06-06 14:43]: Mac Dashboard Cards Height Alignment Fix
  - *Details*: Ensured that the dashboard cards in the Mac app ("Top Expense Categories", "Recent Activity", "Six-Month Cash Flow", "Asset Allocation") align perfectly by stretching their inner VStacks to the maximum available height.
  - *Tech Notes*: Applied `.frame(maxHeight: .infinity, alignment: .top)` to the content `VStack` inside `allocationCard`, `cashFlowCard`, `topExpensesCard`, and `recentActivityCard` in `MacDashboardView.swift`.

- [2026-06-06 15:15:19]: iCloud Document Sync Implementation
  - *Details*: Added iCloud Document sync capability while maintaining local storage priority.
  - *Tech Notes*: Replaced `mutating` structs logic with dynamic URL computation in `LocalFinancePersistence`. Added `isICloudSyncEnabled` toggle in `AppSettings` via `UserDefaults`. Configured `NSMetadataQuery` in `FinanceStore` to automatically observe changes to the Ubiquity Container and reload data automatically across devices. Updated both iOS and macOS Settings views to expose the new iCloud sync toggle.
- [2026-06-06 15:35]: iCloud Sync Reliability Fix
  - *Details*: Bypassed Info.plist container requirements by using a hidden Data directory.
  - *Tech Notes*: Changed NSMetadataQuery to use `NSMetadataQueryUbiquitousDataScope` instead of `NSMetadataQueryUbiquitousDocumentsScope` and moved file to `Data/wealth-compass-local-data.json`. This forces iCloud to sync without needing `NSUbiquitousContainers` explicitly defined in Info.plist.

- [2026-06-06 15:38]: Manual iCloud Force Sync
  - *Details*: Added a "Force Sync iCloud" button in Settings to manually trigger download and merge of iCloud state.
  - *Tech Notes*: Added `forceICloudSync()` to `FinancePersistence` and `FinanceStore` that utilizes `FileManager.default.startDownloadingUbiquitousItem()`. Exposed button conditionally in both `SettingsView.swift` and `MacSettingsView.swift`.

- [2026-06-06 15:48]: iCloud Sync Critical Bug Fixes
  - *Details*: Resolved critical data loss bugs caused by unsafe local file deletions, missing file coordination, and incorrect iCloud file replacement behaviors.
  - *Tech Notes*: Introduced `NSFileCoordinator` in `FinancePersistence` for atomic read/write operations to iCloud container URLs. Replaced destructive iCloud sync logic with safe temporary file replacement and `options: .atomic` writing. Fixed `NSMetadataQuery` in `FinanceStore` to respect `NSMetadataUbiquitousItemDownloadingStatusKey` and automatically trigger `startDownloadingUbiquitousItem` if the updated file is not fully downloaded before attempting to load data.
