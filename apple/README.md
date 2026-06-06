# Wealth Compass for Apple Platforms

The Apple implementation is one Xcode project with two independent native application targets:

- `WealthCompassMobile`: SwiftUI for iPhone, iOS 17+
- `WealthCompassMac`: native SwiftUI for macOS 14+

Neither target uses Mac Catalyst. The macOS application is built against the macOS SDK and uses desktop navigation, tables, menus, keyboard shortcuts, AppKit file panels, a Settings scene, sandbox entitlements, and Mac icon assets.

## Project Layout

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

The shared layer owns finance models, calculations, local persistence, import/export, exchange rates, market data, settings, and reusable visual components. Platform folders own lifecycle and interaction design.

## Local Storage

Both applications store an independent JSON database in their sandboxed Application Support directory:

```text
Application Support/Wealth Compass/wealth-compass-local-data.json
```

The iPhone app automatically copies the previous Documents-based database into this location the first time the new version starts.

The storage implementation is behind `FinancePersistence`. This is the boundary used by the current local store and the future CloudKit synchronization layer.

## Build

```bash
xcodebuild \
  -project WealthCompass/WealthCompass.xcodeproj \
  -scheme WealthCompassMac \
  -destination 'platform=macOS' \
  build
```

```bash
xcodebuild \
  -project WealthCompass/WealthCompass.xcodeproj \
  -scheme WealthCompassMobile \
  -destination 'generic/platform=iOS Simulator' \
  build
```

For the iCloud implementation plan, see [`ICLOUD_SYNC.md`](./ICLOUD_SYNC.md).
