import XCTest
@testable import WealthCompassMobile

/// T5 — analytics: totals, category grouping, cash-flow trend, allocations (M1).
final class AnalyticsEngineTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return utc.date(from: comps)!
    }

    private func tx(_ type: TransactionType, _ amount: Double, _ category: String, _ when: Date) -> Transaction {
        Transaction(type: type, category: category, amount: amount, description: "", date: when)
    }

    private func engine(_ data: FinancialData, now: Date) -> AnalyticsEngine {
        AnalyticsEngine(data: data, displayCurrency: .eur, calendar: utc, now: now)
    }

    func testCalculateTotals() {
        let data = FinancialData(
            transactions: [tx(.income, 1000, "Salary", date(2026, 6, 1)), tx(.expense, 300, "Food", date(2026, 6, 2))],
            investments: [Investment(type: .stock, symbol: "AAPL", name: "Apple", quantity: 1, costBasis: 100, currentValue: 150, currentPrice: 150, currency: .eur, geography: "US", sector: "Tech", isin: "", fees: 0)],
            liabilities: [Liability(name: "Loan", currentBalance: 200, currency: .eur)]
        )
        let totals = engine(data, now: date(2026, 6, 22)).calculateTotals()
        XCTAssertEqual(totals.totalLiquidity, 700)
        XCTAssertEqual(totals.totalInvestments, 150)
        XCTAssertEqual(totals.totalLiabilities, 200)
        XCTAssertEqual(totals.netWorth, 650)
    }

    func testExpensesByCategoryGroupsRanksAndExcludesIncome() {
        let now = date(2026, 6, 22)
        let data = FinancialData(transactions: [
            tx(.expense, 100, "Food", date(2026, 6, 20)),
            tx(.expense, 50, "Food", date(2026, 6, 21)),
            tx(.expense, 200, "Rent", date(2026, 6, 19)),
            tx(.income, 999, "Salary", date(2026, 6, 18))
        ])
        let result = engine(data, now: now).expensesByCategory(period: .thirtyDays)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.name, "Rent")
        XCTAssertEqual(result.first?.value, 200)
        XCTAssertEqual(result.map(\.value).reduce(0, +), 350)
    }

    func testCashFlowTrendCountsMonthsAndSumsCurrentMonth() {
        let data = FinancialData(transactions: [
            tx(.income, 100, "X", date(2026, 6, 10)),
            tx(.expense, 40, "Y", date(2026, 6, 11))
        ])
        let trend = engine(data, now: date(2026, 6, 22)).cashFlowTrend(months: 6)
        XCTAssertEqual(trend.count, 6)
        XCTAssertEqual(trend.last?.income, 100)
        XCTAssertEqual(trend.last?.expense, 40)
    }

    func testAssetAllocationFiltersZeroSlices() {
        let data = FinancialData(transactions: [tx(.income, 500, "X", date(2026, 6, 1))])
        let slices = engine(data, now: date(2026, 6, 22)).assetAllocation()
        XCTAssertEqual(slices.count, 1, "investments and crypto are zero, so only Cash remains")
        XCTAssertEqual(slices.first?.value, 500)
    }
}
