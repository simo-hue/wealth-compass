import SwiftUI

private enum InvestmentsTab: String, CaseIterable, Identifiable {
    case overview
    case positions

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .positions: "Positions"
        }
    }
}

// Drives the add/edit sheet by item identity (mirrors macOS `MacEditor`). Presenting via
// `.sheet(item:)` instead of `.sheet(isPresented:)` + a separate `editingInvestment` state avoids
// the first-tap race where the form seeded its @State from a still-nil selection (empty banner).
private enum InvestmentFormRoute: Identifiable {
    case add
    case edit(Investment)

    var id: String {
        switch self {
        case .add: "new"
        case .edit(let investment): investment.id.uuidString
        }
    }

    var investment: Investment? {
        switch self {
        case .add: nil
        case .edit(let investment): investment
        }
    }
}

struct InvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var activeForm: InvestmentFormRoute?
    @State private var investmentPendingDeletion: Investment?
    @State private var selectedTab: InvestmentsTab = .overview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: LocalizedStringKey("Investments"), subtitle: LocalizedStringKey("Follow positions, allocation, and performance.")) {
                    PrimaryActionButton(systemImage: "plus", accessibilityLabel: "Add Investment") {
                        activeForm = .add
                    }
                }

                investmentsTabPicker

                if selectedTab == .overview {
                    summary
                    AllocationChart(title: LocalizedStringKey("Allocation by Sector"), slices: finance.investmentAllocation(settings: settings), settings: settings)
                    // VIEW-02: match macOS, which also breaks the portfolio down by type and geography
                    // (both store methods already exist and feed the macOS charts). Single-column on iPhone.
                    AllocationChart(title: LocalizedStringKey("Allocation by Type"), slices: finance.investmentTypeAllocation(settings: settings), settings: settings)
                    AllocationChart(title: LocalizedStringKey("Allocation by Geography"), slices: finance.investmentGeographyAllocation(settings: settings), settings: settings)
                } else {
                    investmentList
                }
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(item: $activeForm) { route in
            InvestmentFormView(investment: route.investment) { investment in
                finance.upsertInvestment(investment, settings: settings)
            }
        }
        .alert(item: $investmentPendingDeletion) { investment in
            Alert(
                title: Text("Delete Investment?"),
                message: Text("This permanently removes \(investment.symbol) from your investment portfolio."),
                primaryButton: .destructive(Text("Delete")) {
                    finance.deleteInvestment(investment, settings: settings)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var investmentsTabPicker: some View {
        Picker("Investments view", selection: $selectedTab) {
            ForEach(InvestmentsTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalInvestments
        let costBasis = finance.data.investments.reduce(Decimal(0)) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain.doubleValue / costBasis.doubleValue) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: LocalizedStringKey("Portfolio Value"), value: settings.privateCurrency(total), systemImage: "chart.line.uptrend.xyaxis", accent: .cyan, detail: LocalizedStringKey("Current market value"))
            MetricCard(title: LocalizedStringKey("Positions"), value: settings.privateCount(finance.data.investments.count), systemImage: "square.stack.3d.up.fill", detail: LocalizedStringKey("Stocks, ETFs, and more"))
            MetricCard(title: LocalizedStringKey("Cost Basis"), value: settings.privateCurrency(costBasis), systemImage: "banknote.fill", detail: LocalizedStringKey("Capital invested"))
            MetricCard(
                title: LocalizedStringKey("Profit / Loss"),
                value: settings.privateCurrency(gain),
                systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right",
                accent: gain >= 0 ? WCColor.primary : WCColor.destructive,
                detail: settings.isPrivacyMode ? LocalizedStringKey("Performance hidden") : LocalizedStringKey("\(formattedPercent(percent, locale: settings.effectiveLocale)) performance")
            )

            // VIEW-07: Performance % + Status (last-update recency + distinct-sector count) cards, matching macOS.
            if !settings.isPrivacyMode {
                MetricCard(
                    title: LocalizedStringKey("Performance"),
                    value: formattedPercent(percent, locale: settings.effectiveLocale),
                    systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: percent >= 0 ? WCColor.primary : WCColor.destructive
                )
            }
            let latestUpdate = finance.data.investments.map(\.updatedAt).max()
            let sectorCount = Set(finance.data.investments.map(\.sector).filter { !$0.isEmpty }).count
            let sectorCountLabel = settings.privateCount(sectorCount)
            // The card's own title already redacts its count, and then its value said "Never"
            // whenever the portfolio was empty — the same fact, in the same card, in the clear.
            // Tokenised rather than hidden: this card is drawn in both states and only its value
            // moves, so `••••` in a slot that always exists discloses nothing. The populated arm
            // goes too, because a "last updated" timestamp is itself data about the account.
            MetricCard(
                verbatimTitle: settings.localized("Status • \(sectorCountLabel) Sectors"),
                value: settings.isPrivacyMode
                    ? settings.redactionToken
                    : (latestUpdate.map { settings.date($0) } ?? settings.localized("Never")),
                systemImage: "checkmark.circle"
            )
        }
    }

    private var investmentList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(LocalizedStringKey("Positions"), subtitle: LocalizedStringKey("Tap a position to edit its details"))

                // Privacy before emptiness. The Positions card above already redacts its count to
                // `••••` (line 107); this sentence gave the same fact back in words. The populated
                // arm still lists its rows — ranked lists are a separate ruling (TO_SIMO_DO.md) —
                // so what stops here is the card stating the portfolio is empty.
                if settings.isPrivacyMode, finance.data.investments.isEmpty {
                    EmptyState(title: LocalizedStringKey("Hidden by Privacy Mode"), systemImage: "eye.slash")
                } else if finance.data.investments.isEmpty {
                    EmptyState(title: LocalizedStringKey("No investments yet"), systemImage: "chart.xyaxis.line")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.investments.rankedByValue(settings.convert)) { investment in
                            investmentRow(investment)
                                .contextMenu {
                                    Button {
                                        activeForm = .edit(investment)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        investmentPendingDeletion = investment
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

    private func investmentRow(_ investment: Investment) -> some View {
        InsetFinanceRow {
            HStack(alignment: .top, spacing: 12) {
                Text(String(investment.symbol.prefix(2)))
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 38, height: 38)
                    .background(Color.cyan.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(investment.symbol)
                            .font(.headline.monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(investment.type.title)
                            .textCase(.uppercase)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WCColor.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(WCColor.primary.opacity(0.11), in: Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text(investment.name)
                        .font(.subheadline)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(settings.privateNumber(investment.quantity, fractionDigits: QuantityPrecision.investment)) • \(investment.sector)")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(settings.privateCurrency(investment.currentValue, sourceCurrency: investment.currency))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ValueDelta(
                        value: investment.gainLoss.doubleValue,
                        formattedValue: settings.privateCurrency(investment.gainLoss, sourceCurrency: investment.currency),
                        percentText: settings.privatePercent(investment.gainLossPercent)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(settings.localized("Updated \(settings.date(investment.updatedAt))"))
                        .font(.caption2)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeForm = .edit(investment)
        }
        // WC-L24: surface tap-to-edit as an activatable button for VoiceOver / Switch Control.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            activeForm = .edit(investment)
        }
    }
}
