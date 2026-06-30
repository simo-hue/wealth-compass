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

- [2026-06-28]: iCloud sync — status-severity model + complete CKError taxonomy (Apple)
  - *Details*: Audited the iCloud sync for robustness/UX. The error taxonomy was already mature, but `CloudSyncStatus` collapsed every non-account failure into a single red `.error` ("Sync Error"), so *transient, normal* conditions — **offline**, connection lost, rate-limited, "iCloud preparing" — showed as a scary red error despite their own copy saying "saved, will retry automatically." Also, a few common transient `CKError`s fell through to a generic system string. Introduced a three-severity status model and routed every common error to the right tone; chose **clear inline copy only** for action states (iOS has no reliable public deep-link to iCloud settings — `App-Prefs:` schemes risk App-Review rejection).
  - *Tech Notes*:
    - `CloudSyncStatus` (`CloudKitSyncService.swift`): added `.waiting(String)` (transient/self-resolving) and `.actionNeeded(String)` (persistent, user must act), plus a `severity` (`ok/info/attention/error`) and derived `tint` (`WCColor.textSecondary`/`warning`/`destructive`) and `symbolName`. Transient conditions are now `.info` (neutral) — **never red**.
    - `failureCategory(for:)`: added `.managedAccountRestricted → restricted`, `.serviceUnavailable`/`.accountTemporarilyUnavailable → temporarilyUnavailable`, `.zoneBusy → rateLimited`. `syncStatus(for:)` re-routed: offline/connection-lost/temporarily-unavailable/rate-limited/preparing → `.waiting`; quota/restricted/account-changed → `.actionNeeded`; not-signed-in → `.accountUnavailable`; unexpected → `.error`.
    - Both Settings views (`SettingsView.swift`, `MacSettingsView.swift`) now color the status + show an SF Symbol by `cloudSyncStatus.severity`/`.tint`/`.symbolName` instead of `iCloudSyncError == nil ? secondary : red`. `FinanceStore.updateCloudSyncStatus` and the `forceICloudSync` rethrow treat `.waiting` as non-error (no alarming alert / no red flag) and `.actionNeeded` as a surfaced problem.
    - Tests (`CloudSyncCoreTests.swift`): extended `testFailureCategoryMapsCKErrorCodes` with the new codes; replaced the old "everything → .error" test with `testSyncStatusRoutesEachCategoryToTheRightToneAndSeverity` (transient → `.waiting`/`.info`; quota/restricted → `.actionNeeded`/`.attention`; same-category codes share status; distinct copy per category).
    - **Verification** (no Xcode here): all 5 changed files pass `swiftc -parse`; a standalone CloudKit harness (which also proves the new `CKError` codes exist) verified the full routing→tone→severity — **15/15**. The view changes (Label/icon + tint) and the ~4 new user-facing strings need your Xcode build + localization.

