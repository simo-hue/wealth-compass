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
                // WC-M5: the language-change `.id` re-render lives on the post-onboarding `tabs`
                // inside ContentView, so picking a language during onboarding (page 2) no longer
                // resets the flow. (Also stops ContentView.init re-running on every change — WC-L25.)
        }
    }
}
