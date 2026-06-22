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

    private func convert(_ value: Double, from currency: Currency) -> Double {
        converter.convert(value, from: currency, to: displayCurrency)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        AppLocalization.string(key, appLanguage: appLanguage)
    }

    func calculateTotals() -> FinanceTotals {
        let totalLiquidity = data.transactions.reduce(into: 0.0) { result, transaction in
            switch transaction.type {
            case .income:  result += transaction.amount
            case .expense: result -= transaction.amount
            }
        }
        let totalInvestments = data.investments.reduce(0) {
            $0 + convert($1.currentValue, from: $1.currency)
        }
        let totalCrypto = data.crypto.reduce(0) {
            $0 + convert($1.currentValue, from: $1.currency)
        }
        let totalLiabilities = data.liabilities.reduce(0) {
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
            .reduce(0) { $0 + $1.amount }
        let expenses = data.transactions
            .filter { $0.type == .expense && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
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

        return data.snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { NetWorthPoint(date: $0.date, value: $0.netWorth) }
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
            let income = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let expense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

            return CashFlowMonth(
                monthKey: monthKey,
                monthLabel: labelFormatter.string(from: date),
                income: income,
                expense: expense
            )
        }
    }

    func expensesByCategory(period: AnalyticsPeriod) -> [CategoryTotal] {
        let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let total = grouped.values.reduce(0, +)

        return grouped.map { key, value in
            CategoryTotal(name: key, value: value, percentage: total > 0 ? (value / total) * 100 : 0)
        }
        .sorted { $0.value > $1.value }
    }

    func spendingTimeline(period: AnalyticsPeriod) -> [CategoryTotal] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses) { formatter.string(from: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        return grouped.map { CategoryTotal(name: $0.key, value: $0.value, percentage: 0) }
            .sorted { $0.name < $1.name }
    }

    func assetAllocation() -> [AllocationSlice] {
        let totals = calculateTotals()
        return [
            AllocationSlice(name: localized("Investments"), value: totals.totalInvestments, color: .blue),
            AllocationSlice(name: localized("Crypto"), value: totals.totalCrypto, color: .orange),
            AllocationSlice(name: localized("Cash"), value: totals.totalLiquidity, color: .green)
        ].filter { $0.value > 0 }
    }

    func investmentAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.sector)
            .mapValues { items in
                items.reduce(0) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                AllocationSlice(name: item.name, value: item.value, color: ColorPalette.chart[index % ColorPalette.chart.count])
            }
    }

    func investmentTypeAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: { $0.type.rawValue })
            .mapValues { items in
                items.reduce(0) { partial, investment in
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
                    value: item.value,
                    color: ColorPalette.chartType[index % ColorPalette.chartType.count]
                )
            }
    }

    func investmentGeographyAllocation() -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.geography)
            .mapValues { items in
                items.reduce(0) { partial, investment in
                    partial + convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, item in
                AllocationSlice(name: item.name, value: item.value, color: ColorPalette.chartGeography[index % ColorPalette.chartGeography.count])
            }
    }

    func cryptoAllocation() -> [AllocationSlice] {
        data.crypto.enumerated().map { index, holding in
            AllocationSlice(
                name: holding.symbol,
                value: convert(holding.currentValue, from: holding.currency),
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
