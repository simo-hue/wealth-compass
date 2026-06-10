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

- [2026-06-06 15:59]: Production iCloud Sync Capabilities
  - *Details*: Added conflict resolution (merging), account status observation, and UI animations.
  - *Tech Notes*: Modified `FinanceModels.swift` to introduce `MergeableRecord` and `updatedAt` for conflict resolution based on timestamp. Refactored `FinancePersistence` to decode and merge local and incoming iCloud JSON data before saving. Added `NSUbiquityIdentityDidChange` observer to `FinanceStore` to safely disable sync upon iCloud logout. Wrapped data reloading in `withAnimation`. Exposed `@Published var iCloudSyncError` for graceful error handling.

- [2026-06-06 16:08]: Deep Scan iCloud Bug Fixes
  - *Details*: Fixed bugs causing infinite sync loops, stale offline changes, and broken timestamps during store mutations.
  - *Tech Notes*: Updated `upsertRecurringTransaction`, `upsertCrypto`, and `upsertInvestment` in `FinanceStore` to explicitly inject `Date()` to `updatedAt` to ensure edits properly trigger timestamp-based conflict resolution. Exposed `sortedForStorage()` in `FinanceModels.swift` to canonicalize array structures to make `Equatable` safe. Added push-back logic in `FinancePersistence.syncFromICloudIfNeeded()` that automatically uploads offline-merged data back to iCloud conditionally if `mergedData != sortedICloudData`.

- [2026-06-06 19:35]: Production CloudKit Sync
  - *Details*: Replaced whole-file iCloud Documents synchronization with entity-level private CloudKit synchronization powered by `CKSyncEngine`, while keeping the local JSON database available offline on every device.
  - *Tech Notes*: Added a durable custom-zone sync engine, persisted engine state and record system fields, tombstones, account isolation, initial bootstrap reconciliation, revision-checked acknowledgements, conditional remote application, retry handling, legacy JSON migration, sync status UI, CloudKit/push entitlements, iOS remote-notification background mode, and focused XCTest coverage.

## CloudKit Sync Architecture

- Local data remains in Application Support as `wealth-compass-local-data.json`; CloudKit is the cross-device synchronization transport.
- Each transaction, recurring transaction, investment, crypto holding, liability, and net-worth snapshot is stored as a separate record in the private `WealthCompassZone` zone.
- Deletes are synchronized as tombstones so a device returning after a long offline period cannot recreate deleted data.
- Pending mutations, CloudKit system fields, account identity, bootstrap state, and `CKSyncEngine` state are persisted independently in `wealth-compass-cloud-sync.json`.
- Initial bootstrap uses each entity's `updatedAt` timestamp for local-versus-remote reconciliation. An existing remote tombstone wins unless the record was explicitly edited after that tombstone was observed.
- Upload acknowledgements and fetched mutations are revision checked so an in-flight operation cannot overwrite or clear a newer local edit.
- Switching or signing out of the iCloud account disables sync without deleting local data. Re-enabling sync is the explicit action that adopts the current account.

## CloudKit Production Deployment

1. The iOS and macOS targets intentionally share the explicit App ID `com.wealthcompass.mobile` to participate in the same App Store Connect record as a Universal Purchase.
2. In Certificates, Identifiers & Profiles, enable **iCloud / CloudKit** and **Push Notifications** for `com.wealthcompass.mobile`, including macOS support for that App ID.
3. Associate the App ID with `iCloud.com.wealthcompasstracker`, then regenerate development and distribution provisioning profiles.
4. Run a development build while signed into iCloud and create at least one record of every supported type: `WCTransaction`, `WCRecurringTransaction`, `WCInvestment`, `WCCryptoHolding`, `WCLiability`, and `WCNetWorthSnapshot`.
5. In CloudKit Dashboard, verify the generated fields (`schemaVersion`, `payload`, `createdAt`, `updatedAt`, `clientModifiedAt`, `revision`, `isDeleted`, and `deletedAt`) and deploy the development schema to Production before TestFlight or App Store distribution.
6. In the existing iOS app record in App Store Connect, choose **Add Platform > macOS**. Do not create a separate macOS app record.
7. Validate on two physical devices using the same Apple Account, including offline edits, concurrent edits, deletes, account sign-out, app relaunch, and manual force sync.

