import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let recurringTransactionNotificationReceived = Notification.Name(
        "wealthCompass.recurringTransactionNotificationReceived"
    )
}

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
}

enum RecurringTransactionNotificationService {
    /// Configured shared instance — the logic lives in the shared `RecurringNotificationService` (M2).
    static let shared = RecurringNotificationService(identifierPrefix: "wealth-compass-recurring-")
}
