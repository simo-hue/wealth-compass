# Manual Actions Needed for iCloud Sync

To finish configuring iCloud in Xcode (based on your current setup):

1. **Select the Sync Type in Xcode (Capabilities Tab):**
   - Under the "Services" section, check **iCloud Documents** (recommended for your current JSON file-based approach).
   - Alternatively, check **CloudKit** if you plan to refactor the app to use a structured database (like CoreData or SwiftData) later.

2. **Add a Container:**
   - Under the "Containers" section, click the **+** button.
   - Select your developer team if prompted.
   - Xcode will automatically create or assign a default container for your bundle identifier (usually something like `iCloud.com.yourcompany.WealthCompass`). Make sure this new container is checked.

3. **Code Changes Needed After Setup:**
   - Your current data is saved via `LocalFinancePersistence` to the local Application Support directory. To sync via iCloud Documents, we'll need to update `FinancePersistence.swift` to use the iCloud Ubiquity Container (`FileManager.default.url(forUbiquityContainerIdentifier:)`). Let me know when you are done with the Xcode setup, and I can help update the code!
