# Wealth Compass Tracker - App Store Connect Submission Information

Last verified: June 6, 2026

This document contains the information needed to create and submit Wealth Compass in App Store Connect. Text marked **REQUIRED - REPLACE** must be completed by the app owner before submission.

## 1. App Record

| App Store Connect field | Value |
|---|---|
| Platforms | iOS |
| App name | Wealth Compass Tracker |
| Primary language | English (U.S.) |
| Bundle ID | `com.wealthcompass.mobile` |
| SKU | `wealth-compass-ios` |
| User access | Full Access |

Notes:

- The app name must be available in App Store Connect.
- The SKU is internal and cannot be changed after the app record is created.
- The Bundle ID must exactly match the Xcode project.

## 2. General App Information

| Field | Value |
|---|---|
| Name | Wealth Compass Tracker |
| Subtitle | Private Wealth Tracker |
| Primary category | Finance |
| Secondary category | Productivity |
| Content rights | No, this app does not contain, show, or access third-party content requiring separate distribution rights. It only requests factual market prices and exchange rates from data providers. |
| Made for Kids | No |
| License agreement | Apple's Standard End User License Agreement |

### Privacy Policy URL

`https://libriperilcambiamento.github.io/wealth-compass/privacy`

The URL must be public, work without authentication, and describe the actual practices listed in the privacy section below.

### User Privacy Choices URL

Leave blank. This is optional. The app has no user accounts or developer-hosted user data. Users can delete all locally stored data from **Settings > Data > Delete All Data**.

## 3. Version and Build

| Field | Value |
|---|---|
| Version | `1.2.0` |
| Build | `12` |
| Minimum OS | iOS 17.0 |
| Device family | iPhone |
| Orientation | Portrait |

The Xcode project is at version `1.2.0`, build `12` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.pbxproj`). If a build is uploaded and rejected during processing, Apple may allow reuse; otherwise increment the build number before uploading another binary.

## 4. App Store Product Page

### Promotional Text

Track your complete financial picture privately with cash-flow insights, investment and crypto monitoring, recurring transactions, and automatic net-worth history.

### Description

Wealth Compass is a private, local-first personal finance dashboard that helps you understand your net worth, cash flow, investments, crypto assets, and liabilities in one place.

Build a clear picture of your finances:

- View net worth, cash balance, investments, and crypto at a glance
- Track income and expenses with categories and visual trends
- Schedule recurring transactions and receive optional local reminders
- Monitor stock, ETF, and cryptocurrency holdings
- Review cost basis, profit and loss, and portfolio allocation
- Track liabilities alongside your assets
- Follow net-worth history with automatic local snapshots
- Convert values using cached ECB reference exchange rates
- Hide sensitive amounts instantly with Privacy Mode
- Protect the app with Face ID or Touch ID
- Export, import, and delete your local data whenever you choose

Your financial records stay on your device. Wealth Compass does not require an account and does not store your portfolio or transaction history on developer-operated servers.

Optional market-price updates use API credentials that you provide. Credentials are stored securely in the iOS Keychain.

Wealth Compass is an informational tracking tool. It does not connect to financial institutions, execute trades, provide financial advice, or guarantee the accuracy of third-party market data.

### Keywords

`net worth,budget,expense,income,cash flow,portfolio,investment,crypto,finance,wealth`

The keyword field has a 100-character limit. The proposed value is 84 characters and does not repeat the app name.

### Support URL

`https://libriperilcambiamento.github.io/wealth-compass/support`

The page must be public and provide real contact information, such as a support email address. Suggested page content:

- App name: Wealth Compass Tracker
- Support email: `mattioli.simone.10@gmail.com`
- Developer: Simone Mattioli
- Postal/legal address if required in the countries where the app is distributed
- Link to the privacy policy

### Marketing URL

`https://libriperilcambiamento.github.io/wealth-compass/`

### Copyright

`2026 Simone Mattioli`

Do not include the copyright symbol; App Store Connect adds it automatically.

