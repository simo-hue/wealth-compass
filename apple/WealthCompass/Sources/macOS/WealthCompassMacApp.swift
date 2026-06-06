import SwiftUI

@main
struct WealthCompassMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var finance = FinanceStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var appModel = MacAppModel()
    @StateObject private var appLock = MacAppLockStore()

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
