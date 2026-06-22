import Foundation

/// Pure net-worth snapshot math (M1 / M5 / T3).
///
/// Extracted from `FinanceStore` so the carry-forward backfill and retroactive
/// adjustment can be unit-tested without the `@MainActor` store. Every method is
/// referentially transparent: it takes the current snapshot array (+ inputs) and
/// returns a new array, leaving the caller to assign it back.
struct SnapshotEngine {
    var calendar: Calendar = .current

    /// Maximum number of missing days to carry-forward-backfill, matching the
    /// recurring catch-up window (H7) so the two engines stay consistent.
    static let maxBackfillDays = 60

    /// Upserts a snapshot for `now` and carry-forward-backfills any missing days
    /// since the last snapshot (capped at `maxBackfillDays`). Returned array is sorted ascending.
    func appendingSnapshot(
        to snapshots: [NetWorthSnapshot],
        totals: FinanceTotals,
        now: Date = Date()
    ) -> [NetWorthSnapshot] {
        var snapshots = snapshots
        let today = calendar.startOfDay(for: now)

        if let lastSnapshot = snapshots.last {
            let lastSnapshotDate = calendar.startOfDay(for: lastSnapshot.date)
            if lastSnapshotDate < today {
                let components = calendar.dateComponents([.day], from: lastSnapshotDate, to: today)
                if let daysMissing = components.day, daysMissing > 0 {
                    let backfillDays = min(daysMissing, Self.maxBackfillDays)
                    for dayOffset in 1...backfillDays {
                        if let backfillDate = calendar.date(byAdding: .day, value: dayOffset, to: lastSnapshotDate),
                           backfillDate < today {
                            // End-of-day timestamp represents the closing balance.
                            var components = calendar.dateComponents([.year, .month, .day], from: backfillDate)
                            components.hour = 23
                            components.minute = 59
                            components.second = 59
                            let finalBackfillDate = calendar.date(from: components) ?? backfillDate
                            snapshots.append(
                                NetWorthSnapshot(
                                    date: finalBackfillDate,
                                    totalAssets: lastSnapshot.totalAssets,
                                    totalLiabilities: lastSnapshot.totalLiabilities,
                                    netWorth: lastSnapshot.netWorth,
                                    liquidity: lastSnapshot.liquidity,
                                    investments: lastSnapshot.investments,
                                    crypto: lastSnapshot.crypto
                                )
                            )
                        }
                    }
                }
            }
        }

        let snapshot = NetWorthSnapshot(
            date: now,
            totalAssets: totals.totalAssets,
            totalLiabilities: totals.totalLiabilities,
            netWorth: totals.netWorth,
            liquidity: totals.totalLiquidity,
            investments: totals.totalInvestments,
            crypto: totals.totalCrypto
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
        liquidityDelta: Double
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
