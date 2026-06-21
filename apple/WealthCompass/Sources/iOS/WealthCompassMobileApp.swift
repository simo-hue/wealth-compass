import SwiftUI

@main
struct WealthCompassMobileApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @StateObject private var financeStore: FinanceStore
    @StateObject private var settings: AppSettings
    @StateObject private var appLock = AppLockStore()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _financeStore = StateObject(wrappedValue: FinanceStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(financeStore)
                .environmentObject(settings)
                .environmentObject(appLock)
                .preferredColorScheme(.dark)
                .appLanguage(settings.appLanguage)
                .id(settings.appLanguage ?? "system")
        }
    }
}
