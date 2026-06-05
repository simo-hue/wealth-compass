import Foundation

@MainActor
final class AppSettings: ObservableObject {
    let defaultIncomeCategories = ["Salary", "Freelance", "Dividends", "Other"]
    let defaultExpenseCategories = ["Housing", "Food", "Transport", "Utilities", "Fuel", "Entertainment", "Shopping", "Health", "Other"]

    @Published var currency: Currency {
        didSet { UserDefaults.standard.set(currency.rawValue, forKey: Keys.currency) }
    }

    @Published var isPrivacyMode: Bool {
        didSet { UserDefaults.standard.set(isPrivacyMode, forKey: Keys.privacyMode) }
    }

    @Published private(set) var customIncomeCategories: [String] = [] {
        didSet { saveStringArray(customIncomeCategories, key: Keys.customIncomeCategories) }
    }

    @Published private(set) var customExpenseCategories: [String] = [] {
        didSet { saveStringArray(customExpenseCategories, key: Keys.customExpenseCategories) }
    }

    private enum Keys {
        static let currency = "wc_mobile_currency"
        static let privacyMode = "wc_mobile_privacy_mode"
        static let customIncomeCategories = "wc_mobile_custom_income_categories"
        static let customExpenseCategories = "wc_mobile_custom_expense_categories"
    }

    init() {
        let storedCurrency = UserDefaults.standard.string(forKey: Keys.currency)
            .flatMap(Currency.init(rawValue:)) ?? .eur
        currency = storedCurrency
        isPrivacyMode = UserDefaults.standard.bool(forKey: Keys.privacyMode)
        customIncomeCategories = Self.loadStringArray(key: Keys.customIncomeCategories)
        customExpenseCategories = Self.loadStringArray(key: Keys.customExpenseCategories)
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
        guard let sourceCurrency, sourceCurrency != currency else { return value }
        let valueInEUR = value * sourceCurrency.eurValue
        return valueInEUR / currency.eurValue
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
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadStringArray(key: String) -> [String] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values
    }
}
