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

    /// The schedules `sync` still owes a pending reminder for, at the instant `now`.
    ///
    /// Pure and `static` so the eligibility rule can be asserted directly: `sync` itself returns
    /// early behind an authorization guard the test host never clears, so nothing downstream of it
    /// is observable from a test.
    ///
    /// The clause that matters is the last one. `clearReminders(supersededBy:)` has already removed
    /// every pending request under our prefix by the time this runs, so a schedule this filter drops
    /// is a schedule whose reminder is *deleted* rather than re-scheduled — there is no "leave the
    /// existing one alone" branch. It therefore has to be asked about the moment the trigger will
    /// actually fire, not about the due date: WC-L5 pins a midnight due time to 09:00 local
    /// (`fireMoment`), which is also what `coalescedIdentifier` keys on.
    nonisolated static func schedulesStillToFire(
        _ schedules: [RecurringTransaction],
        now: Date
    ) -> [RecurringTransaction] {
        schedules.filter { schedule in
            schedule.isActive
                && !schedule.isCompleted
                && schedule.notificationsEnabled
                && fireMoment(for: schedule.nextDueDate) > now
                && (schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true)
        }
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
        let upcoming = Self.schedulesStillToFire(schedules, now: now)

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
            let identifier = coalescedIdentifier(
                at: fireMoment(for: schedule.nextDueDate), prefix: identifierPrefix
            )
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
    /// What is in and what is out follows **one** rule, and an earlier version of this comment
    /// stated it too broadly — broadly enough that the type appeared to contradict itself once
    /// `81c2fca` added three more fields. It is *not* "leave out anything the system might rewrite
    /// on delivery". That would exclude `title`, `subtitle` and `body`, which are the entire point
    /// of the comparison, so it cannot be the rule and never was. This teardown irreducibly assumes
    /// what `UserNotifications` documents: `UNNotification.request` is the archived request, so the
    /// fields of its content come back as they were submitted. Reading `userInfo` straight off
    /// `deliveredNotifications()` is that same assumption, and it is a relied-on pattern.
    ///
    /// The rule is the narrower one: **compare every field the lock screen draws whose type has
    /// value equality and whose value the system does not replace with one of its own.** Three
    /// fields fail it, each for a reason particular to that field, and no one of those reasons
    /// generalises to another:
    ///
    /// - `attachments`: not a round-trip question but a *value* one. The system copies the file into
    ///   its own store and hands back a different `URL`, so a delivered attachment can never compare
    ///   equal to a freshly built one. The lock-screen test asserts `attachments.count == 0` under
    ///   Privacy Mode instead.
    /// - `sound`: a *type* question. `UNNotificationSound` has no documented value equality — two
    ///   `.default` instances are two objects — so comparing it would compare identities. It is not
    ///   drawn either.
    /// - `userInfo`: `[AnyHashable: Any]` is not `Equatable` at all, so it could not join an
    ///   `Equatable` struct without a hand-written comparison; it is app-private, never rendered,
    ///   and it carries the schedule's UUID by design. The lock-screen test clears it before
    ///   archiving for exactly that reason.
    ///
    /// `threadIdentifier`, `categoryIdentifier` and `badge` pass that test — plain `String` and
    /// `Int?`, read off the same archived object `title` is read off — so they are in. `81c2fca`
    /// added them against a real gap: an edit setting `content.threadIdentifier = schedule.category`
    /// draws the category as the notification group's header, and the comparison could not have seen
    /// it change. `badge` is in for the same reason one surface over — a badge count is the
    /// multiplicity disclosure `5265c96` closed for banners.
    ///
    /// The cost if the assumption is wrong is worth stating plainly, because it is the failure this
    /// teardown exists to avoid: a field the system does not return verbatim marks **every**
    /// delivered banner stale, and the detailed branch is then swept on every `sync` — `73e3b22`'s
    /// over-sweep. Dropping these three would not buy protection from that, only a smaller share of
    /// it, because `title`, `subtitle` and `body` carry the identical assumption and cannot be
    /// dropped without dropping the teardown. So the three stay, and the assumption is stated once,
    /// here, instead of being half-denied in a list of exclusions.
    ///
    /// Nothing sets the three today. That is checked rather than claimed —
    /// `testTheDeliveredComparisonSeesEveryFieldAScheduleCouldReach` asserts the builder leaves all
    /// three at their defaults on both branches — so an edit that starts pouring a schedule into one
    /// of them fails there and is sent back to re-read this.
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
    /// under that identifier) — that is the detailed branch; the hidden branch keeps a *spent*
    /// banner through all four, and the five-case list further down is what that costs — when
    /// Privacy Mode has flipped (the hidden branch files under
    /// `due-<moment>` and the detailed one under the schedule's UUID, so neither can match the
    /// other), or when the amount, currency, category or language would now render differently. An
    /// unrelated edit changes none of those, and the banner stays.
    ///
    /// "Live" here drops the still-to-fire clause `sync` applies to the *pending* set
    /// (`schedulesStillToFire`), and has to: a delivered banner is by definition one whose fire time
    /// has passed, so filtering to future fire moments would find no schedule behind any of them and
    /// take down every one.
    ///
    /// **Spent banners are kept, on both branches.** Once `processDueRecurringTransactions` has
    /// recorded the occurrence and advanced `nextDueDate`, the reminder has done its job and has not
    /// necessarily been read. On the detailed branch that falls out for free: the identifier is the
    /// bare schedule UUID and the text is what the next reminder will say too, so a spent banner is
    /// indistinguishable from an accurate one and survives. On the hidden branch it did **not**, and
    /// the difference was a live bug rather than a wrinkle. The coalesced identifier is derived from
    /// the fire moment, so advancing `nextDueDate` renames it: nothing rebuilds
    /// `<prefix>due-<moment>` any more, the banner reads as one nothing stands behind, and the
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
    /// What this concedes is wider than an earlier version of this comment admitted. That version
    /// said "a spent hidden banner whose schedule was **deleted** after it fired", as though
    /// deletion were the way in. It is not the way in, it is one of five. The keep turns on there
    /// being *no rebuilt entry* under the identifier, and every route to that lands in the same
    /// place. Measured one case at a time, against a spent hidden banner and a schedule set that no
    /// longer covers its moment:
    ///
    /// - the schedule was **deleted**;
    /// - it was **completed** (`completedAt` set, so `isCompleted`);
    /// - it was **deactivated** (`!isActive`);
    /// - its **reminders were switched off** (`!notificationsEnabled`);
    /// - it ran **past its `endDate`**.
    ///
    /// All five drop it from `live`, so all five leave `accurate` with no entry under that
    /// identifier, so all five keep the banner. Nor is there a recency bound: `moment <= now` is as
    /// satisfied by a stamp from 2001 as by one from a minute ago, so a hidden banner is kept however
    /// long ago it fired. `testASpentHiddenBannerIsKeptWhateverSilencedItsSchedule` holds the list,
    /// so it cannot quietly become six.
    ///
    /// It stays a concession rather than a leak, and that is why the width is tolerable: the third
    /// condition checks that the payload is exactly the two constants `hiddenContent` builds, so in
    /// none of the five is anything about the schedule on the screen. What the user is left with is
    /// a banner to swipe. What the other choice would cost them is an unread reminder — which under
    /// Privacy Mode is the only trace they have that anything fired at all. It is the same trade the
    /// detailed branch already makes for the advance, on a banner that says two constants.
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

    /// The instant a reminder for `dueDate` fires: `fireComponents` resolved against the calendar
    /// and time zone in force **now**, which is what `UNCalendarNotificationTrigger` will match.
    ///
    /// Resolving through the components rather than adjusting the date is what carries WC-L5's
    /// 00:00 → 09:00 pin, and it is also what keeps this in step with the trigger: the same
    /// components produce both, so the identifier can never name a moment the banner does not fire
    /// at. The components already distinguish everything the calendar distinguishes —
    /// `Calendar.dateComponents` fills in `isLeapMonth` whether or not it is asked for, and
    /// `date(from:)` honours it — so this separates a Chinese leap month from the ordinary month of
    /// the same number, which the *stamp* below could not.
    ///
    /// `?? dueDate` rather than a constant: an unresolvable component set must still give distinct
    /// schedules distinct moments, or the coalescing would collapse them into one banner.
    nonisolated static func fireMoment(for dueDate: Date) -> Date {
        Calendar.current.date(from: fireComponents(for: dueDate)) ?? dueDate
    }

    /// The identifier a coalesced reminder is filed under: the fire **moment**, not a schedule and
    /// not a rendering of one.
    ///
    /// A pure function of the moment, so re-running `sync` over an unchanged schedule set produces
    /// the same request set. `due-` cannot collide with the per-schedule form, which is a UUID
    /// string.
    ///
    /// The stamp used to be `<Y-M-D-H-M>`, read back with `Calendar.current.date(from:)` — the
    /// calendar and time zone **at read time**, not the ones that wrote it. That made the
    /// identifier a *calendar rendering* of an instant, and a rendering means different instants to
    /// different readers:
    ///
    /// - **A time-zone change moved it by the offset difference, up to ±26 h.** Measured with a
    ///   probe replicating both functions verbatim: `due-2026-9-1-9-0` stamped in Tokyo names
    ///   2026-09-01T00:00Z, and read in London the same string names 2026-09-01T08:00Z. Against a
    ///   `now` thirty seconds after the banner fired, `moment <= now` flips from true to false and
    ///   `staleDelivered` takes down a banner that had just arrived — the thirty-second take-down
    ///   `81c2fca` fixed, back again while travelling.
    /// - **Under a Chinese `Calendar.current` it lost a reminder outright.** A leap-month date and
    ///   the ordinary month of the same number render to the *same* five numbers, because
    ///   `isLeapMonth` was not among the fields stamped. Two schedules a leap month apart therefore
    ///   collided in `posted.insert(identifier)` and the second was never posted. (Measured and not
    ///   affected: japanese, buddhist, roc, islamic-umalqura, hebrew, persian, coptic and indian all
    ///   round-trip exactly.)
    ///
    /// So the stamp is now the instant itself — whole seconds since the reference date — and the
    /// reader parses it with **no calendar at all**. There is nothing left for a reader's locale to
    /// disagree with. The coalescing property is unchanged and for the same reason it always held:
    /// two schedules due at the same moment produce the same `fireMoment` and therefore the same
    /// string, and `fireComponents`' minute resolution is what makes "the same moment" the right
    /// grain.
    ///
    /// What this does *not* fix: the trigger is a wall-clock rule, so a device that changes time
    /// zone between the last `sync` and the fire delivers the banner at a different instant than the
    /// one stamped. In practice `sync` re-stamps the whole pending set on the 30-second timer and on
    /// every data change, so the stamp a *delivered* banner carries is the instant it actually fired
    /// unless the app never ran between the change and the fire. Bounded by the offset difference,
    /// and in the same direction as the DST fall-back drift that was always here.
    private nonisolated static func coalescedIdentifier(at moment: Date, prefix: String) -> String {
        "\(prefix)due-\(Int(moment.timeIntervalSinceReferenceDate.rounded()))"
    }

    /// The moment a coalesced identifier names, or `nil` if it does not name one.
    ///
    /// The inverse of `coalescedIdentifier(at:prefix:)`, written next to it. Both stay `private`:
    /// what a test can reach is the verdict `staleDelivered` reaches with them, and
    /// `testASpentPrivacyModeBannerSurvivesItsScheduleAdvancing` exercises the round trip that way —
    /// a past moment is kept, the same moment in the future is not, and a `due-` identifier whose
    /// stamp does not parse is not.
    ///
    /// `staleDelivered` needs this because *spent* is the only thing that separates a schedule
    /// advancing past its due moment from a schedule being deleted: neither leaves a live schedule
    /// at that moment, and the identifier is the only place the moment survives. Anything that does
    /// not parse cleanly — a foreign identifier, a per-schedule UUID, a stamp that is not a number —
    /// returns `nil` and is judged the old way, which is the conservative direction.
    ///
    /// **The `<Y-M-D-H-M>` branch is migration and nothing else.** Nothing writes that form any
    /// more, but banners delivered under it are on lock screens right now, and the identifier of a
    /// delivered banner cannot be rewritten. Dropping the branch would make every one of them
    /// unparsable, and an unparsable `due-` identifier is judged stale and taken down — so the
    /// upgrade itself would sweep the very unread Privacy Mode banners this teardown exists to
    /// spare. Read the old form the old way instead: for a banner stamped under the old scheme that
    /// is exactly the behaviour it was stamped for, drift and all, so no banner is worse off than it
    /// is today and none is orphaned into never being torn down. The branch dies out on its own, as
    /// the banners behind it are swiped or superseded; the two forms cannot be confused, because a
    /// seconds stamp never splits into five fields and five fields never parse as one `Int`.
    private nonisolated static func coalescedMoment(of identifier: String, prefix: String) -> Date? {
        let marker = "\(prefix)due-"
        guard identifier.hasPrefix(marker) else { return nil }
        let stamp = identifier.dropFirst(marker.count)
        if let seconds = Int(stamp) {
            return Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
        }
        // The date components the **superseded** identifier form stamped, in the order it stamped
        // them. A local rather than a `static`: as type-level storage it needed a `nonisolated`
        // annotation to satisfy strict concurrency, and `nonisolated(unsafe)` is exactly what
        // `testTheErasePathNamesEveryReminderItOwns` forbids in this file — rightly, since state
        // that survives between calls here could filter still-backed banners out of the erase path
        // and leave wiped data describing itself on the lock screen. Nothing else reads it, so
        // there is no reason for it to be type-level at all.
        let legacyStampFields: [WritableKeyPath<DateComponents, Int?>] = [
            \.year, \.month, \.day, \.hour, \.minute,
        ]
        let fields = stamp.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == legacyStampFields.count else { return nil }
        var components = DateComponents()
        for (field, text) in zip(legacyStampFields, fields) {
            guard let value = Int(text) else { return nil }
            components[keyPath: field] = value
        }
        return Calendar.current.date(from: components)
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
    /// Stated as a function, erase names every reminder under this prefix, from the two queues and
    /// **nothing else**. There is no parameter through which a schedule could arrive, so no caller
    /// can feed it one.
    ///
    /// An earlier version of this comment went further and was **wrong about Swift**: it said
    /// "`nonisolated static` means no actor state can be read either, so making this consult the
    /// data takes a signature change that its test will not compile against". `nonisolated` excludes
    /// the actor's *instance* state — there is no `self` here — and that is all it excludes. Static
    /// storage is not instance state. A `nonisolated(unsafe) static var lastSyncedSchedules` written
    /// by `sync` and read here compiles, needs no signature change, and lets erase spare every
    /// banner still backed by a cached schedule — after "erase local data", which is precisely the
    /// regression this was claimed to make impossible. The false sentence was load-bearing: it was
    /// the reason nobody was looking.
    ///
    /// What actually holds it is weaker and worth naming as such: the parameter list, plus
    /// `testTheErasePathNamesEveryReminderItOwns` asserting that this type declares no mutable
    /// static or file-scope storage for such a cache to live in. That second half is a *textual*
    /// check over this file — the same kind of check as the notification pins, with the same kind of
    /// limit — and it does not reach a cache parked in another file. Erase is all-or-nothing by
    /// construction here and by lint everywhere else.
    ///
    /// `testTheErasePathNamesEveryReminderItOwns` asserts the values;
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
