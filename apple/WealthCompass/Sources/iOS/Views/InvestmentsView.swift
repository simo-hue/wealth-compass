import SwiftUI

struct InvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingForm = false
    @State private var editingInvestment: Investment?
    @State private var investmentPendingDeletion: Investment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: LocalizedStringKey("Investments"), subtitle: LocalizedStringKey("Follow positions, allocation, and performance.")) {
                    PrimaryActionButton(systemImage: "plus", accessibilityLabel: "Add Investment") {
                        editingInvestment = nil
                        showingForm = true
                    }
                }

                summary
                AllocationChart(title: LocalizedStringKey("Allocation by Sector"), slices: finance.investmentAllocation(settings: settings), settings: settings)
                investmentList
            }
            .padding(16)
        }
        .pageChrome()
        .sheet(isPresented: $showingForm, onDismiss: { editingInvestment = nil }) {
            InvestmentFormView(investment: editingInvestment) { investment in
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

    private var summary: some View {
        let total = finance.calculateTotals(settings: settings).totalInvestments
        let costBasis = finance.data.investments.reduce(Decimal(0)) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain.doubleValue / costBasis.doubleValue) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: LocalizedStringKey("Portfolio Value"), value: settings.privateCurrency(total), systemImage: "chart.line.uptrend.xyaxis", accent: .cyan, detail: LocalizedStringKey("Current market value"))
            MetricCard(title: LocalizedStringKey("Positions"), value: settings.isPrivacyMode ? settings.redactionToken : "\(finance.data.investments.count)", systemImage: "square.stack.3d.up.fill", detail: LocalizedStringKey("Stocks, ETFs, and more"))
            MetricCard(title: LocalizedStringKey("Cost Basis"), value: settings.privateCurrency(costBasis), systemImage: "banknote.fill", detail: LocalizedStringKey("Capital invested"))
            MetricCard(
                title: LocalizedStringKey("Profit / Loss"),
                value: settings.privateCurrency(gain),
                systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right",
                accent: gain >= 0 ? WCColor.primary : WCColor.destructive,
                detail: settings.isPrivacyMode ? LocalizedStringKey("Performance hidden") : LocalizedStringKey("\(percent.formatted(.number.precision(.fractionLength(1))))% performance")
            )
        }
    }

    private var investmentList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(LocalizedStringKey("Positions"), subtitle: LocalizedStringKey("Tap a position to edit its details"))

                if finance.data.investments.isEmpty {
                    EmptyState(title: LocalizedStringKey("No investments yet"), systemImage: "chart.xyaxis.line")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.investments.sorted { $0.currentValue > $1.currentValue }) { investment in
                            investmentRow(investment)
                                .contextMenu {
                                    Button {
                                        editingInvestment = investment
                                        showingForm = true
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
                    Text("\(settings.privateNumber(investment.quantity, fractionDigits: 4)) • \(investment.sector)")
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
                        percent: investment.gainLossPercent
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(settings.localized("Updated \(investment.updatedAt.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.caption2)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingInvestment = investment
            showingForm = true
        }
        // WC-L24: surface tap-to-edit as an activatable button for VoiceOver / Switch Control.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            editingInvestment = investment
            showingForm = true
        }
    }
}
