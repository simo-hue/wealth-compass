import Foundation
import SwiftUI

enum Currency: String, CaseIterable, Codable, Identifiable {
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
    case chf = "CHF"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eur: "Euro"
        case .usd: "US Dollar"
        case .gbp: "British Pound"
        case .chf: "Swiss Franc"
        }
    }

    var symbol: String {
        switch self {
        case .eur: "€"
        case .usd: "$"
        case .gbp: "£"
        case .chf: "Fr"
        }
    }

    var fallbackUnitsPerEuro: Double {
        switch self {
        case .eur: 1.0
        case .usd: 1 / 0.92
        case .gbp: 1 / 1.17
        case .chf: 1 / 1.05
        }
    }
}

enum TransactionType: String, CaseIterable, Codable, Identifiable {
    case income
    case expense

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum InvestmentType: String, CaseIterable, Codable, Identifiable {
    case stock
    case etf
    case bond
    case realEstate = "real_estate"
    case commodity
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stock: "Stock"
        case .etf: "ETF"
        case .bond: "Bond"
        case .realEstate: "Real Estate"
        case .commodity: "Commodity"
        case .other: "Other"
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

    var title: String {
        switch self {
        case .sevenDays: "Last 7 Days"
        case .thirtyDays: "Last 30 Days"
        case .threeMonths: "Last 3 Months"
        case .yearToDate: "Year to Date"
        case .all: "All Time"
        }
    }
}

enum FeeMode: String, CaseIterable, Identifiable {
    case fixed
    case percent

    var id: String { rawValue }
    var title: String { self == .fixed ? "Fixed" : "Percent" }
}

struct Transaction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: TransactionType
    var category: String
    var amount: Double
    var description: String
    var date: Date
    var createdAt: Date = Date()
    var recurringTransactionID: UUID?
    var recurringOccurrenceDate: Date?
}

enum RecurringTransactionFrequency: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
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

        while occurrence < threshold && iterationCount < 20_000 {
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
}

struct FinancialData: Codable, Equatable {
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