- [2026-06-28]: iCloud sync "write hygiene" — snapshot amplification (#11) + metadata compaction (#12) (Apple)
  - *Details*: Continuation of the I1 churn-reduction work. Two amplification sources remained: (#11) a long absence made `appendSnapshot` carry-forward-backfill up to **60** `NetWorthSnapshot` rows in one save — each its own CloudKit record — so one edit could fire dozens of uploads; (#12) the sync metadata file was ~900 KB pretty-printed with ~80 stale per-record entries, rewritten on many events.
  - *Tech Notes*:
    - **#11** — `SnapshotEngine.appendingSnapshot` no longer materializes carry-forward gap days; it just upserts today's snapshot (a 172-day gap now adds **1** row, not 62). To keep the chart continuous, `AnalyticsEngine.snapshotsForChart` gains `carryingForwardDailyGaps(...)`, which fills missing days by carrying the previous day's value forward **at render time** (a flat line, not a slope) — so real point-in-time history still stores+syncs, but inactive days cost nothing. Net visual change: a gap >60 days now renders flat (previously sloped past the old 60-cap) — more accurate.
    - **#12** — `CloudKitSyncService.pruningSettledTombstones(from:knownLocalHashes:)` (pure, static, testable) drops `records` entries that are settled tombstones (`isTombstone && pending == nil && not in knownLocalHashes`); called from `CloudSyncMetadataStore.update` so the file self-compacts on every write. Safe because every entity id is a one-shot UUID (a pruned id never returns, so its tombstone can't be needed to block a resurrection). Metadata now persists with `prettyPrinted: false`. `CloudSyncRecordState` relaxed `private`→internal so the prune is unit-testable.
    - Tests: `SnapshotEngineTests` backfill tests replaced with no-backfill assertions; `AnalyticsEngineTests.testSnapshotsForChartCarriesForwardGapDays` proves the flat gap-fill; `CloudSyncCoreTests.testPruningDropsOnlySettledTombstones`.
    - **Verification** (no Xcode here): all 6 changed files pass `swiftc -parse`; a standalone `swift` harness verified — against verbatim copies — the no-backfill append, the carry-forward gap-fill (incl. single-point / adjacent-day edges), and the prune predicate: **12/12**. Run `SnapshotEngineTests` + `AnalyticsEngineTests` + `CloudSyncCoreTests` on Xcode and eyeball the net-worth chart (it should still be continuous, flat across inactivity).

- [2026-06-28]: iCloud sync — dedupe manual + automatic sync (#13) (Apple)
  - *Details*: `CKSyncEngine` runs with `automaticallySync = true`, so it fetches/sends on its own; the app *also* drove an opportunistic foreground sync (`requestSync`) and Force Sync (`synchronize`) with explicit `fetchChanges`+`sendChanges`. The `isSynchronizing` guard only covered the *manual* path, so foregrounding could pile a redundant fetch+send on top of an in-flight *automatic* sync. Now the opportunistic path stands down whenever the engine is already syncing.
  - *Tech Notes*:
    - Added `engineSyncActivity` (Int depth counter) tracked from CKSyncEngine's delegate events in `handleEvent`: `willFetchChanges`/`willSendChanges` → +1, `didFetchChanges`/`didSendChanges` → −1 (clamped at 0). This gives the actor visibility into engine-*driven* sync cycles that `isSynchronizing` (manual-only) lacked.
    - `requestSync()` (opportunistic foreground, already debounced 30s per #7) now gates through a pure `static shouldRunOpportunisticSync(isSynchronizing:engineSyncActivity:secondsSinceLastSync:minimumInterval:)` — it runs only when nothing is syncing (manual *or* automatic) and the debounce elapsed. **Force Sync (`synchronize()`) is intentionally unchanged** — a user-initiated "sync now" must always run.
    - Robustness: `engineSyncActivity` resets to 0 at both engine-teardown points (`stop()`, `stopAfterFatalError`), so an unbalanced will/did sequence can never wedge `requestSync` shut. Even if it did, the blast radius is bounded — Force Sync and change-driven automatic sync keep working; only the 30s-debounced foreground opportunistic sync would pause until the next teardown/restart.
    - Tests: `CloudSyncCoreTests.testOpportunisticSyncGate` covers the pure gate. The counter tracking lives in `handleEvent`, which can't be unit-tested (`CKSyncEngine.Event` has no public initializer — see TO_IMPROVE #22), so it was modelled + verified in standalone Swift instead.
    - **Verification** (no Xcode here): `CloudKitSyncService.swift` + `CloudSyncCoreTests.swift` pass `swiftc -parse`; a standalone harness verified the activity state machine (full cycle → 0, mid-cycle busy, stray-`did` clamp, teardown reset) and the gate, including end-to-end "foreground during an automatic sync is suppressed, then allowed once it ends" — **11/11**. Needs a 2-device confirm that foregrounding still pulls remote changes and Force Sync always works.

- [2026-06-28]: Chart NaN-safety (#16) + remove risky `withAnimation` on store loads (#17) (Apple)
  - *Details*: Robustness pass on the view/store layer. Audit finding for #16: the chart data is already provably finite — every series (`cashFlowTrend`, allocations, category totals, net-worth points) is `Decimal.doubleValue` (a `Decimal` can't be NaN/Inf) and `snapshotsForChart` already `.isFinite`-filters — so there's no active data-NaN bug. The one genuine risk was `chartDomain`: it does raw-`Double` `min()/max()` arithmetic, so a single non-finite value would make `(NaN)...(NaN)` **trap (crash)**, not just warn. #17: `FinanceStore.load()` still wrapped its `@Published` writes in `withAnimation`, which emits "Publishing changes from within view updates" when load runs during a view update.
  - *Tech Notes*:
    - **#16** — extracted the two byte-identical private `chartDomain(...)` copies (DashboardView + MacDashboardView) into one hardened, unit-tested `AnalyticsEngine.chartYDomain(for:)` that filters to finite values before `min()/max()` (empty / all-non-finite → safe `0...1`), so the y-domain can never trap. Both dashboards now forward to it and also `.filter { $0.value.isFinite }` the chart points at the view boundary (defense-in-depth at the mark inputs, per the backlog's step 1). The displayed percentages were already guarded (`first.value != 0 ?`, `allocationTotal > 0 ?`); left as-is.
    - **#17** — `FinanceStore.load()` success + error paths now use plain `@Published` assignment instead of `withAnimation` (matching the remote-apply path, which already did). Grep confirms no `withAnimation` remains in `Stores/Services/Persistence`.
    - Tests: `AnalyticsEngineTests.testChartYDomainIsFiniteSafe` (empty / all-non-finite → `0...1`; mixed → finite padded bounds; single / all-equal → non-degenerate range).
    - **Verification** (no Xcode here): all 5 changed files pass `swiftc -parse`; a standalone harness verified `chartYDomain` finite-safety across empty / non-finite / single / flat / negative inputs — **9/9**.
    - **Honest caveat** (#16 step 3): this hardens the data→chart boundary and removes a real crash path, but the original CoreGraphics-NaN *flood* was suspected to be **geometric** (the animated `ScreenBackground` or the chart spring), not data. If it persists after this, re-run with `CG_NUMERICS_SHOW_BACKTRACE=1` to pinpoint the geometric source (and remove the diagnostic env var afterward).

- [2026-06-30]: iCloud sync — clarify in Settings that preferences are per-device (#19 step 1) (Apple)
  - *Details*: Only finance **records** sync via CloudKit; per-device `UserDefaults` still hold currency, privacy mode, custom categories, app language, and API-related prefs. Both Settings views already explained that financial *data* syncs, but never said the converse — so a user could reasonably assume currency/language/categories follow them across devices. Added a single complementary caption stating preferences are per-device. This is the documentation half of #19 (step 1); actually syncing a prefs record (step 2, via a small `WCSettings` CloudKit record or `NSUbiquitousKeyValueStore`) remains open and optional.
  - *Tech Notes*:
    - **iOS** (`Sources/iOS/Views/SettingsView.swift`): added a second `Text(...)` caption immediately after the existing "Your financial data stays available locally…" line in the **iCloud Sync** `Section`, same `.font(.caption).foregroundStyle(WCColor.textSecondary)` styling.
    - **macOS** (`Sources/macOS/Views/MacSettingsView.swift`): added the same caption as a standalone `Text(...)` between the sync toggle's `SettingsRow` and the `Divider()`, matching the macOS caption house style (`.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)`).
    - **Copy** (one new string, identical in both files → one catalog key): *"Preferences like currency, categories, and language are set per device and don't sync."* Deliberately a non-exhaustive list ("like …") covering the most user-visible prefs; API keys are intentionally omitted (they are Keychain-only and must never read as syncable).
    - **No string changed.** The existing "financial data syncs…" caption (29 localized entries in `Localizable.xcstrings`) is left byte-for-byte intact, so no translations are orphaned. Following the repo's established pattern, the new literal is **not** hand-added to the catalog — Xcode extraction on the next build picks it up; translation is logged in `TO_SIMO_DO`.
    - No model/persistence/sync-logic change; purely additive view copy.
    - **Not built locally** — Command Line Tools only (no `Xcode.app`), so `xcodebuild` can't run. Both changed files pass `swiftc -parse` clean (zero syntax errors); the SourceKit "Cannot find 'WCColor'/'FinanceStore' in scope" notes are the documented per-file-isolation noise and don't touch the added lines. Compile both schemes, localize the new string, and eyeball the iCloud Sync section on Xcode.

- [2026-06-30]: iCloud sync — extract + test the sent-side per-record failure classifier (#22 steps 1+2) (Apple)
  - *Details*: TO_IMPROVE #22's headline gap was that `handleSentRecordZoneChanges` — the code that decides what to do with each record CloudKit *rejects* in a send batch (retry / recreate the zone / resolve a conflict / surface a genuine failure) — was an inline if/else ladder coupled to `CKSyncEngine.Event.SentRecordZoneChanges`, which has no public initializer and so can't be constructed in a unit test. Per the documented house pattern ("extract a pure planner instead"), the per-record decision was lifted into a pure, static, `Equatable`-returning `sentRecordFailureResolution(...)` that takes plain primitives, leaving the side effects (metadata writes, enqueue, throw) in the caller. This is a *behaviour-preserving* refactor, verified as such, plus the new direct tests it unlocks. Also closed #22 step 2 (prune count-convergence). No functional/runtime change to sync — same decisions, now testable.
  - *Tech Notes*:
    - **New pure helper** (`Sources/Shared/Services/CloudKitSyncService.swift`): `enum SentRecordFailureResolution { staleRequeue, retryableRequeue, zoneRecreation, nonDeletedConflict, deletedConflict, fatal }` + `static func sentRecordFailureResolution(errorCode:errorIsRetryable:hasServerRecord:serverRecordIsDeleted:failedRevision:currentRevision:)`. Placed next to its sibling sent-side classifiers (`isRetryable`/`partialFailureIsBenign`) and kept in lock-step with them. Internal (not `private`) so `@testable import` reaches it, matching `bootstrapDecision`/`conflictAction`/`pruningSettledTombstones`.
    - **Caller refactor**: the `failedRecordSaves` loop in `handleSentRecordZoneChanges` now extracts `serverRecord`/`serverIsDeleted` once, calls the classifier, and `switch`es on the result to perform the exact same side effects as before (the `if let serverRecord` in the conflict cases is always satisfied — the classifier only returns those when a server record is present). The separate stale-revision `continue` folded into the classifier's `.staleRequeue` (it still takes precedence over every error branch). Preserved edge: `serverRecordChanged` with **no** attached server record has nothing to merge → not retryable → `.fatal`/throw, exactly as before.
    - **Tests appended** to `Tests/CloudSyncCoreTests.swift` (already registered → no `project.pbxproj` change): `testSentRecordFailureResolutionRoutesEachFailureKind` (every outcome incl. stale-precedence and the no-server-record edge), `testIsRetryableCoversTransientErrorsOnly` (pins the retryable set; documents that `serverRecordChanged`/`zoneNotFound` are NOT retryable, which is why they're routed before the retryable check), and `testPruningConvergesRecordCountTowardKnownHashes` (#22 step 2 — 317 records + 238 known hashes → prune → 238).
    - **Verification** (no Xcode here): both changed files pass `swiftc -parse` clean. A standalone `swift`+`CloudKit` harness transcribed the ORIGINAL inline ladder and the NEW classifier and compared them across the full cartesian product of {14 CKError codes × server-record present/absent × server-deleted T/F × 5 revision pairings} = **300 combinations with 0 divergences**, then asserted every expected outcome, the `isRetryable` set, and the prune convergence — **329/329 assertions green**. The proof that old≡new is what makes this safe to land without an Xcode run. (`resultsTruncated` emits a deprecation warning — pre-existing; production's `isRetryable` already lists it and the test mirrors that set faithfully.)
    - Run `WealthCompassTests/CloudSyncCoreTests` on Xcode to confirm the three new tests pass under XCTest; behaviour of live sync is unchanged by construction.

- [2026-06-30]: iCloud sync — production-safe telemetry: OSSignposter + .debug summaries + diagnostics export (#23) (Apple)
  - *Details*: Implemented #23 in full (steps 1–3) after a design interview. Added Instruments signpost intervals **and** live-readable `.debug` `Logger` summary lines at 6 sync/persistence sites, plus a Settings "Export Sync Diagnostics" action. Reframed the "no debug instrumentation" rule: OSLog `Logger` was already shipping in 3 files (FinanceStore/ExchangeRatePersistence/CloudKitSyncService) — the banned thing was the deleted localhost-HTTP `wcDebugLog`/`I18nDebugLog`, not OSLog. This is the sanctioned form: no network, no PII (counts/bytes/ms/result only, all `.public`), `.debug` level = zero production footprint.
  - *Tech Notes*:
    - **New types** (appended to `CloudKitSyncService.swift`, Shared → both targets, **no `project.pbxproj` change**): `SyncDiagnosticsLog` — a lock-guarded (`final class @unchecked Sendable`, NOT an actor, to keep `record(_:)` synchronous and preserve `PersistenceCoordinator`'s no-suspension-point invariant) capped ring buffer (~500 lines, FIFO eviction, timestamped). `SyncSignpost` — `final class @unchecked Sendable` wrapping `OSSignposter` + `Logger` on a dedicated **`Telemetry`** category; `begin`/`end` (unique signpost id), `ms(since:)` (monotonic `DispatchTime`), and `emit(_:)` (logs `.debug` `.public` **and** copies into `SyncDiagnosticsLog.shared`). Two shared instances split by layer subsystem: `.persistence` (`com.wealthcompass.persistence`) and `.sync` (`com.wealthcompass.sync`).
    - **6 instrumented sites** (per-batch, never per-record): `PersistenceCoordinator.save` → `save records/changed/deleted/ms`; `FinanceStore.applyRemoteMutations` → `applyRemote muts/applicable/applied/skipped/ms` (via `defer` so every non-throwing path emits accurate counts); `CloudSyncMetadataStore.persist` → `metadata records/bytes/ms`; `CloudKitSyncService.synchronize` → `synchronize ms/result` (`result=failed` set in the report branch); `handleFetchedRecordZoneChanges` → `fetched mods/dels`; `handleSentRecordZoneChanges` → `sent saved/failed`. The key `.error` paths also `record(…)` to the buffer (central `report`, fatal account-change, save failure, skipped remote record), prefixed `ERROR`, so the export captures failures.
    - **Export** (#23 step 3, done as a *visible* Settings → Data row, not hidden — easier for support to direct users to): `FinanceStore.exportSyncDiagnosticsURL()` writes a non-identifying header (app version/build · platform · OS · sync on/off — **no account, no financial data**) + the buffered lines to a temp `.txt`. iOS: button sets `diagnosticsURL` → `ShareLink` (mirrors backup export). macOS: `exportSyncDiagnostics()` → `NSSavePanel` with `.plainText` (mirrors `exportBackup`). Sourced from the ring buffer because `.debug` lines aren't persisted, so `OSLogStore` can't retrieve them after the fact (a dependency surfaced during the design interview).
    - **Why a buffer, not OSLogStore**: keeping `.debug` (zero footprint, live-streamable) means the summaries aren't in the persisted log store; the in-memory ring sidesteps the OSLogStore iOS entitlement/redaction risk entirely and is PII-clean by construction (only our own controlled lines) — and it's unit-testable.
    - **Tests** appended to `Tests/CloudSyncCoreTests.swift` (registered → no pbxproj change): `SyncDiagnosticsLog` cap/FIFO eviction, timestamp-prefix + message preservation, `clear()`, and thread-safety under 1000 concurrent appends.
    - **Verification** (no Xcode here): all 5 changed files pass `swiftc -parse` clean. A standalone `swift` harness that **`import OSLog`** and uses the real `OSSignposter`/`Logger` API (so it compile-checks `OSSignposter(subsystem:category:)`, `makeSignpostID()`, `beginInterval(_:id:)`, `endInterval(_:_:)`, `logger.debug("\(…, privacy: .public)")` against the actual framework — the part `swiftc -parse` can't validate) verified the buffer (cap, FIFO, timestamp format, 5000-way concurrent thread-safety, capacity floor) + the `ms` helper + the `emit`→buffer round-trip — **15/15 green**.
  - *Follow-ups (TO_SIMO_DO)*: build both schemes + run `CloudSyncCoreTests`; localize the 4 new UI strings (`Export Sync Diagnostics`, `Share Sync Diagnostics`, `Export Sync Diagnostics...`, `Diagnostics Exported`); smoke-test `log stream --predicate 'category == "Telemetry"'` during a sync and the export share/save flow on each platform.

- [2026-06-30]: Tests — cover the 7 previously-untested `AnalyticsEngine` pure methods (Apple)
  - *Details*: Coverage audit found 7 of 13 `AnalyticsEngine` methods had no direct tests — all pure money/percentage math feeding the dashboard charts: the four allocation breakdowns (`investmentAllocation` by sector, `investmentTypeAllocation`, `investmentGeographyAllocation`, `cryptoAllocation`), `monthlyCashFlow(for:)`, `hasForeignCurrencyExposure(relativeTo:)`, and the raw `snapshots(range:)`. Added 8 tests pinning their contracts. No production code changed — pure test addition; chosen because its entire verification closes in-session (no Xcode/device needed).
  - *Tech Notes*:
    - Appended to `Tests/AnalyticsEngineTests.swift` (already registered → no `project.pbxproj` change), reusing the file's `date`/`tx`/`engine`/`snapshot` helpers plus two new `investment(...)`/`crypto(...)` fixture builders.
    - Contracts pinned: foreign exposure = any non-base holding in any bucket (empty → false); `monthlyCashFlow` sums only the requested month split by type; `snapshots(range:)` filters on/after the range cutoff, sorts ascending, maps net-worth; the three investment allocations group→sum(converted)→sort-desc (by sector / localized type title / geography); `cryptoAllocation` is one slice per holding, drops zero-value, sorts desc; plus a FX-conversion assertion (125 USD ÷ 1.25 = 100 EUR) proving allocations are in the display currency.
    - **Verification** (no Xcode here): `Tests/AnalyticsEngineTests.swift` passes `swiftc -parse` clean; a standalone `swift` harness transcribing all 7 methods verbatim (stubbing only converter / localization / colors, which don't affect the numeric/grouping logic) asserted every expected value — **20/20 green**, so the XCTests will pass under XCTest. Run `WealthCompassTests/AnalyticsEngineTests` on Xcode to confirm.

- [2026-06-30]: CloudKit schema check script (#24) (Apple)
  - *Details*: Closed #24 — guard against shipping with a CloudKit schema mismatch (the container's record types/fields drifting from the code). New `apple/WealthCompass/scripts/check_cloudkit_schema.py` treats the Swift source as the single source of truth: it extracts the record types and CKRecord field keys and (1) prints a release checklist of what must exist in the production container, and (2) acts as a CI drift gate. Fully runnable + verified here (no Xcode/CloudKit needed for the source-derived part).
  - *Tech Notes*:
    - **Extraction** (from `Sources/Shared/Services/CloudKitSyncService.swift`): record types from the `CloudSyncRecordType` enum raw values (6: `WCTransaction`, `WCRecurringTransaction`, `WCInvestment`, `WCCryptoHolding`, `WCLiability`, `WCNetWorthSnapshot`); field keys from `[Rr]ecord["…"]` usages (8, identical on every type since the entity is encoded into `payload`: `payload` BYTES, `createdAt`/`updatedAt`/`clientModifiedAt`/`deletedAt` TIMESTAMP, `isDeleted`/`schemaVersion` INT64, `revision` STRING); plus the `containerIdentifier`/`zoneName`/`schemaVersion` constants.
    - **Drift gate**: the expected schema is embedded in the script (`EXPECTED_TYPES`/`EXPECTED_FIELDS`). If the source adds/removes a type or field the manifest doesn't match, it exits 1 with a message telling the dev to update the manifest AND the CloudKit Dashboard (deploy Development→Production) before shipping. This is the CI value — it converts "remember to update the Dashboard" into a failing check.
    - **Modes**: default → human checklist + exit 0/1; `--json` → machine-readable manifest (CI-pipeable), still gated. Executable (`chmod +x`), matches the repo's `scripts/add_tab_bar_localizations.py` convention. Python 3, stdlib only.
    - **What it can't do from here**: hit the live CloudKit container (needs credentials + network). That stays a manual checklist confirm — logged in `TO_SIMO_DO`. The script verifies the source-derived schema is self-consistent and un-drifted; the printed checklist is what you tick off against the production container.
    - **Verification** (in-session): ran the script → checklist + exit 0; `--json` → correct manifest; a harness loaded the script as a module and exercised its real `main()` against the real source with a tampered manifest in BOTH drift directions (source has an unknown field → exit 1; manifest expects a missing type → exit 1) and confirmed extraction finds exactly 6 types / 8 fields — **all green**. No Swift changed; no `project.pbxproj` change (it's a standalone script, not a build input).
