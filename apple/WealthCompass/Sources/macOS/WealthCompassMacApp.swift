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
            // WC-LOCK1: these bypass the root view's `loadState` gate entirely — the editor sheet
            // is attached outside it — so without this a ⌘N over the "Data Unavailable" screen
            // would open a transaction form, accept everything the user typed into the in-memory
            // dataset, and then have `save()` refuse it. The entry would vanish on the next
            // successful load with no indication it was ever discarded.
            CommandGroup(replacing: .newItem) {
                Button(AppLocalization.string("New Transaction", appLanguage: settings.appLanguage)) {
                    appModel.editor = .transaction
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(finance.loadState != .loaded)

                Button(AppLocalization.string("New Investment", appLanguage: settings.appLanguage)) {
                    appModel.editor = .investment(nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(finance.loadState != .loaded)

                Button(AppLocalization.string("New Crypto Holding", appLanguage: settings.appLanguage)) {
                    appModel.editor = .crypto(nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(finance.loadState != .loaded)
            }

            // A Mac app without a File-menu export feels broken, and this routes to the same
            // shared sheet the Settings page uses rather than adding a second export surface.
            CommandGroup(after: .newItem) {
                Divider()
                Button(AppLocalization.string("Export...", appLanguage: settings.appLanguage)) {
                    appModel.requestExport()
                }
                .keyboardShortcut("e", modifiers: .command)
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

                Button(AppLocalization.string("Settings", appLanguage: settings.appLanguage)) {
                    appModel.selection = .settings
                }
                .keyboardShortcut("5", modifiers: .command)
            }

            // ⌘, now selects the in-window Settings page instead of opening a separate Preferences
            // window (the `Settings { }` scene was removed so there's a single MacSettingsView surface).
            // Keeps the standard App ▸ Settings menu item working.
            CommandGroup(replacing: .appSettings) {
                Button(AppLocalization.string("Settings", appLanguage: settings.appLanguage)) {
                    appModel.selection = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            SidebarCommands()
        }
    }
}
