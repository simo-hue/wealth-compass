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
            CommandGroup(replacing: .newItem) {
                Button(AppLocalization.string("New Transaction", appLanguage: settings.appLanguage)) {
                    appModel.editor = .transaction
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(AppLocalization.string("New Investment", appLanguage: settings.appLanguage)) {
                    appModel.editor = .investment(nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button(AppLocalization.string("New Crypto Holding", appLanguage: settings.appLanguage)) {
                    appModel.editor = .crypto(nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // Sidebar navigation shortcuts (Cmd+1 through Cmd+5)
            CommandMenu(AppLocalization.string("Navigate", appLanguage: settings.appLanguage)) {
                Button(AppLocalization.string("Dashboard", appLanguage: settings.appLanguage)) {
                    appModel.selection = .dashboard
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(AppLocalization.string("Cash Flow", appLanguage: settings.appLanguage)) {
                    appModel.selection = .cashFlow
                }
                .keyboardShortcut("2", modifiers: .command)

                Button(AppLocalization.string("Investments", appLanguage: settings.appLanguage)) {
                    appModel.selection = .investments
                }
                .keyboardShortcut("3", modifiers: .command)

                Button(AppLocalization.string("Crypto", appLanguage: settings.appLanguage)) {
                    appModel.selection = .crypto
                }
                .keyboardShortcut("4", modifiers: .command)

                // L15: Settings is reached via the native ⌘, scene below, not a sidebar destination.
            }

            SidebarCommands()
        }

        Settings {
            MacSettingsView()
                .environmentObject(finance)
                .environmentObject(settings)
                .environmentObject(appLock)
                .preferredColorScheme(.dark)
                .appLanguage(settings.appLanguage)
                .id(settings.appLanguage ?? "system")
        }
    }
}
