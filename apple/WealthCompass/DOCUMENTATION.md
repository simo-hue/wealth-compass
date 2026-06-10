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

- [2026-06-10 18:35]: Shared Selector Island & Table Redesign
  - *Details*: Extracted the custom selector island into a shared generic component and applied the exact same split-view layout to the Investments and Crypto pages.
  - *Tech Notes*: Created `MacSelectorIsland<Tab: MacSelectorTab>` in `DesignSystem.swift`. Updated `MacCashFlowView`, `MacInvestmentsView`, and `MacCryptoView` to adopt the shared component, splitting their UIs cleanly into "Overview" and "Transactions"/"Holdings" tabs.

- [2026-06-10 18:41]: Settings Redesign — Custom Island UI
  - *Details*: Redesigned the macOS Settings view to match the custom dark glassmorphism aesthetic of the rest of the app, completely removing the native `Form` and `TabView` layout.
  - *Tech Notes*: Refactored `MacSettingsView` to use `MacSelectorIsland`, `FinanceCard`, and `ScreenBackground`. Created `SettingsSection` and `SettingsRow` helper components to ensure uniform padding, layouts, and typography across all settings options.

- [2026-06-10 18:42]: Crypto Holdings Custom Card Redesign
  - *Details*: Replaced the raw native `NSTableView` in the Crypto page's "Holdings" tab with a custom scrollable list of beautifully styled `FinanceCard` elements to ensure UI consistency.
  - *Tech Notes*: Replaced the `Table` implementation in `MacCryptoView` with a `ScrollView` and `LazyVStack` containing iterating `FinanceCard` rows. Retained context menus and double-tap gestures for editing and deleting holdings.

- [2026-06-10 18:44]: Crypto Holdings Responsive Grid
  - *Details*: Converted the vertical list of crypto holdings into a responsive grid that automatically places multiple holdings side-by-side on larger screens.
  - *Tech Notes*: Replaced `LazyVStack` with `LazyVGrid` using `GridItem(.adaptive(minimum: 360))` in `MacCryptoView`'s holdings view. Expanded the `ScrollView` `maxWidth` to `1440` to allow the grid to flow horizontally.

- [2026-06-10 18:46]: Investment Positions Custom Card Grid
  - *Details*: Applied the exact same responsive `FinanceCard` grid redesign to the Investments page's "Positions" tab, replacing the native `NSTableView`.
  - *Tech Notes*: Replaced `Table` with `ScrollView` and `LazyVGrid` in `MacInvestmentsView.swift`. Created `investmentCard(for:)` preserving context menus, double-tap editing, and all primary data fields.

- [2026-06-10 18:47]: Cash Flow Transactions Custom Card Grid
  - *Details*: Replaced the native `NSTableView` in the Cash Flow "Transactions" tab with a fully responsive `FinanceCard` grid layout.
  - *Tech Notes*: Replaced `Table` with `ScrollView` and `LazyVGrid` in `MacCashFlowView.swift`. Designed `transactionCard(for:)` to handle income/expense styling dynamically, support recurring schedule badges, and maintain delete context menus.

- [2026-06-10 18:50]: Cash Flow Grid Height & Filter Polish
  - *Details*: Equalized the vertical heights of all transaction cards regardless of description presence, and styled the filter pickers with a custom glassmorphic pill background.
  - *Tech Notes*: Added `Spacer(minLength: 0)` and `.frame(maxHeight: .infinity, alignment: .top)` to the `FinanceCard` inner `VStack`. Wrapped the top pickers in an `.ultraThinMaterial` background with custom border radii.

- [2026-06-10 18:51]: Centered Cash Flow Filters
  - *Details*: Centered the transaction filter pill horizontally on the Cash Flow page.
  - *Tech Notes*: Removed internal `Spacer()` and applied `.frame(maxWidth: .infinity, alignment: .center)` to the `transactionFilters` component in `MacCashFlowView.swift`.

- [2026-06-10 18:54]: Removed Repetitive Position Section
  - *Details*: Removed the Position section cards from the macOS dashboard entirely because it presented repetitive net-worth and position information.
  - *Tech Notes*: Deleted `positionSection` and the `PositionMetricCard` struct from `MacDashboardView.swift`.

