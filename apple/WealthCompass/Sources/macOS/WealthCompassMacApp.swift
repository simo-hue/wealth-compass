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
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Transaction") {
                    appModel.editor = .transaction
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Investment") {
                    appModel.editor = .investment(nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("New Crypto Holding") {
                    appModel.editor = .crypto(nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // Sidebar navigation shortcuts (Cmd+1 through Cmd+5)
            CommandMenu("Navigate") {
                Button("Dashboard") {
                    appModel.selection = .dashboard
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Cash Flow") {
                    appModel.selection = .cashFlow
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Investments") {
                    appModel.selection = .investments
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Crypto") {
                    appModel.selection = .crypto
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Settings") {
                    appModel.selection = .settings
                }
                .keyboardShortcut("5", modifiers: .command)
            }

            SidebarCommands()
        }

        Settings {
            MacSettingsView()
                .environmentObject(finance)
                .environmentObject(settings)
                .environmentObject(appLock)
                .preferredColorScheme(.dark)
        }
    }
}
