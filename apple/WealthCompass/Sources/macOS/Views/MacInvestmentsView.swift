import SwiftUI

private enum MacInvestmentsTab: MacSelectorTab {
    case overview
    case positions

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .positions: return "Positions"
        }
    }
}

struct MacInvestmentsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var selection: Investment.ID?
    @State private var investmentPendingDeletion: Investment?
    @State private var selectedTab: MacInvestmentsTab = .overview

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        summaryCards
                        
                        HStack(spacing: 24) {
                            AllocationChart(
                                title: "Allocation by Sector",
                                slices: finance.investmentAllocation(settings: settings),
                                settings: settings
                            )
                            AllocationChart(
                                title: "Allocation by Type",
                                slices: finance.investmentTypeAllocation(settings: settings),
                                settings: settings
                            )
                            AllocationChart(
                                title: "Allocation by Geography",
                                slices: finance.investmentGeographyAllocation(settings: settings),
                                settings: settings
                            )
                        }
                        
                        topHoldingsSection
                    }
                    .padding(24)
                    .frame(maxWidth: 1440, alignment: .leading)
                }
            } else {
                investmentTable
                    .layoutPriority(1)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Investments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.editor = .investment(nil)
                } label: {
                    Label("New Investment", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            "Delete Investment?",
            isPresented: isShowingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: investmentPendingDeletion
        ) { investment in
            Button("Delete \(investment.symbol)", role: .destructive) {
                finance.deleteInvestment(investment, settings: settings)
                selection = nil
                investmentPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                investmentPendingDeletion = nil
            }
        } message: { investment in
            Text("This permanently removes \(investment.symbol) from your investment portfolio.")
        }
    }

    private var summaryCards: some View {
        let total = finance.calculateTotals(settings: settings).totalInvestments
        let costBasis = finance.data.investments.reduce(0) {
            $0 + settings.convert($1.costBasis, from: $1.currency)
        }
        let gain = total - costBasis
        let percent = costBasis > 0 ? (gain / costBasis) * 100 : 0

        return LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 16) {
            MetricCard(
                title: "Portfolio Value",
                value: settings.privateCurrency(total),
                systemImage: "chart.line.uptrend.xyaxis",
                accent: .blue
            )
            MetricCard(
                title: "Positions",
                value: privateCount(finance.data.investments.count),
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
            
            if !settings.isPrivacyMode {
                MetricCard(
                    title: "Performance",
                    value: "\(percent.formatted(.number.precision(.fractionLength(1))))%",
                    systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right",
                    accent: percent >= 0 ? WCColor.primary : WCColor.destructive
                )
            }
            
            let latestUpdate = finance.data.investments.map(\.updatedAt).max()
            let sectorCount = Set(finance.data.investments.map(\.sector).filter(isNonEmpty)).count
            MetricCard(
                title: "Status • \(privateCount(sectorCount)) Sectors",
                value: latestUpdate.map(formattedUpdate) ?? "Never",
                systemImage: "checkmark.circle"
            )
        }
    }

    private var topHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Holdings")
                .font(.title2.weight(.semibold))
            
            let topHoldings = finance.data.investments
                .sorted { $0.currentValue > $1.currentValue }
                .prefix(5)
            
            if topHoldings.isEmpty {
                ContentUnavailableView(
                    "No Investments",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Add stocks, ETFs, bonds, or other positions.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(topHoldings) { investment in
                        investmentCard(for: investment)
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    private var investmentTable: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], alignment: .leading, spacing: 16) {
                if finance.data.investments.isEmpty {
                    ContentUnavailableView(
                        "No Investments",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add stocks, ETFs, bonds, or other positions.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(finance.data.investments) { investment in
                        investmentCard(for: investment)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1440, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func investmentCard(for investment: Investment) -> some View {
        FinanceCard {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(investment.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(investment.symbol)
                                .font(.subheadline.weight(.semibold))
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(investment.type.title)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(settings.privateCurrency(investment.currentValue, sourceCurrency: investment.currency))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                        ValueDelta(
                            value: investment.gainLoss,
                            formattedValue: settings.privateCurrency(investment.gainLoss, sourceCurrency: investment.currency),
                            percent: investment.gainLossPercent
                        )
                    }
                }
                
                Divider().background(WCColor.border)
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.privateNumber(investment.quantity, fractionDigits: 6))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Price")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(settings.privateCurrency(investment.currentPrice, sourceCurrency: investment.currency))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formattedUpdate(investment.updatedAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appModel.editor = .investment(investment)
        }
        .contextMenu {
            Button {
                appModel.editor = .investment(investment)
            } label: {
                Label("Edit Investment", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                investmentPendingDeletion = investment
            } label: {
                Label("Delete Investment", systemImage: "trash")
            }
        }
    }

    private var selectedInvestment: Investment? {
        guard let selection else { return nil }
        return finance.data.investments.first { $0.id == selection }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { investmentPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    investmentPendingDeletion = nil
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
