import SwiftUI

struct MacRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @State private var isRefreshing = false

    var body: some View {
        NavigationSplitView {
            List(MacDestination.allCases, selection: $appModel.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Wealth Compass")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(minWidth: 760, minHeight: 560)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await refreshData() }
                        } label: {
                            Label("Refresh Data", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)

                        Menu {
                            Button("Transaction") { appModel.editor = .transaction }
                                .keyboardShortcut("n", modifiers: .command)
                            Button("Investment") { appModel.editor = .investment(nil) }
                            Button("Crypto Holding") { appModel.editor = .crypto(nil) }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $appModel.editor) { editor in
            MacEditorSheet(editor: editor)
                .environmentObject(finance)
                .environmentObject(settings)
        }
        .task {
            await handleAppBecameActive()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await handleAppBecameActive() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selection ?? .dashboard {
        case .dashboard:
            MacDashboardView()
        case .cashFlow:
            MacCashFlowView()
        case .investments:
            MacInvestmentsView()
        case .crypto:
            MacCryptoView()
        }
    }

    private func handleAppBecameActive() async {
        _ = finance.processDueRecurringTransactions(settings: settings)
        if settings.shouldAutoRefreshExchangeRates() {
            _ = await settings.refreshExchangeRates()
        }
    }

    private func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        _ = await settings.refreshExchangeRates()

        let finnhubKey = try? KeychainCredentialStore.shared.string(for: .finnhubAPIKey)
        let coinGeckoKey = try? KeychainCredentialStore.shared.string(for: .coingeckoAPIKey)
        _ = await finance.refreshMarketPrices(
            finnhubAPIKey: finnhubKey ?? nil,
            coingeckoAPIKey: coinGeckoKey ?? nil,
            settings: settings
        )
    }
}
