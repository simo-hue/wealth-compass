import SwiftUI

struct MacInvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: Investment.ID?
    @State private var investmentPendingDeletion: Investment?

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable summary area (cards + chart)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    AllocationChart(
                        title: "Allocation by Sector",
                        slices: finance.investmentAllocation(settings: settings),
                        settings: settings
                    )
                }
                .padding(24)
                .frame(maxWidth: 1440, alignment: .leading)
            }
            .frame(maxHeight: 420)

            Divider()

            // Native Table — outside ScrollView for proper NSTableView behavior
            investmentTable
                .layoutPriority(1)
        }
        .background(ScreenBackground())
        .navigationTitle("Investments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.editor = .investment(nil)
                } label: {
                    Label("New Investment", systemImage: "plus")
                }
            }
        }
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

    private var summaryCards: some View {
        let total = finance.calculateTotals(settings: settings).totalInvestments
        let costBasis = finance.data.investments.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 16) {
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
            
            if !settings.isPrivacyMode {
                MetricCard(
                    title: "Performance",
                    value: "\(percent.formatted(.number.precision(.fractionLength(1))))%",
                    systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: percent >= 0 ? WCColor.primary : WCColor.destructive
                )
            }
            
            let latestUpdate = finance.data.investments.map(\.updatedAt).max()
            let sectorCount = Set(finance.data.investments.map(\.sector).filter(isNonEmpty)).count
            MetricCard(
                title: "Status • \(privateCount(sectorCount)) Sectors",
                value: latestUpdate.map(formattedUpdate) ?? "Never",
                systemImage: "checkmark.circle"
            )
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
        .contextMenu(forSelectionType: Investment.ID.self) { selectedIDs in
            if let id = selectedIDs.first,
               let investment = finance.data.investments.first(where: { $0.id == id }) {
                Button {
                    appModel.editor = .investment(investment)
                } label: {
                    Label("Edit Investment", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    investmentPendingDeletion = investment
                } label: {
                    Label("Delete Investment", systemImage: "trash")
                }
            }
        } primaryAction: { selectedIDs in
            // Double-click to edit
            if let id = selectedIDs.first,
               let investment = finance.data.investments.first(where: { $0.id == id }) {
                appModel.editor = .investment(investment)
            }
        }
        .onDeleteCommand {
            guard let investment = selectedInvestment else { return }
            investmentPendingDeletion = investment
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
