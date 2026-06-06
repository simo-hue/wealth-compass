import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var recurringInsertionAlert: RecurringInsertionAlert?

    private let recurringCheckTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                LockView()
            } else {
                tabs
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                appLock.lock()
            } else if newPhase == .active {
                Task { await handleAppBecameActive() }
            }
        }
        .task {
            await handleAppBecameActive()
        }
        .onReceive(recurringCheckTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await processRecurringTransactions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recurringTransactionNotificationReceived)) { _ in
            Task { await processRecurringTransactions() }
        }
        .onChange(of: finance.data.recurringTransactions) { _, _ in
            Task { await syncRecurringNotifications() }
        }
        .alert(item: $recurringInsertionAlert) { alert in
            Alert(
                title: Text("Recurring Transactions Added"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var tabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            CashFlowView()
                .tabItem { Label("Cash Flow", systemImage: "arrow.left.arrow.right") }

            InvestmentsView()
                .tabItem { Label("Investments", systemImage: "chart.line.uptrend.xyaxis") }

            CryptoView()
                .tabItem { Label("Crypto", systemImage: "bitcoinsign.circle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(WCColor.primary)
    }

    private func handleAppBecameActive() async {
        await finance.refreshICloudSyncIfNeeded()
        await processRecurringTransactions()
        await refreshRemoteDataIfNeeded()
    }

    private func refreshRemoteDataIfNeeded() async {
        await refreshExchangeRatesIfNeeded()
        await refreshMarketPricesIfNeeded()
    }

    private func processRecurringTransactions() async {
        let insertedCount = finance.processDueRecurringTransactions(settings: settings)
        await syncRecurringNotifications()

        guard insertedCount > 0 else { return }
        let transactionWord = insertedCount == 1 ? "transaction was" : "transactions were"
        recurringInsertionAlert = RecurringInsertionAlert(
            message: "\(insertedCount) scheduled \(transactionWord) automatically added to Cash Flow."
        )
    }

    private func syncRecurringNotifications() async {
        await RecurringTransactionNotificationService.shared.sync(
            schedules: finance.data.recurringTransactions,
            currencyCode: settings.currency.rawValue,
            showAmounts: !settings.isPrivacyMode
        )
    }

    private func refreshExchangeRatesIfNeeded() async {
        guard settings.shouldAutoRefreshExchangeRates() else { return }
        let result = await settings.refreshExchangeRates()
        if result.didChangeRates, finance.hasForeignCurrencyExposure(relativeTo: settings.currency) {
            finance.takeSnapshot(settings: settings)
        }
    }

    private func refreshMarketPricesIfNeeded() async {
        guard finance.shouldAutoRefreshMarketPrices() else { return }
        let finnhubAPIKey: String?
        let coingeckoAPIKey: String?
        do {
            finnhubAPIKey = try KeychainCredentialStore.shared.string(for: .finnhubAPIKey)
        } catch {
            finnhubAPIKey = nil
        }
        do {
            coingeckoAPIKey = try KeychainCredentialStore.shared.string(for: .coingeckoAPIKey)
        } catch {
            coingeckoAPIKey = nil
        }
        _ = await finance.refreshMarketPrices(
            finnhubAPIKey: finnhubAPIKey,
            coingeckoAPIKey: coingeckoAPIKey,
            settings: settings
        )
    }
}

private struct RecurringInsertionAlert: Identifiable {
    let id = UUID()
    let message: String
}