### What's New in This Version

Leave blank. App Store Connect does not require "What's New" for the first public release.

## 5. Screenshots and App Preview

### Required Screenshots

Upload screenshots from a supported iPhone display size accepted by App Store Connect. App Store Connect will show the currently required dimensions for the selected device class.

Recommended screenshot sequence:

1. Dashboard - headline: `Your Complete Financial Picture`
2. Cash Flow - headline: `Understand Income and Spending`
3. Recurring Transactions - headline: `Stay Ahead of Every Due Date`
4. Investments - headline: `Track Portfolio Performance`
5. Crypto - headline: `Monitor Your Crypto Holdings`
6. Privacy Mode or biometric lock - headline: `Private and Stored on Your Device`
7. Settings and backup - headline: `Your Data, Under Your Control`

Screenshot requirements:

- Use realistic sample data, never real personal financial information.
- Do not show placeholder API keys, notification banners containing private amounts, or debug UI.
- Keep claims consistent with the app. Do not imply bank syncing, trading, investment advice, or cloud sync.
- The app currently supports iPhone only, so iPad screenshots are not needed.

### App Preview Video

Optional. Leave blank unless a polished preview video is available.

## 6. App Privacy Answers

### Data Collection

Select:

> **No, we do not collect data from this app.**

Reasoning for the current code:

- Financial records, settings, snapshots, custom categories, and imported backups are stored locally in the app sandbox.
- Finnhub and CoinGecko credentials are supplied by the user and stored locally in the iOS Keychain.
- The app has no developer account system, analytics SDK, advertising SDK, tracking SDK, remote database, or developer-operated backend.
- Financial records are not sent to the exchange-rate or market-data providers. Only requested currency codes, stock symbols, crypto identifiers, and user-supplied API credentials are included in real-time provider requests.
- Apple's definition of collection generally concerns data transmitted off device and retained in a way accessible to the developer or a third party beyond servicing the request. Confirm the providers' current retention practices before publishing this answer.

Do not select any individual data types when using the "No, we do not collect data" answer.

### Tracking

| Question | Answer |
|---|---|
| Does the app or its third-party partners use data for tracking? | No |
| Does the app use the Advertising Identifier (IDFA)? | No |
| Does the app display advertising? | No |
| Is App Tracking Transparency permission required? | No |

### Required Privacy Policy Statements

The published privacy policy should explicitly state:

- The app does not require registration or create user accounts.
- Financial information entered by the user is stored locally on the user's device.
- The developer does not receive or store transaction, investment, crypto, liability, or net-worth data.
- The app makes network requests to Frankfurter/ECB for exchange rates, to Yahoo Finance for stock and ETF prices (keyless, contacted without any user-supplied credentials), and, when the user provides API keys, to Finnhub (stocks/ETFs) and CoinGecko (crypto) for market prices.
- Provider requests may expose ordinary network information such as IP address and may be governed by each provider's privacy policy.
- User-provided API keys remain on device in the iOS Keychain but are transmitted to the applicable provider to authenticate requests.
- The app uses optional local notifications for recurring transactions.
- The app uses optional Face ID, Touch ID, or other supported device biometrics through Apple's LocalAuthentication framework; the app does not access or store biometric data.
- Users can export a JSON backup through the iOS share sheet.
- Users can delete all local finance data in the app.
- The app contains no advertising or cross-app tracking.
- A support contact is provided for privacy questions.

## 7. Age Rating

Complete Apple's age-rating questionnaire with these answers for the current app:

| Descriptor or capability | Answer |
|---|---|
| Parental controls | None |
| Age assurance | None |
| Unrestricted web access | No |
| User-generated content | No |
| Messaging and chat | No |
| Advertising | No |
| Violence | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None |
| Horror or fear themes | None |
| Alcohol, tobacco, or drug references | None |
| Medical or treatment information | None |
| Contests | None |
| Gambling | None |
| Loot boxes | No |

