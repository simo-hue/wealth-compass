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

    /// - Parameter showDetails: Privacy Mode inverted (`!settings.isPrivacyMode`). It gates the
    ///   whole notification, not just the figure. The name used to be `showAmounts`, and that was
    ///   the leak: the amount was redacted while `content.title` still named the *type* and
    ///   `content.body` still named the *category*, so a locked phone showed "Recurring Expense
    ///   due — Rent is scheduled" on a surface that needs no unlock. Every other disclosure this
    ///   audit series closed needed someone holding the device already unlocked. With the flag
    ///   down the notification says only that the app wants attention.
    func sync(
        schedules: [RecurringTransaction],
        convertedAmounts: [UUID: Decimal],
        currencyCode: String,
        showDetails: Bool,
        now: Date = Date()
    ) async {
        await clearScheduledReminders()

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

        // Read the in-app language once, not once per schedule, and source the key from the single
        // source of truth on AppSettings rather than a brittle literal (WC-L31).
        let appLanguage = UserDefaults.standard.string(forKey: AppSettings.appLanguageDefaultsKey)
        for schedule in upcoming {
            let content = Self.content(
                for: schedule,
                convertedAmount: convertedAmounts[schedule.id],
                currencyCode: currencyCode,
                showDetails: showDetails,
                appLanguage: appLanguage
            )

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

    /// Everything one schedule puts on a lock screen.
    ///
    /// Split out of `sync` so it can be asserted on directly: `sync` itself returns early unless
    /// `UNUserNotificationCenter` reports an authorization, which a test host is never granted, so
    /// nothing downstream of that guard is reachable from a test. `nonisolated` for the same
    /// reason — it reads only its arguments.
    ///
    /// With `showDetails` false **no property of `schedule` is read**, which is the property the
    /// lock screen needs: title, body and every other rendered field are the same two constants
    /// for every schedule, so nothing a bystander can see moves with the data.
    nonisolated static func content(
        for schedule: RecurringTransaction,
        convertedAmount: Decimal?,
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if showDetails {
            content.title = AppLocalization.string("Recurring \(schedule.type.localizedTitle(appLanguage: appLanguage)) due", appLanguage: appLanguage)
            // `schedule.amount` is Decimal (WC-A1) in the schedule's OWN currency. The caller
            // pre-converts it to the display currency on the @MainActor (deep-audit M20), so the
            // number and the currency code agree; fall back to the raw amount if absent.
            let displayAmount = convertedAmount ?? schedule.amount
            // L49: format the amount in the in-app language's locale too, so its separators and
            // symbol placement match the surrounding sentence (not the system locale).
            let amount = displayAmount.formatted(
                .currency(code: currencyCode)
                    .locale(AppLocalization.effectiveLocale(appLanguage: appLanguage))
            )
            content.body = AppLocalization.string("\(schedule.category): \(amount). Wealth Compass Tracker records it automatically when the app is active.", appLanguage: appLanguage)
        } else {
            // The title has to move with the body. `Recurring %@ due` names the *type* — Expense or
            // Income — independently of anything the body says, so redacting only the body left
            // half the disclosure standing on a surface that needs no unlock.
            content.title = AppLocalization.string("Reminder", appLanguage: appLanguage)
            content.body = AppLocalization.string("Open Wealth Compass Tracker to review.", appLanguage: appLanguage)
        }
        content.sound = .default
        // Everything else `UNMutableNotificationContent` can put on a lock screen is either never
        // set here or cannot vary with the schedule: `subtitle`, `threadIdentifier`,
        // `categoryIdentifier`, `badge` and `attachments` are all left at their defaults, and
        // `sound` is `.default` on both branches. `userInfo` carries an opaque UUID for the tap
        // handler; it is app-private payload, it is never rendered, and it names nothing.
        content.userInfo = ["recurringTransactionID": schedule.id.uuidString]
        return content
    }

    func cancel(scheduleID: UUID) {
        let identifier = notificationIdentifier(for: scheduleID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() async {
        await clearScheduledReminders()
    }

    /// Tears down every reminder this service owns — the ones still waiting to fire **and the ones
    /// already sitting on the lock screen**.
    ///
    /// Both halves matter, and until now neither teardown path had both.
    ///
    /// `sync` removed pending requests only. So a reminder that had already fired — "Recurring
    /// Expense due / Rent: €1.450,00" — stayed on the lock screen and in Notification Center after
    /// the user turned Privacy Mode *on*. The toggle does re-run `sync`
    /// (`ContentView.swift:119`, `MacRootView.swift:125`), which rewrote the pending set correctly
    /// and then walked past the banner already published. That is the normal case, not the corner
    /// one: people turn Privacy Mode on *because* schedules exist, so a fired reminder is exactly
    /// what is on screen at that moment.
    ///
    /// `cancelAll` looked like it handled the delivered case and did not. It filtered
    /// `pendingNotificationRequests()` and handed **that** list to `removeDeliveredNotifications`,
    /// but a notification that has been delivered is by definition no longer pending, so its
    /// identifier was never in the list and the call could not reach it. `cancelAll` is the
    /// erase-everything path (`SettingsView.performErase`, `MacSettingsView.performErase`, and the
    /// "erase local data" recovery action on both root views), so a factory reset was leaving the
    /// user's schedules describing themselves on the lock screen of a wiped device.
    ///
    /// Delivered reminders are cleared on **every** `sync`, not only the Privacy-Mode one. `sync`
    /// is never called speculatively: its callers are the three `.onChange` observers (schedule
    /// set, display currency, Privacy Mode), the save/toggle handlers in the two Cash Flow views,
    /// and `processRecurringTransactions` — which since WC-L1 only re-syncs when an occurrence was
    /// actually generated. Every one of those means the banner on screen has stopped describing the
    /// data: the schedule was edited or deleted, the amount is now denominated in a different
    /// currency, or the occurrence has already been recorded and the reminder is spent. A stale
    /// banner is wrong whether or not Privacy Mode is on, so this deliberately does not branch on
    /// `showDetails` — the narrower "clear delivered only when hiding details" would have left the
    /// staleness bug standing for everyone else and made correctness depend on an unrelated flag.
    private func clearScheduledReminders() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let identifiers = (pending + delivered).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notificationIdentifier(for scheduleID: UUID) -> String {
        "\(identifierPrefix)\(scheduleID.uuidString)"
    }
}
