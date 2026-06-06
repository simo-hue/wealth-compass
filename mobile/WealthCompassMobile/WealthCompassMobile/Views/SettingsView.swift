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
                Section("Currency") {
                    Picker("Base Currency", selection: $settings.currency) {
                        ForEach(Currency.allCases) { currency in
                            Text("\(currency.displayName) (\(currency.rawValue))").tag(currency)
                        }
                    }
                }

                exchangeRatesSection

                Section("Privacy") {
                    Toggle(isOn: $settings.isPrivacyMode) {
                        Label("Privacy Mode", systemImage: settings.isPrivacyMode ? "eye.slash" : "eye")
                    }
                    .tint(WCColor.primary)
                }

                Section("Security") {
                    Toggle(isOn: biometricLockBinding) {
                        Label("\(appLock.biometryName) App Lock", systemImage: "lock.shield")
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
            }
            .navigationTitle("Settings")
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
            .alert(item: $settingsAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(item: $pendingDestructiveAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmButtonTitle)) {
                        performDestructiveAction(action)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
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
                    settings.isRefreshingExchangeRates ? "Refreshing Exchange Rates" : "Refresh Exchange Rates",
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
                Label(isRefreshingPrices ? "Refreshing Market Data" : "Refresh Market Data", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRefreshingPrices || (finance.data.investments.isEmpty && finance.data.crypto.isEmpty))
        }
    }

    private func credentialRow(title: String, systemImage: String, isConfigured: Bool) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.white)
            Spacer()
            Text(isConfigured ? "Configured" : "Not Set")
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
                Task { await appLock.enableLock() }
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
                settingsAlert = SettingsAlertState(title: "Import Complete", message: result.message)
            } catch {
                settingsAlert = SettingsAlertState(
                    title: "Import Failed",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        case .failure(let error):
            settingsAlert = SettingsAlertState(title: "Import Failed", message: error.localizedDescription)
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
                title: "\(credential.title) Saved",
                message: "\(message)\n\nThe API key was saved securely in Keychain."
            )
        } catch {
            credentialEditorAlert = SettingsAlertState(
                title: "\(credential.title) Failed",
                message: SettingsView.errorMessage(error)
            )
        }
    }

    private func validationMessage(for credential: MarketDataCredentialKind, apiKey: String) async throws -> String {
        switch credential {
        case .finnhub:
            let quote = try await FinnhubQuoteClient(apiKey: apiKey).testConnection()
            return "Finnhub returned a live AAPL quote at \(quote.price.formatted(.currency(code: Currency.usd.rawValue)))."
        case .coingecko:
            let quote = try await CoinGeckoPriceClient(apiKey: apiKey).testConnection()
            return "CoinGecko returned a live Bitcoin price at \(quote.price.formatted(.currency(code: Currency.usd.rawValue)))."
        }
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
        settingsAlert = SettingsAlertState(title: result.title, message: result.message)
    }

    private func refreshExchangeRates() async {
        let result = await settings.refreshExchangeRates()
        if result.didChangeRates, finance.hasForeignCurrencyExposure(relativeTo: settings.currency) {
            finance.takeSnapshot(settings: settings)
        }
        settingsAlert = SettingsAlertState(title: result.title, message: result.message)
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

    var title: String {
        switch self {
        case .finnhub:
            "Finnhub API Key"
        case .coingecko:
            "CoinGecko API Key"
        }
    }

    var placeholder: String {
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

    var testAssetName: String {
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

    var title: String {
        switch self {
        case .deleteAllData:
            "Delete All Data?"
        case .deleteCustomCategory:
            "Delete Custom Category?"
        }
    }

    var message: String {
        switch self {
        case .deleteAllData:
            "This permanently removes all local Wealth Compass data from this device."
        case .deleteCustomCategory(let category, let type):
            "This removes \(category) from your custom \(type.title.lowercased()) categories. Existing transactions using this category will keep their current label."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .deleteAllData:
            "Delete"
        case .deleteCustomCategory:
            "Delete Category"
        }
    }
}
