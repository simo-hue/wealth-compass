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

    /// A corrected snapshot has to advertise that it was corrected.
    ///
    /// `updatedAt` is the primary key of both `NetWorthSnapshot.supersedesForCollapse` and
    /// `Array.mergedByID`, so a row this pass rewrites while leaving its timestamp alone still
    /// claims its pre-correction age — and loses the same-day collapse, and the merge, to a stale
    /// copy carrying the very figures this call just corrected. `backfillingCurrencies` already
    /// found and fixed exactly this for itself (note `#9b`).
    ///
    /// One `now` for the whole pass, for the reason that note gives: rows adjusted together must
    /// stay tied on `updatedAt` and fall through to `date`/`id` as before, rather than being
    /// ordered by nothing but the loop's iteration order.
    func testARetroactiveAdjustmentStampsEveryRowItRewrites() {
        let stamp = date(2026, 7, 1)
        let untouchedAt = date(2026, 1, 1)
        func row(_ on: Date) -> NetWorthSnapshot {
            NetWorthSnapshot(
                date: on, totalAssets: 100, totalLiabilities: 0, netWorth: 100,
                liquidity: 100, investments: 0, crypto: 0, currency: .eur,
                createdAt: untouchedAt, updatedAt: untouchedAt
            )
        }
        let snaps = [row(date(2026, 6, 18)), row(date(2026, 6, 20)), row(date(2026, 6, 21))]

        let result = engine.adjustingHistoricalSnapshots(
            snaps, from: date(2026, 6, 19),
            transactionCurrency: .eur, displayCurrency: .eur, liquidityDelta: 50, now: stamp
        )

        XCTAssertEqual(
            result[0].updatedAt, untouchedAt,
            "a row before the cutoff was not rewritten, so its timestamp must not move either"
        )
        XCTAssertEqual(
            [result[1].updatedAt, result[2].updatedAt], [stamp, stamp],
            """
            A rewritten snapshot kept its old `updatedAt`, so it still advertises its \
            pre-correction age. `supersedesForCollapse` and `mergedByID` both key on that field, \
            so the corrected row loses to a stale copy of itself.
            """
        )
        XCTAssertEqual(
            result[1].createdAt, untouchedAt,
            "`createdAt` is the row's birthday and an adjustment is not a birth"
        )
    }

    /// Changing only a transaction's *currency* must leave stored history alone.
    ///
    /// `updateTransaction` reverses the old row and re-applies the new one as two independent calls
    /// to `adjustHistoricalSnapshots`, and the engine's foreign-delta guard is a deliberate no-op
    /// per leg. That guard is right per leg and wrong per pair: when the currency is what changed,
    /// exactly one leg passes it, so the reversal and the re-application no longer cancel. Every
    /// stored snapshot on/after the date moves by the full amount and stays wrong, while today's
    /// figure is recomputed from the ledger and is right — which is how the Dashboard header and
    /// the chart behind it end up disagreeing.
    ///
    /// Every other edit (amount, date, type, category) is safe because both legs take the same
    /// branch, and `deleteTransaction` is a single leg. This is the pair case, so it goes through
    /// the store rather than the engine.
    @MainActor
    func testChangingOnlyATransactionsCurrencyLeavesStoredHistoryAlone() {
        let settings = AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
        settings.currency = .eur

        let when = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let transaction = Transaction(
            type: .expense, category: "Food", amount: 100, description: "lunch",
            date: when, currency: .eur
        )
        let history = NetWorthSnapshot(
            date: when, totalAssets: 1_000, totalLiabilities: 0, netWorth: 1_000,
            liquidity: 1_000, investments: 0, crypto: 0, currency: .eur
        )
        let store = FinanceStore(
            persistence: SnapshotSeededPersistence(
                FinancialData(transactions: [transaction], snapshots: [history])
            ),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )

        store.updateTransaction(
            transaction, type: .expense, amount: 100, category: "Food",
            description: "lunch", date: when, currency: .usd, settings: settings
        )

        let stored = store.data.snapshots.first { $0.id == history.id }
        XCTAssertEqual(
            stored?.liquidity, 1_000,
            """
            Switching a transaction's currency reversed it out of history in the old currency and \
            never re-applied it in the new one, so every snapshot from that date on moved by the \
            full amount and stayed there. A currency change must run both legs or neither.
            """
        )
        XCTAssertEqual(stored?.netWorth, 1_000)
        XCTAssertEqual(stored?.totalAssets, 1_000)
    }

    /// The other direction of the same edit: **foreign → base** must not double-count.
    ///
    /// The test above only covers base → foreign, where the old two-leg code *removed* the row from
    /// history. The mirror case is the one the "history holds base-currency rows only" reading gets
    /// wrong, so it is the one worth pinning: a foreign transaction entered on the day it happened
    /// **is** in stored history, because `appendSnapshot` recomputes the day's row from
    /// `AnalyticsEngine.calculateTotals`, which converts and sums *every* settled transaction
    /// whatever its currency. `adjustingHistoricalSnapshots`' foreign guard refuses only the
    /// *retroactive* patch of an already-frozen row; it does not keep foreign money out of history.
    ///
    /// So re-applying the base-currency leg on its own does not "add a row that was missing" — it
    /// adds a second copy of a row that is already there. Here the stored day already carries the
    /// USD expense (1 000 − 92 = 908); running leg 2 alone would take it to 808 and leave it there
    /// for good, while today's figure, recomputed from the ledger, stays right.
    @MainActor
    func testChangingATransactionFromAForeignCurrencyToTheBaseDoesNotDoubleCountIt() {
        let settings = AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
        settings.currency = .eur

        let when = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let transaction = Transaction(
            type: .expense, category: "Food", amount: 100, description: "lunch",
            date: when, currency: .usd
        )
        // 1 000 minus the USD expense as that day's snapshot already recorded it.
        let history = NetWorthSnapshot(
            date: when, totalAssets: 908, totalLiabilities: 0, netWorth: 908,
            liquidity: 908, investments: 0, crypto: 0, currency: .eur
        )
        let store = FinanceStore(
            persistence: SnapshotSeededPersistence(
                FinancialData(transactions: [transaction], snapshots: [history])
            ),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )

        store.updateTransaction(
            transaction, type: .expense, amount: 100, category: "Food",
            description: "lunch", date: when, currency: .eur, settings: settings
        )

        let stored = store.data.snapshots.first { $0.id == history.id }
        XCTAssertEqual(
            stored?.liquidity, 908,
            """
            Re-applying the base-currency leg without reversing the foreign one booked the expense \
            into history a second time: the day fell to 808 and stayed there, while today's figure \
            — recomputed from the ledger — stayed correct. A currency change runs both legs or \
            neither.
            """
        )
        XCTAssertEqual(stored?.netWorth, 908)
        XCTAssertEqual(stored?.totalAssets, 908)
    }

    /// The premise the whole `canAdjust` decision rests on, pinned so it cannot drift.
    ///
    /// It is tempting to read `adjustingHistoricalSnapshots`' foreign-currency guard as an
    /// invariant — "stored history holds base-currency transactions only" — and to conclude from it
    /// that a currency edit is a *membership* change: remove the row's effect when it leaves the
    /// base-currency set, add it when it joins. That reading is false in both halves, and this test
    /// is the two measurements that show it.
    ///
    /// 1. **Foreign money is in stored history.** The guard refuses only the *retroactive patch* of
    ///    an already-frozen row. A transaction entered on the day it happened reaches history
    ///    through `appendSnapshot`, which rewrites the day's row from
    ///    `AnalyticsEngine.calculateTotals` — and that converts and sums every settled transaction
    ///    whatever its currency. So the USD row below is in the stored snapshot, at ~92 EUR.
    /// 2. **Nothing puts it there again at render time.** `AnalyticsEngine.snapshots(range:)`
    ///    reconverts each stored row's own frozen base currency into the display currency and never
    ///    walks `data.transactions`; `snapshotsForChart` adds only *today's* live figure on top of
    ///    that. A 999,999 USD transaction dated on a historical day moves that day's plotted point
    ///    by nothing at all.
    ///
    /// Together they say a currency edit is not a membership change: history already carries one
    /// representation of the row, so running one leg of the pair erases it or duplicates it. That
    /// is why `updateTransaction` runs both legs or neither.
    @MainActor
    func testForeignMoneyIsInStoredHistoryAndNothingReAddsItAtRenderTime() throws {
        let settings = AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
        settings.currency = .eur

        // 1. A USD row dated today lands in today's stored snapshot, converted.
        let live = FinanceStore(
            persistence: SnapshotSeededPersistence(FinancialData()),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )
        live.addTransaction(
            type: .expense, amount: 100, category: "Food", description: "lunch",
            date: Date(), currency: .usd, settings: settings
        )
        let today = try XCTUnwrap(live.data.snapshots.max { $0.date < $1.date })
        XCTAssertTrue(
            today.liquidity < -80 && today.liquidity > -100,
            """
            A foreign transaction dated today left no mark on the stored snapshot (liquidity \
            \(today.liquidity)). If that ever becomes true, "history holds base-currency rows \
            only" becomes the real invariant and `updateTransaction`'s paired guard has to be \
            revisited.
            """
        )

        // 2. No reader re-adds a transaction to a historical point.
        let when = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        )
        let frozen = NetWorthSnapshot(
            date: when, totalAssets: 1_000, totalLiabilities: 0, netWorth: 1_000,
            liquidity: 1_000, investments: 0, crypto: 0, currency: .eur
        )
        let rendered = FinanceStore(
            persistence: SnapshotSeededPersistence(FinancialData(
                transactions: [Transaction(
                    type: .expense, category: "Food", amount: 999_999,
                    description: "huge", date: when, currency: .usd
                )],
                snapshots: [frozen]
            )),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )
        let historical = rendered.snapshotsForChart(range: .all, settings: settings)
            .first { Calendar.current.isDate($0.date, inSameDayAs: when) }
        XCTAssertEqual(
            try XCTUnwrap(historical).value, 1_000, accuracy: 0.001,
            """
            A historical chart point moved when a foreign transaction dated that day was present, \
            so something re-adds transactions to stored history at render time after all. The \
            "left to render-time reconversion" reading of the engine's guard would then be real, \
            and every conclusion drawn from its absence has to be re-derived.
            """
        )
    }
}

/// An in-memory `FinancePersistence` preloaded with one dataset, so `FinanceStore.init` — which
/// loads synchronously — comes up with a ledger and a snapshot history already in it.
private final class SnapshotSeededPersistence: FinancePersistence, @unchecked Sendable {
    private var stored: FinancialData?
    init(_ data: FinancialData) { stored = data }
    var locationDescription: String { "in-memory (snapshot engine test)" }
    func load() throws -> FinancePersistenceLoad? { stored.map { FinancePersistenceLoad(data: $0) } }
    func save(_ data: FinancialData) throws { stored = data }
    func clear() throws { stored = nil }
}
