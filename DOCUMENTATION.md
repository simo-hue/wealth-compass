# Wealth Compass - Promotional Website Documentation

## Overview
This documentation covers the implementation of the promotional website for Wealth Compass, located on the `promotional-website` orphan branch. The site is built with **Vite, React, Tailwind CSS**, and **Framer Motion**.

## Structure
- **Branch**: `promotional-website` (Orphan branch, effectively a new project root).
- **Core Tech**: React 19, Vite 7, Tailwind CSS 3.
- **Animation**: Framer Motion for page transitions and entry effects.
- **Charts**: Recharts for interactive data visualization.

## Pages Implemented

### 1. Home Page (`/`)
- **Hero Section**: "Master Your Financial Destiny" with call-to-action.
- **[NEW] Authentic Dashboard Demo**: A pixel-perfect recreation of the real Wealth Compass dashboard (`HeroDemo.tsx`).
    - **Exact Replica**: Sidebar, KPI Cards, and Chart matching the main app design.
    - **3D Tilt**: Follows mouse movement using `framer-motion`.
    - **Simulated Live Data**: Real-time ticker updates for Net Worth.
- **Features Grid**: High-level summary of key capabilities.

### 2. Features Page (`/features`)
- **Detailed Features**: 6 Cards detailing specific functionalities.
- **Interactive Demos**:
    - **Smart Allocation**: Interactive Pie Chart (`AllocationPreview.tsx`).
    - **Growth Calculator**: Slider-based compound interest projector (`GrowthPreview.tsx`).
    - **Cash Flow**: Stacked bar chart showing monthly Income vs Expenses (`CashFlowPreview.tsx`).
    - **Portfolio**: Detailed asset table with live-looking price updates (`PortfolioPreview.tsx`).

### 3. Founder Page (`/founder`)
- **Bio**: Information about Simone Mattioli.
- **Links**: Professional links to GitHub and LinkedIn.

### 4. ROI / Legal Pages
- **FAQ** (`/faq`): 50+ questions with search.
- **Privacy Policy** (`/privacy`) and **Terms of Service** (`/terms`).
- **Tutorial** (`/tutorial`): Installation guide.

## Components
- **Layout**: `Layout.tsx` wraps pages with `Navbar` and `Footer`.
- **Footer**: Compact, minimal design with legal links.
- **Previews**: Located in `src/components/previews/`.

## Development
- **Run**: `npm run dev`
- **Build**: `npm run build`

## Mobile Optimization (Jan 28, 2026)
- **Objective**: Ensure the Home page and specifically the Demo are fully usable on mobile devices without compromising the desktop experience.
- **HeroDemo.tsx Improvements**:
    - **Adaptive Height**: Switched from fixed height to `h-auto` on mobile to accommodate stacked content without internal scrolling (scroll trap prevention).
    - **Overflow Handling**: Changed `overflow-hidden` to `visible` on mobile to allow natural page scrolling.
    - **Grid Layout**: Optimized KPI cards to `grid-cols-2` on mobile (up from 1) to conserve vertical space.
    - **Actions**: Hidden "Refresh" and "Snapshot" buttons on mobile (`hidden sm:flex`) to reduce visual clutter and save space.
    - **Chart Controls**: Hidden timeframe selector ("1W", "1M" etc.) on mobile to simplify the chart view.
- **Home.tsx Improvements**:
    - **Typography**: Adjusted Hero H1 size from `5xl` to `4xl` on mobile to prevent aggressive wrapping/overflow.
- **Features.tsx Improvements**:
    - **Projections**: Hidden "Powerful Projections" box on mobile (`hidden md:block`) as requested.
- **Footer.tsx Improvements**:
    - **Layout**: Compressed to `grid-cols-2` on mobile (vs `grid-cols-1` stacked) for "Product" and "Connect".
    - **Content**: Hidden informative text paragraph on mobile to save vertical space.
    - **Spacing**: Reduced vertical padding and margins on mobile.

## Header Button Update (Jan 28, 2026)
- **Change**: Renamed the "Get Started" button in the navigation bar to "Start".
- **Link**: Updated the button's destination from the GitHub repository to the internal `/tutorial` page.
- **Affected Component**: `Navbar.tsx` (Desktop and Mobile views).

## Home Page Button Update (Jan 28, 2026)
- **Change**: Renamed the "Get Started Free" button in the Hero section to "Start Free".
- **Link**: Updated the button's destination from the GitHub repository to the internal `/tutorial` page.
- **Affected Page**: `Home.tsx`.
7.  **Favicon Update (Jan 28, 2026)**:
    - **Change**: Replaced the default Vite favicon with a custom "Stylized Compass" icon (`favicon.png`).
    - **Location**: `public/favicon.png`.
    - **Affected File**: `index.html`.
