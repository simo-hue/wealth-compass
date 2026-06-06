import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: MacAppLockStore
    @State private var importMode: FinanceImportMode = .merge
    @State private var settingsAlert: MacSettingsAlert?
    @State private var credentialEditorAlert: MacSettingsAlert?
    @State private var activeCredentialEditor: MacMarketDataCredentialKind?
    @State private var credentialDraft = ""
    @State private var hasFinnhubAPIKey = false
    @State private var hasCoinGeckoAPIKey = false
    @State private var isSavingMarketDataCredential = false
    @State private var isRefreshingPrices = false
    @State private var pendingDestructiveAction: MacSettingsDestructiveAction?

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }

            dataSettings
                .tabItem { Label("Data", systemImage: "internaldrive") }

            syncSettings
                .tabItem { Label("iCloud", systemImage: "icloud") }
        }
        .frame(width: 780, height: 700)
        .onAppear(perform: refreshMarketDataKeyStatus)
        .sheet(item: $activeCredentialEditor) { credential in
            MacMarketDataCredentialEditor(
                credential: credential,
                apiKey: $credentialDraft,
                alert: $credentialEditorAlert,
                isConfigured: isCredentialConfigured(credential),
                isSaving: isSavingMarketDataCredential,
                onCancel: closeCredentialEditor,
                onSave: {
                    Task { await saveAndTestMarketDataCredential(credential) }
                },
                onRemove: {
                    removeMarketDataCredential(credential)
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
        .confirmationDialog(
            pendingDestructiveAction?.title ?? "",
            isPresented: destructiveActionPresented,
            presenting: pendingDestructiveAction
        ) { action in
            Button(action.confirmButtonTitle, role: .destructive) {
                performDestructiveAction(action)
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Currency") {
                Picker("Base Currency", selection: $settings.currency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.displayName) (\(currency.rawValue))").tag(currency)
                    }
                }
            }

            exchangeRatesSection

            Section("Privacy") {
                Toggle("Privacy Mode", isOn: $settings.isPrivacyMode)

                Text("Hide financial values throughout Wealth Compass.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Security") {
                Toggle("\(appLock.biometryName) App Lock", isOn: biometricLockBinding)

                if let error = appLock.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("When enabled, Wealth Compass locks when the app is no longer active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Custom Categories") {
                categoryGroup(
                    title: "Income",
                    type: .income,
                    categories: settings.customIncomeCategories
                )
                categoryGroup(
                    title: "Expense",
                    type: .expense,
                    categories: settings.customExpenseCategories
                )
            }

            marketDataSection
        }
        .formStyle(.grouped)
        .padding()
    }

    private var exchangeRatesSection: some View {
        Section("Exchange Rates") {
            LabeledContent("Source") {
                if let snapshot = settings.exchangeRateSnapshot {
                    Text("ECB")
                    Text("· \(snapshot.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Offline fallback")
                        .foregroundStyle(.orange)
                }
            }

            ForEach(Currency.allCases.filter { $0 != settings.currency }) { quoteCurrency in
                let converted = settings.convert(1, from: settings.currency, to: quoteCurrency)
                LabeledContent("1 \(settings.currency.rawValue)") {
                    Text("\(converted.formatted(.number.precision(.fractionLength(2...4)))) \(quoteCurrency.rawValue)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
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
                        .controlSize(.small)
                }
            }

            if let error = settings.exchangeRateError {
                Text("\(error) Cached or fallback rates remain active.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let snapshot = settings.exchangeRateSnapshot {
                Text("\(snapshot.provider). Fetched \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)) and cached locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("ECB reference rates are refreshed automatically and cached locally for offline use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            HStack {
                Button {
                    Task { await refreshMarketPrices() }
                } label: {
                    Label(
                        isRefreshingPrices ? "Refreshing Market Data" : "Refresh Market Data",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(
                    isRefreshingPrices
                        || (finance.data.investments.isEmpty && finance.data.crypto.isEmpty)
                )

                if isRefreshingPrices {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("API keys are verified against a live quote before they are stored in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSettings: some View {
        Form {
            Section("Import and Export") {
                Picker("Import Behavior", selection: $importMode) {
                    Text("Merge with local data").tag(FinanceImportMode.merge)
                    Text("Replace local data").tag(FinanceImportMode.replace)
                }

                HStack {
                    Button("Import JSON...", action: importBackup)
                    Button("Export JSON...", action: exportBackup)
                }
            }

            Section("Local Storage") {
                LabeledContent("Mode", value: "Local Only")
                LabeledContent("Transactions", value: "\(finance.data.transactions.count)")
                LabeledContent("Recurring Schedules", value: "\(finance.data.recurringTransactions.count)")
                LabeledContent("Investments", value: "\(finance.data.investments.count)")
                LabeledContent("Crypto Holdings", value: "\(finance.data.crypto.count)")
                LabeledContent("Liabilities", value: "\(finance.data.liabilities.count)")
                LabeledContent("Snapshots", value: "\(finance.data.snapshots.count)")

                Text(finance.storageLocationDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Button("Delete All Local Data...", role: .destructive) {
                    pendingDestructiveAction = .deleteAllData
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var syncSettings: some View {
        Form {
            Section("Status") {
                LabeledContent("iCloud Sync", value: "Not Configured")
                LabeledContent("Local Database", value: "Active")
            }

            Section("Planned Architecture") {
                Text(
                    "The app now stores data behind a shared persistence interface. "
                        + "CloudKit sync can be added without changing the iPhone or Mac interfaces."
                )
                Text(
                    "The production sync layer should use one CloudKit record per transaction, "
                        + "holding, liability, recurring schedule, and snapshot so edits can merge safely."
                )
            }

            Section {
                Text("An iCloud container and App Store provisioning profile are required before sync can be enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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

    private var destructiveActionPresented: Binding<Bool> {
        Binding {
            pendingDestructiveAction != nil
        } set: { isPresented in
            if !isPresented {
                pendingDestructiveAction = nil
            }
        }
    }

    private func categoryGroup(
        title: String,
        type: TransactionType,
        categories: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if categories.isEmpty {
                Text("No custom \(title.lowercased()) categories yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categories, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        Button(role: .destructive) {
                            pendingDestructiveAction = .deleteCustomCategory(
                                category: category,
                                type: type
                            )
                        } label: {
                            Label("Remove \(category)", systemImage: "minus.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(category)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func credentialRow(
        title: String,
        systemImage: String,
        isConfigured: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(isConfigured ? "Configured" : "Not Set")
                .foregroundStyle(isConfigured ? Color.accentColor : .secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func refreshMarketDataKeyStatus() {
        hasFinnhubAPIKey = KeychainCredentialStore.shared.contains(.finnhubAPIKey)
        hasCoinGeckoAPIKey = KeychainCredentialStore.shared.contains(.coingeckoAPIKey)
    }

    private func isCredentialConfigured(_ credential: MacMarketDataCredentialKind) -> Bool {
        switch credential {
        case .finnhub:
            hasFinnhubAPIKey
        case .coingecko:
            hasCoinGeckoAPIKey
        }
    }

    private func openCredentialEditor(_ credential: MacMarketDataCredentialKind) {
        credentialDraft = ""
        credentialEditorAlert = nil
        activeCredentialEditor = credential
    }

    private func closeCredentialEditor() {
        credentialDraft = ""
        credentialEditorAlert = nil
        activeCredentialEditor = nil
    }

    private func saveAndTestMarketDataCredential(
        _ credential: MacMarketDataCredentialKind
    ) async {
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
            settingsAlert = MacSettingsAlert(
                title: "\(credential.title) Saved",
                message: "\(message)\n\nThe API key was saved securely in Keychain."
            )
        } catch {
            credentialEditorAlert = MacSettingsAlert(
                title: "\(credential.title) Failed",
                message: Self.errorMessage(error)
            )
        }
    }

    private func validationMessage(
        for credential: MacMarketDataCredentialKind,
        apiKey: String
    ) async throws -> String {
        switch credential {
        case .finnhub:
            let quote = try await FinnhubQuoteClient(apiKey: apiKey).testConnection()
            return "Finnhub returned a live AAPL quote at \(quote.price.formatted(.currency(code: Currency.usd.rawValue)))."
        case .coingecko:
            let quote = try await CoinGeckoPriceClient(apiKey: apiKey).testConnection()
            return "CoinGecko returned a live Bitcoin price at \(quote.price.formatted(.currency(code: Currency.usd.rawValue)))."
        }
    }

    private func removeMarketDataCredential(_ credential: MacMarketDataCredentialKind) {
        do {
            try KeychainCredentialStore.shared.delete(credential.keychainCredential)
            closeCredentialEditor()
            refreshMarketDataKeyStatus()
            settingsAlert = MacSettingsAlert(
                title: "\(credential.title) Removed",
                message: "The API key was removed from the macOS Keychain."
            )
        } catch {
            credentialEditorAlert = MacSettingsAlert(
                title: "Unable to Remove \(credential.title)",
                message: Self.errorMessage(error)
            )
        }
    }

    private func storedAPIKey(for credential: KeychainCredential) throws -> String? {
        let value = try KeychainCredentialStore.shared.string(for: credential)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func refreshMarketPrices() async {
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }

        do {
            let result = await finance.refreshMarketPrices(
                finnhubAPIKey: try storedAPIKey(for: .finnhubAPIKey),
                coingeckoAPIKey: try storedAPIKey(for: .coingeckoAPIKey),
                settings: settings
            )
            refreshMarketDataKeyStatus()
            settingsAlert = MacSettingsAlert(title: result.title, message: result.message)
        } catch {
            refreshMarketDataKeyStatus()
            settingsAlert = MacSettingsAlert(
                title: "Unable to Refresh Market Data",
                message: Self.errorMessage(error)
            )
        }
    }

    private func refreshExchangeRates() async {
        let result = await settings.refreshExchangeRates()
        if result.didChangeRates,
           finance.hasForeignCurrencyExposure(relativeTo: settings.currency) {
            finance.takeSnapshot(settings: settings)
        }
        settingsAlert = MacSettingsAlert(title: result.title, message: result.message)
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try finance.importBackup(from: url, mode: importMode, settings: settings)
            let insertedCount = finance.processDueRecurringTransactions(settings: settings)

            Task {
                await syncRecurringNotifications()

                var message = result.message
                if insertedCount > 0 {
                    let transactionWord = insertedCount == 1 ? "transaction was" : "transactions were"
                    message += "\n\n\(insertedCount) due recurring \(transactionWord) added to Cash Flow."
                }
                settingsAlert = MacSettingsAlert(title: "Import Complete", message: message)
            }
        } catch {
            settingsAlert = MacSettingsAlert(
                title: "Import Failed",
                message: Self.errorMessage(error)
            )
        }
    }

    private func exportBackup() {
        do {
            let temporaryURL = try finance.exportBackupURL()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = temporaryURL.lastPathComponent

            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
            settingsAlert = MacSettingsAlert(
                title: "Backup Exported",
                message: destination.path
            )
        } catch {
            settingsAlert = MacSettingsAlert(
                title: "Export Failed",
                message: Self.errorMessage(error)
            )
        }
    }

    private func performDestructiveAction(_ action: MacSettingsDestructiveAction) {
        switch action {
        case .deleteAllData:
            finance.clearData()
            Task {
                await MacRecurringTransactionNotificationService.shared.cancelAll()
            }
        case .deleteCustomCategory(let category, let type):
            settings.removeCustomTransactionCategory(category, for: type)
        }
        pendingDestructiveAction = nil
    }

    private func syncRecurringNotifications() async {
        await MacRecurringTransactionNotificationService.shared.sync(
            schedules: finance.data.recurringTransactions,
            currencyCode: settings.currency.rawValue,
            showAmounts: !settings.isPrivacyMode
        )
    }

    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct MacSettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum MacMarketDataCredentialKind: String, Identifiable {
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

private enum MacSettingsDestructiveAction {
    case deleteAllData
    case deleteCustomCategory(category: String, type: TransactionType)

    var title: String {
        switch self {
        case .deleteAllData:
            "Delete all local finance data?"
        case .deleteCustomCategory:
            "Remove custom category?"
        }
    }

    var message: String {
        switch self {
        case .deleteAllData:
            "This permanently removes the local Mac database and its scheduled notifications. This action cannot be undone."
        case .deleteCustomCategory(let category, _):
            "Existing transactions using \(category) will keep their current category label."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .deleteAllData:
            "Delete All Data"
        case .deleteCustomCategory(let category, _):
            "Remove \(category)"
        }
    }
}

private struct MacMarketDataCredentialEditor: View {
    let credential: MacMarketDataCredentialKind
    @Binding var apiKey: String
    @Binding var alert: MacSettingsAlert?
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
        VStack(spacing: 0) {
            Form {
                Section(credential.title) {
                    SecureField(credential.placeholder, text: $apiKey)
                        .textContentType(.password)
                        .privacySensitive()

                    Text("The key is saved only after \(credential.testAssetName) returns a live USD price.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isSaving {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Retrieving \(credential.testAssetName) price...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Remove Key", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .disabled(!isConfigured || isSaving)

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)

                Button("Verify & Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 520, height: 270)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Remove \(credential.title)?",
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove Key", role: .destructive, action: onRemove)
        } message: {
            Text("The stored credential will be deleted from the macOS Keychain.")
        }
    }
}
