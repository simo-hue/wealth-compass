# Wealth Compass Mobile

Native iOS implementation of the Wealth Compass app.

Current app version: `1.1`.

## Scope

- SwiftUI iPhone app under `WealthCompassMobile/`
- Local-only JSON persistence in the app sandbox
- No Supabase client, credentials, auth flow, or remote database dependency
- Optional Finnhub and CoinGecko API keys, verified with a live price request before secure Keychain storage
- Automatic net-worth snapshots after local finance data changes
- Persistent custom cash-flow categories in addition to the default category set
- Optional Face ID / Touch ID app lock

## Pages

- Dashboard
- Cash Flow
- Investments
- Crypto
- Settings

## Open

Open `mobile/WealthCompassMobile/WealthCompassMobile.xcodeproj` in Xcode and run the `WealthCompassMobile` scheme on an iPhone simulator or device.
