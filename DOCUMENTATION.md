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
