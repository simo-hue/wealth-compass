# Manual Actions Needed for iCloud Sync

- Upload the new builds (Version 1.0.2, Build 3) to App Store Connect.
- Submit the newly uploaded builds for review in App Store Connect.

## App Store Connect Publish (Metadata Only)
- Open Terminal and navigate to `apple/WealthCompass`
- Run the command: `bundle exec fastlane deliver`
- Follow the prompts to log in with your Apple ID. This will automatically upload all 38 localized metadata folders without touching your App Store screenshots.
