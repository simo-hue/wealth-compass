import Foundation
import UserNotifications

/// Schedules local "recurring transaction due" reminders (M2).
///
/// Extracted from the byte-identical iOS + macOS notification actors, which differed
/// only in their notification-identifier prefix. The platform app delegates (UIKit /
/// AppKit) that forward notification taps stay per-platform; each platform exposes a
/// configured `.shared` instance of this actor.
actor RecurringNotificationService {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix: String

    init(identifierPrefix: String) {
        self.identifierPrefix = identifierPrefix
    }

    func requestAuthorization() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if Self.isAuthorized(status) { return true }
        guard status == .notDetermined else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// `.ephemeral` (App Clips) exists only on iOS, so it's guarded per-platform.
    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            return true
        #if os(iOS)
        case .ephemeral:
            return true
        #endif
        default:
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

        guard Self.isAuthorized(await center.notificationSettings().authorizationStatus) else {
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

        // Read the in-app language once, not once per schedule (WC-L31).
        let appLanguage = UserDefaults.standard.string(forKey: "wc_mobile_app_language")
        for schedule in upcoming {
            let content = UNMutableNotificationContent()
            content.title = AppLocalization.string("Recurring \(schedule.type.localizedTitle(appLanguage: appLanguage)) due", appLanguage: appLanguage)
            if showAmounts {
                // `schedule.amount` is Decimal (WC-A1); use the Decimal currency format style.
                let amount = schedule.amount.formatted(
                    .currency(code: currencyCode)
                )
                content.body = AppLocalization.string("\(schedule.category): \(amount). Wealth Compass records it automatically when the app is active.", appLanguage: appLanguage)
            } else {
                content.body = AppLocalization.string("\(schedule.category) is scheduled. Open Wealth Compass to review it.", appLanguage: appLanguage)
            }
            content.sound = .default
            content.userInfo = ["recurringTransactionID": schedule.id.uuidString]

            var dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.nextDueDate
            )
            // WC-L5: date-only / imported schedules carry a midnight time, which would fire the
            // reminder at 00:00. Pin those to 9:00 local; schedules with a real time keep it.
            if (dateComponents.hour ?? 0) == 0 && (dateComponents.minute ?? 0) == 0 {
                dateComponents.hour = 9
                dateComponents.minute = 0
            }
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
