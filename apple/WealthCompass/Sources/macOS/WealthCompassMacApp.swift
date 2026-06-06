import SwiftUI

@main
struct WealthCompassMacApp: App {
    @StateObject private var finance = FinanceStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var appModel = MacAppModel()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(finance)
                .environmentObject(settings)
                .environmentObject(appModel)
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
                .preferredColorScheme(.dark)
        }
    }
}
