# TO SIMO DO

This document tracks manual actions and considerations for you to address.

- [ ] Onboarding tutorial for inserting the API KEY for the tracking of the assets for both macOS and iOS.

---

cd apple
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac -destination 'platform=macOS' build
xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'generic/platform=iOS Simulator' build
# suite should stay green (no test changes this batch):
xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'