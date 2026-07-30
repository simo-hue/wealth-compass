import Foundation
import SwiftUI

/// Pure analytics over a `FinancialData` value (M1 / M3 / T5).
///
/// Extracted from `FinanceStore` so totals, cash-flow, category and allocation math
/// can be unit-tested without the `@MainActor` store or `AppSettings`. Currency is
/// resolved through an injected `CurrencyConverter` + `displayCurrency`; localized
/// slice labels through `appLanguage`. `now`/`calendar` are injectable for
/// deterministic tests.
struct AnalyticsEngine {
    let data: FinancialData
    // Currency context is only needed by the value/allocation methods; the cash-flow
    // and category methods operate on raw amounts, so these carry defaults to let
    // callers build a lightweight engine without settings.
    var converter: CurrencyConverter = CurrencyConverter(snapshot: nil)
    var displayCurrency: Currency = .eur
    var appLanguage: String? = nil
    var calendar: Calendar = .current
    var now: Date = Date()

    private func convert(_ value: Decimal, from currency: Currency) -> Decimal {
        converter.convert(value, from: currency, to: displayCurrency)
    }

    /// A transaction's amount expressed in the display currency (WC-M1). Legacy rows with no
    /// currency are treated as already in the display currency (no conversion) until
    /// `FinanceStore.load` backfills them to the base currency.
    private func displayAmount(_ transaction: Transaction) -> Decimal {
        converter.convert(transaction.amount, from: transaction.currency ?? displayCurrency, to: displayCurrency)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        AppLocalization.string(key, appLanguage: appLanguage)
    }

    func calculateTotals() -> FinanceTotals {
        // Exclude future-dated transactions from the live total (deep-audit L51): a transaction dated
        // ahead of today would otherwise inflate today's net worth (and its snapshot), while
        // adjustHistoricalSnapshots only shifts snapshots on/after that future date — an inconsistency.
        // Future-dating stays allowed; the amount lands in the total once its day arrives.
        let startOfToday = calendar.startOfDay(for: now)
        let totalLiquidity = data.transactions
            .filter { calendar.startOfDay(for: $0.date) <= startOfToday }
            .reduce(Decimal(0)) { result, transaction in
                switch transaction.type {
                case .income:  return result + displayAmount(transaction)
                case .expense: return result - displayAmount(transaction)
                }
            }
        let totalInvestments = data.investments.reduce(Decimal(0)) {
            $0 + convert($1.currentValue, from: $1.currency)
        }
        let totalCrypto = data.crypto.reduce(Decimal(0)) {
            $0 + convert($1.currentValue, from: $1.currency)
        }
        let totalLiabilities = data.liabilities.reduce(Decimal(0)) {
            $0 + convert($1.currentBalance, from: $1.currency)
        }
        let totalAssets = totalLiquidity + totalInvestments + totalCrypto

        return FinanceTotals(
            totalLiquidity: totalLiquidity,
            totalInvestments: totalInvestments,
            totalCrypto: totalCrypto,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: totalAssets - totalLiabilities
        )
    }

    func hasForeignCurrencyExposure(relativeTo baseCurrency: Currency) -> Bool {
        data.investments.contains { $0.currency != baseCurrency }
            || data.crypto.contains { $0.currency != baseCurrency }
            || data.liabilities.contains { $0.currency != baseCurrency }
    }

