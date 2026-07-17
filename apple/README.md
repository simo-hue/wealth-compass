# Wealth Compass (Apple Platforms)

Wealth Compass is a comprehensive, privacy-focused personal finance dashboard designed to give you a complete 360-degree view of your financial health. This repository contains the native Apple ecosystem implementation, providing secure, local-first tracking of your assets, liabilities, and cash flow.

## Native iOS & macOS Apps

The Apple implementation is driven by a single Xcode project containing two independent, fully native application targets:

- **WealthCompassMobile**: Built with SwiftUI for iPhone, requiring iOS 17 or later.
- **WealthCompassMac**: Built with native SwiftUI for macOS 14 or later. 

*(Note: The macOS target does **not** use Mac Catalyst. It is built directly against the macOS SDK to leverage authentic desktop navigation, tables, menus, keyboard shortcuts, AppKit file panels, an in-window Settings page, sandbox entitlements, and Mac icon assets.)*

### Core Features
- 📊 **Interactive Dashboard**: Visual history of your net worth over time, asset allocation breakdowns, and key performance metrics.
- 💰 **Cash Flow Management**: Track income and expenses with categories, visual trends, and schedule recurring transaction reminders.
- 📈 **Investment Portfolio**: Real-time stock & ETF price updates via Finnhub and Yahoo Finance (with keyless fallback). Track cost basis, current value, and profit/loss.
- ₿ **Crypto Tracker**: Live data fetching from CoinGecko. Track crypto holdings and monitor live valuations.
- 🔒 **Privacy & Security**: All financial data is strictly stored locally in the app sandbox. Supports Face ID / Touch ID biometric locks and a quick-toggle Privacy Mode to blur sensitive amounts.
- 🌍 **Localization**: Fully localized in 38 languages via Xcode String Catalogs.
- 🔄 **Data Portability**: Easily export your data to a JSON backup or import existing backups. Private CloudKit synchronization is available to keep your iPhone and Mac in sync.

### Project Layout

```text
WealthCompass/
├── Sources/
│   ├── Shared/
│   │   ├── Models/
│   │   ├── Persistence/
│   │   ├── Services/
│   │   ├── Stores/
│   │   └── UI/
│   ├── iOS/
│   └── macOS/
├── Resources/
│   ├── iOS/
│   └── macOS/
└── WealthCompass.xcodeproj
```

The `Shared` layer owns the core finance models, calculations, local persistence, import/export logic, exchange rates, market data, settings, and reusable visual components. The `iOS` and `macOS` platform folders handle platform-specific application lifecycles and interaction design.

### Local Storage

Both applications store an independent JSON database in their sandboxed Application Support directory:

```text
Application Support/Wealth Compass/wealth-compass-local-data.json
```

The storage implementation is abstracted behind `FinancePersistence`. This is the boundary used by the current local store and the CloudKit synchronization layer.

### Building from Source

To build the macOS application:
```bash
xcodebuild \
  -project WealthCompass/WealthCompass.xcodeproj \
  -scheme WealthCompassMac \
  -destination 'platform=macOS' \
  build
```

To build the iOS application (Simulator):
```bash
xcodebuild \
  -project WealthCompass/WealthCompass.xcodeproj \
  -scheme WealthCompassMobile \
  -destination 'generic/platform=iOS Simulator' \
  build
```

For iCloud sync design notes and remaining architecture work, see [`WealthCompass/TO_IMPROVE.md`](./WealthCompass/TO_IMPROVE.md).

---

## 🌐 Web Application (Legacy / Alternative)

In addition to the native Apple applications, the [`web-app/`](../web-app/) directory contains the source code for the **Wealth Compass Web App**.

- **Tech Stack**: React, TypeScript, Vite, Tailwind CSS, shadcn/ui, Recharts.
- **Backend**: Supabase (with Row Level Security).
- **Deployment**: Manual — `cd web-app && npm run deploy` publishes to the `gh-pages` branch. There is no CI workflow.

The web app is structurally independent of the Apple applications. Unlike the local-first native Apple apps, the web app uses a centralized Supabase backend to persist its data. The web app is located in [`web-app/`](../web-app/), a sibling of this `apple/` directory.
