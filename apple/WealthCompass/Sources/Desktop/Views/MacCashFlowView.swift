import Charts
import SwiftUI

private enum MacTransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .income: "Income"
        case .expense: "Expense"
        }
    }

    var transactionType: TransactionType? {
        switch self {
        case .all: nil
        case .income: .income
        case .expense: .expense
        }
    }
}

private enum MacCashFlowEditor: Identifiable {
    case transaction(Transaction?)
    case recurring(RecurringTransaction?)

    var id: String {
        switch self {
        case .transaction(let transaction):
            "transaction-\(transaction?.id.uuidString ?? "new")"
        case .recurring(let schedule):
            "recurring-\(schedule?.id.uuidString ?? "new")"
        }
    }
}

private enum MacCashFlowAlert: Identifiable {
    case deleteTransaction(Transaction)
    case deleteRecurringTransaction(RecurringTransaction)
    case finishRecurringTransaction(RecurringTransaction)
    case message(title: String, message: String)

    var id: String {
        switch self {
        case .deleteTransaction(let transaction):
            "delete-transaction-\(transaction.id)"
        case .deleteRecurringTransaction(let schedule):
            "delete-recurring-\(schedule.id)"
        case .finishRecurringTransaction(let schedule):
            "finish-recurring-\(schedule.id)"
        case .message(let title, let message):
            "message-\(title)-\(message)"
        }
    }
}

private enum MacCashFlowTab: MacSelectorTab {
    case overview
    case transactions

    var title: LocalizedStringKey {
        switch self {
        case .overview: return "Overview"
        case .transactions: return "Transactions"
        }
    }
}