    func monthlyCashFlow(for month: Date) -> MonthlyCashFlow {
        let income = data.transactions
            .filter { $0.type == .income && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(Decimal(0)) { $0 + displayAmount($1) }
        let expenses = data.transactions
            .filter { $0.type == .expense && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(Decimal(0)) { $0 + displayAmount($1) }
        return MonthlyCashFlow(monthlyIncome: income, monthlyExpenses: expenses)
    }

    func snapshots(range: TimeRange) -> [NetWorthPoint] {
        let cutoff: Date
        switch range {
        case .oneWeek:   cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .oneMonth:  cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        case .sixMonths: cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        case .oneYear:   cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .all:       cutoff = .distantPast
        }

        let filtered = data.snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
        // Reconvert each stored value from the base currency it was captured in into the current
        // display currency (deep-audit H11). A legacy row with no captured currency is treated as
        // already in the display currency — mirroring `displayAmount` for transactions — so it is a
        // no-op until the load migration stamps it. Without this, changing the base currency left
        // the whole history at the old scale while today's live point jumped to the new one.
        return filtered.map { snapshot in
            let value = converter.convert(snapshot.netWorth, from: snapshot.currency ?? displayCurrency, to: displayCurrency)
            return NetWorthPoint(date: snapshot.date, value: value.doubleValue)
        }
    }

    /// Display-ready net-worth series: finite values only, one point per calendar day,
    /// and today's point aligned with the live total shown in the dashboard header.
    func snapshotsForChart(range: TimeRange, currentNetWorth: Double) -> [NetWorthPoint] {
        let finitePoints = snapshots(range: range).filter { $0.value.isFinite }

        var latestByDay: [Date: NetWorthPoint] = [:]
        for point in finitePoints {
            let day = calendar.startOfDay(for: point.date)
            if let existing = latestByDay[day] {
                if point.date > existing.date {
                    latestByDay[day] = point
                }
            } else {
                latestByDay[day] = point
            }
        }

        var points = latestByDay.values.sorted { $0.date < $1.date }

        if currentNetWorth.isFinite {
            if let lastIndex = points.indices.last,
               calendar.isDate(points[lastIndex].date, inSameDayAs: now) {
                points[lastIndex] = NetWorthPoint(date: now, value: currentNetWorth)
            } else {
                points.append(NetWorthPoint(date: now, value: currentNetWorth))
            }
        }

        return downsampled(carryingForwardDailyGaps(points))
    }

    /// Fills missing calendar days between the first and last point by carrying the previous day's
    /// value forward — reproducing the flat-during-inactivity net-worth line that materialized
    /// carry-forward snapshots used to give, but computed at render time instead of stored + synced
    /// (WC-#11). A line connecting only the real points would instead slope across a gap, implying a
    /// gradual change that never happened.
    private func carryingForwardDailyGaps(_ points: [NetWorthPoint]) -> [NetWorthPoint] {
        guard points.count > 1, let first = points.first, let last = points.last else { return points }
        let byDay = Dictionary(points.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
        var result: [NetWorthPoint] = []
        var cursor = calendar.startOfDay(for: first.date)
        let endDay = calendar.startOfDay(for: last.date)
        var lastValue = first.value
        while cursor <= endDay {
            if let real = byDay[cursor] {
                result.append(real)
                lastValue = real.value
            } else {
                result.append(NetWorthPoint(date: cursor, value: lastValue))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Caps the plotted point count so a multi-year `.all` range doesn't hand Swift Charts thousands
    /// of marks (deep-audit M15/M16). A series already at/under `maxPoints` is returned unchanged so
    /// day-level detail is kept for the short ranges; a longer span is strided, always keeping the
    /// first and last points so the line still starts at account history and ends at today. Striding
    /// a mostly-flat carry-forward series barely shifts the step positions, so the shape is preserved.
    private func downsampled(_ points: [NetWorthPoint], maxPoints: Int = 365) -> [NetWorthPoint] {
        guard points.count > maxPoints else { return points }
        let step = Int((Double(points.count) / Double(maxPoints)).rounded(.up))
        guard step > 1 else { return points }
        var result: [NetWorthPoint] = []
        result.reserveCapacity(points.count / step + 2)
        var index = 0
        while index < points.count {
            result.append(points[index])
            index += step
        }
        if let last = points.last, result.last?.date != last.date {
            result.append(last)
        }
        return result
    }

    /// Padded y-axis domain for the net-worth chart, hardened against non-finite input: a single
    /// NaN/Inf value would otherwise make `min()`/`max()` yield NaN and constructing the
    /// `ClosedRange` *trap* (crash), not merely warn (WC-#16). Empty or all-non-finite input falls
    /// back to a safe default. Pure + `static` so the guard is unit-tested and shared by both
    /// dashboards instead of duplicated.
    static func chartYDomain(for points: [NetWorthPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        let spread = max(maximum - minimum, max(abs(maximum), 1) * 0.08)
        let padding = spread * 0.18
        let lower = minimum - padding
        let upper = maximum + padding
        // L31: guarantee a minimum readable domain height so an all-zero series (new user) or a
        // near-zero net worth doesn't over-zoom into a sub-penny hairline axis (e.g. -0.01…0.01).
        // Normal series (height already ≥ minHeight) are returned unchanged.
        let minHeight = 2.0
        guard upper - lower < minHeight else { return lower...upper }
        let center = (lower + upper) / 2
        return (center - minHeight / 2)...(center + minHeight / 2)
    }

    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        // Bucket in the engine's own time zone (deep-audit L32) so a boundary-dated transaction lands
        // in the same month here as it does in monthlyCashFlow's calendar-granularity comparison; an
        // unpinned formatter defaults to the system zone and diverges under an injected calendar.
        monthFormatter.timeZone = calendar.timeZone
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"
        labelFormatter.timeZone = calendar.timeZone

        return stride(from: months - 1, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let monthKey = monthFormatter.string(from: date)
            let transactions = data.transactions.filter { monthFormatter.string(from: $0.date) == monthKey }
            let income = transactions.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + displayAmount($1) }
            let expense = transactions.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + displayAmount($1) }

            return CashFlowMonth(
                monthKey: monthKey,
                monthLabel: labelFormatter.string(from: date),
                income: income.doubleValue,
                expense: expense.doubleValue
            )
        }
    }

    func expensesByCategory(period: AnalyticsPeriod) -> [CategoryTotal] {
        let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + displayAmount($1) } }
            // `Decimal` addition *returns NaN* on overflow rather than trapping, so a single absurd
            // imported amount produced a category whose value and percentage were both NaN — and
            // these feed `SectorMark` geometry directly. One NaN in a chart is the exact failure
            // the guards in `AppSettings.convert` exist to prevent. `sankeyCategoryTotals` already
            // filters this way; only finiteness is screened here, because dropping non-positive
            // categories as well would change which wedges appear, which is a separate decision.
            .filter { $0.value.isFinite }
        // Summed from the filtered set, so the percentages still add to 100 once a bad category
        // has been dropped.
        let total = grouped.values.reduce(Decimal(0), +)

        return grouped.map { key, value in
            CategoryTotal(
                name: key,
                value: value.doubleValue,
                percentage: total > 0 ? (value.doubleValue / total.doubleValue) * 100 : 0
            )
        }
        .sorted { $0.value > $1.value }
    }

    // MARK: - Money Flow (Sankey)

    /// The Money Flow model for a period: income categories → a single hub → expense categories,
    /// with the imbalance absorbed by one synthetic node so the diagram conserves flow.
    ///
    /// Two deliberate departures from `expensesByCategory`:
    ///
    /// 1. Future-dated rows are clamped on *every* period, `.all` included.
    ///    `filteredTransactions(period: .all)` returns the raw array, which would let a post-dated
    ///    recurring occurrence widen a ribbon for money that hasn't moved — and desynchronize the
    ///    diagram from `calculateTotals`, which has excluded the future since deep-audit L51.
    /// 2. Percentages are of the whole diagram, not of one column, because the detail row reads
    ///    "N% of cash flow" for income and expense nodes alike.
    func cashFlowSankey(period: AnalyticsPeriod, maxNodesPerSide: Int = 7) -> CashFlowSankey {
        let today = calendar.startOfDay(for: now)
        let transactions = filteredTransactions(period: period)
            .filter { calendar.startOfDay(for: $0.date) <= today }
        return cashFlowSankey(transactions: transactions, maxNodesPerSide: maxNodesPerSide)
    }

    /// Builds the diagram from an explicit transaction set.
    ///
    /// The PDF report needs this: it bounds its ledger by the *export's* date range, and feeding it
    /// an `AnalyticsPeriod` window instead would make the diagram contradict the rest of the
    /// document — the same trap `ReportDocumentBuilder` already documents for
    /// `expensesByCategory(period:)`. Future-dating is the caller's call here, since a historical
    /// range has no "future" to clamp.
    func cashFlowSankey(transactions: [Transaction], maxNodesPerSide: Int = 7) -> CashFlowSankey {
        let hubTitle = localized("Cash Flow")

        let incomeTotals = sankeyCategoryTotals(transactions, type: .income)
        let expenseTotals = sankeyCategoryTotals(transactions, type: .expense)
        let totalIncome = incomeTotals.reduce(0) { $0 + $1.value }
        let totalExpense = expenseTotals.reduce(0) { $0 + $1.value }
        let total = max(totalIncome, totalExpense)
        guard total.isFinite, total > 0 else { return .empty(hubTitle: hubTitle) }

        var inflows = sankeyNodes(from: incomeTotals, role: .income, maxNodes: maxNodesPerSide, total: total)
        var outflows = sankeyNodes(from: expenseTotals, role: .expense, maxNodes: maxNodesPerSide, total: total)

        // At most one of these fires, and it is what makes the two columns sum to the same number.
        // Both are appended rather than sorted in, so they sit at the bottom of their column at
        // every period instead of migrating as their size changes.
        //
        // The threshold is *relative*, not a fixed number of cents, and it has to be: both totals
        // are Doubles summed from many Decimals, so the summation residue scales with the total.
        // A fixed half-cent floor is simultaneously too coarse for a €0.006 month — where a real
        // €0.004 imbalance is two thirds of the diagram — and too fine at €1e14, where pure float
        // noise exceeds it and would draw a hairline ribbon labelled "€0.00". A relative floor is
        // correct at every magnitude; 1e-9 sits ~six orders above the per-operation residue.
        let imbalance = totalIncome - totalExpense
        let noiseFloor = total * 1e-9
        if imbalance < -noiseFloor {
            inflows.append(
                CashFlowSankeyNode(
                    id: "shortfall",
                    title: localized("Drawn from Savings"),
                    // `total - totalIncome` rather than `-imbalance`: the column's job is to reach
                    // the hub, so compute it from the hub.
                    value: total - totalIncome,
                    role: .shortfall,
                    share: sankeyShare(total - totalIncome, of: total),
                    colorIndex: nil,
                    categories: [],
                    folded: []
                )
            )
        } else if imbalance > noiseFloor {
            outflows.append(
                CashFlowSankeyNode(
                    id: "surplus",
                    title: localized("Surplus"),
                    value: total - totalExpense,
                    role: .surplus,
                    share: sankeyShare(total - totalExpense, of: total),
                    colorIndex: nil,
                    categories: [],
                    folded: []
                )
            )
        } else {
            // Below the floor the two columns are equal to every digit that matters — but `total`
            // still took the larger of the two Doubles, so the shorter column would fall a residue
            // short of the hub. The layout stacks ribbons against the hub edge by cursor, so that
            // residue renders as a literal bare stretch of hub. Push it onto the column's largest
            // node: invisible by construction, and `inflows.sum == hub == outflows.sum` holds
            // exactly, which is what both the model contract and `SankeyLayout` are written against.
            inflows = absorbingResidue(inflows, upTo: total)
            outflows = absorbingResidue(outflows, upTo: total)
        }

        let hub = CashFlowSankeyNode(
            id: "hub",
            title: hubTitle,
            value: total,
            role: .hub,
            share: 100,
            colorIndex: nil,
            categories: [],
            folded: []
        )

        let links = inflows.map { CashFlowSankeyLink(sourceID: $0.id, targetID: hub.id, value: $0.value) }
            + outflows.map { CashFlowSankeyLink(sourceID: hub.id, targetID: $0.id, value: $0.value) }

        return CashFlowSankey(inflows: inflows, hub: hub, outflows: outflows, links: links)
    }

    /// Per-category totals for one transaction type, in display currency, largest first.
    ///
    /// Non-positive and non-finite totals are dropped *here* rather than at render time so the
    /// column sums downstream are computed from exactly the rows that will be drawn. Filtering
    /// later would leave the columns no longer summing to the hub, and the ribbons would stop
    /// meeting its edge.
    private func sankeyCategoryTotals(
        _ transactions: [Transaction],
        type: TransactionType
    ) -> [(name: String, value: Double)] {
        Dictionary(grouping: transactions.filter { $0.type == type }, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + displayAmount($1) } }
            .map { (name: $0.key, value: $0.value.doubleValue) }
            .filter { $0.value.isFinite && $0.value > 0 }
            .sorted { lhs, rhs in
                // Tie-break by name so identical data never reshuffles between renders — otherwise
                // two equal-value categories could swap places and SwiftUI would animate a
                // meaningless move.
                lhs.value == rhs.value ? lhs.name < rhs.name : lhs.value > rhs.value
            }
    }

    /// Ranks one column's categories, folding everything past `maxNodes` into a single bucket.
    ///
    /// A lone leftover is deliberately *not* folded: replacing one category with "Smaller
    /// categories" hides its name and buys no room, so `maxNodes + 1` categories all keep their
    /// own node. The bucket is named for why it exists rather than what it contains, because
    /// "Other" is already a real category on both sides — it is the fallback every import path
    /// writes for a missing category, so on imported data it is often one of the largest.
    ///
    /// (A user *can* still create a custom category literally named "Smaller categories", which
    /// would render two same-titled boxes. Their ids and values differ so nothing breaks; it is
    /// left alone as a cosmetic edge rather than reserving a name in the user's vocabulary.)
    private func sankeyNodes(
        from totals: [(name: String, value: Double)],
        role: CashFlowSankeyRole,
        maxNodes: Int,
        total: Double
    ) -> [CashFlowSankeyNode] {
        guard !totals.isEmpty else { return [] }
        let limit = max(1, maxNodes)

        func node(_ item: (name: String, value: Double), colorIndex: Int) -> CashFlowSankeyNode {
            CashFlowSankeyNode(
                // The `-cat-` segment keeps real categories out of the synthetic id namespace: a
                // category named "folded" would otherwise collide with the bucket, and since a
                // link's id is derived from its endpoints', the *ribbons* would collide too —
                // `ForEach` would silently drop one and real money would vanish from the diagram.
                id: "\(role.rawValue)-cat-\(item.name)",
                // Imports only default a *nil* category to "Other" (FinanceImportService), so a
                // present-but-blank one survives into the data and would draw an unlabelled box
                // with an empty VoiceOver label. `categories` deliberately keeps the raw value so
                // the drill-through filter still matches what is stored.
                title: item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? localized("Uncategorized")
                    : item.name,
                value: item.value,
                role: role,
                share: sankeyShare(item.value, of: total),
                colorIndex: colorIndex,
                categories: [item.name],
                folded: []
            )
        }

        // `totals.count - 1 > limit`, not `totals.count > limit + 1`: a caller passing `Int.max`
        // as a "never fold" sentinel would overflow the addition and trap. `totals` is guarded
        // non-empty above, so the subtraction cannot underflow.
        guard totals.count - 1 > limit else {
            return totals.enumerated().map { node($1, colorIndex: $0) }
        }

        let kept = totals.prefix(limit).enumerated().map { node($1, colorIndex: $0) }
        let remainder = Array(totals.dropFirst(limit))
        let foldedValue = remainder.reduce(0) { $0 + $1.value }
        let bucket = CashFlowSankeyNode(
            id: "\(role.rawValue)-folded",
            title: localized("Smaller categories"),
            value: foldedValue,
            role: role,
            share: sankeyShare(foldedValue, of: total),
            // Not a palette slot: the bucket renders neutral, so it never competes with a real
            // category for attention.
            colorIndex: nil,
            categories: remainder.map(\.name),
            folded: remainder.map {
                CategoryTotal(name: $0.name, value: $0.value, percentage: sankeyShare($0.value, of: total))
            }
        )
        return kept + [bucket]
    }

    /// Tops up a column's largest node so the column sums to exactly `total`.
    ///
    /// Only called when the imbalance is already below the noise floor, so the adjustment is
    /// invisible — its job is purely to keep the ribbons meeting the hub edge with no gap.
    private func absorbingResidue(
        _ column: [CashFlowSankeyNode],
        upTo total: Double
    ) -> [CashFlowSankeyNode] {
        guard let largest = column.first else { return column }
        let residue = total - column.reduce(0) { $0 + $1.value }
        guard residue != 0, residue.isFinite else { return column }
        var adjusted = column
        // `column` is sorted descending, so index 0 absorbs it with the least relative distortion.
        adjusted[0] = CashFlowSankeyNode(
            id: largest.id,
            title: largest.title,
            value: largest.value + residue,
            role: largest.role,
            share: sankeyShare(largest.value + residue, of: total),
            colorIndex: largest.colorIndex,
            categories: largest.categories,
            folded: largest.folded
        )
        return adjusted
    }

    /// Percent of the diagram total, hardened against the zero/NaN cases that would otherwise
    /// reach chart geometry.
    private func sankeyShare(_ value: Double, of total: Double) -> Double {
        guard total.isFinite, total > 0, value.isFinite else { return 0 }
        return (value / total) * 100
    }

    func assetAllocation() -> [AllocationSlice] {
        let totals = calculateTotals()
        return [
            AllocationSlice(id: "asset-investments", name: localized("Investments"), value: totals.totalInvestments.doubleValue, color: .blue),
            AllocationSlice(id: "asset-crypto", name: localized("Crypto"), value: totals.totalCrypto.doubleValue, color: .orange),
            AllocationSlice(id: "asset-cash", name: localized("Cash"), value: totals.totalLiquidity.doubleValue, color: .green)
        ]
        // L33: a pie can't render a negative wedge, so net-negative cash is clamped out here. The
        // dashboards surface a footnote quantifying the excluded liability (see
        // `FinanceStore.assetAllocationExcludedCash`) so the ring total's gap to the net-worth header
        // is explained rather than silent.
        .filter { $0.value > 0 }
    }

    func investmentAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.sector)
            .mapValues { items in
                items.reduce(Decimal(0)) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                AllocationSlice(id: item.name, name: item.name, value: item.value.doubleValue, color: ColorPalette.chart[index % ColorPalette.chart.count])
            }
            .filter { $0.value > 0 }
    }

    func investmentTypeAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: { $0.type.rawValue })
            .mapValues { items in
                items.reduce(Decimal(0)) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                let type = InvestmentType(rawValue: item.name) ?? .other
                return AllocationSlice(
                    id: item.name,
                    name: type.localizedTitle(appLanguage: appLanguage),
                    value: item.value.doubleValue,
                    color: ColorPalette.chartType[index % ColorPalette.chartType.count]
                )
            }
            .filter { $0.value > 0 }
    }

    func investmentGeographyAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.geography)
            .mapValues { items in
                items.reduce(Decimal(0)) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                AllocationSlice(id: item.name, name: item.name, value: item.value.doubleValue, color: ColorPalette.chartGeography[index % ColorPalette.chartGeography.count])
            }
            .filter { $0.value > 0 }
    }

    func cryptoAllocation() -> [AllocationSlice] {
        data.crypto.enumerated().map { index, holding in
            AllocationSlice(
                id: holding.id.uuidString,
                name: holding.symbol,
                value: convert(holding.currentValue, from: holding.currency).doubleValue,
                color: ColorPalette.chart[index % ColorPalette.chart.count]
            )
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
    }

    private func filteredTransactions(period: AnalyticsPeriod) -> [Transaction] {
        let start: Date
        switch period {
        case .sevenDays:  start = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays: start = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: now) ?? .distantPast
        case .yearToDate: start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? .distantPast
        case .all:        return data.transactions
        }
        // Compare at calendar-day granularity in the engine's own calendar (deep-audit L05): the
        // boundaries and the startOfDay-stored transaction dates then stay aligned even after a
        // timezone/DST shift, instead of dropping day-boundary items when a raw-instant boundary
        // lands mid-day.
        let startOfDay = calendar.startOfDay(for: start)
        let endOfDay = calendar.startOfDay(for: now)
        return data.transactions.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= startOfDay && day <= endOfDay
        }
    }
}