The app includes personal finance tracking but no trading, gambling, lending, or financial transactions. Apple calculates the final regional rating from the questionnaire.

## 8. App Review Information

### Sign-In Information

| Field | Value |
|---|---|
| Sign-in required | No |
| Demo account | Not applicable |
| Username | Leave blank |
| Password | Leave blank |

### Contact Information

All fields must identify a person Apple can contact during review:

| Field | Value |
|---|---|
| First name | Simone |
| Last name | Mattioli |
| Phone number | **REQUIRED - REPLACE, include country code** |
| Email | `mattioli.simone.10@gmail.com` |

### Review Notes

Paste the following:

> Wealth Compass is a local-first personal finance tracker. No account or sign-in is required, and the app does not connect to banks or execute financial transactions.
>
> To review the app, add sample records with the plus buttons in Cash Flow, Investments, and Crypto. Liabilities can be managed from Cash Flow. The Dashboard updates automatically after local finance data changes.
>
> Optional recurring reminders can be tested by creating a recurring transaction and enabling "Notify When Due." iOS will request notification permission at that point.
>
> Optional biometric lock can be enabled in Settings. Face ID is unavailable on some simulators; this feature can be reviewed on a supported device or configured simulator.
>
> Exchange rates refresh automatically from ECB reference-rate data through Frankfurter. The app includes offline fallback rates if the service is unavailable.
>
> Market-price refreshes are optional. Stock and ETF prices update automatically through a keyless provider (Yahoo Finance) with no API key required; providing a Finnhub key is optional and improves US/USD coverage. Live crypto prices require a user-provided CoinGecko key. None of these credentials are required to review the core app, and prices can also be entered manually.
>
> All finance data is stored locally. Settings includes JSON backup export/import and a Delete All Data action.

### Attachment

Optional. Add a short review video only if Apple cannot easily discover a feature during review.

## 9. Export Compliance and Encryption

The app uses HTTPS through Apple's networking APIs and stores user-provided API keys in Apple's Keychain. It does not implement proprietary encryption algorithms.

For the standard App Store Connect encryption questions, the likely answer is:

| Question | Answer |
|---|---|
| Does the app use encryption? | Yes, only encryption provided by or built into Apple's operating system, such as HTTPS and Keychain |
| Does it implement non-standard or proprietary encryption? | No |
| Does it implement standard encryption algorithms itself? | No |
| Is export-compliance documentation expected? | No, based on exempt use of operating-system encryption |

Apple's wording can vary. Read each displayed question carefully and answer according to the shipped binary and your legal situation.

The project includes this build setting:

`ITSAppUsesNonExemptEncryption = NO`

This reflects the current implementation, which uses Apple-provided HTTPS, Keychain, and operating-system security without implementing non-exempt encryption. This document is not legal advice.

## 10. Content Rights

Select:

> **No, it does not contain, show, or access third-party content.**

The app displays factual market-price and exchange-rate results obtained through provider APIs. Before release, confirm that use and attribution comply with the current Finnhub, CoinGecko, Frankfurter, and ECB terms. If Apple treats these feeds as third-party content in the displayed questionnaire, select **Yes** and confirm that you hold the necessary rights.

Do not upload copyrighted logos, publication content, or promotional artwork without permission.

## 11. Advertising Identifier

The app does not use the Advertising Identifier. If App Store Connect asks why the binary uses IDFA, stop and inspect dependencies because the current source has no advertising or tracking SDK.

## 12. Pricing and Availability

Recommended settings for the current app:

| Field | Value |
|---|---|
| Price | Free |
| In-App Purchases | None |
| Subscriptions | None |
| Availability | **REQUIRED - SELECT intended countries or regions** |
| Pre-order | No |
| App distribution | Public App Store |

Review third-party market-data licensing before selecting worldwide availability.

### EU Digital Services Act Trader Status

**REQUIRED - COMPLETE IN APP STORE CONNECT.**

Choose the status that accurately describes the developer:

