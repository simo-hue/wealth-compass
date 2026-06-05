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
                PageHeader(title: "Investments", subtitle: "Manage your stock and ETF portfolio") {
                    Button {
                        editingInvestment = nil
                        showingForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                }

                summary
                AllocationChart(title: "Allocation by Sector", slices: finance.investmentAllocation(settings: settings), settings: settings)
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
        let costBasis = finance.data.investments.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Portfolio Value", value: settings.privateCurrency(total), systemImage: "chart.line.uptrend.xyaxis", accent: .blue)
            MetricCard(title: "Positions", value: settings.isPrivacyMode ? "****" : "\(finance.data.investments.count)", systemImage: "number")
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

    private var investmentList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Investments")
                    .font(.headline)
                    .foregroundStyle(.white)

                if finance.data.investments.isEmpty {
                    EmptyState(title: "No investments yet", systemImage: "chart.xyaxis.line")
                } else {
                    VStack(spacing: 12) {
                        ForEach(finance.data.investments.sorted { $0.currentValue > $1.currentValue }) { investment in
                            investmentRow(investment)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingInvestment = investment
                                        showingForm = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(investment.symbol)
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                    Text(investment.type.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(WCColor.primary, in: Capsule())
                }
                Text(investment.name)
                    .font(.subheadline)
                    .foregroundStyle(WCColor.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(settings.privateNumber(investment.quantity, fractionDigits: 6))
                    Text(investment.sector)
                }
                .font(.caption)
                .foregroundStyle(WCColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(settings.privateCurrency(investment.currentValue, sourceCurrency: investment.currency))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                ValueDelta(
                    value: investment.gainLoss,
                    formattedValue: settings.privateCurrency(investment.gainLoss, sourceCurrency: investment.currency),
                    percent: investment.gainLossPercent
                )
                Text("Updated \(investment.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(WCColor.textSecondary)
            }
        }
        .padding(12)
        .background(WCColor.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editingInvestment = investment
            showingForm = true
        }
    }
}
