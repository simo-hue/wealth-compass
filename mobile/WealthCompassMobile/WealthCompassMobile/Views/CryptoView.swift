import SwiftUI

struct CryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingForm = false
    @State private var editingHolding: CryptoHolding?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Crypto Assets", subtitle: "Manage your cryptocurrency holdings") {
                    Button {
                        editingHolding = nil
                        showingForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                }

                summary
                AllocationChart(title: "Crypto Allocation", slices: finance.cryptoAllocation(settings: settings), settings: settings)
                holdingsList
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(isPresented: $showingForm, onDismiss: { editingHolding = nil }) {
            CryptoFormView(holding: editingHolding) { holding in
                finance.upsertCrypto(holding, settings: settings)
            }
        }
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalCrypto
        let costBasis = finance.data.crypto.reduce(0) {
            $0 + settings.convert($1.costBasis, from: .usd)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Crypto Value", value: settings.privateCurrency(total), systemImage: "bitcoinsign.circle", accent: WCColor.warning)
            MetricCard(title: "Holdings", value: settings.isPrivacyMode ? "****" : "\(finance.data.crypto.count)", systemImage: "number")
            MetricCard(title: "Cost Basis", value: settings.privateCurrency(costBasis), systemImage: "banknote")
            MetricCard(title: "Profit / Loss", value: settings.privateCurrency(gain), systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right", accent: gain >= 0 ? WCColor.primary : WCColor.destructive)

            if !settings.isPrivacyMode {
                Text("Performance \(percent.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gain >= 0 ? WCColor.primary : WCColor.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var holdingsList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Crypto Holdings")
                    .font(.headline)
                    .foregroundStyle(.white)

                if finance.data.crypto.isEmpty {
                    EmptyState(title: "No crypto holdings yet", systemImage: "bitcoinsign.circle")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.crypto.sorted { $0.currentValue > $1.currentValue }) { holding in
                            holdingRow(holding)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingHolding = holding
                                        showingForm = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        finance.deleteCrypto(holding, settings: settings)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func holdingRow(_ holding: CryptoHolding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(holding.symbol)
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                    Text(holding.name)
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                }
                Text("\(settings.privateNumber(holding.quantity, fractionDigits: 8)) units")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
                Text("\(settings.privateCurrency(holding.currentPrice, sourceCurrency: .usd)) / unit")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(settings.privateCurrency(holding.currentValue, sourceCurrency: .usd))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                ValueDelta(
                    value: holding.gainLoss,
                    formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: .usd),
                    percent: holding.gainLossPercent
                )
                Text("Updated \(holding.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(WCColor.textSecondary)
            }
        }
        .padding(12)
        .background(WCColor.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editingHolding = holding
            showingForm = true
        }
    }
}
