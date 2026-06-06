import SwiftUI

struct MacCryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: CryptoHolding.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

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
        .background(ScreenBackground())
        .navigationTitle("Crypto")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Crypto")
                    .font(.largeTitle.bold())
                Text("\(finance.data.crypto.count) tracked holdings")
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
                finance.deleteCrypto(holding, settings: settings)
                selection = nil
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

    private var selectedHolding: CryptoHolding? {
        guard let selection else { return nil }
        return finance.data.crypto.first { $0.id == selection }
    }
}
