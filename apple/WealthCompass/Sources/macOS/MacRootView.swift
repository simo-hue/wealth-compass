import SwiftUI

struct MacRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appLock: MacAppLockStore
    @State private var isRefreshing = false
    @State private var alert: MacRootAlert?

    private let recurringCheckTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                MacLockView()
                    .frame(minWidth: 760, minHeight: 560)
            } else {
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
            }
        }
        .sheet(item: $appModel.editor) { editor in
            MacEditorSheet(editor: editor)
                .environmentObject(finance)
                .environmentObject(settings)
        }
        .task {
            await handleAppBecameActive()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await handleAppBecameActive() }
            } else {
                appLock.lock()
            }
        }
        .onReceive(recurringCheckTimer) { _ in
            guard scenePhase == .active, appLock.isUnlocked else { return }
            Task { await processRecurringTransactions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRecurringTransactionNotificationReceived)) { _ in
            Task { await processRecurringTransactions() }
        }
        .onChange(of: finance.data.recurringTransactions) { _, _ in
            Task { await syncRecurringNotifications() }
        }
        .onChange(of: settings.currency) { _, _ in
            Task { await syncRecurringNotifications() }
        }
        .onChange(of: settings.isPrivacyMode) { _, _ in
            Task { await syncRecurringNotifications() }
        }
        .alert(item: $alert) { value in
            Alert(
                title: Text(value.title),
                message: Text(value.message),
                dismissButton: .default(Text("OK"))
            )
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
        await processRecurringTransactions()

        if settings.shouldAutoRefreshExchangeRates() {
            let result = await settings.refreshExchangeRates()
            if result.didChangeRates, finance.hasForeignCurrencyExposure(relativeTo: settings.currency) {
                finance.takeSnapshot(settings: settings)
            }
        }

        if finance.shouldAutoRefreshMarketPrices() {
            _ = await refreshMarketPrices()
        }
    }

    private func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let exchangeResult = await settings.refreshExchangeRates()
        if exchangeResult.didChangeRates, finance.hasForeignCurrencyExposure(relativeTo: settings.currency) {
            finance.takeSnapshot(settings: settings)
        }

        let marketResult = await refreshMarketPrices()
        alert = MacRootAlert(
            title: marketResult.title,
            message: "\(exchangeResult.message)\n\n\(marketResult.message)"
        )
    }

    private func refreshMarketPrices() async -> MarketPriceRefreshResult {
        let finnhubKey = try? KeychainCredentialStore.shared.string(for: .finnhubAPIKey)
        let coinGeckoKey = try? KeychainCredentialStore.shared.string(for: .coingeckoAPIKey)
        return await finance.refreshMarketPrices(
            finnhubAPIKey: finnhubKey ?? nil,
            coingeckoAPIKey: coinGeckoKey ?? nil,
            settings: settings
        )
    }

    private func processRecurringTransactions() async {
        let insertedCount = finance.processDueRecurringTransactions(settings: settings)
        await syncRecurringNotifications()

        guard insertedCount > 0 else { return }
        alert = MacRootAlert(
            title: "Recurring Transactions Added",
            message: "\(insertedCount) due transaction\(insertedCount == 1 ? " was" : "s were") added to Cash Flow."
        )
    }

    private func syncRecurringNotifications() async {
        await MacRecurringTransactionNotificationService.shared.sync(
            schedules: finance.data.recurringTransactions,
            currencyCode: settings.currency.rawValue,
            showAmounts: !settings.isPrivacyMode
        )
    }
}

private struct MacRootAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
