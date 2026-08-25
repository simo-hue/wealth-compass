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

    /// iOS keeps at most 64 pending local notification requests per app and silently drops the
    /// rest, so this posts at most 60 and leaves headroom.
    ///
    /// It caps the **requests**, not the schedules. Under Privacy Mode the two are no longer the
    /// same number, and spending the budget on duplicate banners for today rather than on the dates
    /// after them would be the wrong trade.
    static let pendingRequestLimit = 60

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
        // Read the in-app language once, not once per schedule, and source the key from the single
        // source of truth on AppSettings rather than a brittle literal (WC-L31).
        let appLanguage = UserDefaults.standard.string(forKey: AppSettings.appLanguageDefaultsKey)

        await clearReminders(
            supersededBy: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: currencyCode,
            showDetails: showDetails,
            appLanguage: appLanguage
        )

        guard Self.isAuthorized(await center.notificationSettings().authorizationStatus) else {
            return
        }

        // Not sorted here: `requests(for:)` orders by due date itself, because the cap it applies
        // is what makes the order load-bearing and the two must not be able to drift apart.
        let upcoming = schedules.filter { schedule in
            schedule.isActive
                && !schedule.isCompleted
                && schedule.notificationsEnabled
                && schedule.nextDueDate > now
                && (schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true)
        }

        // `requests(for:…)` is the **only** source of anything this actor hands to the notification
        // centre, on both branches of Privacy Mode, and nothing stands between it and `center.add` —
        // no local to write to after the fact. That is what makes asserting on its return value the
        // same thing as asserting on what the lock screen will draw;
        // `testEveryReminderReachingTheNotificationCentreComesFromOneBuilder` pins it.
        for request in Self.requests(
            for: upcoming,
            convertedAmounts: convertedAmounts,
            currencyCode: currencyCode,
            showDetails: showDetails,
            appLanguage: appLanguage,
            identifierPrefix: identifierPrefix
        ) {
            try? await center.add(request)
        }
    }

    /// The whole set of requests one `sync` hands to the notification centre.
    ///
    /// Built as a set rather than one schedule at a time because under Privacy Mode the set is not
    /// a function of any single schedule. With the details hidden every reminder is the same two
    /// constants, so N schedules due at the same moment posted the same banner N times, and the
    /// banners said nothing that could tell them apart: **the multiplicity was the disclosure**. A
    /// bystander could not read what was due, but could count how much of it there was.
    ///
    /// WC-L5 makes that the ordinary case and not a coincidence. It pins every date-only or
    /// imported schedule's 00:00 to 09:00 local, so "due in the same minute" is really "due on the
    /// same day" — which is exactly what importing a JSON backup or a broker statement produces.
    /// Under Privacy Mode the banner count was the schedule count.
    ///
    /// So the hidden branch coalesces by fire time: one reminder per moment something is due. Not
    /// one reminder overall — a reminder that did not fire when the thing was due would not be a
    /// reminder — and not one per day either, because a schedule with a real time of day keeps it.
    /// Only the exact duplicates collapse.
    ///
    /// Non-privacy behaviour is untouched, deliberately: one request per schedule, identified by
    /// its UUID, in due-date order, capped the same way. The hidden branch never even looks at
    /// `convertedAmounts`, which is the structural version of the same promise.
    ///
    /// The due-date sort happens **here** rather than in `sync`. It used to be the caller's, and the
    /// doc comment promised "in due-date order" while this function did nothing to produce it: the
    /// order only held because `sync` happened to sort one line earlier. Since the order decides
    /// *which* schedules survive `pendingRequestLimit`, a second caller passing an unsorted array —
    /// or a future edit dropping `sync`'s sort — would have silently truncated an arbitrary 60 of
    /// them and dropped real reminders. The guarantee now lives with the function that documents it.
    ///
    /// - Parameter limit: how many requests may be produced. Defaults to the pending-request budget,
    ///   which is what `sync` needs. `staleDelivered` passes `.max`: it is asking what each banner
    ///   *would* say rather than what will be posted, and a cap there would read the 61st schedule's
    ///   still-accurate banner as one nothing stands behind.
    nonisolated static func requests(
        for schedules: [RecurringTransaction],
        convertedAmounts: [UUID: Decimal],
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?,
        identifierPrefix: String,
        limit: Int = pendingRequestLimit
    ) -> [UNNotificationRequest] {
        let ordered = schedules.sorted { $0.nextDueDate < $1.nextDueDate }

        guard !showDetails else {
            return ordered.prefix(limit).map { schedule in
                request(
                    for: schedule,
                    convertedAmount: convertedAmounts[schedule.id],
                    currencyCode: currencyCode,
                    showDetails: true,
                    appLanguage: appLanguage,
                    identifierPrefix: identifierPrefix
                )
            }
        }

        var posted: Set<String> = []
        var coalesced: [UNNotificationRequest] = []
        for schedule in ordered {
            let due = fireComponents(for: schedule.nextDueDate)
            let identifier = coalescedIdentifier(dueAt: due, prefix: identifierPrefix)
            guard posted.insert(identifier).inserted else { continue }
            coalesced.append(coalescedRequest(
                dueAt: due, identifier: identifier, appLanguage: appLanguage
            ))
            if coalesced.count == limit { break }
        }
        return coalesced
    }

    /// A banner already on the lock screen, reduced to what deciding its fate needs: how it is
    /// filed, and what it says.
    struct DeliveredReminder: Equatable {
        let identifier: String
        let title: String
        let subtitle: String
        let body: String

        init(identifier: String, title: String, subtitle: String = "", body: String) {
            self.identifier = identifier
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }

        init(_ request: UNNotificationRequest) {
            self.init(
                identifier: request.identifier,
                title: request.content.title,
                subtitle: request.content.subtitle,
                body: request.content.body
            )
        }

        init(_ notification: UNNotification) {
            self.init(notification.request)
        }
    }

    /// Which delivered banners have stopped describing the data, given the schedules as they are now.
    ///
    /// `73e3b22` fixed a real bug — a fired reminder survived turning Privacy Mode on, and survived
    /// a factory reset — with an all-or-nothing sweep: every delivered banner carrying this
    /// platform's prefix, gone, on every `sync`. Its justification was that "`sync` is never called
    /// speculatively", so every call already meant the banner had stopped being accurate. That is
    /// not true, and the cost is that **editing one schedule dismissed the unread banner of every
    /// other one**: add a "Gym" reminder at 20:00 and an unread "Rent: €1.450,00" from 09:00
    /// disappears. Three paths reach `sync` with nothing about the existing banners changed:
    ///
    /// - A silent CloudKit push while the phone is locked. `FinanceStore.applyRemote` assigns
    ///   `data = updatedData`, and `RecurringTransaction`'s synthesised `==` covers every stored
    ///   property including `updatedAt` and `nextDueDate` — so a remote edit to an unrelated
    ///   schedule, or a bare reorder from `sortedForStorage()`, fires
    ///   `.onChange(of: finance.data.recurringTransactions)` and re-syncs. That fires *exactly* when
    ///   a banner is sitting unread on a locked screen.
    /// - `processDueRecurringTransactions` returning 0 while still writing schedules back. The
    ///   dedup advance, the catch-up fast-forward, the pathological-backdate deactivation and the
    ///   endDate deactivation all mutate the array without generating an occurrence, so WC-L1's
    ///   `guard insertedCount > 0` never sees them — the array mutation fires `.onChange` by itself.
    ///   Driven by the 30-second timer.
    /// - Backup import, unconditionally, on both platforms.
    ///
    /// So the question a teardown has to answer is not "was `sync` called" but "does this banner
    /// still describe its schedule". The answer here is deliberately literal: rebuild the reminder
    /// every currently-live schedule *would* get, and keep a delivered banner if and only if one of
    /// those is filed under the same identifier **and says the same thing**. A banner is taken down
    /// when its schedule is gone, completed, deactivated or has its reminders switched off (no entry
    /// under that identifier), when Privacy Mode has flipped (the hidden branch files under
    /// `due-<moment>` and the detailed one under the schedule's UUID, so neither can match the
    /// other), or when the amount, currency, category or language would now render differently. An
    /// unrelated edit changes none of those, and the banner stays.
    ///
    /// "Live" here drops the `nextDueDate > now` clause `sync` applies to the *pending* set, and has
    /// to: a delivered banner is by definition one whose fire time has passed, so filtering to
    /// future dues would find no schedule behind any of them and take down every one.
    ///
    /// One edge is knowingly left conservative. Once `processDueRecurringTransactions` has recorded
    /// the occurrence and advanced `nextDueDate`, a detailed banner is arguably spent, but its
    /// identifier is the bare schedule UUID and its text is what the next reminder will say too, so
    /// it is indistinguishable from an accurate one here and is kept. Keeping a spent banner is the
    /// failure this is trading against dismissing a live one, and it is the smaller of the two.
    ///
    /// Pure, and takes the delivered banners as plain values, because none of this is observable
    /// from the test host: `authorizationStatus.rawValue == 0`, `center.add` retains 0 of 5
    /// requests, and `deliveredNotifications()` is always empty. What a test can check is the
    /// decision, not the queue.
    nonisolated static func staleDelivered(
        _ delivered: [DeliveredReminder],
        schedules: [RecurringTransaction],
        convertedAmounts: [UUID: Decimal],
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?,
        identifierPrefix: String
    ) -> [String] {
        // The overwhelmingly common case, and the one the 30-second timer drives: nothing has been
        // delivered, so there is nothing to judge. Rebuilding every live schedule's reminder to find
        // that out would be the one place this teardown does more work than the prefix sweep did.
        let ours = delivered.filter { $0.identifier.hasPrefix(identifierPrefix) }
        guard !ours.isEmpty else { return [] }

        let live = schedules.filter { schedule in
            schedule.isActive
                && !schedule.isCompleted
                && schedule.notificationsEnabled
                && (schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true)
        }
        let accurate = Dictionary(
            requests(
                for: live,
                convertedAmounts: convertedAmounts,
                currencyCode: currencyCode,
                showDetails: showDetails,
                appLanguage: appLanguage,
                identifierPrefix: identifierPrefix,
                limit: .max
            ).map(DeliveredReminder.init).map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ours.filter { accurate[$0.identifier] != $0 }.map(\.identifier)
    }

    /// Everything one schedule hands to the notification centre — payload, identifier and trigger —
    /// assembled into a request `requests(for:…)` returns.
    ///
    /// **In production this is only ever reached with `showDetails: true`.** `requests(for:…)` sends
    /// the Privacy Mode case to `coalescedRequest` instead, which reaches `hiddenContent` without
    /// passing through here. That is why the lock-screen test asserts on `requests(for:…)` and not
    /// on this: a test pinned to this function covers the branch that is allowed to describe the
    /// schedule and says nothing at all about the branch that is not. `866b3c7` pinned this
    /// function; `5265c96` moved the privacy path off it one commit later, and the suite stayed at
    /// 302 passed / 0 failed with `subtitle`/`threadIdentifier` set from the schedule inside
    /// `coalescedRequest`. `showDetails: false` still works here and is still tested, because
    /// `cancel(scheduleID:)`, the identifier and the trigger are all per-schedule facts.
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
        let payload = Self.content(
            for: schedule,
            convertedAmount: convertedAmount,
            currencyCode: currencyCode,
            showDetails: showDetails,
            appLanguage: appLanguage
        )
        return UNNotificationRequest(
            identifier: notificationIdentifier(for: schedule.id, prefix: identifierPrefix),
            content: payload,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: fireComponents(for: schedule.nextDueDate), repeats: false
            )
        )
    }

    /// The one reminder Privacy Mode posts for everything due at a given moment.
    ///
    /// The payload comes from the same `content(for:…)` the per-schedule path uses, with the same
    /// `showDetails: false` branch, so the two can never grow apart — and that branch reads nothing
    /// from a schedule, which is why this function has none to pass it. `userInfo` is the one field
    /// the per-schedule request carries that this cannot: it stands for N schedules and naming one
    /// of them would be arbitrary. Nothing reads `userInfo` today — both delegate callbacks post
    /// `.recurringTransactionNotificationReceived` with no object and re-derive the work from the
    /// store — so leaving it out changes no behaviour; it removes a trap for whoever adds a tap
    /// handler later.
    private nonisolated static func coalescedRequest(
        dueAt components: DateComponents,
        identifier: String,
        appLanguage: String?
    ) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: hiddenContent(appLanguage: appLanguage),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    /// The payload half of a reminder. `private`: `request(for:…)` seals it into an immutable
    /// request on the very next line, and everything outside this type asserts on that request.
    private nonisolated static func content(
        for schedule: RecurringTransaction,
        convertedAmount: Decimal?,
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?
    ) -> UNMutableNotificationContent {
        let content: UNMutableNotificationContent
        if showDetails {
            content = UNMutableNotificationContent()
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
            content.sound = .default
        } else {
            content = hiddenContent(appLanguage: appLanguage)
        }
        // Everything else `UNMutableNotificationContent` can put on a lock screen is either never
        // set here or cannot vary with the schedule: `subtitle`, `threadIdentifier`,
        // `categoryIdentifier`, `badge` and `attachments` are all left at their defaults, and
        // `sound` is `.default` on both branches. `userInfo` carries the schedule's UUID: app-private
        // payload, never rendered, and it names nothing. It was put there for a tap handler that
        // does not exist — `AppNotificationDelegate` and `MacAppDelegate` both answer `willPresent`
        // and `didReceive` by posting `.recurringTransactionNotificationReceived` with `object: nil`
        // and re-deriving the work from the store, so nothing reads this key today.
        content.userInfo = ["recurringTransactionID": schedule.id.uuidString]
        return content
    }

    /// What a reminder says with Privacy Mode on: two constants, and no argument that could carry a
    /// schedule into them. The title has to move with the body — `Recurring %@ due` names the
    /// *type*, Expense or Income, independently of anything the body says, so redacting only the
    /// body left half the disclosure standing on a surface that needs no unlock.
    private nonisolated static func hiddenContent(appLanguage: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.string("Reminder", appLanguage: appLanguage)
        content.body = AppLocalization.string("Open Wealth Compass Tracker to review.", appLanguage: appLanguage)
        content.sound = .default
        return content
    }

    /// When a reminder fires.
    ///
    /// WC-L5: date-only / imported schedules carry a midnight time, which would fire the reminder
    /// at 00:00. Pin those to 9:00 local; schedules with a real time keep it. Shared by the
    /// per-schedule and the coalesced paths so they cannot disagree about which moment is which —
    /// coalescing is *by* this value.
    nonisolated static func fireComponents(for dueDate: Date) -> DateComponents {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        if (components.hour ?? 0) == 0 && (components.minute ?? 0) == 0 {
            components.hour = 9
            components.minute = 0
        }
        return components
    }

    /// The identifier a coalesced reminder is filed under: the fire time, not a schedule.
    ///
    /// A pure function of the moment, so re-running `sync` over an unchanged schedule set produces
    /// the same request set. `due-` cannot collide with the per-schedule form, which is a UUID
    /// string.
    private nonisolated static func coalescedIdentifier(dueAt due: DateComponents, prefix: String) -> String {
        let stamp = [due.year, due.month, due.day, due.hour, due.minute]
            .map { $0.map(String.init) ?? "x" }
            .joined(separator: "-")
        return "\(prefix)due-\(stamp)"
    }

    /// Drops one schedule's reminder, pending or already delivered.
    ///
    /// Under Privacy Mode there is no such reminder to name: the banner is coalesced and filed under
    /// its fire time, so this finds nothing. That is covered, and by the stronger path — all four
    /// callers (`CashFlowView` :688 and :725, `MacCashFlowView` :1022 and :1061) mutate
    /// `finance.data.recurringTransactions` immediately before calling it, which fires
    /// `.onChange(of:)` at `ContentView.swift:110` / `MacRootView.swift:119` and re-runs `sync`.
    /// `sync` tears down every pending request under this prefix, and every *delivered* banner that
    /// no live schedule still stands behind — a deleted schedule leaves no entry under its
    /// identifier, and a coalesced banner outlives the deletion only while some other schedule is
    /// still due at that same moment, which is exactly when it should. The same is true of the
    /// per-schedule identifier, which is why this method's removals are belt-and-braces rather than
    /// load-bearing.
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
    /// This is now the **erase** path only — `cancelAll`, and nothing else. It stays all-or-nothing
    /// deliberately: "erase local data" means the schedules are gone, so no banner describing one
    /// can still be accurate, and there is nothing left to compare against.
    ///
    /// `sync` used to call this too, which is the bug `clearReminders(supersededBy:…)` fixes; its
    /// doc comment has the argument. The claim that used to stand here — that `sync` "is never
    /// called speculatively", with a caller list to match — was wrong twice over. The list omitted
    /// backup import (`SettingsView.swift:665`, `MacSettingsView.swift:826`, both unconditional),
    /// and WC-L1's `guard insertedCount > 0` does not stop the timer path from re-syncing, because
    /// the schedule write-back inside `processDueRecurringTransactions` fires
    /// `.onChange(of: finance.data.recurringTransactions)` on its own.
    private func clearScheduledReminders() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let identifiers = (pending + delivered).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// The teardown half of one `sync`: every pending request this service owns, and every delivered
    /// banner that the schedules as they now stand no longer support.
    ///
    /// Pending is unconditional because the whole pending set is rebuilt three lines later, so
    /// keeping one would save nothing and risk keeping a stale one. Delivered is not: a banner
    /// already on the lock screen is not going to be re-posted, and taking down one that still
    /// describes its schedule is a lost reminder. `staleDelivered` is where that judgement lives.
    ///
    /// Two awaits, the same two `clearScheduledReminders` makes — `sync` is reentrant with a
    /// pre-existing read → remove → await → add window and this does not widen it further.
    private func clearReminders(
        supersededBy schedules: [RecurringTransaction],
        convertedAmounts: [UUID: Decimal],
        currencyCode: String,
        showDetails: Bool,
        appLanguage: String?
    ) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let delivered = await center.deliveredNotifications().map(DeliveredReminder.init)
        center.removeDeliveredNotifications(withIdentifiers: Self.staleDelivered(
            delivered,
            schedules: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: currencyCode,
            showDetails: showDetails,
            appLanguage: appLanguage,
            identifierPrefix: identifierPrefix
        ))
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