struct MacCashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var searchText = ""
    // All Time by default: the Money Flow card answers "where does my money go", and a single
    // month is often too sparse to show a shape — the Dashboard's compact card stays on 30 days,
    // where recency is the point.
    @State private var moneyFlowPeriod: AnalyticsPeriod = .all
    /// Set when the user drills in from the Money Flow diagram; shown as a removable chip in the
    /// filter bar and cleared by dismissing it.
    @State private var categoryFilter: CashFlowCategoryFilter?
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: MacTransactionTypeFilter = .all
    @State private var editor: MacCashFlowEditor?
    @State private var activeAlert: MacCashFlowAlert?
    @State private var selectedTab: MacCashFlowTab = .overview
    @State private var cashFlowRange: CashFlowTimeframe = .sixMonths
    @State private var hoveredCashFlowMonth: CashFlowMonth?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                MacSelectorIsland(selection: $selectedTab)
                Spacer()
            }
            .padding(.vertical, 16)

            if selectedTab == .overview {
                // Overview tab: summary cards, analytics, recurring transactions
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            summaryCards(width: proxy.size.width)

                            // Full width, directly under the metrics: a Sankey needs a long
                            // horizontal run or its ribbons read as blobs. The Expense Categories
                            // donut that used to share this row was retired when this landed — its
                            // entire content is this diagram's right-hand column.
                            moneyFlowCard

                            cashFlowTrendCard

                            if proxy.size.width >= 1_090 {
                                HStack(alignment: .top, spacing: 20) {
                                    recentActivityCard
                                        .frame(width: max(340, proxy.size.width * 0.45))
                                    recurringTransactionsCard
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                VStack(spacing: 20) {
                                    recentActivityCard
                                    recurringTransactionsCard
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                // Transactions tab: filter bar and transaction table
                VStack(alignment: .leading, spacing: 10) {
                    transactionFilters
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    transactionTable
                        .layoutPriority(1)
                }
            }
        }
        .background(ScreenBackground())
        // navigationTitle centralized in MacRootView (collapse-aware).
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        editor = .transaction(nil)
                    } label: {
                        Label("One-Time Transaction", systemImage: "plus.circle")
                    }

                    Button {
                        editor = .recurring(nil)
                    } label: {
                        Label("Recurring Transaction", systemImage: "repeat.circle")
                    }
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .transaction(let transaction):
                MacCashFlowTransactionEditor(transaction: transaction) { original, type, amount, category, description, date, currency in
                    if let original {
                        finance.updateTransaction(
                            original,
                            type: type,
                            amount: amount,
                            category: category,
                            description: description,
                            date: date,
                            currency: currency,
                            settings: settings
                        )
                    } else {
                        finance.addTransaction(
                            type: type,
                            amount: amount,
                            category: category,
                            description: description,
                            date: date,
                            currency: currency,
                            settings: settings
                        )
                    }
                }
                .environmentObject(settings)
            case .recurring(let schedule):
                MacRecurringTransactionEditor(schedule: schedule) { schedule in
                    saveRecurringTransaction(schedule)
                }
                .environmentObject(settings)
            }
        }
        .alert(item: $activeAlert, content: alert(for:))
        .onChange(of: appModel.cashFlowFilter) { _, request in
            guard let request else { return }
            applyIncomingFilter(request)
        }
        .onAppear {
            // The Dashboard sets the request and switches pages in the same turn, so this view may
            // not exist yet when the change fires.
            if let request = appModel.cashFlowFilter { applyIncomingFilter(request) }
        }
    }

    // The 6 cash-flow summary cards fill the pane width edge-to-edge (matching the Dashboard),
    // reflowing 6/5/4/3/2/1 by width so a laptop looks unchanged while a wide external display no
    // longer leaves a dead right margin. `width` is the full pane width; subtract the 24pt
    // horizontal padding on each side so the fit math sees the real content width.
    private func summaryCards(width: CGFloat) -> some View {
        let cashFlow = finance.monthlyCashFlow(for: Date(), settings: settings)
        let totals = finance.calculateTotals(settings: settings)
        let monthlyTransactionsCount = finance.monthlyTransactionCount(for: Date())

        return LazyVGrid(
            columns: fillingFlexibleColumns(availableWidth: max(0, width - 48), itemCount: 6),
            alignment: .leading,
            spacing: 16
        ) {
            MetricCard(
                title: "Monthly Income",
                value: settings.privateCurrency(cashFlow.monthlyIncome),
                // Down-left is money in, up-right is money out — the convention iOS uses, the Mac
                // Dashboard uses, and the transaction rows 500 lines below in this same file use.
                // `recurringTransactionRow` on this same Overview tab now reads the same way, so an
                // up-right arrow can no longer mean "expenses" in this strip and "income" in the
                // card directly beneath it.
                systemImage: "arrow.down.left",
                accent: WCColor.primary
            )
            MetricCard(
                title: "Monthly Expenses",
                value: settings.privateCurrency(cashFlow.monthlyExpenses),
                systemImage: "arrow.up.right",
                accent: WCColor.destructive
            )
            MetricCard(
                title: "Net Savings",
                value: settings.privateCurrency(cashFlow.netSavings),
                systemImage: "wallet.pass",
                accent: cashFlow.netSavings >= 0 ? WCColor.primary : WCColor.destructive
            )
            MetricCard(
                title: "Savings Rate",
                value: settings.isPrivacyMode
                    ? settings.redactionToken
                    : formattedPercent(cashFlow.savingsRate, locale: settings.effectiveLocale),
                systemImage: "percent"
            )
            MetricCard(
                title: "Transactions",
                value: settings.privateCount(monthlyTransactionsCount),
                systemImage: "arrow.left.arrow.right"
            )
            MetricCard(
                title: "Total Cash",
                value: settings.privateCurrency(totals.totalLiquidity),
                systemImage: "banknote",
                accent: totals.totalLiquidity >= 0 ? WCColor.primary : WCColor.destructive
            )
        }
    }

    private var cashFlowTrendCard: some View {
        let trend = finance.cashFlowTrend(months: cashFlowRange.rawValue, settings: settings)
        let hasCashFlow = trend.contains { $0.income != 0 || $0.expense != 0 }
        let totalIncome = trend.reduce(0) { $0 + $1.income }
        let totalExpense = trend.reduce(0) { $0 + $1.expense }

        return FinanceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cash Flow")
                            .font(.headline)
                        Text("Income and expenses by month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    DashboardSegmentedPicker(selection: $cashFlowRange, items: CashFlowTimeframe.allCases) { $0.label }
                }

                // Privacy before emptiness: this card carries its own range picker, so "No recent
                // cash flow" appearing for some ranges and not others is itself a readout.
                if settings.isPrivacyMode {
                    EmptyState(title: "Cash-flow chart concealed", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity, minHeight: 244)
                } else if !hasCashFlow {
                    EmptyState(title: "No recent cash flow", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 244)
                } else {
                    Chart(trend) { month in
                        BarMark(
                            x: .value("Month", month.monthKey),
                            y: .value("Amount", month.income)
                        )
                        .foregroundStyle(WCColor.primary.gradient)
                        .position(by: .value("Type", "Income"))
                        .cornerRadius(6)
                        .opacity(hoveredCashFlowMonth == nil || hoveredCashFlowMonth?.id == month.id ? 1.0 : 0.3)
                        .accessibilityLabel(Text(verbatim: "\(month.monthLabel), \(settings.localized("Income"))"))
                        .accessibilityValue(Text(settings.privateCurrency(month.income)))

                        BarMark(
                            x: .value("Month", month.monthKey),
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
                    .chartXAxis {
                        // Bars are keyed on the unique monthKey ("yyyy-MM") so same-month-different-year
                        // columns stay distinct on the 12M range (deep-audit M04); map back to the short
                        // "MMM" label for the visible axis.
                        AxisMarks { value in
                            AxisValueLabel {
                                if let key = value.as(String.self),
                                   let month = trend.first(where: { $0.monthKey == key }) {
                                    Text(month.monthLabel)
                                }
                            }
                        }
                    }
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
                                            if let monthKey: String = proxy.value(atX: x) {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredCashFlowMonth = trend.first { $0.monthKey == monthKey }
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
                        .foregroundStyle(.secondary)
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

    /// The Money Flow (Sankey) card. Replaced the Expense Categories donut that used to sit here:
    /// the donut's entire content is this diagram's right-hand column, and this adds the income
    /// side, the surplus, and a way into the underlying transactions.
    private var moneyFlowCard: some View {
        let sankey = finance.cashFlowSankey(period: moneyFlowPeriod, settings: settings)

        return FinanceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Money Flow")
                            .font(.headline)
                        Text("Where your income went this period")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Picker("Money Flow period", selection: $moneyFlowPeriod) {
                        ForEach(AnalyticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }

                SankeyDiagramView(sankey: sankey, settings: settings) { node in
                    drillIn(to: node)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Clicking a node opens the Transactions tab filtered to what it stands for. Already on this
    /// page, so it switches tabs directly rather than routing through `MacAppModel`.
    private func drillIn(to node: CashFlowSankeyNode) {
        guard node.isDrillable else { return }
        let type: TransactionType = node.role == .income ? .income : .expense
        categoryFilter = CashFlowCategoryFilter(
            categories: Set(node.categories),
            title: node.title,
            type: type,
            period: moneyFlowPeriod
        )
        transactionTypeFilter = type == .income ? .income : .expense
        transactionPeriod = moneyFlowPeriod
        searchText = ""
        selectedTab = .transactions
    }

    /// Applies a drill-through that arrived from the Dashboard's compact diagram.
    private func applyIncomingFilter(_ request: CashFlowCategoryFilter) {
        categoryFilter = request
        transactionTypeFilter = request.type == .income ? .income : .expense
        transactionPeriod = request.period
        searchText = ""
        selectedTab = .transactions
        // Consume it, so navigating back to this page later does not silently re-apply a filter
        // the user has since dismissed.
        //
        // Deferred a turn: this runs from `onAppear` during the root view's own update for the
        // navigation that brought us here, and mutating an `@Published` on `MacAppModel` inline
        // would publish a change from within that update.
        Task { @MainActor in appModel.cashFlowFilter = nil }
    }

    private var recentActivityCard: some View {
        let transactions = Array(finance.transactions.prefix(6))

        return FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recent Activity")
                            .font(.headline)
                        Text("Your latest cash flow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Privacy before emptiness, as at the transaction table: "No activity yet" states
                // that this person has never recorded a transaction. The populated arm still lists
                // its rows (ranked lists are a separate ruling), so what stops is the sentence.
                if settings.isPrivacyMode, transactions.isEmpty {
                    EmptyState(title: "Hidden by Privacy Mode", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if transactions.isEmpty {
                    EmptyState(title: "No activity yet", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                            ActivityRow(
                                transaction: transaction,
                                formattedAmount: signedAmount(for: transaction)
                            )

                            if index < transactions.count - 1 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var recurringTransactionsCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recurring Transactions")
                            .font(.headline)
                        Text("Due schedules catch up on open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editor = .recurring(nil)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }

                // Privacy before emptiness, as above: the sentence states that this person keeps
                // no standing income or expenses.
                if settings.isPrivacyMode, finance.recurringTransactions.isEmpty {
                    EmptyState(title: "Hidden by Privacy Mode", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if finance.recurringTransactions.isEmpty {
                    EmptyState(title: "No recurring transactions", systemImage: "repeat")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(finance.recurringTransactions) { schedule in
                        recurringTransactionRow(schedule)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func recurringTransactionRow(_ schedule: RecurringTransaction) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Same direction convention as the summary strip and the transaction rows: down-left is
            // money in, up-right is money out. The `.circle.fill` variants are this row's own
            // weight, not a different meaning.
            Image(systemName: schedule.type == .income ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)
                .font(.title2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(schedule.category))
                        .font(.headline)
                    Label(
                        schedule.notificationsEnabled
                            ? settings.localized("Notifications on")
                            : settings.localized("Notifications off"),
                        systemImage: schedule.notificationsEnabled ? "bell.fill" : "bell.slash"
                    )
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(schedule.notificationsEnabled
                        ? settings.localized("Notifications enabled")
                        : settings.localized("Notifications disabled"))
                }

                HStack(spacing: 10) {
                    Text(schedule.frequency.title)
                    if schedule.isActive {
                        Text("Next \(settings.date(schedule.nextDueDate, time: .shortened))")
                    } else {
                        Text("Paused")
                            .foregroundStyle(WCColor.warning)
                    }
                    if let endDate = schedule.endDate {
                        Text("Ends \(settings.date(endDate))")
                    } else {
                        Text("No end date")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !schedule.description.isEmpty {
                    Text(schedule.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let prefix = schedule.type == .income ? "+" : "−"
            Text("\(prefix)\(settings.privateSourceCurrency(schedule.amount, currency: schedule.currency ?? settings.currency))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)
                .frame(minWidth: 140, alignment: .trailing)

            HStack(spacing: 4) {
                Button {
                    toggleRecurringTransaction(schedule)
                } label: {
                    Image(systemName: schedule.isActive ? "pause.fill" : "play.fill")
                }
                .help(schedule.isActive
                    ? settings.localized("Pause schedule")
                    : settings.localized("Resume schedule"))
                // `.help` is accessibility *help*, not a label: without this VoiceOver reads the SF
                // Symbol's own name ("pause", "trash") rather than what the button does.
                .accessibilityLabel(schedule.isActive
                    ? settings.localized("Pause schedule")
                    : settings.localized("Resume schedule"))

                Button {
                    activeAlert = .finishRecurringTransaction(schedule)
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Finish schedule")
                .accessibilityLabel(settings.localized("Finish schedule"))

                Button {
                    editor = .recurring(schedule)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit schedule")
                .accessibilityLabel(settings.localized("Edit schedule"))

                Button(role: .destructive) {
                    activeAlert = .deleteRecurringTransaction(schedule)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete schedule")
                .accessibilityLabel(settings.localized("Delete schedule"))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(WCColor.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var transactionFilters: some View {
        // The controls are all fixed-width — Type 220, Search 200, Period 160, plus their labels
        // and spacing — so the row wants ~880pt. A Mac window and an iPad in landscape have that;
        // an iPad held in portrait has ~657pt after the sidebar, and the only flexible thing in
        // the row is the count, which is why it used to render hyphenated as "Show-/ing 0 of 0".
        // Wrapping to two rows keeps every control at its designed size instead.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                typeFilterControl
                searchFieldControl
                periodFilterControl
                categoryFilterChip
                transactionCountLabel
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    typeFilterControl
                    periodFilterControl
                }
                HStack(spacing: 24) {
                    searchFieldControl
                    categoryFilterChip
                    transactionCountLabel
                }
            }

            // An iPad mini in portrait leaves the detail column ~474pt of usable width, and the
            // two pickers plus their labels want ~524pt, so even the two-row form was over budget
            // and crushed the "Type" and "Period" labels down to slivers. One control per row.
            VStack(alignment: .leading, spacing: 12) {
                typeFilterControl
                periodFilterControl
                HStack(spacing: 24) {
                    searchFieldControl
                    categoryFilterChip
                    transactionCountLabel
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WCColor.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var typeFilterControl: some View {
        HStack(spacing: 10) {
            Text("Type")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("Type", selection: $transactionTypeFilter) {
                ForEach(MacTransactionTypeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private var searchFieldControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.desktopControlBackground.opacity(0.5))
        }
        .frame(width: 200)
    }

    private var periodFilterControl: some View {
        HStack(spacing: 10) {
            Text("Period")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("Period", selection: $transactionPeriod) {
                ForEach(AnalyticsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
    }

    /// Only present when you arrived here from the Money Flow diagram; the bar is otherwise
    /// exactly what it has always been.
    @ViewBuilder
    private var categoryFilterChip: some View {
        if let categoryFilter {
            HStack(spacing: 6) {
                Text(categoryFilter.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { self.categoryFilter = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Clear category filter")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(WCColor.primary)
            .background(Capsule().fill(WCColor.primary.opacity(0.14)))
            .overlay(Capsule().stroke(WCColor.primary.opacity(0.34), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(settings.localized("Filtered to \(categoryFilter.title)")))
        }
    }

    /// Exact counts of what exists and what the filters matched, sitting inside the filter bar
    /// itself — the most direct form of the walk-the-picker probe in the app: vary a filter, read
    /// off how many records fall inside it, with every amount already `••••`. Tokenised rather than
    /// hidden, because this row is drawn in both data states and only its two numbers move.
    ///
    /// Two `Text` calls rather than one with a ternary: a ternary between two string literals
    /// leaves the `Text(_:)` overload to inference, and picking the `StringProtocol` one would
    /// render the sentence verbatim in all 35 languages.
    ///
    /// `.fixedSize()` because this is the one flexible item in the bar: whatever width the row is
    /// short by came out of this label, and a count that has been hyphenated in half tells the
    /// reader nothing.
    @ViewBuilder
    private var transactionCountLabel: some View {
        Group {
            if settings.isPrivacyMode {
                Text("Showing \(settings.redactionToken) of \(settings.redactionToken)")
            } else {
                Text("Showing \(filteredTransactions.count) of \(finance.transactions.count)")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    private var transactionTable: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], alignment: .leading, spacing: 16) {
                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        transactionEmptyTitle,
                        systemImage: transactionEmptySystemImage,
                        description: Text(transactionEmptyDescription)
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(filteredTransactions) { transaction in
                        transactionCard(for: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editor = .transaction(transaction)
                            }
                            // M05: expose the whole-card tap-to-edit to VoiceOver / Switch Control as
                            // one activatable button (onTapGesture alone isn't surfaced). Mirrors iOS WC-L24.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { editor = .transaction(transaction) }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transactionCard(for transaction: Transaction) -> some View {
        FinanceCard {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(transaction.category))
                                .font(.headline)
                                .foregroundStyle(.white)
                            if transaction.recurringTransactionID != nil {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(WCColor.primary)
                                    .help("Generated from a recurring schedule")
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Label(
                                transaction.type.title,
                                systemImage: transaction.type == .income ? "arrow.down.left" : "arrow.up.right"
                            )
                            .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer()
                    
                    let prefix = transaction.type == .income ? "+" : "−"
                    Text("\(prefix)\(settings.privateSourceCurrency(transaction.amount, currency: transaction.currency ?? settings.currency))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                }
                
                if !transaction.description.isEmpty {
                    Divider().background(WCColor.border)
                    Text(transaction.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer(minLength: 0)
                
                Divider().background(WCColor.border)
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.date(transaction.date))
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    Spacer()

                    HStack(spacing: 4) {
                        Button {
                            editor = .transaction(transaction)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help("Edit transaction")
                        .accessibilityLabel(settings.localized("Edit transaction"))

                        Button(role: .destructive) {
                            activeAlert = .deleteTransaction(transaction)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete transaction")
                        .accessibilityLabel(settings.localized("Delete transaction"))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editor = .transaction(transaction)
            } label: {
                Label("Edit Transaction", systemImage: "pencil")
            }

            Button(role: .destructive) {
                activeAlert = .deleteTransaction(transaction)
            } label: {
                Label("Delete Transaction", systemImage: "trash")
            }
        }
    }

    private var filteredTransactions: [Transaction] {
        // Hoist the period bounds out of the per-row closure (both were recomputed per transaction).
        let startDate = transactionStartDate
        let endDate = transactionEndDate
        // Matched on the category field only — deliberately not folded into `searchText`, which
        // also matches descriptions and could not express the multi-category "Smaller categories"
        // node in the first place.
        let categories = categoryFilter?.categories
        return finance.transactions.filter { transaction in
            let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
            let matchesPeriod = startDate.map { start in
                transaction.date >= start && (endDate.map { transaction.date <= $0 } ?? true)
            } ?? true
            let matchesSearch = searchText.isEmpty
                || transaction.category.localizedCaseInsensitiveContains(searchText)
                || transaction.description.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = categories.map { $0.contains(transaction.category) } ?? true
            return matchesType && matchesPeriod && matchesSearch && matchesCategory
        }
    }


    /// The same window `AnalyticsEngine.filteredTransactions` uses, from the same definition.
    ///
    /// This used to be a second copy of the rule, which is how it drifted: it computed `now - N`
    /// where the engine counted N-1 back from today, so the Money Flow drill-through listed a day
    /// more than the node it was opened from.
    private var transactionStartDate: Date? {
        transactionPeriod.firstIncludedDay(relativeTo: Date(), calendar: .current)
    }

    /// L17: the upper bound of the period window. Rolling windows (7/30/90 days) end at *now* — a
    /// post-dated transaction genuinely isn't in the "last N days". Year-to-date spans the whole
    /// calendar year, so a future-this-year entry stays visible in the table instead of silently
    /// vanishing until 'All'. (The chart/totals still exclude unrealized future flow via
    /// AnalyticsEngine's own `<= now` clamp; the table lists what has been entered.)
    private var transactionEndDate: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch transactionPeriod {
        case .sevenDays, .thirtyDays, .threeMonths:
            return now
        case .yearToDate:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
                .flatMap { calendar.date(byAdding: DateComponents(year: 1, second: -1), to: $0) }
        case .all:
            return nil
        }
    }

    /// The three properties below decide what the transaction table shows when it has nothing to
    /// list, and each of them branched on `finance.transactions.isEmpty` — saying in words, in an
    /// icon and in a sentence whether this person has *never* recorded a transaction or merely has
    /// none matching the current filters. Every one of those filters is a control in the bar above
    /// the table, so the pair is a probe: vary a filter, read off what exists, with every amount
    /// already `••••`. Under Privacy Mode all three collapse to one data-independent answer, or
    /// the distinction survives in whichever one is left un-gated.
    ///
    /// Only the empty arms are merged. A populated table still lists its rows — ranked lists are a
    /// separate ruling (TO_SIMO_DO.md) — so this closes the *reason* the table is empty.
    private var transactionEmptyTitle: String {
        if settings.isPrivacyMode {
            return settings.localized("Hidden by Privacy Mode")
        }
        if finance.transactions.isEmpty {
            return settings.localized("No Transactions")
        }
        return settings.localized("No Matching Transactions")
    }

    private var transactionEmptySystemImage: String {
        if settings.isPrivacyMode { return "eye.slash" }
        return finance.transactions.isEmpty ? "arrow.left.arrow.right" : "line.3.horizontal.decrease.circle"
    }

    private var transactionEmptyDescription: String {
        if settings.isPrivacyMode {
            return settings.localized("Turn off Privacy Mode to reveal this.")
        }
        if finance.transactions.isEmpty {
            return settings.localized("Add your first income or expense.")
        }
        // Right after a drill-through the category chip is the likeliest culprit, and it is the one
        // filter the old copy never mentioned — narrowing the period afterwards would empty the
        // list with no explanation on screen.
        if categoryFilter != nil {
            return settings.localized("Clear the category chip, or change the search, type, or period filters.")
        }
        return settings.localized("Change the search, type, or period filters.")
    }

    private func signedAmount(for transaction: Transaction) -> String {
        guard !settings.isPrivacyMode else { return settings.redactionToken }
        let prefix = transaction.type == .income ? "+" : "−"
        // Show each row in its own currency (deep-audit H5); totals stay converted.
        return prefix + settings.formatSourceCurrency(transaction.amount, currency: transaction.currency ?? settings.currency)
    }

    private func saveRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.upsertRecurringTransaction(schedule)

        Task { @MainActor in
            if schedule.notificationsEnabled {
                let authorized = await MacRecurringTransactionNotificationService.shared.requestAuthorization()
                if !authorized {
                    finance.setRecurringNotificationsEnabled(id: schedule.id, isEnabled: false)
                    activeAlert = .message(
                        title: settings.localized("Notifications Disabled"),
                        message: settings.localized("The schedule was saved, but notifications are not authorized. You can enable them in System Settings and then edit this schedule.")
                    )
                }
            }
            await syncRecurringNotifications()
        }
    }

    private func toggleRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.setRecurringTransactionActive(schedule, isActive: !schedule.isActive)
        Task { await syncRecurringNotifications() }
    }

    private func finishRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.completeRecurringTransaction(schedule)
        Task {
            await MacRecurringTransactionNotificationService.shared.cancel(scheduleID: schedule.id)
        }
    }

    private func syncRecurringNotifications() async {
        let schedules = finance.data.recurringTransactions
        let convertedAmounts = Dictionary(
            schedules.map { ($0.id, settings.convert($0.amount, from: $0.currency)) },
            uniquingKeysWith: { first, _ in first }
        )
        await MacRecurringTransactionNotificationService.shared.sync(
            schedules: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: settings.currency.rawValue,
            showDetails: !settings.isPrivacyMode
        )
    }

    private func alert(for alert: MacCashFlowAlert) -> Alert {
        switch alert {
        case .deleteTransaction(let transaction):
            return Alert(
                title: Text("Delete Transaction?"),
                message: Text(
                    settings.localized("This permanently removes the \(transaction.category) transaction from \(settings.date(transaction.date)).")
                ),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteTransaction(transaction, settings: settings)
                },
                secondaryButton: .cancel()
            )

        case .deleteRecurringTransaction(let schedule):
            return Alert(
                title: Text("Delete Recurring Transaction?"),
                message: Text(settings.localized("Future \(schedule.frequency.localizedTitle(appLanguage: settings.appLanguage).lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))) occurrences for \(schedule.category) will no longer be created.")),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteRecurringTransaction(schedule)
                    Task {
                        await MacRecurringTransactionNotificationService.shared.cancel(scheduleID: schedule.id)
                    }
                },
                secondaryButton: .cancel()
            )

        case .finishRecurringTransaction(let schedule):
            return Alert(
                title: Text("Finish Recurring Transaction?"),
                message: Text(
                    settings.localized("\(schedule.category) will disappear from Recurring Transactions and no future occurrences will be inserted automatically.")
                ),
                primaryButton: .default(Text("Finish")) {
                    finishRecurringTransaction(schedule)
                },
                secondaryButton: .cancel()
            )

        case .message(let title, let message):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

}

private struct MacCashFlowTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let transaction: Transaction?
    let onSave: (Transaction?, TransactionType, Decimal, String, String, Date, Currency) -> Void

    private static let customCategoryTag = "__wealth_compass_mac_custom_category__"

    @State private var type: TransactionType
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @State private var currency: Currency
    @State private var hasInitializedCurrency = false
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

    init(
        transaction: Transaction? = nil,
        onSave: @escaping (Transaction?, TransactionType, Decimal, String, String, Date, Currency) -> Void
    ) {
        self.transaction = transaction
        self.onSave = onSave
        _type = State(initialValue: transaction?.type ?? .expense)
        _amount = State(initialValue: transaction.map { AmountInputFormatter.string($0.amount) } ?? "")
        _category = State(initialValue: transaction?.category ?? "Food")
        _note = State(initialValue: transaction?.description ?? "")
        _date = State(initialValue: transaction?.date ?? Date())
        _currency = State(initialValue: transaction?.currency ?? .eur)
    }

    private var categories: [String] {
        settings.transactionCategories(for: type)
    }

    private var trimmedCustomCategory: String {
        customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCustomCategorySelected: Bool {
        category == Self.customCategoryTag
    }

    private var currentCategoryName: String {
        isCustomCategorySelected ? trimmedCustomCategory : category
    }

    private var parsedAmount: Decimal? {
        MoneyParser.decimal(from: amount)
    }

    private var isSaveDisabled: Bool {
        guard let parsedAmount, parsedAmount > 0 else { return true }
        return currentCategoryName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        if !settings.transactionCategories(for: newType).contains(category) && !isCustomCategorySelected {
                            category = settings.transactionCategories(for: newType).first ?? ""
                        }
                        // M08: preserve an in-progress custom category name across a type toggle — a
                        // custom category isn't tied to income vs expense, so don't wipe it (mirrors
                        // MacTransactionEditor in MacEditorSheet; the sibling editor already had this).
                        if !isCustomCategorySelected {
                            customCategory = ""
                            isCustomCategoryFocused = false
                        }
                    }

                    TextField("Amount (\(currency.rawValue))", text: $amount)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currencyOption in
                            (Text(currencyOption.localizedDisplayName(appLanguage: settings.appLanguage)) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        // DA-H06: keep the current value selectable even if it isn't in the type's
                        // default+custom list (imported/legacy category, or the transient state mid
                        // type-toggle) so the selection always has a matching tag — no "selection is
                        // invalid" warning, no silent category rewrite on save (mirrors MacTransactionEditor).
                        if category != Self.customCategoryTag && !categories.contains(category) {
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        ForEach(categories, id: \.self) { category in
                            // Localize built-in category names; custom user ones fall through verbatim (WC-M10).
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        Text("Custom...").tag(Self.customCategoryTag)
                    }
                    .onChange(of: category) { _, newCategory in
                        if newCategory == Self.customCategoryTag {
                            Task { @MainActor in
                                isCustomCategoryFocused = true
                            }
                        } else {
                            customCategory = ""
                            isCustomCategoryFocused = false
                        }
                    }

                    if isCustomCategorySelected {
                        TextField("Custom category name", text: $customCategory)
                            .focused($isCustomCategoryFocused)

                        Text(settings.localized("The category will be saved for future \(type.localizedTitle(appLanguage: settings.appLanguage).lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))) transactions."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                guard !hasInitializedCurrency else { return }
                if transaction == nil { currency = settings.currency }
                hasInitializedCurrency = true
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTransaction)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 400, idealHeight: 480)
    }

    private func saveTransaction() {
        guard let parsedAmount, parsedAmount > 0 else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        onSave(transaction, type, parsedAmount, selectedCategory, note, date, currency)
        dismiss()
    }
}
