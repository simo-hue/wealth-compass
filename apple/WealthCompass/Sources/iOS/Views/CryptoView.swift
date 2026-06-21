import SwiftUI

struct CryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingForm = false
    @State private var editingHolding: CryptoHolding?
    @State private var holdingPendingDeletion: CryptoHolding?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: LocalizedStringKey( "Crypto assets"), subtitle: LocalizedStringKey( "Track holdings, allocation, and performance.")) {
                    PrimaryActionButton(systemImage: "plus", accessibilityLabel: "Add Crypto Holding") {
                        editingHolding = nil
                        showingForm = true
                    }
                }

                summary
                AllocationChart(title: LocalizedStringKey( "Crypto Allocation"), slices: finance.cryptoAllocation(settings: settings), settings: settings)
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
        .alert(item: $holdingPendingDeletion) { holding in
            Alert(
                title: Text("Delete Crypto Holding?"),
                message: Text("This permanently removes \(holding.symbol) from your crypto portfolio."),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteCrypto(holding, settings: settings)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalCrypto
        let costBasis = finance.data.crypto.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: LocalizedStringKey( "Crypto Value"), value: settings.privateCurrency(total), systemImage: "bitcoinsign.circle.fill", accent: WCColor.warning, detail: LocalizedStringKey( "Current market value"))
            MetricCard(title: LocalizedStringKey( "Holdings"), value: settings.isPrivacyMode ? "****" : "\(finance.data.crypto.count)", systemImage: "square.stack.3d.up.fill", detail: LocalizedStringKey( "Tracked assets"))
            MetricCard(title: LocalizedStringKey( "Cost Basis"), value: settings.privateCurrency(costBasis), systemImage: "banknote.fill", detail: LocalizedStringKey( "Capital invested"))
            MetricCard(
                title: LocalizedStringKey( "Profit / Loss"),
                value: settings.privateCurrency(gain),
                systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right",
                accent: gain >= 0 ? WCColor.primary : WCColor.destructive,
                detail: settings.isPrivacyMode ? LocalizedStringKey("Performance hidden") : LocalizedStringKey("\(percent.formatted(.number.precision(.fractionLength(1))))% performance")
            )
        }
    }

    private var holdingsList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(LocalizedStringKey( "Crypto holdings"), subtitle: LocalizedStringKey( "Tap a holding to edit its details"))

                if finance.data.crypto.isEmpty {
                    EmptyState(title: LocalizedStringKey( "No crypto holdings yet"), systemImage: "bitcoinsign.circle")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.crypto.sorted { $0.currentValue > $1.currentValue }) { holding in
                            holdingRow(holding)
                                .contextMenu {
                                    Button {
                                        editingHolding = holding
                                        showingForm = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        holdingPendingDeletion = holding
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
        InsetFinanceRow {
            HStack(alignment: .top, spacing: 12) {
                CryptoIconView(symbol: holding.symbol)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(holding.symbol)
                            .font(.headline.monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(holding.name)
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text("\(settings.privateNumber(holding.quantity, fractionDigits: 6)) units")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(settings.privateCurrency(holding.currentPrice, sourceCurrency: holding.currency)) / unit")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(settings.privateCurrency(holding.currentValue, sourceCurrency: holding.currency))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ValueDelta(
                        value: holding.gainLoss,
                        formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: holding.currency),
                        percent: holding.gainLossPercent
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(settings.localized("Updated \(holding.updatedAt.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.caption2)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingHolding = holding
            showingForm = true
        }
    }
}
