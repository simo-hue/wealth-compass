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
