import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var timeRange: TimeRange = .oneYear
    @State private var lastSnapshotAt: Date?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Dashboard", subtitle: "Financial Command Center") {
                    Button {
                        finance.takeSnapshot(settings: settings)
                        lastSnapshotAt = Date()
                    } label: {
                        Image(systemName: "camera")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                }

                if let lastSnapshotAt {
                    Text("Snapshot saved at \(lastSnapshotAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                }

                let totals = finance.calculateTotals(settings: settings)
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(title: "Net Worth", value: settings.privateCurrency(totals.netWorth), systemImage: "chart.line.uptrend.xyaxis")
                    MetricCard(title: "Cash Balance", value: settings.privateCurrency(totals.totalLiquidity), systemImage: "wallet.pass")
                    MetricCard(title: "Investments", value: settings.privateCurrency(totals.totalInvestments), systemImage: "chart.xyaxis.line", accent: .blue)
                    MetricCard(title: "Crypto", value: settings.privateCurrency(totals.totalCrypto), systemImage: "bitcoinsign.circle", accent: WCColor.warning)
                }

                netWorthHistory
                cashFlowTrend
                topExpenses
                AllocationChart(title: "Asset Allocation", slices: finance.assetAllocation(settings: settings), settings: settings)
            }
            .padding(16)
        }
        .pageChrome()
    }

    private var netWorthHistory: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Net Worth History")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Picker("Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                let points = finance.snapshots(range: timeRange)
                if points.isEmpty {
                    EmptyState(title: "Take a snapshot to build history", systemImage: "camera")
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Net Worth", point.value)
                        )
                        .foregroundStyle(WCColor.primary)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Net Worth", point.value)
                        )
                        .foregroundStyle(WCColor.primary.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis(settings.isPrivacyMode ? .hidden : .automatic)
                    .frame(height: 210)
                }
            }
        }
    }

    private var cashFlowTrend: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cash Flow Trend")
                    .font(.headline)
                    .foregroundStyle(.white)

                let trend = finance.cashFlowTrend(months: 6)
                Chart(trend) { month in
                    BarMark(
                        x: .value("Month", month.monthLabel),
                        y: .value("Income", month.income)
                    )
                    .foregroundStyle(WCColor.primary)
                    .position(by: .value("Type", "Income"))

                    BarMark(
                        x: .value("Month", month.monthLabel),
                        y: .value("Expense", month.expense)
                    )
                    .foregroundStyle(WCColor.destructive)
                    .position(by: .value("Type", "Expense"))
                }
                .chartYAxis(settings.isPrivacyMode ? .hidden : .automatic)
                .frame(height: 220)

                HStack(spacing: 16) {
                    Label("Income", systemImage: "circle.fill")
                        .foregroundStyle(WCColor.primary)
                    Label("Expense", systemImage: "circle.fill")
                        .foregroundStyle(WCColor.destructive)
                }
                .font(.caption)
            }
        }
    }

    private var topExpenses: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top Expenses")
                    .font(.headline)
                    .foregroundStyle(.white)

                let expenses = Array(finance.expensesByCategory(period: .thirtyDays).prefix(5))
                if expenses.isEmpty {
                    EmptyState(title: "No expenses in the last 30 days", systemImage: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 12) {
                        ForEach(expenses) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.name)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                ProgressView(value: item.percentage, total: 100)
                                    .tint(WCColor.destructive)
                            }
                        }
                    }
                }
            }
        }
    }
}
