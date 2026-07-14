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
    @State private var searchText = ""
    @State private var analyticsPeriod: AnalyticsPeriod = .all
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: MacTransactionTypeFilter = .all
    @State private var editor: MacCashFlowEditor?
    @State private var activeAlert: MacCashFlowAlert?
    @State private var selectedTab: MacCashFlowTab = .overview
    @State private var cashFlowRange: CashFlowTimeframe = .sixMonths
    @State private var hoveredExpenseCategory: CategoryTotal?
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

                            if proxy.size.width >= 1_090 {
                                HStack(alignment: .top, spacing: 20) {
                                    cashFlowTrendCard
                                        .frame(width: max(340, proxy.size.width * 0.55))
                                    expenseCategoriesCard
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                VStack(spacing: 20) {
                                    cashFlowTrendCard
                                    expenseCategoriesCard
                                }
                            }

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
                systemImage: "arrow.up.right",
                accent: WCColor.primary
            )
            MetricCard(
                title: "Monthly Expenses",
                value: settings.privateCurrency(cashFlow.monthlyExpenses),
                systemImage: "arrow.down.right",
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
                    : "\(cashFlow.savingsRate.formatted(.number.precision(.fractionLength(1))))%",
                systemImage: "percent"
            )
            MetricCard(
                title: "Transactions",
                value: settings.isPrivacyMode ? settings.redactionToken : "\(monthlyTransactionsCount)",
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

                if !hasCashFlow {
                    EmptyState(title: "No recent cash flow", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 244)
                } else if settings.isPrivacyMode {
                    EmptyState(title: "Cash-flow chart concealed", systemImage: "eye.slash")
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

    private var expenseCategoriesCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expense Categories")
                            .font(.headline)
                        Text("Breakdown of recorded spending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Expense period", selection: $analyticsPeriod) {
                        ForEach(AnalyticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }

                let categories = finance.expensesByCategory(period: analyticsPeriod, settings: settings)
                let totalExpenses = categories.reduce(0) { $0 + $1.value }
                if categories.isEmpty {
                    EmptyState(title: "No expenses for this period", systemImage: "chart.pie")
                        .frame(maxWidth: .infinity, minHeight: 244)
                } else {
                    ZStack {
                        Chart(categories) { item in
                            SectorMark(
                                angle: .value("Expense", item.value),
                                innerRadius: .ratio(0.62),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Category", item.name))
                            .cornerRadius(5)
                            .opacity(hoveredExpenseCategory == nil || hoveredExpenseCategory?.id == item.id ? 1.0 : 0.3)
                            .accessibilityLabel(Text(item.name))
                            .accessibilityValue(Text(settings.privateCurrency(item.value)))
                        }
                        .chartLegend(.hidden)
                        .chartBackground { proxy in
                            GeometryReader { geometry in
                                if let plotFrame = proxy.plotFrame {
                                    let frame = geometry[plotFrame]
                                    VStack(spacing: 3) {
                                        if let hoveredExpenseCategory {
                                            Text(hoveredExpenseCategory.name)
                                                .textCase(.uppercase)
                                                .font(.caption2.weight(.bold))
                                                .tracking(1.3)
                                                .foregroundStyle(.white.opacity(0.8))
                                            Text(settings.privateCurrency(hoveredExpenseCategory.value))
                                                .font(.headline.monospacedDigit().weight(.bold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                            Text("\(hoveredExpenseCategory.percentage.formatted(.number.precision(.fractionLength(1))))%")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.6))
                                        } else {
                                            Text("EXPENSES")
                                                .font(.caption2.weight(.bold))
                                                .tracking(1.3)
                                                .foregroundStyle(WCColor.textTertiary)
                                            Text(settings.privateCurrency(totalExpenses))
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
                                                    hoveredExpenseCategory = categorySlice(at: location, in: frame, categories: categories)
                                                }
                                            case .ended:
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredExpenseCategory = nil
                                                }
                                            }
                                        }
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: categories.map(\.value))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Expense Categories"))
                    }
                    .frame(minHeight: 250, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
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

                if transactions.isEmpty {
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

                if finance.recurringTransactions.isEmpty {
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
            Image(systemName: schedule.type == .income ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)
                .font(.title2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(schedule.category)
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
                        Text("Next \(schedule.nextDueDate.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Paused")
                            .foregroundStyle(WCColor.warning)
                    }
                    if let endDate = schedule.endDate {
                        Text("Ends \(endDate.formatted(date: .abbreviated, time: .omitted))")
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

                Button {
                    activeAlert = .finishRecurringTransaction(schedule)
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Finish schedule")

                Button {
                    editor = .recurring(schedule)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit schedule")

                Button(role: .destructive) {
                    activeAlert = .deleteRecurringTransaction(schedule)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete schedule")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(WCColor.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var transactionFilters: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                Text("Type")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $transactionTypeFilter) {
                    ForEach(MacTransactionTypeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

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
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .frame(width: 200)

            HStack(spacing: 10) {
                Text("Period")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $transactionPeriod) {
                    ForEach(AnalyticsPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Text("Showing \(filteredTransactions.count) of \(finance.transactions.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
                            Text(transaction.category)
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
                        Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
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

                        Button(role: .destructive) {
                            activeAlert = .deleteTransaction(transaction)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete transaction")
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
        return finance.transactions.filter { transaction in
            let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
            let matchesPeriod = startDate.map { start in
                transaction.date >= start && (endDate.map { transaction.date <= $0 } ?? true)
            } ?? true
            let matchesSearch = searchText.isEmpty
                || transaction.category.localizedCaseInsensitiveContains(searchText)
                || transaction.description.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesPeriod && matchesSearch
        }
    }


    private var transactionStartDate: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch transactionPeriod {
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .yearToDate:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .all:
            return nil
        }
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

    private var transactionEmptyTitle: String {
        if finance.transactions.isEmpty {
            return settings.localized("No Transactions")
        }
        return settings.localized("No Matching Transactions")
    }

    private var transactionEmptySystemImage: String {
        finance.transactions.isEmpty ? "arrow.left.arrow.right" : "line.3.horizontal.decrease.circle"
    }

    private var transactionEmptyDescription: String {
        if finance.transactions.isEmpty {
            return settings.localized("Add your first income or expense.")
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
            showAmounts: !settings.isPrivacyMode
        )
    }

    private func alert(for alert: MacCashFlowAlert) -> Alert {
        switch alert {
        case .deleteTransaction(let transaction):
            return Alert(
                title: Text("Delete Transaction?"),
                message: Text(
                    settings.localized("This permanently removes the \(transaction.category) transaction from \(transaction.date.formatted(date: .abbreviated, time: .omitted)).")
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

    private func categorySlice(at location: CGPoint, in rect: CGRect, categories: [CategoryTotal]) -> CategoryTotal? {
        // WC-L15: `total` was dead — `PieSliceHitTester.sliceIndex` derives the total from `values`.
        return PieSliceHitTester.sliceIndex(at: location, in: rect, values: categories.map(\.value))
            .map { categories[$0] }
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
                            (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
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
