import SwiftUI

private enum MacCryptoTab: MacSelectorTab {
    case overview
    case holdings

    var title: LocalizedStringKey {
        switch self {
        case .overview: return "Overview"
        case .holdings: return "Holdings"
        }
    }
}

struct MacCryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var holdingPendingDeletion: CryptoHolding?
    @State private var selectedTab: MacCryptoTab = .overview

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                MacSelectorIsland(selection: $selectedTab)
                Spacer()
            }
            .padding(.vertical, 16)

            if selectedTab == .overview {
                ViewThatFits(in: .vertical) {
                    overviewContent
                    ScrollView {
                        overviewContent
                    }
                }
            } else {
                cryptoTable
                    .layoutPriority(1)
            }
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
        let costBasis = finance.data.crypto.reduce(Decimal(0)) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain.doubleValue / costBasis.doubleValue) * 100 : 0

        return LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 16) {
            MetricCard(
                title: LocalizedStringKey("Crypto Value"),
                value: settings.privateCurrency(total),
                systemImage: "bitcoinsign.circle",
                accent: WCColor.warning
            )
            MetricCard(
                title: LocalizedStringKey("Holdings"),
                value: privateCount(finance.data.crypto.count),
                systemImage: "number"
            )
            MetricCard(
                title: LocalizedStringKey("Cost Basis"),
                value: settings.privateCurrency(costBasis),
                systemImage: "banknote"
            )
            MetricCard(
                title: LocalizedStringKey("Profit / Loss"),
                value: settings.privateCurrency(gain),
                systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right",
                accent: gain >= 0 ? WCColor.primary : WCColor.destructive
            )
            
            if !settings.isPrivacyMode {
                MetricCard(
                    title: LocalizedStringKey("Performance"),
                    value: "\(percent.formatted(.number.precision(.fractionLength(1))))%",
                    systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: percent >= 0 ? WCColor.primary : WCColor.destructive
                )
            }
            
            let latestUpdate = finance.data.crypto.map(\.updatedAt).max()
            let uniqueCryptoCount = Set(finance.data.crypto.map(\.symbol).filter(isNonEmpty)).count
            MetricCard(
                // L19: already resolved by settings.localized — pass verbatim so Text doesn't re-localize.
                verbatimTitle: settings.localized("Status • \(privateCount(uniqueCryptoCount)) Coins"),
                value: latestUpdate.map(formattedUpdate) ?? settings.localized("Never"),
                systemImage: "checkmark.circle"
            )
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            summaryCards
            
            HStack(spacing: 24) {
                AllocationChart(
                    title: LocalizedStringKey("Crypto Allocation"),
                    slices: finance.cryptoAllocation(settings: settings),
                    settings: settings,
                    showLegend: false
                )
                .frame(maxWidth: .infinity)
                
                performanceSection
            }
            
            topHoldingsSection
        }
        .padding(24)
        .frame(maxWidth: 1440, alignment: .leading)
    }

    @ViewBuilder
    private var performanceSection: some View {
        let cryptos = finance.data.crypto
        let best = cryptos.max(by: { $0.gainLossPercent < $1.gainLossPercent })
        let worst = cryptos.min(by: { $0.gainLossPercent < $1.gainLossPercent })
        
        let hasBest = best != nil && best!.gainLossPercent > 0
        let hasWorst = worst != nil && worst!.gainLossPercent < 0
        
        if hasBest || hasWorst {
            FinanceCard {
                VStack(spacing: 24) {
                    if let best, best.gainLossPercent > 0 {
                        performanceCard(title: "Top Performer", holding: best)
                    }
                    
                    if hasBest && hasWorst {
                        Divider().background(WCColor.border)
                    }
                    
                    if let worst, worst.gainLossPercent < 0 {
                        performanceCard(title: "Biggest Loser", holding: worst)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 400)
        }
    }

    private func performanceCard(title: LocalizedStringKey, holding: CryptoHolding) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            HStack(spacing: 12) {
                CryptoIconView(symbol: holding.symbol, size: 40, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(holding.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(holding.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(settings.privateCurrency(holding.currentValue, sourceCurrency: holding.currency))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    ValueDelta(
                        value: holding.gainLoss.doubleValue,
                        formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: holding.currency),
                        percent: holding.gainLossPercent
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Holdings")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 2)
            
            let topHoldings = finance.data.crypto
                .sorted { $0.currentValue > $1.currentValue }
                .prefix(6)
            
            if topHoldings.isEmpty {
                ContentUnavailableView(
                    "No Crypto Holdings",
                    systemImage: "bitcoinsign.circle",
                    description: Text("Add a holding to track its value.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(topHoldings) { holding in
                        holdingCard(for: holding)
                    }
                }
            }
        }
    }

    private var cryptoTable: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], alignment: .leading, spacing: 16) {
                if finance.data.crypto.isEmpty {
                    ContentUnavailableView(
                        "No Crypto Holdings",
                        systemImage: "bitcoinsign.circle",
                        description: Text("Add a holding to track its value and performance.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(finance.data.crypto) { holding in
                        holdingCard(for: holding)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1440, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func holdingCard(for holding: CryptoHolding) -> some View {
        FinanceCard {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    CryptoIconView(symbol: holding.symbol, size: 36, cornerRadius: 8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(holding.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(holding.symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(settings.privateCurrency(holding.currentValue, sourceCurrency: holding.currency))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                        ValueDelta(
                            value: holding.gainLoss.doubleValue,
                            formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: holding.currency),
                            percent: holding.gainLossPercent
                        )
                    }
                }
                
                Divider().background(WCColor.border)
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.privateNumber(holding.quantity, fractionDigits: 8))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Price")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.privateCurrency(holding.currentPrice, sourceCurrency: holding.currency))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formattedUpdate(holding.updatedAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appModel.editor = .crypto(holding)
        }
        // WC-L24: the double-click-to-edit affordance is invisible to VoiceOver/keyboard, so expose the
        // card as one activatable button whose default action opens the editor (mirrors the Cash Flow card).
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            appModel.editor = .crypto(holding)
        }
        .contextMenu {
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
        settings.isPrivacyMode ? settings.redactionToken : "\(count)"
    }

    private func formattedUpdate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func isNonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
