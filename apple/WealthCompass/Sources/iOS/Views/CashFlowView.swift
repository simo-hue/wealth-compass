import SwiftUI
import Charts

private enum TransactionListTypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .income: String(localized: "Income")
        case .expense: String(localized: "Expense")
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

struct CashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTransaction = false
    @State private var recurringEditor: RecurringTransactionEditor?
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: TransactionListTypeFilter = .all
    @State private var activeAlert: CashFlowAlert?
    @State private var hoveredExpenseCategory: CategoryTotal?

    private let transactionDisplayLimit = 40

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
                            .frame(width: 42, height: 42)
                            .background(WCColor.primary.gradient, in: Circle())
                            .shadow(color: WCColor.primary.opacity(0.24), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                }

                summaryCards
                recurringTransactions
                analytics
                transactions
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(isPresented: $showingAddTransaction) {
            TransactionFormView { type, amount, category, description, date in
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
        .sheet(item: $recurringEditor) { editor in
            RecurringTransactionFormView(schedule: editor.schedule) { schedule in
                saveRecurringTransaction(schedule)
            }
        }
        .alert(item: $activeAlert, content: alert(for:))
    }

    private var summaryCards: some View {
        let cashFlow = finance.monthlyCashFlow(for: Date())
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Monthly Income", value: settings.privateCurrency(cashFlow.monthlyIncome), systemImage: "arrow.down.left", accent: WCColor.primary, detail: "This month")
            MetricCard(title: "Monthly Expenses", value: settings.privateCurrency(cashFlow.monthlyExpenses), systemImage: "arrow.up.right", accent: WCColor.destructive, detail: "This month")
            MetricCard(title: "Net Savings", value: settings.privateCurrency(cashFlow.netSavings), systemImage: "wallet.pass.fill", accent: cashFlow.netSavings >= 0 ? WCColor.primary : WCColor.destructive, detail: "Income less expenses")
            MetricCard(title: "Savings Rate", value: settings.isPrivacyMode ? "****" : "\(cashFlow.savingsRate.formatted(.number.precision(.fractionLength(1))))%", systemImage: "percent", detail: "Of monthly income")
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

                let categories = finance.expensesByCategory(period: period)
                let totalExpenses = categories.reduce(0) { $0 + $1.value }
                if categories.isEmpty {
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
                        }
                        .chartLegend(.hidden)
                        .chartBackground { proxy in
                            GeometryReader { geometry in
                                if let plotFrame = proxy.plotFrame {
                                    let frame = geometry[plotFrame]
                                    VStack(spacing: 3) {
                                        if let hoveredExpenseCategory {
                                            Text(hoveredExpenseCategory.name.uppercased())
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
                                                .foregroundStyle(.white.opacity(0.45))
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
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredExpenseCategory = categorySlice(at: value.location, in: frame, total: totalExpenses, categories: categories)
                                                    }
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredExpenseCategory = nil
                                                    }
                                                }
                                        )
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: categories.map(\.value))
                    }
                    .frame(minHeight: 250, maxHeight: .infinity)

                    VStack(spacing: 10) {
                        ForEach(categories.prefix(6)) { item in
                            HStack {
                                Text(item.name)
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    Text("\(item.percentage.formatted(.number.precision(.fractionLength(1))))%")
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

                if finance.recurringTransactions.isEmpty {
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

                Text("Due schedules are recorded automatically while the app is active and caught up the next time it opens.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            }
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
                        Text(schedule.category)
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
                        Text("Next: \(schedule.nextDueDate.formatted(date: .abbreviated, time: .shortened))")
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
                    Text("\(prefix)\(settings.privateCurrency(schedule.amount))")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)

                    HStack(spacing: 14) {
                        if !schedule.isCompleted {
                            Button {
                                activeAlert = .finishRecurringTransaction(schedule)
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .accessibilityLabel("Finish schedule")

                            Button {
                                toggleRecurringTransaction(schedule)
                            } label: {
                                Image(systemName: schedule.isActive ? "pause.fill" : "play.fill")
                            }
                            .accessibilityLabel(schedule.isActive ? String(localized: "Pause schedule") : String(localized: "Resume schedule"))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityLabel("Schedule completed")
                        }

                        Button {
                            recurringEditor = RecurringTransactionEditor(schedule: schedule)
                        } label: {
                            Image(systemName: "pencil")
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
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                transactionHeader
                transactionFilters

                if finance.transactions.isEmpty {
                    EmptyState(title: "No transactions found", systemImage: "tray")
                } else if filteredTransactions.isEmpty {
                    EmptyState(title: "No transactions match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    VStack(spacing: 12) {
                        ForEach(visibleTransactions) { transaction in
                            transactionRow(transaction)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        activeAlert = .deleteTransaction(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    if hiddenTransactionCount > 0 {
                        Text("\(hiddenTransactionCount) more transactions hidden by this view.")
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var transactionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent Transactions")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            if !finance.transactions.isEmpty {
                Text("Showing \(visibleTransactions.count) of \(filteredTransactions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WCColor.textSecondary)
            }
        }
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
        finance.transactions.filter { transaction in
            let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
            let matchesPeriod = transactionStartDate.map { transaction.date >= $0 && transaction.date <= Date() } ?? true
            return matchesType && matchesPeriod
        }
    }

    private var visibleTransactions: [Transaction] {
        Array(filteredTransactions.prefix(transactionDisplayLimit))
    }

    private var hiddenTransactionCount: Int {
        max(0, filteredTransactions.count - visibleTransactions.count)
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
                        Text(transaction.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if transaction.recurringTransactionID != nil {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(WCColor.primary)
                        }
                        Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
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
                Text("\(prefix)\(settings.privateCurrency(transaction.amount))")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
            }
        }
    }

    private func saveRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.upsertRecurringTransaction(schedule)

        Task {
            if schedule.notificationsEnabled {
                let authorized = await RecurringTransactionNotificationService.shared.requestAuthorization()
                if !authorized {
                    finance.setRecurringNotificationsEnabled(id: schedule.id, isEnabled: false)
                    activeAlert = .message(
                        title: String(localized: "Notifications Disabled"),
                        message: String(localized: "The schedule was saved, but notifications are not authorized. You can enable them in iOS Settings and then edit this schedule.")
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
        await RecurringTransactionNotificationService.shared.sync(
            schedules: finance.data.recurringTransactions,
            currencyCode: settings.currency.rawValue,
            showAmounts: !settings.isPrivacyMode
        )
    }

    private func alert(for alert: CashFlowAlert) -> Alert {
        switch alert {
        case .deleteTransaction(let transaction):
            return Alert(
                title: Text("Delete Transaction?"),
                message: Text(String(localized: "This permanently removes the \(transaction.category) transaction from \(transaction.date.formatted(date: .abbreviated, time: .omitted)).")),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteTransaction(transaction, settings: settings)
                },
                secondaryButton: .cancel()
            )

        case .deleteRecurringTransaction(let schedule):
            return Alert(
                title: Text("Delete Recurring Transaction?"),
                message: Text(String(localized: "Future \(schedule.frequency.title) occurrences for \(schedule.category) will no longer be created.")),
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
                message: Text(String(localized: "\(schedule.category) will disappear from Recurring Transactions and no future occurrences will be inserted automatically.")),
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

    private func categorySlice(at location: CGPoint, in rect: CGRect, total: Double, categories: [CategoryTotal]) -> CategoryTotal? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y
        
        let distance = sqrt(dx*dx + dy*dy)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.62
        if distance < innerRadius || distance > radius {
            return nil
        }
        
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        
        let fraction = angle / (2 * .pi)
        let selectedValue = fraction * total
        
        var cumulative = 0.0
        for category in categories {
            cumulative += category.value
            if selectedValue <= cumulative {
                return category
            }
        }
        return nil
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
