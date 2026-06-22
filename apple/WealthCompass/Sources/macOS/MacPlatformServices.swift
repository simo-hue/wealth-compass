import AppKit
import Foundation
import LocalAuthentication
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let macRecurringTransactionNotificationReceived = Notification.Name(
        "wealthCompass.mac.recurringTransactionNotificationReceived"
    )
}

final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .macRecurringTransactionNotificationReceived, object: nil)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .macRecurringTransactionNotificationReceived, object: nil)
        completionHandler()
    }
}

enum MacRecurringTransactionNotificationService {
    /// Configured shared instance — the logic lives in the shared `RecurringNotificationService` (M2).
    static let shared = RecurringNotificationService(identifierPrefix: "wealth-compass-mac-recurring-")
}

@MainActor
/// macOS biometric app-lock — all logic lives in the shared `BiometricLockStore` (M2);
/// this only fixes the macOS-specific UserDefaults key.
final class MacAppLockStore: BiometricLockStore {
    init() {
        super.init(defaultsKey: "wc_mac_biometric_lock_enabled")
    }
}

struct MacLockView: View {
    @EnvironmentObject private var appLock: MacAppLockStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            ScreenBackground()

            FinanceCard {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(WCColor.primary)

                    VStack(spacing: 6) {
                        Text("Wealth Compass")
                            .font(.largeTitle.bold())
                        Text(settings.localized("Unlock with \(appLock.biometryName(appLanguage: settings.appLanguage))"))
                            .foregroundStyle(WCColor.textSecondary)
                    }

                    Button {
                        Task { await appLock.unlock(appLanguage: settings.appLanguage) }
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                            .font(.headline)
                            .frame(width: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)

                    if let error = appLock.lastError {
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WCColor.destructive)
                            .frame(maxWidth: 320)
                    }
                }
                .padding(24)
            }
            .frame(width: 430)
        }
        .task {
            await appLock.unlock(appLanguage: settings.appLanguage)
        }
    }
}
