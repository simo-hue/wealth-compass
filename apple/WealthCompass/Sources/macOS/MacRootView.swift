import SwiftUI

struct MacRootView: View {
    @Environment(\.locale) private var locale
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
                                // WC-M12: "Refresh Data" is meaningless on the Settings page —
                                // hide it (and its ⌘R) there. Settings stays a sidebar destination.
                                if appModel.selection != .settings {
                                    Button {
                                        Task { await refreshData() }
                                    } label: {
                                        Label(refreshDataLabel, systemImage: "arrow.clockwise")
                                    }
                                    .disabled(isRefreshing)
                                    .keyboardShortcut("r", modifiers: .command)
                                }
                            }
                        }
                }
                .navigationSplitViewStyle(.balanced)
                // WC-M5: force the language re-render here (post-onboarding) instead of at the
                // app root, so changing language never resets the onboarding flow.
                .id(settings.appLanguage ?? "system")
            }
        }
        .overlay(alignment: .top) {
            if let persistenceError = finance.persistenceError {
                PersistenceErrorBanner(message: persistenceError)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: finance.persistenceError)
        .sheet(item: $appModel.editor) { editor in
            MacEditorSheet(editor: editor)
                .environmentObject(finance)
                .environmentObject(settings)
                .appLanguage(settings.appLanguage)
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
        .onChange(of: appLock.isUnlocked) { _, isUnlocked in
            // WC-M6: became-active work is guarded out while locked, so run it once the user unlocks.
            if isUnlocked { Task { await handleAppBecameActive() } }
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

    private var refreshDataLabel: String {
        if let progress = finance.marketRefreshProgress, progress.total > 0 {
            return settings.localized("Updating \(progress.done) of \(progress.total)")
        }
        return settings.localized("Refresh Data")
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
        // WC-M6: don't sync, generate recurring transactions, or surface their alert while the
        // lock screen is up; the .onChange(isUnlocked) handler re-runs this right after unlock.
        guard appLock.isUnlocked else { return }
        await finance.ensureICloudSyncRunning()
        await finance.requestICloudSync()
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
        let exchangeMessage = exchangeResultForAlert?.localizedMessage(appLanguage: settings.appLanguage) ?? ""
        let marketMessage = marketResult.localizedMessage(appLanguage: settings.appLanguage)
        // WC-L19: both parts are already localized — concatenate directly rather than running
        // them through a `"%@\n\n%@"` lookup (which also left stray newlines when one was empty).
        alert = MacRootAlert(
            title: marketResult.localizedTitle(appLanguage: settings.appLanguage),
            message: [exchangeMessage, marketMessage].filter { !$0.isEmpty }.joined(separator: "\n\n")
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
        // WC-L18: use two explicit keys instead of concatenating grammar fragments, so
        // translators get full sentences (mirrors the singular/plural pattern in MacSettingsView).
        let message = insertedCount == 1
            ? settings.localized("1 due transaction was added to Cash Flow.")
            : settings.localized("\(insertedCount) due transactions were added to Cash Flow.")
        alert = MacRootAlert(
            title: settings.localized("Recurring Transactions Added"),
            message: message
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
