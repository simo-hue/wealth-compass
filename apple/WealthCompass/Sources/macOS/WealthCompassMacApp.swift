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
                .id(settings.appLanguage ?? "system")
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
                // Settings is reached via the standard ⌘, Settings scene (M6) — no
                // sidebar destination / ⌘5 navigation command.
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
