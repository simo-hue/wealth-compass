# Currency Symbol Replacement Implementation

## Overview
Replaced static hardcoded "$" symbols with a dynamic currency symbol based on the user's global settings. This ensures the application reflects the selected base currency (USD, EUR, GBP, CHF) across the dashboard and calculators.

## Changes
1.  **SettingsContext**
    -   Added `currencySymbol` to the context value.
    -   Implemented logic to derive the symbol from the `currency` code (e.g., 'EUR' -> '€') using `Intl.NumberFormat`.

2.  **FIRECalculator**
    -   Updated the chart tick formatter to use `currencySymbol` instead of hardcoded `$`.
    -   Verified text labels use `formatCurrency`.

3.  **DashboardCharts**
    -   Updated `CashFlowTrendChart` to use `currencySymbol` in the Y-axis tick formatter.

## Verification
-   **Build**: Successfully built using `npm run build`.
-   **Manual Check**:
    -   Navigate to Settings and change currency.
    -   Check FIRE Calculator charts.
    -   Check Dashboard Cash Flow chart.

# Pie Chart Redesign (Professional Style)

## Overview
Revamped the "Crypto Allocation" pie chart into a modern, aesthetic Donut chart to improve professional appearance and data readability.

## Changes
1.  **CryptoCharts (`CryptoAllocationChart`)**
    -   **Chart Style**: Converted to a **Donut Chart** with a thinner ring (`innerRadius` increased).
    -   **Center Info**: Added a central display showing the **Total Balance**.
    -   **Interactivity**:
        -   **Hover Effect**: Active segments expand slightly (`renderActiveShape`) and the central text updates (implied or static total depending on exact final code version - currently set to Total Balance).
        -   **Highlighting**: Hovering over the legend or chart highlights the specific segment.
    -   **Legend**: Replaced the default Recharts legend with a **Custom Side Legend** (or bottom on mobile) that shows:
        -   Color dot with shadow.
        -   Coin Symbol & Percentage.
        -   Value & Quantity details.
    -   **Visuals**: Utilized `glass-card` styling, `Sector` for rounded corners, and consistent spacing.

## Verification
-   **Visual**: chart is now a sleek ring with information clearly presented in the center and side panel.
-   **Responsiveness**: Verified mobile adjustments (smaller radii, legend moves to bottom).

# Mobile Menu Auto-Close Implementation

## Overview
Improved the mobile user experience by ensuring the sidebar menu (Sheet) automatically closes when a navigation link is clicked.

## Changes
1.  **MainLayout ()**
    -   Introduced `isMobileMenuOpen` state to control the Sheet visibility.
    -   Passed `setIsMobileMenuOpen` to the `Sheet` component.
    -   Passed a callback `() => setIsMobileMenuOpen(false)` to the `Sidebar` component.

2.  **Sidebar ()**
    -   Added optional `onNavigate` prop.
    -   Attached `onNavigate` handler to all navigation Links.

## Verification
-   **Manual**: Open the mobile menu (hamburger icon) and click any link (e.g., Dashboard). The menu should close immediately.

# Chart Modernization (Global Upgrade)

## Overview
A comprehensive update to all chart components to adhere to a modern, professional "glassmorphism" aesthetic. The goal was to replace standard Recharts visuals with custom, high-end designs featuring rounded corners, gradients, interactive legends, and rich tooltips.

## Implemented Changes

### 1. Dashboard Charts (`src/components/dashboard/DashboardCharts.tsx`)
- **Cash Flow Trend**:
    - Converted to **Bar Chart** with rounded top corners.
    - Added custom Tooltip with glass effect.
    - Improved grid and axis styling (minimalist).
- **Asset Allocation**:
    - Converted to **Donut Chart** (`innerRadius={innerRadius}`).
    - Added **Center Text** displaying Total Assets.
    - Added **Custom Side Legend** with interactive hover effects.
    - Implemented `ActiveShape` for segment expansion on hover.
    - **Mobile Optimization**: Adjusts radii and layout for smaller screens.

### 2. Allocation Chart (`src/components/dashboard/AllocationChart.tsx`)
- **Style**: **Donut Chart**.
- **Features**: 
    - Consistent styling with Asset Allocation chart.
    - Dynamic coloring based on category (Geography/Sector/Type).
    - Custom interactive legend.
    - Smooth hover transitions.

### 3. Net Worth Chart (`src/components/dashboard/NetWorthChart.tsx`)
- **Style**: **Area Chart** with gradient fill.
- **Features**:
    - "Monotone" curve for smoothness.
    - Custom Gradient Definition (`<defs>`) for a fading emerald fill (`#10b981`).
    - Rich Tooltip showing Net Worth with distinct typography.
    - Interactive dots only appear on hover (`activeDot`).

### 4. Cash Flow Analytics (`src/components/dashboard/CashFlowAnalytics.tsx`)
- **Expense Structure**: Converted to **Donut Chart** with custom legend.
- **Spending Timeline**: Converted to **Area Chart** with red gradient (`#EF4444`) to signify outflows.
- **Interactivity**: Synchronized hover states between chart and legend.

### 5. FIRE Calculator (`src/components/calculations/FIRECalculator.tsx`)
- **Style**: **Composed Chart** (Lines + Area).
- **Net Worth**: Displayed as a **Green Gradient Area** (`#22c55e`).
- **Benchmarks**: 
    - **FIRE**: Dashed Orange line.
    - **Fat FIRE**: Dashed Purple line.
    - **Lean FIRE**: Dashed Red line.
- **Tooltip**: Comprehensive glass card showing all 4 metrics (Net Worth, FIRE, Lean, Fat) at a glance.

## Technical Standards Applied
- **Glassmorphism**: `bg-black/40 backdrop-blur-xl border-white/5`
- **Typography**: Tailwind's `font-mono` for numbers, `text-white/90` for headings.
- **Gradients**: SVG `<linearGradient>` used for Area fills.
- **Responsiveness**: `ResponsiveContainer` used everywhere; mobile-specific radius and layouts handled via `useIsMobile`.

# Expense Structure Chart Mobile Fix

## Overview
Fixed a layout issue where the "Expense Structure" chart was cut off on mobile devices.

## Changes
1.  **CashFlowAnalytics.tsx**
    -   This allows the stacked content (Chart + List) to expand naturally on smaller screens without being clipped.

# Investments Page Mobile Reordering

## Overview
Reordered the layout on the Investments page for mobile devices to prioritize visual data.

## Changes
1.  **Investments.tsx**
    -   Changed main container from `grid` to `flex flex-col-reverse` on mobile.
    -   **Mobile**: The "Allocation" chart (originally second in DOM) now appears **ABOVE** the Investment Table.
    -   **Desktop**: Retained `lg:grid lg:grid-cols-3` to keep the original side-by-side layout (Table Left, Chart Right).

## Visual Refinement
- Removed redundant `Card` wrapper around `AllocationChart` in `Investments.tsx`.
- The chart component itself provides its own Card styling, so the outer wrapper was causing a double-border effect.

# Website & App Integration (Dual Access)

## Overview
Implemented a dual-access architecture where the public promotional website and the private financial software coexist within the same deployment but are logically separated.

## Architecture
1.  **Public Website**:
    -   Served at the root path `/`.
    -   Contains Landing Page, Features, FAQ, etc.
    -   No visible navigation links to the private software to maintain "hidden" access.

2.  **Private Software**:
    -   Served under the `/sw` prefix (e.g., `/sw/dashboard`).
    -   **Login Page**: Moved to `/sw/login`.
    -   **Protected Routes**: All app pages (`dashboard`, `cash-flow`, etc.) are protected and prefixed with `/sw`.

## Implementation Details
-   **Routing (`App.tsx`)**: Refactored `Routes` to define a public group (WebsiteLayout) and a private group (`/sw` path).
-   **Sidebar**: Updated all navigation links to use the `/sw` prefix.
-   **Auth Redirection**:
    -   `Login.tsx`: Redirects successful logins to `/sw/dashboard`.
    -   `ProtectedRoute.tsx`: Redirects unauthenticated users to `/sw/login`.

# Fix: Application Route Prefixing (/sw)

## Overview
Fixed the 404 errors when accessing `/sw/login` or other application routes by correctly nesting the application routes under a `/sw` path in `App.tsx`.

## Changes
1.  **App.tsx**
    -   Implemented a parent `<Route path="sw">` to wrap all application routes.
    -   Ensured `WebsiteLayout` remains at the root level (`/`).
    -   Added `Navigate` to redirect `/sw` index to `/sw/dashboard`.

2.  **Navbar.tsx**
    -   Updated the "Get Started" button to "Login" and pointed it to `/sw/login` to match the new route structure.

## Verification
-   **Build**: Successfully built using `npm run build`.
-   **Manual**:
    -   Accessing `/` loads the website.
    -   Accessing `/sw/login` loads the login page.
    -   Login redirects to `/sw/dashboard`.

# Fix: Login Page Hook Error

## Overview
Fixed a "Rendered fewer hooks than expected" error in `LoginPage` caused by an early return statement placed before a `useState` hook.

## Changes
1.  **Login.tsx**
    -   Moved `const [cooldown, setCooldown] = useState(0);` before the `if (user) return` block to verify React's Rules of Hooks are followed.

## Verification
-   **Manual**: The error should no longer appear when accessing the login page, even if the authentication state changes.

# PWA Configuration (Jan 29, 2026)

## Overview
Implemented PWA capabilities to allow the application to be installed as a standalone app with a custom icon.

## Changes
1.  **Icon Generation**:
    -   Generated standard PWA icons (192x192, 512x512) and Apple Touch Icon from source image.
    -   **Optimization**: Applied aggressive trimming to remove all transparent borders, scaling the logo to **100% fill** of the icon container.
    -   Replaced standard favicon with generated 64x64 PNG.

2.  **Manifest**:
    -   Created `public/manifest.webmanifest`.
    -   Configured for `standalone` display with correct name and colors.
    -   **Start URL Update**: Updated `start_url` to `/wealth-compass/sw/dashboard` to ensure the PWA opens directly to the application dashboard instead of the website homepage.
    -   **Maskable Icons**: Added `"purpose": "any maskable"` to `pwa-192x192.png` and `pwa-512x512.png` to fix the icon display in the macOS Dock, ensuring it fills the container.

3.  **HTML Integration**:
    -   Updated `index.html` to link to the new manifest and icons.

# GitHub Actions Deployment (Jan 29, 2026)

## Overview
Implemented an automated deployment workflow using GitHub Actions to enable continuous deployment for the Web App, specifically addressing the need to deploy from a fork without conflicting with the main repository's website.

## Changes
1.  **Workflow File (`.github/workflows/deploy.yml`)**:
    -   **Trigger**: Fires on `push` to `main` branch.
    -   **Process**:
        -   Checkout code.
        -   Install dependencies (`npm ci`).
        -   Build project (`npm run build`).
        -   Deploy the `dist` folder to a **new branch** named `gh-pages-webapp`.
    -   **Rationale**: By deploying to `gh-pages-webapp` instead of `gh-pages`, we ensure the "Web App" deployment does not overwrite the "Website" deployment on the main repository.

## Verification
-   **Manual**:
    -   Push changes to `main`.
    -   Observe action run in "Actions" tab.
    -   Verify branch `gh-pages-webapp` is created/updated.
    -   (User Action) Switch GitHub Pages source to this new branch.

## Troubleshooting: Fork Deployment
If the workflow does not run automatically on the Fork:
1.  **Enable Actions**: GitHub disables Actions on forks by default. Go to the **Actions** tab and click the button to enable them.
2.  **Manual Run**: If the sync happened *before* enabling actions, you may need to manually trigger the workflow:
    -   Go to **Actions** tab.
    -   Select **Deploy Web App**.
    -   Click **Run workflow**.

## Configuration: Secrets (Supabase)
For the application to connect to the database, you must configure the following **Repository Secrets** in the Fork settings (Settings > Secrets and variables > Actions):
-   `VITE_SUPABASE_URL`: Your Supabase Project URL.
-   `VITE_SUPABASE_ANON_KEY`: Your Supabase Anon Key.

# Mobile Numpad Keyboard Force (Mar 30, 2026)

## Overview
Forced mobile devices (iOS/Android) to exclusively show the numeric keypad (numpad) when users are inputting numbers instead of the full keyboard with numbers.

## Changes
1.  **Input Component (`src/components/ui/input.tsx`)**
    -   Automatically applied `inputMode="decimal"` to all input elements where `type="number"`.
    -   This prevents the standard alphanumeric keyboard from appearing when focusing on number fields, streamlining data entry for the financial application.

# macOS Settings Sidebar Link (June 06, 2026)

## Overview
Added a dedicated Settings link to the main navigation sidebar in the macOS app implementation.

## Changes
1.  **MacAppModel (`MacDestination`)**
    -   Added `.settings` enum case.
    -   Configured title as "Settings" and system icon as `gear`.
    -   Mapped selection to `.transaction` editor default appropriately.

2.  **MacRootView**
    -   Added `case .settings:` in the `detail` view builder to render `MacSettingsView()`.
- [Sat Jun  6 14:40:51 CEST 2026] Fixed UI bug in crypto and investments pages
  - *Details*: Added .frame(maxWidth: .infinity, alignment: .leading) to the inner VStack of FinanceCard in MacInvestmentsView.swift and MacCryptoView.swift to make the status cards use all available width space.
  - *Tech Notes*: Modified MacInvestmentsView.swift and MacCryptoView.swift.

