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
            notificationsEnabled: true, now: date(2026, 6, 22)
        )
        XCTAssertEqual(result.nextDueDate, date(2026, 7, 1))
        XCTAssertTrue(result.isActive)
    }

    func testNewScheduleWithPastStartIsNeverBackDated() {
        let now = date(2026, 6, 22)
        let result = RecurringScheduleBuilder.build(
            existing: nil, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: date(2026, 1, 1), frequency: .monthly, endDate: nil,
            notificationsEnabled: true, now: now
        )
        XCTAssertGreaterThanOrEqual(result.nextDueDate, now, "next due must never be back-dated (H7)")
    }

    func testEndDateBeforeNextDueDeactivates() {
        let result = RecurringScheduleBuilder.build(
            existing: nil, type: .income, category: "X", amount: 10, description: "",
            startDate: date(2026, 7, 1), frequency: .monthly, endDate: date(2026, 6, 25),
            notificationsEnabled: true, now: date(2026, 6, 22)
        )
        XCTAssertFalse(result.isActive)
    }

    func testUnchangedExistingSchedulePreservesNextDueAndIdentity() {
        let start = date(2026, 6, 1)
        let existing = schedule(start: start, frequency: .monthly, nextDue: date(2026, 7, 1))
        let rebuilt = RecurringScheduleBuilder.build(
            existing: existing, type: .expense, category: "Rent", amount: 500, description: "Rent",
            startDate: start, frequency: .monthly, endDate: nil,
            notificationsEnabled: true, now: date(2026, 6, 22)
        )
        XCTAssertEqual(rebuilt.nextDueDate, existing.nextDueDate)
        XCTAssertEqual(rebuilt.id, existing.id)
    }

    func testFirstOccurrenceMonthlyAnchorsToStartDay() {
        let schedule = schedule(start: date(2026, 1, 15), frequency: .monthly, nextDue: date(2026, 1, 15))
        let occurrence = schedule.firstOccurrence(onOrAfter: date(2026, 6, 22), calendar: utc)
        XCTAssertNotNil(occurrence)
        XCTAssertEqual(occurrence.map { utc.component(.day, from: $0) }, 15)
        XCTAssertEqual(occurrence.map { utc.component(.month, from: $0) }, 7)
    }
}
