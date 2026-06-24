import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var timeRange: TimeRange = .oneYear
    @State private var showingAddTransaction = false
    @State private var selectedNetWorthDate: Date?
    @ScaledMetric(relativeTo: .largeTitle) private var netWorthSize: CGFloat = 35

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var totals: FinanceTotals {
        finance.calculateTotals(settings: settings)
    }

    private var currentMonthCashFlow: MonthlyCashFlow {
        finance.monthlyCashFlow(for: Date())
    }

    private var isCompletelyEmpty: Bool {
        finance.data.transactions.isEmpty
            && finance.data.investments.isEmpty
            && finance.data.crypto.isEmpty
            && finance.data.liabilities.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardHeader

                if isCompletelyEmpty {
                    onboardingCard
                }

                netWorthHero
                positionSection
                cashFlowTrend
                AllocationChart(
                    title: "Asset Allocation",
                    slices: finance.assetAllocation(settings: settings),
                    settings: settings
                )
                topExpenses
                recentActivity
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .pageChrome()
        .sheet(isPresented: $showingAddTransaction) {
            TransactionFormView { _, type, amount, category, description, date in
                finance.addTransaction(
                    type: type,
                    amount: amount,
                    category: category,
                    description: description,
                    date: date,
                    settings: settings
                )
            }
        }
    }

    private var dashboardHeader: some View {
        PageHeader(
            title: "Financial horizon",
            subtitle: "Everything you own, owe, earn, and spend."
        ) {
            PrimaryActionButton(systemImage: "plus", accessibilityLabel: "Add Transaction") {
                showingAddTransaction = true
            }
        }
    }

    private var onboardingCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WCColor.primary)
                        .frame(width: 38, height: 38)
                        .background(WCColor.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build your first financial view")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Record cash flow or add a position to bring this dashboard to life.")
                            .font(.caption)
                            .foregroundStyle(WCColor.textTertiary)
                    }
                }

                Button {
                    showingAddTransaction = true
                } label: {
                    Label("Add your first transaction", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WCColor.primary)
            }
        }
    }

    private var netWorthHero: some View {
        let points = finance.snapshotsForChart(range: timeRange, settings: settings)
        let rangeChange = netWorthChange(in: points)
        let yDomain = chartDomain(for: points)

        return FinanceCard {
            ZStack {
                MobileHeroScenery()
                    .padding(-18)

                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NET WORTH")
                                .font(.caption2.weight(.bold))
                                .tracking(1.7)
                                .foregroundStyle(WCColor.textTertiary)
                            Text(settings.privateCurrency(totals.netWorth))
                                .font(.system(size: netWorthSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.58)

                            if let rangeChange {
                                HStack(spacing: 6) {
                                    Image(systemName: rangeChange.value >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text(settings.privateCurrency(abs(rangeChange.value)))
                                    Text(privatePercent(abs(rangeChange.percentage)))
                                    Text(timeRange.rawValue)
                                        .foregroundStyle(WCColor.textTertiary)
                                }
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(rangeChange.value >= 0 ? WCColor.primary : WCColor.destructive)
                            } else {
                                Text("Add another snapshot to see movement")
                                    .font(.caption)
                                    .foregroundStyle(WCColor.textTertiary)
                            }
                        }

                        Spacer(minLength: 6)
                        snapshotFreshness
                    }

                    Picker("Net worth range", selection: $timeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if points.isEmpty {
                        EmptyState(
                            title: "Your net-worth trail starts here",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .frame(height: 205)
                    } else if settings.isPrivacyMode {
                        MobilePrivacyChartCover(
                            title: "Net-worth history concealed",
                            message: "Turn off Privacy Mode to reveal values and movement."
                        )
                        .frame(height: 205)
                    } else {
                        Chart {
                            if let selectedNetWorthDate,
                               let selectedPoint = points.min(by: { abs($0.date.timeIntervalSince(selectedNetWorthDate)) < abs($1.date.timeIntervalSince(selectedNetWorthDate)) }) {
                                RuleMark(x: .value("Selected Date", selectedPoint.date))
                                    .foregroundStyle(WCColor.primary.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                                    .accessibilityHidden(true)
                                    .annotation(position: .top) {
                                        VStack(spacing: 4) {
                                            Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.7))
                                            Text(settings.privateCurrency(selectedPoint.value))
                                                .font(.caption.monospacedDigit().weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WCColor.border, lineWidth: 1))
                                    }
                            }

                            ForEach(points) { point in
                                AreaMark(
                                    x: .value("Date", point.date),
                                    yStart: .value("Range floor", yDomain.lowerBound),
                                    yEnd: .value("Net Worth", point.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [WCColor.primary.opacity(0.3), WCColor.primary.opacity(0.01)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.linear)
                                .accessibilityHidden(true)

                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Net Worth", point.value)
                                )
                                .foregroundStyle(WCColor.primary)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.linear)
                                .symbol(Circle())
                                .symbolSize(22)
                                .accessibilityLabel(Text(point.date.formatted(date: .abbreviated, time: .omitted)))
                                .accessibilityValue(Text(settings.privateCurrency(point.value)))
                            }
                        }
                        .chartYScale(domain: yDomain)
                        .chartXSelection(value: $selectedNetWorthDate)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: points)
                        .frame(height: 205)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Net-worth history"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var snapshotFreshness: some View {
        if let snapshot = finance.data.snapshots.max(by: { $0.date < $1.date }) {
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(snapshotFreshnessColor(snapshot.date))
                        .frame(width: 6, height: 6)
                        .shadow(color: snapshotFreshnessColor(snapshot.date).opacity(0.75), radius: 4)
                    Text(freshnessText(snapshot.date))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))
                }
                Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(WCColor.textFaint)
            }
        } else {
            Label("No snapshots", systemImage: "camera.metering.center.weighted")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WCColor.textTertiary)
        }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                "Position",
                subtitle: "Balances derived from your activity and holdings"
            )

            LazyVGrid(columns: columns, spacing: 12) {
                MetricCard(
                    title: "Recorded Cash",
                    value: settings.privateCurrency(totals.totalLiquidity),
                    systemImage: "banknote.fill",
                    detail: finance.data.transactions.isEmpty ? "No activity yet" : "Income less expenses"
                )
                MetricCard(
                    title: "Investments",
                    value: settings.privateCurrency(totals.totalInvestments),
                    systemImage: "chart.line.uptrend.xyaxis",
                    accent: .cyan,
                    detail: finance.data.investments.count == 1 ? LocalizedStringKey("1 position") : LocalizedStringKey("\(finance.data.investments.count) positions")
                )
                MetricCard(
                    title: "Crypto",
                    value: settings.privateCurrency(totals.totalCrypto),
                    systemImage: "bitcoinsign.circle.fill",
                    accent: WCColor.warning,
                    detail: finance.data.crypto.count == 1 ? LocalizedStringKey("1 holding") : LocalizedStringKey("\(finance.data.crypto.count) holdings")
                )
                MetricCard(
                    title: "Total Assets",
                    value: settings.privateCurrency(totals.totalAssets),
                    systemImage: "building.columns.fill",
                    accent: .indigo,
                    detail: "Across every asset"
                )
                MetricCard(
                    title: "Liabilities",
                    value: settings.privateCurrency(totals.totalLiabilities),
                    systemImage: "creditcard.fill",
                    accent: WCColor.destructive,
                    detail: finance.data.liabilities.count == 1 ? LocalizedStringKey("1 liability") : LocalizedStringKey("\(finance.data.liabilities.count) liabilities")
                )
                MetricCard(
                    title: "Net Savings",
                    value: settings.privateCurrency(currentMonthCashFlow.netSavings),
                    systemImage: currentMonthCashFlow.netSavings >= 0 ? "arrow.down.to.line.circle.fill" : "arrow.up.to.line.circle.fill",
                    accent: currentMonthCashFlow.netSavings >= 0 ? WCColor.primary : WCColor.destructive,
                    detail: LocalizedStringKey(Date().formatted(.dateTime.month(.wide)))
                )
            }
        }
    }

    private var cashFlowTrend: some View {
        let trend = finance.cashFlowTrend(months: 6)
        let hasCashFlow = trend.contains { $0.income != 0 || $0.expense != 0 }
        let totalIncome = trend.reduce(0) { $0 + $1.income }
        let totalExpense = trend.reduce(0) { $0 + $1.expense }

        return FinanceCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading("Six-Month Cash Flow", subtitle: "Income and expenses by month")

                if !hasCashFlow {
                    EmptyState(title: "No recent cash flow", systemImage: "chart.bar.xaxis")
                        .frame(height: 210)
                } else if settings.isPrivacyMode {
                    MobilePrivacyChartCover(
                        title: "Cash-flow chart concealed",
                        message: "Monthly amounts and proportions are hidden."
                    )
                    .frame(height: 210)
                } else {
                    Chart(trend) { month in
                        BarMark(
                            x: .value(settings.localized("Month"), month.monthLabel),
                            y: .value(settings.localized("Amount"), month.income)
                        )
                        .foregroundStyle(WCColor.primary.gradient)
                        .position(by: .value(settings.localized("Type"), settings.localized("Income")))
                        .cornerRadius(6)
                        .accessibilityLabel(Text(verbatim: "\(month.monthLabel), \(settings.localized("Income"))"))
                        .accessibilityValue(Text(settings.privateCurrency(month.income)))

                        BarMark(
                            x: .value(settings.localized("Month"), month.monthLabel),
                            y: .value(settings.localized("Amount"), month.expense)
                        )
                        .foregroundStyle(WCColor.destructive.opacity(0.8).gradient)
                        .position(by: .value(settings.localized("Type"), settings.localized("Expenses")))
                        .cornerRadius(6)
                        .accessibilityLabel(Text(verbatim: "\(month.monthLabel), \(settings.localized("Expenses"))"))
                        .accessibilityValue(Text(settings.privateCurrency(month.expense)))
                    }
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(WCColor.textTertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: trend)
                    .frame(height: 210)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Six-Month Cash Flow"))
                }

                HStack(spacing: 18) {
                    cashFlowLegend(title: settings.localized("Income"), value: totalIncome, color: WCColor.primary)
                    cashFlowLegend(title: settings.localized("Expenses"), value: totalExpense, color: WCColor.destructive)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("6M NET")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(WCColor.textFaint)
                        Text(settings.privateCurrency(totalIncome - totalExpense))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(totalIncome - totalExpense >= 0 ? WCColor.primary : WCColor.destructive)
                    }
                }
            }
        }
    }

    private func cashFlowLegend(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.gradient)
                .frame(width: 8, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(WCColor.textFaint)
                Text(settings.privateCurrency(value))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private var topExpenses: some View {
        let expenses = Array(finance.expensesByCategory(period: .thirtyDays).prefix(5))

        return FinanceCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(
                    "Top Expense Categories",
                    subtitle: "Where spending was concentrated in the last 30 days"
                )

                if expenses.isEmpty {
                    EmptyState(title: "No expenses in the last 30 days", systemImage: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 15) {
                        ForEach(Array(expenses.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 8) {
                                HStack(spacing: 9) {
                                    Text("\(index + 1)")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(WCColor.textFaint)
                                        .frame(width: 17)
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                }

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(.white.opacity(0.06))
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [WCColor.warning, WCColor.destructive.opacity(0.82)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: settings.isPrivacyMode ? 0 : geometry.size.width * max(0, min(item.percentage / 100, 1)))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentActivity: some View {
        let transactions = Array(finance.transactions.prefix(5))

        return FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading("Recent Activity", subtitle: "Your latest recorded cash movements")

                if transactions.isEmpty {
                    EmptyState(title: "No activity yet", systemImage: "clock.arrow.circlepath")
                } else {
                    VStack(spacing: 10) {
                        ForEach(transactions) { transaction in
                            InsetFinanceRow {
                                HStack(spacing: 12) {
                                    Image(systemName: transaction.type == .income ? "arrow.down.left" : "arrow.up.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            (transaction.type == .income ? WCColor.primary : WCColor.destructive).opacity(0.11),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        )

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(transaction.category)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.84))
                                            .lineLimit(1)
                                        Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(WCColor.textFaint)
                                    }

                                    Spacer(minLength: 8)
                                    Text(signedAmount(for: transaction))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(transaction.type == .income ? WCColor.primary : .white.opacity(0.82))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func netWorthChange(in points: [NetWorthPoint]) -> (value: Double, percentage: Double)? {
        guard let first = points.first, let last = points.last, first.date != last.date else {
            return nil
        }
        let change = last.value - first.value
        let percentage = first.value != 0 ? change / abs(first.value) * 100 : 0
        return (change, percentage)
    }

    private func chartDomain(for points: [NetWorthPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        let spread = max(maximum - minimum, max(abs(maximum), 1) * 0.08)
        let padding = spread * 0.18
        return (minimum - padding)...(maximum + padding)
    }

    private func privatePercent(_ value: Double) -> String {
        settings.isPrivacyMode
            ? settings.redactionToken
            : "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func signedAmount(for transaction: Transaction) -> String {
        guard !settings.isPrivacyMode else { return settings.redactionToken }
        let prefix = transaction.type == .income ? "+" : "−"
        return prefix + settings.formatCurrency(transaction.amount)
    }



    private func freshnessText(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        switch interval {
        case 0..<60:
            return settings.localized("Just now")
        case 60..<(60 * 60):
            let m = Int(interval / 60)
            return settings.localized("\(m)m ago")
        case (60 * 60)..<(24 * 60 * 60):
            let h = Int(interval / (60 * 60))
            return settings.localized("\(h)h ago")
        case (24 * 60 * 60)..<(7 * 24 * 60 * 60):
            let d = Int(interval / (24 * 60 * 60))
            return settings.localized("\(d)d ago")
        default:
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func snapshotFreshnessColor(_ date: Date) -> Color {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 24 * 60 * 60 {
            return WCColor.primary
        }
        if interval < 7 * 24 * 60 * 60 {
            return WCColor.warning
        }
        return .white.opacity(0.35)
    }
}

private struct MobileHeroScenery: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.12, blue: 0.13),
                        Color(red: 0.035, green: 0.07, blue: 0.12),
                        Color(red: 0.025, green: 0.04, blue: 0.075)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(WCColor.primary.opacity(0.14))
                    .frame(width: 240, height: 240)
                    .blur(radius: 58)
                    .offset(x: proxy.size.width * 0.38, y: -proxy.size.height * 0.3)

                Circle()
                    .fill(WCColor.accent.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .blur(radius: 55)
                    .offset(x: -proxy.size.width * 0.38, y: proxy.size.height * 0.35)
            }
        }
        .allowsHitTesting(false)
    }
}
