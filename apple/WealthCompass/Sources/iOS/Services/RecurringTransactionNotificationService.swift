import Foundation
import os
import UIKit
import UserNotifications

extension Notification.Name {
    static let recurringTransactionNotificationReceived = Notification.Name(
        "wealthCompass.recurringTransactionNotificationReceived"
    )
}

/// M31: diagnostics for the CloudKit push channel, via the unified log (App-Store-safe).
private let cloudKitPushLog = Logger(subsystem: "com.wealthcompass.mobile", category: "CloudKitPush")

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.configureTabBarAppearance()
        return true
    }

    /// WC-L25: configure the global `UITabBar` appearance once at launch, instead of mutating the
    /// shared appearance proxy from `ContentView.init` — which re-ran on every `@Published`
    /// settings change (currency, privacy, …) since the App body reads `settings`.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(red: 0.035, green: 0.05, blue: 0.085, alpha: 0.78)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        let normalColor = UIColor.white.withAlphaComponent(0.52)
        let selectedColor = UIColor(red: 0.12, green: 0.86, blue: 0.60, alpha: 1)
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .recurringTransactionNotificationReceived, object: nil)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .recurringTransactionNotificationReceived, object: nil)
        completionHandler()
    }

    // MARK: - M31: CloudKit push (remote notifications)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // The token isn't sent anywhere — CloudKit owns the APNs channel server-side. Registration
        // succeeding is what matters; log it for diagnostics.
        cloudKitPushLog.info("Registered for remote notifications (\(deviceToken.count) byte token).")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        cloudKitPushLog.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        // A silent CloudKit push: a remote device changed the zone. Drive a fetch, then report new data
        // so the system keeps waking us for future pushes. `handleRemoteCloudKitPush` no-ops if sync is off.
        cloudKitPushLog.info("Received remote notification — triggering CloudKit sync.")
        await FinanceStore.handleRemoteCloudKitPush()
        return .newData
    }
}

enum RecurringTransactionNotificationService {
    /// Configured shared instance — the logic lives in the shared `RecurringNotificationService` (M2).
    static let shared = RecurringNotificationService(identifierPrefix: "wealth-compass-recurring-")
}
