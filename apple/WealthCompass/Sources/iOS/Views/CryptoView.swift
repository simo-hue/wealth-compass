import SwiftUI

private enum CryptoTab: String, CaseIterable, Identifiable {
    case overview
    case holdings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .holdings: "Holdings"
        }
    }
}

// Drives the add/edit sheet by item identity (mirrors macOS `MacEditor`). Presenting via
// `.sheet(item:)` instead of `.sheet(isPresented:)` + a separate `editingHolding` state avoids
// the first-tap race where the form seeded its @State from a still-nil selection (empty banner).
private enum CryptoFormRoute: Identifiable {
    case add
    case edit(CryptoHolding)

    var id: String {
        switch self {
        case .add: "new"
        case .edit(let holding): holding.id.uuidString
        }
    }

    var holding: CryptoHolding? {
        switch self {
        case .add: nil
        case .edit(let holding): holding
        }
    }
}

struct CryptoView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var activeForm: CryptoFormRoute?
    @State private var holdingPendingDeletion: CryptoHolding?
    @State private var selectedTab: CryptoTab = .overview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: LocalizedStringKey("Crypto assets"), subtitle: LocalizedStringKey("Track holdings, allocation, and performance.")) {
                    PrimaryActionButton(systemImage: "plus", accessibilityLabel: "Add Crypto Holding") {
                        activeForm = .add
                    }
                }

                cryptoTabPicker

                if selectedTab == .overview {
                    summary
                    performanceSection
                    AllocationChart(title: LocalizedStringKey("Crypto Allocation"), slices: finance.cryptoAllocation(settings: settings), settings: settings)
                } else {
                    holdingsList
                }
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(item: $activeForm) { route in
            CryptoFormView(holding: route.holding) { holding in
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

    private var cryptoTabPicker: some View {
        Picker("Crypto view", selection: $selectedTab) {
            ForEach(CryptoTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalCrypto
        let costBasis = finance.data.crypto.reduce(Decimal(0)) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain.doubleValue / costBasis.doubleValue) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: LocalizedStringKey("Crypto Value"), value: settings.privateCurrency(total), systemImage: "bitcoinsign.circle.fill", accent: WCColor.warning, detail: LocalizedStringKey("Current market value"))
            MetricCard(title: LocalizedStringKey("Holdings"), value: settings.privateCount(finance.data.crypto.count), systemImage: "square.stack.3d.up.fill", detail: LocalizedStringKey("Tracked assets"))
            MetricCard(title: LocalizedStringKey("Cost Basis"), value: settings.privateCurrency(costBasis), systemImage: "banknote.fill", detail: LocalizedStringKey("Capital invested"))
            MetricCard(
                title: LocalizedStringKey("Profit / Loss"),
                value: settings.privateCurrency(gain),
                systemImage: settings.privateSymbol(isPositive: gain >= 0, positive: "arrow.up.right", negative: "arrow.down.right"),
                accent: settings.privateAccent(isPositive: gain >= 0),
                detail: settings.isPrivacyMode ? LocalizedStringKey("Performance hidden") : LocalizedStringKey("\(formattedPercent(percent, locale: settings.effectiveLocale)) performance")
            )

            // VIEW-07: Performance % + Status (last-update recency + distinct-coin count) cards, matching macOS.
            if !settings.isPrivacyMode {
                MetricCard(
                    title: LocalizedStringKey("Performance"),
                    value: formattedPercent(percent, locale: settings.effectiveLocale),
                    systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: percent >= 0 ? WCColor.primary : WCColor.destructive
                )
            }
            let latestUpdate = finance.data.crypto.map(\.updatedAt).max()
            let coinCount = Set(finance.data.crypto.map(\.symbol).filter { !$0.isEmpty }).count
            let coinCountLabel = settings.privateCount(coinCount)
            // The card's own title already redacts its count, and then its value said "Never"
            // whenever the portfolio was empty — the same fact, in the same card, in the clear.
            // Tokenised rather than hidden: this card is drawn in both states and only its value
            // moves, so `••••` in a slot that always exists discloses nothing. The populated arm
            // goes too, because a "last updated" timestamp is itself data about the account.
            MetricCard(
                verbatimTitle: settings.localized("Status • \(coinCountLabel) Coins"),
                value: settings.isPrivacyMode
                    ? settings.redactionToken
                    : (latestUpdate.map { settings.date($0) } ?? settings.localized("Never")),
                systemImage: "checkmark.circle"
            )
        }
    }

    // VIEW-06: Top Performer / Biggest Loser leaderboard, matching macOS (shown only when a positive
    // best and/or negative worst exists). Both halves of each row redact in Privacy Mode: the amount
    // through `privateCurrency`, the percentage through `privatePercent`. `ValueDelta` redacts
    // nothing itself — it renders the two strings it is handed — so the guard has to be here.
    @ViewBuilder
    private var performanceSection: some View {
        let cryptos = finance.data.crypto
        let best = cryptos.max(by: { $0.gainLossPercent < $1.gainLossPercent })
        let worst = cryptos.min(by: { $0.gainLossPercent < $1.gainLossPercent })
        let hasBest = best != nil && best!.gainLossPercent > 0
        let hasWorst = worst != nil && worst!.gainLossPercent < 0

        if hasBest || hasWorst {
            FinanceCard {
                VStack(spacing: 16) {
                    if let best, best.gainLossPercent > 0 {
                        performanceCard(title: LocalizedStringKey("Top Performer"), holding: best)
                    }
                    if hasBest && hasWorst {
                        Divider().background(WCColor.border)
                    }
                    if let worst, worst.gainLossPercent < 0 {
                        performanceCard(title: LocalizedStringKey("Biggest Loser"), holding: worst)
                    }
                }
            }
        }
    }

    private func performanceCard(title: LocalizedStringKey, holding: CryptoHolding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                CryptoIconView(symbol: holding.symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(holding.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(holding.symbol)
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(settings.privateCurrency(holding.currentValue, sourceCurrency: holding.currency))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    ValueDelta(
                        value: holding.gainLoss.doubleValue,
                        formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: holding.currency),
                        percentText: settings.privatePercent(holding.gainLossPercent),
                        isRedacted: settings.isPrivacyMode
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var holdingsList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(LocalizedStringKey("Crypto holdings"), subtitle: LocalizedStringKey("Tap a holding to edit its details"))

                // Privacy before emptiness. The Holdings card above already redacts its count to
                // `••••` (line 104); this sentence gave the same fact back in words. The populated
                // arm still lists its rows (a separate ruling), so what stops is the sentence.
                if settings.isPrivacyMode, finance.data.crypto.isEmpty {
                    EmptyState(title: LocalizedStringKey("Hidden by Privacy Mode"), systemImage: "eye.slash")
                } else if finance.data.crypto.isEmpty {
                    EmptyState(title: LocalizedStringKey("No crypto holdings yet"), systemImage: "bitcoinsign.circle")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.crypto.rankedByValue(settings.convert)) { holding in
                            holdingRow(holding)
                                .contextMenu {
                                    Button {
                                        activeForm = .edit(holding)
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
                    Text("\(settings.privateNumber(holding.quantity, fractionDigits: QuantityPrecision.crypto)) units")
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
                        value: holding.gainLoss.doubleValue,
                        formattedValue: settings.privateCurrency(holding.gainLoss, sourceCurrency: holding.currency),
                        percentText: settings.privatePercent(holding.gainLossPercent),
                        isRedacted: settings.isPrivacyMode
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(settings.localized("Updated \(settings.privateDate(holding.updatedAt))"))
                        .font(.caption2)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeForm = .edit(holding)
        }
        // WC-L24: surface tap-to-edit as an activatable button for VoiceOver / Switch Control.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            activeForm = .edit(holding)
        }
    }
}
