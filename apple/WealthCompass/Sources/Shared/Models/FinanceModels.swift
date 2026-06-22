import Foundation
import SwiftUI

/// ISO-4217 currencies the app can represent and convert.
///
/// The set mirrors the currencies published by the European Central Bank and
/// served by Frankfurter (our exchange-rate provider, EUR-based), so every case
/// can be converted once a rate snapshot is cached. The four "major" cases are
/// declared first so they surface at the top of pickers; the remainder follow
/// alphabetically. Stored as the ISO code string, so existing JSON ("EUR", …)
/// continues to decode unchanged.
enum Currency: String, CaseIterable, Codable, Identifiable {
    // Majors — surfaced first in pickers.
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
    case chf = "CHF"
    // Remaining ECB / Frankfurter-supported currencies (alphabetical).
    case aud = "AUD"
    case bgn = "BGN"
    case brl = "BRL"
    case cad = "CAD"
    case cny = "CNY"
    case czk = "CZK"
    case dkk = "DKK"
    case hkd = "HKD"
    case huf = "HUF"
    case idr = "IDR"
    case ils = "ILS"
    case inr = "INR"
    case isk = "ISK"
    case jpy = "JPY"
    case krw = "KRW"
    case mxn = "MXN"
    case myr = "MYR"
    case nok = "NOK"
    case nzd = "NZD"
    case php = "PHP"
    case pln = "PLN"
    case ron = "RON"
    case sek = "SEK"
    case sgd = "SGD"
    case thb = "THB"
    case `try` = "TRY"
    case zar = "ZAR"

    var id: String { rawValue }

    /// SwiftUI-only display name; resolves against the environment locale inside a `Text`.
    /// Use `localizedDisplayName(appLanguage:)` everywhere a resolved `String` is needed.
    var displayName: LocalizedStringKey {
        LocalizedStringKey(Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue)
    }

    func localizedDisplayName(appLanguage: String?) -> String {
        let locale = appLanguage.map { Locale(identifier: $0) } ?? Locale.current
        return locale.localizedString(forCurrencyCode: rawValue) ?? rawValue
    }

    var symbol: String {
        switch self {
        case .eur: return "€"
        case .usd: return "$"
        case .gbp: return "£"
        case .chf: return "Fr"
        default:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = rawValue
            return formatter.currencySymbol ?? rawValue
        }
    }

    /// Approximate offline seed rates (units per 1 EUR), used only before the first
    /// live ECB snapshot is cached; they are replaced by real rates on refresh.
    /// A `.nan` here is fine — `AppSettings.convert` guards non-finite rates and
    /// leaves the value unconverted rather than producing NaN chart geometry.
    var fallbackUnitsPerEuro: Double {
        switch self {
        case .eur: return 1.0
        case .usd: return 1 / 0.92
        case .gbp: return 1 / 1.17
        case .chf: return 1 / 1.05
        case .aud: return 1.63
        case .bgn: return 1.956
        case .brl: return 5.40
        case .cad: return 1.47
        case .cny: return 7.70
        case .czk: return 25.2
        case .dkk: return 7.46
        case .hkd: return 8.40
        case .huf: return 390
        case .idr: return 17000
        case .ils: return 4.00
        case .inr: return 90
        case .isk: return 150
        case .jpy: return 165
        case .krw: return 1450
        case .mxn: return 18.5
        case .myr: return 5.10
        case .nok: return 11.5
        case .nzd: return 1.78
        case .php: return 61
        case .pln: return 4.30
        case .ron: return 4.97
        case .sek: return 11.4
        case .sgd: return 1.46
        case .thb: return 39
        case .`try`: return 35
        case .zar: return 20
        }
    }
}

enum TransactionType: String, CaseIterable, Codable, Identifiable {
    case income
    case expense

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .income: AppLocalization.string("Income", appLanguage: appLanguage)
        case .expense: AppLocalization.string("Expense", appLanguage: appLanguage)
        }
    }
}

enum InvestmentType: String, CaseIterable, Codable, Identifiable {
    case stock
    case etf
    case bond
    case realEstate = "real_estate"
    case commodity
    case other

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .stock: "Stock"
        case .etf: "ETF"
        case .bond: "Bond"
        case .realEstate: "Real Estate"
        case .commodity: "Commodity"
        case .other: "Other"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .stock: AppLocalization.string("Stock", appLanguage: appLanguage)
        case .etf: AppLocalization.string("ETF", appLanguage: appLanguage)
        case .bond: AppLocalization.string("Bond", appLanguage: appLanguage)
        case .realEstate: AppLocalization.string("Real Estate", appLanguage: appLanguage)
        case .commodity: AppLocalization.string("Commodity", appLanguage: appLanguage)
        case .other: AppLocalization.string("Other", appLanguage: appLanguage)
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var id: String { rawValue }
}

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case threeMonths = "3m"
    case yearToDate = "ytd"
    case all = "all"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .sevenDays: "Last 7 Days"
        case .thirtyDays: "Last 30 Days"
        case .threeMonths: "Last 3 Months"
        case .yearToDate: "Year to Date"
        case .all: "All Time"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .sevenDays: AppLocalization.string("Last 7 Days", appLanguage: appLanguage)
        case .thirtyDays: AppLocalization.string("Last 30 Days", appLanguage: appLanguage)
        case .threeMonths: AppLocalization.string("Last 3 Months", appLanguage: appLanguage)
        case .yearToDate: AppLocalization.string("Year to Date", appLanguage: appLanguage)
        case .all: AppLocalization.string("All Time", appLanguage: appLanguage)
        }
    }
}