- [2026-06-10 18:57]: Net Worth Chart Hover UX Improvement
  - *Details*: Replaced the awkward bottom bar that appeared when hovering the net worth chart with a sleek, floating Chart annotation directly attached to the selected rule mark. This guarantees a much more professional and seamless UX, keeping the user's focus on the data point itself without shifting layout below.
  - *Tech Notes*: Updated MacDashboardView.swift by adding an '.annotation(position: .top, overflowResolution: ...)' to the existing RuleMark and removing the separate HStack that conditionally appeared below the chart.

- [2026-06-10 19:03]: Cash Flow Overview Redesign
  - *Details*: Completely redesigned the Cash Flow Overview page to use a responsive dashboard layout, adding a "Six-Month Cash Flow" trend chart and a "Recent Activity" list while packing "Expense Categories" and "Recurring Transactions" into compact side-by-side cards.
  - *Tech Notes*: Modified `MacCashFlowView.swift` to use `GeometryReader` with a grid layout mirroring the dashboard. Extracted `ActivityRow`, `DashboardEmptyState`, `CashFlowLegendItem`, and `PrivacyChartCover` from `MacDashboardView.swift` by making them `internal` to enable clean code reuse. Added `signedAmount(for:)` helper to `MacCashFlowView`.

- [2026-06-10 19:04]: Improved Mac Investments Overview Dashboard
  - *Details*: Redesigned the overview tab in `MacInvestmentsView.swift` to show three donut charts side-by-side (Allocation by Sector, Allocation by Type, Allocation by Geography). Also added a "Top Holdings" section to display the top 5 largest investments in the portfolio for better UX.
  - *Tech Notes*: Added `investmentTypeAllocation` and `investmentGeographyAllocation` to `FinanceStore.swift` to provide data slices for the new charts.

- [2026-06-10 19:11]: AllocationChart Uniform Height Fix
  - *Details*: Ensured that multiple `AllocationChart` views placed in an `HStack` expand to match the height of the tallest chart in the row, preventing unprofessional staggered box sizes.
  - *Tech Notes*: Added `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` to the inner `VStack` of `AllocationChart` in `DesignSystem.swift`.

- [2026-06-10 19:14]: Cash Flow Cards Uniform Height Fix
  - *Details*: Coordinated the sizes of the "Recent Activity" and "Recurring Transactions" boxes in the Cash Flow Overview to dynamically match heights, maintaining a professional and aligned grid. Also applied this to the trend and category charts.
  - *Tech Notes*: Added `.frame(maxHeight: .infinity, alignment: .top)` to the inner `VStack` inside `recentActivityCard`, `recurringTransactionsCard`, `cashFlowTrendCard`, and `expenseCategoriesCard` in `MacCashFlowView.swift` to allow them to stretch to the `HStack`'s proposed height. Added `.fixedSize(horizontal: false, vertical: true)` to the parent `HStack`s to ensure the vertical height proposal correctly propagates down through the `ScrollView`. Also fixed an Xcode project compilation issue by linking `DynamicMasonryLayout.swift`.

- [2026-06-10 19:20]: Improved Mac Crypto Overview Dashboard
  - *Details*: Redesigned the overview tab in MacCryptoView to display top gainers/losers side-by-side at the top, and placed the Crypto Allocation chart horizontally next to a new 'Top Holdings' list, making the interface professional and informative.
  - *Tech Notes*: Added `performanceSection` and `topHoldingsSection` as native SwiftUI components inside `MacCryptoView.swift`, reusing existing `CryptoIconView` and `FinanceCard` designs.

- [2026-06-10 19:26]: Interactive Donut Chart Hover & Hidden Legend
  - *Details*: Updated the AllocationChart component to support an interactive hover state on macOS. When hovering over a slice, it lights up while the others dim, and the center text dynamically updates to display the slice's specific details. Hid the chart legend in the Crypto view to make the circular chart the exclusive focus of its box.
  - *Tech Notes*: Used `.onContinuousHover` combined with a custom `slice(at:in:total:)` geometric math calculation to accurately detect hovered sectors without relying on newer iOS 17 `chartAngleSelection` limits. Updated `AllocationChart` to accept an optional `showLegend` boolean.

