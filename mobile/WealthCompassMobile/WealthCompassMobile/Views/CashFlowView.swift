import SwiftUI
import Charts

private enum TransactionListTypeFilter: String, CaseIterable, Identifiable {
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

struct CashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTransaction = false
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var transactionPeriod: AnalyticsPeriod = .thirtyDays
    @State private var transactionTypeFilter: TransactionListTypeFilter = .all
    @State private var transactionPendingDeletion: Transaction?

    private let transactionDisplayLimit = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Cash Flow", subtitle: "Track your income and expenses") {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                }

                summaryCards
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
        .alert(item: $transactionPendingDeletion) { transaction in
            Alert(
                title: Text("Delete Transaction?"),
                message: Text("This permanently removes the \(transaction.category) transaction from \(transaction.date.formatted(date: .abbreviated, time: .omitted))."),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteTransaction(transaction, settings: settings)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var summaryCards: some View {
        let cashFlow = finance.monthlyCashFlow(for: Date())
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Monthly Income", value: settings.privateCurrency(cashFlow.monthlyIncome), systemImage: "arrow.up.right", accent: WCColor.primary)
            MetricCard(title: "Monthly Expenses", value: settings.privateCurrency(cashFlow.monthlyExpenses), systemImage: "arrow.down.right", accent: WCColor.destructive)
            MetricCard(title: "Net Savings", value: settings.privateCurrency(cashFlow.netSavings), systemImage: "wallet.pass", accent: cashFlow.netSavings >= 0 ? WCColor.primary : WCColor.destructive)
            MetricCard(title: "Savings Rate", value: settings.isPrivacyMode ? "****" : "\(cashFlow.savingsRate.formatted(.number.precision(.fractionLength(1))))%", systemImage: "percent")
        }
    }

    private var analytics: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Analytics")
                        .font(.headline)
                        .foregroundStyle(.white)
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
                if categories.isEmpty {
                    EmptyState(title: "No expenses for this period", systemImage: "chart.pie")
                } else {
                    Chart(categories) { item in
                        SectorMark(
                            angle: .value("Expense", item.value),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Category", item.name))
                        .cornerRadius(5)
                    }
                    .frame(height: 190)

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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        transactionPendingDeletion = transaction
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: transaction.type == .income ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                .foregroundStyle(transaction.type == .income ? WCColor.primary : WCColor.destructive)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(transaction.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
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
        .padding(12)
        .background(WCColor.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
