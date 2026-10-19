import SwiftUI

@main
struct WealthCompassMobileApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @StateObject private var financeStore: FinanceStore
    @StateObject private var settings: AppSettings
    @StateObject private var appLock = AppLockStore()
    // Navigation state for the desktop-class UI. Constructed on every device — an iPhone simply
    // never reads it — because a `@StateObject` cannot be created conditionally without changing
    // the App's storage layout between devices.
    @StateObject private var appModel = MacAppModel()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _financeStore = StateObject(wrappedValue: FinanceStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(financeStore)
                .environmentObject(settings)
                .environmentObject(appLock)
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
                .appLanguage(settings.appLanguage)
                // WC-M5: the language-change `.id` re-render lives on the post-onboarding view
                // inside each root (ContentView's `tabs`, MacRootView's split view), so picking a
                // language during onboarding no longer resets the flow. (Also stops the root's
                // `init` re-running on every change — WC-L25.)
        }
        // iPad gets the Mac's File/Navigate menus and their ⌘ shortcuts — the iPadOS menu bar
        // draws them, and the shortcut HUD lists them. `isEnabled` keeps them off the iPhone,
        // where nothing observes `MacAppModel` and they would be dead keys.
        .commands {
            DesktopCommands(
                finance: financeStore,
                settings: settings,
                appModel: appModel,
                appLock: appLock,
                isEnabled: DesktopPlatform.isPad
            )
        }
    }
}

/// Picks the UI for the device. iPad runs the desktop-class views from `Sources/Desktop/` — the
/// same sidebar, pages, editors and styling as the Mac — while iPhone keeps its `TabView`.
///
/// The test is device idiom, not horizontal size class, and that is deliberate. A size-class test
/// would swap the entire app between two different UIs as the user dragged a Split View divider,
/// losing navigation state and re-presenting sheets mid-gesture. `NavigationSplitView` already
/// collapses to a navigation stack on its own when the window is narrow, so the desktop UI stays
/// usable in Slide Over without the app changing shape underneath anyone.
private struct RootView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            MacRootView()
        } else {
            ContentView()
        }
    }
}
