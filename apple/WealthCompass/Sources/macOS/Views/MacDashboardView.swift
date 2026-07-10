import Charts
import SwiftUI

struct MacDashboardView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel

    @State private var timeRange: TimeRange = .oneYear
    @State private var expensePeriod: AnalyticsPeriod = .thirtyDays
    @State private var selectedNetWorthDate: Date?
    @State private var cashFlowRange: CashFlowTimeframe = .sixMonths
    @State private var hoveredAssetSlice: AllocationSlice?
    @State private var hoveredCashFlowMonth: CashFlowMonth?
    @Namespace private var animationNamespace
    @ScaledMetric(relativeTo: .largeTitle) private var headerSize: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var netWorthSize: CGFloat = 42

    private var totals: FinanceTotals {
        finance.calculateTotals(settings: settings)
    }

    private var currentMonthCashFlow: MonthlyCashFlow {
        finance.monthlyCashFlow(for: Date(), settings: settings)
    }

    private var isCompletelyEmpty: Bool {
        finance.data.transactions.isEmpty
            && finance.data.investments.isEmpty
            && finance.data.crypto.isEmpty
            && finance.data.liabilities.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dashboardHeader

                    if isCompletelyEmpty {
                        onboardingCard
                    }

                    netWorthHero
                    keyMetrics(width: proxy.size.width)

                    if proxy.size.width >= 1_090 {
                        HStack(alignment: .top, spacing: 20) {
                            allocationCard
                                .frame(width: max(340, proxy.size.width * 0.34))
                            cashFlowCard
                        }
                    } else {
                        VStack(spacing: 20) {
                            cashFlowCard
                            allocationCard
                        }
                    }

                    if proxy.size.width >= 1_020 {
                        HStack(alignment: .top, spacing: 20) {
                            topExpensesCard
                            recentActivityCard
                        }
                    } else {
                        VStack(spacing: 20) {
                            topExpensesCard
                            recentActivityCard
                        }
                    }
                }
                .padding(.horizontal, 24)
                .scenePadding(.minimum, edges: .horizontal)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .background(MacDashboardBackdrop())
        // navigationTitle centralized in MacRootView (collapse-aware) — see the page-switcher change.
        .onChange(of: timeRange) {
            selectedNetWorthDate = nil
        }
    }

    // VIEW-01: a responsive cash-flow row — Monthly Income / Expenses / Net Savings / Savings Rate
    // (this month) plus total Liabilities — that fills the window width, splitting evenly into
    // 5 / 3 / 2 / 1 flexible columns as the pane narrows.
    private func keyMetrics(width: CGFloat) -> some View {
        let cf = currentMonthCashFlow
        let count = width >= 1_080 ? 5 : (width >= 820 ? 3 : (width >= 560 ? 2 : 1))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            MetricCard(
                title: "Monthly Income",
                value: settings.privateCurrency(cf.monthlyIncome),
                systemImage: "arrow.down.left",
                accent: WCColor.primary,
                detail: "This month"
            )
            .frame(maxWidth: .infinity)
            MetricCard(
                title: "Monthly Expenses",
                value: settings.privateCurrency(cf.monthlyExpenses),
                systemImage: "arrow.up.right",
                accent: WCColor.destructive,
                detail: "This month"
            )
            .frame(maxWidth: .infinity)
            MetricCard(
                title: "Net Savings",
                value: settings.privateCurrency(cf.netSavings),
                systemImage: cf.netSavings >= 0 ? "arrow.down.to.line.circle.fill" : "arrow.up.to.line.circle.fill",
                accent: cf.netSavings >= 0 ? WCColor.primary : WCColor.destructive,
                detail: "Income less expenses"
            )
            .frame(maxWidth: .infinity)
            MetricCard(
                title: "Savings Rate",
                value: settings.isPrivacyMode ? settings.redactionToken : "\(cf.savingsRate.formatted(.number.precision(.fractionLength(1))))%",
                systemImage: "percent",
                detail: "Of monthly income"
            )
            .frame(maxWidth: .infinity)
            MetricCard(
                title: "Liabilities",
                value: settings.privateCurrency(totals.totalLiabilities),
                systemImage: "creditcard.fill",
                accent: WCColor.destructive,
                detail: finance.data.liabilities.count == 1 ? LocalizedStringKey("1 liability") : LocalizedStringKey("\(finance.data.liabilities.count) liabilities")
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your financial horizon")
                    .font(.system(size: headerSize, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, WCColor.primary.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("A clear view of what you own, owe, earn, and spend.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 16)

            if settings.isPrivacyMode {
                Label("Privacy on", systemImage: "eye.slash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.07), in: Capsule())
            }

            Button {
                appModel.presentNewItem(for: .cashFlow)
            } label: {
                Label("Add Transaction", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(WCColor.primary)
        }
    }

    private var onboardingCard: some View {
        DashboardGlassCard(padding: 0) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Build your first financial view", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Record cash flow or add a position. Wealth Compass will create snapshots and fill this dashboard automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    onboardingButton("Cash Flow", systemImage: "arrow.left.arrow.right", destination: .cashFlow)
                    onboardingButton("Investment", systemImage: "chart.line.uptrend.xyaxis", destination: .investments)
                    onboardingButton("Crypto", systemImage: "bitcoinsign.circle", destination: .crypto)
                }
            }
            .padding(22)
            .background(
                LinearGradient(
                    colors: [WCColor.primary.opacity(0.14), WCColor.accent.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private func onboardingButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        destination: MacDestination
    ) -> some View {
        Button {
            appModel.presentNewItem(for: destination)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var netWorthHero: some View {
        // Defensive: only finite points reach Swift Charts (the engine already guards, but the chart
        // boundary is the last line of defense against a NaN/Inf y emitting CoreGraphics warnings) (WC-#16).
        let points = finance.snapshotsForChart(range: timeRange, settings: settings).filter { $0.value.isFinite }
        let selectedPoint = selectedPoint(in: points)
        let rangeChange = netWorthChange(in: points)
        let yDomain = chartDomain(for: points)
        // L40: computed once here to flag a total built partly on seed rates (details in Settings).
        let hasIncompleteRates = !finance.heldCurrenciesUsingSeedRate(settings: settings).isEmpty

        return DashboardGlassCard(padding: 0) {
            ZStack {
                HeroScenery()

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NET WORTH")
                                .font(.caption.weight(.bold))
                                .tracking(1.8)
                                .foregroundStyle(WCColor.textTertiary)
                            Text(settings.privateCurrency(totals.netWorth))
                                .font(.system(size: netWorthSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            if let rangeChange {
                                HStack(spacing: 7) {
                                    Image(systemName: rangeChange.value >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text(settings.privateCurrency(abs(rangeChange.value)))
                                    Text(privatePercent(abs(rangeChange.percentage)))
                                    Text("for \(timeRange.rawValue)")
                                        .foregroundStyle(WCColor.textTertiary)
                                }
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(rangeChange.value >= 0 ? WCColor.primary : WCColor.destructive)
                            } else {
                                Text("Add another snapshot to see movement over time")
                                    .font(.subheadline)
                                    .foregroundStyle(WCColor.textTertiary)
                            }

                            // L40: subtle cue that the total mixes an approximate offline rate for a
                            // held currency missing from the latest update (details in Settings).
                            if hasIncompleteRates {
                                Label("Rates may be incomplete", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(WCColor.warning)
                            }
                        }

                        Spacer(minLength: 16)

                        VStack(alignment: .trailing, spacing: 12) {
                            DashboardSegmentedPicker(selection: $timeRange, items: TimeRange.allCases) { LocalizedStringKey($0.rawValue) }
                                .padding(.bottom, 2)

                            snapshotFreshness
                        }
                    }

                    if points.isEmpty {
                        DashboardEmptyState(
                            title: "Your net-worth trail starts here",
                            message: "Adding a transaction or position records a snapshot for this chart.",
                            systemImage: "chart.line.uptrend.xyaxis",
                            actionTitle: "Add Transaction"
                        ) {
                            appModel.presentNewItem(for: .cashFlow)
                        }
                        .frame(height: 238)
                    } else if settings.isPrivacyMode {
                        PrivacyChartCover(
                            title: "Net-worth history concealed",
                            message: "Turn off Privacy Mode to reveal values and movement."
                        )
                        .frame(height: 238)
                    } else {
                        Chart {
                            ForEach(points) { point in
                                AreaMark(
                                    x: .value("Date", point.date),
                                    yStart: .value("Range floor", yDomain.lowerBound),
                                    yEnd: .value("Net Worth", point.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [WCColor.primary.opacity(0.28), WCColor.primary.opacity(0.015)],
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

                            if let selectedPoint {
                                RuleMark(x: .value("Selected date", selectedPoint.date))
                                    .foregroundStyle(.white.opacity(0.34))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .accessibilityHidden(true)
                                    .annotation(
                                        position: .top,
                                        spacing: 0,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                                    ) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(selectedPoint.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.white.opacity(0.62))
                                            Text(settings.privateCurrency(selectedPoint.value))
                                                .font(.callout.monospacedDigit().weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(.white.opacity(0.1), lineWidth: 1)
                                        }
                                        .padding(.bottom, 6)
                                    }

                                PointMark(
                                    x: .value("Selected date", selectedPoint.date),
                                    y: .value("Selected net worth", selectedPoint.value)
                                )
                                .foregroundStyle(WCColor.primary)
                                .symbolSize(64)
                                .accessibilityHidden(true)
                            }
                        }
                        .chartYScale(domain: yDomain)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                                AxisGridLine()
                                    .foregroundStyle(.white.opacity(0.06))
                                AxisValueLabel()
                                    .foregroundStyle(WCColor.textTertiary)
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartXSelection(value: $selectedNetWorthDate)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: points)
                        .frame(height: 238)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Net-worth history"))

                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private var snapshotFreshness: some View {
        if let snapshot = finance.data.snapshots.max(by: { $0.date < $1.date }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(snapshotFreshnessColor(snapshot.date))
                    .frame(width: 7, height: 7)
                    .shadow(color: snapshotFreshnessColor(snapshot.date).opacity(0.8), radius: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Latest snapshot \(freshnessText(snapshot.date))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(WCColor.textTertiary)
                }
            }
        } else {
            Label("No snapshots yet", systemImage: "camera.metering.center.weighted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WCColor.textTertiary)
        }
    }

    private var allocationCard: some View {
        let slices = finance.assetAllocation(settings: settings)
        let allocationTotal = slices.reduce(0) { $0 + $1.value }

        return DashboardGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading("Asset Allocation", subtitle: "How investable assets are distributed")

                if slices.isEmpty {
                    DashboardEmptyState(
                        title: "No assets to allocate",
                        message: "Add recorded cash, an investment, or a crypto holding.",
                        systemImage: "chart.pie",
                        actionTitle: "Add Investment"
                    ) {
                        appModel.presentNewItem(for: .investments)
                    }
                    .frame(minHeight: 260)
                } else {
                    ZStack {
                        if settings.isPrivacyMode {
                            PrivacyChartCover(
                                title: "Allocation concealed",
                                message: "Values and proportions are hidden."
                            )
                        } else {
                            Chart(slices) { slice in
                                SectorMark(
                                    angle: .value("Value", slice.value),
                                    innerRadius: .ratio(0.72),
                                    angularInset: 2.5
                                )
                                .foregroundStyle(slice.color.gradient)
                                .cornerRadius(5)
                                .opacity(hoveredAssetSlice == nil || hoveredAssetSlice?.id == slice.id ? 1.0 : 0.3)
                                .accessibilityLabel(Text(slice.name))
                                .accessibilityValue(Text(settings.privateCurrency(slice.value)))
                            }
                            .chartLegend(.hidden)
                            .chartBackground { proxy in
                                GeometryReader { geometry in
                                    if let plotFrame = proxy.plotFrame {
                                        let frame = geometry[plotFrame]
                                        VStack(spacing: 3) {
                                            if let hoveredAssetSlice {
                                                Text(hoveredAssetSlice.name)
                                                    .textCase(.uppercase)
                                                    .font(.caption2.weight(.bold))
                                                    .tracking(1.3)
                                                    .foregroundStyle(hoveredAssetSlice.color)
                                                Text(settings.privateCurrency(hoveredAssetSlice.value))
                                                    .font(.headline.monospacedDigit().weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                                Text(privatePercent(allocationTotal > 0 ? hoveredAssetSlice.value / allocationTotal * 100 : 0))
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.white.opacity(0.6))
                                            } else {
                                                Text("ASSETS")
                                                    .font(.caption2.weight(.bold))
                                                    .tracking(1.3)
                                                    .foregroundStyle(WCColor.textTertiary)
                                                Text(settings.privateCurrency(allocationTotal))
                                                    .font(.headline.monospacedDigit().weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                            }
                                        }
                                        .position(x: frame.midX, y: frame.midY)
                                    }
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    if let plotFrame = proxy.plotFrame {
                                        let frame = geometry[plotFrame]
                                        Rectangle().fill(.clear).contentShape(Rectangle())
                                            .accessibilityHidden(true)
                                            .onContinuousHover { phase in
                                                switch phase {
                                                case .active(let location):
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredAssetSlice = slice(at: location, in: frame, slices: slices)
                                                    }
                                                case .ended:
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredAssetSlice = nil
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: slices.map(\.value))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(Text("Asset Allocation"))
                        }
                    }
                    .frame(height: 210)

                    VStack(spacing: 11) {
                        ForEach(slices) { slice in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(slice.color.gradient)
                                    .frame(width: 10, height: 10)
                                Text(slice.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.76))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(settings.privateCurrency(slice.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(privatePercent(allocationTotal > 0 ? slice.value / allocationTotal * 100 : 0))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(WCColor.textTertiary)
                                }
                            }
                        }
                    }

                    if let excludedCash = finance.assetAllocationExcludedCash(settings: settings) {
                        // L33: cash is net-negative and dropped from the ring (no negative wedge), so the
                        // ring total exceeds the net-worth header — explain the gap.
                        Text(settings.localized("Chart shows gross assets; \(settings.privateCurrency(excludedCash)) in net cash liabilities is excluded."))
                            .font(.caption2)
                            .foregroundStyle(WCColor.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var cashFlowCard: some View {
        let trend = finance.cashFlowTrend(months: cashFlowRange.rawValue, settings: settings)
        let hasCashFlow = trend.contains { $0.income != 0 || $0.expense != 0 }
        let totalIncome = trend.reduce(0) { $0 + $1.income }
        let totalExpense = trend.reduce(0) { $0 + $1.expense }

        return DashboardGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    sectionHeading("Cash Flow", subtitle: "Income and expenses by month")
                    Spacer(minLength: 16)
                    HStack(spacing: 12) {
                        DashboardSegmentedPicker(selection: $cashFlowRange, items: CashFlowTimeframe.allCases) { $0.label }
                        
                        Button("View Cash Flow") {
                            appModel.selection = .cashFlow
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WCColor.primary)
                    }
                }

                if !hasCashFlow {
                    DashboardEmptyState(
                        title: "No recent cash flow",
                        message: "Record income or an expense to reveal the monthly pattern.",
                        systemImage: "chart.bar.xaxis",
                        actionTitle: "Add Transaction"
                    ) {
                        appModel.presentNewItem(for: .cashFlow)
                    }
                    .frame(height: 244)
                } else if settings.isPrivacyMode {
                    PrivacyChartCover(
                        title: "Cash-flow chart concealed",
                        message: "Monthly amounts and proportions are hidden."
                    )
                    .frame(height: 244)
                } else {
                    Chart(trend) { month in
                        BarMark(
                            x: .value("Month", month.monthLabel),
                            y: .value("Amount", month.income)
                        )
                        .foregroundStyle(WCColor.primary.gradient)
                        .position(by: .value("Type", "Income"))
                        .cornerRadius(6)
                        .opacity(hoveredCashFlowMonth == nil || hoveredCashFlowMonth?.id == month.id ? 1.0 : 0.3)
                        .accessibilityLabel(Text(verbatim: "\(month.monthLabel), \(settings.localized("Income"))"))
                        .accessibilityValue(Text(settings.privateCurrency(month.income)))

                        BarMark(
                            x: .value("Month", month.monthLabel),
                            y: .value("Amount", month.expense)
                        )
                        .foregroundStyle(WCColor.destructive.opacity(0.78).gradient)
                        .position(by: .value("Type", "Expenses"))
                        .cornerRadius(6)
                        .opacity(hoveredCashFlowMonth == nil || hoveredCashFlowMonth?.id == month.id ? 1.0 : 0.3)
                        .accessibilityLabel(Text(verbatim: "\(month.monthLabel), \(settings.localized("Expenses"))"))
                        .accessibilityValue(Text(settings.privateCurrency(month.expense)))
                    }
                    .chartLegend(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .accessibilityHidden(true)
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        if let plotFrame = proxy.plotFrame {
                                            let frame = geometry[plotFrame]
                                            let x = location.x - frame.origin.x
                                            if let monthLabel: String = proxy.value(atX: x) {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredCashFlowMonth = trend.first { $0.monthLabel == monthLabel }
                                                }
                                            }
                                        }
                                    case .ended:
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            hoveredCashFlowMonth = nil
                                        }
                                    }
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(WCColor.textTertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: trend)
                    .frame(height: 244)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Cash Flow"))
                }

                HStack(spacing: 20) {
                    CashFlowLegendItem(
                        title: "Income",
                        value: settings.privateCurrency(hoveredCashFlowMonth?.income ?? totalIncome),
                        color: WCColor.primary
                    )
                    CashFlowLegendItem(
                        title: "Expenses",
                        value: settings.privateCurrency(hoveredCashFlowMonth?.expense ?? totalExpense),
                        color: WCColor.destructive
                    )
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Group {
                            if hoveredCashFlowMonth != nil {
                                Text(hoveredCashFlowMonth!.monthLabel)
                            } else {
                                Text(settings.localized("\(cashFlowRange.localizedTitle(appLanguage: settings.appLanguage)) NET"))
                            }
                        }
                        .textCase(.uppercase)
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(WCColor.textFaint)
                        let net = hoveredCashFlowMonth != nil ? (hoveredCashFlowMonth!.income - hoveredCashFlowMonth!.expense) : (totalIncome - totalExpense)
                        Text(settings.privateCurrency(net))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(net >= 0 ? WCColor.primary : WCColor.destructive)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var topExpensesCard: some View {
        let expenses = Array(finance.expensesByCategory(period: expensePeriod, settings: settings).prefix(5))

        return DashboardGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    sectionHeading("Top Expense Categories", subtitle: "Where recorded spending is concentrated")
                    Spacer()
                    Picker("Expense period", selection: $expensePeriod) {
                        ForEach(AnalyticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }

                if expenses.isEmpty {
                    DashboardEmptyState(
                        title: "No expenses for this period",
                        message: "Choose another period or record an expense.",
                        systemImage: "list.bullet.rectangle.portrait",
                        actionTitle: "Add Transaction"
                    ) {
                        appModel.presentNewItem(for: .cashFlow)
                    }
                    .frame(minHeight: 246)
                } else {
                    VStack(spacing: 15) {
                        ForEach(Array(expenses.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 8) {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(WCColor.textFaint)
                                        .frame(width: 18)
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(privatePercent(item.percentage))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(WCColor.textTertiary)
                                        .frame(width: 48, alignment: .trailing)
                                }

                                if settings.isPrivacyMode {
                                    Capsule()
                                        .fill(.white.opacity(0.07))
                                        .frame(height: 5)
                                } else {
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
                                                .frame(width: geometry.size.width * max(0, min(item.percentage / 100, 1)))
                                        }
                                    }
                                    .frame(height: 5)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 246, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentActivityCard: some View {
        let transactions = Array(finance.transactions.prefix(6))

        return DashboardGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    sectionHeading("Recent Activity", subtitle: "Your latest recorded cash movements")
                    Spacer()
                    Button("View All") {
                        appModel.selection = .cashFlow
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WCColor.primary)
                }

                if transactions.isEmpty {
                    DashboardEmptyState(
                        title: "No activity yet",
                        message: "Your latest income and expenses will appear here.",
                        systemImage: "clock.arrow.circlepath",
                        actionTitle: "Add Transaction"
                    ) {
                        appModel.presentNewItem(for: .cashFlow)
                    }
                    .frame(minHeight: 246)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                            ActivityRow(
                                transaction: transaction,
                                formattedAmount: signedAmount(for: transaction)
                            )

                            if index < transactions.count - 1 {
                                Divider()
                                    .overlay(.white.opacity(0.06))
                                    .padding(.leading, 45)
                            }
                        }
                    }
                    .frame(minHeight: 246, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeading(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(WCColor.textTertiary)
        }
    }

    private func selectedPoint(in points: [NetWorthPoint]) -> NetWorthPoint? {
        guard let selectedNetWorthDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedNetWorthDate))
                < abs($1.date.timeIntervalSince(selectedNetWorthDate))
        }
    }

    private func netWorthChange(in points: [NetWorthPoint]) -> (value: Double, percentage: Double)? {
        guard let first = points.first, let last = points.last, first.date != last.date else {
            return nil
        }
        let change = last.value - first.value
        let percentage = abs(first.value) > 1 ? change / abs(first.value) * 100 : 0
        return (change, percentage)
    }

    private func chartDomain(for points: [NetWorthPoint]) -> ClosedRange<Double> {
        AnalyticsEngine.chartYDomain(for: points)
    }

    private func privatePercent(_ value: Double) -> String {
        settings.isPrivacyMode
            ? settings.redactionToken
            : "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func signedAmount(for transaction: Transaction) -> String {
        guard !settings.isPrivacyMode else { return settings.redactionToken }
        let prefix = transaction.type == .income ? "+" : "−"
        // Show each row in its own currency (deep-audit H5); totals stay converted.
        return prefix + settings.formatSourceCurrency(transaction.amount, currency: transaction.currency ?? settings.currency)
    }

    private func freshnessText(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        switch interval {
        case 0..<60:
            return settings.localized("just now")
        case 60..<(60 * 60):
            return settings.localized("\(Int(interval / 60))m ago")
        case (60 * 60)..<(24 * 60 * 60):
            return settings.localized("\(Int(interval / (60 * 60)))h ago")
        case (24 * 60 * 60)..<(7 * 24 * 60 * 60):
            return settings.localized("\(Int(interval / (24 * 60 * 60)))d ago")
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

    private func slice(at location: CGPoint, in rect: CGRect, slices: [AllocationSlice]) -> AllocationSlice? {
        return PieSliceHitTester.sliceIndex(at: location, in: rect, values: slices.map(\.value), innerRadiusRatio: 0.72)
            .map { slices[$0] }
    }
}

struct DashboardGlassCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.055), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

struct CashFlowLegendItem: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.gradient)
                .frame(width: 9, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WCColor.textTertiary)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }
}

struct ActivityRow: View {
    @Environment(\.appLanguage) private var appLanguage
    let transaction: Transaction
    let formattedAmount: String

    var body: some View {
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
                Text(transaction.description.isEmpty ? transaction.type.localizedTitle(appLanguage: appLanguage) : transaction.description)
                    .font(.caption2)
                    .foregroundStyle(WCColor.textFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedAmount)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(transaction.type == .income ? WCColor.primary : .white.opacity(0.8))
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(WCColor.textFaint)
            }
        }
        .padding(.vertical, 9)
    }
}

struct DashboardEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        systemImage: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(WCColor.primary.opacity(0.78))
                .frame(width: 48, height: 48)
                .background(WCColor.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
            Text(message)
                .font(.caption)
                .foregroundStyle(WCColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(WCColor.primary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
    }
}

struct PrivacyChartCover: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.12))

            VStack(spacing: 9) {
                Image(systemName: "eye.slash.fill")
                    .font(.title2)
                    .foregroundStyle(WCColor.primary.opacity(0.75))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WCColor.textFaint)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct HeroScenery: View {
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
                    .fill(WCColor.primary.opacity(0.13))
                    .frame(width: 340, height: 340)
                    .blur(radius: 70)
                    .offset(x: proxy.size.width * 0.33, y: -proxy.size.height * 0.34)

                Circle()
                    .fill(WCColor.accent.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .blur(radius: 64)
                    .offset(x: -proxy.size.width * 0.36, y: proxy.size.height * 0.34)

                LinearGradient(
                    colors: [.white.opacity(0.055), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MacDashboardBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.026, blue: 0.047)

            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.085, blue: 0.105).opacity(0.8),
                    .clear,
                    Color(red: 0.035, green: 0.045, blue: 0.085).opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(WCColor.primary.opacity(0.055))
                .frame(width: 520, height: 520)
                .blur(radius: 110)
                .offset(x: 420, y: -330)
        }
        .ignoresSafeArea()
    }
}

// CashFlowTimeframe moved to Shared/Models/FinanceModels.swift (VIEW-03) so iOS can reuse it.

struct DashboardSegmentedPicker<SelectionValue: Hashable & Identifiable>: View {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]
    let labelProvider: (SelectionValue) -> LocalizedStringKey
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = item
                    }
                } label: {
                    Text(labelProvider(item))
                        .font(.caption.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                        .frame(minWidth: 44)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                // M07: a plain Button gives native VoiceOver (announced as a button) and keyboard
                // focus/activation, which the previous Text + onTapGesture did not expose. The
                // `.plain` style keeps the custom capsule look; the selected state is surfaced too.
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.black.opacity(0.2))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}
