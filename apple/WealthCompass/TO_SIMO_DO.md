# Manual Actions Needed for iCloud Sync

2. **Add a Container:**
   - You must do this for **BOTH** the `WealthCompassMac` and `WealthCompassMobile` targets.
   - Under the "Containers" section, click the **+** button.
   - Select your developer team if prompted.
   - Xcode will automatically create or assign a default container for your bundle identifier (usually something like `iCloud.com.yourcompany.WealthCompass`). Make sure this new container is checked on both targets.

3. **Code Changes Needed After Setup:**
   - *These are already completed.* The code in `FinancePersistence.swift` and `FinanceStore.swift` is fully shared between both platforms. It is already actively managing dual-storage iCloud sync for you behind the scenes whenever `isICloudSyncEnabled` is toggled!
