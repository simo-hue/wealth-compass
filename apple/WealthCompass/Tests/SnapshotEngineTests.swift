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

    /// One logical daily row keeps one identity.
    ///
    /// The same-day upsert replaced the row with a freshly-minted `NetWorthSnapshot`, so its UUID
    /// changed on every write. `appendSnapshot` runs on every add, edit, delete and price refresh,
    /// and each new id diffs as "delete the old record, create a new one" — so twenty edits in a day
    /// produced twenty CloudKit records and nineteen permanent server tombstones, which every new
    /// device then downloads on bootstrap.
    func testSameDayUpsertKeepsTheRowsIdentity() {
        let day = date(2026, 6, 22)
        let first = engine.appendingSnapshot(to: [], totals: totals, now: day)
        let originalID = try? XCTUnwrap(first.first?.id)
        let originalCreatedAt = first.first?.createdAt

        let updatedTotals = FinanceTotals(
            totalLiquidity: 900, totalInvestments: 50, totalCrypto: 25,
            totalAssets: 975, totalLiabilities: 30, netWorth: 945
        )
        let second = engine.appendingSnapshot(to: first, totals: updatedTotals, now: day)

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.netWorth, 945, "the value must still update")
        XCTAssertEqual(second.first?.id, originalID, "the row changed identity on a same-day update")
        XCTAssertEqual(second.first?.createdAt, originalCreatedAt, "createdAt must survive the upsert")
    }

    /// A snapshot dated ahead of `now` must not defeat the same-day collapse.
    ///
    /// The upsert only inspected `snapshots.indices.last`, so once a future-dated row existed — from
    /// an import, or synced from a device with a fast clock — every later save appended another row
    /// for today instead of replacing it, growing the array by one duplicate per edit.
    func testFutureDatedRowDoesNotDefeatTheSameDayCollapse() {
        let today = date(2026, 6, 22)
        var history = engine.appendingSnapshot(to: [], totals: totals, now: today)
        history.append(NetWorthSnapshot(
            date: date(2026, 12, 1), totalAssets: 1, totalLiabilities: 0,
            netWorth: 1, liquidity: 1, investments: 0, crypto: 0
        ))
        history.sort { $0.date < $1.date }

        for _ in 0..<5 {
            history = engine.appendingSnapshot(to: history, totals: totals, now: today)
        }

        let todaysRows = history.filter { utc.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(todaysRows.count, 1, "duplicate rows accumulated for the same day")
        XCTAssertEqual(history.count, 2, "history grew beyond today + the future row")
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
        let result = engine.adjustingHistoricalSnapshots(snaps, from: date(2026, 6, 19), transactionCurrency: .usd, displayCurrency: .usd, liquidityDelta: 50)
        XCTAssertEqual(result[0].netWorth, 100, "before the cutoff is untouched")
        XCTAssertEqual(result[1].liquidity, 150)
        XCTAssertEqual(result[1].totalAssets, 150)
        XCTAssertEqual(result[1].netWorth, 150)
    }

    func testSkipsForeignCurrencyDeltaToAvoidMixingRateEpochs() {
        // A foreign-currency (converted, today-rate) delta must NOT be folded into history frozen at
        // other capture-time rates (deep-audit M22/M23); the retroactive mutation is skipped entirely
        // and the render-time reconversion handles display instead.
        let snaps = [
            NetWorthSnapshot(date: date(2026, 6, 20), totalAssets: 100, totalLiabilities: 0, netWorth: 100, liquidity: 100, investments: 0, crypto: 0)
        ]
        let result = engine.adjustingHistoricalSnapshots(snaps, from: date(2026, 6, 19), transactionCurrency: .usd, displayCurrency: .eur, liquidityDelta: 50)
        XCTAssertEqual(result[0].netWorth, 100, "foreign-currency delta is skipped, history unchanged")
        XCTAssertEqual(result[0].liquidity, 100)
    }
}
