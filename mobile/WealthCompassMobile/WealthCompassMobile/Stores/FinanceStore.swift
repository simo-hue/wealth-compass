import Foundation
import SwiftUI

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var data = FinancialData()

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageURL = documents.appendingPathComponent("wealth-compass-local-data.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    var transactions: [Transaction] {
        data.transactions.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.createdAt > rhs.createdAt }
            return lhs.date > rhs.date
        }
    }

    func addTransaction(type: TransactionType, amount: Double, category: String, description: String, date: Date) {
        let transaction = Transaction(
            type: type,
            category: category,
            amount: amount,
            description: description,
            date: Calendar.current.startOfDay(for: date)
        )
        data.transactions.append(transaction)
        save()
    }

    func deleteTransaction(_ transaction: Transaction) {
        data.transactions.removeAll { $0.id == transaction.id }
        save()
    }

    func upsertInvestment(_ investment: Investment) {
        if let index = data.investments.firstIndex(where: { $0.id == investment.id }) {
            data.investments[index] = investment
        } else {
            data.investments.append(investment)
        }
        save()
    }

    func deleteInvestment(_ investment: Investment) {
        data.investments.removeAll { $0.id == investment.id }
        save()
    }

    func upsertCrypto(_ holding: CryptoHolding) {
        if let index = data.crypto.firstIndex(where: { $0.id == holding.id }) {
            data.crypto[index] = holding
        } else {
            data.crypto.append(holding)
        }
        save()
    }

    func deleteCrypto(_ holding: CryptoHolding) {
        data.crypto.removeAll { $0.id == holding.id }
        save()
    }

    func calculateTotals(settings: AppSettings) -> FinanceTotals {
        let income = data.transactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
        let expenses = data.transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }

        let totalLiquidity = income - expenses
        let totalInvestments = data.investments.reduce(0) {
            $0 + settings.convert($1.currentValue, from: $1.currency)
        }
        let totalCrypto = data.crypto.reduce(0) {
            $0 + settings.convert($1.currentValue, from: .usd)
        }
        let totalLiabilities = data.liabilities.reduce(0) {
            $0 + settings.convert($1.currentBalance, from: $1.currency)
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

    func takeSnapshot(settings: AppSettings) {
        let totals = calculateTotals(settings: settings)
        let snapshot = NetWorthSnapshot(
            date: Date(),
            totalAssets: totals.totalAssets,
            totalLiabilities: totals.totalLiabilities,
            netWorth: totals.netWorth,
            liquidity: totals.totalLiquidity,
            investments: totals.totalInvestments,
            crypto: totals.totalCrypto
        )
        data.snapshots.append(snapshot)
        data.snapshots.sort { $0.date < $1.date }
        save()
    }

    func monthlyCashFlow(for month: Date) -> MonthlyCashFlow {
        let calendar = Calendar.current
        let income = data.transactions
            .filter { $0.type == .income && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let expenses = data.transactions
            .filter { $0.type == .expense && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        return MonthlyCashFlow(monthlyIncome: income, monthlyExpenses: expenses)
    }

    func snapshots(range: TimeRange) -> [NetWorthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let cutoff: Date

        switch range {
        case .oneWeek:
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .oneMonth:
            cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        case .sixMonths:
            cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        case .oneYear:
            cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .all:
            cutoff = .distantPast
        }

        return data.snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { NetWorthPoint(date: $0.date, value: $0.netWorth) }
    }

    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        let calendar = Calendar.current
        let now = Date()
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

    func assetAllocation(settings: AppSettings) -> [AllocationSlice] {
        let totals = calculateTotals(settings: settings)
        return [
            AllocationSlice(name: "Investments", value: totals.totalInvestments, color: .blue),
            AllocationSlice(name: "Crypto", value: totals.totalCrypto, color: .orange),
            AllocationSlice(name: "Cash", value: totals.totalLiquidity, color: .green)
        ].filter { $0.value > 0 }
    }

    func investmentAllocation(settings: AppSettings) -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.sector)
            .mapValues { items in
                items.reduce(0) { partial, investment in
                    partial + settings.convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped.enumerated().map { index, item in
            AllocationSlice(name: item.key, value: item.value, color: ColorPalette.chart[index % ColorPalette.chart.count])
        }
        .sorted { $0.value > $1.value }
    }

    func cryptoAllocation(settings: AppSettings) -> [AllocationSlice] {
        data.crypto.enumerated().map { index, holding in
            AllocationSlice(
                name: holding.symbol,
                value: settings.convert(holding.currentValue, from: .usd),
                color: ColorPalette.chart[index % ColorPalette.chart.count]
            )
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
    }

    func clearData() {
        data = FinancialData()
        try? FileManager.default.removeItem(at: storageURL)
    }

    func exportBackupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "wealth-compass-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let payload = try encoder.encode(data)
        try payload.write(to: url, options: .atomic)
        return url
    }

    private func filteredTransactions(period: AnalyticsPeriod) -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let start: Date

        switch period {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        case .threeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: now) ?? .distantPast
        case .yearToDate:
            start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? .distantPast
        case .all:
            return data.transactions
        }

        return data.transactions.filter { $0.date >= start && $0.date <= now }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let payload = try Data(contentsOf: storageURL)
            data = try decoder.decode(FinancialData.self, from: payload)
        } catch {
            data = FinancialData()
        }
    }

    private func save() {
        do {
            let payload = try encoder.encode(data)
            try payload.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save local finance data: \(error)")
        }
    }
}
