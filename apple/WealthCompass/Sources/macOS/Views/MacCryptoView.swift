import SwiftUI

struct MacCryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: CryptoHolding.ID?
    @State private var holdingPendingDeletion: CryptoHolding?

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
                        title: "Crypto Allocation",
                        slices: finance.cryptoAllocation(settings: settings),
                        settings: settings
                    )
                }
                .padding(24)
                .frame(maxWidth: 1440, alignment: .leading)
            }
            .frame(maxHeight: 420)

            Divider()

            // Native Table — outside ScrollView for proper NSTableView behavior
            cryptoTable
                .layoutPriority(1)
        }
        .background(ScreenBackground())
        .navigationTitle("Crypto")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.editor = .crypto(nil)
                } label: {
                    Label("New Holding", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            "Delete Crypto Holding?",
            isPresented: isShowingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: holdingPendingDeletion
        ) { holding in
            Button("Delete \(holding.symbol)", role: .destructive) {
                finance.deleteCrypto(holding, settings: settings)
                selection = nil
                holdingPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                holdingPendingDeletion = nil
            }
        } message: { holding in
            Text("This permanently removes \(holding.symbol) from your crypto portfolio.")
        }
    }

    private var summaryCards: some View {
        let total = finance.calculateTotals(settings: settings).totalCrypto
        let costBasis = finance.data.crypto.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 16) {
            MetricCard(
                title: "Crypto Value",
                value: settings.privateCurrency(total),
                systemImage: "bitcoinsign.circle",
                accent: WCColor.warning
            )
            MetricCard(
                title: "Holdings",
                value: privateCount(finance.data.crypto.count),
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
            
            let latestUpdate = finance.data.crypto.map(\.updatedAt).max()
            let uniqueCryptoCount = Set(finance.data.crypto.map(\.symbol).filter(isNonEmpty)).count
            MetricCard(
                title: "Status • \(privateCount(uniqueCryptoCount)) Coins",
                value: latestUpdate.map(formattedUpdate) ?? "Never",
                systemImage: "checkmark.circle"
            )
        }
    }

    private var cryptoTable: some View {
        Table(finance.data.crypto, selection: $selection) {
            TableColumn("Symbol") { holding in
                HStack(spacing: 8) {
                    CryptoIconView(symbol: holding.symbol, size: 24, cornerRadius: 6)
                    Text(holding.symbol)
                }
            }
                .width(min: 70, ideal: 90)
            TableColumn("Asset", value: \.name)
            TableColumn("Quantity") {
                Text(settings.privateNumber($0.quantity, fractionDigits: 8))
                    .monospacedDigit()
            }
            .width(min: 100, ideal: 130)
            TableColumn("Price") {
                Text(settings.privateCurrency($0.currentPrice, sourceCurrency: $0.currency))
                    .monospacedDigit()
            }
            .width(min: 100, ideal: 130)
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
        .contextMenu(forSelectionType: CryptoHolding.ID.self) { selectedIDs in
            if let id = selectedIDs.first,
               let holding = finance.data.crypto.first(where: { $0.id == id }) {
                Button {
                    appModel.editor = .crypto(holding)
                } label: {
                    Label("Edit Holding", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    holdingPendingDeletion = holding
                } label: {
                    Label("Delete Holding", systemImage: "trash")
                }
            }
        } primaryAction: { selectedIDs in
            // Double-click to edit
            if let id = selectedIDs.first,
               let holding = finance.data.crypto.first(where: { $0.id == id }) {
                appModel.editor = .crypto(holding)
            }
        }
        .onDeleteCommand {
            guard let holding = selectedHolding else { return }
            holdingPendingDeletion = holding
        }
        .overlay {
            if finance.data.crypto.isEmpty {
                ContentUnavailableView(
                    "No Crypto Holdings",
                    systemImage: "bitcoinsign.circle",
                    description: Text("Add a holding to track its value and performance.")
                )
            }
        }
    }

    private var selectedHolding: CryptoHolding? {
        guard let selection else { return nil }
        return finance.data.crypto.first { $0.id == selection }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { holdingPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    holdingPendingDeletion = nil
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
