import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let defaultIncomeCategoryKeys = ["Salary", "Freelance", "Dividends", "Other"]
    private static let defaultExpenseCategoryKeys = ["Housing", "Food", "Transport", "Utilities", "Fuel", "Entertainment", "Shopping", "Health", "Other"]
    /// Ceiling for the exchange-rate retry-backoff exponent (deep-audit L50): both the read site and
    /// the persisted increment clamp to this, so the stored failure count can't drift unbounded.
    private static let maxExchangeRateBackoffExponent = 4

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

    /// The single source of truth for the in-app language `UserDefaults` key, exposed for the few
    /// off-`AppSettings` readers that can't hold an instance (WC-L31: `RecurringNotificationService`
    /// reads it directly). Kept in sync with the private `Keys.appLanguage`.
    static let appLanguageDefaultsKey = Keys.appLanguage

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

        AppLocalization.applyLanguagePreference(appLanguage)
    }

    /// Languages offered in the picker, sorted by their *displayed* name in the effective
    /// in-app locale (WC-L23) rather than by raw ISO code.
    var availableLanguages: [String] {
        let locale = effectiveLocale
        return Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted {
                languageName(for: $0, locale: locale)
                    .localizedCaseInsensitiveCompare(languageName(for: $1, locale: locale)) == .orderedAscending
            }
    }

    /// Names a language code in the user's chosen in-app language (WC-L23) — not the system
    /// locale — and preserves each language's own casing convention (no forced capitalization).
    func languageName(for code: String) -> String {
        languageName(for: code, locale: effectiveLocale)
    }

    private func languageName(for code: String, locale: Locale) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }

    /// The locale the in-app language override resolves to, falling back to the system locale.
    private var effectiveLocale: Locale {
        appLanguage.map(Locale.init(identifier:)) ?? .current
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

    /// Restores every preference to its first-launch default for a factory reset: clears the
    /// `wc_mobile_*` preference keys (including the biometric App-Lock flag owned by
    /// `AppLockStore`, WC-L22), resets the in-memory published state, and removes the cached
    /// exchange-rate snapshot. Flipping `hasSeenOnboarding` to false makes the root view
    /// navigate back to onboarding. Market-data API keys live in the Keychain (cleared
    /// separately by the reset), never here.
    func resetToDefaults() {
        // Clear the keys up front so the two manually-persisted retry fields (which have no
        // `didSet`) don't leave a stale value behind; the property assignments below then
        // re-persist clean defaults for everything else.
        let keys = [
            Keys.currency, Keys.privacyMode, Keys.customIncomeCategories,
            Keys.customExpenseCategories, Keys.iCloudSyncEnabled, Keys.hasSeenOnboarding,
            Keys.appLanguage, Keys.lastExchangeRateRefreshAttempt, Keys.consecutiveExchangeRateFailures,
            // Owned by AppLockStore, but cleared here so a factory reset truly removes the
            // biometric App-Lock preference instead of leaving it enabled (WC-L22).
            "wc_mobile_biometric_lock_enabled"
        ]
        keys.forEach { userDefaults.removeObject(forKey: $0) }

        currency = .eur
        isPrivacyMode = false
        isICloudSyncEnabled = false
        hasSeenOnboarding = false
        appLanguage = nil
        customIncomeCategories = []
        customExpenseCategories = []

        exchangeRatePersistence.clear()
        exchangeRateSnapshot = nil
        exchangeRateError = nil
        isRefreshingExchangeRates = false
        lastExchangeRateRefreshAttemptAt = nil
        consecutiveExchangeRateFailures = 0
    }

    /// Pure converter bound to the current rate snapshot (see `CurrencyConverter`, M1/T1).
    var currencyConverter: CurrencyConverter {
        CurrencyConverter(snapshot: exchangeRateSnapshot)
    }

    func convert(_ value: Double, from sourceCurrency: Currency?) -> Double {
        currencyConverter.convert(value, from: sourceCurrency, to: currency)
    }

    func convert(_ value: Double, from sourceCurrency: Currency, to targetCurrency: Currency) -> Double {
        currencyConverter.convert(value, from: sourceCurrency, to: targetCurrency)
    }

    func shouldAutoRefreshExchangeRates(
        staleAfter: TimeInterval = 12 * 60 * 60,
        baseRetryAfter: TimeInterval = 15 * 60,
        now: Date = Date()
    ) -> Bool {
        // Exponential backoff: 15min × 2^min(failures, 4) → caps at ~4 hours
        let backoffMultiplier = pow(2.0, Double(min(consecutiveExchangeRateFailures, Self.maxExchangeRateBackoffExponent)))
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

            // Increment the backoff counter on failure, clamped to the backoff domain (deep-audit
            // L50) so the persisted value never drifts past the ceiling the read site uses.
            consecutiveExchangeRateFailures = min(consecutiveExchangeRateFailures + 1, Self.maxExchangeRateBackoffExponent)
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

    /// Single source of truth for the privacy-mode redaction glyph (L8).
    let redactionToken = "••••"

    func formatCurrency(_ value: Double, sourceCurrency: Currency? = nil) -> String {
        let converted = convert(value, from: sourceCurrency)
        return converted.formatted(.currency(code: currency.rawValue))
    }

    func formatSourceCurrency(_ value: Double, currency sourceCurrency: Currency) -> String {
        value.formatted(.currency(code: sourceCurrency.rawValue))
    }

    func privateCurrency(_ value: Double, sourceCurrency: Currency? = nil) -> String {
        isPrivacyMode ? redactionToken : formatCurrency(value, sourceCurrency: sourceCurrency)
    }

    func privateNumber(_ value: Double, fractionDigits: Int = 2) -> String {
        guard !isPrivacyMode else { return redactionToken }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    // MARK: - Decimal (money) overloads (WC-A1)
    // Money and quantities are stored as `Decimal`; these mirror the `Double` helpers so the
    // views format and convert money without crossing back to `Double` except inside the
    // converter's FX multiply.

    func convert(_ value: Decimal, from sourceCurrency: Currency?) -> Decimal {
        currencyConverter.convert(value, from: sourceCurrency, to: currency)
    }

    func convert(_ value: Decimal, from sourceCurrency: Currency, to targetCurrency: Currency) -> Decimal {
        currencyConverter.convert(value, from: sourceCurrency, to: targetCurrency)
    }

    func formatCurrency(_ value: Decimal, sourceCurrency: Currency? = nil) -> String {
        convert(value, from: sourceCurrency).formatted(.currency(code: currency.rawValue))
    }

    func formatSourceCurrency(_ value: Decimal, currency sourceCurrency: Currency) -> String {
        value.formatted(.currency(code: sourceCurrency.rawValue))
    }

    func privateCurrency(_ value: Decimal, sourceCurrency: Currency? = nil) -> String {
        isPrivacyMode ? redactionToken : formatCurrency(value, sourceCurrency: sourceCurrency)
    }

    /// Formats a single record's amount in **its own** currency without converting to the display
    /// currency (deep-audit H5), redacting under privacy mode. Transaction and recurring rows use
    /// this so a non-display-currency record shows its true amount + symbol (e.g. `$100` for a USD
    /// row while the base is EUR) instead of the raw number wearing the display symbol (`€100`).
    /// Aggregate totals stay converted; only per-row displays switch to source-currency formatting.
    func privateSourceCurrency(_ value: Decimal, currency sourceCurrency: Currency) -> String {
        isPrivacyMode ? redactionToken : formatSourceCurrency(value, currency: sourceCurrency)
    }

    func privateNumber(_ value: Decimal, fractionDigits: Int = 2) -> String {
        guard !isPrivacyMode else { return redactionToken }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    private func saveStringArray(_ values: [String], key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        userDefaults.set(data, forKey: key)
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
