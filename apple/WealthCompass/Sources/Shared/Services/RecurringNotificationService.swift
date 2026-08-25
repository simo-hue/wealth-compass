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
            appLanguage: appLanguage,
            now: now
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
    ///
    /// The comparison used to be `identifier`/`title`/`subtitle`/`body` and nothing else, which
    /// left a gap: a later edit setting `threadIdentifier` or `categoryIdentifier` from a schedule
    /// would put the schedule's category on the lock screen — `threadIdentifier` is drawn as the
    /// group header — and the teardown could not have noticed the category changing underneath it.
    /// The sibling lock-screen test archives the *whole* `UNNotificationContent`
    /// (`testPrivacyModeStopsTheRecurringReminderDescribingTheSchedule`), so it would see such a
    /// field; this could not. Those two are now in.
    ///
    /// Three of `UNNotificationContent`'s remaining drawn fields are deliberately left out, and the
    /// reason is the same in each case — a delivered banner is not the request that produced it,
    /// and comparing a field the system rewrites on delivery would mark **every** banner stale,
    /// which is precisely the failure this teardown exists to avoid:
    ///
    /// - `attachments`: the system copies the file into its own store and hands back a different
    ///   `URL`, so a delivered attachment can never compare equal to a freshly built one. The
    ///   lock-screen test asserts `attachments.count == 0` under Privacy Mode instead.
    /// - `sound`: not drawn, and `UNNotificationSound` has no documented value equality — two
    ///   `.default` instances are two objects.
    /// - `userInfo`: app-private, never rendered, and it carries the schedule's UUID by design; the
    ///   lock-screen test clears it before archiving for exactly that reason.
    ///
    /// `badge` **is** compared, and is a `String`-free exception to the "text only" reading of this
    /// type on purpose: a badge count is the multiplicity disclosure `5265c96` closed for banners,
    /// one surface over. Nothing sets it today.
    ///
    /// None of this is observable from the test host, so what pins it is
    /// `testTheDeliveredComparisonSeesEveryFieldAScheduleCouldReach`, which moves one field at a
    /// time and asserts the verdict — for `sound` and `userInfo` as well as for the six that are
    /// compared, so those exclusions are recorded decisions rather than oversights. `attachments`
    /// is the one exclusion not probed there, because building a `UNNotificationAttachment` needs a
    /// real file on disk and a unit test that can fail on file I/O is a worse trade than the
    /// assertion is worth; the lock-screen test pins it directly instead, with
    /// `attachments.count == 0` under Privacy Mode.
    struct DeliveredReminder: Equatable {
        let identifier: String
        let title: String
        let subtitle: String
        let body: String
        let threadIdentifier: String
        let categoryIdentifier: String
        let badge: Int?

        init(
            identifier: String,
            title: String,
            subtitle: String = "",
            body: String,
            threadIdentifier: String = "",
            categoryIdentifier: String = "",
            badge: Int? = nil
        ) {
            self.identifier = identifier
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.threadIdentifier = threadIdentifier
            self.categoryIdentifier = categoryIdentifier
            self.badge = badge
        }

        init(_ content: UNNotificationContent, identifier: String) {
            self.init(
                identifier: identifier,
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                threadIdentifier: content.threadIdentifier,
                categoryIdentifier: content.categoryIdentifier,
                badge: content.badge?.intValue
            )
        }

        init(_ request: UNNotificationRequest) {
            self.init(request.content, identifier: request.identifier)
        }

        init(_ notification: UNNotification) {
            self.init(notification.request)
        }

        /// This reminder as it would read if it were filed elsewhere: everything drawn, nothing
        /// about where it sits. Rebuilt through the memberwise `init` rather than by listing the
        /// fields to compare, so a field added above is carried here without a second edit.
        func filed(as identifier: String) -> DeliveredReminder {
            DeliveredReminder(
                identifier: identifier,
                title: title,
                subtitle: subtitle,
                body: body,
                threadIdentifier: threadIdentifier,
                categoryIdentifier: categoryIdentifier,
                badge: badge
            )
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
    /// **Spent banners are kept, on both branches.** Once `processDueRecurringTransactions` has
    /// recorded the occurrence and advanced `nextDueDate`, the reminder has done its job and has not
    /// necessarily been read. On the detailed branch that falls out for free: the identifier is the
    /// bare schedule UUID and the text is what the next reminder will say too, so a spent banner is
    /// indistinguishable from an accurate one and survives. On the hidden branch it did **not**, and
    /// the difference was a live bug rather than a wrinkle. The coalesced identifier is derived from
    /// the fire moment, so advancing `nextDueDate` renames it: nothing rebuilds
    /// `<prefix>due-<Y-M-D-H-M>` any more, the banner reads as one nothing stands behind, and the
    /// app takes down an unread reminder about thirty seconds after it fired — via the timer, or at
    /// once through `didReceive` → `.recurringTransactionNotificationReceived`. And the advance is
    /// not an edge: it is what the 30-second timer does to every schedule the moment it comes due.
    /// Privacy Mode is the one mode where the banner is the user's only trace that anything fired,
    /// so this was worst exactly where it mattered most.
    ///
    /// So a delivered banner with no rebuilt entry under its identifier is kept when all three of
    /// these hold, and taken down otherwise:
    ///
    /// - Privacy Mode is still on. A hidden banner outliving the toggle is `73e3b22`'s other
    ///   direction, already pinned, and turning details back on is the user saying they want to see
    ///   what is due.
    /// - Its identifier is this platform's coalesced form and names a moment at or before `now` —
    ///   *spent*. This is the whole discriminator between an advance and a deletion, which the
    ///   schedule set alone cannot tell apart: both leave no live schedule at that moment. A
    ///   coalesced banner whose moment is still ahead has no business being on the lock screen at
    ///   all, and goes.
    /// - It says exactly what the hidden branch says. The hidden payload names no schedule, so it
    ///   cannot have gone stale and cannot become a disclosure — but that argument only holds while
    ///   the payload really is that payload, which is what the comparison checks. A banner filed
    ///   under `due-…` carrying a *detailed* payload is a disclosure, and is taken down.
    ///
    /// The one thing this concedes is a spent hidden banner whose schedule was deleted after it
    /// fired: it stays until the user swipes it, or until the erase path takes it. That is the same
    /// trade the detailed branch already makes for the advance, on a banner that says two constants.
    ///
    /// The comparison stays sensitive to the *figure*, and that is a decision rather than an
    /// oversight. `convertedAmounts` is computed by the caller from the current exchange rates, so a
    /// rate refresh alone re-renders a foreign-currency schedule's body and drops an otherwise
    /// untouched detailed banner on the next speculative `sync` — not reachable today, since every
    /// one of the six call sites passes a conversion total over the same `schedules`, but a rate
    /// change is enough to reach it. It is left sensitive because this function's whole question is
    /// "does this banner still say what the app would say", and a money figure is the part of a
    /// reminder a reader acts on; a banner quoting a number the app no longer agrees with is worse
    /// than a reminder the reader has to fetch from the app. Making it insensitive is not a matter
    /// of relaxing a comparison either — the two cases that must be told apart, a rate drift and the
    /// user editing the amount, are identical here, so telling them apart means carrying the rate a
    /// banner was delivered under, which is new persisted state for a banner whose whole content is
    /// one sentence. Under Privacy Mode the question does not arise: the hidden branch never reads
    /// `convertedAmounts`.
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
        identifierPrefix: String,
        now: Date = Date()
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
        // Built once, and only used on the branch that needs it: what a hidden banner says, with no
        // identifier attached, so `filed(as:)` can ask "does this say the same thing" without the
        // filing getting in the way.
        let hidden = DeliveredReminder(hiddenContent(appLanguage: appLanguage), identifier: "")
        return ours.filter { delivered in
            if let rebuilt = accurate[delivered.identifier] { return rebuilt != delivered }
            guard !showDetails,
                  let moment = coalescedMoment(of: delivered.identifier, prefix: identifierPrefix),
                  moment <= now,
                  delivered.filed(as: "") == hidden
            else { return true }
            return false
        }.map(\.identifier)
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
        let stamp = Self.coalescedStampFields
            .map { due[keyPath: $0].map(String.init) ?? "x" }
            .joined(separator: "-")
        return "\(prefix)due-\(stamp)"
    }

    /// The moment a coalesced identifier names, or `nil` if it does not name one.
    ///
    /// The inverse of `coalescedIdentifier(dueAt:prefix:)`, written next to it and over the same
    /// field list so the two cannot drift. Both stay `private`: what a test can reach is the
    /// verdict `staleDelivered` reaches with them, and
    /// `testASpentPrivacyModeBannerSurvivesItsScheduleAdvancing` exercises the round trip that way —
    /// a past moment is kept, the same moment in the future is not, and a `due-` identifier whose
    /// stamp does not parse is not.
    ///
    /// `staleDelivered` needs this because *spent* is the only thing that separates a schedule
    /// advancing past its due moment from a schedule being deleted: neither leaves a live schedule
    /// at that moment, and the identifier is the only place the moment survives. Anything that does
    /// not parse cleanly — a foreign identifier, a per-schedule UUID, a component written as `x`
    /// because `fireComponents` handed back a nil — returns `nil` and is judged the old way, which
    /// is the conservative direction.
    private nonisolated static func coalescedMoment(of identifier: String, prefix: String) -> Date? {
        let marker = "\(prefix)due-"
        guard identifier.hasPrefix(marker) else { return nil }
        let stamp = identifier.dropFirst(marker.count).split(separator: "-", omittingEmptySubsequences: false)
        guard stamp.count == Self.coalescedStampFields.count else { return nil }
        var components = DateComponents()
        for (field, text) in zip(Self.coalescedStampFields, stamp) {
            guard let value = Int(text) else { return nil }
            components[keyPath: field] = value
        }
        return Calendar.current.date(from: components)
    }

    /// The date components a coalesced identifier stamps, in the order it stamps them. One list,
    /// read by the writer and the reader, so neither can gain or lose a field alone.
    private nonisolated static let coalescedStampFields: [WritableKeyPath<DateComponents, Int?>] = [
        \.year, \.month, \.day, \.hour, \.minute,
    ]

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
        let identifiers = Self.everyReminder(
            pending: await center.pendingNotificationRequests().map(\.identifier),
            delivered: await center.deliveredNotifications().map(\.request.identifier),
            identifierPrefix: identifierPrefix
        )
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Which of the notification centre's identifiers this service owns — the erase path's whole
    /// decision, extracted so it can be tested as a value rather than described in a lint.
    ///
    /// The guard this replaces was that `clearScheduledReminders`'s body contained no literal
    /// `staleDelivered`, which is a check about spelling. It passes verbatim against a teardown that
    /// caches the schedules in `sync` and keeps the banners still backed by them, under any name at
    /// all — and that is the regression it claims to guard: after "erase local data" there are no
    /// schedules, so a banner kept is one describing data the user just wiped off the device.
    ///
    /// Stated as a function, the property is structural rather than textual: erase names every
    /// reminder under this prefix, from the two queues and **nothing else**. There is no parameter
    /// through which a schedule could arrive, and `nonisolated static` means no actor state can be
    /// read either, so making this consult the data takes a signature change that its test will not
    /// compile against. `testTheErasePathNamesEveryReminderItOwns` asserts the values;
    /// `testRecurringReminderTeardownClearsDeliveredBannersToo` asserts that the erase path still
    /// hands this function's result *straight* to both removals, with nothing filtered out in
    /// between.
    nonisolated static func everyReminder(
        pending: [String], delivered: [String], identifierPrefix: String
    ) -> [String] {
        (pending + delivered).filter { $0.hasPrefix(identifierPrefix) }
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
        appLanguage: String?,
        now: Date
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
            identifierPrefix: identifierPrefix,
            now: now
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
