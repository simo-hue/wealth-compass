import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var currency: Currency {
        didSet { UserDefaults.standard.set(currency.rawValue, forKey: Keys.currency) }
    }

    @Published var isPrivacyMode: Bool {
        didSet { UserDefaults.standard.set(isPrivacyMode, forKey: Keys.privacyMode) }
    }

    private enum Keys {
        static let currency = "wc_mobile_currency"
        static let privacyMode = "wc_mobile_privacy_mode"
    }

    init() {
        let storedCurrency = UserDefaults.standard.string(forKey: Keys.currency)
            .flatMap(Currency.init(rawValue:)) ?? .eur
        currency = storedCurrency
        isPrivacyMode = UserDefaults.standard.bool(forKey: Keys.privacyMode)
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
}
