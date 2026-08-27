import SwiftUI

@main
struct WealthCompassMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var finance: FinanceStore
    @StateObject private var settings: AppSettings
    @StateObject private var appModel = MacAppModel()
    @StateObject private var appLock = MacAppLockStore()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _finance = StateObject(wrappedValue: FinanceStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(finance)
                .environmentObject(settings)
                .environmentObject(appModel)
                .environmentObject(appLock)
                .preferredColorScheme(.dark)
                .appLanguage(settings.appLanguage)
                // WC-M5: the language-change `.id` re-render lives inside MacRootView on the
                // post-onboarding view only — applying it here destroyed the onboarding view
                // (resetting its page + entered API keys) when the user picked a language on page 2.
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            DesktopCommands(finance: finance, settings: settings, appModel: appModel)
        }
    }
}