- [Sat Jun  6 14:50:04 CEST 2026] Added Additional Info to Cash Flow Cards
  - *Details*: Added "Transactions" (current month's count) and "Total Cash" metrics to MacCashFlowView to fill the empty space on the right of the summary cards row.
  - *Tech Notes*: Updated MacCashFlowView.swift to compute monthly transactions count and total liquidity.

- [Sat Jun  6 14:55:47 CEST 2026] Unification of Investments and Crypto Layouts
  - *Details*: Replaced the split-pane (HSplitView) layout in MacInvestmentsView and MacCryptoView with a vertically scrolling, full-width design. This mirrors the Cash Flow page structure for a more cohesive UI.
  - *Tech Notes*: Replaced HSplitView with ScrollView containing a VStack. Adapted headers to use PageHeader. Extracted metrics into a LazyVGrid. Wrapped tables inside FinanceCards, and moved the 'Edit' and 'Delete' context actions to the table headers.

- [Sat Jun  6 15:01:25 CEST 2026] Moved Status Details into Summary Metrics grid
  - *Details*: Deleted the dedicated Portfolio Status and Holding Status cards and moved their critical info into the top metric grids as a new 'Status' box. Allocation charts now consume the full row width.
  - *Tech Notes*: Removed the HStack wrapper in MacInvestmentsView and MacCryptoView. Added a new MetricCard inside summaryCards rendering 'Status • X Sectors' and 'Status • X IDs'.

- [Sat Jun  6 15:04:17 CEST 2026] Updated Crypto Status Card metric
  - *Details*: Changed the secondary metric in the MacCryptoView Status card from the number of Coin IDs to the number of unique Coins (symbols).
  - *Tech Notes*: Updated MacCryptoView.swift to use 'Set(finance.data.crypto.map(\.symbol).filter(isNonEmpty)).count'.

- [2026-06-07T00:16:00+02:00]: App Version Bump
  - *Details*: Incremented the app version number for store publication.
  - *Tech Notes*: Bumped MARKETING_VERSION to 1.0.1 and CURRENT_PROJECT_VERSION to 2 in WealthCompass.xcodeproj/project.pbxproj.

- [2026-06-10T15:20:00+02:00]: SwiftUI Charts UI Enhancement
  - *Details*: Modernized the Net Worth, Cash Flow, and Asset Allocation charts across the iOS and macOS app. Removed Y-axes for a cleaner look, added interactive scrubbing to the Net Worth chart, improved styling (glows, points, corner radii), and integrated entry/morphing animations.
  - *Tech Notes*: Updated `DesignSystem.swift`, `DashboardView.swift`, and `MacDashboardView.swift`.

- [2026-06-10T15:24:00+02:00]: Fix: SwiftUI Charts Symbol Error
  - *Details*: Fixed a build error regarding `ChartSymbolShape` conformity.
  - *Tech Notes*: Replaced `.symbol(Circle().strokeBorder(...))` with `.symbol(Circle())` in `DashboardView.swift` and `MacDashboardView.swift` because `LineMark.symbol` requires basic shapes, not stroked view modifiers. Verified with successful `xcodebuild`.

- [2026-06-10T15:35:00+02:00]: SwiftUI UI Enhancements Phase 2
  - *Details*: Added dynamic "odometer" rolling numeric text animations, ambient "breathing" gradient background animation, context menus for native swipe-like interaction on lists, and hierarchical colored empty states.
  - *Tech Notes*: 
    - Updated `MetricCard` and `ValueDelta` in `DesignSystem.swift` to use `.contentTransition(.numericText())`.
    - Added infinite scale/rotation animation loop to `ScreenBackground` in `DesignSystem.swift`.
    - Replaced non-functional `.swipeActions` in `ScrollView` with `.contextMenu` across `InvestmentsView.swift`, `CryptoView.swift`, and `CashFlowView.swift`.
    - Updated `EmptyState` symbol rendering to `.hierarchical`.

- [2026-06-10T15:40:00+02:00]: Fix: UI Overflow in Data Rows
  - *Details*: Fixed layout squishing and text wrapping in Investment and Crypto rows.
  - *Tech Notes*: Added `lineLimit(1)`, `minimumScaleFactor(0.8)`, and `fixedSize()` to text elements to prevent badge truncation and multi-line wrapping in `InvestmentsView.swift` and `CryptoView.swift`. Used `Spacer(minLength: 8)` to ensure proper spacing between columns.

- [2026-06-10T17:53:00+02:00]: Fix: Web App Chart Edge Clipping & Interpolation Artifacts
  - *Details*: Fixed a graphical artifact in the Net Worth chart where the line was abruptly cut off at the very edges and `curveMonotoneX` produced overshoots at the start/end points causing the line to dip below or extend past the visible data markers.
  - *Tech Notes*: Updated `NetWorthChart.tsx`. Increased horizontal `margin` (left: 20, right: 20) on the `AreaChart` to prevent point clipping and replaced `type="monotone"` with `type="linear"` to strictly connect data points without Bezier curve overshoots.

- [2026-06-10T15:58:00+02:00]: Web App UI Enhancements Phase 3
  - *Details*: Migrated the premium feel of the iOS app over to the React Web application by adding rolling animated number counters, scroll-driven reveal animations, and an ambient breathing background.
  - *Tech Notes*: 
    - Created an `AnimatedNumber.tsx` component using `framer-motion`'s `useSpring` and `useTransform` to achieve smooth odometer effects.
    - Wrapped `StatCard.tsx` stat text with `<AnimatedNumber />`.
    - Integrated `framer-motion`'s `motion.div` with `whileInView` into `Dashboard.tsx` to add staggered scroll reveals.
    - Added an `.ambient-bg` CSS animation in `index.css` and injected it into `Dashboard.tsx` for a rotating gradient blur backdrop in dark mode.

- [2026-06-10T19:15:00+02:00]: macOS Settings Responsive Layout Enhancement
  - *Details*: Upgraded the macOS app settings page with a custom responsive masonry layout, moving from a single long vertical list to a dynamic multi-column grid that optimizes screen space usage on wide desktop screens.
  - *Tech Notes*:
    - Created `DynamicMasonryLayout.swift` adopting the `Layout` protocol to dynamically handle columns and heights.
    - Added `DynamicMasonryLayout.swift` to Xcode targets (`WealthCompassMac`, `WealthCompassMobile`).
    - Updated `MacSettingsView.swift` tabs to use `DynamicMasonryLayout` with a minimum column width of 380pt.
    - Adjusted max frame width constraints in `MacSettingsView.swift` to allow the grid layout to expand.

- [2026-06-10T19:19:00+02:00]: Net Worth Timeframe Selector UI Enhancement
  - *Details*: Replaced the native segmented picker on the macOS Dashboard's net worth chart with a sleek, custom-built glassmorphism pill selector.
  - *Tech Notes*: 
    - Implemented `timeframeSelector` in `MacDashboardView.swift`.
    - Used `matchedGeometryEffect` for smooth capsule selection animation.

- [2026-06-10T19:22:00+02:00]: Cash Flow Timeframe Selector
  - *Details*: Abstracted the glassmorphism pill selector into a generic `DashboardSegmentedPicker` and applied it to the Cash Flow card.
  - *Tech Notes*: 
    - Refactored timeframe selector logic in `MacDashboardView.swift` to be reusable.
    - Added `CashFlowTimeframe` enum to support 3M, 6M, and 12M cash flow trend ranges.

- [2026-06-10T19:26:00+02:00]: Cash Flow View Timeframe Selector
  - *Details*: Reused the generic `DashboardSegmentedPicker` for the macOS Cash Flow view (Overview Tab) to match the dynamic 3M/6M/12M ranges introduced on the Dashboard.
  - *Tech Notes*: 
    - Made `CashFlowTimeframe` and `DashboardSegmentedPicker` internal in `MacDashboardView.swift` so they can be consumed by `MacCashFlowView.swift`.
    - Updated the cash flow trend card to adapt to `cashFlowRange` dynamically.
- [2026-06-10T19:39:00+02:00]: macOS Crypto View Refactoring
  - *Details*: Grouped Top Performer and Biggest Loser into a single FinanceCard for a cleaner design to match the Crypto Allocation layout height.
  - *Tech Notes*:
    - Updated `MacCryptoView.swift` to wrap the `performanceSection` `VStack` in a single `FinanceCard`.
    - Added a `Divider()` between the Top Performer and Biggest Loser cards.
    - Adjusted paddings to ensure identical box sizing.
- [2026-06-10T19:41:00+02:00]: macOS Crypto View Refactoring (continued)
  - *Details*: Centered the Top Performer and Biggest Loser vertically inside their combined `FinanceCard` container.
  - *Tech Notes*: Removed `alignment: .top` from the `VStack`'s frame modifiers inside `MacCryptoView.swift` to allow natural vertical centering.

- [2026-06-10T20:20:00+02:00]: Fix: App Store Connect Upload Error (BGTaskSchedulerPermittedIdentifiers)
  - *Details*: Resolved the ITMS-90771 upload error regarding missing Info.plist values for background processing.
  - *Tech Notes*: Added the `BGTaskSchedulerPermittedIdentifiers` key to the iOS app's `Info.plist` with a list of identifiers (`$(PRODUCT_BUNDLE_IDENTIFIER).refresh`, `$(PRODUCT_BUNDLE_IDENTIFIER).processing`), which is required by App Store Connect when `UIBackgroundModes` contains `processing`.

- [6/10/2026, 9:46:43 PM]: Internationalization (i18n) via String Catalogs
  - *Details*: Implemented a scalable localization strategy for macOS and iOS apps using Xcode's String Catalogs (.xcstrings). The app now automatically detects the device language and gracefully falls back to English if the language is unsupported.
  - *Tech Notes*:
    - Created `apple/WealthCompass/Sources/Shared/Resources/Localizable.xcstrings`.
    - Updated `WealthCompass.xcodeproj` to enable Base Internationalization.
    - Added language regions: `it`, `de`, `es`, `zh-Hans`, `ar`.
    - Extracted and automatically translated all strings.

- [2026-06-10]: Model & Settings Localization Fix
  - *Details*: Performed an extensive audit to guarantee 100% string mapping across the codebase. Found and fixed several model enumerations and static default settings (like Categories, CloudKit Sync States, Currency names) that were returning unlocalized string literals. Wrapped them in `String(localized: "")` and extracted them to `Localizable.xcstrings`.
  - *Tech Notes*: Modified `FinanceModels.swift`, `AppSettings.swift`, and `CloudKitSyncService.swift`.

- [2026-06-10]: iOS Specific Services Localization Fix
  - *Details*: Checked iOS-specific implementations (Notifications and AppLock) and wrapped remaining hardcoded string literals with `String(localized:)` for full translation coverage.
  - *Tech Notes*: Modified `RecurringTransactionNotificationService.swift` and `AppLockStore.swift`.

- [2026-06-10]: Manual Language Selection Settings
  - *Details*: Added a dynamic language picker in the settings view for both iOS and macOS applications. This allows users to manually override the system language and choose any supported language from within the app.
  - *Tech Notes*: Modified `AppSettings.swift` to introduce an `appLanguage` property backed by `UserDefaults`. Injected `.environment(\.locale)` into the root views in `WealthCompassMobileApp.swift` and `WealthCompassMacApp.swift` to force SwiftUI to re-render in the chosen language instantly. Exported and translated the new settings UI strings.

- [2026-06-10]: Comprehensive String Audit and macOS Localization
  - *Details*: Audited all `.swift` files across the codebase to identify unlocalized strings missing `String(localized:)` wrapping. Identified multiple missing localizations primarily in the macOS platform layer (`MacRootView`, `MacAppModel`, `MacPlatformServices`, `MacInvestmentsView`).
  - *Tech Notes*: Replaced bare string literals with `String(localized:)` for notification titles/bodies, Biometric Touch ID/Face ID prompts, app navigation model titles, dashboard alert messages, and chart component titles (`AllocationChart`, `MetricCard`). Re-ran the Xcode localization extraction script to include these strings in `Localizable.xcstrings` and fully translated them across all supported languages.

- [2026-06-10]: App Store Connect Localized Metadata Scaffolding
  - *Details*: Generated the Fastlane metadata folder structure for all 39 App Store Connect supported languages to automate App Store Optimization (ASO). Configured `Deliverfile` to strictly ignore screenshots to prevent overwriting existing custom designs.
  - *Tech Notes*: Created `fastlane/metadata/` with subfolders for each region (e.g., `en-US`, `zh-Hans`, `es-ES`). Each contains text files for `name`, `subtitle`, `description`, `promotional_text`, and `keywords`. Created `fastlane/Deliverfile` with `skip_screenshots(true)` and `overwrite_screenshots(false)`.

- [2026-06-20T14:04:03+02:00]: App Store Connect Release Notes Update
  - *Details*: Updated the "What's New in This Version" field (`release_notes.txt`) for all languages to "UI improvements" via Fastlane metadata.
  - *Tech Notes*: Run `fastlane deliver` to publish these to App Store Connect.

- [2026-06-20T18:29:00+02:00]: Transaction Edit & Delete Feature (iOS & macOS)
  - *Details*: Implemented full transaction edit and delete capability across both iOS and macOS apps. Users can now tap any transaction to open an edit form (reusing the same popup as the add-transaction form, pre-populated with existing values), and delete transactions via context menus or inline buttons.
  - *Tech Notes*:
    - **FinanceStore.swift**: Added `updateTransaction()` method that updates a transaction in place by ID (type, amount, category, description, date) while preserving its original ID and recurring references.
    - **iOS Forms.swift**: Refactored `TransactionFormView` to accept an optional `Transaction` parameter and an optional `onDelete` closure. When editing, all fields are pre-populated and an explicit "Delete Transaction" button is shown at the bottom of the form for better discoverability. The `onSave` callback now passes the original `Transaction?` to distinguish add vs update.
    - **iOS CashFlowView.swift**: Added `@State transactionToEdit`, tap gesture on transaction rows to open edit sheet, context menu with Edit and Delete options, and a dedicated `.sheet(item:)` for the edit flow.
    - **iOS DashboardView.swift**: Updated `TransactionFormView` call site to match new signature.
    - **macOS MacCashFlowView.swift**: Updated `MacCashFlowEditor` enum to `.transaction(Transaction?)`, added tap gesture and edit/delete buttons to transaction cards, refactored `MacCashFlowTransactionEditor` with `init(transaction:onSave:)` for pre-population, updated sheet handler to route add vs update.
    - Both iOS and macOS builds verified successfully via `xcodebuild`.

- [2026-06-20T18:44:00+02:00]: Historical Net Worth Snapshot Recalculation
  - *Details*: Fixed a bug where deleting or editing historical cash flow transactions did not retroactively update the Net Worth history graph. The app now recalculates past snapshots dynamically when transactions are modified.
  - *Tech Notes*:
    - **FinanceStore.swift**: Introduced `adjustHistoricalSnapshots(from:liquidityDelta:)` which iterates over existing snapshots on or after the transaction's date and applies the exact cash delta to `liquidity`, `totalAssets`, and `netWorth`.
    - Applied this helper to `addTransaction()`, `deleteTransaction()`, `updateTransaction()`, and `processDueRecurringTransactions()` ensuring the net worth graph is instantly accurate without requiring a full rebuild from scratch.

- [2026-06-20T18:54:00+02:00]: App Store Connect Version Bump (macOS Upload Fix)
  - *Details*: Fixed the App Store Connect submission error "Invalid Pre-Release Train. The train version '1.0.4' is closed for new build submissions" by bumping the MARKETING_VERSION (CFBundleShortVersionString).
  - *Tech Notes*:
    - **project.pbxproj**: Incremented `MARKETING_VERSION` from `1.0.4` to `1.0.5`.

- [2026-06-20]: App Store Metadata Translation & Upload
  - *Details*: Translated all App Store Connect metadata from English to 38 supported languages and pushed the updates to App Store Connect.
  - *Tech Notes*: Executed `translate_metadata.cjs` and `translate_bing.cjs` to handle translation and rate limit fallback. Enforced App Store character limits (170 for promotional text, 100 for keywords) using `fix_lengths.cjs`. Used `fastlane deliver --force` with `FASTLANE_ITC_TEAM_NAME` to push the translated metadata fields to the respective App Store Connect locales.

- [2026-06-21]: App Store Connect Release Notes & Submission
  - *Details*: Updated the "what"s new in this version" (release notes) to "UI Improvements" for all localized languages and successfully submitted version 1.0.5 of the iOS application for review.
  - *Tech Notes*:
    - Created/updated `release_notes.txt` in all `fastlane/metadata/*/` locale directories.
    - Executed `fastlane deliver` with `FASTLANE_ITC_TEAM_ID` set to `128920131` ("Simone Mattioli" group) and `--submit_for_review true` to process the metadata upload and submission.

- [2026-06-22]: App Store Connect Release Notes Update (1.0.6)
  - *Details*: Updated the "What's New in This Version" (release notes) to "Translations improvements" for all localized languages for iOS version 1.0.6.
  - *Tech Notes*:
    - Modified `release_notes.txt` in all `fastlane/metadata/*/` locale directories.
    - Executed `fastlane deliver` with `FASTLANE_ITC_TEAM_ID` set to `128920131` ("Simone Mattioli" group), `--app_version 1.0.6`, and bypass flags for binaries/screenshots.

- [2026-06-22]: Fix Italian Translation for "Crypto"
  - *Details*: Changed the Italian translation of "Crypto assets" from "Risorse crittografiche" to "Criptovalute" to make it contextual for a financial application.
  - *Tech Notes*: Modified `Localizable.xcstrings` line 30983.

- [2026-06-22]: Settings Layout Update
  - *Details*: Moved Exchange Rates from a popover in the Global Currency section to its own dedicated Card at the bottom of the Settings page.
  - *Tech Notes*: Modified src/pages/Settings.tsx to extract the currencyRates iteration into a new card.

- [2026-06-23]: Increment Application Version
  - *Details*: Incremented the application version to 1.0.7 for the upcoming release.
  - *Tech Notes*: Updated `MARKETING_VERSION` to `1.0.7` and `CURRENT_PROJECT_VERSION` to `8` in `project.pbxproj` for the Apple/iOS App.

- [2026-06-28]: Fix "Picker selection is invalid" warning in transaction & category editors (Apple)
  - *Details*: The Category `Picker` in the iOS and macOS transaction and recurring-transaction editors logged `Picker: the selection "Food"/"Salary" is invalid and does not have an associated tag` whenever the selected `category` was not present in `AppSettings.transactionCategories(for: type)`. Two triggers: (1) transiently while toggling the Type segmented control — the selection still holds the previous type's category until `onChange(of: type)` resets it; (2) editing an imported/legacy transaction whose category isn't in the default+custom set. Fix preserves the stored value (no silent rewrite) and silences the warning.
  - *Tech Notes*: In each Category `Picker`, render a fallback tag before the `ForEach`: `if category != Self.customCategoryTag && !categories.contains(category) { Text(category).tag(category) }` (macOS uses `Text(LocalizedStringKey(category))` to match its existing localization). Files: `Sources/iOS/Views/Forms.swift` (TransactionFormView + RecurringTransactionFormView), `Sources/macOS/Views/MacEditorSheet.swift`, `Sources/macOS/Views/MacRecurringTransactionEditor.swift`. No data-model/persistence change. **Not built locally** — only Command Line Tools are installed (no `Xcode.app`), so `xcodebuild` can't run; `swiftc -parse` is clean. Compile/verify on Xcode.
  - *Diagnostics (separate, still open)*: Added `CG_NUMERICS_SHOW_BACKTRACE=1` to the `WealthCompassMobile` Run scheme to localize the NaN→CoreGraphics flood (`Error: …invalid numeric value (NaN…)` + `CGPathCloseSubpath: no current point`). The data pipeline is already `isFinite`-guarded (`CurrencyConverter`, `AnalyticsEngine.snapshotsForChart`, exchange rates, import decoders), so the emitter is geometric/view-layer (candidates: the perpetually-animated `ScreenBackground`, or the net-worth `Chart`'s spring). Awaiting the runtime backtrace to pinpoint. Env var is diagnostic-only and must be removed afterward.

- [2026-06-28]: Yahoo Finance fallback so non-US listings (e.g. VWCE) auto-update on price refresh (Apple)
  - *Details*: A 3-holding portfolio (VWCE, NFLX, GOOGL) reported only "2 updated" on every price refresh. Root cause: every holding is priced through Finnhub's free `/quote`, whose **free Demo tier only covers US-listed securities**. NFLX/GOOGL (NASDAQ) price fine; VWCE (a European-listed UCITS ETF) comes back with a zero price (`c: 0`), which `FinnhubQuoteClient` correctly rejects as `.noQuote` (`MarketDataService.swift`), so it lands in `failedInvestments`. Not a loop bug — a provider limitation. Added a **keyless Yahoo Finance fallback** consulted *only* when Finnhub returns `.noQuote`, so European/other non-US listings now update too. Yahoo returns the listing's currency, so the price is stored in the holding's own currency instead of Finnhub's hardcoded `.usd`.
  - *Tech Notes*:
    - New `YahooQuoteClient` in `Sources/Shared/Services/MarketDataService.swift` — keyless, injectable `URLSession`, routed through `NetworkRetry`, browser `User-Agent` header. New endpoints in `APIConfiguration`: `yahooChartURL` (`/v8/finance/chart/<symbol>`) and `yahooSearchURL` (`/v1/finance/search`). No API key, no Keychain entry, no new dependency.
    - Symbol-resolution cascade (mirrors `CryptoHolding.coinGeckoID`): explicit exchange suffix (`VWCE.MI`) → ISIN search → bare-symbol search. `bestCandidate(...)` keeps ETF/equity types, prefers a currency match (avoids an FX hop), tie-breaks by Jaccard name similarity, else Yahoo's top-ranked result. London pence (`GBp`/`GBX`) normalized to major units; an unmodelled currency fails cleanly (a safe no-update, never a wrong value).
    - Wired into `FinanceStore.refreshMarketPrices`: on Finnhub `.noQuote`, fetch via Yahoo, then re-express the price in the holding's currency with `settings.convert(...)` (mirrors the crypto path) before storing. Other Finnhub errors (rate-limit/auth/network) keep their existing behavior. Scope: only runs when a Finnhub key is present (no-key holdings are still skipped, as before).
    - Tests: `Tests/MarketDataServiceTests.swift`, registered in `project.pbxproj` (UUID `C7`; `plutil -lint` OK). Covers chart/search decoders, `GBp` normalization, zero/unknown-currency rejection, and disambiguation.
    - **Not built locally** — only Command Line Tools are installed (no `Xcode.app`), so `xcodebuild`/XCTest can't run here. The decoder + scorer logic was extracted verbatim and verified green with the standalone `swift` toolchain (16/16 assertions). Compile, run `WealthCompassTests/MarketDataServiceTests`, and smoke-test a live refresh on Xcode.

- [2026-06-28]: Price-refresh "last updated" fix + investment/crypto sync audit (Apple)
  - *Details*: Reported bug — after a successful price refresh the per-row "last update" on the investments page stayed an old date. Root cause: the refresh apply loops set `updatedAt = quote.asOf` (the *market* close timestamp) while every other store mutation uses `Date()`; on a date-only row a refresh after the last close showed the old close date. Fixed to a single `refreshedAt = Date()` reused by both apply loops and `result.refreshedAt`. Then audited the investment + crypto sync/refresh path (two parallel read-only agents, every claim re-verified against source) and implemented four items the user selected.
  - *Tech Notes*:
    - **Fix** (`FinanceStore.swift`): apply loops now stamp `updatedAt` with the refresh time, not the quote's market time. Side benefit: `shouldAutoRefreshMarketPrices` staleness is now measured from the real refresh, not the (always-past) market time.
    - **I1 — sync-churn guard** (`FinanceStore.swift`): the apply loops now only write `currentPrice`/`currentValue`/`updatedAt` when the price actually changed (crypto also on a first-time `coinId` backfill). Because the CloudKit payload hash includes `updatedAt` (`CloudKitSyncService.swift:131`), this stops unchanged holdings from re-syncing on every refresh. Trade-off accepted by the user: on a flat-price refresh that row's date won't move (the dialog's "Last refresh" still shows now). The `result.updated*` counts still reflect every re-priced holding.
    - **I2 — crypto symbol auto-resolution** (`MarketDataService.swift` + `FinanceStore.swift` + `APIConfiguration.swift`): holdings with no explicit `coinId` and not in the built-in map (e.g. `S`) are now resolved via CoinGecko `/search` (`coinGeckoSearchURL`) instead of being skipped. `CoinGeckoPriceClient.bestCoinID(...)` takes the exact ticker match with the best market-cap rank, falling back to a *unique* exact name match, else nil (skip, never mis-price). Skip message changed to "no matching CoinGecko coin".
    - **I3 — keyless Yahoo for investments** (`FinanceStore.swift`): the investment loop was restructured so Yahoo runs as the sole (keyless) source when no Finnhub key is set — previously all investments were skipped without a Finnhub key. With a key, Finnhub stays primary and Yahoo remains the `.noQuote` fallback. Shared Yahoo resolution extracted into a local `yahooQuote(for:)`.
    - **B1 — CoinGecko partial-batch fix** (`MarketDataService.swift`): `priceTable(for:)` now accumulates per-100-coin chunks and only throws if *every* chunk failed, so one failed batch no longer discards already-fetched prices (>100-coin portfolios).
    - **Audit — investigated and explicitly NOT changed** (guard against future "fixes"): the conflict-resolution hash tiebreaker (`CloudKitSyncService.swift:1494`) is correct — it only fires for non-deliberate records with an exact `updatedAt` tie, and `local.hash > remote.hash` is deterministic *and convergent* across devices; the suggested "compare UUIDs" fix is broken (same record id on both sides). The Finnhub hardcoded `currency: .usd` (`MarketDataService.swift:311`) is inert for investments — the apply loop stores the raw price and never reads `quote.currency` on the Finnhub path.
    - Tests: added CoinGecko `/search` decode + `bestCoinID` cases to `Tests/MarketDataServiceTests.swift`.
    - **Not built locally** (Command Line Tools only). All changed Swift files pass `swiftc -parse`; the new CoinGecko decoder/scorer logic was verified verbatim with the standalone `swift` toolchain (10/10 assertions). Compile + run `WealthCompassTests/MarketDataServiceTests` and smoke-test a refresh on Xcode.

- [2026-06-28]: Professional hardening of the two audited non-bugs — currency unification + sync-conflict docs/tests (Apple)
  - *Details*: Neither audited item was a correctness bug, but both were tidied to a professional standard. (1) Finnhub's `currency: .usd` was inert but misleading, and the three price paths converted currency in three different places. (2) The conflict tiebreaker is correct; the proposed "server `modificationDate`" upgrade was investigated and **rejected as unsound** — in a local-vs-remote conflict the local side is a *pending* change with no fresh server timestamp, so comparing server dates would make the remote win almost always and systematically lose local edits. The correct signal is the domain `updatedAt`, which the code already uses. So the sync work is hardening (a property test + docs), not a logic change.
  - *Tech Notes*:
    - **Currency unification** (`MarketDataService.swift` + `FinanceStore.swift`): `MarketPriceQuote.currency` is now `Currency?` — `nil` means "source didn't report one" (Finnhub's `/quote`), instead of fabricating `.usd`. A single private `FinanceStore.storedPrice(_:from:to:settings:)` is the one conversion boundary for **all three** sources: it maps a `nil` source currency to the holding's own (so it's a no-op for USD-on-USD) and converts via FX otherwise, crossing to `Decimal` and dropping non-finite quotes. Yahoo and CoinGecko now return their **native** price+currency (Yahoo's `yahooQuote` helper no longer pre-converts; `cryptoQuotes` carries `currency`), so conversion happens once, at the apply loop, for Finnhub/Yahoo/crypto alike. H2 (never re-base a holding's currency) is preserved — the convert is a no-op when source == holding currency.
    - **Sync hardening** (`CloudKitSyncService.swift` + `Tests/CloudSyncCoreTests.swift`): expanded the `bootstrapDecision` doc to record *why* it compares domain `updatedAt` and not server `modificationDate`, and why the hash tie-break is convergent — so the "scary" finding isn't re-opened. Added `testBootstrapDecisionTieBreakIsConvergentAcrossDevices`, which asserts the **property** (both devices select the same payload across many mirror-image pairs) directly, rather than re-deriving the hash formula like the existing test.
    - **Verification** (no Xcode here): all touched files pass `swiftc -parse`. A standalone `swift` harness verified, against verbatim copies of the logic, the optional-currency promotion (so existing `MarketDataServiceTests` assertions still compile), the `storedPrice` rule (nil/same-currency → no-op; cross-currency → FX), and **convergence over 1000 mirror pairs (0 divergences)** — 11/11 assertions. Run `WealthCompassTests` (esp. `CloudSyncCoreTests` + `MarketDataServiceTests`) on Xcode and smoke-test a refresh.

- [2026-07-06T20:34:19+02:00]: App Version Bump & Metadata Translation for App Store Connect Release
  - *Details*: Incremented the app version numbers across the codebase and generated localized release notes across 38 languages to prepare for the App Store release.
  - *Tech Notes*: Bumped `MARKETING_VERSION` to `1.0.10` and `CURRENT_PROJECT_VERSION` to `11` in `project.pbxproj`. Updated `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`. Bumped root `package.json` version to `1.0.10` and updated the tracking comment in `fastlane/Fastfile`. Ran automated scripts to translate the new App Store Connect `release_notes.txt` to all supported languages.

- [2026-07-06T23:04:00+0200]: Fix Catalan App Store Metadata Limits
  - *Details*: Shortened the Catalan App Store Connect promotional text and keywords to conform to Apple's length limits. The upload previously failed due to these limits, triggering a false positive fastlane needs an update message.
  - *Tech Notes*: Edited apple/WealthCompass/fastlane/metadata/ca/keywords.txt and promotional_text.txt to be under 100 and 170 characters respectively. Reran fastlane ios metadata.

- [2026-07-06T23:04:58+0200]: Fix Catalan App Store Metadata Name Limit
  - *Details*: Shortened the Catalan App Store Connect app name to conform to Apple's 30 character length limit. The second upload failed due to this remaining long string.
  - *Tech Notes*: Edited apple/WealthCompass/fastlane/metadata/ca/name.txt to Brúixola de la Riquesa. Reran fastlane ios metadata.

- [2026-07-10T21:00:00+02:00]: App Version Bump (1.1.0) & Metadata Translation
  - *Details*: Incremented the app version across the codebase to 1.1.0 for an App Store release and updated the release notes.
  - *Tech Notes*: Bumped `MARKETING_VERSION` to `1.1.0` in `project.pbxproj`. Updated `CFBundleShortVersionString` to `1.1.0` in `Info.plist`. Bumped root `package.json` version to `1.1.0`. Added a `:metadata` lane for macOS in the `Fastfile` and ran automated scripts to translate the new App Store Connect `release_notes.txt` to all supported languages.

- [2026-07-13]: Broker / Bank Statement CSV Import (Revolut + Trade Republic), auto-detected — iOS & macOS
  - *Details*: The import flow now accepts CSV statements in addition to the native JSON backup, and **auto-detects** the format so the user never picks a provider. Three formats are recognized by content signature: a native Wealth Compass JSON backup, a **Trade Republic** flat transaction export (`Transaction export.csv` shape — cash + securities trades), and a **Revolut** consolidated statement (multi-section: per-currency transaction tables + crypto holdings). The single "Import Data…" button on both platforms routes automatically; the summary sheet names the detected format. Trade Republic uses a real user sample (see caveat in `TO_SIMO_DO.md` re: provenance). PDF ingestion is intentionally out of scope (CSV carries the same data far more reliably).
  - Mapping is **full-fidelity and net-worth-exact**: cash rows → income/expense transactions (by amount sign); a `TRADING`/`BUY` → an `Investment` holding aggregated by ISIN **plus** a matching "Investments" cash-out expense, so liquidity (which is `Σ transactions` in `AnalyticsEngine`) stays correct — a purchase moves cash→asset with the only net-worth delta being the real trade fee; a `TRADING`/`SELL` decrements the net holding (fully-sold positions drop out) **plus** a cash-in, so a liquidation doesn't leave a phantom holding; dividends/interest/stock-perks/referrals → income; Revolut crypto "End of Year holding statement" → `CryptoHolding`. Rows in a Revolut account section whose currency isn't representable (e.g. AED, outside the ECB-backed `Currency` set) are skipped rather than mislabeled with the previous section's currency. Imported holdings carry the **ISIN** (brokers export no ticker), so live-price refresh won't fire until a ticker is added; values are cost-based until then. Every record gets a **deterministic UUID** (CryptoKit SHA-256 of a stable key: the broker `transaction_id`, an ISIN, a crypto symbol, or `section+date+description+amount+balance`), so re-importing the same or an overlapping export **merges idempotently** via `FinancialData.mergedByID` instead of duplicating, and preserves in-app edits.
  - *Tech Notes*: New file `Sources/Shared/Services/BrokerStatementImportService.swift` (RFC-4180 `CSVTokenizer`, `BrokerImportParsing` helpers incl. deterministic UUID + statement/ISO date + multi-currency money parsing, `BrokerStatementImportService.detect/parse`, and the two provider parsers) — added to both app targets in `project.pbxproj`. `FinanceStore` gains `importFile(from:mode:settings:)` (detects JSON vs CSV, parses off the MainActor) and a shared `applyImport(...)` tail refactored out of `importBackup` (retained for JSON callers/tests); `FinanceImportError` gains `.unrecognizedFormat` / `.malformedCSV`; `FinanceImportResult` gains `detectedSource` (shown in `ImportSummaryView`'s header). iOS `SettingsView` + macOS `MacSettingsView` widen the picker to `[.json, .commaSeparatedText, .plainText]`, rename the button to "Import Data", and call `importFile`. New tests `Tests/BrokerStatementImportServiceTests.swift` (synthetic anonymized fixtures). No third-party dependencies (Foundation + CryptoKit only). `IMPORT_TEMPLATE/` (real PII samples) added to `.gitignore`.
  - *Verification* (no Xcode in this environment — only Command Line Tools): the parser logic was compiled with `swiftc` against stubs mirroring the real model initializers and **run against the two real sample CSVs** — Trade Republic: 83 transactions + 3 ISIN-aggregated holdings (BUYs net to exactly −€1.00 = the trade fee, confirming no double-count), idempotent re-parse; Revolut: 114 multi-currency transactions + 7 crypto holdings, thousands-separators + `£… (€…)` cells parsed correctly, 0 malformed. The synthetic XCTest fixtures were run through the same compiled parser and match every asserted value. A parallel adversarial code review (compile-risk, parser-correctness, iOS/macOS wiring) reported **zero** compile/wiring issues and **four** confirmed correctness bugs the sample data couldn't reach — a `SELL` double-count (phantom holding), a dedup-UUID collision for same-ISIN same-day trades lacking a `transaction_id`, a timezone-dependent id seed, and unsupported-currency rows mislabeled with the prior section's currency — all now fixed and re-verified (full-liquidation → no holding + net worth = realized gain; partial sell → correct residual; no-`transaction_id` duplicate BUYs → distinct cash legs; AED section → skipped). The suite was then run for real on an iOS 26.5 simulator (iPhone 17): 18/19 `BrokerStatementImportServiceTests` passed and the one failure surfaced a genuine bug the LF-only samples couldn't — Swift treats a `\r\n` as a single `Character` (grapheme cluster), so the char-by-char `CSVTokenizer` never saw CRLF as a row terminator and would collapse a Windows/CRLF-encoded export into one row. Fixed by normalizing CRLF/CR → LF before tokenizing (re-verified: the failing input now yields 2 rows; a CRLF-encoded file parses; LF files unchanged).

- [2026-07-13]: Release-hardening of the CSV import (post-test-pass)
  - *Details*: Two follow-ups before shipping the feature. (1) **Locale-tolerant amounts** — `plainDecimal`/`statementDecimal` now share a `flexibleDecimal` that parses both English (`1,234.56`) and European/German (`1.234,56`, `123,45`) number formats, not just the dot-decimal ISO of the sample files, so a German-formatted Trade Republic export isn't silently mis-parsed ~100×. Rule: with both separators the later one is the decimal point; a lone separator is decimal when single, thousands when repeated; ISO values like `5000.000000` are preserved. (2) **Localization** — the six new user-facing strings ("Import Data", "Import Data...", "Detected format: %@.", the unrecognized-format and malformed-CSV errors, and the reworded no-records error) were added to `Localizable.xcstrings` as `extractionState: manual` source entries for the translation pipeline to fill (they fall back to English until translated).
  - *Tech Notes*: New `BrokerImportParsing.flexibleDecimal(_:)` + tests (`testFlexibleNumberFormatsEnglishAndEuropean`, `testGermanFormattedTradeRepublicAmountParses`). `Localizable.xcstrings` grew from 652 → 658 strings (source-only; validated as JSON). Verified via the standalone `swiftc` harness across every prior case plus the new number formats — all green.

- [2026-07-13]: Imported-holding ticker backfill (display polish) + limitation correction
  - *Details*: Corrected an earlier mis-assessment: imported holdings **already auto-refresh**. The existing `YahooQuoteClient.resolvedQuote` searches Yahoo **by ISIN** (keyless, covers US stocks *and* European ETFs), and `refreshMarketPrices` routes non-USD holdings straight to it — so a holding stored with `symbol`/`isin` both set to the ISIN prices correctly. The only real gap was cosmetic (the ticker column shows the ISIN). Now the first refresh **persists the Yahoo-resolved exchange-qualified symbol back to `Investment.symbol`** (mirroring the crypto `coinId` backfill), so the UI shows `GOOGL`/`VWCE.DE` instead of `US02079K3059`. Also confirmed the "no cross-format dedup" item is a non-issue by design (one format per provider; cross-provider records are legitimately distinct).
  - *Tech Notes*: `YahooQuoteClient.resolvedQuote` now returns `(quote, resolvedSymbol)`; the refresh collects `resolvedSymbols` per holding and backfills `symbol` in the apply loop, guarded on `symbol == isin` (never overwrites a user ticker) and bumping `updatedAt`/re-sync only on a real change. No import-path change (parse stays offline). Both files syntax-parsed clean; needs an Xcode build to type-check (the store isn't standalone-compilable). **PDF import remains pending real sample files.**

- [2026-07-13]: Trade Republic PDF import (Account statement + Net Worth)
  - *Details*: Added auto-detected PDF import for the two Trade Republic statements (the user's real files). Revolut PDF is intentionally **not** supported — its data is identical to the Revolut CSV that already imports reliably, so a Revolut PDF errors with a "use the CSV" message. Both TR PDFs are Italian, European-number-format, and PDFKit flattens their tables — handled with two techniques verified against the real files: **`Account statement.pdf`** (transactions) recovers the lost income/expense column by inferring sign from the **running-balance delta** (seeded from SALDO INIZIALE); **`Net Worth.pdf`** (portfolio snapshot) collects the name/qty/ISIN lines and the separately-extracted, scrambled price/value number block, then **zips them by position, validating each pair with `value ≈ quantity × price`**. Net Worth holdings use the same `tr-holding:<ISIN>` id as the CSV parser (so they merge, not duplicate); its cash balance imports as one Liquidity transaction. Provenance now fully resolved: `Transaction export.csv` **is** the TR export — its BUY quantities exactly equal the Net Worth holdings.
  - *Tech Notes*: `BrokerStatementImportService` gains `import PDFKit`, `extractText(fromPDF:)`, `parsePDFText(_:context:)` (detects TR-account vs TR-net-worth by content, throws `unrecognizedFormat` otherwise), two new `Format` cases, and the `TradeRepublicAccountPDFParser` / `TradeRepublicNetWorthPDFParser` (pure text→data, so testable without PDFKit). `BrokerImportParsing` gains Italian (`01 lug 2026`) + dotted (`13.07.2026`) date parsers, `euroAmounts`, `isPureNumberLine`. `FinanceStore.importFile` sniffs PDFs (`%PDF` / `.pdf`) and routes them through PDFKit extraction; iOS/macOS pickers now accept `.pdf`. Whole-word ETF-type detection (a naive `contains("ETF")` mis-tagged "n·ETF·lix"). New tests use synthetic extracted-text fixtures. Verified end-to-end against the real files via a `swiftc`+PDFKit harness. `import PDFKit` auto-links (the project's Frameworks phases are empty; all system frameworks auto-link) — no pbxproj change.

- [2026-07-13]: Professional-review hardening of the whole import feature (CSV + PDF)
  - *Details*: Ran a 4-dimension adversarial review workflow (pdf-correctness, compile-safety, regression, professionalism) with per-finding verification: 17 raised, 14 confirmed, all addressed. The headline change: **the Net Worth PDF now imports as a single `NetWorthSnapshot`, not as holdings + cash.** The review confirmed three *major* data-integrity defects when the earlier holdings-based version was combined with the transaction CSV — (a) the scrambled price/value zip mis-paired every holding on a single stray/missing number line and emitted garbage 0/0 holdings; (b) the snapshot holdings shared the `tr-holding:<ISIN>` id with the CSV holdings and clobbered their real cost basis on merge (gains zeroed); (c) the lump-sum cash transaction double-counted liquidity against the CSV's per-row cash. Importing the "net worth statement" as a `NetWorthSnapshot` (date + the three labeled summary totals — netWorth/investments/liquidity, in EUR) dissolves all three: no fragile zip, no id collision, no cash double-count. Actual holdings (with cost basis) come from `Transaction export.csv`; the snapshot adds a net-worth history point.
  - The **account-statement PDF** parser was hardened too: it now uses the *printed* amount for magnitude (with the running-balance delta only for the sign), requires ≥2 amounts per row, and cuts the description before the printed amount — robust against a number embedded in a merchant name or an off opening balance.
  - Polish: dedicated `FinanceImportError.malformedPDF` (was reusing `.malformedCSV`) and `.unsupportedPDFStatement` (a Revolut PDF now gets "PDF statements are supported for Trade Republic only — import the CSV instead" rather than a generic message); the unused `context` param and the duplicated `slice` helper were removed (shared `BrokerImportParsing.between/firstMatch/amountAfter/euroAmountMatches`); new error strings added to `Localizable.xcstrings` (now 660 strings). Format `displayName`s remain English format identifiers (contain brand names) — a minor follow-up.
  - *Tech Notes*: `TradeRepublicNetWorthPDFParser` reduced to a summary-totals → `NetWorthSnapshot` parse (id `tr-pdf-networth:<date>`, idempotent). Re-verified against the real `Account statement.pdf` (5 transactions, income €7,13 / expense €56,45) and `Net Worth.pdf` (one snapshot: netWorth €12.480,55, investments €6.958,80, liquidity €5.521,75, currency EUR), plus the full CSV suite — all green via the harness. Tests updated (`testTradeRepublicNetWorthPDFImportsSnapshot`, `testRevolutPDFTextIsRejectedWithHelpfulError`).

- [2026-07-13T21:25:51+0200]: App Version Bump (1.2.0) & Web/App Release
  - *Details*: Incremented the app version across the codebase to 1.2.0, adding 3D public and Revolut imports (PDF and CSV).
  - *Tech Notes*: Bumped `MARKETING_VERSION` to 1.2.0 and `CURRENT_PROJECT_VERSION` to 13 in `project.pbxproj`. Updated root `package.json` version to 1.2.0. Updated release notes and translated them. Deployed web build and shipped iOS build via Fastlane.

- [2026-07-16T01:30:27+02:00]: Replicate macOS View Selectors on iOS (Investments & Crypto)
  - *Details*: Updated the iOS `InvestmentsView` and `CryptoView` to use a segmented picker at the top to toggle between tabs, mirroring the macOS implementation and iOS `CashFlowView`. The content in both pages is now split: the "Overview" tab shows summary cards, performance sections, and allocation charts, while the "Positions" (for investments) or "Holdings" (for crypto) tab shows only the list of positions/holdings.
  - *Tech Notes*:
    - **InvestmentsView**: Introduced `InvestmentsTab` enum (`.overview`, `.positions`), added `@State private var selectedTab`, and conditionally rendered sections based on selection.
    - **CryptoView**: Introduced `CryptoTab` enum (`.overview`, `.holdings`), added `@State private var selectedTab`, and applied similar conditional rendering logic.
    - Used the existing translated strings (`"Overview"`, `"Positions"`, `"Holdings"`) from `Localizable.xcstrings`, avoiding any new unlocalized string keys.

- [2026-07-16T01:33:48+02:00]: Set Net Worth Graph to Weekly View
  - *Details*: Changed the default timeRange for the net worth chart in iOS DashboardView from .oneYear to .oneWeek.
  - *Tech Notes*: Updated DashboardView.swift @State variable.

- [2026-07-16T01:40:00+02:00]: Make iOS Dashboard Cards Clickable
  - *Details*: Made the summary cards on the iOS Dashboard interactive. Tapping a card (e.g. Recorded Cash, Investments, Crypto) now cleanly navigates to its corresponding tab with a subtle visual bounce effect. "Total Assets" and "Liabilities" remain unclickable as they serve as high-level summaries without dedicated tabs.
  - *Tech Notes*: 
    - Updated `ContentView.swift` to track the active tab using `@State private var selectedTab` and assign tags to `TabView` items.
    - Modified `DashboardView.swift` to accept a `@Binding var selectedTab`, wrapping supported `MetricCard`s in `Button`s.
    - Added a custom `CardBounceButtonStyle` at the bottom of `DashboardView.swift` to handle press interactions seamlessly without altering the card's native look.

- [2026-07-16 21:26:36]: App Version Bump (1.1.2) & App Store Metadata Upload
  - *Details*: Incremented app versions and pushed translated metadata for App Store Connect release.
  - *Tech Notes*: Bumped MARKETING_VERSION to 1.1.2 and CURRENT_PROJECT_VERSION to 17. Ran fastlane ios metadata and fastlane mac metadata.

- [2026-07-17 07:21:12+0200]: Fix empty edit-form on first tap (iOS Investments/Crypto)
  - *Details*: On the iOS **Investments → Positions** and **Crypto → Holdings** lists, tapping a row opened the edit sheet **empty** on the first tap; a second tap showed it correctly pre-filled. Root cause: both views presented the editor with `.sheet(isPresented: $showingForm)` while reading the selected item from a *separate* `@State` (`editingInvestment` / `editingHolding`) that was set in the same tap handler. `InvestmentFormView`/`CryptoFormView` seed all their `@State` fields from the passed item **once**, in `init` (`State(initialValue:)`), and SwiftUI built that content view before the selection state propagated — so the form initialized from a `nil` item (empty defaults). Fixed by driving the sheet with `.sheet(item:)` keyed on item identity, so SwiftUI only builds the form once a concrete item exists and hands it in. macOS was already correct (it uses the `MacEditor` Identifiable enum + `.sheet(item:)`), so this only touched the two iOS views and brings them in line with that pattern.
  - *Tech Notes*:
    - **InvestmentsView.swift**: replaced `@State showingForm: Bool` + `@State editingInvestment: Investment?` with a single `@State activeForm: InvestmentFormRoute?`, a new `private enum InvestmentFormRoute: Identifiable { case add; case edit(Investment) }` (mirrors `MacEditor`, `id`/`investment` computed from the case). Add button → `activeForm = .add`; row tap, accessibility action, and context-menu Edit → `activeForm = .edit(investment)`. Sheet is now `.sheet(item: $activeForm) { InvestmentFormView(investment: $0.investment) … }` (the old `onDismiss` reset is no longer needed — `.sheet(item:)` nils the binding on dismiss).
    - **CryptoView.swift**: identical change with `CryptoFormRoute { case add; case edit(CryptoHolding) }` and `activeForm: CryptoFormRoute?`.
    - No model, form, or localization changes; `InvestmentFormView`/`CryptoFormView` and their `upsert*` calls are untouched. No new dependencies.
    - Verification: this environment has only Command Line Tools (no `xcodebuild`), so both files were `swiftc -parse`-checked (no syntax errors). Full type-check/build + on-device tap test are pending Xcode (see TO_SIMO_DO.md).

- [2026-07-17 08:30:51+0200]: Repository reorganisation — web app moved from root into `web-app/`
  - *Details*: The repo root was simultaneously the React/Vite web app and the container for `apple/`, so the two platforms sat at different levels and the root mixed build config with repo-wide docs. Moved every web concern into a new `web-app/` directory, making the root a pure two-platform container (`apple/` + `web-app/`) that now tracks only six files: `.gitignore`, `README.md`, `LICENSE`, `SECURITY.md`, `DOCUMENTATION.md`, `TO_SIMO_DO.md`. This reverses the previous README rationale ("the web app remains at the repository root so its existing Vite and GitHub Pages deployment stays stable"), which was verified obsolete before proceeding — see Tech Notes.
  - *Tech Notes*:
    - **Moved (140 renames, 136 of them byte-identical)**: `src/`, `public/`, `index.html`, `package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig{,.app,.node}.json`, `tailwind.config.ts`, `postcss.config.js`, `eslint.config.js`, `components.json`, `env_example.txt`, and the four web docs (`DEPLOYMENT.md`, `INSTALLATION.md`, `INSTALLATION_IT.md`, `IMPLEMENTATION_LOG.md`).
    - **Untracked (kept on disk)**: `dist/` (12 files) and `.DS_Store`, via `git rm --cached`. `dist/` was a committed duplicate of the deploy artifact — the live site is served from the `gh-pages` branch, which already holds that exact file set, and `predeploy` rebuilds it anyway. It had also been swept into unrelated Apple commits (e.g. `944da02`).
    - **Deleted**: `bun.lockb` (committed once in the 2025-01-01 scaffold `bebc3a2` and never updated, while `package-lock.json` moved 5 times — two lockfiles for one project is a footgun) and `prompt_saved.md` (a one-line note now permanently encoded in the global CLAUDE.md protocol).
    - **New**: `web-app/.gitignore` (`node_modules`, `dist`) and `web-app/README.md`, mirroring the self-contained structure `apple/` already had. Root `.gitignore` now carries only repo-wide concerns (`.DS_Store`, `IMPORT_TEMPLATE/`).
    - **`package.json`**: name `vite_react_shadcn_ts` → `wealth-compass-web` (template leftover; `private: true` so nothing publishes). `homepage` `libriperilcambiamento.github.io` → `simo-hue.github.io` — it disagreed with the `origin` remote. Vite ignores `homepage`, so this was cosmetic but wrong. `npm install` synced `package-lock.json`'s name and its stale `version: 0.0.0` → `1.1.1`.
    - **Docs corrected to match reality**: root `README.md` (layout tree, links repointed to `./web-app/`, and the false "Deployed via GitHub Actions" claim replaced with the actual manual `npm run deploy` flow), `web-app/DEPLOYMENT.md` (rewritten — it was a stale agent status note telling you to install `gh-pages`, which is already a devDependency), `web-app/INSTALLATION{,_IT}.md` (`cd wealth-compass` → `cd wealth-compass/web-app`, `.env` location).
    - **`apple/` deliberately untouched except two sentences about the web app's location**: `apple/README.md` (lines 78–87) and `apple/CLAUDE.md` both asserted the web app lives at the repository root and is deployed by `.github/workflows/deploy.yml`. Both claims are now false — the second has been false since June (see below). Zero Swift, Xcode project, resource, or fastlane files touched.
    - **`IMPORT_TEMPLATE/` left at the root untouched**: despite sitting at the root it is *Apple* material (it feeds `apple/.../BrokerStatementImportService.swift`; the web app has no CSV parsing at all), and it is gitignored personal financial data. It stays invisible to git, so the root is a pure container in the index regardless.
    - **Discovered, not fixed**: `.github/workflows/deploy.yml` was deleted in commit `ba8c852` (2026-06-22) whose message is "icloud fix" — an apparently accidental removal of CI in an unrelated commit. Deploys have been manual ever since. Logged in `TO_SIMO_DO.md` as a decision rather than fixed here, to keep this change structural.
    - **Verification**: `npm install` + `npm run build` in `web-app/` both succeed. The build emits `index-JeiMyvtz.css` and `index-LNODZzvC.js` — content hashes **identical** to the previously committed `dist/assets/*`, proving the relocated app builds to byte-identical output. `npm run lint` reports 52 pre-existing problems in files that are 100% renames (unrelated to this change). `npm run deploy` was **not** run: it publishes the live site and needs explicit approval.
    - No dependency, endpoint, or runtime-behaviour changes. All build config paths were verified file-relative before the move (`vite.config.ts` uses `__dirname`, Tailwind globs are `./src/**`, `tsconfig` uses `baseUrl: "."`, `index.html` uses Vite-root-relative paths), and no external host config (Vercel/Netlify/Lovable) exists that would pin the app to the root.

- [2026-07-17 09:05:00+0200]: Security audit of the public repo + history purge of real personal financial data
  - *Details*: Full secret-scan of the codebase and all git history ahead of pushing, since the repo is public. **No credential has ever been leaked** — but `apple/export template.json`, despite its name, was a real export of the owner's finances and had been public on `origin/main` since 2026-06-06 (commit `5ac5154`, formerly `ad6a4ff`): 139 transactions, 3 investments, 6 crypto holdings, 68 net-worth snapshots (€10,371 → €14,995), including GDPR Art. 9 health entries (`Analisi sangue`, `Pharmacy`, `supporto toracico`) and transactions naming third parties (`Cena con mia`, `teaching Maxim`, `Sito web Matteo`). The misleading filename is why it survived review for six weeks — it reads as a fixture, so nobody opened it. It was referenced by no code, test, or doc.
  - *Tech Notes*:
    - **Data preserved, not destroyed**: moved to the gitignored `IMPORT_TEMPLATE/` (which already holds exactly this class of data), plus a copy verified before any git operation ran.
    - **History rewrite**: `git filter-repo --invert-paths` over `apple/export template.json`, `mobile/export template.json`, `apple/WealthCompass/build/`, `WealthCompassMobile.ipa`, `WealthCompassMobile.app.dSYM.zip`, and the `.cursor/` logs. **The second path mattered**: the file lived at `mobile/export template.json` before the `mobile/` → `apple/` restructure, so the first pass left the data intact under the old path — caught only because verification used a content pickaxe (`git log -S"Analisi sangue"`) rather than trusting path matching or the tool's exit code.
    - **Force-pushed `main` (`443cf2d` → `55bf289`) and `code-audit` (`de068a9` → `fc0c11c`)** only. `gh-pages`, `gh-pages-webapp`, and `promotional-website` were byte-identical after the rewrite (they never contained the purged paths), so the **live site was untouched and not republished**.
    - **Result**: `.git` 409MB → 60MB; all 291 commits and 673 tracked files preserved. Verified from a *fresh clone of the remote* (not local state): 0 paths and 0 pickaxe hits for `Analisi sangue` / `teaching Maxim` / `14937.77`; `.ipa`, `mobileprovision`, and `dSYM` all 0.
    - **A local check gave a false negative and was caught**: `git cat-file -e origin/main:<path>` reported "clean" *before* the push because filter-repo had already pruned the blob from the local object DB. A fresh `git clone` proved GitHub was still serving the file. Local object checks are not valid tests of remote state.
    - **⚠ The purge is incomplete and cannot be finished locally.** The repo has 3 forks, so GitHub retains the objects in the shared fork network. Verified against the live API *after* the force-push: commits `443cf2d` and `ad6a4ff`, and blob `4a27b6bf6394b21bcc2c287935429d136421a37f` (the data), all still return **HTTP 200**. Only GitHub Support can purge these — logged as the top action in `TO_SIMO_DO.md`. The data must be treated as disclosed regardless.
    - **`.gitignore` hardened** (`apple/.gitignore`): `*.ipa`, `*.app.dSYM.zip`, `*.dSYM/`, `*.xcarchive`, `.cursor/`, `export*.json`, `*.export.json`. The absence of these rules is why the artifacts landed in the repo; without them it recurs.
    - **Verified clean across 291 commits / 5 branches / all blobs incl. binaries**: no `service_role` key (the only JWT in history decodes to `"role":"anon"` — publishable by design), no AWS/GitHub/Stripe tokens, no private keys, no `.env` ever committed. The Finnhub key is never inlined — bundles resolve `token=${t}` from `localStorage` at runtime, and the Apple app reads it from Keychain with no hardcoded fallback. **`IMPORT_TEMPLATE/` (real bank statements with IBANs) was never committed** — confirmed three ways including an IBAN regex over every text blob. `cloudkit-development.ckdb` is schema DDL with no data rows.
    - **Open security item**: Supabase project ref `tstmgujgiygcravqfoto` is public in the gh-pages bundle (expected — the anon key ships to browsers by design), which makes **RLS the entire security boundary**. `VITE_ALLOWED_EMAIL` in `AuthContext.tsx` is a client-side check and is trivially bypassable — UX, not security. Confirming RLS on every table is logged in `TO_SIMO_DO.md`.
    - **Commit hashes changed repo-wide**; doc references were remapped via `.git/filter-repo/commit-map` (`1e1b7cc` → `ba8c852`, `8b95230` → `944da02`). Pre-rewrite backup: `~/wealth-compass-BACKUP-before-history-rewrite.bundle` (268MB, `git bundle verify` passed) — it still contains the data and should be deleted once the remote purge is confirmed.
    - No dependency or runtime changes.

- [2026-07-18T09:15:00+02:00]: macOS Dashboard Header Padding Fix
  - *Details*: Fixed an alignment issue on the macOS Dashboard where the "Add Transaction" button was not aligned with the rest of the overview page content. 
  - *Tech Notes*: Added `.scenePadding(.minimum, edges: .horizontal)` to `dashboardHeader` in `MacDashboardView.swift` to match the padding of the main `ScrollView` content.

- [2026-07-27]: Fix GitHub Pages Deployment Crash
  - *Details*: Resolved an issue where the deployed website would render a blank page. The application was crashing on load because it expected Supabase environment variables that are missing in the GitHub Pages environment.
  - *Tech Notes*: Updated `src/lib/supabase.ts` to provide dummy fallback strings when `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are not set. This allows the Supabase client to instantiate without throwing a fatal error, allowing public routes (like the landing page) to render successfully. The fix was deployed to `gh-pages` branch using `npm run deploy`.

- [2026-07-27]: Added Apple App Store Link
  - *Details*: Added a prominent download button to the hero section on the landing page for the native macOS and iOS apps.
  - *Tech Notes*: Imported the official app icon to  and updated . Redeployed to .

- [2026-07-27]: Added Apple App Store Link
  - *Details*: Added a prominent download button to the hero section on the landing page for the native macOS and iOS apps.
  - *Tech Notes*: Imported the official app icon to src/assets/apple-icon.png and updated src/pages/Home.tsx. Redeployed to gh-pages.

- [2026-07-27]: PDF Report Export (iOS + macOS)
  - *Details*: Added a branded PDF report export alongside the existing JSON backup. A single "Export…" action on both platforms opens a shared sheet where the user picks the format (PDF / JSON) and, for PDF, the scope (full report or any subset of Overview / Cash Flow / Investments / Crypto) and a ledger date range. The full report opens with a branded cover, a clickable two-level contents page with real page numbers, and one section per page-break, and closes with an appendix disclosing the exchange rates used. Replaces the old two-tap "Prepare Backup" → "Share Backup" flow on iOS.
  - *Tech Notes*:
    - **New group `Sources/Shared/Export/`** (9 files, all registered in `project.pbxproj` by hand — no Xcode on the dev machine; UUIDs follow the existing `AC…`/`AD…` scheme using a new 3-hex `E<n>0/1/2` family per the `MoneyDecimal` precedent, validated with `plutil -lint`).
    - **Renderer is pure CoreGraphics + CoreText + PDFKit** — no SwiftUI, UIKit, AppKit or Swift Charts. This is deliberate: those frameworks are unavailable to a Command Line Tools build, and keeping the renderer free of them is what lets `scripts/render_sample_report.swift` compile and *run* the real pipeline without Xcode. Charts (donut / grouped bars / area) are hand-drawn CG paths for the same reason.
    - **Pipeline**: `FinancialData` → `ReportDocumentBuilder` (app-side; does all money/locale formatting) → `ReportDocument` (pure blocks, strings already formatted) → `ReportPaginator` (measure pass) → `PDFReportRenderer` (draw pass) → PDFKit pass for the sidebar outline + document attributes.
    - **Pagination is measured, not estimated.** CoreText sizes text without a graphics context, so the exact page count is known before anything is drawn — which is what makes the contents page's page numbers correct in one pass and the progress UI genuinely determinate. Tables split across pages with a repeated header; the totals row only ever lands on the final chunk.
    - **`CGPDFContextSetOutline` is unusable** — it throws `NSInvalidArgumentException` inside `convertOutlineTree` on current OS versions for every documented dictionary shape. The outline is therefore attached in a second pass via PDFKit (`PDFDocument.outlineRoot`), which preserves the `/Link` annotations emitted by the CG pass.
    - **RTL**: full layout mirroring for Arabic/Hebrew (column order, alignment, header/footer sides, chart legend side). Numeric cells deliberately opt out of alignment mirroring and use an LTR base direction, so amount columns stay visually right-aligned and decimal points keep lining up.
    - **Reconciliation**: the ledger is rendered as a statement (opening balance / income / expenses / closing balance + a running balance column) so a date-filtered range still ties to the all-time cash figure. Future-dated rows are printed but greyed, excluded from balances, and footnoted — matching `AnalyticsEngine.calculateTotals()`. The existing `assetAllocationExcludedCash` footnote is reproduced.
    - **Privacy mode is intentionally ignored** by the PDF (real amounts always), consistent with the JSON export; the sheet says so inline rather than letting the user discover it after sharing.
    - New `FinanceStore.exportReportURL(options:settings:progress:isCancelled:)` snapshots state on the MainActor and builds off it via `Task.detached`, mirroring `exportBackupURL`. It also prunes stale exports from `temporaryDirectory`, which the JSON export never did.
    - New `BrandMark.imageset` in both platform asset catalogues: the 1024px `AppIcon` has opaque black corners (visible against the navy cover) and added ~1.4 MB to every export. The rounded, alpha-masked 256px mark cut the full report from 1795 KB to 408 KB and a crypto-only export from 1536 KB to 141 KB.
    - macOS gains **File ▸ Export… (⌘E)**, routed through `MacAppModel.requestExport()` to the same shared sheet.
    - 81 new keys added to `Localizable.xcstrings` as English-only entries (`"Key" : {}`), inserted in place so the diff is 243 additions / 0 deletions.
    - Verification: `scripts/render_sample_report.swift` renders six variants (full / single-section / date-filtered / RTL / US Letter / empty database) from seeded fixtures. 622 transactions → 27 pages in ~300 ms.

- [2026-07-27]: PDF Report Export — adversarial review pass
  - *Details*: Ran a six-dimension review of the export implementation with independent skeptics attempting to refute each finding. 21 findings were raised, 14 confirmed by reproduction and 7 refuted. All 14 are fixed. Two were serious enough to have shipped wrong figures.
  - *Tech Notes*:
    - **Lost totals row (high).** When every row of a table fitted a page but the footer did not, `splitTable` emitted a continuation chunk with zero rows and the footer attached; `drawTable` read "no rows" as "no data", printed "No entries recorded." and dropped the totals row from the document. Reproduced at roughly one row count in 25. Fixed on both sides: the split now carries the last row forward with the footer, and the renderer only prints the empty-state when there is genuinely no footer either. Regression test sweeps 1…200 rows × {1-line, 2-line} × {caption, none} asserting rows are never lost, reordered or duplicated and the footer appears exactly once.
    - **Ledger did not add up with foreign currencies (high).** Converted amounts were accumulated unrounded and rounded only at print, so printed opening + income + expenses missed printed closing by a cent and the running balance drifted against the amounts beside it. All per-record conversions now go through `recordValue` (rounded to the base currency's minor unit, derived from `NumberFormatter.maximumFractionDigits` so JPY/KRW/ISK/HUF are handled), and totals are sums of those. Fixing this in isolation put the Overview "Cash" tile a cent from the Cash Flow closing balance, so `reportTotals` replaced `AnalyticsEngine.calculateTotals()` throughout the builder — the document is now internally consistent, and diverges from the app's screen by at most one rounding unit per foreign-currency record (asserted as a bounded invariant, not exact equality).
    - **Flat net worth drawn as a full-height climb (high).** The area axis only widened a span that was exactly zero, so a 0.1% move filled the plot. Now applies the same 8% relative floor as `AnalyticsEngine.chartYDomain`, which the app's own dashboards already use, so the PDF and the screen cannot disagree.
    - **No reentrancy guard (high).** Two exports on the same day resolved to the same temp path and would trample each other. Each export now renders into its own `export-<uuid>/` directory (keeping the filename clean for the share sheet), and `ExportCoordinator` refuses a second run while one is in flight.
    - **⌘E did nothing on first press (high).** `requestExport()` set `selection` and `exportRequest` in one update, so `MacSettingsView` was *created* with the token already set and `.onChange` had no transition to observe. Fixed with `initial: true`.
    - Also fixed: subheadings still stranding at page feet (the orphan guard reserved 18pt where a table needs ~79pt — now peeks at what the heading actually introduces); the allocation ring quoting a centre total it did not contain when cash is net-negative; month KPIs and the trend chart counting future-dated rows the ledger excludes; donut colours silently repeating past 8 categories (tail now aggregates into "Other"); duplicate axis tick labels on narrow ranges; donut percentages formatted in the system locale rather than the report's; cancellation ignored during finalisation; the iOS progress sheet being swipe-dismissable without cancelling; and a half-written PDF being left at the export path on any failure.
    - New `Tests/ReportRenderingTests.swift` pins the pagination and reconciliation invariants.
    - Refuted (no change made): a claimed table-drop on an empty page, "0%" for zero-cost-basis holdings, a `pruneStaleExports` guard bug, the iOS share-sheet run-loop claim, an orphaned macOS export on navigation, the untranslated-catalogue "bug" (deliberate and already logged), and a `replacingOccurrences` format-specifier leak.

# Landing Page Rebuild — Pass 1 (design system, hero, Dashboard simulations)

- [2026-07-27]: Marketing site rebuilt as an App Store landing page — pass 1 of 2
- *Details*: The site's incentives pointed away from downloads: the loud hero CTA went to GitHub,
  the nav's most prominent button was a Login that is hard-gated to a single email
  (`VITE_ALLOWED_EMAIL`), and the copy sold Supabase/RLS — a backend the Apple apps do not use.
  Repositioned around the Apple app, with the web app presented as source-available and
  self-hostable. Decisions were locked in an interview before any code; see the memory note
  `landing-page-design`.
- *Tech Notes*:
  - **Two separate design systems, on purpose.** `src/site/site.css` is the marketing chrome:
    slate-indigo canvas (`#16202B`), achromatic, no green anywhere. `src/sim/tokens.ts` is a port of
    `apple/.../Shared/UI/DesignSystem.swift` and is used only inside a simulated device screen. The
    rule is that `WCColor.primary` appears only inside the glass, so the app screens read as the
    only saturated thing on the page.
  - **Type**: Archivo (variable, `wdth` axis at 125%) for display, Instrument Sans for body, IBM Plex
    Mono for every numeral and eyebrow — the mono rule quotes the app's own `.monospacedDigit()`.
    Self-hosted woff2 in `public/fonts` (8 files, ~125K downloaded for a latin visitor); no Google
    Fonts request, since the page claims to load nothing third-party.
  - **Simulations** are hand-built React/CSS, no recharts. The iPhone lays out at 440×956 points and
    the Mac at 1440×900, then scales — so every measurement copied from Swift is literal. Charts are
    hand-rolled SVG in `src/sim/charts.tsx`; donut segments are round-capped stroked arcs, which
    reproduce `SectorMark(innerRadius: .ratio(0.72), angularInset: 2.5).cornerRadius(5)` in one path.
  - **One dataset** (`src/sim/data.ts`) drives every screen and the hero horizon. Totals derive from
    positions. The asset total (14.559,41 €) matches the App Store screenshots deliberately; the
    positions were widened from three to four because a sector ring that is 98,4% one slice reads as
    a rendering bug.
  - **Live controls**: currency, privacy mode and language live in `SimProvider` and re-render every
    screen at once. Amounts format through `Intl` with `useGrouping: 'always'`, matching Foundation.
  - **Strings are the app's own.** `src/sim/strings.ts` is generated by
    `web-app/scripts/extract-strings.py` from `Localizable.xcstrings` and `TabBarLabelResolver.swift`
    — 45 strings × 8 languages. The script fails loudly on a missing key and reports which strings
    are untranslated in the app.
  - **Signature**: `src/site/Horizon.tsx` draws the net-worth trail full-viewport-width as a slate
    hairline using the same `geometry.ts` generator and the same series the in-device chart uses. It
    draws once on load and then never moves. Motion follows the palette rule: the page is still, the
    app breathes (`ScreenBackground`'s circles, paused off-screen via IntersectionObserver, mirroring
    the `scenePhase` guard in Swift).
  - New deps: none. `framer-motion` is slated for removal in pass 2.
  - Verified: `tsc --noEmit` clean for all new files (pre-existing errors in `FIRECalculator.tsx` and
    `pages/Dashboard.tsx` are untouched and predate this work), `npm run build` succeeds, and the
    page was rendered and inspected at 1440px and at mobile width.

## Current Status

Pass 1 is complete and running. **Immediate next step (pass 2):**
1. The remaining six simulated screens (iOS Cash Flow / Investments / Crypto / Settings; macOS
   Investments / Cash Flow). Every tab is currently wired but renders the Dashboard.
2. Sticky five-areas section where scroll drives the iPhone's tab bar; full-bleed Mac section.
3. Move `AuthProvider` / `SettingsProvider` / `FinanceProvider` inside the `/sw` subtree and lazy-load
   it — they currently mount on the marketing pages and fire an exchange-rate fetch on load, which
   contradicts the footer's "loads nothing from a third party".
4. Prerender pipeline (SSR entry + post-build step) so `/privacy`, `/faq`, `/support`, `/terms`,
   `/open-source` return 200 with real HTML. **They 404 in production today.**
5. Rewrite FAQ around the app, move Apple's support URL to `/support`, build `/open-source`, correct
   the four inaccurate "open source" claims to "source-available", add redirects for
   `/features` → `/#areas`, `/tutorial` → `/open-source`, `/founder` → `/#who`.
6. Mobile nav (it wraps below ~600px), OG images, per-page meta.

# Landing Page Rebuild — Pass 2 + audit remediation

- [2026-07-28]: All 8 simulated screens, content pages, prerendering, and three audits remediated
- *Details*: Completed the site. Then ran three independent read-only audits (chart/React correctness;
  SSR-safety and responsive; Swift fidelity and accessibility) and implemented every confirmed finding
  through agents partitioned by file.
- *Tech Notes*:
  - **The 404s are fixed.** `/privacy`, `/faq`, `/support`, `/terms` and `/open-source` are now real
    files with real markup, per-route `<title>`, `<meta description>` and `<link rel=canonical>`.
    Root cause of the regression was traceable: the ancestor `promotional-website` branch deployed with
    `cp dist/index.html dist/404.html && gh-pages -d dist`, and the `cp` step was dropped when the site
    moved into `web-app/`. `dist/404.html` is restored as a fallback on top of the prerendering.
  - **Router restructured.** `BrowserRouter` reads `document` during render and crashes
    `renderToString`, so the route table is exported separately (`AppRoutes`) and the prerender entry
    drives it through `StaticRouter`. `main.tsx` now hydrates when the container has server markup and
    falls back to `createRoot` for `/sw`, which is not prerendered.
  - **Providers moved.** `AuthProvider`/`SettingsProvider`/`FinanceProvider` wrapped the *public*
    routes, so every landing-page visit instantiated a Supabase client and fetched ECB rates from
    api.frankfurter.app — contradicting the footer's "loads nothing from a third party". They now live
    in `src/sw/SwRoutes.tsx` behind a `React.lazy` boundary.
  - **The donut was lying.** Wedges were round-capped strokes; a round cap extends by half the stroke
    width, 9.33° per end, uncompensated. Crypto's true 8.8% rendered as 13.8% while the legend beneath
    printed "8,8 %", and 408.7° of ink was crammed into a 360° ring. Replaced with a true annular
    sector (inset, then stroked with 2×corner and a round line-join), which also brings the corner
    radius to Swift's `.cornerRadius(5)` instead of 14. Verified: 352.5° of ink + three 2.5° gaps =
    exactly 360°.
  - **Privacy Mode was demonstrated backwards.** `DashboardView.swift:547` collapses the top-expense
    bars to zero width; the web drew them at full width while redacting only the numbers. Fixed on both
    platforms — and macOS additionally conceals the whole allocation ring (`:445-449`) where iOS keeps
    the donut visible. Checked before acting: the iOS donut is faithful as-is, so it was left alone.
  - **The trail was the wrong curve.** A comment claimed Swift uses `.interpolationMethod(.monotone)`;
    it uses `.linear` (`DashboardView.swift:247`). Now linear, which also changes the hero horizon —
    intended, since the horizon's claim is that it is the same curve as the chart.
  - **macOS was using iOS type metrics** (`.headline` 17 where macOS resolves 13) and the iOS card
    surface. Added `MAC_TEXT` and `macCard` (DashboardGlassCard, `MacDashboardView.swift:910-943`),
    plus the missing `MobileHeroScenery`/`MacHeroScenery` behind the net-worth hero.
  - **Strings** reconciled against every `t()` call in `src/sim`: 173 keys × 8 languages, generated by
    `web-app/scripts/extract-strings.py`, which fails on a key absent from the catalogue and reports
    which strings are untranslated in the app itself.
  - **Accessibility**: `--ink-faint` raised from 3.93:1 to pass AA on all four surfaces it is used on;
    charts now expose their data via `<title>`/`<desc>` honouring privacy mode; the segmented control
    dropped a `role="tablist"` it did not implement.
  - Bundle: `/sw` is lazy, so Supabase, sonner and the old dashboard leave the marketing chunk.

## Current Status

The site is complete and building. **Remaining: SEO and GEO optimisation**, requested as the final
step — audit first, then implement. Target queries are financial/net-worth/wealth/asset tracking, free
finance app, and the founder as a person entity (ORCID + Google Scholar corroboration available).
Brief and constraints are recorded before that work starts.

# Landing Page — SEO + GEO pass

- [2026-07-28]: Search and AI-answer-engine optimisation, audited then implemented
- *Details*: Two read-only audits (search/technical/on-page/schema/content; GEO and entity authority)
  ran against the new build and the live site, then six agents implemented the in-repo findings
  partitioned by file. The most valuable findings were **outside this repo** and are logged in
  TO_SIMO_DO.md.
- *Tech Notes*:
  - **Entity graph.** A JSON-LD `@graph` is injected per route by `scripts/prerender.mjs`, so it lands
    in the static HTML rather than depending on hydration. Nodes: `Person`, `SoftwareApplication`,
    `WebSite`, `BreadcrumbList` (sub-pages), `SoftwareSourceCode` (/open-source/), plus the existing
    `FAQPage`, which now carries `about` and `author` edges into the graph.
  - **The Person node is REFERENCED, not minted.** `@id` is `https://simo-hue.github.io/#person`, which
    already exists on the author's personal site — verified live. Minting a second Person node for the
    same human would split the entity and destroy the authority the markup is meant to build. If that
    external `@id` ever changes, `PERSON_ID` in `prerender.mjs` is the single place to update.
  - **Facts are read from source at build time, not typed in.** `inLanguage` parses the 35 locale codes
    out of `Localizable.xcstrings`; `operatingSystem` and `softwareVersion` come from
    `project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, `MARKETING_VERSION`).
    **This makes `web-app`'s build depend on the `apple/` tree** — deliberate, since a silently stale
    locale count is worse than a loud failure.
  - **Trailing slashes everywhere.** GitHub Pages 301s `/faq` to `/faq/`, so previously 5 of 6 sitemap
    URLs would have reported "Page with redirect" and no canonical was self-referential on the URL
    Google actually indexes. Canonicals, `og:url`, sitemap and every internal link now use the slash
    form. React Router matches `/faq` for an href of `/faq/`, so no route changed.
  - **`/features`, `/tutorial`, `/founder` returned HTTP 404 to crawlers** — they were client-side
    `<Navigate>` with no file behind them. Now meta-refresh stubs with canonicals, which is the only
    redirect mechanism GitHub Pages permits. Not in the sitemap.
  - **Anchor text.** The nav and footer said "Open source" on all six pages — 12 links whose target's
    H1 is "Source available. Not open source." Now "Source & licence".
  - **Demo data is excluded from snippets.** 26% of the home page's extractable text was fabricated
    euro figures from the device simulations, with nothing marking them illustrative — a real
    hallucination surface. Device frames are now `data-nosnippet` with a visible "Sample data" caption.
  - **The four "checkable" claims are now links** to the App Store listing, the privacy manifest and
    the LICENSE — the section is headed "What you do not have to take on faith" and previously gave
    the reader nowhere to go.
  - Also: founder photo 967 kB → 6.9 kB WebP with a real `alt`; the hero Mac's JS breakpoint (900px)
    reconciled with its CSS breakpoint (1180px), which was rendering a full Mac dashboard into a
    `display:none` container on every tablet; metric-matched font fallback to stop the H1 reflowing on
    font swap; `manifest.webmanifest` `start_url` no longer points at a 404; per-question anchors on
    all 40 FAQ items; a mobile nav.
  - Verified after: 0 type errors in new code, build succeeds, no off-host resource loads anywhere in
    `dist` (the footer's "loads nothing from a third party" is true and checkable), all six routes
    carry correct structured data.

## Current Status

**The website is finished, verified and deployed** — published to `gh-pages` on 2026-07-28, including
the real-logo change logged below this section. `cd web-app && npm run deploy` republishes to the same
branch and the same URL.

The remaining work is all outside this repo and is listed in TO_SIMO_DO.md — most importantly the
GitHub About box, which is what AI answer engines currently quote when asked what this project is, and
which still describes the retired React/Supabase web app.

---

- **2026-07-28: The landing page now uses the app's real logo**
  - *Details*: The site chrome carried a hand-drawn four-point star as its mark, and the
    favicon / apple-touch-icon / PWA icons were still the **purple compass from the previous
    site** — two logos for one product, neither of them the icon on the App Store listing a
    visitor has just come from. Everything is now derived from the shipping app icon
    (`apple/…/AppIcon.appiconset/AppIcon-1024.png`).
  - *Tech Notes*:
    - New `web-app/scripts/generate-icons.py` (Pillow, run by hand, not a build step, outputs
      committed). It cuts the black that iOS icons bake into their corners back to transparency —
      threshold the near-black, flood-fill from the four corners so only *exterior* black is
      taken, crop, and repaint the cut area in the rim colour before writing the alpha, because
      Pillow does not premultiply on resize and black RGB under a transparent pixel draws a dark
      hairline around the mark at nav size. Emits `images/logo.png` (128, transparent),
      `favicon.png` (64), `favicon.ico` (16/32/48), and `apple-touch-icon.png` / `pwa-192` /
      `pwa-512` **opaque**, since iOS and Android mask those themselves and a transparent corner
      under the mask renders black. All quantised to a 256-entry palette — indistinguishable at
      every size written, 4–5× smaller (`pwa-512` 277 → 47 kB, the nav mark 26 → 5.8 kB).
    - `SiteLayout.tsx`: `Mark` is now an `<img>` at 28px (footer 26), up from the star's 22.
      Rendered pixel-doubled at 22/26/28/32 first — the art is dense (ring, needle, bar chart,
      two badges) and below 28 the chart collapses into noise. No CSS `border-radius`: the file
      already carries its own rounded, transparent corners.
    - Both nav breakpoint comments re-measured in Chrome rather than adjusted by arithmetic. The
      wordmark lockup went 164.7 → 170.7px, so the desktop row now folds at 716px (was 710, cut
      at 780) and the wordmark-text row runs out at 409px (was 403, cut at 430). Both still clear.
    - Fixed in passing: below 430px `.wc-wordmark-text` is `display:none`, which also takes it out
      of the accessibility tree — the home link had **no accessible name at all** on a phone. The
      `aria-label` now sits on the anchor, so the name survives the breakpoint and is never
      announced twice.
  - *Verification*: `npm run build` passes, including the guard that every same-site asset a page
    references exists in `dist` — which now covers `images/logo.png`. `npx eslint
    src/site/SiteLayout.tsx` clean. Checked live at 1280px and 420px: mark renders, no console
    errors, footer `<img>` reports `complete`, `naturalWidth` 128, laid out at 26px.

- [2026-07-30]: App Version Bump and Release Notes Update
  - *Details*: Incremented both the Build Version (to 21) and the Marketing Version (to 1.1.5) for both iOS and macOS apps. Updated the release notes ("What's new") to feature the "new cash-flow graph".
  - *Tech Notes*: Used agvtool to bump CFBundleShortVersionString and CFBundleVersion across the .pbxproj and Info.plist files. Batch updated release_notes.txt across all localized metadata directories to "new cash-flow graph".

- [2026-08-09]: WC-LOCK1 — Locked-Device Launch Corrupted Sync State and Showed a Zeroed Dashboard (iOS)
  - *Details*: Diagnosed from a user's exported sync diagnostics (v1.1.5 b21, iOS 26.6). The app declares
    `UIBackgroundModes: remote-notification` and syncs on silent CloudKit pushes, so iOS can cold-launch the
    process **while the device is locked**. Every persisted JSON file was written with
    `.completeFileProtectionUnlessOpen` — a class that permits *creating* a file while locked but not
    *reopening* a closed one — which produced two independent failures from one cause:
    1. **The zeroed dashboard.** `FinanceStore.init` calls `load()` exactly once; it threw
       `NSFileReadNoPermissionError` (Cocoa 257), leaving `data` as an empty `FinancialData()`. Nothing
       retried — there was no `protectedDataDidBecomeAvailable` observer anywhere in the project — so when
       the user later unlocked and foregrounded that still-alive process, the dashboard rendered the empty
       dataset faithfully as €0. Force-quitting re-ran `init` unlocked and everything returned. The
       `ERROR synchronize:` lines in the export were the *consequence*: `applyRemoteMutations` rethrowing
       the stored load error. That guard is why no data was lost.
    2. **The sync-metadata wipe.** `CloudSyncMetadataStore.init` used `try? Data(contentsOf:)`, which cannot
       distinguish "file missing" from "read denied". It started from empty metadata and the first
       `update()` persisted that over the healthy file (the export's `metadata records=0 bytes=155` first
       line). Losing `bootstrapCompleted` + the change token forced a full zone re-fetch — the
       `mods=200/200/40` = 440 records in the log — of which nothing could be applied.
  - *Tech Notes*:
    - **New** `Sources/Shared/Persistence/DataProtection.swift`: `DataProtection.atomicWriteOptions`
      (`[.atomic, .completeFileProtectionUntilFirstUserAuthentication]`) is now the single write policy for
      the finance DB, sync metadata and FX cache; `isPermissionDenied`/`diagnosticCode` classifiers;
      `upgradeProtectionClass(at:)` one-time `setAttributes` migration (a file's class is fixed at creation,
      so changing the write option alone would never reach an install that syncs but is never edited).
      `ProtectedDataAvailability` is the iOS/macOS shim (`isAvailable`, `didBecomeAvailableNotification`,
      `launchContext`). The `.pre-cloudkit-backup` sidecar deliberately keeps the stricter class — it is
      write-only and never read back.
    - **New** `FinanceDataLoadState` (`.notLoaded` / `.loaded` / `.failed(message:isLocked:)`) on
      `FinanceStore`. "No data" and "data we could not read" were previously the same state, which is the
      root reason the failure was invisible. `load()` split into `performLoad()` (no state mutation) and
      `applyLoadOutcome`/`applyLoadFailure`, plus `retryLoadIfNeeded(reason:)` wired to
      `protectedDataDidBecomeAvailable` and to every foreground transition on both platforms. Recovery
      seeds the new `PersistenceCoordinator.reseed` **before** flipping to `.loaded`, so a post-recovery
      edit doesn't diff against an empty baseline and re-upload the whole dataset.
    - Every write guard moved from `localPersistenceError == nil` to `isLocalDataReady`
      (`loadState == .loaded`), which also covers the deferred case where no error exists because no read
      was attempted: `save()`, `importFile` (×2), `applyRemoteMutations`, `setICloudSyncEnabled`,
      `ensureICloudSyncRunning`, `requestICloudSync`, `syncForRemotePush`, `updateCloudSyncStatus`.
    - `CloudSyncMetadataStore` now classifies reads as loaded/missing/corrupt/**unreadable**. Unreadable is
      fail-closed: `unreadableError` is set, `update()` throws `CloudSyncMetadataStoreError.unavailable`
      before touching `cached`, `CloudKitSyncService.start` refuses to bring the engine up, and
      `reloadIfUnavailable()` adopts the on-disk state once readable. Corrupt still starts clean and heals
      by overwriting (a corrupt file must not wedge sync permanently); `reset()` works while unavailable so
      the factory-reset escape hatch survives.
    - `LocalExchangeRatePersistence.load()` had the same conflation with a worse action — it `clear()`ed a
      merely-unreadable cache. Read failures now leave the file intact; only decode/validity failures clear.
    - **New** `Sources/Shared/UI/FinanceDataUnavailableView.swift`, rendered by both `ContentView` and
      `MacRootView` whenever `loadState != .loaded`, ordered *before* the onboarding check so an unread DB
      can never drop a returning user into the welcome flow.
    - Diagnostics: launch marker (`context=fg|bg protectedData=available|locked`), load
      failure/skip/retry/recovery lines, metadata unreadable/corrupt lines, a `local data:` +
      `protected data:` export header, and `MM-dd` added to every timestamp (the old time-only stamps made
      a multi-day ring ambiguous — 22:11 then 09:15 could be one night or three days).
    - **New** `Tests/DataProtectionRecoveryTests.swift` (9 cases) reproducing the denial with `chmod 000`,
      which yields the identical Cocoa 257 — no injected reader, no production seam added for tests.
      Two new files wired into both app targets in `project.pbxproj`; the test file into the test target.
  - *Verification*: `xcodebuild` is unavailable on this machine (Command Line Tools only), so:
    `swiftc -typecheck` over all of `Sources/Shared` + `Sources/macOS` (arm64-apple-macos14.0) is clean; a
    harness compiled against the **real** Shared sources exercises the whole fix with `chmod 000` and passes
    37/37 checks; and the same scenarios run against the pre-fix tree at 983d7739 reproduce both defects
    (metadata 447 bytes/1 record state → 99 bytes/0; FX cache deleted), proving the tests are not vacuous.
    **Unverified here**: everything inside `#if os(iOS)`, all of `Sources/iOS/`, and the XCTest suite — no
    iOS SDK and no XCTest on this machine.

- [2026-08-09]: WC-LOCK1 follow-up — defects found by adversarial multi-agent review of the fix above
  - *Details*: A 33-agent review (5 dimensions → per-finding refutation → completeness critic) raised 27
    findings; 4 survived refutation, the critic added 5, and I acted on 3 more that were refuted but were
    cheap to make right. Everything below is a defect in the WC-LOCK1 change itself, not in pre-existing code.
    1. **Lockout (critical).** A *non-transient* load failure (corrupt JSON, disk full during the schema
       migration write, a macOS permission problem) replaced the entire UI — Settings included — with a
       screen whose only affordance was "Try Again", which would fail identically forever. Previously the
       user landed in the app with an empty dataset and could still reach Erase Everything / import /
       diagnostics. Delete-and-reinstall had become the only way out, destroying the data the screen was
       simultaneously promising was intact.
    2. **Wedged metadata store (high).** With the DB readable but `wealth-compass-cloud-sync.json` not —
       they carry independent protection classes and fail independently — `performLoad` returned `.success`
       and the store went `.loaded`. From that instant `reloadIfUnavailable()` was unreachable (its only
       call site sits inside `performLoad`, which `retryLoadIfNeeded` skips once loaded), so sync stayed
       down for the whole process and *every* edit wrote to disk successfully and then raised "Your latest
       change could not be saved to this device" — false, and repeated forever.
    3. **Background sync disabled (high).** `UIApplication.isProtectedDataAvailable` tracks the *complete*
       protection class and is false on every lock; files at `completeUntilFirstUserAuthentication` stay
       readable in exactly that window. Gating `init`/`syncForRemotePush` on it switched off all background
       sync while the screen was locked — the capability relaxing the class was meant to buy.
    4. **False reassurance (high).** The failure screen asserted "your data is still on this device and in
       iCloud" unconditionally — untrue for the ~majority of users, since sync is opt-in and off by default,
       and untrue about "unchanged" when the DB had just failed to decode.
    5. **macOS ⌘N/⇧⌘I/⇧⌘K (high).** The editor sheet is attached outside the root view's `loadState` branch
       and the menu commands set `appModel.editor` unconditionally, so a user could open a transaction form
       over the "Data Unavailable" screen, fill it in, and have it silently discarded on the next load.
    6. Plus: a vacuous test (it could not detect deletion of `coordinator.reseed`), `retryLoadIfNeeded`
       re-entrancy, `reset()` clearing the fail-closed flag before the write that could fail, the FX cache
       missing its protection-class migration, `reloadIfUnavailable` holding `dataLock` across disk I/O
       (violating the WC-M3 invariant), and four comments making claims the code did not support.
  - *Tech Notes*:
    - `FinanceDataUnavailableView` now takes `isCloudSyncEnabled`, `exportDiagnostics` and `eraseLocalData`.
      Non-lock failures get Export Diagnostics plus a confirmed "Erase and Start Over" that calls
      `eraseEverything(deleteCloud: false)` — local-only, so the server copy stays as the way back. A locked
      device still shows only Try Again: it self-resolves, and offering a destructive action there would be
      inviting harm for a problem about to disappear. The reassurance line is now branched per case and
      never claims a cloud copy the user doesn't have.
    - `recoverSyncMetadataIfNeeded(reason:)` runs from `retryLoadIfNeeded` *before* the `.loaded` short-circuit
      and from the save path, re-running `reconcileLocalInventory` with the retained `lastLoadedSkippedRecordKeys`
      so the H08 skip set is preserved (without it, that reconcile would tombstone undecodable records account-wide).
    - New `SyncBookkeepingError` distinguishes "the DB write succeeded, the CloudKit bookkeeping after it did
      not" from a genuine disk failure, so the save banner stops lying. The diff baseline is still deliberately
      left un-advanced in that case, so the next save re-detects and re-queues the records.
    - Both `init` and `syncForRemotePush` now gate on `isLocalDataReady` (did the read actually work) rather
      than on `isProtectedDataAvailable`. `ProtectedDataAvailability` is kept for the diagnostics launch
      marker and the unlock notification. This is a deliberate refinement of the agreed "gate explicitly"
      decision: the gate stays explicit, but uses a signal that is actually true.
    - `processDueRecurringTransactions` and `refreshMarketPrices` now return early unless loaded — both are
      driven by timers/notifications that know nothing about `loadState`, and the former would otherwise
      report "N scheduled transactions were added" about records that could never persist.
  - *Verification*: macOS whole-module `swiftc -typecheck` clean; the harness grew to **46/46 checks**, adding
    section 9 (split readable-DB/unreadable-metadata: no false save banner, the edit really reaches disk,
    recovery without relaunch) and section 10 (a correct baseline leaves already-synced records untouched;
    an empty one re-marks everything — proving the assertion discriminates). Both new scenarios are mirrored
    in `DataProtectionRecoveryTests`. One test failure during this pass was a bug in the *test*: `Transaction`
    stamps fresh `createdAt`/`updatedAt` per initialization, so a baseline derived from a second sample
    hashes differently and makes even a correct baseline look stale.

- [2026-08-09]: WC-LOCK1 — verification update
  - *Details*: `xcodebuild test -only-testing:WealthCompassTests/DataProtectionRecoveryTests` passed on the
    `WealthCompassMobile` scheme (run by the user; this machine has no Xcode). The two entries above listed
    the iOS-only code as unverified — that is now stale and superseded by this note.
  - *Tech Notes*: The test target is hosted by the Mobile app (`TEST_HOST` → `WealthCompassMobile.app`), so
    a passing test run necessarily compiled the entire iOS target. That retires the single largest risk in
    the change — the `#if os(iOS)` branches could not be compiled locally. Now confirmed against the real
    iOS SDK: `UIApplication.shared.isProtectedDataAvailable`, `UIApplication.protectedDataDidBecomeAvailableNotification`
    and `applicationState` accessed from the `@MainActor` `ProtectedDataAvailability` shim;
    `FileProtectionType.completeUntilFirstUserAuthentication` with `FileManager.setAttributes(_:ofItemAtPath:)`
    and the `attributesOfItem` read-back cast; `Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication`
    on iOS as well as macOS; the `NotificationCenter` observer's `Task { @MainActor in }` hop and its weak
    capture; `FinanceStore`'s nonisolated `deinit` touching MainActor-isolated stored properties; the
    `FinanceDataUnavailableView(state:isCloudSyncEnabled:retry:exportDiagnostics:eraseLocalData:)` call site
    with its `() async -> Void` closures; and the Mobile-target `project.pbxproj` wiring for both new files.
    All 11 XCTest cases pass, including the two added after the review pass (split readable-DB/unreadable-
    metadata recovery, and the stale-diff-baseline discrimination check).
  - *Remaining*: a real `WealthCompassMac` build (macOS target membership was hand-edited into
    `project.pbxproj`; `swiftc -typecheck` passes but is not a build), on-device locked-launch behaviour,
    and a visual pass over the new failure screen. See TO_SIMO_DO.md.

- [2026-08-09]: 1.1.6 Version Bump + App Store Metadata Overhaul (39 locales)
  - *Details*: Prepares the WC-LOCK1 fix for release on iOS **and** macOS (universal purchase, same app
    record). Beyond the version bump, an audit of the metadata turned up two pre-existing defects that were
    live on the storefront, both fixed here.
    1. **29 fields were literally truncated mid-word.** Six subtitles (el, es-ES, es-MX, fi, it, pt-PT) and
       23 `promotional_text` fields ended in `..`, sitting exactly on Apple's 30/170-character limits —
       someone had hard-cut the translations to fit rather than writing shorter ones. `Rastreador de
       patrimonio pri..` was appearing under the app name in Spanish search results. All 29 rewritten as
       complete phrases that fit naturally, reusing each locale's own terminology from its `description.txt`.
    2. **`marketing_url` pointed at the Terms page** in all 39 locales. Apple surfaces this as the app's
       marketing/developer website link.
  - *Tech Notes*:
    - `project.pbxproj`: `MARKETING_VERSION` 1.1.5 → **1.1.6** and `CURRENT_PROJECT_VERSION` 21 → **22**,
      6 occurrences each (Mobile, Mac, Tests × Debug/Release) so nothing drifts between targets.
    - `release_notes.txt` written for all **39 locales**, translated rather than English-duplicated (the
      1.1.5 notes were the literal string "new cash-flow graph" in every language). Copy is deliberately
      platform-neutral because `deliver` reads one metadata folder for both iOS and macOS — and it is
      accurate for both, since the Mac app received the same recovery screen, metadata-store hardening and
      ⌘N gating. It leads with the symptom a user would recognise and states plainly that no data was lost.
    - URLs corrected across all 39 locales: `marketing_url` → site root, `support_url` → `/support` (a real
      route, and the field App Review checks), `privacy_url` → `/privacy` (unchanged).
    - **Metadata tree consolidated.** There were two diverged copies — `metadata/` at the repo root and
      `apple/WealthCompass/fastlane/metadata/` — 312 files apart, with *contradictory* URL values. Only the
      latter is ever read, because the Fastfile lanes run from `apple/WealthCompass`. The app-level files
      that existed only at the root (`copyright.txt`, `primary_category.txt`, `secondary_category.txt`,
      `review_information/`) were moved into the fastlane tree, and the root copy deleted. Verified first
      that nothing in the repo references it. The four `*_sub_category.txt` files were dropped: they held a
      bare newline, and App Store subcategories exist only for Games and Stickers, not Finance/Productivity.
      The 39 empty `apple_tv_privacy_policy.txt` placeholders were dropped too (not a tvOS app).
    - `Fastfile` header comment refreshed (it still claimed 1.1.0 / build 11) and now documents the
      `skip_app_version_update(true)` consequence — the version must exist in App Store Connect *before*
      the lane runs, once per platform.
  - *Verification*: an independent post-write audit (not the script that wrote the files) confirms 39
    locales × 9 fields present, none empty, **none over Apple's limits**, none still ending in `..`, and one
    consistent value for each of the three URLs. 33 distinct release-note texts across 39 locales, which is
    exactly right: en-US/GB/AU/CA share one and fr-FR/fr-CA share one.