- [2026-06-10 17:47]: Daily Snapshot Backfill Mechanism
  - *Details*: Implemented a carry-forward backfill strategy to automatically generate snapshots for any days the app is not opened.
  - *Tech Notes*: Modified `appendSnapshot` in `FinanceStore.swift` to detect missing days between the last snapshot and the current date. It appends up to 60 backfill snapshots at `23:59:59` carrying forward the exact last known values to guarantee mathematical honesty and a continuous daily graph.

- [2026-06-10 17:48]: Dynamic Crypto Icons
  - *Details*: Replaced hardcoded Bitcoin icon with a dynamic CDN-fetched image for all crypto holdings, matching the specific token automatically.
  - *Tech Notes*: Created `CryptoIconView` in `DesignSystem.swift` using `AsyncImage` with `assets.coincap.io` CDN. Implemented a deterministic hash-based fallback with the token's first letter and background color for when an image is unavailable. Updated both `CryptoView.swift` (iOS) and `MacCryptoView.swift` (macOS) to use the new dynamic icons.

- [2026-06-10 18:17]: macOS UX Overhaul — All 7 Analysis Issues Fixed
  - *Details*: Implemented every fix from `macOS_UX_Analysis.md` to bring the macOS app in line with native HIG conventions. This is a comprehensive production-quality UX pass across the entire macOS target.
  - *Tech Notes*:
    - **Issue 1 (Table Architecture):** Pulled `Table` components out of outer `ScrollView` wrappers in `MacInvestmentsView`, `MacCryptoView`, and `MacCashFlowView`. Tables now sit outside the scroll context with `.layoutPriority(1)`, enabling native `NSTableView` scrolling with pinned column headers and row virtualization.
    - **Issue 2 (Context Menus):** Added `.contextMenu(forSelectionType:)` with Edit/Delete actions, `primaryAction:` for double-click editing, and `.onDeleteCommand` for keyboard Delete key on all data tables. Removed floating Edit/Delete button HStacks.
    - **Issue 3 (Toolbar & Search):** Replaced `TextField` search in `MacCashFlowView` with `.searchable(text:prompt:)` modifier (auto-binds `Cmd+F` and places in toolbar). Moved Add Transaction menu to native `ToolbarItemGroup`.
    - **Issue 4 (Window Sizing):** Reduced minimum frame constraints from 760×560 to 520×400 in `MacRootView` to allow compact column layout.
    - **Issue 5 (Editor Sheets):** Refactored all 5 editor views (`MacTransactionEditor`, `MacInvestmentEditor`, `MacCryptoEditor`, `MacRecurringTransactionEditor`, `MacCashFlowTransactionEditor`) to use `NavigationStack` with `.navigationTitle()` and `.toolbar` with `.cancellationAction`/`.confirmationAction` placements. Replaced hardcoded frame sizes with flexible min/ideal constraints. Added `Cmd+S` shortcut to all Save buttons.
    - **Issue 6 (Keyboard Shortcuts):** Added "Navigate" menu with `Cmd+1` through `Cmd+5` for instant sidebar navigation. Added `Cmd+R` for Refresh Data.
    - **Issue 7 (Dashboard Padding):** Replaced manual `proxy.size.width < 900 ? 20 : 28` padding with `.padding(.horizontal, 24)` + `.scenePadding(.minimum, edges: .horizontal)`.

- [2026-06-10 18:29]: Cash Flow Redesign — Tab Selector Island
  - *Details*: Redesigned the Cash Flow view to include a native macOS selector island at the top, splitting the view into "Overview" and "Transactions" tabs.
  - *Tech Notes*: Replaced the top-level `VStack` in `MacCashFlowView.swift` with a custom `CashFlowSelectorIsland` component that mimics the settings pill UI. Removed arbitrary `.frame(maxHeight: 520)` constraint.
