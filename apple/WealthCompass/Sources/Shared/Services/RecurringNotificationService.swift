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
            // Nothing stands between the builder and `center.add` — no local to write to after the
            // fact. That is deliberate; `request(for:…)` says why.
            try? await center.add(Self.request(
                for: schedule,
                convertedAmount: convertedAmounts[schedule.id],
                currencyCode: currencyCode,
                showDetails: showDetails,
                appLanguage: appLanguage,
                identifierPrefix: identifierPrefix
            ))
        }
    }

    /// Everything one schedule hands to the notification centre — payload, identifier and trigger —
    /// assembled into the exact request `sync` adds.
    ///
    /// It returns the `UNNotificationRequest` rather than the content, and that is the whole point.
    /// `UNMutableNotificationContent` is a **class**. While this handed one back, `sync` could keep
    /// writing to that object after the builder was finished with it, and a test asserting on the
    /// builder's return value would never see it. Measured, not supposed: injecting
    ///
    ///     content.threadIdentifier = schedule.category
    ///     content.subtitle = schedule.description
    ///
    /// into `sync` immediately after the old `content(...)` call left the suite at 297 passed / 0
    /// failed — and those are precisely the two fields the lock-screen test names as ones that
    /// "would each carry the same disclosure if a later change started setting them from
    /// `schedule`". The refactor that made the payload testable is what let production diverge from
    /// what the test asserts.
    ///
    /// `UNNotificationRequest.content` is an immutable `UNNotificationContent`, copied at
    /// construction, so once the request exists the payload is frozen. Asserting on the request is
    /// therefore asserting on what the lock screen will draw, wherever in the pipeline a field was
    /// set — and it reaches the `identifier` and the `trigger` too, neither of which the old shape
    /// exposed to a test at all.
    ///
    /// `nonisolated` because `sync` returns early unless `UNUserNotificationCenter` reports an
    /// authorization the test host is never granted (measured: `authorizationStatus.rawValue == 0`,
    /// and `center.add` retains 0 of 5 requests), so nothing below that guard is reachable from a
    /// test. This reads only its arguments.
    ///
    /// With `showDetails` false **nothing the lock screen renders varies with the schedule**: title,
    /// body and every other drawn field are the same constants whichever schedule this is. Two
    /// things do still vary with it and neither is drawn — the `identifier`, which is the schedule's
    /// UUID behind the platform prefix and is what `cancel(scheduleID:)` names, and the `trigger`,
    /// which fires at the due moment, something a reminder cannot be without. An earlier version of
    /// this comment claimed "no property of `schedule` is read", which the `userInfo` line below
    /// contradicts; what is true is the narrower and sufficient statement above.
    nonisolated static func request(
        for schedule: RecurringTransaction,
        convertedAmount: Decimal?,
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?,
        identifierPrefix: String
    ) -> UNNotificationRequest {
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
        return UNNotificationRequest(
            identifier: notificationIdentifier(for: schedule.id, prefix: identifierPrefix),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        )
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

    /// The one spelling of a reminder's identifier, so the builder and `cancel(scheduleID:)` cannot
    /// drift apart — `cancel` can only reach a banner it can name exactly.
    nonisolated static func notificationIdentifier(for scheduleID: UUID, prefix: String) -> String {
        "\(prefix)\(scheduleID.uuidString)"
    }

    private func notificationIdentifier(for scheduleID: UUID) -> String {
        Self.notificationIdentifier(for: scheduleID, prefix: identifierPrefix)
    }
}
