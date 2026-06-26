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
        } else if !scheduleChanged, let existing {
            saved.nextDueDate = existing.nextDueDate
        } else if let nextDueDate = seed.firstOccurrence(onOrAfter: now) {
            saved.nextDueDate = nextDueDate
        } else {
            saved.isActive = false
        }

        if let endDate = saved.endDate, saved.nextDueDate > endDate {
            saved.isActive = false
        }
        return saved
    }
}
