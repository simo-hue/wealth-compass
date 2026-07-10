import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var backupURL: URL?
    @State private var diagnosticsURL: URL?
    @State private var backupError: String?
    @State private var importMode: FinanceImportMode = .merge
    @State private var showingImportOptions = false
    @State private var showingFileImporter = false
    @State private var importSummary: FinanceImportResult?
    @State private var importSummaryNote: String?
    @State private var settingsAlert: SettingsAlertState?
    @State private var credentialEditorAlert: SettingsAlertState?
    @State private var activeCredentialEditor: MarketDataCredentialKind?
    @State private var credentialDraft = ""
    @State private var hasFinnhubAPIKey = false
    @State private var hasCoinGeckoAPIKey = false
    @State private var isSavingMarketDataCredential = false
    @State private var isRefreshingPrices = false
    @State private var pendingDestructiveAction: SettingsDestructiveAction?
    @State private var showingEraseFailure = false
    @State private var eraseFailureMessage = ""
    @State private var isErasing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    settingsOverview
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Region & Language") {
                    Picker("Language", selection: $settings.appLanguage) {
                        Text("System").tag(String?.none)
                        ForEach(settings.availableLanguages, id: \.self) { code in
                            Text(settings.languageName(for: code)).tag(String?.some(code))
                        }
                    }
                    
                    Picker("Base Currency", selection: $settings.currency) {
                        ForEach(Currency.allCases) { currency in
                            (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                        }
                    }
                }

                Section("Privacy") {
                    Toggle(isOn: $settings.isPrivacyMode) {
                        Label("Privacy Mode", systemImage: settings.isPrivacyMode ? "eye.slash" : "eye")
                    }
                    .tint(WCColor.primary)
                }

                Section("Security") {
                    Toggle(isOn: biometricLockBinding) {
                        Label("\(appLock.biometryName(appLanguage: settings.appLanguage)) App Lock", systemImage: "lock.shield")
                    }
                    .tint(WCColor.primary)

                    if let error = appLock.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WCColor.destructive)
                    } else {
                        Text("When enabled, Wealth Compass locks whenever the app leaves the foreground.")
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }

                Section("Custom Categories") {
                    categoryGroup(title: "Income", type: .income, categories: settings.customIncomeCategories)
                    categoryGroup(title: "Expense", type: .expense, categories: settings.customExpenseCategories)
                }

                marketDataSection

                Section("iCloud Sync") {
                    Toggle(isOn: $settings.isICloudSyncEnabled) {
                        Label("Sync Data with iCloud", systemImage: "icloud")
                    }
                    .tint(WCColor.primary)
                    .onChange(of: settings.isICloudSyncEnabled) { _, isEnabled in
                        Task {
                            await finance.setICloudSyncEnabled(isEnabled)
                        }
                    }

                    Text("Your financial data stays available locally and syncs across your devices through your private CloudKit database.")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)

                    Text("Preferences like currency, categories, and language are set per device and don't sync.")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)

                    LabeledContent("Status") {
                        Label {
                            Text(finance.cloudSyncStatus.localizedTitle(appLanguage: settings.appLanguage))
                        } icon: {
                            Image(systemName: finance.cloudSyncStatus.symbolName)
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(finance.cloudSyncStatus.tint)
                    }
                    if let detail = finance.cloudSyncStatus.localizedDetail(appLanguage: settings.appLanguage) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(finance.cloudSyncStatus.tint)
                    }
                    
                    if settings.isICloudSyncEnabled {
                        Button {
                            Task {
                                do {
                                    try await finance.forceICloudSync()
                                } catch {
                                    let syncError = error as? CloudSyncError
                                    settingsAlert = SettingsAlertState(
                                        title: settings.localized(syncError?.alertTitleKey ?? "Sync Failed"),
                                        message: syncError?.localizedDescription(appLanguage: settings.appLanguage)
                                            ?? error.localizedDescription
                                    )
                                }
                            }
                        } label: {
                            Label("Force Sync iCloud", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                        .tint(WCColor.primary)
                        .disabled(finance.cloudSyncStatus.isBusy)
                    }
                }

                Section("Data") {
                    Button {
                        // L55: exportBackupURL is now async (encodes off the MainActor).
                        Task {
                            do {
                                backupURL = try await finance.exportBackupURL()
                                backupError = nil
                            } catch {
                                backupError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Prepare Backup", systemImage: "doc.badge.arrow.up")
                    }

                    Button {
                        showingImportOptions = true
                    } label: {
                        Label("Import JSON Backup", systemImage: "doc.badge.plus")
                    }

                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Share Backup", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let backupError {
                        Text(backupError)
                            .font(.caption)
                            .foregroundStyle(WCColor.destructive)
                    }

                    Button {
                        do {
                            diagnosticsURL = try finance.exportSyncDiagnosticsURL()
                            backupError = nil
                        } catch {
                            backupError = error.localizedDescription
                        }
                    } label: {
                        Label("Export Sync Diagnostics", systemImage: "stethoscope")
                    }

                    if let diagnosticsURL {
                        ShareLink(item: diagnosticsURL) {
                            Label("Share Sync Diagnostics", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteAllData
                    } label: {
                        Label("Erase Everything", systemImage: "trash")
                    }
                    .disabled(isErasing)
                }

                Section("Storage") {
                    HStack {
                        Label("Mode", systemImage: "internaldrive")
                        Spacer()
                        Text("Local Only")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Transactions", systemImage: "arrow.left.arrow.right")
                        Spacer()
                        Text("\(finance.data.transactions.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Recurring", systemImage: "repeat")
                        Spacer()
                        Text("\(finance.data.recurringTransactions.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Text("\(finance.data.investments.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Crypto", systemImage: "bitcoinsign.circle")
                        Spacer()
                        Text("\(finance.data.crypto.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Liabilities", systemImage: "creditcard")
                        Spacer()
                        Text("\(finance.data.liabilities.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Snapshots", systemImage: "camera")
                        Spacer()
                        Text("\(finance.data.snapshots.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }

                exchangeRatesSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .contentMargins(.top, 6, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 50)
            .tint(WCColor.primary)
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .preferredColorScheme(.dark)
            .onAppear {
                refreshMarketDataKeyStatus()
            }
            .alert("Import JSON Backup", isPresented: $showingImportOptions) {
                Button("Merge With Existing Data") {
                    importMode = .merge
                    showingFileImporter = true
                }

                Button("Replace Existing Data", role: .destructive) {
                    importMode = .replace
                    showingFileImporter = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Merge adds new records and updates matching IDs. Replace clears current local finance data before importing.")
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { result in
                handleImportSelection(result)
            }
            .sheet(item: $activeCredentialEditor) { credential in
                MarketDataCredentialEditor(
                    credential: credential,
                    appLanguage: settings.appLanguage,
                    apiKey: $credentialDraft,
                    alert: $credentialEditorAlert,
                    isConfigured: KeychainCredentialStore.shared.contains(credential.keychainCredential),
                    isSaving: isSavingMarketDataCredential,
                    onCancel: {
                        credentialDraft = ""
                        credentialEditorAlert = nil
                        activeCredentialEditor = nil
                    },
                    onSave: {
                        Task { await saveAndTestMarketDataCredential(credential) }
                    },
                    onRemove: {
                        removeMarketDataCredential(credential)
                    }
                )
            }
            .sheet(item: $importSummary) { summary in
                ImportSummaryView(result: summary, appLanguage: settings.appLanguage, additionalNote: importSummaryNote) {
                    importSummary = nil
                    importSummaryNote = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert(item: $settingsAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(item: $pendingDestructiveAction) { action in
                Alert(
                    title: Text(action.localizedTitle(appLanguage: settings.appLanguage)),
                    message: Text(action.message(appLanguage: settings.appLanguage)),
                    primaryButton: .destructive(Text(action.localizedConfirmButtonTitle(appLanguage: settings.appLanguage))) {
                        performDestructiveAction(action)
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Couldn't Delete iCloud Data", isPresented: $showingEraseFailure) {
                Button("Retry") {
                    Task { await performErase(deleteCloud: true) }
                }
                Button("Delete This Device Only", role: .destructive) {
                    Task { await performErase(deleteCloud: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(eraseFailureMessage)
            }
        }
    }

    private var settingsOverview: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WCColor.primary)
                        .frame(width: 42, height: 42)
                        .background(WCColor.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your preferences")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Privacy, sync, currency, and market data")
                            .font(.caption)
                            .foregroundStyle(WCColor.textTertiary)
                    }
                }

                HStack(spacing: 8) {
                    settingsStatusChip(
                        settings.currency.rawValue,
                        systemImage: "coloncurrencysign",
                        color: WCColor.accent
                    )
                    settingsStatusChip(
                        settings.isPrivacyMode ? settings.localized("Private") : settings.localized("Visible"),
                        systemImage: settings.isPrivacyMode ? "eye.slash.fill" : "eye.fill",
                        color: WCColor.primary
                    )
                    settingsStatusChip(
                        settings.isICloudSyncEnabled ? settings.localized("iCloud") : settings.localized("Local"),
                        systemImage: settings.isICloudSyncEnabled ? "icloud.fill" : "internaldrive.fill",
                        color: .blue
                    )
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
    }

    private func settingsStatusChip(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var exchangeRatesSection: some View {
        Section("Exchange Rates") {
            HStack {
                Label("Source", systemImage: "building.columns")
                Spacer()
                if let snapshot = settings.exchangeRateSnapshot {
                    Text("ECB")
                        .foregroundStyle(WCColor.primary)
                    Text("· \(snapshot.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(WCColor.textSecondary)
                } else {
                    Text("Offline fallback")
                        .foregroundStyle(WCColor.warning)
                }
            }

            ForEach(Currency.allCases.filter { $0 != settings.currency }) { quoteCurrency in
                let converted: Double = settings.convert(1, from: settings.currency, to: quoteCurrency)
                HStack {
                    Text("1 \(settings.currency.rawValue)")
                    Spacer()
                    Text("\(converted.formatted(.number.precision(.fractionLength(2...4)))) \(quoteCurrency.rawValue)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(WCColor.textSecondary)
                }
            }

            Button {
                Task { await refreshExchangeRates() }
            } label: {
                Label(
                    settings.isRefreshingExchangeRates
                        ? settings.localized("Refreshing Exchange Rates")
                        : settings.localized("Refresh Exchange Rates"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(settings.isRefreshingExchangeRates)

            if settings.isRefreshingExchangeRates {
                ProgressView()
            }

            if let error = settings.exchangeRateError {
                Text("\(error) Cached or fallback rates remain active.")
                    .font(.caption)
                    .foregroundStyle(WCColor.destructive)
            } else if let snapshot = settings.exchangeRateSnapshot {
                Text("\(snapshot.provider). Fetched \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)) and cached locally.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            } else {
                Text("ECB reference rates are refreshed automatically and cached locally for offline use.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            }

            // L40: warn when a currency the user actually holds is missing from the fresh snapshot and
            // is therefore converting via its approximate offline seed rate.
            if let seedRateNotice {
                Text(seedRateNotice)
                    .font(.caption)
                    .foregroundStyle(WCColor.warning)
            }
        }
    }

    /// L40: a caption naming held currencies that fall back to their offline seed rate, or nil.
    private var seedRateNotice: String? {
        let currencies = finance.heldCurrenciesUsingSeedRate(settings: settings)
        guard !currencies.isEmpty else { return nil }
        let list = currencies.map(\.rawValue).joined(separator: ", ")
        return settings.localized("Rates may be incomplete: \(list) aren't in the latest update and use an approximate offline rate.")
    }

    private var marketDataSection: some View {
        Section("Market Data") {
            Button {
                openCredentialEditor(.finnhub)
            } label: {
                credentialRow(
                    title: "Finnhub API Key",
                    systemImage: "chart.line.uptrend.xyaxis",
                    isConfigured: hasFinnhubAPIKey
                )
            }
            .buttonStyle(.plain)

            Button {
                openCredentialEditor(.coingecko)
            } label: {
                credentialRow(
                    title: "CoinGecko API Key",
                    systemImage: "bitcoinsign.circle",
                    isConfigured: hasCoinGeckoAPIKey
                )
            }
            .buttonStyle(.plain)

            Button {
                Task { await refreshMarketPrices() }
            } label: {
                Label(
                    refreshMarketDataLabel,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(isRefreshingPrices || (finance.data.investments.isEmpty && finance.data.crypto.isEmpty))
        }
    }

    private func credentialRow(title: String, systemImage: String, isConfigured: Bool) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.white)
            Spacer()
            Text(isConfigured ? settings.localized("Configured") : settings.localized("Not Set"))
                .font(.subheadline)
                .foregroundStyle(isConfigured ? WCColor.primary : WCColor.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WCColor.textSecondary)
        }
        .contentShape(Rectangle())
    }

    private var biometricLockBinding: Binding<Bool> {
        Binding {
            appLock.isLockEnabled
        } set: { isEnabled in
            if isEnabled {
                Task { await appLock.enableLock(appLanguage: settings.appLanguage) }
            } else {
                // WC-L3: require auth to turn the lock off (passcode fallback via WC-L2).
                Task { await appLock.confirmDisableLock(appLanguage: settings.appLanguage) }
            }
        }
    }

    private func categoryGroup(title: String, type: TransactionType, categories: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if categories.isEmpty {
                // L21: locale-aware lowercasing (root-locale .lowercased() mis-cases Turkish I/İ, etc.).
                Text("No custom \(title.lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))) categories yet.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            } else {
                ForEach(categories, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        Button(role: .destructive) {
                            pendingDestructiveAction = .deleteCustomCategory(category: category, type: type)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func performDestructiveAction(_ action: SettingsDestructiveAction) {
        switch action {
        case .deleteAllData:
            Task { await performErase(deleteCloud: true) }
        case .deleteCustomCategory(let category, let type):
            settings.removeCustomTransactionCategory(category, for: type)
        }
    }

    /// Runs the factory reset. On success the root view navigates to onboarding (via
    /// `hasSeenOnboarding`), so there's nothing more to show here. If the iCloud deletion
    /// fails, we surface the Retry / "Delete this device only" dialog and keep the data.
    private func performErase(deleteCloud: Bool) async {
        isErasing = true
        defer { isErasing = false }
        do {
            try await finance.eraseEverything(deleteCloud: deleteCloud)
            appLock.disableLock()
            await RecurringTransactionNotificationService.shared.cancelAll()
            backupURL = nil
        } catch {
            let syncError = error as? CloudSyncError
            eraseFailureMessage = syncError?.localizedDescription(appLanguage: settings.appLanguage)
                ?? error.localizedDescription
            showingEraseFailure = true
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // L55: importBackup is now async (parses off the MainActor).
            Task {
                do {
                    let result = try await finance.importBackup(from: url, mode: importMode, settings: settings)
                    // SET-02: match macOS — materialize any now-due recurring transactions the backup
                    // brought in, reschedule notifications, and note the count in the import summary.
                    let insertedCount = finance.processDueRecurringTransactions(settings: settings)
                    await syncRecurringNotifications()
                    if insertedCount == 1 {
                        importSummaryNote = settings.localized("\n\n1 due recurring transaction was added to Cash Flow.")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if insertedCount > 1 {
                        importSummaryNote = settings.localized("\n\n\(insertedCount) due recurring transactions were added to Cash Flow.")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        importSummaryNote = nil
                    }
                    backupURL = nil
                    backupError = nil
                    importSummary = result
                } catch {
                    settingsAlert = SettingsAlertState(
                        title: settings.localized("Import Failed"),
                        message: Self.errorMessage(error, appLanguage: settings.appLanguage)
                    )
                }
            }
        case .failure(let error):
            settingsAlert = SettingsAlertState(
                title: settings.localized("Import Failed"),
                message: error.localizedDescription
            )
        }
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
            showAmounts: !settings.isPrivacyMode
        )
    }

    private func refreshMarketDataKeyStatus() {
        hasFinnhubAPIKey = KeychainCredentialStore.shared.contains(.finnhubAPIKey)
        hasCoinGeckoAPIKey = KeychainCredentialStore.shared.contains(.coingeckoAPIKey)
    }

    private func openCredentialEditor(_ credential: MarketDataCredentialKind) {
        credentialDraft = ""
        credentialEditorAlert = nil
        activeCredentialEditor = credential
    }

    // SET-03: throw on a Keychain read failure instead of masking it as "no key" (mirrors macOS
    // storedAPIKey), so refreshMarketPrices can surface a real error rather than silently going keyless.
    private func currentStoredAPIKey(for credential: KeychainCredential) throws -> String? {
        let value = try KeychainCredentialStore.shared.string(for: credential)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func saveAndTestMarketDataCredential(_ credential: MarketDataCredentialKind) async {
        let key = credentialDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isSavingMarketDataCredential = true
        defer { isSavingMarketDataCredential = false }

        do {
            let message = try await validationMessage(for: credential, apiKey: key)
            try KeychainCredentialStore.shared.save(key, for: credential.keychainCredential)
            credentialDraft = ""
            activeCredentialEditor = nil
            refreshMarketDataKeyStatus()
            settingsAlert = SettingsAlertState(
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Saved"),
                message: "\(message)\n\n\(settings.localized("The API key was saved securely in Keychain."))"
            )
        } catch {
            credentialEditorAlert = SettingsAlertState(
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Failed"),
                message: SettingsView.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func removeMarketDataCredential(_ credential: MarketDataCredentialKind) {
        do {
            try KeychainCredentialStore.shared.delete(credential.keychainCredential)
            credentialDraft = ""
            credentialEditorAlert = nil
            activeCredentialEditor = nil
            refreshMarketDataKeyStatus()
            settingsAlert = SettingsAlertState(
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Removed"),
                message: settings.localized("The API key was removed from Keychain.")
            )
        } catch {
            credentialEditorAlert = SettingsAlertState(
                title: settings.localized("Unable to Remove \(credential.localizedTitle(appLanguage: settings.appLanguage))"),
                message: SettingsView.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func validationMessage(for credential: MarketDataCredentialKind, apiKey: String) async throws -> String {
        let provider: SettingsViewModel.MarketDataProvider
        switch credential {
        case .finnhub: provider = .finnhub
        case .coingecko: provider = .coingecko
        }
        return try await SettingsViewModel.validateMarketDataKey(provider, apiKey: apiKey, appLanguage: settings.appLanguage)
    }

    private var refreshMarketDataLabel: String {
        guard isRefreshingPrices else {
            return settings.localized("Refresh Market Data")
        }
        if let progress = finance.marketRefreshProgress, progress.total > 0 {
            return settings.localized("Updating \(progress.done) of \(progress.total)")
        }
        return settings.localized("Refreshing Market Data")
    }

    private func refreshMarketPrices() async {
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }

        // SET-03: surface a Keychain read failure as an alert instead of silently refreshing keyless.
        do {
            let result = await finance.refreshMarketPrices(
                finnhubAPIKey: try currentStoredAPIKey(for: .finnhubAPIKey),
                coingeckoAPIKey: try currentStoredAPIKey(for: .coingeckoAPIKey),
                settings: settings
            )
            refreshMarketDataKeyStatus()
            settingsAlert = SettingsAlertState(
                title: result.localizedTitle(appLanguage: settings.appLanguage),
                message: result.localizedMessage(appLanguage: settings.appLanguage)
            )
        } catch {
            refreshMarketDataKeyStatus()
            settingsAlert = SettingsAlertState(
                title: settings.localized("Unable to Refresh Market Data"),
                message: SettingsView.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func refreshExchangeRates() async {
        await settings.refreshExchangeRatesAndRecalculate(finance: finance) { result in
            settingsAlert = SettingsAlertState(
                title: result.localizedTitle(appLanguage: settings.appLanguage),
                message: result.localizedMessage(appLanguage: settings.appLanguage)
            )
        }
    }

    // L26: resolve app-defined errors through their appLanguage-aware description so the alert BODY
    // matches the appLanguage-localized title, instead of the system-locale `errorDescription`.
    private static func errorMessage(_ error: Error, appLanguage: String?) -> String {
        if let error = error as? FinanceImportError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? CloudSyncError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? ExchangeRateError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? MarketDataError { return error.localizedDescription(appLanguage: appLanguage) }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct SettingsAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum MarketDataCredentialKind: String, Identifiable {
    case finnhub
    case coingecko

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .finnhub:
            "Finnhub API Key"
        case .coingecko:
            "CoinGecko API Key"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .finnhub:
            AppLocalization.string("Finnhub API Key", appLanguage: appLanguage)
        case .coingecko:
            AppLocalization.string("CoinGecko API Key", appLanguage: appLanguage)
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .finnhub:
            "Paste Finnhub API key"
        case .coingecko:
            "Paste CoinGecko API key"
        }
    }

    var keychainCredential: KeychainCredential {
        switch self {
        case .finnhub:
            .finnhubAPIKey
        case .coingecko:
            .coingeckoAPIKey
        }
    }

    var testAssetName: LocalizedStringKey {
        switch self {
        case .finnhub:
            "Apple (AAPL)"
        case .coingecko:
            "Bitcoin"
        }
    }
}

private struct MarketDataCredentialEditor: View {
    let credential: MarketDataCredentialKind
    let appLanguage: String?
    @Binding var apiKey: String
    @Binding var alert: SettingsAlertState?
    let isConfigured: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void
    @State private var showingRemoveConfirmation = false

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(credential.title) {
                    SecureField(credential.placeholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .privacySensitive()

                    Text("The key is saved only after \(credential.testAssetName) returns a live USD price.")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)

                    if isSaving {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Retrieving \(credential.testAssetName) price...")
                                .foregroundStyle(WCColor.textSecondary)
                        }
                    }
                }

                // SET-01: allow clearing a stored key (parity with the macOS "Remove Key"). Only
                // shown when a key is actually configured; confirmed before deleting from Keychain.
                if isConfigured {
                    Section {
                        Button("Remove Key", role: .destructive) {
                            showingRemoveConfirmation = true
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(credential.title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify & Save", action: onSave)
                        .disabled(!canSave)
                }
            }
            .alert(item: $alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Remove \(credential.localizedTitle(appLanguage: appLanguage))?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Key", role: .destructive, action: onRemove)
            } message: {
                Text("The stored credential will be deleted from Keychain.")
            }
        }
    }
}

private enum SettingsDestructiveAction: Identifiable {
    case deleteAllData
    case deleteCustomCategory(category: String, type: TransactionType)

    var id: String {
        switch self {
        case .deleteAllData:
            "delete-all-data"
        case .deleteCustomCategory(let category, let type):
            "delete-category-\(type.rawValue)-\(category.lowercased())"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .deleteAllData:
            "Erase Everything?"
        case .deleteCustomCategory:
            "Delete Custom Category?"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Erase Everything?", appLanguage: appLanguage)
        case .deleteCustomCategory:
            AppLocalization.string("Delete Custom Category?", appLanguage: appLanguage)
        }
    }

    func message(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("This permanently deletes all finance data on this device and the copy in iCloud, your Finnhub and CoinGecko API keys, and every preference — returning the app to onboarding. Other devices signed in to the same iCloud account keep their own copy and may restore it to iCloud until you erase it there too. This cannot be undone. Prepare a backup first if you might need this data.", appLanguage: appLanguage)
        case .deleteCustomCategory(let category, let type):
            AppLocalization.string("This removes \(category) from your custom \(type.localizedTitle(appLanguage: appLanguage)) categories. Existing transactions using this category will keep their current label.", appLanguage: appLanguage)
        }
    }

    func localizedConfirmButtonTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Erase Everything", appLanguage: appLanguage)
        case .deleteCustomCategory:
            AppLocalization.string("Delete Category", appLanguage: appLanguage)
        }
    }
}
