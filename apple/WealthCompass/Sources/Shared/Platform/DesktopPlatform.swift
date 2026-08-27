#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// The desktop-class UI in `Sources/Desktop/` compiles into **both** app targets: it is the macOS
/// app, and it is also what an iPad runs (iPhone keeps the `TabView` UI in `Sources/iOS/`). This
/// file is the whole of the platform difference.
///
/// Two shapes are used, deliberately:
///
/// * `DesktopPlatform` for behaviour that has no common spelling — only `registerForRemoteNotifications`
///   qualifies, since `NSApplication` and `UIApplication` are unrelated types.
/// * `typealias`es *toward the Mac names* for the per-platform singletons. Aliasing this direction
///   means the moved Desktop files reference `MacAppLockStore` and
///   `MacRecurringTransactionNotificationService` exactly as they always did, and stayed a pure
///   `git mv` — nothing in ~5,500 lines of working macOS UI had to be renamed to gain an iPad. The
///   Mac-only definitions live in `Sources/macOS/MacAppDelegate.swift`; the iOS ones in
///   `Sources/iOS/Services/`.
enum DesktopPlatform {
    /// M31: register for the silent CloudKit pushes that propagate remote changes without a
    /// foreground round-trip. Idempotent; callers gate it on `settings.isICloudSyncEnabled`.
    @MainActor
    static func registerForRemoteNotifications() {
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// True when this build is running the desktop-class UI on an iPad, rather than on a Mac.
    /// Used only where a control genuinely cannot exist on one of the two (file panels), never to
    /// vary layout — the whole point of sharing the layer is that iPad and Mac look the same.
    static var isPad: Bool {
        #if os(macOS)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

#if !os(macOS)
/// On iPad the desktop UI drives the *iOS* lock store and notification service, so it shares the
/// iPhone's UserDefaults key (`wc_mobile_biometric_lock_enabled`) and notification identifier
/// prefix. A device must not keep two independent lock settings or two sets of pending reminders
/// depending on which UI it happened to render.
typealias MacAppLockStore = AppLockStore
typealias MacRecurringTransactionNotificationService = RecurringTransactionNotificationService

extension Notification.Name {
    /// `AppNotificationDelegate` posts the iOS name; the Desktop layer listens for the Mac one.
    static let macRecurringTransactionNotificationReceived = Notification.Name
        .recurringTransactionNotificationReceived
}
#endif