- **Trader:** Apple will require verified public contact information for EU distribution.
- **Not a trader:** Use only if the developer acts outside a trade, business, craft, or profession.

This is a legal/business determination and cannot be inferred from the source code.

### Tax and Banking

For a free app with no paid content, paid-app banking setup is generally not needed. The Account Holder must still accept all current Apple agreements required for distribution.

## 13. Release Options

Recommended:

| Field | Value |
|---|---|
| Version release | Manually release this version |
| Phased release | Off for the first release |
| App Store server notifications | Not applicable |
| Game Center | Not used |
| In-App Events | None |
| Custom Product Pages | None |

Manual release gives the developer control over the public launch date after approval.

## 14. Permissions Used by the App

| Permission or capability | Purpose |
|---|---|
| Face ID / biometrics | Optional local app lock |
| Notifications | Optional reminders for recurring transactions |
| File importer | Import a user-selected Wealth Compass JSON backup |
| Share sheet | Export a user-created JSON backup |
| Network access | Fetch exchange rates and optional market prices |

Current Face ID usage text:

> Use Face ID to unlock your local Wealth Compass data.

Notification permission is requested in context when the user enables reminders. The app does not use location, contacts, camera, microphone, photos, HealthKit, Bluetooth, or motion data.

## 15. App Review Compliance Summary

| Topic | Current app behavior |
|---|---|
| Account creation | None |
| Account deletion requirement | Not applicable; no account exists |
| User data deletion | Settings > Data > Delete All Data |
| Purchases | None |
| External payments | None |
| Financial transactions | None |
| Bank connections | None |
| Investment execution | None |
| Financial advice | None; add disclaimer in description and privacy/support pages |
| Ads | None |
| Analytics | None |
| Tracking | None |
| Social features | None |
| Cloud sync | Optional opt-in iCloud sync via CloudKit (off by default; user's private iCloud database only) |
| Third-party SDKs | None visible in the current source |

## 16. Items That Must Be Prepared Outside App Store Connect

- A publicly accessible privacy policy page.
- A publicly accessible support page with valid contact information.
- App Review contact name, phone, and email.
- Developer or company legal name for copyright.
- Final country and region availability.
- EU trader-status declaration and verification, where applicable.
- App Store screenshots made from the production build using fictional data.
- Provider-terms review for Finnhub, CoinGecko, Frankfurter, and ECB data.
- A valid distribution certificate/profile or Xcode-managed signing configuration.
- An archived Release build uploaded through Xcode.

## 17. Pre-Submission Checklist

- [ ] Replace every **REQUIRED - REPLACE** value in this document.
- [ ] Confirm the app name is available.
- [ ] Confirm Bundle ID `com.wealthcompass.mobile`.
- [ ] Confirm version `1.2.0` and increment the build number (currently `12`) if that build was already successfully uploaded.
- [ ] Test the Release build on a physical iPhone running iOS 17 or later.
- [ ] Test launch with no network connection.
- [ ] Test add, edit, and delete flows for every financial record type.
- [ ] Test JSON export, merge import, and replace import.
- [ ] Test Delete All Data.
- [ ] Test notification permission granted and denied.
- [ ] Test biometric lock on a supported device.
- [ ] Verify all sample screenshot data is fictional.
- [ ] Publish the privacy policy and support pages before review.
- [ ] Complete App Privacy and publish the answers.
- [ ] Complete the age-rating questionnaire.
- [ ] Complete export-compliance answers.
- [ ] Complete content-rights answers.
- [ ] Complete pricing, availability, and EU trader status.
- [ ] Upload and select the correct build.
- [ ] Add screenshots and version metadata.
- [ ] Enter App Review contact information and review notes.
- [ ] Resolve all App Store Connect warnings.
- [ ] Add the version for review, then submit the draft submission.

## 18. Official Apple References

- [App information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/)
- [Platform version and App Review information](https://developer.apple.com/help/app-store-connect/reference/app-review-information)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Age ratings](https://developer.apple.com/help/app-store-connect/reference/age-ratings)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
