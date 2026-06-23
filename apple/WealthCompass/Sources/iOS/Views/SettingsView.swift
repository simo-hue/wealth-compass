import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var backupURL: URL?
    @State private var backupError: String?
    @State private var importMode: FinanceImportMode = .merge
    @State private var showingImportOptions = false
    @State private var showingFileImporter = false
    @State private var importSummary: FinanceImportResult?
    @State private var settingsAlert: SettingsAlertState?
    @State private var credentialEditorAlert: SettingsAlertState?
    @State private var activeCredentialEditor: MarketDataCredentialKind?
    @State private var credentialDraft = ""
    @State private var hasFinnhubAPIKey = false
    @State private var hasCoinGeckoAPIKey = false
    @State private var isSavingMarketDataCredential = false
    @State private var isRefreshingPrices = false
    @State private var pendingDestructiveAction: SettingsDestructiveAction?

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

                    LabeledContent("Status", value: finance.cloudSyncStatus.localizedTitle(appLanguage: settings.appLanguage))
                    if let detail = finance.cloudSyncStatus.localizedDetail(appLanguage: settings.appLanguage) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(
                                finance.iCloudSyncError == nil ? WCColor.textSecondary : WCColor.destructive
                            )
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
                        do {
                            backupURL = try finance.exportBackupURL()
                            backupError = nil
                        } catch {
                            backupError = error.localizedDescription
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

                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteAllData
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
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
                    apiKey: $credentialDraft,
                    alert: $credentialEditorAlert,
                    isSaving: isSavingMarketDataCredential,
                    onCancel: {
                        credentialDraft = ""
                        credentialEditorAlert = nil
                        activeCredentialEditor = nil
                    },
                    onSave: {
                        Task { await saveAndTestMarketDataCredential(credential) }
                    }
                )
            }
            .sheet(item: $importSummary) { summary in
                ImportSummaryView(result: summary, appLanguage: settings.appLanguage) {
                    importSummary = nil
                }
                .presentationDetents([.medium, .large])
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
                let converted = settings.convert(1, from: settings.currency, to: quoteCurrency)
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
        }
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
                appLock.disableLock()
            }
        }
    }

    private func categoryGroup(title: String, type: TransactionType, categories: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if categories.isEmpty {
                Text("No custom \(title.lowercased()) categories yet.")
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
            finance.clearData()
            backupURL = nil
            Task {
                await RecurringTransactionNotificationService.shared.cancelAll()
            }
        case .deleteCustomCategory(let category, let type):
            settings.removeCustomTransactionCategory(category, for: type)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let result = try finance.importBackup(from: url, mode: importMode, settings: settings)
                backupURL = nil
                backupError = nil
                importSummary = result
            } catch {
                settingsAlert = SettingsAlertState(
                    title: settings.localized("Import Failed"),
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        case .failure(let error):
            settingsAlert = SettingsAlertState(
                title: settings.localized("Import Failed"),
                message: error.localizedDescription
            )
        }
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

    private func currentStoredAPIKey(for credential: KeychainCredential) -> String {
        do {
            return (try KeychainCredentialStore.shared.string(for: credential) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
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
                message: SettingsView.errorMessage(error)
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

        let currentKey = currentStoredAPIKey(for: .finnhubAPIKey)
        let finnhubKey = currentKey.isEmpty ? nil : currentKey
        let currentCoinGeckoKey = currentStoredAPIKey(for: .coingeckoAPIKey)
        let coingeckoKey = currentCoinGeckoKey.isEmpty ? nil : currentCoinGeckoKey
        let result = await finance.refreshMarketPrices(
            finnhubAPIKey: finnhubKey,
            coingeckoAPIKey: coingeckoKey,
            settings: settings
        )
        refreshMarketDataKeyStatus()
        settingsAlert = SettingsAlertState(
            title: result.localizedTitle(appLanguage: settings.appLanguage),
            message: result.localizedMessage(appLanguage: settings.appLanguage)
        )
    }

    private func refreshExchangeRates() async {
        await settings.refreshExchangeRatesAndRecalculate(finance: finance) { result in
            settingsAlert = SettingsAlertState(
                title: result.localizedTitle(appLanguage: settings.appLanguage),
                message: result.localizedMessage(appLanguage: settings.appLanguage)
            )
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
    @Binding var apiKey: String
    @Binding var alert: SettingsAlertState?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

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
            "Delete All Data?"
        case .deleteCustomCategory:
            "Delete Custom Category?"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Delete All Data?", appLanguage: appLanguage)
        case .deleteCustomCategory:
            AppLocalization.string("Delete Custom Category?", appLanguage: appLanguage)
        }
    }

    func message(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("This permanently removes all local Wealth Compass data from this device.", appLanguage: appLanguage)
        case .deleteCustomCategory(let category, let type):
            AppLocalization.string("This removes \(category) from your custom \(type.localizedTitle(appLanguage: appLanguage)) categories. Existing transactions using this category will keep their current label.", appLanguage: appLanguage)
        }
    }

    func localizedConfirmButtonTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Delete", appLanguage: appLanguage)
        case .deleteCustomCategory:
            AppLocalization.string("Delete Category", appLanguage: appLanguage)
        }
    }
}
