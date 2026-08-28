import SwiftUI

/// The desktop menu commands: File ▸ New…/Export…, a Navigate menu, and the sidebar toggle.
///
/// Shared by the Mac app and the iPad, which draws them in the iPadOS menu bar and lists them in
/// the hardware-keyboard shortcut HUD. None of this summons the on-screen keyboard or takes any
/// room from the app — a shortcut with no keyboard attached simply never fires.
///
/// `isEnabled` wraps *every* group, `SidebarCommands()` included — an iPhone has no sidebar to
/// toggle, and an escaped `SidebarCommands()` would have offered ⌃⌘S for one anyway.
///
/// `isEnabled` is what keeps them off the iPhone. The same binary runs there, but iPhone renders
/// `ContentView`, whose navigation is its own `@State` tab — it never reads `MacAppModel`. Attached
/// unconditionally, ⌘N on an iPhone with a Magic Keyboard would set `appModel.editor` where nothing
/// is watching it and appear to do nothing at all, which is worse than having no shortcut.
struct DesktopCommands: Commands {
    @ObservedObject var finance: FinanceStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var appModel: MacAppModel
    var isEnabled: Bool = true

    var body: some Commands {
        if isEnabled {
            commands
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        // WC-LOCK1: these bypass the root view's `loadState` gate entirely — the editor sheet
        // is attached outside it — so without the `.disabled` a ⌘N over the "Data Unavailable"
        // screen would open a transaction form, accept everything the user typed into the
        // in-memory dataset, and then have `save()` refuse it. The entry would vanish on the next
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

        // A desktop-class app without a File-menu export feels broken, and this routes to the same
        // shared sheet the Settings page uses rather than adding a second export surface.
        CommandGroup(after: .newItem) {
            Divider()
            Button(AppLocalization.string("Export...", appLanguage: settings.appLanguage)) {
                appModel.requestExport()
            }
            .keyboardShortcut("e", modifiers: .command)
            // Same guard the New-item buttons above carry, and for the same reason: with the data
            // unloaded the root renders `FinanceDataUnavailableView` and never builds the Settings
            // page, so this sets an export token nothing is listening for — and the token persists,
            // so the sheet then popped unprompted the moment a retry succeeded.
            .disabled(finance.loadState != .loaded)
        }

        // Sidebar navigation shortcuts (⌘1 through ⌘5).
        CommandMenu(AppLocalization.string("Navigate", appLanguage: settings.appLanguage)) {
            navigateButton(.dashboard, "Dashboard", key: "1")
            navigateButton(.cashFlow, "Cash Flow", key: "2")
            navigateButton(.investments, "Investments", key: "3")
            navigateButton(.crypto, "Crypto", key: "4")
            navigateButton(.settings, "Settings", key: "5")
        }

        #if os(macOS)
        // ⌘, selects the in-window Settings page instead of opening a separate Preferences window
        // (the `Settings { }` scene was removed so there's a single MacSettingsView surface).
        // Keeps the standard App ▸ Settings menu item working. macOS-only: iPadOS has no
        // application menu for `.appSettings` to replace.
        CommandGroup(replacing: .appSettings) {
            Button(AppLocalization.string("Settings", appLanguage: settings.appLanguage)) {
                appModel.selection = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            // The same guard as Navigate above: with the data unloaded the root replaces the split
            // view entirely, so there is no Settings destination for this to select.
            .disabled(finance.loadState != .loaded)
        }
        #endif

        SidebarCommands()
    }

    private func navigateButton(
        _ destination: MacDestination,
        _ title: String.LocalizationValue,
        key: KeyEquivalent
    ) -> some View {
        Button(AppLocalization.string(title, appLanguage: settings.appLanguage)) {
            appModel.selection = destination
        }
        .keyboardShortcut(key, modifiers: .command)
        // Likewise: with nothing loaded these rewrite a selection no view is observing.
        .disabled(finance.loadState != .loaded)
    }
}
