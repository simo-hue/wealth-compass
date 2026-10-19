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
    @ObservedObject var appLock: MacAppLockStore
    var isEnabled: Bool = true

    var body: some Commands {
        if isEnabled {
            commands
        }
    }

    /// Whether the menu commands may fire, given what the root view is currently rendering.
    ///
    /// Pure and `static` because neither a `Commands` tree nor the menu bar it builds is reachable
    /// from a unit test; the condition every command below shares is.
    ///
    /// Both terms are the same mistake, caught twice. These commands are attached to the *scene*,
    /// so they outlive every branch `MacRootView`'s body takes — and the editor sheet is attached
    /// to the enclosing `Group`, outside those branches too. `loadState` covered the "Data
    /// Unavailable" screen. The app lock is a view gate that sits *before* the loadState branch
    /// and leaves `loadState == .loaded`, so on the lock screen ⌘N opened a New Transaction sheet
    /// (exposing the user's custom category names, and accepting a save), ⌘1-5 / ⌘, navigated
    /// behind it, and ⌘E armed an export token that fired on unlock. The `onChange(of:)` handlers
    /// in `MacRootView` dismiss a sheet that was *already open* when the lock engaged; they cannot
    /// see a command fired while the app is already locked.
    static func commandsEnabled(
        loadState: FinanceDataLoadState,
        isLockEnabled: Bool,
        isUnlocked: Bool
    ) -> Bool {
        loadState == .loaded && !(isLockEnabled && !isUnlocked)
    }

    private var commandsEnabled: Bool {
        Self.commandsEnabled(
            loadState: finance.loadState,
            isLockEnabled: appLock.isLockEnabled,
            isUnlocked: appLock.isUnlocked
        )
    }

    /// **The gate has to live inside the action, not in `.disabled(...)`. Measured, not assumed.**
    ///
    /// A `Commands` tree is built once and its menu items are never re-applied. A throwaway
    /// SwiftUI/AppKit app (`CommandGroup(replacing: .newItem)` *and* `CommandMenu`, an
    /// `@ObservedObject` in the `Commands` struct, a plain `Bool` read in `App.body`, and
    /// `@FocusedValue` — all four) showed the same thing on macOS 26: flipping the published value
    /// re-runs the `.commands { }` builder with the new value, and the `NSMenuItem` does not
    /// change. Not its `isEnabled`, not even its **title**. Whatever `.disabled(...)` evaluated to
    /// when the scene was first built is what the menu keeps for the life of the process, and
    /// `NSMenu.performKeyEquivalent` — the path a ⌘-shortcut actually takes — honours that frozen
    /// value.
    ///
    /// So `.disabled(!commandsEnabled)` was wrong in *both* directions, and the second one is the
    /// dangerous one:
    ///
    /// - Launch **unlocked** (the lock disabled, or enabled and engaged later on backgrounding):
    ///   frozen enabled. ⌘N still draws a transaction form over the lock screen — the bug is not
    ///   closed at all.
    /// - Launch **locked** (`BiometricLockStore.init` sets `isUnlocked = !isLockEnabled`, so this
    ///   is every launch for a user who turned the lock on): frozen *disabled*, and unlocking does
    ///   not bring the menus back. ⌘N, ⌘⇧I, ⌘⇧K, ⌘E, ⌘1-5 and ⌘, stay dead for the whole session,
    ///   on Mac and iPad alike.
    ///
    /// Reading the condition inside the action works, and is the one variant that did: the closure
    /// captures the *stores*, which are reference types, so it reads `isUnlocked` / `loadState` at
    /// the moment the key is pressed. The same probe confirmed it tracks locked → unlocked →
    /// locked exactly.
    ///
    /// The cost is the greyed-out affordance, and it is not a real cost: that affordance never
    /// worked: it froze at launch. A command that quietly does nothing is strictly better than one
    /// that opens an editor over the lock screen, and better than one the user can never use again.
    private func gated(_ action: @escaping () -> Void) -> () -> Void {
        { if commandsEnabled { action() } }
    }

    @CommandsBuilder
    private var commands: some Commands {
        // WC-LOCK1: these bypass the root view's `loadState` gate entirely — the editor sheet
        // is attached outside it — so ungated, a ⌘N over the "Data Unavailable" screen would open
        // a transaction form, accept everything the user typed into the in-memory dataset, and
        // then have `save()` refuse it. The entry would vanish on the next successful load with no
        // indication it was ever discarded.
        //
        // The **app-lock screen** is the same escape and is covered too: it is a view gate sitting
        // *before* the loadState branch, so `loadState` stays `.loaded` while locked and every one
        // of these commands was live over it — ⌘N drew a transaction form (with the user's own
        // category names in it) on top of the lock. `commandsEnabled` reads both.
        //
        // Every action goes through `gated`, and none of them carries `.disabled(...)`. See that
        // helper: a menu item's disabled state is frozen at scene construction, so `.disabled` here
        // gated nothing on the launch-unlocked path and permanently killed all six shortcuts on the
        // launch-locked one.
        CommandGroup(replacing: .newItem) {
            Button(AppLocalization.string("New Transaction", appLanguage: settings.appLanguage),
                   action: gated { appModel.editor = .transaction })
                .keyboardShortcut("n", modifiers: .command)

            Button(AppLocalization.string("New Investment", appLanguage: settings.appLanguage),
                   action: gated { appModel.editor = .investment(nil) })
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(AppLocalization.string("New Crypto Holding", appLanguage: settings.appLanguage),
                   action: gated { appModel.editor = .crypto(nil) })
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        // A desktop-class app without a File-menu export feels broken, and this routes to the same
        // shared sheet the Settings page uses rather than adding a second export surface.
        CommandGroup(after: .newItem) {
            Divider()
            // Same guard the New-item buttons above carry, and for the same reason: with the data
            // unloaded the root renders `FinanceDataUnavailableView` and never builds the Settings
            // page, so this sets an export token nothing is listening for — and the token persists,
            // so the sheet then popped unprompted the moment a retry succeeded.
            Button(AppLocalization.string("Export...", appLanguage: settings.appLanguage),
                   action: gated { appModel.requestExport() })
                .keyboardShortcut("e", modifiers: .command)
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
            // The same guard as Navigate above: with the data unloaded the root replaces the split
            // view entirely, so there is no Settings destination for this to select.
            Button(AppLocalization.string("Settings", appLanguage: settings.appLanguage),
                   action: gated { appModel.selection = .settings })
                .keyboardShortcut(",", modifiers: .command)
        }
        #endif

        SidebarCommands()
    }

    private func navigateButton(
        _ destination: MacDestination,
        _ title: String.LocalizationValue,
        key: KeyEquivalent
    ) -> some View {
        // Likewise: with nothing loaded these rewrite a selection no view is observing.
        Button(AppLocalization.string(title, appLanguage: settings.appLanguage),
               action: gated { appModel.selection = destination })
            .keyboardShortcut(key, modifiers: .command)
    }
}
