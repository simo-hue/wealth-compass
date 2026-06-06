import SwiftUI

struct MacCryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: CryptoHolding.ID?
    @State private var holdingPendingDeletion: CryptoHolding?

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

                cryptoTable
                    .frame(minWidth: 500)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Crypto")
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Crypto")
                    .font(.largeTitle.bold())
                Text("\(privateCount(finance.data.crypto.count)) tracked holdings")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", systemImage: "pencil") {
                guard let holding = selectedHolding else { return }
                appModel.editor = .crypto(holding)
            }
            .disabled(selectedHolding == nil)

            Button(role: .destructive) {
                guard let holding = selectedHolding else { return }
                holdingPendingDeletion = holding
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedHolding == nil)

            Button {
                appModel.editor = .crypto(nil)
            } label: {
                Label("New Holding", systemImage: "plus")
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
                    title: "Crypto Allocation",
                    slices: finance.cryptoAllocation(settings: settings),
                    settings: settings
                )
                statusDetails
            }
            .padding(20)
        }
        .background(WCColor.background.opacity(0.35))
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalCrypto
        let costBasis = finance.data.crypto.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: metricColumns, spacing: 12) {
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
            }

            if !settings.isPrivacyMode {
                Text("Performance \(percent.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gain >= 0 ? WCColor.primary : WCColor.destructive)
            }
        }
    }

    private var statusDetails: some View {
        let holdings = finance.data.crypto
        let identifierCount = holdings.filter { isNonEmpty($0.coinId) }.count
        let pricedCount = holdings.filter { $0.currentPrice > 0 }.count
        let latestUpdate = holdings.map(\.updatedAt).max()

        return FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Holding Status", systemImage: "checkmark.circle")
                    .font(.headline)

                LabeledContent("Last Updated") {
                    Text(latestUpdate.map(formattedUpdate) ?? "Never")
                }
                LabeledContent("Price Coverage") {
                    Text("\(privateCount(pricedCount)) of \(privateCount(holdings.count))")
                }
                LabeledContent("Coin IDs") {
                    Text("\(privateCount(identifierCount)) of \(privateCount(holdings.count))")
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var cryptoTable: some View {
        Table(finance.data.crypto, selection: $selection) {
            TableColumn("Symbol", value: \.symbol)
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
