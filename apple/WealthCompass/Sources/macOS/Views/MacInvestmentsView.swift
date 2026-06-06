import SwiftUI

struct MacInvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: Investment.ID?
    @State private var investmentPendingDeletion: Investment?

    private let metricColumns = [
        GridItem(.adaptive(minimum: 135), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                overview
                    .frame(minWidth: 250, idealWidth: 340, maxWidth: 430)

                investmentTable
                    .frame(minWidth: 500)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Investments")
        .confirmationDialog(
            "Delete Investment?",
            isPresented: isShowingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: investmentPendingDeletion
        ) { investment in
            Button("Delete \(investment.symbol)", role: .destructive) {
                finance.deleteInvestment(investment, settings: settings)
                selection = nil
                investmentPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                investmentPendingDeletion = nil
            }
        } message: { investment in
            Text("This permanently removes \(investment.symbol) from your investment portfolio.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Investments")
                    .font(.largeTitle.bold())
                Text("\(privateCount(finance.data.investments.count)) tracked positions")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", systemImage: "pencil") {
                guard let investment = selectedInvestment else { return }
                appModel.editor = .investment(investment)
            }
            .disabled(selectedInvestment == nil)

            Button(role: .destructive) {
                guard let investment = selectedInvestment else { return }
                investmentPendingDeletion = investment
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedInvestment == nil)

            Button {
                appModel.editor = .investment(nil)
            } label: {
                Label("New Investment", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(WCColor.primary)
        }
        .padding(24)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                AllocationChart(
                    title: "Allocation by Sector",
                    slices: finance.investmentAllocation(settings: settings),
                    settings: settings
                )
                statusDetails
            }
            .padding(20)
        }
        .background(WCColor.background.opacity(0.35))
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalInvestments
        let costBasis = finance.data.investments.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                MetricCard(
                    title: "Portfolio Value",
                    value: settings.privateCurrency(total),
                    systemImage: "chart.line.uptrend.xyaxis",
                    accent: .blue
                )
                MetricCard(
                    title: "Positions",
                    value: privateCount(finance.data.investments.count),
                    systemImage: "number"
                )
                MetricCard(
                    title: "Cost Basis",
                    value: settings.privateCurrency(costBasis),
                    systemImage: "banknote"
                )
                MetricCard(
                    title: "Profit / Loss",
                    value: settings.privateCurrency(gain),
                    systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: gain >= 0 ? WCColor.primary : WCColor.destructive
                )
            }

            if !settings.isPrivacyMode {
                Text("Performance \(percent.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gain >= 0 ? WCColor.primary : WCColor.destructive)
            }
        }
    }

    private var statusDetails: some View {
        let investments = finance.data.investments
        let sectorCount = Set(investments.map(\.sector).filter(isNonEmpty)).count
        let identifierCount = investments.filter { isNonEmpty($0.isin) }.count
        let pricedCount = investments.filter { $0.currentPrice > 0 }.count
        let latestUpdate = investments.map(\.updatedAt).max()

        return FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Portfolio Status", systemImage: "checkmark.circle")
                    .font(.headline)

                LabeledContent("Last Updated") {
                    Text(latestUpdate.map(formattedUpdate) ?? "Never")
                }
                LabeledContent("Price Coverage") {
                    Text("\(privateCount(pricedCount)) of \(privateCount(investments.count))")
                }
                LabeledContent("ISIN / IDs") {
                    Text("\(privateCount(identifierCount)) of \(privateCount(investments.count))")
                }
                LabeledContent("Sectors") {
                    Text(privateCount(sectorCount))
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var investmentTable: some View {
        Table(finance.data.investments, selection: $selection) {
            TableColumn("Symbol", value: \.symbol)
                .width(min: 70, ideal: 90)
            TableColumn("Name", value: \.name)
            TableColumn("Type") { Text($0.type.title) }
                .width(min: 80, ideal: 100)
            TableColumn("Quantity") {
                Text(settings.privateNumber($0.quantity, fractionDigits: 6))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("Value") {
                Text(settings.privateCurrency($0.currentValue, sourceCurrency: $0.currency))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 140)
            TableColumn("Gain / Loss") {
                ValueDelta(
                    value: $0.gainLoss,
                    formattedValue: settings.privateCurrency($0.gainLoss, sourceCurrency: $0.currency),
                    percent: $0.gainLossPercent
                )
            }
            .width(min: 150, ideal: 180)
            TableColumn("Updated") {
                Text(formattedUpdate($0.updatedAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
        }
        .overlay {
            if finance.data.investments.isEmpty {
                ContentUnavailableView(
                    "No Investments",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Add stocks, ETFs, bonds, or other positions.")
                )
            }
        }
    }

    private var selectedInvestment: Investment? {
        guard let selection else { return nil }
        return finance.data.investments.first { $0.id == selection }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { investmentPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    investmentPendingDeletion = nil
                }
            }
        )
    }

    private func privateCount(_ count: Int) -> String {
        settings.isPrivacyMode ? "****" : "\(count)"
    }

    private func formattedUpdate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func isNonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
