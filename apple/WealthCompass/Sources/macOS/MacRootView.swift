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
    private let exchangeRateRefreshTimer = Timer.publish(every: 5 * 60 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                MacLockView()
                    .frame(minWidth: 520, minHeight: 400)
            } else if !settings.hasSeenOnboarding {
                MacOnboardingView()
                    .frame(minWidth: 700, minHeight: 500)
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
                        .frame(minWidth: 520, minHeight: 400)
                        .toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                Button {
                                    Task { await refreshData() }
                                } label: {
                                    Label("Refresh Data", systemImage: "arrow.clockwise")
                                }
                                .disabled(isRefreshing)
                                .keyboardShortcut("r", modifiers: .command)

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
        .onReceive(exchangeRateRefreshTimer) { _ in
            guard scenePhase == .active, appLock.isUnlocked else { return }
            Task { await refreshExchangeRatesIfNeeded() }
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
        case .settings:
            MacSettingsView()
        }
    }

    private func handleAppBecameActive() async {
        await finance.refreshICloudSyncIfNeeded()
        await processRecurringTransactions()

        if settings.shouldAutoRefreshExchangeRates() {
            await settings.refreshExchangeRatesAndRecalculate(finance: finance)
        }

        if finance.shouldAutoRefreshMarketPrices() {
            _ = await refreshMarketPrices()
        }
    }

    private func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var exchangeResultForAlert: ExchangeRateRefreshResult?
        await settings.refreshExchangeRatesAndRecalculate(finance: finance) { result in
            exchangeResultForAlert = result
        }

        let marketResult = await refreshMarketPrices()
        let exchangeMessage = exchangeResultForAlert?.message ?? ""
        alert = MacRootAlert(
            title: marketResult.title,
            message: String(localized: "\(exchangeMessage)\n\n\(marketResult.message)")
        )
    }

    private func refreshExchangeRatesIfNeeded() async {
        guard settings.shouldAutoRefreshExchangeRates() else { return }
        await settings.refreshExchangeRatesAndRecalculate(finance: finance)
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
            title: String(localized: "Recurring Transactions Added"),
            message: String(localized: "\(insertedCount) due transaction\(insertedCount == 1 ? " was" : "s were") added to Cash Flow.")
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
