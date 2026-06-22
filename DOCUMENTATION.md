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
