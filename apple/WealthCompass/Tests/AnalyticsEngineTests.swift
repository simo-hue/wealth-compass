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
        Transaction(type: type, category: category, amount: Decimal(amount), description: "", date: when)
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

    func testCalculateTotalsConvertsTransactionsByOwnCurrency() {
        // WC-M1: each transaction converts from its own currency to the display currency
        // before summing into cash/liquidity.
        let converter = CurrencyConverter(snapshot: ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: ["USD": 1.25],
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "test"
        ))
        var eurTx = tx(.income, 100, "Salary", date(2026, 6, 1)); eurTx.currency = .eur
        var usdTx = tx(.income, 125, "Bonus", date(2026, 6, 2)); usdTx.currency = .usd
        let totals = AnalyticsEngine(
            data: FinancialData(transactions: [eurTx, usdTx]),
            converter: converter, displayCurrency: .eur, calendar: utc, now: date(2026, 6, 22)
        ).calculateTotals()
        // 100 EUR + (125 USD ÷ 1.25) = 200 EUR
        XCTAssertEqual(totals.totalLiquidity.doubleValue, 200, accuracy: 0.01)
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

    private func snapshot(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0,
        netWorth: Double
    ) -> NetWorthSnapshot {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        let when = utc.date(from: comps)!
        return NetWorthSnapshot(
            date: when,
            totalAssets: Decimal(netWorth),
            totalLiabilities: 0,
            netWorth: Decimal(netWorth),
            liquidity: Decimal(netWorth),
            investments: 0,
            crypto: 0
        )
    }

    func testSnapshotsForChartCollapsesSameDayToLatest() {
        let now = date(2026, 6, 22)
        let data = FinancialData(snapshots: [
            snapshot(2026, 6, 20, hour: 9, netWorth: 100),
            snapshot(2026, 6, 22, hour: 8, netWorth: 200),
            snapshot(2026, 6, 22, hour: 18, netWorth: 500)
        ])
        let points = engine(data, now: now).snapshotsForChart(range: .oneMonth, currentNetWorth: 999)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.value, 999, "today aligns with live total")
        XCTAssertEqual(points[0].value, 100)
    }

    func testSnapshotsForChartFiltersNonFiniteValues() {
        let now = date(2026, 6, 22)
        let data = FinancialData(snapshots: [
            snapshot(2026, 6, 20, netWorth: 100),
            NetWorthSnapshot(
                date: date(2026, 6, 21),
                totalAssets: 0,
                totalLiabilities: 0,
                // Decimal can't hold a float-literal NaN; use the NSDecimalNumber NaN whose
                // doubleValue is NaN, so the chart's `.isFinite` filter is still exercised.
                netWorth: NSDecimalNumber.notANumber.decimalValue,
                liquidity: 0,
                investments: 0,
                crypto: 0
            )
        ])
        let points = engine(data, now: now).snapshotsForChart(range: .oneMonth, currentNetWorth: 150)
        XCTAssertEqual(points.map(\.value), [100, 150])
    }

    func testSnapshotsForChartBackfillLikeSeriesHasOnePointPerDay() {
        let now = date(2026, 6, 22)
        var snapshots: [NetWorthSnapshot] = []
        for day in 18...21 {
            snapshots.append(snapshot(2026, 6, day, hour: 23, minute: 59, netWorth: 1_000))
            snapshots.append(snapshot(2026, 6, day, hour: 11, netWorth: 1_000))
        }
        snapshots.append(snapshot(2026, 6, 22, hour: 10, netWorth: 5_000))

        let data = FinancialData(snapshots: snapshots)
        let points = engine(data, now: now).snapshotsForChart(range: .oneMonth, currentNetWorth: 827_000)

        XCTAssertEqual(points.count, 5, "18, 19, 20, 21, 22")
        XCTAssertEqual(Set(points.map { utc.startOfDay(for: $0.date) }).count, 5)
        XCTAssertEqual(points.last?.value, 827_000)
    }
}
