import Charts
import SwiftUI

private enum MacTransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var title: String {
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
    case transaction
    case recurring(RecurringTransaction?)

    var id: String {
        switch self {
        case .transaction:
            "transaction"
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

private enum MacCashFlowTab: Hashable {
    case overview
    case transactions
}

struct MacCashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: Transaction.ID?
    @State private var searchText = ""
    @State private var analyticsPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: MacTransactionTypeFilter = .all
    @State private var editor: MacCashFlowEditor?
    @State private var activeAlert: MacCashFlowAlert?
    @State private var selectedTab: MacCashFlowTab = .overview

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 16)
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            // Overview tab: summary cards, analytics, recurring transactions
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    analytics
                    recurringTransactions
                }
                .padding(24)
                .frame(maxWidth: 1440, alignment: .leading)
            }
            .tabItem { Label("Overview", systemImage: "chart.bar.xaxis.ascending") }
            .tag(MacCashFlowTab.overview)

            // Transactions tab: filter bar and transaction table
            VStack(alignment: .leading, spacing: 10) {
                transactionFilters
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                transactionTable
                    .layoutPriority(1)
            }
            .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            .tag(MacCashFlowTab.transactions)
        }
        .background(ScreenBackground())
        .navigationTitle("Cash Flow")
        .searchable(text: $searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        editor = .transaction
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
            case .transaction:
                MacCashFlowTransactionEditor { type, amount, category, description, date in
                    finance.addTransaction(
                        type: type,
                        amount: amount,
                        category: category,
                        description: description,
                        date: date,
                        settings: settings
                    )
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

    private var summaryCards: some View {
        let cashFlow = finance.monthlyCashFlow(for: Date())
        let totals = finance.calculateTotals(settings: settings)
        let monthlyTransactionsCount = finance.transactions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count

        return LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 16) {
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
                    ? "****"
                    : "\(cashFlow.savingsRate.formatted(.number.precision(.fractionLength(1))))%",
                systemImage: "percent"
            )
            MetricCard(
                title: "Transactions",
                value: settings.isPrivacyMode ? "****" : "\(monthlyTransactionsCount)",
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

    private var analytics: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Expense Categories")
                        .font(.headline)
                    Spacer()
                    Picker("Analytics Period", selection: $analyticsPeriod) {
                        ForEach(AnalyticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                let categories = finance.expensesByCategory(period: analyticsPeriod)
                if categories.isEmpty {
                    EmptyState(title: "No expenses for this period", systemImage: "chart.pie")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    HStack(alignment: .center, spacing: 28) {
                        Chart(categories) { item in
                            SectorMark(
                                angle: .value("Expense", item.value),
                                innerRadius: .ratio(0.62),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Category", item.name))
                            .cornerRadius(5)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 250, height: 220)

                        VStack(spacing: 10) {
                            ForEach(Array(categories.prefix(8).enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(ColorPalette.chart[index % ColorPalette.chart.count])
                                        .frame(width: 8, height: 8)
                                    Text(item.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(settings.privateCurrency(item.value))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    Text("\(item.percentage.formatted(.number.precision(.fractionLength(1))))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 52, alignment: .trailing)
                                }
                            }
                        }
                        .frame(maxWidth: 560)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var recurringTransactions: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recurring Transactions")
                            .font(.headline)
                        Text("Due schedules are recorded while the app is active and caught up the next time it opens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editor = .recurring(nil)
                    } label: {
                        Label("Add Schedule", systemImage: "plus")
                    }
                }

                if finance.recurringTransactions.isEmpty {
                    EmptyState(title: "No recurring transactions", systemImage: "repeat")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(finance.recurringTransactions) { schedule in
                        recurringTransactionRow(schedule)
                    }
                }
            }
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
                        schedule.notificationsEnabled ? "Notifications on" : "Notifications off",
                        systemImage: schedule.notificationsEnabled ? "bell.fill" : "bell.slash"
                    )
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(schedule.notificationsEnabled ? "Notifications enabled" : "Notifications disabled")
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

            let prefix = schedule.type == .income ? "+" : "-"
            Text("\(prefix)\(settings.privateCurrency(schedule.amount))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(schedule.type == .income ? WCColor.primary : WCColor.destructive)
                .frame(minWidth: 140, alignment: .trailing)

            HStack(spacing: 4) {
                Button {
                    toggleRecurringTransaction(schedule)
                } label: {
                    Image(systemName: schedule.isActive ? "pause.fill" : "play.fill")
                }
                .help(schedule.isActive ? "Pause schedule" : "Resume schedule")

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
        HStack(spacing: 14) {
            Picker("Type", selection: $transactionTypeFilter) {
                ForEach(MacTransactionTypeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Picker("Period", selection: $transactionPeriod) {
                ForEach(AnalyticsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .frame(width: 180)

            Spacer()

            Text("Showing \(filteredTransactions.count) of \(finance.transactions.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var transactionTable: some View {
        Table(filteredTransactions, selection: $selection) {
            TableColumn("Date") { transaction in
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
            }
            .width(min: 90, ideal: 110)

            TableColumn("Type") { transaction in
                Label(
                    transaction.type.title,
                    systemImage: transaction.type == .income ? "arrow.down.left" : "arrow.up.right"
                )
                .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Category") { transaction in
                HStack(spacing: 6) {
                    Text(transaction.category)
                    if transaction.recurringTransactionID != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(WCColor.primary)
                            .help("Generated from a recurring schedule")
                    }
                }
            }
            .width(min: 110, ideal: 160)

            TableColumn("Description", value: \.description)

            TableColumn("Amount") { transaction in
                let prefix = transaction.type == .income ? "+" : "-"
                Text("\(prefix)\(settings.privateCurrency(transaction.amount))")
                    .monospacedDigit()
                    .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: Transaction.ID.self) { selectedIDs in
            if let id = selectedIDs.first,
               let transaction = filteredTransactions.first(where: { $0.id == id }) {
                Button(role: .destructive) {
                    activeAlert = .deleteTransaction(transaction)
                } label: {
                    Label("Delete Transaction", systemImage: "trash")
                }
            }
        }
        .onDeleteCommand {
            guard let selectedTransaction else { return }
            activeAlert = .deleteTransaction(selectedTransaction)
        }
        .overlay {
            if filteredTransactions.isEmpty {
                ContentUnavailableView(
                    transactionEmptyTitle,
                    systemImage: transactionEmptySystemImage,
                    description: Text(transactionEmptyDescription)
                )
            }
        }
    }

    private var filteredTransactions: [Transaction] {
        finance.transactions.filter { transaction in
            let matchesType = transactionTypeFilter.transactionType.map { $0 == transaction.type } ?? true
            let matchesPeriod = transactionStartDate.map {
                transaction.date >= $0 && transaction.date <= Date()
            } ?? true
            let matchesSearch = searchText.isEmpty
                || transaction.category.localizedCaseInsensitiveContains(searchText)
                || transaction.description.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesPeriod && matchesSearch
        }
    }

    private var selectedTransaction: Transaction? {
        guard let selection else { return nil }
        return filteredTransactions.first { $0.id == selection }
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

    private var transactionEmptyTitle: String {
        if finance.transactions.isEmpty {
            return "No Transactions"
        }
        return "No Matching Transactions"
    }

    private var transactionEmptySystemImage: String {
        finance.transactions.isEmpty ? "arrow.left.arrow.right" : "line.3.horizontal.decrease.circle"
    }

    private var transactionEmptyDescription: String {
        if finance.transactions.isEmpty {
            return "Add your first income or expense."
        }
        return "Change the search, type, or period filters."
    }

    private func saveRecurringTransaction(_ schedule: RecurringTransaction) {
        finance.upsertRecurringTransaction(schedule)

        Task { @MainActor in
            if schedule.notificationsEnabled {
                let authorized = await MacRecurringTransactionNotificationService.shared.requestAuthorization()
                if !authorized {
                    finance.setRecurringNotificationsEnabled(id: schedule.id, isEnabled: false)
                    activeAlert = .message(
                        title: "Notifications Disabled",
                        message: "The schedule was saved, but notifications are not authorized. You can enable them in System Settings and then edit this schedule."
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
        await MacRecurringTransactionNotificationService.shared.sync(
            schedules: finance.data.recurringTransactions,
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
                    "This permanently removes the \(transaction.category) transaction from "
                        + "\(transaction.date.formatted(date: .abbreviated, time: .omitted))."
                ),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteTransaction(transaction, settings: settings)
                    selection = nil
                },
                secondaryButton: .cancel()
            )

        case .deleteRecurringTransaction(let schedule):
            return Alert(
                title: Text("Delete Recurring Transaction?"),
                message: Text(
                    "Future \(schedule.frequency.title.lowercased()) occurrences for "
                        + "\(schedule.category) will no longer be created."
                ),
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
                    "\(schedule.category) will disappear from Recurring Transactions and "
                        + "no future occurrences will be inserted automatically."
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

    let onSave: (TransactionType, Double, String, String, Date) -> Void

    private static let customCategoryTag = "__wealth_compass_mac_custom_category__"

    @State private var type: TransactionType = .expense
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

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

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var isSaveDisabled: Bool {
        parsedAmount <= 0 || currentCategoryName.isEmpty
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
                        category = settings.transactionCategories(for: newType).first ?? ""
                        customCategory = ""
                        isCustomCategoryFocused = false
                    }

                    TextField("Amount (\(settings.currency.rawValue))", text: $amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
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

                        Text("The category will be saved for future \(type.title.lowercased()) transactions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Transaction")
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
        guard parsedAmount > 0 else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        onSave(type, parsedAmount, selectedCategory, note, date)
        dismiss()
    }
}
