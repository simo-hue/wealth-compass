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
        return true
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

actor RecurringTransactionNotificationService {
    static let shared = RecurringTransactionNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "wealth-compass-recurring-"

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func sync(
        schedules: [RecurringTransaction],
        currencyCode: String,
        showAmounts: Bool,
        now: Date = Date()
    ) async {
        let pendingRequests = await center.pendingNotificationRequests()
        let recurringIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: recurringIdentifiers)

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return
        }

        let upcoming = schedules
            .filter { schedule in
                schedule.isActive
                    && !schedule.isCompleted
                    && schedule.notificationsEnabled
                    && schedule.nextDueDate > now
                    && (schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true)
            }
            .sorted { $0.nextDueDate < $1.nextDueDate }
            .prefix(60)

        for schedule in upcoming {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Recurring \(schedule.type.title) due")
            if showAmounts {
                let amount = schedule.amount.formatted(
                    FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
                )
                content.body = String(localized: "\(schedule.category): \(amount). Wealth Compass records it automatically when the app is active.")
            } else {
                content.body = String(localized: "\(schedule.category) is scheduled. Open Wealth Compass to review it.")
            }
            content.sound = .default
            content.userInfo = ["recurringTransactionID": schedule.id.uuidString]

            let dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.nextDueDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: schedule.id),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancel(scheduleID: UUID) {
        let identifier = notificationIdentifier(for: scheduleID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notificationIdentifier(for scheduleID: UUID) -> String {
        "\(identifierPrefix)\(scheduleID.uuidString)"
    }
}
