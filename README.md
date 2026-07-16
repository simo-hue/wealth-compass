# Wealth Compass

<a href="https://apps.apple.com/app/wealth-compass/idYOUR_APP_ID_HERE" target="_blank">
  <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" width="160">
</a>
<a href="https://apps.apple.com/app/wealth-compass/idYOUR_APP_ID_HERE" target="_blank">
  <img src="https://developer.apple.com/assets/elements/badges/download-on-the-mac-app-store.svg" alt="Download on the Mac App Store" width="160">
</a>

Wealth Compass is a comprehensive, privacy-focused personal finance dashboard designed to give you a complete 360-degree view of your financial health. Available as a native app for **iOS and macOS**, it offers real-time tracking of assets, liabilities, and cash flow in a beautiful, local-first interface.

## 📱 Native Apple Applications

The core of Wealth Compass is a native Apple ecosystem implementation, ensuring secure, local-first tracking on your devices.

- **WealthCompassMobile**: Built with SwiftUI for iPhone, requiring iOS 17 or later.
- **WealthCompassMac**: Built with native SwiftUI for macOS 14 or later (built directly against the macOS SDK, not Mac Catalyst).

### Core Features
- 📊 **Interactive Dashboard**: Visual history of your net worth over time, asset allocation breakdowns, and key performance metrics.
- 💰 **Cash Flow Management**: Track income and expenses with categories, visual trends, and schedule recurring transaction reminders.
- 📈 **Investment Portfolio**: Real-time stock & ETF price updates via Finnhub and Yahoo Finance. Track cost basis, current value, and profit/loss.
- ₿ **Crypto Tracker**: Live data fetching from CoinGecko. Track crypto holdings and monitor live valuations.
- 🔒 **Privacy & Security**: All financial data is strictly stored locally in the app sandbox. Supports Face ID / Touch ID biometric locks and a quick-toggle Privacy Mode to blur sensitive amounts.
- 🌍 **Localization**: Fully localized in 38 languages via Xcode String Catalogs.
- 🔄 **Data Portability**: Easily export your data to a JSON backup or import existing backups. Private CloudKit synchronization is available to keep your iPhone and Mac in sync.

### Building the Apple Apps

Open `apple/WealthCompass/WealthCompass.xcodeproj` and select:
- `WealthCompassMobile` for the iPhone app
- `WealthCompassMac` for the native macOS app

For architecture and detailed build instructions, see [`apple/README.md`](./apple/README.md).

## 📁 Repository Layout

```text
wealth-compass/
├── apple/
│   └── WealthCompass/
│       ├── Sources/Shared/      Shared iPhone and Mac domain code
│       ├── Sources/iOS/         iPhone application and views
│       ├── Sources/macOS/       Native macOS application and views
│       ├── Resources/iOS/
│       ├── Resources/macOS/
│       └── WealthCompass.xcodeproj
├── src/                         Web application (Legacy/Alternative)
├── public/                      Web assets
└── .github/workflows/           Web deployment
```

---

## 🌐 Web Application (Alternative)

In addition to the native Apple apps, the repository root contains the source code for the **Wealth Compass Web App**. 

- **Tech Stack**: React, TypeScript, Vite, Tailwind CSS, shadcn/ui.
- **Backend & Auth**: Supabase (with Row Level Security).
- **Deployment**: Deployed via GitHub Actions to GitHub Pages.

Unlike the local-first native Apple apps, the web app relies on a centralized Supabase backend to persist its data. The web app remains at the repository root so its existing Vite and GitHub Pages deployment stays stable.

### Web App Installation
- [**Installation Guide (English)**](./INSTALLATION.md)
- [**Guida all'Installazione (Italiano)**](./INSTALLATION_IT.md)

---

<p align="center">
  <span style="color: #666; font-size: 0.8em;">Wealth Compass &copy; 2026</span>
</p>
