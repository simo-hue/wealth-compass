import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let defaultIncomeCategoryKeys = ["Salary", "Freelance", "Dividends", "Other"]
    private static let defaultExpenseCategoryKeys = ["Housing", "Food", "Transport", "Utilities", "Fuel", "Entertainment", "Shopping", "Health", "Other"]

    var defaultIncomeCategories: [String] { Self.defaultIncomeCategoryKeys }
    var defaultExpenseCategories: [String] { Self.defaultExpenseCategoryKeys }

    @Published var currency: Currency {
        didSet { userDefaults.set(currency.rawValue, forKey: Keys.currency) }
    }

    @Published var isPrivacyMode: Bool {
        didSet { userDefaults.set(isPrivacyMode, forKey: Keys.privacyMode) }
    }

    @Published var isICloudSyncEnabled: Bool {
        didSet { userDefaults.set(isICloudSyncEnabled, forKey: Keys.iCloudSyncEnabled) }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet { userDefaults.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding) }
    }

    @Published var appLanguage: String? {
        didSet {
            if let lang = appLanguage {
                userDefaults.set(lang, forKey: Keys.appLanguage)
            } else {
                userDefaults.removeObject(forKey: Keys.appLanguage)
            }
            AppLocalization.applyLanguagePreference(appLanguage)
            // #region agent log
            I18nDebugLog.sampleResolutions(appLanguage: appLanguage)
            I18nDebugLog.log(
                location: "AppSettings.swift:appLanguage",
                message: "app language changed",
                hypothesisId: "D",
                data: [
                    "appLanguage": appLanguage ?? "nil",
                    "defaultIncomeFirst": defaultIncomeCategories.first ?? "nil",
                    "transactionTypeIncome": TransactionType.income.localizedTitle(appLanguage: appLanguage)
                ]
            )
            // #endregion
        }
    }

    @Published private(set) var customIncomeCategories: [String] = [] {
        didSet { saveStringArray(customIncomeCategories, key: Keys.customIncomeCategories) }
    }

    @Published private(set) var customExpenseCategories: [String] = [] {
        didSet { saveStringArray(customExpenseCategories, key: Keys.customExpenseCategories) }
    }

    @Published private(set) var exchangeRateSnapshot: ExchangeRateSnapshot?
    @Published private(set) var isRefreshingExchangeRates = false
    @Published private(set) var exchangeRateError: String?

    private let userDefaults: UserDefaults
    private let exchangeRatePersistence: ExchangeRatePersistence
    private var lastExchangeRateRefreshAttemptAt: Date?
    private var consecutiveExchangeRateFailures: Int

    private enum Keys {
        static let currency = "wc_mobile_currency"
        static let privacyMode = "wc_mobile_privacy_mode"
        static let customIncomeCategories = "wc_mobile_custom_income_categories"
        static let customExpenseCategories = "wc_mobile_custom_expense_categories"
        static let iCloudSyncEnabled = "wc_mobile_icloud_sync_enabled"
        static let hasSeenOnboarding = "wc_mobile_has_seen_onboarding"
        static let appLanguage = "wc_mobile_app_language"
        static let lastExchangeRateRefreshAttempt = "wc_mobile_last_exchange_rate_refresh_attempt"
        static let consecutiveExchangeRateFailures = "wc_mobile_consecutive_exchange_rate_failures"
    }

    init(
        userDefaults: UserDefaults = .standard,
        exchangeRatePersistence: ExchangeRatePersistence = LocalExchangeRatePersistence()
    ) {
        self.userDefaults = userDefaults
        self.exchangeRatePersistence = exchangeRatePersistence

        let storedCurrency = userDefaults.string(forKey: Keys.currency)
            .flatMap(Currency.init(rawValue:)) ?? .eur
        currency = storedCurrency
        isPrivacyMode = userDefaults.bool(forKey: Keys.privacyMode)
        isICloudSyncEnabled = userDefaults.bool(forKey: Keys.iCloudSyncEnabled)
        hasSeenOnboarding = userDefaults.bool(forKey: Keys.hasSeenOnboarding)
        appLanguage = userDefaults.string(forKey: Keys.appLanguage)
        customIncomeCategories = Self.loadStringArray(key: Keys.customIncomeCategories, userDefaults: userDefaults)
        customExpenseCategories = Self.loadStringArray(key: Keys.customExpenseCategories, userDefaults: userDefaults)

        // Load exchange rate snapshot from file-based persistence (with auto-migration from UserDefaults)
        exchangeRateSnapshot = exchangeRatePersistence.load()

        // Restore persisted retry state
        consecutiveExchangeRateFailures = userDefaults.integer(forKey: Keys.consecutiveExchangeRateFailures)
        if let timestamp = userDefaults.object(forKey: Keys.lastExchangeRateRefreshAttempt) as? Date {
            lastExchangeRateRefreshAttemptAt = timestamp
        }

        // #region agent log
        I18nDebugLog.sampleResolutions(appLanguage: appLanguage)
        I18nDebugLog.log(
            location: "AppSettings.swift:init",
            message: "settings initialized",
            hypothesisId: "D",
            data: [
                "appLanguage": appLanguage ?? "nil",
                "defaultIncomeFirst": defaultIncomeCategories.first ?? "nil"
            ]
        )
        // #endregion

        AppLocalization.applyLanguagePreference(appLanguage)
    }

    var availableLanguages: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted()
    }

    func languageName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code)?.capitalized ?? code
    }

    func localized(_ key: String.LocalizationValue) -> String {
        AppLocalization.string(key, appLanguage: appLanguage)
    }

    func transactionCategories(for type: TransactionType) -> [String] {
        let defaults = type == .income ? defaultIncomeCategories : defaultExpenseCategories
        let custom = type == .income ? customIncomeCategories : customExpenseCategories
        return defaults + custom.filter { candidate in
            !defaults.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
    }

    @discardableResult
    func addCustomTransactionCategory(_ rawValue: String, for type: TransactionType) -> String? {
        let category = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { return nil }

        let existing = transactionCategories(for: type)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) else {
            return existing.first { $0.caseInsensitiveCompare(category) == .orderedSame }
        }

        if type == .income {
            customIncomeCategories.append(category)
            customIncomeCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            customExpenseCategories.append(category)
            customExpenseCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        return category
    }

    func removeCustomTransactionCategory(_ category: String, for type: TransactionType) {
        if type == .income {
            customIncomeCategories.removeAll { $0.caseInsensitiveCompare(category) == .orderedSame }
        } else {
            customExpenseCategories.removeAll { $0.caseInsensitiveCompare(category) == .orderedSame }
        }
    }

    func convert(_ value: Double, from sourceCurrency: Currency?) -> Double {
        guard let sourceCurrency else { return value }
        return convert(value, from: sourceCurrency, to: currency)
    }

    func convert(_ value: Double, from sourceCurrency: Currency, to targetCurrency: Currency) -> Double {
        guard sourceCurrency != targetCurrency else { return value }

        let sourceUnitsPerEuro = unitsPerEuro(for: sourceCurrency)
        let targetUnitsPerEuro = unitsPerEuro(for: targetCurrency)
        // Guard against malformed exchange-rate data (a zero or non-finite rate),
        // which would otherwise yield Inf/NaN and propagate into chart geometry,
        // triggering "invalid numeric value (NaN) to CoreGraphics" errors.
        guard
            value.isFinite,
            sourceUnitsPerEuro.isFinite, sourceUnitsPerEuro > 0,
            targetUnitsPerEuro.isFinite, targetUnitsPerEuro > 0
        else {
            return value
        }
        let result = value / sourceUnitsPerEuro * targetUnitsPerEuro
        return result.isFinite ? result : value
    }

    func shouldAutoRefreshExchangeRates(
        staleAfter: TimeInterval = 12 * 60 * 60,
        baseRetryAfter: TimeInterval = 15 * 60,
        now: Date = Date()
    ) -> Bool {
        // Exponential backoff: 15min × 2^min(failures, 4) → caps at ~4 hours
        let backoffMultiplier = pow(2.0, Double(min(consecutiveExchangeRateFailures, 4)))
        let retryAfter = baseRetryAfter * backoffMultiplier

        if let lastExchangeRateRefreshAttemptAt,
           now.timeIntervalSince(lastExchangeRateRefreshAttemptAt) < retryAfter {
            return false
        }

        guard let exchangeRateSnapshot else { return true }
        return now.timeIntervalSince(exchangeRateSnapshot.fetchedAt) >= staleAfter
    }

    func refreshExchangeRates(client: ExchangeRateClient = ExchangeRateClient()) async -> ExchangeRateRefreshResult {
        guard !isRefreshingExchangeRates else {
            return ExchangeRateRefreshResult(
                snapshot: nil,
                errorMessage: nil,
                didChangeRates: false,
                wasAlreadyRunning: true
            )
        }

        isRefreshingExchangeRates = true
        lastExchangeRateRefreshAttemptAt = Date()
        userDefaults.set(lastExchangeRateRefreshAttemptAt, forKey: Keys.lastExchangeRateRefreshAttempt)
        defer { isRefreshingExchangeRates = false }

        do {
            let previousSnapshot = exchangeRateSnapshot
            let snapshot = try await client.latestRates()
            exchangeRateSnapshot = snapshot
            exchangeRateError = nil
            exchangeRatePersistence.save(snapshot)

            // Reset backoff on success
            consecutiveExchangeRateFailures = 0
            userDefaults.set(0, forKey: Keys.consecutiveExchangeRateFailures)

            return ExchangeRateRefreshResult(
                snapshot: snapshot,
                errorMessage: nil,
                didChangeRates: previousSnapshot?.rates != snapshot.rates,
                wasAlreadyRunning: false
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            exchangeRateError = message

            // Increment backoff counter on failure
            consecutiveExchangeRateFailures += 1
            userDefaults.set(consecutiveExchangeRateFailures, forKey: Keys.consecutiveExchangeRateFailures)

            return ExchangeRateRefreshResult(
                snapshot: exchangeRateSnapshot,
                errorMessage: message,
                didChangeRates: false,
                wasAlreadyRunning: false
            )
        }
    }

    /// Shared helper that refreshes exchange rates and recalculates net worth if rates changed.
    /// Consolidates the duplicated "refresh → check didChangeRates → takeSnapshot" pattern
    /// used across iOS ContentView, macOS MacRootView, and both platform SettingsViews.
    func refreshExchangeRatesAndRecalculate(
        finance: FinanceStore,
        client: ExchangeRateClient = ExchangeRateClient(),
        showResult: ((ExchangeRateRefreshResult) -> Void)? = nil
    ) async {
        let result = await refreshExchangeRates(client: client)
        if result.didChangeRates, finance.hasForeignCurrencyExposure(relativeTo: currency) {
            finance.takeSnapshot(settings: self)
        }
        showResult?(result)
    }

    func formatCurrency(_ value: Double, sourceCurrency: Currency? = nil) -> String {
        let converted = convert(value, from: sourceCurrency)
        return converted.formatted(.currency(code: currency.rawValue))
    }

    func formatSourceCurrency(_ value: Double, currency sourceCurrency: Currency) -> String {
        value.formatted(.currency(code: sourceCurrency.rawValue))
    }

    func privateCurrency(_ value: Double, sourceCurrency: Currency? = nil) -> String {
        isPrivacyMode ? "****" : formatCurrency(value, sourceCurrency: sourceCurrency)
    }

    func privateNumber(_ value: Double, fractionDigits: Int = 2) -> String {
        guard !isPrivacyMode else { return "****" }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    private func saveStringArray(_ values: [String], key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        userDefaults.set(data, forKey: key)
    }

    private func unitsPerEuro(for currency: Currency) -> Double {
        exchangeRateSnapshot?.unitsPerBaseCurrency(for: currency) ?? currency.fallbackUnitsPerEuro
    }

    private static func loadStringArray(key: String, userDefaults: UserDefaults) -> [String] {
        guard
            let data = userDefaults.data(forKey: key),
            let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values
    }
}
