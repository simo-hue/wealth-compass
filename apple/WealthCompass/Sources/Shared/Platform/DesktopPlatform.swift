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

import SwiftUI

extension View {
    /// A Mac window/sheet size floor, applied only on macOS.
    ///
    /// These numbers exist because a Mac window is the *user's* to drag, and the content needs a
    /// floor below which it stops working. An iPad window is sized by the system instead, and the
    /// sizes it hands out include a 320pt Slide Over — where a 520pt floor does not protect the
    /// layout, it pushes it off the screen. Off macOS this is a no-op and the platform's own
    /// sheet and window sizing wins.
    @ViewBuilder
    func desktopWindowSize(
        minWidth: CGFloat,
        idealWidth: CGFloat? = nil,
        minHeight: CGFloat,
        idealHeight: CGFloat? = nil
    ) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight, idealHeight: idealHeight)
        #else
        self
        #endif
    }

    /// A fixed Mac card width that becomes a cap on iPad, where the window itself can be narrower
    /// than the card the Mac always has room for.
    @ViewBuilder
    func desktopCardWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        frame(maxWidth: width)
        #endif
    }

    /// A fixed Mac sheet size, applied only on macOS. Same reasoning as `desktopWindowSize`; on
    /// iPad these sheets take the system form-sheet size, which is close to the Mac's ideal anyway.
    @ViewBuilder
    func desktopFixedSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }
}

extension Color {
    /// AppKit's `controlBackgroundColor`, which has no UIKit counterpart.
    ///
    /// Both apps force `.preferredColorScheme(.dark)`, so there is exactly one appearance to
    /// match and the iPad value can be the literal dark-aqua one — measured, not guessed:
    /// `NSColor.controlBackgroundColor` resolves to sRGB #1E1E1E (0.117647 grey) under
    /// `NSAppearance(named: .darkAqua)`. macOS keeps reading the dynamic system colour so it
    /// still follows any future appearance change there.
    static var desktopControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(white: 0.117647)
        #endif
    }
}

extension View {
    /// Label style for an item inside a `Menu`.
    ///
    /// `NSMenu` sizes itself to its content, so the Mac shows icon + title at any length. UIKit
    /// caps a toolbar menu at ~250pt, which leaves roughly 150pt for the title once the icon and
    /// insets are taken — and "One-Time Transaction" needs ~175pt, so iPadOS broke it *mid-word*
    /// ("One-Time Transac-/tion"). Dropping the icon returns those ~36pt and the title fits on one
    /// line. The icon is decorative here; the wrapped word was not.
    @ViewBuilder
    func desktopMenuLabelStyle() -> some View {
        #if os(macOS)
        self
        #else
        labelStyle(.titleOnly)
        #endif
    }
}
