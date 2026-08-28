import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var recurringInsertionAlert: RecurringInsertionAlert?
    @State private var selectedTab: TabBarLabelResolver.Tab = .dashboard

    private let recurringCheckTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let exchangeRateRefreshTimer = Timer.publish(every: 5 * 60 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                LockView()
            } else if finance.loadState != .loaded {
                // WC-LOCK1: ordered before onboarding so the load gate covers the setup flow too.
                // Not because onboarding would lose data — it writes nothing through `FinanceStore`,
                // only `settings.currency`, `settings.appLanguage`, `hasSeenOnboarding` and the
                // Keychain API keys, none of which live in the finance DB. Two other reasons:
                //
                // `.notLoaded` is the state every launch starts in, so this branch is also the
                // launch spinner. Ordered after onboarding, a first run would start the flow
                // against a store still being read and then cross-fade out from under the user the
                // moment that read failed, discarding whatever they had typed into it.
                //
                // And this branch stands in for the whole app, Settings included, so
                // `FinanceDataUnavailableView`'s Retry / Export diagnostics / Erase local data are
                // the only such controls *reachable in this state* — `SettingsView` has its own
                // Export Sync Diagnostics and Erase Everything, but nothing here can get to them.
                // Behind onboarding, a user whose database is corrupt on first run would have to
                // finish or skip setup before being told anything was wrong, or offered a way out.
                //
                // (`hasSeenOnboarding` lives in UserDefaults, so a *returning* user is never sent
                // back to onboarding by either ordering.)
                FinanceDataUnavailableView(
                    state: finance.loadState,
                    isCloudSyncEnabled: settings.isICloudSyncEnabled,
                    retry: { await finance.retryLoadIfNeeded(reason: "user retry") },
                    exportDiagnostics: { try finance.exportSyncDiagnosticsURL() },
                    eraseLocalData: {
                        // Local-only: the iCloud copy is the user's way back if the local DB is
                        // the broken part. Mirrors SettingsView.performErase's follow-up steps,
                        // which are unreachable from here.
                        _ = try? await finance.eraseEverything(deleteCloud: false)
                        appLock.disableLock()
                        await RecurringTransactionNotificationService.shared.cancelAll()
                    }
                )
            } else if !settings.hasSeenOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                tabs
                    .id(settings.appLanguage ?? "system")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: finance.loadState)
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
            //
            // Kept alongside the window below, not replaced by it: this covers the root itself the
            // instant SwiftUI re-renders, while the window covers whatever is presented *above* the
            // root — which an overlay structurally cannot reach.
            if scenePhase != .active {
                PrivacyShield()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The overlay above cannot cover a presented sheet: an editor or the export sheet is
            // presented above this view's hosting controller, so the overlay painted behind it and
            // the app-switcher snapshot kept the sheet's figures. Same condition, second surface.
            DesktopPlatform.setPrivacyShieldVisible(newPhase != .active)

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
        .onChange(of: settings.isICloudSyncEnabled) { _, enabled in
            // M31: register for push the moment sync is enabled, so it works without a foreground round-trip.
            if enabled { UIApplication.shared.registerForRemoteNotifications() }
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
        .onChange(of: settings.currency) { _, _ in
            // SYNC-01: rebuild already-scheduled recurring notifications when the display currency
            // changes, so pending reminders show the new currency/amount instead of the stale one
            // (mirrors macOS MacRootView; iOS previously only re-synced on recurringTransactions).
            Task { await syncRecurringNotifications() }
        }
        .onChange(of: settings.isPrivacyMode) { _, _ in
            // SYNC-01: rebuild already-scheduled recurring notifications when Privacy Mode toggles,
            // so a pending reminder's amount is hidden/shown per the new setting rather than leaking
            // the previously-scheduled amount on the lock screen (mirrors macOS MacRootView).
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
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem { tabLabel(.dashboard, systemImage: "gauge.with.dots.needle.67percent") }
                .tag(TabBarLabelResolver.Tab.dashboard)

            CashFlowView()
                .tabItem { tabLabel(.cashFlow, systemImage: "arrow.left.arrow.right") }
                .tag(TabBarLabelResolver.Tab.cashFlow)

            InvestmentsView()
                .tabItem { tabLabel(.investments, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(TabBarLabelResolver.Tab.investments)

            CryptoView()
                .tabItem { tabLabel(.crypto, systemImage: "bitcoinsign.circle") }
                .tag(TabBarLabelResolver.Tab.crypto)

            SettingsView()
                .tabItem { tabLabel(.settings, systemImage: "gearshape") }
                .tag(TabBarLabelResolver.Tab.settings)
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
        // WC-LOCK1: second recovery trigger, complementing the protectedDataDidBecomeAvailable
        // observer. Covers the case that produced the original report — a process launched behind
        // a locked screen that is still alive when the user later opens the app — plus any load
        // failure that has nothing to do with the lock screen. No-ops once loaded.
        await finance.retryLoadIfNeeded(reason: "foreground")
        await finance.ensureICloudSyncRunning()
        // M31: register for silent CloudKit pushes so remote changes propagate in near-real-time /
        // in the background, instead of only on the next foreground. Idempotent; only when sync is on.
        if settings.isICloudSyncEnabled {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await finance.requestICloudSync()
        await processRecurringTransactions()
        await refreshRemoteDataIfNeeded()
    }

    private func refreshRemoteDataIfNeeded() async {
        await refreshExchangeRatesIfNeeded()
        await refreshMarketPricesIfNeeded()
    }

    private func processRecurringTransactions() async {
        // Deep-audit H01: never generate/sync recurring transactions or surface their alert while the
        // lock screen is up. The `.recurringTransactionNotificationReceived` handler calls this
        // without a lock guard (unlike the timers), so guard here — the single point every path
        // funnels through. `handleAppBecameActive` re-runs this right after unlock, so nothing is lost.
        guard appLock.isUnlocked else { return }
        let insertedCount = finance.processDueRecurringTransactions(settings: settings)
        // WC-L1: only re-sync notifications when occurrences were actually generated. Schedule
        // edits are handled by the .onChange(recurringTransactions) observer, so the 30s timer
        // no longer tears down and rebuilds every notification request each tick.
        guard insertedCount > 0 else { return }
        await syncRecurringNotifications()
        // Hidden, not reworded: this alert only ever fires when `insertedCount > 0`, so its
        // *appearance* already says a schedule came due, and its sentence then says how many.
        // Dropping the number would leave the first half of that intact — the slot is the signal.
        // The occurrences are still generated and still saved; only the announcement stops, and
        // the notification path two lines up is gated on the same flag
        // (`showDetails: !settings.isPrivacyMode`), which is why this one stood out.
        guard !settings.isPrivacyMode else { return }
        let message = insertedCount == 1
            ? settings.localized("1 scheduled transaction was automatically added to Cash Flow.")
            : settings.localized("\(insertedCount) scheduled transactions were automatically added to Cash Flow.")
        recurringInsertionAlert = RecurringInsertionAlert(
            message: message
        )
    }

    private func syncRecurringNotifications() async {
        let schedules = finance.data.recurringTransactions
        let convertedAmounts = Dictionary(
            schedules.map { ($0.id, settings.convert($0.amount, from: $0.currency)) },
            uniquingKeysWith: { first, _ in first }
        )
        await RecurringTransactionNotificationService.shared.sync(
            schedules: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: settings.currency.rawValue,
            showDetails: !settings.isPrivacyMode
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
