import SwiftUI

struct MacRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    private var shouldCoverForPrivacy: Bool { Self.shouldCoverForPrivacy(scenePhase) }

    /// Whether the privacy cover belongs on screen for this scene phase.
    ///
    /// `!= .active` is right on macOS, where `.inactive` means another app is frontmost. It is
    /// wrong on iPadOS: a Split View or Stage Manager window that is merely *unfocused* reports
    /// `.inactive` while staying fully visible to its own user, so tapping into Safari beside the
    /// app turned it into an opaque locked panel — and stopped the 30-second recurring timer and
    /// the rate refresh with it, since both gate on `.active`.
    ///
    /// `.background` is the phase that actually precedes a snapshot on iOS, and it is already what
    /// the hard lock below keys on, so the cover and the lock now agree about what "away" means.
    ///
    /// This fixes the cover only. The 30-second recurring timer and the rate refresh still guard on
    /// `scenePhase == .active` further down, so on an unfocused iPad window they remain paused —
    /// separate from this, and left alone deliberately rather than fixed in passing.
    static func shouldCoverForPrivacy(_ phase: ScenePhase) -> Bool {
        #if os(macOS)
        phase != .active
        #else
        phase == .background
        #endif
    }
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appLock: MacAppLockStore
    @State private var isRefreshing = false
    @State private var alert: MacRootAlert?
    // Persisted sidebar-collapse state; when collapsed, the page-switcher (MacGlobalNavBar) moves into
    // the toolbar's center and the window title is blanked.
    @AppStorage("wc_mac_sidebar_collapsed") private var sidebarCollapsed = false

    private let recurringCheckTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let exchangeRateRefreshTimer = Timer.publish(every: 5 * 60 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                MacLockView()
                    .desktopWindowSize(minWidth: 520, minHeight: 400)
            } else if finance.loadState != .loaded {
                // WC-LOCK1: mirrors iOS. macOS can't hit the lock-screen variant (no lock-time
                // protection classes), but any load failure — a permissions problem, a bad disk —
                // must never be rendered as a zeroed net worth here either. And because macOS
                // failures are never the self-resolving kind, the recovery actions matter more
                // here, not less.
                FinanceDataUnavailableView(
                    state: finance.loadState,
                    isCloudSyncEnabled: settings.isICloudSyncEnabled,
                    retry: { await finance.retryLoadIfNeeded(reason: "user retry") },
                    exportDiagnostics: { try finance.exportSyncDiagnosticsURL() },
                    eraseLocalData: {
                        _ = try? await finance.eraseEverything(deleteCloud: false)
                        appLock.disableLock()
                        await MacRecurringTransactionNotificationService.shared.cancelAll()
                    }
                )
                .desktopWindowSize(minWidth: 520, minHeight: 400)
            } else if !settings.hasSeenOnboarding {
                MacOnboardingView()
                    .desktopWindowSize(minWidth: 700, minHeight: 500)
            } else {
                mainSplitView
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
            // Deep-audit H03/H04 + privacy: an opaque cover so financial data isn't exposed during
            // app switching / Mission Control without forcing a re-authentication. The condition is
            // `shouldCoverForPrivacy(_:)` and differs by platform — it is NOT simply "not active"
            // any more, and it no longer mirrors the iPhone root, which keeps `!= .active` because
            // iPhone has no unfocused-but-visible window state to be wrong about.
            if shouldCoverForPrivacy {
                MacPrivacyShield()
            }
        }
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
            // The overlay above cannot cover the editor or export sheet: both are presented above
            // this view's hosting controller, so on iPad the app-switcher snapshot kept them while
            // the cover sat behind. Second surface, same `shouldCoverForPrivacy` condition as the
            // overlay; a no-op on macOS, which has no snapshot and keeps the overlay alone.
            DesktopPlatform.setPrivacyShieldVisible(Self.shouldCoverForPrivacy(phase))

            // Deep-audit H03/H04: hard-lock only on .background (the app hidden via Cmd-H or all
            // windows minimized). Transient .inactive (another app frontmost, Mission Control, screen
            // occlusion) is covered by the privacy shield above instead, so simply switching apps no
            // longer forces a re-authentication. Mirrors the iOS behavior (WC-L26).
            if phase == .background {
                appLock.lock()
            } else if phase == .active {
                Task { await handleAppBecameActive() }
            }
        }
        .onChange(of: appLock.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                // WC-M6: became-active work is guarded out while locked, so run it once the user unlocks.
                Task { await handleAppBecameActive() }
            } else {
                // Deep-audit H02: dismiss any presented editor sheet when the app locks, so a
                // pre-filled financial form can't remain visible over the lock screen.
                appModel.editor = nil
            }
        }
        .onChange(of: finance.loadState) { _, state in
            // WC-LOCK1: the editor sheet is attached to this Group, outside the loadState branch,
            // so it would stay on screen over the "Data Unavailable" view. Dismiss it — anything
            // typed into it cannot be saved and would be discarded by the next successful load.
            // Mirrors the app-lock handler above, which dismisses it for the same reason.
            if state != .loaded { appModel.editor = nil }
        }
        .onChange(of: settings.isICloudSyncEnabled) { _, enabled in
            // M31: register for push the moment sync is enabled, so it works without a foreground round-trip.
            if enabled { DesktopPlatform.registerForRemoteNotifications() }
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

    // Post-onboarding main UI: the sidebar + detail split. Extracted from `body` so each view
    // expression stays small enough for the Swift type-checker.
    private var mainSplitView: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List(MacDestination.allCases, selection: $appModel.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Wealth Compass Tracker")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .desktopWindowSize(minWidth: 520, minHeight: 400)
                // iPad puts the page-switcher along the bottom edge (see `bottomNavBar`), so the
                // title bar is free and the page name goes back into it. On macOS the switcher
                // still fills the title bar itself, and its highlighted segment already names the
                // current page — so blank the title there to avoid saying it twice. Either way,
                // with the sidebar expanded it is the sidebar that navigates and the title stands.
                .navigationTitle(
                    sidebarCollapsed && !DesktopPlatform.isPad
                        ? "" : (appModel.selection ?? .dashboard).title
                )
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomNavBar }
                .toolbar {
                    // Collapsed-only global page-switcher, centered in the toolbar. macOS only:
                    // a title-bar segment is the desktop idiom, whereas reaching the top of a
                    // 13-inch iPad to change page is not — there it sits under the thumbs
                    // instead, where iPhone's tab bar is.
                    if sidebarCollapsed, !DesktopPlatform.isPad {
                        ToolbarItem(placement: .principal) {
                            MacGlobalNavBar(selection: $appModel.selection)
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Refresh Data (⌘R) — hidden on the Settings page, which has its own
                        // market-data / exchange-rate refresh controls.
                        if (appModel.selection ?? .dashboard) != .settings {
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

    /// iPad's page-switcher, pinned along the bottom edge in place of the macOS title-bar segment.
    ///
    /// A `safeAreaInset` rather than an overlay, so each page's own scroll view ends above the
    /// pill instead of running underneath it — the same contract iPhone's tab bar has with the
    /// views behind it. Shown on exactly the same condition as the macOS toolbar version: with the
    /// sidebar open it is the sidebar that navigates, and two page-switchers on screen at once
    /// would just be asking the same question twice.
    @ViewBuilder
    private var bottomNavBar: some View {
        if sidebarCollapsed, DesktopPlatform.isPad {
            MacGlobalNavBar(selection: $appModel.selection)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }

    // Maps the persisted collapse flag to the NavigationSplitView column visibility (and back, so the
    // native sidebar toggle / drag keeps the flag — and the toolbar page-switcher's visibility — in
    // sync).
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarCollapsed ? .detailOnly : .all },
            set: { sidebarCollapsed = ($0 == .detailOnly) }
        )
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
        // WC-LOCK1: retry a load that previously failed, mirroring iOS. No-ops once loaded.
        await finance.retryLoadIfNeeded(reason: "foreground")
        await finance.ensureICloudSyncRunning()
        // M31: register for silent CloudKit pushes so remote changes propagate in near-real-time /
        // in the background, instead of only on the next foreground. Idempotent; only when sync is on.
        if settings.isICloudSyncEnabled {
            DesktopPlatform.registerForRemoteNotifications()
        }
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
        // Deep-audit H01: never generate/sync recurring transactions or surface their alert while the
        // lock screen is up. The `.macRecurringTransactionNotificationReceived` handler calls this
        // without a lock guard (unlike the timers), so guard here — the single point every path
        // funnels through. `handleAppBecameActive` re-runs this right after unlock, so nothing is lost.
        guard appLock.isUnlocked else { return }
        let insertedCount = finance.processDueRecurringTransactions(settings: settings)
        // WC-L1: only re-sync notifications when occurrences were generated (schedule edits are
        // handled by the .onChange observers), so the 30s timer doesn't churn notifications.
        guard insertedCount > 0 else { return }
        await syncRecurringNotifications()
        // Hidden, not reworded: this alert only ever fires when `insertedCount > 0`, so its
        // *appearance* already says a schedule came due, and its sentence then says how many.
        // Dropping the number would leave the first half of that intact — the slot is the signal.
        // The occurrences are still generated and still saved; only the announcement stops, and
        // the notification path two lines up is gated on the same flag
        // (`showDetails: !settings.isPrivacyMode`), which is why this one stood out.
        guard !settings.isPrivacyMode else { return }
        // WC-L18: a full sentence, never concatenated grammar fragments, so translators get
        // something they can actually restructure.
        //
        // One key for every count, not a singular/plural pair chosen here. Branching in Swift can
        // only express the two categories English has, and it silently imposes them on languages
        // that have more: Czech and Slovak need a distinct form at n=2..4, and Russian, Ukrainian,
        // Polish, Croatian and Romanian all put 21, 31, 101 back in the *singular* category. The
        // catalog carries `variations.plural` instead, which CLDR selects per locale.
        let message = settings.localized("\(insertedCount) due transactions were added to Cash Flow.")
        alert = MacRootAlert(
            title: settings.localized("Recurring Transactions Added"),
            message: message
        )
    }

    private func syncRecurringNotifications() async {
        let schedules = finance.data.recurringTransactions
        let convertedAmounts = Dictionary(
            schedules.map { ($0.id, settings.convert($0.amount, from: $0.currency)) },
            uniquingKeysWith: { first, _ in first }
        )
        await MacRecurringTransactionNotificationService.shared.sync(
            schedules: schedules,
            convertedAmounts: convertedAmounts,
            currencyCode: settings.currency.rawValue,
            showDetails: !settings.isPrivacyMode
        )
    }
}

private struct MacRootAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Global page-switcher shown when the NavigationSplitView sidebar is collapsed — an icon+label pill
/// (mirrors the MacSelectorIsland aesthetic) that reaches every page, incl. Settings. It is hosted
/// as a `ToolbarItem(placement: .principal)`, so it sits centred in the title bar rather than
/// floating over the page; that is what keeps it clear of each page's own top selector.
private struct MacGlobalNavBar: View {
    @Binding var selection: MacDestination?
    @Namespace private var namespace

    /// The pill measures 553pt in English and 576pt in German with all five titles and icons —
    /// comfortably inside a full-screen iPad, and wider than every narrower multitasking size the
    /// app can be put into. With no ladder it simply ran off the edge, taking **Settings** with it,
    /// and on iPad this is the *only* page switcher there is: the toolbar copy above is gated
    /// `!DesktopPlatform.isPad`, so an unreachable item here is an unreachable page.
    ///
    /// Three rungs, because two do not cover the middle: dropping the icons alone saves roughly
    /// 100pt, which is enough for a half-and-half split (~507pt) but nowhere near Slide Over's
    /// 320pt. Icon-only measures ~234pt and reaches it. The icons are distinct per destination and
    /// each still carries `destination.title` as its accessibility label — `.labelStyle` changes
    /// what is *drawn*, not what VoiceOver reads — and `.help` keeps the pointer tooltip.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(.titleAndIcon, geometryID: "mac_global_nav_full")
            pill(.titleOnly, geometryID: "mac_global_nav_titles")
            pill(.iconOnly, geometryID: "mac_global_nav_icons")
        }
    }

    /// One rung of the ladder.
    ///
    /// `geometryID` differs per rung on purpose: `ViewThatFits` builds every candidate in order to
    /// measure it, and two live `matchedGeometryEffect` sources sharing one id in one namespace is
    /// exactly the "multiple inserted views in matched geometry group" case.
    private func pill(_ style: NavBarLabelStyle, geometryID: String) -> some View {
        HStack(spacing: 4) {
            ForEach(MacDestination.allCases) { destination in
                let isSelected = selection == destination
                Button {
                    selection = destination
                } label: {
                    navLabel(for: destination, style: style)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .matchedGeometryEffect(id: geometryID, in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(destination.title)
            }
        }
        // Titles must never be the thing that shrinks: a wrapped or truncated title here would
        // hide the ladder's own failure instead of letting the next rung win.
        .fixedSize()
        .padding(4)
        .background(
            Capsule()
                .fill(Color(white: 0.13))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
        // Subtle shadow — the pill sits inside the toolbar rather than floating over content.
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    }

    /// `LabelStyle` is a protocol, and the three concrete styles are different types, so a rung
    /// cannot take one as a parameter without erasing it. This enum is that choice, spelled out.
    private enum NavBarLabelStyle {
        case titleAndIcon, titleOnly, iconOnly
    }

    @ViewBuilder
    private func navLabel(for destination: MacDestination, style: NavBarLabelStyle) -> some View {
        let label = Label(destination.title, systemImage: destination.systemImage)
        switch style {
        case .titleAndIcon: label.labelStyle(.titleAndIcon)
        case .titleOnly: label.labelStyle(.titleOnly)
        case .iconOnly: label.labelStyle(.iconOnly)
        }
    }
}

/// An opaque cover shown whenever the window isn't active, so financial data isn't exposed during
/// app switching / Mission Control without forcing a re-auth. Opaque (not a blur) so nothing leaks.
/// Mirrors the iOS `PrivacyShield` (WC-L26).
private struct MacPrivacyShield: View {
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
