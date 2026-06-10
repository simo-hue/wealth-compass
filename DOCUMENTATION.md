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
