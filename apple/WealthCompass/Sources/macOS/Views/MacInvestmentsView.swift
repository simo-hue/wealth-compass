import SwiftUI

struct MacInvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: Investment.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

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
        .background(ScreenBackground())
        .navigationTitle("Investments")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Investments")
                    .font(.largeTitle.bold())
                Text("\(finance.data.investments.count) tracked positions")
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
                finance.deleteInvestment(investment, settings: settings)
                selection = nil
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

    private var selectedInvestment: Investment? {
        guard let selection else { return nil }
        return finance.data.investments.first { $0.id == selection }
    }
}
