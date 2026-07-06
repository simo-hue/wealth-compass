import AppKit
import Foundation
import LocalAuthentication
import os
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let macRecurringTransactionNotificationReceived = Notification.Name(
        "wealthCompass.mac.recurringTransactionNotificationReceived"
    )
}

/// M31: diagnostics for the CloudKit push channel, via the unified log (App-Store-safe).
private let cloudKitPushLog = Logger(subsystem: "com.wealthcompass.mobile", category: "CloudKitPush")

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

    // MARK: - M31: CloudKit push (remote notifications)

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit owns the APNs channel server-side; registration succeeding is what matters.
        cloudKitPushLog.info("Registered for remote notifications (\(deviceToken.count) byte token).")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        cloudKitPushLog.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        // A silent CloudKit push: a remote device changed the zone. macOS has no background-fetch result,
        // so kick off the sync in a Task. `handleRemoteCloudKitPush` no-ops if sync is off.
        cloudKitPushLog.info("Received remote notification — triggering CloudKit sync.")
        Task { await FinanceStore.handleRemoteCloudKitPush() }
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
    /// One auto-prompt per lock episode (M02): the view re-renders on every focus regain, so without
    /// this the biometric sheet would re-present unsolicited each time the window becomes key.
    @State private var hasAutoPrompted = false

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
                    .disabled(appLock.isAuthenticating)

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
            guard !hasAutoPrompted else { return }
            hasAutoPrompted = true
            await appLock.unlock(appLanguage: settings.appLanguage)
        }
        .onChange(of: appLock.isUnlocked) { _, unlocked in
            // Re-arm the one-shot auto-prompt for the next lock episode.
            if !unlocked { hasAutoPrompted = false }
        }
    }
}
