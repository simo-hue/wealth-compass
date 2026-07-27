import XCTest
@testable import WealthCompassMobile

/// Report export options: date-range resolution, section ordering, validity and filenames.
/// Covers the pure decision layer only — rendering is exercised separately.
final class ReportExportOptionsTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `fileName` pins its formatter's calendar but never its time zone, so the stamp always
    /// renders in the device's zone. Filename fixtures are therefore built at noon in that same
    /// zone — a UTC fixture would stamp the *next* day on a simulator set to UTC+13 or UTC+14.
    /// The identifier stays gregorian so a device on a Buddhist region calendar cannot turn 2026
    /// into 2569.
    private let deviceCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return utc.date(from: comps)!
    }

    private func deviceNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return deviceCalendar.date(from: comps)!
    }

    // MARK: - Date range: presets

    func testAllTimeResolvesToNoInterval() {
        XCTAssertNil(ReportDateRange.allTime.resolve(now: date(2026, 6, 22), calendar: utc),
                     "an unbounded ledger must not be narrowed by a synthetic interval")
    }

    func testThisYearRunsFromJanuaryFirstToEndOfToday() throws {
        let interval = try XCTUnwrap(ReportDateRange.thisYear.resolve(now: date(2026, 6, 22), calendar: utc))
        XCTAssertEqual(interval.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(interval.end, date(2026, 6, 22, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 173 * 86_400 - 1, "1 Jan through 22 Jun inclusive, less the clamped second")
    }

    func testThisYearIncludesATransactionDatedLaterToday() throws {
        // The point of clamping to end-of-day: an entry timestamped 23:59 today must not fall
        // outside a range the user thinks of as "this year", whatever the hour of export.
        let interval = try XCTUnwrap(ReportDateRange.thisYear.resolve(now: date(2026, 6, 22, hour: 9), calendar: utc))
        XCTAssertTrue(interval.contains(date(2026, 6, 22, hour: 23, minute: 59)), "later today is in")
        XCTAssertTrue(interval.contains(date(2026, 6, 22, hour: 23, minute: 59, second: 59)), "the last second of today is in")
        XCTAssertTrue(interval.contains(date(2026, 1, 1, hour: 0)), "1 Jan midnight is the inclusive lower bound")
        XCTAssertFalse(interval.contains(date(2026, 6, 23, hour: 0)), "tomorrow is out")
        XCTAssertFalse(interval.contains(date(2025, 12, 31, hour: 23, minute: 59, second: 59)), "last year is out")
    }

    func testLast12MonthsStartsExactlyTwelveMonthsBeforeToday() throws {
        let interval = try XCTUnwrap(ReportDateRange.last12Months.resolve(now: date(2026, 6, 22), calendar: utc))
        XCTAssertEqual(interval.start, date(2025, 6, 22, hour: 0), "the start is a whole day, not now-minus-a-year")
        XCTAssertEqual(interval.end, date(2026, 6, 22, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 366 * 86_400 - 1, "22 Jun 2025 through 22 Jun 2026 inclusive")
    }

    // MARK: - Date range: year boundary

    func testThisYearOnNewYearsDayCoversThatDayAlone() throws {
        let interval = try XCTUnwrap(ReportDateRange.thisYear.resolve(now: date(2026, 1, 1), calendar: utc))
        XCTAssertEqual(interval.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(interval.end, date(2026, 1, 1, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 86_399, "a year that is one day old spans one day")
    }

    func testThisYearOnNewYearsEveCoversTheWholeYear() throws {
        let interval = try XCTUnwrap(ReportDateRange.thisYear.resolve(now: date(2026, 12, 31), calendar: utc))
        XCTAssertEqual(interval.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(interval.end, date(2026, 12, 31, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 365 * 86_400 - 1, "2026 is not a leap year")
    }

    func testLast12MonthsFromNewYearsDayCrossesTheYearBoundary() throws {
        let interval = try XCTUnwrap(ReportDateRange.last12Months.resolve(now: date(2026, 1, 1), calendar: utc))
        XCTAssertEqual(interval.start, date(2025, 1, 1, hour: 0), "twelve months back must leave the year, not clamp inside it")
        XCTAssertEqual(interval.end, date(2026, 1, 1, hour: 23, minute: 59, second: 59))
    }

    // MARK: - Date range: leap day

    func testThisYearOnLeapDayEndsAtEndOfFebruary29() throws {
        let interval = try XCTUnwrap(ReportDateRange.thisYear.resolve(now: date(2024, 2, 29), calendar: utc))
        XCTAssertEqual(interval.start, date(2024, 1, 1, hour: 0))
        XCTAssertEqual(interval.end, date(2024, 2, 29, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 60 * 86_400 - 1, "31 days of January plus 29 of February")
    }

    func testLast12MonthsFromLeapDayClampsToTheLastDayOfFebruary() throws {
        // 29 Feb 2023 does not exist. Foundation pins the day of month rather than rolling into
        // March, so the range opens a day early instead of a day late — which is the safe side,
        // as it can only over-report the ledger, never drop a transaction.
        let interval = try XCTUnwrap(ReportDateRange.last12Months.resolve(now: date(2024, 2, 29), calendar: utc))
        XCTAssertEqual(interval.start, date(2023, 2, 28, hour: 0))
        XCTAssertEqual(interval.end, date(2024, 2, 29, hour: 23, minute: 59, second: 59))
        XCTAssertTrue(interval.contains(date(2023, 2, 28, hour: 12)), "the pinned day is itself covered")
    }

    func testCustomRangeSpanningALeapDayContainsIt() throws {
        let interval = try XCTUnwrap(
            ReportDateRange.custom(start: date(2024, 2, 28), end: date(2024, 3, 1))
                .resolve(now: date(2026, 6, 22), calendar: utc)
        )
        XCTAssertEqual(interval.start, date(2024, 2, 28, hour: 0))
        XCTAssertEqual(interval.end, date(2024, 3, 1, hour: 23, minute: 59, second: 59))
        XCTAssertTrue(interval.contains(date(2024, 2, 29, hour: 12)), "the leap day is not skipped")
        XCTAssertEqual(interval.duration, 3 * 86_400 - 1, "28 Feb, 29 Feb, 1 Mar")
    }

    // MARK: - Date range: custom

    func testCustomRangeNormalisesToWholeDays() throws {
        let interval = try XCTUnwrap(
            ReportDateRange.custom(start: date(2026, 3, 10, hour: 17, minute: 42),
                                   end: date(2026, 3, 15, hour: 6, minute: 5))
                .resolve(now: date(2026, 6, 22), calendar: utc)
        )
        XCTAssertEqual(interval.start, date(2026, 3, 10, hour: 0), "the picker's time component must not clip the first day")
        XCTAssertEqual(interval.end, date(2026, 3, 15, hour: 23, minute: 59, second: 59), "nor the last")
        XCTAssertEqual(interval.duration, 6 * 86_400 - 1, "10th through 15th inclusive")
    }

    func testInvertedCustomRangeIsNormalisedInsteadOfTrapping() throws {
        // The sheet has two independent pickers, so start > end is reachable. `DateInterval` traps
        // on an inverted pair, which would take the app down rather than produce a bad report.
        let interval = try XCTUnwrap(
            ReportDateRange.custom(start: date(2026, 6, 22), end: date(2026, 1, 5))
                .resolve(now: date(2026, 6, 22), calendar: utc)
        )
        XCTAssertEqual(interval.start, date(2026, 1, 5, hour: 0))
        XCTAssertEqual(interval.end, date(2026, 6, 22, hour: 23, minute: 59, second: 59))
        XCTAssertLessThanOrEqual(interval.start, interval.end)
    }

    func testInvertedCustomRangeMatchesItsUprightTwin() throws {
        let now = date(2026, 6, 22)
        let inverted = try XCTUnwrap(
            ReportDateRange.custom(start: date(2026, 6, 22), end: date(2026, 1, 5)).resolve(now: now, calendar: utc)
        )
        let upright = try XCTUnwrap(
            ReportDateRange.custom(start: date(2026, 1, 5), end: date(2026, 6, 22)).resolve(now: now, calendar: utc)
        )
        XCTAssertEqual(inverted, upright, "swapping the two pickers must not change the reported period")
    }

    func testCustomRangeOnASingleDayCoversThatWholeDay() throws {
        // Both ends land on 10 March but in the wrong order — the degenerate case where inversion
        // and same-day collapse meet.
        let interval = try XCTUnwrap(
            ReportDateRange.custom(start: date(2026, 3, 10, hour: 23, minute: 59, second: 59),
                                   end: date(2026, 3, 10, hour: 0, minute: 0, second: 1))
                .resolve(now: date(2026, 6, 22), calendar: utc)
        )
        XCTAssertEqual(interval.start, date(2026, 3, 10, hour: 0))
        XCTAssertEqual(interval.end, date(2026, 3, 10, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(interval.duration, 86_399)
    }

    func testPresetsNeverOfferCustom() {
        XCTAssertEqual(ReportDateRange.presets, [.allTime, .thisYear, .last12Months])
        XCTAssertTrue(ReportDateRange.presets.allSatisfy { !$0.isCustom },
                      ".custom carries live picker dates and is appended by the UI, never listed as a preset")
        XCTAssertTrue(ReportDateRange.custom(start: date(2026, 1, 1), end: date(2026, 6, 22)).isCustom)
    }

    // MARK: - Options

    func testDefaultOptionsAreAValidFullPDF() {
        let options = ReportExportOptions()
        XCTAssertEqual(options.format, .pdf)
        XCTAssertEqual(options.dateRange, .allTime)
        XCTAssertEqual(options.orderedSections, ReportSection.allCases)
        XCTAssertTrue(options.isFullReport)
        XCTAssertTrue(options.isValid)
    }

    func testIsFullReportRequiresEverySection() {
        XCTAssertTrue(ReportExportOptions(sections: Set(ReportSection.allCases)).isFullReport)
        XCTAssertFalse(ReportExportOptions(sections: [.overview, .cashFlow, .investments]).isFullReport,
                       "three of four is a partial report — the cover page wording turns on this")
        XCTAssertFalse(ReportExportOptions(sections: [.crypto]).isFullReport)
        XCTAssertFalse(ReportExportOptions(sections: []).isFullReport)
    }

    func testOrderedSectionsIgnoresSetInsertionOrder() {
        var scrambled: Set<ReportSection> = []
        scrambled.insert(.crypto)
        scrambled.insert(.investments)
        scrambled.insert(.cashFlow)
        scrambled.insert(.overview)

        XCTAssertEqual(ReportExportOptions(sections: scrambled).orderedSections,
                       [.overview, .cashFlow, .investments, .crypto],
                       "section order is the document's table of contents; a Set must never leak hash order into it")
    }

    func testOrderedSectionsKeepsCanonicalOrderForASubset() {
        var scrambled: Set<ReportSection> = []
        scrambled.insert(.crypto)
        scrambled.insert(.overview)
        XCTAssertEqual(ReportExportOptions(sections: scrambled).orderedSections, [.overview, .crypto])
        XCTAssertEqual(ReportExportOptions(sections: []).orderedSections, [])
    }

    func testPDFWithoutSectionsIsInvalid() {
        XCTAssertFalse(ReportExportOptions(format: .pdf, sections: []).isValid,
                       "an empty PDF is a cover page and nothing else — the Export button stays disabled")
        XCTAssertTrue(ReportExportOptions(format: .pdf, sections: [.overview]).isValid)
    }

    func testJSONIgnoresTheSectionPickerAndStaysValid() {
        XCTAssertTrue(ReportExportOptions(format: .json, sections: []).isValid,
                      "JSON is a whole-database backup; a partial one would break the restore contract")
        XCTAssertTrue(ReportExportOptions(format: .json, sections: [.crypto]).isValid)
    }

    // MARK: - Filenames

    func testFileNameForJSONFollowsTheBackupConvention() {
        let options = ReportExportOptions(format: .json, sections: [])
        XCTAssertEqual(options.fileName(date: deviceNoon(2026, 6, 22), calendar: deviceCalendar),
                       "wealth-compass-backup-2026-06-22.json",
                       "the JSON stem is shared with the pre-existing backup export and must not drift")
    }

    func testFileNameForAFullPDFUsesTheGenericReportStem() {
        let options = ReportExportOptions(format: .pdf, sections: Set(ReportSection.allCases))
        XCTAssertEqual(options.fileName(date: deviceNoon(2026, 6, 22), calendar: deviceCalendar),
                       "wealth-compass-report-2026-06-22.pdf")
    }

    func testFileNameForASingleSectionIsKebabCased() {
        let options = ReportExportOptions(format: .pdf, sections: [.cashFlow])
        XCTAssertEqual(options.fileName(date: deviceNoon(2026, 6, 22), calendar: deviceCalendar),
                       "wealth-compass-cash-flow-2026-06-22.pdf",
                       "the camelCase raw value must not leak into the filename")
    }

    func testFileNameCoversEverySingleSectionStem() {
        let stamp = deviceNoon(2026, 6, 22)
        let expectations: [(ReportSection, String)] = [
            (.overview, "wealth-compass-overview-2026-06-22.pdf"),
            (.cashFlow, "wealth-compass-cash-flow-2026-06-22.pdf"),
            (.investments, "wealth-compass-investments-2026-06-22.pdf"),
            (.crypto, "wealth-compass-crypto-2026-06-22.pdf")
        ]
        XCTAssertEqual(expectations.map(\.0), ReportSection.allCases, "a new section must be given an expected stem here")

        for (section, expected) in expectations {
            let options = ReportExportOptions(format: .pdf, sections: [section])
            XCTAssertEqual(options.fileName(date: stamp, calendar: deviceCalendar), expected)
        }
    }

    func testFileNameForTwoSectionsFallsBackToTheGenericStem() {
        let options = ReportExportOptions(format: .pdf, sections: [.crypto, .overview])
        XCTAssertEqual(options.fileName(date: deviceNoon(2026, 6, 22), calendar: deviceCalendar),
                       "wealth-compass-report-2026-06-22.pdf",
                       "only a lone section earns its own stem")
    }

    func testFileNameStampIsZeroPadded() {
        let options = ReportExportOptions(format: .pdf, sections: [.overview])
        XCTAssertEqual(options.fileName(date: deviceNoon(2026, 1, 5), calendar: deviceCalendar),
                       "wealth-compass-overview-2026-01-05.pdf",
                       "a folder of exports has to sort lexicographically")
    }

    // MARK: - Sections

    func testAllCasesFollowTheAppsNavigationOrder() {
        XCTAssertEqual(ReportSection.allCases, [.overview, .cashFlow, .investments, .crypto])
        XCTAssertEqual(ReportSection.allCases.map(\.rawValue),
                       ["overview", "cashFlow", "investments", "crypto"],
                       "raw values are encoded into persisted options and decoded back")
    }

    func testSectionAnchorsAreUniqueAndStable() {
        let anchors = ReportSection.allCases.map(\.anchor)
        XCTAssertEqual(anchors,
                       ["section-overview", "section-cashFlow", "section-investments", "section-crypto"],
                       "anchors are baked into exported PDFs as link destinations — renaming one breaks old documents")
        XCTAssertEqual(Set(anchors).count, ReportSection.allCases.count,
                       "a collision would silently misroute the outline to the wrong page")
    }

    func testSectionIdentityRoundTripsThroughItsRawValue() {
        for section in ReportSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
            XCTAssertEqual(ReportSection(rawValue: section.rawValue), section)
        }
    }

    func testEverySectionHasItsOwnTitleAndSymbol() {
        // Guards the copy-paste failure mode in the two switches, which no other assertion catches.
        XCTAssertEqual(Set(ReportSection.allCases.map(\.titleKey)).count, ReportSection.allCases.count)
        XCTAssertEqual(Set(ReportSection.allCases.map(\.symbolName)).count, ReportSection.allCases.count)
    }
}
