import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum MacSettingsTab: MacSelectorTab {
    case general
    case data
    case icloud

    var title: String {
        switch self {
        case .general: return "General"
        case .data: return "Data"
        case .icloud: return "iCloud"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            
            FinanceCard {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 20)
            content
        }
        .padding(.vertical, 4)
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: MacAppLockStore
    @State private var importMode: FinanceImportMode = .merge
    @State private var selectedTab: MacSettingsTab = .general
    
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
        VStack(spacing: 0) {
            HStack {
                Spacer()
                MacSelectorIsland(selection: $selectedTab)
                Spacer()
            }
            .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .data:
                        dataSettings
                    case .icloud:
                        syncSettings
                    }
                }
                .padding(32)
                .frame(maxWidth: 1200, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Settings")
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
        DynamicMasonryLayout(minColumnWidth: 380, spacing: 32) {
            SettingsSection(title: "Region & Language") {
                SettingsRow(title: "Language") {
                    Picker("", selection: $settings.appLanguage) {
                        Text("System").tag(String?.none)
                        ForEach(settings.availableLanguages, id: \.self) { code in
                            Text(settings.languageName(for: code)).tag(String?.some(code))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                Divider().background(WCColor.border)

                SettingsRow(title: "Base Currency") {
                    Picker("", selection: $settings.currency) {
                        ForEach(Currency.allCases) { currency in
                            Text("\(currency.displayName) (\(currency.rawValue))").tag(currency)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            exchangeRatesSection

            SettingsSection(title: "Privacy & Security") {
                SettingsRow(title: "Privacy Mode", subtitle: "Hide financial values throughout Wealth Compass.") {
                    Toggle("", isOn: $settings.isPrivacyMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(WCColor.border)

                SettingsRow(
                    title: "\(appLock.biometryName) App Lock", 
                    subtitle: appLock.lastError ?? "When enabled, Wealth Compass locks when the app is no longer active."
                ) {
                    Toggle("", isOn: biometricLockBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsSection(title: "Custom Categories") {
                categoryGroup(
                    title: "Income",
                    type: .income,
                    categories: settings.customIncomeCategories
                )
                
                Divider().background(WCColor.border)
                
                categoryGroup(
                    title: "Expense",
                    type: .expense,
                    categories: settings.customExpenseCategories
                )
            }

            marketDataSection
        }
    }

    private var exchangeRatesSection: some View {
        SettingsSection(title: "Exchange Rates") {
            SettingsRow(title: "Source") {
                if let snapshot = settings.exchangeRateSnapshot {
                    VStack(alignment: .trailing) {
                        Text("ECB")
                            .foregroundStyle(.primary)
                        Text(snapshot.effectiveDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Offline fallback")
                        .foregroundStyle(.orange)
                }
            }

            Divider().background(WCColor.border)

            ForEach(Currency.allCases.filter { $0 != settings.currency }) { quoteCurrency in
                let converted = settings.convert(1, from: settings.currency, to: quoteCurrency)
                SettingsRow(title: "1 \(settings.currency.rawValue)") {
                    Text("\(converted.formatted(.number.precision(.fractionLength(2...4)))) \(quoteCurrency.rawValue)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Divider().background(WCColor.border)
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
            .padding(.top, 8)

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
        SettingsSection(title: "Market Data") {
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

            Divider().background(WCColor.border)

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

            Divider().background(WCColor.border)

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
            .padding(.top, 8)

            Text("API keys are verified against a live quote before they are stored in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSettings: some View {
        DynamicMasonryLayout(minColumnWidth: 380, spacing: 32) {
            SettingsSection(title: "Import and Export") {
                SettingsRow(title: "Import Behavior") {
                    Picker("", selection: $importMode) {
                        Text("Merge with local data").tag(FinanceImportMode.merge)
                        Text("Replace local data").tag(FinanceImportMode.replace)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                Divider().background(WCColor.border)

                HStack(spacing: 16) {
                    Button("Import JSON...", action: importBackup)
                    Button("Export JSON...", action: exportBackup)
                }
                .padding(.top, 8)
            }

            SettingsSection(title: "Local Storage") {
                SettingsRow(title: "Mode") { Text("Local Only").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Transactions") { Text("\(finance.data.transactions.count)").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Recurring Schedules") { Text("\(finance.data.recurringTransactions.count)").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Investments") { Text("\(finance.data.investments.count)").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Crypto Holdings") { Text("\(finance.data.crypto.count)").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Liabilities") { Text("\(finance.data.liabilities.count)").foregroundStyle(.secondary) }
                Divider().background(WCColor.border)
                SettingsRow(title: "Snapshots") { Text("\(finance.data.snapshots.count)").foregroundStyle(.secondary) }

                Divider().background(WCColor.border)

                Text(finance.storageLocationDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }

            SettingsSection(title: "Danger Zone") {
                Button("Delete All Local Data...", role: .destructive) {
                    pendingDestructiveAction = .deleteAllData
                }
            }
        }
    }

    private var syncSettings: some View {
        DynamicMasonryLayout(minColumnWidth: 380, spacing: 32) {
            SettingsSection(title: "iCloud Sync") {
                SettingsRow(
                    title: "Sync Data with iCloud",
                    subtitle: "Your financial data stays available locally and syncs across your devices through your private CloudKit database."
                ) {
                    Toggle("", isOn: $settings.isICloudSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: settings.isICloudSyncEnabled) { _, isEnabled in
                            Task {
                                await finance.setICloudSyncEnabled(isEnabled)
                            }
                        }
                }

                Divider().background(WCColor.border)

                SettingsRow(title: "Status") {
                    Text(finance.cloudSyncStatus.title)
                        .foregroundStyle(finance.iCloudSyncError == nil ? .secondary : WCColor.destructive)
                }

                if let detail = finance.cloudSyncStatus.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(finance.iCloudSyncError == nil ? .secondary : WCColor.destructive)
                }
            }
            
            if settings.isICloudSyncEnabled {
                SettingsSection(title: "Manual Actions") {
                    Button {
                        Task {
                            do {
                                try await finance.forceICloudSync()
                            } catch {
                                settingsAlert = MacSettingsAlert(
                                    title: "Sync Failed",
                                    message: error.localizedDescription
                                )
                            }
                        }
                    } label: {
                        Label("Force Sync iCloud", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    .disabled(finance.cloudSyncStatus.isBusy)
                }
            }
        }
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
