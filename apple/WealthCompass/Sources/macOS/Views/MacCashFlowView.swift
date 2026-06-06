import SwiftUI

struct MacCashFlowView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: Transaction.ID?
    @State private var searchText = ""

    private var filteredTransactions: [Transaction] {
        guard !searchText.isEmpty else { return finance.transactions }
        return finance.transactions.filter {
            $0.category.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

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

                TableColumn("Category", value: \.category)
                    .width(min: 100, ideal: 150)

                TableColumn("Description", value: \.description)

                TableColumn("Amount") { transaction in
                    Text(settings.privateCurrency(transaction.amount))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 110, ideal: 140)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search transactions")
            .overlay {
                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Transactions" : "No Results",
                        systemImage: searchText.isEmpty ? "arrow.left.arrow.right" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Add your first income or expense." : "Try another search.")
                    )
                }
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Cash Flow")
    }

    private var header: some View {
        let cashFlow = finance.monthlyCashFlow(for: Date())
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cash Flow")
                        .font(.largeTitle.bold())
                    Text("Income and expenses for \(Date().formatted(.dateTime.month(.wide).year()))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appModel.editor = .transaction
                } label: {
                    Label("New Transaction", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(WCColor.primary)

                Button(role: .destructive) {
                    deleteSelection()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection == nil)
            }

            HStack(spacing: 24) {
                summary("Income", value: cashFlow.monthlyIncome, color: WCColor.primary)
                summary("Expenses", value: cashFlow.monthlyExpenses, color: WCColor.destructive)
                summary("Net Savings", value: cashFlow.netSavings, color: cashFlow.netSavings >= 0 ? WCColor.primary : WCColor.destructive)
                summary(
                    "Savings Rate",
                    text: settings.isPrivacyMode ? "****" : "\(cashFlow.savingsRate.formatted(.number.precision(.fractionLength(1))))%",
                    color: .secondary
                )
            }
        }
        .padding(24)
    }

    private func summary(_ title: String, value: Double, color: Color) -> some View {
        summary(title, text: settings.privateCurrency(value), color: color)
    }

    private func summary(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func deleteSelection() {
        guard
            let selection,
            let transaction = finance.data.transactions.first(where: { $0.id == selection })
        else {
            return
        }
        finance.deleteTransaction(transaction, settings: settings)
        self.selection = nil
    }
}