- [2026-06-10 19:27]: Top Holdings UI Consistency Update
  - *Details*: Redesigned the 'Top Holdings' section in the Crypto Overview tab to match the exact same UI as the main 'Holdings' view. Removed the side-by-side layout in favor of a full-width adaptive `LazyVGrid` layout that scales beautifully.
  - *Tech Notes*: Extracted `topHoldingsSection` from the `HStack`, replaced `VStack` with `LazyVGrid(columns: [GridItem(.adaptive(minimum: 360))])`, aligned the section heading to `.title2`, and increased the display prefix limit to 6 holdings.

- [2026-06-10 19:30]: Crypto Overview No-Scroll Adaptive Layout
  - *Details*: Redesigned the Crypto Overview layout to aggressively fit content on screen without forcing a scrollbar on larger windows. Grouped the 'Crypto Allocation' chart and 'Performance Section' side-by-side to save an entire vertical row of space, allowing all main elements to render above the fold.
  - *Tech Notes*: Wrapped the layout in `ViewThatFits(in: .vertical)` with a fallback `ScrollView`. Extracted content to an `overviewContent` view. Switched `performanceSection` from an `HStack` to a `VStack` to sit elegantly next to the `AllocationChart`.

- [2026-06-10 19:31]: Investment Allocation Distinct Chart Colors
  - *Details*: Modified the Investment Overview charts so that 'Allocation by Sector', 'Allocation by Type', and 'Allocation by Geography' each use distinct color palettes, making them visually unique and easier to distinguish at a glance.
  - *Tech Notes*: Added `chartType` and `chartGeography` arrays to `ColorPalette` in `DesignSystem.swift`. Updated `investmentTypeAllocation` and `investmentGeographyAllocation` in `FinanceStore.swift` to use the new palettes. Also ensured deterministic color mapping by explicitly sorting slices before assigning colors.

- [2026-06-10 19:34]: Interactive Asset Allocation Dashboard Chart
  - *Details*: Replicated the interactive hover behavior from the Crypto Allocation chart into the Asset Allocation chart on the Mac Dashboard. Hovering over a slice now highlights it, dims the others, and displays the slice's specific name, value, and percentage in the center of the donut chart.
  - *Tech Notes*: Added `@State private var hoveredAssetSlice` to `MacDashboardView.swift`. Applied `.opacity` modifier to `SectorMark` bound to the hovered slice state. Added `.chartOverlay` with `.onContinuousHover` to perform hit-testing using a custom geometric `slice(at:in:total:slices:)` function, and updated `.chartBackground` to dynamically display the hovered slice's details or fallback to total assets.

- [2026-06-10 19:37]: Cash Flow Interactive Charts & Unified UI
  - *Details*: Replaced the dropdown menu on the Expense Categories card with a segmented picker to match the layout of the Cash Flow Trend card. Implemented interactive hover effects on both the Expense Categories donut chart and the Cash Flow Trend bar chart.
  - *Tech Notes*: In `MacCashFlowView.swift`, replaced `Picker` with `.pickerStyle(.menu)` with `DashboardSegmentedPicker`. Added `@State` tracking variables for hovered month and category. Added geometric slicing logic `categorySlice(at:in:total:categories:)` for the pie chart hover mapping, and simple coordinate mapping using `proxy.value(atX:)` for the bar chart hover. The Legend text dynamically updates to reflect hovered element properties.

- [2026-06-10 19:46]: Cash Flow Expense Categories Simplification
  - *Details*: Removed the redundant list of categories below the Expense Categories pie chart to maximize the pie chart size and visual impact. Hovering over a slice now serves as the primary way to view exact category amounts.
  - *Tech Notes*: Removed the `VStack` list of items in `MacCashFlowView.swift` and updated the `ZStack` containing the chart to `.frame(minHeight: 250, maxHeight: .infinity)` to fill available vertical space.

- [2026-06-10 19:48]: Layout Optimization for Expense Categories
  - *Details*: Fixed a layout issue where the title was wrapping awkwardly due to the segmented picker taking up too much horizontal space.
  - *Tech Notes*: Reverted the `DashboardSegmentedPicker` on the Expense Categories card in `MacCashFlowView.swift` back to a native `Picker` with `.pickerStyle(.menu)` and a constrained frame of `142pt` to ensure enough width remains for the section title.