enum FeeMode: String, CaseIterable, Identifiable {
    case fixed
    case percent

    var id: String { rawValue }
    var title: LocalizedStringKey { self == .fixed ? "Fixed" : "Percent" }

    func localizedTitle(appLanguage: String?) -> String {
        AppLocalization.string(self == .fixed ? "Fixed" : "Percent", appLanguage: appLanguage)
    }
}

struct Transaction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: TransactionType
    var category: String
    var amount: Double
    var description: String
    var date: Date
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var recurringTransactionID: UUID?
    var recurringOccurrenceDate: Date?
}

enum RecurringTransactionFrequency: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .daily: AppLocalization.string("Daily", appLanguage: appLanguage)
        case .weekly: AppLocalization.string("Weekly", appLanguage: appLanguage)
        case .monthly: AppLocalization.string("Monthly", appLanguage: appLanguage)
        case .yearly: AppLocalization.string("Yearly", appLanguage: appLanguage)
        }
    }

    func nextDate(after date: Date, anchoredTo startDate: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return Self.nextMonthlyDate(after: date, anchoredTo: startDate, calendar: calendar)
        case .yearly:
            return Self.nextYearlyDate(after: date, anchoredTo: startDate, calendar: calendar)
        }
    }

    private static func nextMonthlyDate(after date: Date, anchoredTo startDate: Date, calendar: Calendar) -> Date? {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        guard
            let currentMonth,
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: nextMonth)
        else {
            return nil
        }

        let anchor = calendar.dateComponents([.day, .hour, .minute, .second], from: startDate)
        var components = calendar.dateComponents([.year, .month], from: nextMonth)
        components.day = min(anchor.day ?? 1, dayRange.count)
        components.hour = anchor.hour
        components.minute = anchor.minute
        components.second = anchor.second
        return calendar.date(from: components)
    }

    private static func nextYearlyDate(after date: Date, anchoredTo startDate: Date, calendar: Calendar) -> Date? {
        let currentYear = calendar.component(.year, from: date)
        let anchor = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: startDate)
        guard let month = anchor.month else { return nil }

        var monthComponents = DateComponents()
        monthComponents.calendar = calendar
        monthComponents.year = currentYear + 1
        monthComponents.month = month
        monthComponents.day = 1

        guard
            let monthDate = calendar.date(from: monthComponents),
            let dayRange = calendar.range(of: .day, in: .month, for: monthDate)
        else {
            return nil
        }

        var components = monthComponents
        components.day = min(anchor.day ?? 1, dayRange.count)
        components.hour = anchor.hour
        components.minute = anchor.minute
        components.second = anchor.second
        return calendar.date(from: components)
    }
}

struct RecurringTransaction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: TransactionType
    var category: String
    var amount: Double
    var description: String
    var startDate: Date
    var frequency: RecurringTransactionFrequency
    var nextDueDate: Date
    var endDate: Date?
    var notificationsEnabled: Bool = true
    var isActive: Bool = true
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var isCompleted: Bool {
        completedAt != nil
    }

    func firstOccurrence(onOrAfter threshold: Date, calendar: Calendar = .current) -> Date? {
        var occurrence = startDate
        var iterationCount = 0
        let maxIterations = 20_000

        while occurrence < threshold {
            // If we exhaust the iteration budget before reaching the threshold, we
            // must NOT return the last (still-past) occurrence — that would let a
            // far back-dated schedule mass-generate history. Signal "no occurrence".
            guard iterationCount < maxIterations else { return nil }
            guard let next = frequency.nextDate(after: occurrence, anchoredTo: startDate, calendar: calendar) else {
                return nil
            }
            occurrence = next
            iterationCount += 1
        }

        guard endDate.map({ occurrence <= $0 }) ?? true else { return nil }
        return occurrence
    }
}

struct Investment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: InvestmentType
    var symbol: String
    var name: String
    var quantity: Double
    var costBasis: Double
    var currentValue: Double
    var currentPrice: Double
    var currency: Currency
    var geography: String
    var sector: String
    var isin: String
    var fees: Double
    var updatedAt: Date = Date()
    var createdAt: Date = Date()

    var gainLoss: Double { currentValue - costBasis }
    var gainLossPercent: Double { costBasis > 0 ? (gainLoss / costBasis) * 100 : 0 }
}

