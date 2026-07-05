import Foundation

/// Pure net-worth snapshot math (M1 / M5 / T3).
///
/// Extracted from `FinanceStore` so the carry-forward backfill and retroactive
/// adjustment can be unit-tested without the `@MainActor` store. Every method is
/// referentially transparent: it takes the current snapshot array (+ inputs) and
/// returns a new array, leaving the caller to assign it back.
struct SnapshotEngine {
    var calendar: Calendar = .current

    /// Upserts a snapshot for `now`, replacing an existing same-day snapshot. No-activity days are
    /// **not** materialized here: a long absence used to spawn up to 60 carry-forward rows, each its
    /// own CloudKit record (WC-#11). The chart fills those flat gaps at render time instead
    /// (`AnalyticsEngine.snapshotsForChart`), so net-worth history stays continuous without storing —
    /// or syncing — a row per inactive day. Returned array is sorted ascending.
    func appendingSnapshot(
        to snapshots: [NetWorthSnapshot],
        totals: FinanceTotals,
        currency: Currency? = nil,
        now: Date = Date()
    ) -> [NetWorthSnapshot] {
        var snapshots = snapshots
        let snapshot = NetWorthSnapshot(
            date: now,
            totalAssets: totals.totalAssets,
            totalLiabilities: totals.totalLiabilities,
            netWorth: totals.netWorth,
            liquidity: totals.totalLiquidity,
            investments: totals.totalInvestments,
            crypto: totals.totalCrypto,
            // Stamp the base currency the totals were converted into (deep-audit H11), so a later
            // base-currency change reconverts this row instead of leaving it mis-scaled.
            currency: currency
        )

        if let lastIndex = snapshots.indices.last, calendar.isDate(snapshots[lastIndex].date, inSameDayAs: now) {
            snapshots[lastIndex] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        snapshots.sort { $0.date < $1.date }
        return snapshots
    }

    /// Applies a liquidity delta to every snapshot on/after `date` (retroactive edit).
    func adjustingHistoricalSnapshots(
        _ snapshots: [NetWorthSnapshot],
        from date: Date,
        liquidityDelta: Decimal
    ) -> [NetWorthSnapshot] {
        let startOfDay = calendar.startOfDay(for: date)
        var snapshots = snapshots
        for index in snapshots.indices where snapshots[index].date >= startOfDay {
            snapshots[index].liquidity += liquidityDelta
            snapshots[index].totalAssets += liquidityDelta
            snapshots[index].netWorth += liquidityDelta
        }
        return snapshots
    }
}
