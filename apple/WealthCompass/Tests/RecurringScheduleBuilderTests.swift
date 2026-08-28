import XCTest
@testable import WealthCompassMobile

/// T2 — recurring schedule building + date math (monthly anchoring, future-clamp, H7).
final class RecurringScheduleBuilderTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return utc.date(from: comps)!
    }

    private func schedule(start: Date, frequency: RecurringTransactionFrequency, nextDue: Date, id: UUID = UUID()) -> RecurringTransaction {
        RecurringTransaction(
            id: id, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: start, frequency: frequency, nextDueDate: nextDue, endDate: nil,
            notificationsEnabled: true, isActive: true, completedAt: nil,
            createdAt: start, updatedAt: start
        )
    }

    func testNewScheduleWithFutureStartUsesStartAsNextDue() {
        let result = RecurringScheduleBuilder.build(
            existing: nil, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: date(2026, 7, 1), frequency: .monthly, endDate: nil,
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )
        XCTAssertEqual(result.nextDueDate, date(2026, 7, 1))
        XCTAssertTrue(result.isActive)
    }

    func testNewScheduleWithPastStartIsNeverBackDated() {
        let now = date(2026, 6, 22)
        let result = RecurringScheduleBuilder.build(
            existing: nil, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: date(2026, 1, 1), frequency: .monthly, endDate: nil,
            notificationsEnabled: true, currency: .eur, now: now
        )
        XCTAssertGreaterThanOrEqual(result.nextDueDate, now, "next due must never be back-dated (H7)")
    }

    func testEndDateBeforeNextDueDeactivates() {
        let result = RecurringScheduleBuilder.build(
            existing: nil, type: .income, category: "X", amount: 10, description: "",
            startDate: date(2026, 7, 1), frequency: .monthly, endDate: date(2026, 6, 25),
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )
        XCTAssertFalse(result.isActive)
    }

    func testUnchangedExistingSchedulePreservesNextDueAndIdentity() {
        let start = date(2026, 6, 1)
        let existing = schedule(start: start, frequency: .monthly, nextDue: date(2026, 7, 1))
        let rebuilt = RecurringScheduleBuilder.build(
            existing: existing, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: start, frequency: .monthly, endDate: nil,
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )
        XCTAssertEqual(rebuilt.nextDueDate, existing.nextDueDate)
        XCTAssertEqual(rebuilt.id, existing.id)
    }

    /// Editing an unrelated field on a paused schedule must not resume it.
    ///
    /// The M21 reactivation used to be unconditional, and the branch above it additionally requires
    /// `existing.isActive` — so a paused schedule with an unchanged frequency/start fell straight
    /// through to it. Fixing a typo in the description therefore set `isActive = true`, and within
    /// 30 seconds `processDueRecurringTransactions` started posting the expense again.
    func testEditingAPausedScheduleKeepsItPaused() {
        let start = date(2026, 1, 1)
        var existing = schedule(start: start, frequency: .monthly, nextDue: date(2026, 7, 1))
        existing.isActive = false

        let rebuilt = RecurringScheduleBuilder.build(
            existing: existing, type: .expense, category: "Rent", amount: 500,
            description: "Rent (landlord: Maria)", // the only change
            startDate: start, frequency: .monthly, endDate: nil,
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )

        XCTAssertFalse(rebuilt.isActive, "A paused schedule must survive an unrelated edit.")
        XCTAssertEqual(rebuilt.description, "Rent (landlord: Maria)", "The edit must still be saved.")
    }

    /// ...but M21 itself must still work: extending the end date revives a lapsed schedule.
    func testExtendingTheEndDateStillRevivesALapsedSchedule() {
        let start = date(2026, 1, 1)
        var existing = schedule(start: start, frequency: .monthly, nextDue: date(2026, 7, 1))
        existing.endDate = date(2026, 3, 1) // ran out, so it auto-deactivated
        existing.isActive = false

        let rebuilt = RecurringScheduleBuilder.build(
            existing: existing, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: start, frequency: .monthly,
            endDate: date(2027, 1, 1), // extended
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )

        XCTAssertTrue(rebuilt.isActive, "Extending the end date must revive a lapsed schedule (M21).")
        // Asserted as a range, not an instant: `build` resolves occurrences with `Calendar.current`
        // (it takes no calendar), so pinning the exact `Date` compares a UTC-built fixture against
        // local-calendar month arithmetic and drifts by the UTC offset across a DST boundary —
        // a start in January and a due date in July differ by an hour in any European zone.
        XCTAssertGreaterThan(rebuilt.nextDueDate, date(2026, 6, 22), "The revived due date must be ahead of now.")
        XCTAssertLessThanOrEqual(rebuilt.nextDueDate, date(2027, 1, 1), "…and within the extended end date.")
    }

    /// A changed frequency also counts as a revive-worthy edit.
    func testChangingFrequencyRevivesAnInactiveSchedule() {
        let start = date(2026, 1, 1)
        var existing = schedule(start: start, frequency: .monthly, nextDue: date(2026, 7, 1))
        existing.isActive = false

        let rebuilt = RecurringScheduleBuilder.build(
            existing: existing, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: start, frequency: .weekly, endDate: nil,
            notificationsEnabled: true, currency: .eur, now: date(2026, 6, 22)
        )

        XCTAssertTrue(rebuilt.isActive, "Rewriting the schedule itself still recomputes isActive.")
    }

    func testFirstOccurrenceMonthlyAnchorsToStartDay() {
        let schedule = schedule(start: date(2026, 1, 15), frequency: .monthly, nextDue: date(2026, 1, 15))
        let occurrence = schedule.firstOccurrence(onOrAfter: date(2026, 6, 22), calendar: utc)
        XCTAssertNotNil(occurrence)
        XCTAssertEqual(occurrence.map { utc.component(.day, from: $0) }, 15)
        XCTAssertEqual(occurrence.map { utc.component(.month, from: $0) }, 7)
    }
}
