import Foundation

/// Builds the finalized `RecurringTransaction` from recurring-editor inputs (M2 / T2).
///
/// Extracted from the iOS (`Forms.swift`) and macOS (`MacRecurringTransactionEditor`)
/// editors, which had byte-identical "seed → compute nextDueDate / isActive" logic.
/// Pure and `now`-injectable so the next-due, future-clamp and end-date behavior can
/// be unit-tested. Mirrors H7: a changed/new schedule's next due date is the first
/// occurrence on or after `now` (never back-dated); if none exists the schedule
/// deactivates rather than mass-generating history.
enum RecurringScheduleBuilder {
    static func build(
        existing: RecurringTransaction?,
        type: TransactionType,
        category: String,
        amount: Decimal,
        description: String,
        startDate: Date,
        frequency: RecurringTransactionFrequency,
        endDate: Date?,
        notificationsEnabled: Bool,
        currency: Currency,
        now: Date = Date()
    ) -> RecurringTransaction {
        let scheduleChanged = existing.map {
            $0.frequency != frequency || abs($0.startDate.timeIntervalSince(startDate)) >= 1
        } ?? true

        // Compared by calendar day, not by instant: both editors re-derive the end date as 23:59:59
        // *local* on every save, so an exact `Date` comparison reports a change the user never made
        // as soon as the saving device sits in a different timezone from the one that stored it.
        // (`scheduleChanged` above carries a 1-second tolerance on `startDate` for the same reason.)
        let calendar = Calendar.current
        let endDateChanged = existing.map { prior -> Bool in
            switch (prior.endDate, endDate) {
            case (nil, nil): return false
            case let (priorEnd?, newEnd?): return !calendar.isDate(priorEnd, inSameDayAs: newEnd)
            default: return true
            }
        } ?? true

        // Whether the schedule had already run out — no occurrence left on or after `now` under its
        // own start, frequency and end date. This is what separates a schedule that *lapsed* on its
        // own from one the user deliberately **paused**, a distinction `isActive == false` cannot
        // express on its own because both write the same flag.
        let wasExhausted = existing.map { $0.firstOccurrence(onOrAfter: now) == nil } ?? true

        let seed = RecurringTransaction(
            id: existing?.id ?? UUID(),
            type: type,
            category: category,
            amount: amount,
            description: description,
            startDate: startDate,
            frequency: frequency,
            nextDueDate: startDate,
            endDate: endDate,
            currency: currency,
            notificationsEnabled: notificationsEnabled,
            isActive: existing?.isActive ?? true,
            completedAt: existing?.completedAt,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        var saved = seed
        if saved.isCompleted {
            saved.isActive = false
        } else if !scheduleChanged, let existing, existing.isActive {
            saved.nextDueDate = existing.nextDueDate
        } else if let nextDueDate = seed.firstOccurrence(onOrAfter: now) {
            saved.nextDueDate = nextDueDate
            // Reactivate a lapsed (auto-deactivated) schedule when a fresh future occurrence
            // exists — e.g. the user extended the endDate without touching frequency/startDate
            // (deep-audit M21). The endDate guard below can still turn it back off.
            //
            // Only when the edit could have revived it, though. This used to be unconditional, so a
            // schedule the user paused was resumed by any unrelated edit: reopening "Rent, 1200,
            // monthly", fixing the description and saving left `scheduleChanged == false` and
            // `existing.isActive == false`, which fell through to here and set it running again —
            // and the charge then landed on the schedule's next occurrence, up to a month or a year
            // later, far enough from the edit that nobody would connect the two.
            //
            // An end-date edit only counts when the schedule had actually run out. Asking merely
            // whether the end date *moved* left the same bug one gesture over: setting a first end
            // date on a paused schedule, or even shortening one to wind it down, resumed it.
            // Otherwise the seed's `isActive: existing?.isActive ?? true` stands, preserving pause.
            if scheduleChanged || (endDateChanged && wasExhausted) {
                saved.isActive = true
            }
        } else {
            saved.isActive = false
        }

        if let endDate = saved.endDate, saved.nextDueDate > endDate {
            saved.isActive = false
        }
        return saved
    }
}
