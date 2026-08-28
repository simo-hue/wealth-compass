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

    /// Shows or hides the privacy cover in its **own window**, above everything the app presents.
    ///
    /// The cover used to be a SwiftUI `.overlay` on each root view. Every editor and export sheet is
    /// presented modally *above* the root's hosting controller, so the overlay painted behind them:
    /// with "Edit Investment" open — symbol, quantity, average buy price and current price all on
    /// screen — swiping to the app switcher covered the dashboard behind the sheet and left the
    /// sheet itself fully visible, and that is what iOS captured for the snapshot.
    ///
    /// A separate `UIWindow` is what fixes it rather than a bigger overlay: on iOS a sheet is
    /// presented *within* the same window, so any window above `.normal` necessarily covers it,
    /// whatever is presented and however deeply. It is not interactive and never becomes key, so it
    /// cannot take focus, swallow a touch, or affect what the app restores to.
    ///
    /// A no-op on macOS, where there is no snapshot to protect and the roots keep their overlay.
    @MainActor
    static func setPrivacyShieldVisible(_ isVisible: Bool) {
        #if !os(macOS)
        PrivacyShieldWindow.shared.setVisible(isVisible)
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
    /// Brings up the decimal keypad for a money or quantity field on touch.
    ///
    /// `keyboardType` does not exist on macOS, so the Desktop layer had none of these — and it now
    /// renders on an iPad, where every amount opened the full QWERTY keyboard and needed a manual
    /// switch to the numeric plane. The iPhone UI sets `.decimalPad` on all eleven of its money
    /// fields; this is the same thing for the shared layer.
    func desktopDecimalField() -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(.decimalPad)
        #endif
    }

    /// A ticker / ISIN field: uppercase, and never autocorrected.
    ///
    /// Without this an iPad autocapitalises the first letter only and helpfully corrects "VWCE"
    /// to a dictionary word.
    func desktopSymbolField() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.characters).autocorrectionDisabled()
        #endif
    }

    /// Widens a borderless icon button to the 44pt minimum on touch.
    ///
    /// The Desktop layer's row actions are `.controlSize(.small)` images — roughly 22pt, and 4pt
    /// apart. A pointer hits that precisely; a finger does not, and on the recurring-schedule row
    /// the pencil and the trash sit side by side, so aiming at Edit regularly opened Delete.
    /// A no-op on macOS, where 44pt would make a dense row twice as tall for no gain.
    func desktopTouchTarget() -> some View {
        #if os(macOS)
        self
        #else
        frame(width: 44, height: 44).contentShape(Rectangle())
        #endif
    }

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

#if !os(macOS)
import SwiftUI

/// Owns the privacy cover's window. See `DesktopPlatform.setPrivacyShieldVisible(_:)`.
@MainActor
final class PrivacyShieldWindow {
    static let shared = PrivacyShieldWindow()

    private var window: UIWindow?

    private init() {}

    func setVisible(_ isVisible: Bool) {
        guard isVisible else {
            window?.isHidden = true
            window = nil
            return
        }
        guard window == nil else { return }

        // Prefer the scene the user is actually looking at. On an iPad with several windows open,
        // attaching to a backgrounded scene would cover a window nobody is about to see while
        // leaving the visible one exposed.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .background }) ?? scenes.first else {
            return
        }

        let shield = UIWindow(windowScene: scene)
        // Above `.alert`, which is where UIKit puts presented alerts and action sheets.
        shield.windowLevel = .alert + 1
        // Never interactive and never key: the cover must not swallow the touch that dismisses it,
        // steal first responder from a field the user was editing, or change what the app restores.
        shield.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: PrivacyShieldCover())
        // The hosting controller's own background is clear by default, which would make the cover
        // translucent — the one thing it must never be.
        host.view.backgroundColor = UIColor(WCColor.background)
        shield.rootViewController = host
        shield.isHidden = false
        window = shield
    }

    /// Test seam: the window currently installed, if any.
    var installedWindow: UIWindow? { window }
}

private struct PrivacyShieldCover: View {
    var body: some View {
        ZStack {
            WCColor.background
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(WCColor.primary.opacity(0.5))
        }
        .ignoresSafeArea()
    }
}
#endif
