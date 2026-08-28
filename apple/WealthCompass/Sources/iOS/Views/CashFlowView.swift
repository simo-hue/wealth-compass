import SwiftUI
import Charts

private enum TransactionListTypeFilter: String, CaseIterable, Identifiable {
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

/// Overview / Transactions split for the Cash Flow tab, mirroring the macOS selector island so iOS
/// gets a dedicated, searchable, uncapped transactions view.
///
/// Internal rather than `private` so `CashFlowView(initialTab:)` can name it — see that
/// initializer for why it exists.
enum CashFlowTab: String, CaseIterable, Identifiable {
    case overview
    case transactions

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .transactions: "Transactions"
        }
    }
}

struct CashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var recurringEditor: RecurringTransactionEditor?
    /// Collapsed by default: finished schedules are a recovery affordance, not daily reading.
    @State private var isCompletedRecurringExpanded = false
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: TransactionListTypeFilter = .all
    @State private var transactionSearch = ""
    @State private var selectedTab: CashFlowTab
    @State private var activeAlert: CashFlowAlert?
    @State private var hoveredExpenseCategory: CategoryTotal?

    /// The tab the view opens on. The app always takes the default; the parameter exists so the
    /// transaction list can be reached from a test, which is otherwise impossible — the tab lives
    /// in `@State`, and driving the segmented picker from outside moves the UIKit control's
    /// selection without ever updating the SwiftUI binding (measured: the pill slides, the content
    /// does not change). Same shape as `DashboardView(selectedTab:)`.
    init(initialTab: CashFlowTab = .overview) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Cash flow", subtitle: "Understand what comes in and where it goes.") {
                    Menu {
                        Button {
                            showingAddTransaction = true
                        } label: {
                            Label("One-Time", systemImage: "plus.circle")
                        }

                        Button {
                            recurringEditor = RecurringTransactionEditor(schedule: nil)
                        } label: {
                            Label("Recurring", systemImage: "repeat.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black.opacity(0.82))
                            .frame(width: 44, height: 44)
                            .background(WCColor.primary.gradient, in: Circle())
                            .shadow(color: WCColor.primary.opacity(0.24), radius: 10, y: 5)
                            .accessibilityLabel("Add Transaction") // WC-L24: was an unlabeled "+" glyph
                    }
                    .buttonStyle(.plain)
                }

                cashFlowTabPicker

                if selectedTab == .overview {
                    summaryCards
                    recurringTransactions
                    analytics
                } else {
                    transactions
                }
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(isPresented: $showingAddTransaction) {
            TransactionFormView { _, type, amount, category, description, date, currency in
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
        .sheet(item: $transactionToEdit) { transaction in
            TransactionFormView(transaction: transaction) { original, type, amount, category, description, date, currency in
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
                }
            } onDelete: {
                finance.deleteTransaction(transaction, settings: settings)
            }
        }
        .sheet(item: $recurringEditor) { editor in
            RecurringTransactionFormView(schedule: editor.schedule) { schedule in
                saveRecurringTransaction(schedule)
            }
        }
        .alert(item: $activeAlert, content: alert(for:))
    }

    private var cashFlowTabPicker: some View {
        Picker("Cash flow view", selection: $selectedTab) {
            ForEach(CashFlowTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryCards: some View {
        let cashFlow = finance.monthlyCashFlow(for: Date(), settings: settings)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Monthly Income", value: settings.privateCurrency(cashFlow.monthlyIncome), systemImage: "arrow.down.left", accent: WCColor.primary, detail: "This month")
            MetricCard(title: "Monthly Expenses", value: settings.privateCurrency(cashFlow.monthlyExpenses), systemImage: "arrow.up.right", accent: WCColor.destructive, detail: "This month")
            MetricCard(title: "Net Savings", value: settings.privateCurrency(cashFlow.netSavings), systemImage: "wallet.pass.fill", accent: settings.privateAccent(isPositive: cashFlow.netSavings >= 0), detail: "Income less expenses")
            MetricCard(title: "Savings Rate", value: settings.isPrivacyMode ? settings.redactionToken : formattedPercent(cashFlow.savingsRate, locale: settings.effectiveLocale), systemImage: "percent", detail: "Of monthly income")
        }
    }

    private var analytics: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionHeading("Spending analytics", subtitle: "Expenses grouped by category")
                    Spacer()
                    Picker("Period", selection: $period) {
                        ForEach(AnalyticsPeriod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WCColor.primary)
                }

                let categories = finance.expensesByCategory(period: period, settings: settings)
                let totalExpenses = categories.reduce(0) { $0 + $1.value }
                if settings.isPrivacyMode {
                    // The arcs are the proportions: leaving the donut drawn while its labels
                    // redact still shows a bystander how the spending splits. Same conceal the
                    // net-worth and cash-flow cards use (`DashboardView.swift:193`, `:416`).
                    // The category list below stays as it is — deliberately, ranked lists are
                    // a separate open decision (TO_SIMO_DO.md).
                    //
                    // The title names *this* card's chart, as its two neighbours do. It used to
                    // reuse `AllocationChart`'s "Allocation concealed" to avoid a new key, but
                    // this card is headed "Spending analytics" and its donut is expenses by
                    // category, not an allocation — the cover was naming a chart that is not here.
                    MobilePrivacyChartCover(
                        title: "Spending breakdown concealed",
                        message: "Values and proportions are hidden."
                    )
                    .frame(minHeight: 250, maxHeight: .infinity)
                } else if categories.isEmpty {
                    EmptyState(title: "No expenses for this period", systemImage: "chart.pie")
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
                            .accessibilityLabel(Text(LocalizedStringKey(item.name)))
                            .accessibilityValue(Text(settings.privateCurrency(item.value)))
                        }
                        .chartLegend(.hidden)
                        .chartBackground { proxy in
                            GeometryReader { geometry in
                                if let plotFrame = proxy.plotFrame {
                                    let frame = geometry[plotFrame]
                                    VStack(spacing: 3) {
                                        if let hoveredExpenseCategory {
                                            Text(LocalizedStringKey(hoveredExpenseCategory.name))
                                                .textCase(.uppercase)
                                                .font(.caption2.weight(.bold))
                                                .tracking(1.3)
                                                .foregroundStyle(.white.opacity(0.8))
                                            Text(settings.privateCurrency(hoveredExpenseCategory.value))
                                                .font(.headline.monospacedDigit().weight(.bold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                            // M30: the share % also reveals the spending breakdown, so
                                            // redact it in Privacy Mode like the amount above it.
                                            Text(verbatim: settings.privatePercent(hoveredExpenseCategory.percentage))
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
                                        // A tap, not a zero-distance drag: the drag wins the pan
                                        // from this page's ScrollView, so a swipe starting on the
                                        // donut scrubbed it instead of scrolling. This donut is
                                        // hand-written rather than an `AllocationChart`, which is
                                        // why it survived the first sweep of that pattern.
                                        .gesture(
                                            SpatialTapGesture()
                                                .onEnded { value in
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredExpenseCategory = categorySlice(at: value.location, in: frame, categories: categories)
                                                    }
                                                }
                                        )
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: categories.map(\.value))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Spending analytics"))
                    }
                    .frame(minHeight: 250, maxHeight: .infinity)
                }

                // The ranked list stays a sibling of all three branches, so it renders under the
                // cover too: ranked lists are a separate open decision (TO_SIMO_DO.md).
                if !categories.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(categories.prefix(6)) { item in
                            HStack {
                                Text(LocalizedStringKey(item.name))
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    // M30: same pair as the donut centre — the share reconstructs the
                                    // amount masked above it, so both halves go at once.
                                    Text(verbatim: settings.privatePercent(item.percentage))
                                        .font(.caption)
                                        .foregroundStyle(WCColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var recurringTransactions: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    SectionHeading("Recurring Transactions", subtitle: "Automatic income and expenses")
                    Spacer()
                    Button {
                        recurringEditor = RecurringTransactionEditor(schedule: nil)
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WCColor.primary)
                }

                // Privacy before emptiness, as at the transaction list below: the sentence states
                // that this person keeps no standing income or expenses. The populated arm still
                // lists its schedules (a separate ruling), so what stops is the sentence.
                if settings.isPrivacyMode, finance.recurringTransactions.isEmpty {
                    EmptyState(title: "Hidden by Privacy Mode", systemImage: "eye.slash")
                } else if finance.recurringTransactions.isEmpty {
                    EmptyState(title: "No recurring transactions", systemImage: "repeat")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.recurringTransactions) { schedule in
                            recurringTransactionRow(schedule)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        activeAlert = .deleteRecurringTransaction(schedule)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                completedRecurringSection

                Text("Due schedules are recorded automatically while the app is active and caught up the next time it opens.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            }
        }
    }

    /// Finished schedules, collapsed by default.
    ///
    /// The list above hides them, because the confirmation alert promises the schedule "will
    /// disappear from Recurring Transactions" and that copy ships in 34 languages. Hiding them is
    /// also what made finishing irreversible: delete is only reachable from a row, so a schedule
    /// finished by mistake could not be removed at all. A collapsed section keeps the promise —
    /// the row is gone from the live list — while giving the record somewhere to be deleted from.
    ///
    /// Absent entirely when there is nothing finished, so it costs no space for most people.
    @ViewBuilder
    private var completedRecurringSection: some View {
        let completed = finance.completedRecurringTransactions
        if !completed.isEmpty, !settings.isPrivacyMode {
            DisclosureGroup(isExpanded: $isCompletedRecurringExpanded) {
                VStack(spacing: 12) {
                    ForEach(completed) { schedule in
                        recurringTransactionRow(schedule)
                            .contextMenu {
                                Button(role: .destructive) {
                                    activeAlert = .deleteRecurringTransaction(schedule)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.top, 10)
            } label: {
                // Reuses the existing `Completed` key rather than introducing a
                // "Completed (%lld)" one: that key is already translated in 34 locales, and a new
                // interpolated key would ship English everywhere until someone translated it. The
                // count is formatted for the reader's locale — a bare "\(count)" is exactly what
                // `testWorkingTreeRendersNoUnformattedEntityCount` exists to catch.
                HStack(spacing: 6) {
                    Text("Completed")
                    Text(completed.count.formatted(.number.locale(settings.effectiveLocale)))
                        .monospacedDigit()
                        .opacity(0.7)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WCColor.textSecondary)
            }
            .tint(WCColor.textSecondary)
        }
    }

    private func recurringTransactionRow(_ schedule: RecurringTransaction) -> some View {
        InsetFinanceRow {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: schedule.type == .income ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)
                    .frame(width: 34, height: 34)
                    .background(
                        (schedule.type == .income ? WCColor.primary : WCColor.destructive).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(schedule.category))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Image(systemName: schedule.notificationsEnabled ? "bell.fill" : "bell.slash")
                            .font(.caption2)
                            .foregroundStyle(WCColor.textSecondary)
                    }

                    Text(schedule.frequency.title)
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)

                    if schedule.isCompleted {
                        Text("Completed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WCColor.primary)
                    } else if schedule.isActive {
                        Text("Next: \(settings.date(schedule.nextDueDate, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    } else {
                        Text("Paused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WCColor.warning)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 9) {
                    let prefix = schedule.type == .income ? "+" : "-"
                    Text("\(prefix)\(settings.privateSourceCurrency(schedule.amount, currency: schedule.currency ?? settings.currency))")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)

                    HStack(spacing: 0) {
                        if !schedule.isCompleted {
                            Button {
                                activeAlert = .finishRecurringTransaction(schedule)
                            } label: {
                                Image(systemName: "checkmark")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Finish schedule")

                            Button {
                                toggleRecurringTransaction(schedule)
                            } label: {
                                Image(systemName: schedule.isActive ? "pause.fill" : "play.fill")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(schedule.isActive
                                ? settings.localized("Pause schedule")
                                : settings.localized("Resume schedule"))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Schedule completed")
                        }

                        Button {
                            recurringEditor = RecurringTransactionEditor(schedule: schedule)
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Edit schedule")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WCColor.primary)
                }
            }
        }
    }

    private var transactions: some View {
        // WC-M13: derive the filtered list once per render. `finance.transactions` is cached-sorted,
        // and `filteredTransactions` runs the type/period/search filter a single time here.
        // `finance.data.transactions` is the unsorted backing array, so the emptiness check is free.
        let hasAnyTransactions = !finance.data.transactions.isEmpty
        let filtered = filteredTransactions
        return FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                transactionHeader(shownCount: filtered.count, totalCount: finance.transactions.count)
                transactionFilters
                transactionSearchField

                // The two empty states below say different things: one that this person has never
                // recorded a transaction, the other that they have but none match. Both are
                // reachable from the filter row directly above — set a type, narrow the period,
                // type a search — so a bystander can walk the controls and map which windows,
                // categories and types hold records without a single figure being legible. That is
                // the probe `DashboardView.swift:202-205` and `SankeyDiagramView.swift:45-53`
                // already refuse to offer. Under Privacy Mode the distinction collapses: whichever
                // reason the list is empty for, the card draws the same thing.
                //
                // Only the two empty arms are merged. The populated arm still renders its rows —
                // ranked lists are a separate ruling (TO_SIMO_DO.md) — so this closes the *reason*
                // the list is empty, not the fact that it is.
                if settings.isPrivacyMode, filtered.isEmpty {
                    EmptyState(title: "Hidden by Privacy Mode", systemImage: "eye.slash")
                } else if !hasAnyTransactions {
                    EmptyState(title: "No transactions found", systemImage: "tray")
                } else if filtered.isEmpty {
                    EmptyState(title: "No transactions match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    // LazyVStack so the full (uncapped) list only renders the rows on screen.
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { transaction in
                            transactionRow(transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    transactionToEdit = transaction
                                }
                                // WC-L24: expose the tap-to-edit affordance to VoiceOver / Switch
                                // Control as one activatable button (onTapGesture alone isn't surfaced).
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { transactionToEdit = transaction }
                                .contextMenu {
                                    Button {
                                        transactionToEdit = transaction
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        activeAlert = .deleteTransaction(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func transactionHeader(shownCount: Int, totalCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Transactions")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // Two leaks in four lines. The numbers are exact counts of what exists and what the
            // filters matched, and the `totalCount > 0` gate means the row itself only appears
            // once there is something to count — so under Privacy Mode both the value and the
            // slot had to stop moving with the data. Tokenised rather than hidden, and drawn
            // unconditionally: `Showing •••• of ••••` is the same row in both data states, and it
            // still tells the reader a filter is narrowing a list.
            if settings.isPrivacyMode {
                Text("Showing \(settings.redactionToken) of \(settings.redactionToken)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WCColor.textSecondary)
            } else if totalCount > 0 {
                Text("Showing \(shownCount) of \(totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WCColor.textSecondary)
            }
        }
    }

    private var transactionSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WCColor.textSecondary)
            TextField("Search", text: $transactionSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
            if !transactionSearch.isEmpty {
                Button {
                    transactionSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WCColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var transactionFilters: some View {
        VStack(spacing: 10) {
            Picker("Transaction Type", selection: $transactionTypeFilter) {
                ForEach(TransactionListTypeFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label("Period", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(WCColor.textSecondary)

                Spacer()

                Picker("Transaction Period", selection: $transactionPeriod) {
                    ForEach(AnalyticsPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(WCColor.primary)
            }
        }
    }

    private var filteredTransactions: [Transaction] {
        let query = transactionSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return finance.transactions.filter { transaction in
            let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
            let matchesPeriod = transactionStartDate.map { transaction.date >= $0 && transaction.date <= Date() } ?? true
            // Search matches category or description, case-insensitively but *not* diacritic- or
            // width-insensitively: `localizedCaseInsensitiveContains` folds case only, so "cafe"
            // does not find "Café". `MacCashFlowView` matches the same way, so the two lists agree;
            // moving either to `localizedStandardContains` means moving both.
            let matchesSearch = query.isEmpty
                || transaction.category.localizedCaseInsensitiveContains(query)
                || transaction.description.localizedCaseInsensitiveContains(query)
            return matchesType && matchesPeriod && matchesSearch
        }
    }


    /// The same window `AnalyticsEngine.filteredTransactions` uses, from the same definition.
    ///
    /// This was a third copy of the rule and the loosest: it neither counted back N-1 nor snapped
    /// to the start of the day, so it disagreed with the Mac list as well as with the analytics.
    private var transactionStartDate: Date? {
        transactionPeriod.firstIncludedDay(relativeTo: Date(), calendar: .current)
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        InsetFinanceRow {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: transaction.type == .income ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                    .frame(width: 34, height: 34)
                    .background(
                        (transaction.type == .income ? WCColor.primary : WCColor.destructive).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(transaction.category))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if transaction.recurringTransactionID != nil {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(WCColor.primary)
                        }
                        Text(settings.date(transaction.date))
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    if !transaction.description.isEmpty {
                        Text(transaction.description)
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }

                Spacer()

                let prefix = transaction.type == .income ? "+" : "-"
                Text("\(prefix)\(settings.privateSourceCurrency(transaction.amount, currency: transaction.currency ?? settings.currency))")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
            }
        }
    }

    private func saveRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.upsertRecurringTransaction(schedule)

        // Deep-audit L06 (assessed, intentionally left as fire-and-forget): these `Task {}`s in the
        // recurring-schedule handlers are one-shot notification-sync side effects. They inherit this
        // View's `@MainActor` isolation, so their post-`await` writes (`activeAlert`, store mutations)
        // are main-actor-safe, and SwiftUI simply drops `@State` writes if the view is gone — so there's
        // no torn-state hazard and nothing to cancel. Kept unstructured deliberately; do not "fix".
        Task {
            if schedule.notificationsEnabled {
                let authorized = await RecurringTransactionNotificationService.shared.requestAuthorization()
                if !authorized {
                    finance.setRecurringNotificationsEnabled(id: schedule.id, isEnabled: false)
                    activeAlert = .message(
                        title: settings.localized("Notifications Disabled"),
                        message: settings.localized("The schedule was saved, but notifications are not authorized. You can enable them in iOS Settings and then edit this schedule.")
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

    private func completeRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.completeRecurringTransaction(schedule)
        Task {
            await RecurringTransactionNotificationService.shared.cancel(scheduleID: schedule.id)
        }
    }

    private func syncRecurringNotifications() async {
        let schedules = finance.data.recurringTransactions
        let convertedAmounts = Dictionary(
            schedules.map { ($0.id, settings.convert($0.amount, from: $0.currency)) },
            uniquingKeysWith: { first, _ in first }
        )
        await RecurringTransactionNotificationService.shared.sync(
            schedules: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: settings.currency.rawValue,
            showDetails: !settings.isPrivacyMode
        )
    }

    private func alert(for alert: CashFlowAlert) -> Alert {
        switch alert {
        case .deleteTransaction(let transaction):
            return Alert(
                title: Text("Delete Transaction?"),
                message: Text(settings.localized("This permanently removes the \(transaction.category) transaction from \(settings.date(transaction.date)).")),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteTransaction(transaction, settings: settings)
                },
                secondaryButton: .cancel()
            )

        case .deleteRecurringTransaction(let schedule):
            return Alert(
                title: Text("Delete Recurring Transaction?"),
                message: Text(settings.localized("Future \(schedule.frequency.localizedTitle(appLanguage: settings.appLanguage)) occurrences for \(schedule.category) will no longer be created.")),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteRecurringTransaction(schedule)
                    Task {
                        await RecurringTransactionNotificationService.shared.cancel(scheduleID: schedule.id)
                    }
                },
                secondaryButton: .cancel()
            )

        case .finishRecurringTransaction(let schedule):
            return Alert(
                title: Text("Finish Recurring Transaction?"),
                message: Text(settings.localized("\(schedule.category) will disappear from Recurring Transactions and no future occurrences will be inserted automatically.")),
                primaryButton: .default(Text("Yes")) {
                    completeRecurringTransaction(schedule)
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
        PieSliceHitTester.sliceIndex(at: location, in: rect, values: categories.map(\.value))
            .map { categories[$0] }
    }
}

private struct RecurringTransactionEditor: Identifiable {
    let id = UUID()
    let schedule: RecurringTransaction?
}

private enum CashFlowAlert: Identifiable {
    case deleteTransaction(Transaction)
    case deleteRecurringTransaction(RecurringTransaction)
    case finishRecurringTransaction(RecurringTransaction)
    case message(title: String, message: String)

    var id: String {
        switch self {
        case .deleteTransaction(let transaction):
            return "delete-transaction-\(transaction.id)"
        case .deleteRecurringTransaction(let schedule):
            return "delete-recurring-\(schedule.id)"
        case .finishRecurringTransaction(let schedule):
            return "finish-recurring-\(schedule.id)"
        case .message(let title, let message):
            return "message-\(title)-\(message)"
        }
    }
}
