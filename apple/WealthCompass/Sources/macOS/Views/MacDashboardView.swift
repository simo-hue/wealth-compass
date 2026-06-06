import Charts
import SwiftUI

struct MacDashboardView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var timeRange: TimeRange = .oneYear

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Dashboard", subtitle: "Your financial position at a glance") {
                    Picker("Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                let totals = finance.calculateTotals(settings: settings)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    MetricCard(
                        title: "Net Worth",
                        value: settings.privateCurrency(totals.netWorth),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    MetricCard(
                        title: "Cash Balance",
                        value: settings.privateCurrency(totals.totalLiquidity),
                        systemImage: "wallet.pass"
                    )
                    MetricCard(
                        title: "Investments",
                        value: settings.privateCurrency(totals.totalInvestments),
                        systemImage: "chart.xyaxis.line",
                        accent: .blue
                    )
                    MetricCard(
                        title: "Crypto",
                        value: settings.privateCurrency(totals.totalCrypto),
                        systemImage: "bitcoinsign.circle",
                        accent: WCColor.warning
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    netWorthChart
                    AllocationChart(
                        title: "Asset Allocation",
                        slices: finance.assetAllocation(settings: settings),
                        settings: settings
                    )
                    .frame(minWidth: 300, maxWidth: 380)
                }

                cashFlowChart
            }
            .padding(24)
            .frame(maxWidth: 1440, alignment: .leading)
        }
        .background(ScreenBackground())
        .navigationTitle("Dashboard")
    }

    private var netWorthChart: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Net Worth History")
                    .font(.headline)

                let points = finance.snapshots(range: timeRange)
                if points.isEmpty {
                    EmptyState(title: "History appears after your first update", systemImage: "chart.xyaxis.line")
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
                        .foregroundStyle(WCColor.primary.opacity(0.14))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis(settings.isPrivacyMode ? .hidden : .automatic)
                    .frame(height: 250)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cashFlowChart: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Six-Month Cash Flow")
                    .font(.headline)

                Chart(finance.cashFlowTrend()) { month in
                    BarMark(
                        x: .value("Month", month.monthLabel),
                        y: .value("Income", month.income)
                    )
                    .foregroundStyle(WCColor.primary)
                    .position(by: .value("Type", "Income"))

                    BarMark(
                        x: .value("Month", month.monthLabel),
                        y: .value("Expenses", month.expense)
                    )
                    .foregroundStyle(WCColor.destructive)
                    .position(by: .value("Type", "Expenses"))
                }
                .chartYAxis(settings.isPrivacyMode ? .hidden : .automatic)
                .frame(height: 230)
            }
        }
    }
}