struct CryptoHolding: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var symbol: String
    var name: String
    var quantity: Double
    var avgBuyPrice: Double
    var currentPrice: Double
    var currency: Currency = .usd
    var fees: Double
    var coinId: String
    var updatedAt: Date = Date()
    var createdAt: Date = Date()

    var costBasis: Double { quantity * avgBuyPrice }
    var currentValue: Double { quantity * currentPrice }
    var gainLoss: Double { currentValue - costBasis }
    var gainLossPercent: Double { costBasis > 0 ? (gainLoss / costBasis) * 100 : 0 }
}

struct Liability: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var currentBalance: Double
    var currency: Currency
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct NetWorthSnapshot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var totalAssets: Double
    var totalLiabilities: Double
    var netWorth: Double
    var liquidity: Double
    var investments: Double
    var crypto: Double
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct FinancialData: Codable, Equatable, Sendable {
    var transactions: [Transaction] = []
    var recurringTransactions: [RecurringTransaction] = []
    var investments: [Investment] = []
    var crypto: [CryptoHolding] = []
    var liabilities: [Liability] = []
    var snapshots: [NetWorthSnapshot] = []

    private enum CodingKeys: String, CodingKey {
        case transactions
        case recurringTransactions
        case investments
        case crypto
        case liabilities
        case snapshots
    }

    init(
        transactions: [Transaction] = [],
        recurringTransactions: [RecurringTransaction] = [],
        investments: [Investment] = [],
        crypto: [CryptoHolding] = [],
        liabilities: [Liability] = [],
        snapshots: [NetWorthSnapshot] = []
    ) {
        self.transactions = transactions
        self.recurringTransactions = recurringTransactions
        self.investments = investments
        self.crypto = crypto
        self.liabilities = liabilities
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        recurringTransactions = try container.decodeIfPresent([RecurringTransaction].self, forKey: .recurringTransactions) ?? []
        investments = try container.decodeIfPresent([Investment].self, forKey: .investments) ?? []
        crypto = try container.decodeIfPresent([CryptoHolding].self, forKey: .crypto) ?? []
        liabilities = try container.decodeIfPresent([Liability].self, forKey: .liabilities) ?? []
        snapshots = try container.decodeIfPresent([NetWorthSnapshot].self, forKey: .snapshots) ?? []
    }
}

struct FinanceTotals: Equatable {
    var totalLiquidity: Double = 0
    var totalInvestments: Double = 0
    var totalCrypto: Double = 0
    var totalAssets: Double = 0
    var totalLiabilities: Double = 0
    var netWorth: Double = 0
}

struct MonthlyCashFlow: Equatable {
    var monthlyIncome: Double = 0
    var monthlyExpenses: Double = 0

    var netSavings: Double { monthlyIncome - monthlyExpenses }
    var savingsRate: Double { monthlyIncome > 0 ? (netSavings / monthlyIncome) * 100 : 0 }
}

struct CashFlowMonth: Identifiable, Equatable {
    var id: String { monthKey }
    var monthKey: String
    var monthLabel: String
    var income: Double
    var expense: Double
}

struct CategoryTotal: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var value: Double
    var percentage: Double
}

struct AllocationSlice: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var value: Double
    var color: Color
}

struct NetWorthPoint: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var value: Double
}

protocol MergeableRecord: Identifiable where ID == UUID {
    var updatedAt: Date { get }
}

extension Transaction: MergeableRecord {}
extension RecurringTransaction: MergeableRecord {}
extension Investment: MergeableRecord {}
extension CryptoHolding: MergeableRecord {}
extension Liability: MergeableRecord {}
extension NetWorthSnapshot: MergeableRecord {}

extension Array where Element: MergeableRecord {
    func mergedByID(with incoming: [Element]) -> [Element] {
        var merged = self
        for item in incoming {
            if let index = merged.firstIndex(where: { $0.id == item.id }) {
                if item.updatedAt > merged[index].updatedAt {
                    merged[index] = item
                }
            } else {
                merged.append(item)
            }
        }
        return merged
    }
}

extension FinancialData {
    func merged(with incoming: FinancialData) -> FinancialData {
        FinancialData(
            transactions: transactions.mergedByID(with: incoming.transactions),
            recurringTransactions: recurringTransactions.mergedByID(with: incoming.recurringTransactions),
            investments: investments.mergedByID(with: incoming.investments),
            crypto: crypto.mergedByID(with: incoming.crypto),
            liabilities: liabilities.mergedByID(with: incoming.liabilities),
            snapshots: snapshots.mergedByID(with: incoming.snapshots)
        )
    }
}
