# Wealth Compass

Wealth Compass is a modern, comprehensive personal finance dashboard designed to give you a complete 360-degree view of your financial health. Built with React, Supabase, and Tailwind CSS, it offers real-time tracking of assets, liabilities, and cash flow in a beautiful, privacy-focused interface.

## Repository Layout

```text
wealth-compass/
├── src/                         Web application
├── public/                      Web assets
├── apple/
│   └── WealthCompass/
│       ├── Sources/Shared/      Shared iPhone and Mac domain code
│       ├── Sources/iOS/         iPhone application and views
│       ├── Sources/macOS/       Native macOS application and views
│       ├── Resources/iOS/
│       ├── Resources/macOS/
│       └── WealthCompass.xcodeproj
└── .github/workflows/           Web deployment
```

The web app remains at the repository root so its existing Vite and GitHub Pages deployment stays stable. Native Apple applications are managed by one Xcode project with separate iOS and macOS targets.

### Apple Applications

Open `apple/WealthCompass/WealthCompass.xcodeproj` and select:

- `WealthCompassMobile` for the iPhone app
- `WealthCompassMac` for the native macOS app

See [`apple/README.md`](./apple/README.md) for architecture and build details.

## Features

### 📊 Interactive Dashboard
- **Net Worth Tracking**: Visual history of your net worth over time.
- **Asset Allocation**: Breakdown of your portfolio by sector and asset class.
- **Key Metrics**: Instant view of net worth, cash balance, investments, and crypto.

### 💰 Cash Flow Management
- **Transaction Tracking**: Easy entry for income and expenses.
- **Analytics**: Monthly savings rate, income vs. expense breakdown.
- **Export**: Download your transaction history to CSV for external analysis.

### 📈 Investment Portfolio
- **Stock & ETF Tracking**: Real-time price updates via Finnhub and Yahoo Finance.
- **Performance Metrics**: Track cost basis, current value, and profit/loss.
- **Sector Analysis**: Visualize your exposure across different market sectors.

### ₿ Crypto Tracker
- **Real-time Prices**: Live data fetching from CoinGecko.
- **Portfolio Overview**: Track holdings, average buy price, and current value.
- **Privacy Mode**: Blur sensitive values with a single click.

### 🧮 Financial Calculators
- **Compound Interest**: Project future wealth based on savings and returns.
- **FIRE Calculator**: Estimate your "Financial Independence, Retire Early" timeline.
- **Inflation Impact**: Understand how purchasing power changes over time.
- **Monte Carlo Simulation**: Probability-based stress testing of your portfolio.

### 🔒 Privacy & Security
- **Supabase Backend**: Secure data persistence with Row Level Security (RLS).
- **Privacy Mode**: instantly blur all financial figures for discreet viewing in public.
- **Local Caching**: Smart caching to minimize API calls and improve performance.

## Tech Stack

- **Frontend**: React, TypeScript, Vite
- **UI Framework**: Tailwind CSS, shadcn/ui
- **Backend & Auth**: Supabase
- **Charts**: Recharts
- **Icons**: Lucide React
- **Data Providers**: Finnhub (Stocks), CoinGecko (Crypto), Frankfurter (Currency)

## Getting Started

Ready to take control of your finances? Follow the installation guide to set up your own instance of Wealth Compass.

- [**Installation Guide (English)**](./INSTALLATION.md)
- [**Guida all'Installazione (Italiano)**](./INSTALLATION_IT.md)

---

<p align="center">
  <span style="color: #666; font-size: 0.8em;">Wealth Compass &copy; 2026</span>
</p>
