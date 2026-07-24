import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum MacSettingsTab: MacSelectorTab {
    case general
    case data
    case icloud

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .data: return "Data"
        case .icloud: return "iCloud"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = LocalizedStringKey(title)
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
    let titleKey: LocalizedStringKey?
    let titleString: String?
    let subtitleKey: LocalizedStringKey?
    let subtitleString: String?
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.titleKey = title
        self.titleString = nil
        self.subtitleKey = subtitle
        self.subtitleString = nil
        self.content = content()
    }

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        // WC-H2: string literals bind to this `String` overload, and the old body rendered
        // them through the verbatim `Text(_: String)` initializer — so the whole Settings
        // screen ignored the in-app language. Wrap into `LocalizedStringKey` (as
        // `SettingsSection` already does) so literals localize. Already-resolved strings
        // (e.g. `settings.localized(...)`) are dynamic and won't collide with catalog keys,
        // so they pass through unchanged.
        self.titleKey = LocalizedStringKey(title)
        self.titleString = nil
        self.subtitleKey = subtitle.map { LocalizedStringKey($0) }
        self.subtitleString = nil
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                if let titleKey {
                    Text(titleKey)
                        .font(.body)
                } else if let titleString {
                    Text(titleString)
                        .font(.body)
                }
                if let subtitleKey {
                    Text(subtitleKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let subtitleString {
                    Text(subtitleString)
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

    @State private var importSummary: FinanceImportResult?
    @State private var importSummaryNote: String?
    @State private var settingsAlert: MacSettingsAlert?
    @State private var credentialEditorAlert: MacSettingsAlert?
    @State private var activeCredentialEditor: MacMarketDataCredentialKind?
    @State private var credentialDraft = ""
    @State private var hasFinnhubAPIKey = false
    @State private var hasCoinGeckoAPIKey = false
    @State private var isSavingMarketDataCredential = false
    @State private var isRefreshingPrices = false
    @State private var pendingDestructiveAction: MacSettingsDestructiveAction?
    @State private var showingEraseFailure = false
    @State private var eraseFailureMessage = ""
    @State private var isErasing = false

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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(ScreenBackground())
        // navigationTitle centralized in MacRootView (collapse-aware).
        .onAppear(perform: refreshMarketDataKeyStatus)
        .sheet(item: $activeCredentialEditor) { credential in
            MacMarketDataCredentialEditor(
                credential: credential,
                appLanguage: settings.appLanguage,
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
        .sheet(item: $importSummary) { summary in
            ImportSummaryView(
                result: summary,
                appLanguage: settings.appLanguage,
                additionalNote: importSummaryNote
            ) {
                importSummary = nil
                importSummaryNote = nil
            }
            .frame(width: 460, height: 580)
        }
        .alert(item: $settingsAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            pendingDestructiveAction?.localizedTitle(appLanguage: settings.appLanguage) ?? "",
            isPresented: destructiveActionPresented,
            presenting: pendingDestructiveAction
        ) { action in
            Button(action.localizedConfirmButtonTitle(appLanguage: settings.appLanguage), role: .destructive) {
                performDestructiveAction(action)
            }
        } message: { action in
            Text(action.localizedMessage(appLanguage: settings.appLanguage))
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

    private var generalSettings: some View {
        DynamicMasonryLayout(minColumnWidth: 460, spacing: 32, maxColumns: 3) {
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
                            (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            exchangeRatesSection

            SettingsSection(title: "Privacy & Security") {
                SettingsRow(title: "Privacy Mode", subtitle: "Hide financial values throughout Wealth Compass Tracker.") {
                    Toggle("", isOn: $settings.isPrivacyMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(WCColor.border)

                SettingsRow(
                    title: settings.localized("\(appLock.biometryName(appLanguage: settings.appLanguage)) App Lock"),
                    subtitle: appLock.lastError ?? settings.localized("When enabled, Wealth Compass Tracker locks when the app is no longer active.")
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
                let converted: Double = settings.convert(1, from: settings.currency, to: quoteCurrency)
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
                        settings.isRefreshingExchangeRates
                            ? settings.localized("Refreshing Exchange Rates")
                            : settings.localized("Refresh Exchange Rates"),
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

            // L40: warn when a held currency is missing from the fresh snapshot and converts via seed.
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
                        isRefreshingPrices
                            ? settings.localized("Refreshing Market Data")
                            : settings.localized("Refresh Market Data"),
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
        DynamicMasonryLayout(minColumnWidth: 460, spacing: 32, maxColumns: 3) {
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
                    Button("Import Data...", action: importData)
                    Button("Export JSON...", action: exportBackup)
                }
                .padding(.top, 8)

                Button("Export Sync Diagnostics...", action: exportSyncDiagnostics)
                    .padding(.top, 4)
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
                Button("Erase Everything...", role: .destructive) {
                    pendingDestructiveAction = .deleteAllData
                }
                .disabled(isErasing)
            }
        }
    }

    private var syncSettings: some View {
        DynamicMasonryLayout(minColumnWidth: 460, spacing: 32, maxColumns: 3) {
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

                Text("Preferences like currency, categories, and language are set per device and don't sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(WCColor.border)

                SettingsRow(title: "Status") {
                    Label {
                        // SET-04: resolve via appLanguage so the title honors the in-app language
                        // override (matches the detail line below and iOS), not the environment locale.
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
            }
            
            if settings.isICloudSyncEnabled {
                SettingsSection(title: "Manual Actions") {
                    Button {
                        Task {
                            do {
                                try await finance.forceICloudSync()
                            } catch {
                                let syncError = error as? CloudSyncError
                                settingsAlert = MacSettingsAlert(
                                    title: settings.localized(syncError?.alertTitleKey ?? "Sync Failed"),
                                    message: syncError?.localizedDescription(appLanguage: settings.appLanguage)
                                        ?? error.localizedDescription
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
                Task { await appLock.enableLock(appLanguage: settings.appLanguage) }
            } else {
                // WC-L3: require auth to turn the lock off (passcode fallback via WC-L2).
                Task { await appLock.confirmDisableLock(appLanguage: settings.appLanguage) }
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
        title: LocalizedStringKey,
        type: TransactionType,
        categories: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if categories.isEmpty {
                Text(settings.localized("No custom \(type.localizedTitle(appLanguage: settings.appLanguage).lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))) categories yet."))
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
        title: LocalizedStringKey,
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
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Saved"),
                message: settings.localized("\(message)\n\nThe API key was saved securely in Keychain.")
            )
        } catch {
            credentialEditorAlert = MacSettingsAlert(
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Failed"),
                message: Self.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func validationMessage(
        for credential: MacMarketDataCredentialKind,
        apiKey: String
    ) async throws -> String {
        let provider: SettingsViewModel.MarketDataProvider
        switch credential {
        case .finnhub: provider = .finnhub
        case .coingecko: provider = .coingecko
        }
        return try await SettingsViewModel.validateMarketDataKey(provider, apiKey: apiKey, appLanguage: settings.appLanguage)
    }

    private func removeMarketDataCredential(_ credential: MacMarketDataCredentialKind) {
        do {
            try KeychainCredentialStore.shared.delete(credential.keychainCredential)
            closeCredentialEditor()
            refreshMarketDataKeyStatus()
            settingsAlert = MacSettingsAlert(
                title: settings.localized("\(credential.localizedTitle(appLanguage: settings.appLanguage)) Removed"),
                message: settings.localized("The API key was removed from the macOS Keychain.")
            )
        } catch {
            credentialEditorAlert = MacSettingsAlert(
                title: settings.localized("Unable to Remove \(credential.localizedTitle(appLanguage: settings.appLanguage))"),
                message: Self.errorMessage(error, appLanguage: settings.appLanguage)
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
            settingsAlert = MacSettingsAlert(
                title: result.localizedTitle(appLanguage: settings.appLanguage),
                message: result.localizedMessage(appLanguage: settings.appLanguage)
            )
        } catch {
            refreshMarketDataKeyStatus()
            settingsAlert = MacSettingsAlert(
                title: settings.localized("Unable to Refresh Market Data"),
                message: Self.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func refreshExchangeRates() async {
        await settings.refreshExchangeRatesAndRecalculate(finance: finance) { result in
            settingsAlert = MacSettingsAlert(
                title: result.localizedTitle(appLanguage: settings.appLanguage),
                message: result.localizedMessage(appLanguage: settings.appLanguage)
            )
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText, .plainText, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // L55: import is async (detects + parses off the MainActor). The open panel above stays on the
        // main thread; the async import + summary run in a Task.
        Task {
            do {
                let result = try await finance.importFile(from: url, mode: importMode, settings: settings)
                let insertedCount = finance.processDueRecurringTransactions(settings: settings)
                await syncRecurringNotifications()

                // Reuse the existing localized lines (trimmed of their paragraph spacing)
                // as the summary's extra footnote so we don't add new strings.
                if insertedCount == 1 {
                    importSummaryNote = settings.localized("\n\n1 due recurring transaction was added to Cash Flow.")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if insertedCount > 1 {
                    importSummaryNote = settings.localized("\n\n\(insertedCount) due recurring transactions were added to Cash Flow.")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    importSummaryNote = nil
                }
                importSummary = result
            } catch {
                settingsAlert = MacSettingsAlert(
                    title: settings.localized("Import Failed"),
                    message: Self.errorMessage(error, appLanguage: settings.appLanguage)
                )
            }
        }
    }

    private func exportBackup() {
        // L55: exportBackupURL is now async (encodes off the MainActor). The save panel + the small
        // temp→destination copy run on the main thread inside the Task.
        Task {
            do {
                let temporaryURL = try await finance.exportBackupURL()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = temporaryURL.lastPathComponent

                guard panel.runModal() == .OK, let destination = panel.url else { return }
                try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
                settingsAlert = MacSettingsAlert(
                    title: settings.localized("Backup Exported"),
                    message: destination.path
                )
            } catch {
                settingsAlert = MacSettingsAlert(
                    title: settings.localized("Export Failed"),
                    message: Self.errorMessage(error, appLanguage: settings.appLanguage)
                )
            }
        }
    }

    private func exportSyncDiagnostics() {
        do {
            let temporaryURL = try finance.exportSyncDiagnosticsURL()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = temporaryURL.lastPathComponent

            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
            settingsAlert = MacSettingsAlert(
                title: settings.localized("Diagnostics Exported"),
                message: destination.path
            )
        } catch {
            settingsAlert = MacSettingsAlert(
                title: settings.localized("Export Failed"),
                message: Self.errorMessage(error, appLanguage: settings.appLanguage)
            )
        }
    }

    private func performDestructiveAction(_ action: MacSettingsDestructiveAction) {
        switch action {
        case .deleteAllData:
            Task { await performErase(deleteCloud: true) }
        case .deleteCustomCategory(let category, let type):
            settings.removeCustomTransactionCategory(category, for: type)
        }
        pendingDestructiveAction = nil
    }

    /// Runs the factory reset. On success the root view navigates to onboarding (via
    /// `hasSeenOnboarding`). If the iCloud deletion fails, we surface the Retry /
    /// "Delete this device only" dialog and keep the data intact.
    private func performErase(deleteCloud: Bool) async {
        isErasing = true
        defer { isErasing = false }
        do {
            try await finance.eraseEverything(deleteCloud: deleteCloud)
            appLock.disableLock()
            await MacRecurringTransactionNotificationService.shared.cancelAll()
        } catch {
            let syncError = error as? CloudSyncError
            eraseFailureMessage = syncError?.localizedDescription(appLanguage: settings.appLanguage)
                ?? error.localizedDescription
            showingEraseFailure = true
        }
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
            showAmounts: !settings.isPrivacyMode
        )
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

private struct MacSettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum MacMarketDataCredentialKind: String, Identifiable {
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

    func localizedPlaceholder(appLanguage: String?) -> String {
        switch self {
        case .finnhub:
            AppLocalization.string("Paste Finnhub API key", appLanguage: appLanguage)
        case .coingecko:
            AppLocalization.string("Paste CoinGecko API key", appLanguage: appLanguage)
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

    // A plain String, not a LocalizedStringKey: these are proper asset names that are not
    // translated, and they get interpolated into localized `Text(...)` templates in the editor.
    // A LocalizedStringKey cannot be interpolated into another LocalizedStringKey — it hits the
    // deprecated generic `appendInterpolation` overload and renders an unlocalized debug
    // description. As a String it uses the supported overload (the surrounding sentence stays
    // localized as "… %@ …" with the name substituted in).
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

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Erase Everything?", appLanguage: appLanguage)
        case .deleteCustomCategory:
            AppLocalization.string("Remove custom category?", appLanguage: appLanguage)
        }
    }

    func localizedMessage(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("This permanently deletes all finance data on this Mac and the copy in iCloud, your Finnhub and CoinGecko API keys, and every preference — returning the app to onboarding. Other devices signed in to the same iCloud account keep their own copy and may restore it to iCloud until you erase it there too. This cannot be undone. Prepare a backup first if you might need this data.", appLanguage: appLanguage)
        case .deleteCustomCategory(let category, _):
            AppLocalization.string("Existing transactions using \(category) will keep their current category label.", appLanguage: appLanguage)
        }
    }

    func localizedConfirmButtonTitle(appLanguage: String?) -> String {
        switch self {
        case .deleteAllData:
            AppLocalization.string("Erase Everything", appLanguage: appLanguage)
        case .deleteCustomCategory(let category, _):
            AppLocalization.string("Remove \(category)", appLanguage: appLanguage)
        }
    }
}

private struct MacMarketDataCredentialEditor: View {
    let credential: MacMarketDataCredentialKind
    let appLanguage: String?
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
            "Remove \(credential.localizedTitle(appLanguage: appLanguage))?",
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove Key", role: .destructive, action: onRemove)
        } message: {
            Text("The stored credential will be deleted from the macOS Keychain.")
        }
    }
}
