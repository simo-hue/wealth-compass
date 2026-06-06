import Foundation

@MainActor
final class AppSettings: ObservableObject {
    let defaultIncomeCategories = ["Salary", "Freelance", "Dividends", "Other"]
    let defaultExpenseCategories = ["Housing", "Food", "Transport", "Utilities", "Fuel", "Entertainment", "Shopping", "Health", "Other"]

    @Published var currency: Currency {
        didSet { userDefaults.set(currency.rawValue, forKey: Keys.currency) }
    }

    @Published var isPrivacyMode: Bool {
        didSet { userDefaults.set(isPrivacyMode, forKey: Keys.privacyMode) }
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
    private var lastExchangeRateRefreshAttemptAt: Date?

    private enum Keys {
        static let currency = "wc_mobile_currency"
        static let privacyMode = "wc_mobile_privacy_mode"
        static let customIncomeCategories = "wc_mobile_custom_income_categories"
        static let customExpenseCategories = "wc_mobile_custom_expense_categories"
        static let exchangeRateSnapshot = "wc_mobile_exchange_rate_snapshot"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedCurrency = userDefaults.string(forKey: Keys.currency)
            .flatMap(Currency.init(rawValue:)) ?? .eur
        currency = storedCurrency
        isPrivacyMode = userDefaults.bool(forKey: Keys.privacyMode)
        customIncomeCategories = Self.loadStringArray(key: Keys.customIncomeCategories, userDefaults: userDefaults)
        customExpenseCategories = Self.loadStringArray(key: Keys.customExpenseCategories, userDefaults: userDefaults)

        if
            let data = userDefaults.data(forKey: Keys.exchangeRateSnapshot),
            let snapshot = try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data),
            snapshot.isValid
        {
            exchangeRateSnapshot = snapshot
        } else {
            exchangeRateSnapshot = nil
        }
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
        return value / sourceUnitsPerEuro * targetUnitsPerEuro
    }

    func shouldAutoRefreshExchangeRates(
        staleAfter: TimeInterval = 12 * 60 * 60,
        retryAfter: TimeInterval = 15 * 60,
        now: Date = Date()
    ) -> Bool {
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
        defer { isRefreshingExchangeRates = false }

        do {
            let previousSnapshot = exchangeRateSnapshot
            let snapshot = try await client.latestRates()
            exchangeRateSnapshot = snapshot
            exchangeRateError = nil
            saveExchangeRateSnapshot(snapshot)

            return ExchangeRateRefreshResult(
                snapshot: snapshot,
                errorMessage: nil,
                didChangeRates: previousSnapshot?.rates != snapshot.rates,
                wasAlreadyRunning: false
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            exchangeRateError = message
            return ExchangeRateRefreshResult(
                snapshot: exchangeRateSnapshot,
                errorMessage: message,
                didChangeRates: false,
                wasAlreadyRunning: false
            )
        }
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

    private func saveExchangeRateSnapshot(_ snapshot: ExchangeRateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: Keys.exchangeRateSnapshot)
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
