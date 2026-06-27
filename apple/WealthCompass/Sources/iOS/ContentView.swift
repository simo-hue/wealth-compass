import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var recurringInsertionAlert: RecurringInsertionAlert?

    private let recurringCheckTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let exchangeRateRefreshTimer = Timer.publish(every: 5 * 60 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                LockView()
            } else if !settings.hasSeenOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                tabs
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
        .overlay {
            // WC-L26: opaque privacy shield over the app-switcher snapshot and transient
            // interruptions, so financial data isn't exposed without forcing a re-auth.
            if scenePhase != .active {
                PrivacyShield()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // WC-L26: hard-lock only on .background. Transient .inactive events (Control Center,
            // the share sheet, an incoming call) are covered by the shield above instead, so the
            // user isn't forced to re-authenticate after every harmless interruption.
            if newPhase == .background {
                appLock.lock()
            } else if newPhase == .active {
                Task { await handleAppBecameActive() }
            }
        }
        .onChange(of: appLock.isUnlocked) { _, isUnlocked in
            // WC-M6: handleAppBecameActive is guarded out while locked, so run it once the user
            // actually unlocks — otherwise sync/recurring would be skipped until the next foreground.
            if isUnlocked { Task { await handleAppBecameActive() } }
        }
        .task {
            await handleAppBecameActive()
        }
        .onReceive(recurringCheckTimer) { _ in
            guard scenePhase == .active, appLock.isUnlocked else { return }
            Task { await processRecurringTransactions() }
        }
        .onReceive(exchangeRateRefreshTimer) { _ in
            guard scenePhase == .active, appLock.isUnlocked else { return }
            Task { await refreshExchangeRatesIfNeeded() }
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
                .tabItem { tabLabel(.dashboard, systemImage: "gauge.with.dots.needle.67percent") }

            CashFlowView()
                .tabItem { tabLabel(.cashFlow, systemImage: "arrow.left.arrow.right") }

            InvestmentsView()
                .tabItem { tabLabel(.investments, systemImage: "chart.line.uptrend.xyaxis") }

            CryptoView()
                .tabItem { tabLabel(.crypto, systemImage: "bitcoinsign.circle") }

            SettingsView()
                .tabItem { tabLabel(.settings, systemImage: "gearshape") }
        }
        .tint(WCColor.primary)
        .toolbarColorScheme(.dark, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func tabLabel(_ tab: TabBarLabelResolver.Tab, systemImage: String) -> some View {
        Label {
            Text(TabBarLabelResolver.title(for: tab, appLanguage: settings.appLanguage))
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private func handleAppBecameActive() async {
        // WC-M6: don't sync, generate recurring transactions, or surface their alert while the
        // lock screen is up; the .onChange(isUnlocked) handler re-runs this right after unlock.
        guard appLock.isUnlocked else { return }
        await finance.ensureICloudSyncRunning()
        await finance.requestICloudSync()
        await processRecurringTransactions()
        await refreshRemoteDataIfNeeded()
    }

    private func refreshRemoteDataIfNeeded() async {
        await refreshExchangeRatesIfNeeded()
        await refreshMarketPricesIfNeeded()
    }

    private func processRecurringTransactions() async {
        let insertedCount = finance.processDueRecurringTransactions(settings: settings)
        // WC-L1: only re-sync notifications when occurrences were actually generated. Schedule
        // edits are handled by the .onChange(recurringTransactions) observer, so the 30s timer
        // no longer tears down and rebuilds every notification request each tick.
        guard insertedCount > 0 else { return }
        await syncRecurringNotifications()
        let message = insertedCount == 1
            ? settings.localized("1 scheduled transaction was automatically added to Cash Flow.")
            : settings.localized("\(insertedCount) scheduled transactions were automatically added to Cash Flow.")
        recurringInsertionAlert = RecurringInsertionAlert(
            message: message
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
        await settings.refreshExchangeRatesAndRecalculate(finance: finance)
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

/// WC-L26: an opaque cover shown whenever the scene isn't active, so the app-switcher snapshot
/// and transient interruptions never expose financial data. Opaque (not a blur) so nothing leaks.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            WCColor.background
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(WCColor.primary.opacity(0.5))
        }
        .ignoresSafeArea()
    }
}
