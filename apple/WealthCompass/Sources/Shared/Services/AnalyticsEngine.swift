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
        let totalLiquidity = data.transactions.reduce(Decimal(0)) { result, transaction in
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
        return filtered.map { NetWorthPoint(date: $0.date, value: $0.netWorth.doubleValue) }
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

        return carryingForwardDailyGaps(points)
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
        return (minimum - padding)...(maximum + padding)
    }

    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"

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

    func assetAllocation() -> [AllocationSlice] {
        let totals = calculateTotals()
        return [
            AllocationSlice(name: localized("Investments"), value: totals.totalInvestments.doubleValue, color: .blue),
            AllocationSlice(name: localized("Crypto"), value: totals.totalCrypto.doubleValue, color: .orange),
            AllocationSlice(name: localized("Cash"), value: totals.totalLiquidity.doubleValue, color: .green)
        ].filter { $0.value > 0 }
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
                AllocationSlice(name: item.name, value: item.value.doubleValue, color: ColorPalette.chart[index % ColorPalette.chart.count])
            }
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
                    name: type.localizedTitle(appLanguage: appLanguage),
                    value: item.value.doubleValue,
                    color: ColorPalette.chartType[index % ColorPalette.chartType.count]
                )
            }
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
                AllocationSlice(name: item.name, value: item.value.doubleValue, color: ColorPalette.chartGeography[index % ColorPalette.chartGeography.count])
            }
    }

    func cryptoAllocation() -> [AllocationSlice] {
        data.crypto.enumerated().map { index, holding in
            AllocationSlice(
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
        return data.transactions.filter { $0.date >= start && $0.date <= now }
    }
}
