import XCTest
@testable import WealthCompassMobile

/// T3 — snapshot backfill (incl. > 60-day gaps) and retroactive adjustment (M1/M5).
final class SnapshotEngineTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var engine: SnapshotEngine { SnapshotEngine(calendar: utc) }

    private let totals = FinanceTotals(
        totalLiquidity: 100, totalInvestments: 50, totalCrypto: 25,
        totalAssets: 175, totalLiabilities: 30, netWorth: 145
    )

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return utc.date(from: comps)!
    }

    func testAppendsToEmptyHistory() {
        let result = engine.appendingSnapshot(to: [], totals: totals, now: date(2026, 6, 22))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].netWorth, 145)
    }

    func testUpsertsSameDay() {
        let now = date(2026, 6, 22)
        let first = engine.appendingSnapshot(to: [], totals: totals, now: now)
        let replacement = FinanceTotals(
            totalLiquidity: 200, totalInvestments: 0, totalCrypto: 0,
            totalAssets: 200, totalLiabilities: 0, netWorth: 200
        )
        let second = engine.appendingSnapshot(to: first, totals: replacement, now: now)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].netWorth, 200)
    }

    func testDoesNotMaterializeCarryForwardGaps() {
        // No-activity days are filled by the chart at render time, not stored — so appending after a
        // gap adds exactly one new snapshot (today), never a backfill burst (WC-#11).
        let seed = engine.appendingSnapshot(to: [], totals: totals, now: date(2026, 6, 18))
        let result = engine.appendingSnapshot(to: seed, totals: totals, now: date(2026, 6, 22))
        XCTAssertEqual(result.count, 2, "seed (18) + today (22), no carry-forward rows")
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted())
    }

    func testLongGapStillAddsOnlyOneSnapshot() {
        // A ~172-day gap previously spawned 60 backfill records; now it adds just today's snapshot.
        let seed = engine.appendingSnapshot(to: [], totals: totals, now: date(2026, 1, 1))
        let result = engine.appendingSnapshot(to: seed, totals: totals, now: date(2026, 6, 22))
        XCTAssertEqual(result.count, 2)
    }

    func testAdjustsOnlySnapshotsOnOrAfterDate() {
        let snaps = [
            NetWorthSnapshot(date: date(2026, 6, 18), totalAssets: 100, totalLiabilities: 0, netWorth: 100, liquidity: 100, investments: 0, crypto: 0),
            NetWorthSnapshot(date: date(2026, 6, 20), totalAssets: 100, totalLiabilities: 0, netWorth: 100, liquidity: 100, investments: 0, crypto: 0)
        ]
        let result = engine.adjustingHistoricalSnapshots(snaps, from: date(2026, 6, 19), liquidityDelta: 50)
        XCTAssertEqual(result[0].netWorth, 100, "before the cutoff is untouched")
        XCTAssertEqual(result[1].liquidity, 150)
        XCTAssertEqual(result[1].totalAssets, 150)
        XCTAssertEqual(result[1].netWorth, 150)
    }
}
