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

    func testCalculateTotalsExcludesFutureDatedTransactions() {
        // deep-audit L51: a transaction dated after today must not inflate today's total (it counts
        // once its day arrives), matching adjustHistoricalSnapshots' on/after-date behavior.
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 6, 10)),
            tx(.income, 5000, "Future paycheck", date(2026, 6, 20))
        ])
        let totals = engine(data, now: date(2026, 6, 15)).calculateTotals()
        XCTAssertEqual(totals.totalLiquidity, 1000, "the 6/20 income is in the future and excluded")
        XCTAssertEqual(totals.netWorth, 1000)
    }

    /// WC-#11: backfill snapshots are no longer stored; the chart carries the prior value forward to
    /// fill no-activity days, so two real snapshots 4 days apart still render a continuous flat line
    /// (not a slope), without a row per gap day in storage/iCloud.
    func testSnapshotsForChartCarriesForwardGapDays() {
        let snaps = [
            NetWorthSnapshot(date: date(2026, 6, 18), totalAssets: 100, totalLiabilities: 0, netWorth: 100, liquidity: 100, investments: 0, crypto: 0),
            NetWorthSnapshot(date: date(2026, 6, 22), totalAssets: 200, totalLiabilities: 0, netWorth: 200, liquidity: 200, investments: 0, crypto: 0)
        ]
        let points = engine(FinancialData(snapshots: snaps), now: date(2026, 6, 22))
            .snapshotsForChart(range: .all, currentNetWorth: 200)

        XCTAssertEqual(points.count, 5, "one point per day 18→22 inclusive")
        XCTAssertEqual(points.map(\.value), [100, 100, 100, 100, 200], "gap days carry the 18th's value forward (flat), not interpolated")
    }

    /// deep-audit M15/M16: a multi-year span must be downsampled so Swift Charts isn't handed
    /// thousands of daily marks, while the first (history start) and last (today) points survive.
    func testSnapshotsForChartDownsamplesLongSpans() {
        let start = date(2023, 1, 1)
        let end = date(2026, 1, 1) // ~1096 calendar days → >365 gap-filled points
        let snaps = [
            NetWorthSnapshot(date: start, totalAssets: 100, totalLiabilities: 0, netWorth: 100, liquidity: 100, investments: 0, crypto: 0),
            NetWorthSnapshot(date: end, totalAssets: 500, totalLiabilities: 0, netWorth: 500, liquidity: 500, investments: 0, crypto: 0)
        ]
        let points = engine(FinancialData(snapshots: snaps), now: end)
            .snapshotsForChart(range: .all, currentNetWorth: 500)

        XCTAssertGreaterThan(points.count, 1)
        XCTAssertLessThanOrEqual(points.count, 366, "long spans are strided down to ~365 points")
        XCTAssertEqual(points.first?.value, 100, "history start preserved")
        XCTAssertEqual(points.last?.value, 500, "today preserved")
    }

    /// WC-#16: the net-worth chart y-domain never traps on non-finite input (a NaN bound would crash
    /// the `ClosedRange`), and degrades to a safe default for empty / all-non-finite series.
    func testChartYDomainIsFiniteSafe() {
        func pts(_ values: [Double]) -> [NetWorthPoint] { values.map { NetWorthPoint(date: date(2026, 6, 1), value: $0) } }

        XCTAssertEqual(AnalyticsEngine.chartYDomain(for: []), 0...1, "empty → safe default")
        XCTAssertEqual(AnalyticsEngine.chartYDomain(for: pts([.nan, .infinity])), 0...1, "all non-finite → safe default")

        let domain = AnalyticsEngine.chartYDomain(for: pts([100, .nan, 200, .infinity]))
        XCTAssertTrue(domain.lowerBound.isFinite && domain.upperBound.isFinite, "non-finite values filtered → finite bounds")
        XCTAssertLessThan(domain.lowerBound, 100, "padded below the finite min")
        XCTAssertGreaterThan(domain.upperBound, 200, "padded above the finite max")
    }

    /// L31: a zero or near-zero net-worth series yields a readable band, not a sub-penny hairline axis.
    func testChartYDomainFloorsNearZeroSeries() {
        func pts(_ values: [Double]) -> [NetWorthPoint] { values.map { NetWorthPoint(date: date(2026, 6, 1), value: $0) } }

        let zero = AnalyticsEngine.chartYDomain(for: pts([0, 0, 0]))
        XCTAssertGreaterThanOrEqual(zero.upperBound - zero.lowerBound, 2, "all-zero series spans at least ~2 units")
        XCTAssertEqual((zero.lowerBound + zero.upperBound) / 2, 0, accuracy: 0.0001, "all-zero band is centred on 0")

        let negative = AnalyticsEngine.chartYDomain(for: pts([-0.5]))
        XCTAssertLessThan(negative.lowerBound, -1, "near-zero-negative net worth widens below -1, not a hairline")

        // A normal, wide series keeps its real scale (the floor doesn't kick in).
        let wide = AnalyticsEngine.chartYDomain(for: pts([1000, 5000]))
        XCTAssertLessThan(wide.lowerBound, 1000, "wide series padded below the min")
        XCTAssertGreaterThan(wide.upperBound, 5000, "wide series padded above the max")
        XCTAssertGreaterThan(wide.upperBound - wide.lowerBound, 4000, "wide series keeps its real scale, not the 2-unit floor")
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

    // MARK: - Snapshot history reconversion + backfill (deep-audit H11)

    private func usdRateConverter() -> CurrencyConverter {
        CurrencyConverter(snapshot: ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: ["USD": 1.25],
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "test"
        ))
    }

    func testSnapshotsReconvertFromCapturedCurrencyToDisplay() {
        // A history row captured while the base was USD (netWorth = 125 USD) must render as 100 EUR
        // when the display currency is EUR — before the fix it was read at the raw 125 scale.
        let usdSnap = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 125, totalLiabilities: 0,
            netWorth: 125, liquidity: 125, investments: 0, crypto: 0, currency: .usd
        )
        let engine = AnalyticsEngine(
            data: FinancialData(snapshots: [usdSnap]),
            converter: usdRateConverter(), displayCurrency: .eur, calendar: utc, now: date(2026, 6, 22)
        )
        XCTAssertEqual(engine.snapshots(range: .all).first?.value ?? 0, 100, accuracy: 0.01)
    }

    func testLegacySnapshotWithoutCurrencyIsReadAsDisplayCurrency() {
        // No captured currency → treated as already in the display currency (no conversion),
        // mirroring `displayAmount` for legacy transactions.
        let legacy = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 200, totalLiabilities: 0,
            netWorth: 200, liquidity: 200, investments: 0, crypto: 0
        )
        XCTAssertNil(legacy.currency)
        let engine = AnalyticsEngine(
            data: FinancialData(snapshots: [legacy]),
            converter: usdRateConverter(), displayCurrency: .eur, calendar: utc, now: date(2026, 6, 22)
        )
        XCTAssertEqual(engine.snapshots(range: .all).first?.value ?? 0, 200, accuracy: 0.01)
    }

    func testBackfillStampsLegacySnapshotsWithBaseCurrency() {
        let legacy = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 100, totalLiabilities: 0,
            netWorth: 100, liquidity: 100, investments: 0, crypto: 0
        )
        let tagged = NetWorthSnapshot(
            date: date(2026, 6, 2), totalAssets: 100, totalLiabilities: 0,
            netWorth: 100, liquidity: 100, investments: 0, crypto: 0, currency: .eur
        )
        let (migrated, changed) = FinancialData(snapshots: [legacy, tagged]).backfillingCurrencies(base: .usd)
        XCTAssertTrue(changed)
        XCTAssertEqual(migrated.snapshots.first(where: { $0.id == legacy.id })?.currency, .usd, "legacy row stamped with base")
        XCTAssertEqual(migrated.snapshots.first(where: { $0.id == tagged.id })?.currency, .eur, "already-tagged row untouched")
    }

    // MARK: - Same-day snapshot collapse (deep-audit H14)

    func testCollapsedByCalendarDayKeepsLatestPerDay() {
        let older = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 100, totalLiabilities: 0,
            netWorth: 100, liquidity: 100, investments: 0, crypto: 0, currency: .eur,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 200, totalLiabilities: 0,
            netWorth: 200, liquidity: 200, investments: 0, crypto: 0, currency: .eur,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let otherDay = NetWorthSnapshot(
            date: date(2026, 6, 2), totalAssets: 300, totalLiabilities: 0,
            netWorth: 300, liquidity: 300, investments: 0, crypto: 0, currency: .eur
        )
        let collapsed = [older, newer, otherDay].collapsedByCalendarDay(calendar: utc)
        XCTAssertEqual(collapsed.count, 2, "two 6/1 rows collapse to one; 6/2 stays")
        XCTAssertEqual(collapsed.first?.netWorth, 200, "the newer updatedAt wins for 6/1")
        XCTAssertEqual(collapsed.last?.netWorth, 300)
    }

    func testCollapseIsDeterministicRegardlessOfInputOrder() {
        // Two devices may hold the duplicate pair in different array orders; both must pick the same
        // survivor (id tie-break on equal updatedAt) so they don't ping-pong on every sync.
        let a = NetWorthSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: date(2026, 6, 1), totalAssets: 1, totalLiabilities: 0,
            netWorth: 1, liquidity: 1, investments: 0, crypto: 0,
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let b = NetWorthSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            date: date(2026, 6, 1), totalAssets: 2, totalLiabilities: 0,
            netWorth: 2, liquidity: 2, investments: 0, crypto: 0,
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let forward = [a, b].collapsedByCalendarDay(calendar: utc)
        let reversed = [b, a].collapsedByCalendarDay(calendar: utc)
        XCTAssertEqual(forward.first?.id, reversed.first?.id, "same survivor regardless of order")
        XCTAssertEqual(forward.first?.id, b.id, "equal updatedAt → greatest id wins")
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
        // `now` is the day AFTER the same-day pair so the collapsed value (the latest, 500) is
        // observable rather than being overwritten by the live "today" point. Gap day 6/21 carries
        // the prior value forward (WC-#11 render-time gap fill) and 6/23 aligns with the live total.
        let now = date(2026, 6, 23)
        let data = FinancialData(snapshots: [
            snapshot(2026, 6, 20, hour: 9, netWorth: 100),
            snapshot(2026, 6, 22, hour: 8, netWorth: 200),
            snapshot(2026, 6, 22, hour: 18, netWorth: 500)
        ])
        let points = engine(data, now: now).snapshotsForChart(range: .oneMonth, currentNetWorth: 999)
        // 6/22's two snapshots collapse to the latest (500); 6/21 carries 6/20 forward; 6/23 = live.
        XCTAssertEqual(points.map(\.value), [100, 100, 500, 999])
        XCTAssertEqual(points.last?.value, 999, "today aligns with live total")
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
        // The 6/21 NaN row is filtered out; the resulting gap day carries 6/20's value (100) forward
        // (WC-#11), and 6/22 is the live total — so the non-finite value never reaches the chart.
        XCTAssertEqual(points.map(\.value), [100, 100, 150])
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

    // MARK: - Previously-untested pure methods (foreign-currency exposure, monthly cash flow,
    //         raw snapshots(range:), and the four allocation breakdowns).

    private func investment(
        currentValue: Double = 100,
        currency: Currency = .eur,
        type: InvestmentType = .stock,
        geography: String = "US",
        sector: String = "Tech"
    ) -> Investment {
        Investment(
            type: type, symbol: "SYM", name: "Name", quantity: 1, costBasis: 0,
            currentValue: Decimal(currentValue), currentPrice: Decimal(currentValue),
            currency: currency, geography: geography, sector: sector, isin: "", fees: 0
        )
    }

    private func crypto(symbol: String = "BTC", currentValue: Double = 100, currency: Currency = .eur) -> CryptoHolding {
        // currentValue is computed (quantity * currentPrice).
        CryptoHolding(symbol: symbol, name: symbol, quantity: 1, avgBuyPrice: 0, currentPrice: Decimal(currentValue), currency: currency, fees: 0, coinId: "")
    }

    /// Foreign exposure is true if ANY investment / crypto / liability is held in a non-base
    /// currency; false only when everything is in the base currency (or there's nothing).
    func testHasForeignCurrencyExposureDetectsAnyNonBaseHolding() {
        let allEUR = FinancialData(
            investments: [investment(currency: .eur)],
            crypto: [crypto(currency: .eur)],
            liabilities: [Liability(name: "L", currentBalance: 100, currency: .eur)]
        )
        XCTAssertFalse(engine(allEUR, now: date(2026, 6, 22)).hasForeignCurrencyExposure(relativeTo: .eur))
        XCTAssertFalse(engine(FinancialData(), now: date(2026, 6, 22)).hasForeignCurrencyExposure(relativeTo: .eur), "empty → no exposure")

        // A single non-base holding in any bucket flips it to true.
        XCTAssertTrue(engine(FinancialData(investments: [investment(currency: .usd)]), now: date(2026, 6, 22)).hasForeignCurrencyExposure(relativeTo: .eur))
        XCTAssertTrue(engine(FinancialData(crypto: [crypto(currency: .usd)]), now: date(2026, 6, 22)).hasForeignCurrencyExposure(relativeTo: .eur))
        XCTAssertTrue(engine(FinancialData(liabilities: [Liability(name: "L", currentBalance: 1, currency: .usd)]), now: date(2026, 6, 22)).hasForeignCurrencyExposure(relativeTo: .eur))
    }

    /// `monthlyCashFlow` sums only the requested calendar month, split by type; prior/next-month
    /// transactions are excluded.
    func testMonthlyCashFlowSumsOnlyTheGivenMonthByType() {
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 6, 1)),
            tx(.income, 200, "Bonus", date(2026, 6, 28)),
            tx(.expense, 300, "Food", date(2026, 6, 15)),
            tx(.expense, 999, "Rent", date(2026, 5, 31)),   // previous month — excluded
            tx(.income, 500, "X", date(2026, 7, 1))          // next month — excluded
        ])
        let flow = engine(data, now: date(2026, 6, 22)).monthlyCashFlow(for: date(2026, 6, 10))
        XCTAssertEqual(flow.monthlyIncome, 1200)
        XCTAssertEqual(flow.monthlyExpenses, 300)
        XCTAssertEqual(flow.netSavings, 900)
    }

    /// `snapshots(range:)` keeps snapshots on/after the range cutoff (relative to `now`), sorts
    /// ascending, and maps each to its net-worth value.
    func testSnapshotsFiltersByRangeSortsAscendingAndMapsNetWorth() {
        let now = date(2026, 6, 22)
        let data = FinancialData(snapshots: [
            snapshot(2026, 6, 21, netWorth: 200),  // within a week
            snapshot(2026, 6, 10, netWorth: 150),  // within a month, outside a week
            snapshot(2026, 1, 1, netWorth: 100)    // outside a month
        ])
        XCTAssertEqual(engine(data, now: now).snapshots(range: .oneWeek).map(\.value), [200])
        XCTAssertEqual(engine(data, now: now).snapshots(range: .oneMonth).map(\.value), [150, 200], "ascending, week+month windows")
        XCTAssertEqual(engine(data, now: now).snapshots(range: .all).map(\.value), [100, 150, 200])
    }

    /// `investmentAllocation` groups by sector, sums (converted) value per sector, sorts descending.
    func testInvestmentAllocationGroupsBySectorSumsAndSortsDescending() {
        let data = FinancialData(investments: [
            investment(currentValue: 100, sector: "Tech"),
            investment(currentValue: 50, sector: "Tech"),
            investment(currentValue: 200, sector: "Energy")
        ])
        let slices = engine(data, now: date(2026, 6, 22)).investmentAllocation()
        XCTAssertEqual(slices.map(\.name), ["Energy", "Tech"], "sorted desc: Energy 200 > Tech 150")
        XCTAssertEqual(slices.map(\.value), [200, 150])
    }

    /// `investmentTypeAllocation` groups by type, sums, sorts descending, and labels each slice
    /// with the type's localized title.
    func testInvestmentTypeAllocationGroupsByTypeSumsAndLocalizesNames() {
        let data = FinancialData(investments: [
            investment(currentValue: 300, type: .etf),
            investment(currentValue: 100, type: .stock),
            investment(currentValue: 50, type: .stock)
        ])
        let slices = engine(data, now: date(2026, 6, 22)).investmentTypeAllocation()
        XCTAssertEqual(slices.map(\.value), [300, 150], "ETF 300 > Stock 150")
        XCTAssertEqual(slices.first?.name, InvestmentType.etf.localizedTitle(appLanguage: nil))
        XCTAssertEqual(slices.last?.name, InvestmentType.stock.localizedTitle(appLanguage: nil))
    }

    /// `investmentGeographyAllocation` groups by geography, sums, sorts descending.
    func testInvestmentGeographyAllocationGroupsByGeographySumsAndSorts() {
        let data = FinancialData(investments: [
            investment(currentValue: 100, geography: "US"),
            investment(currentValue: 250, geography: "EU"),
            investment(currentValue: 100, geography: "US")
        ])
        let slices = engine(data, now: date(2026, 6, 22)).investmentGeographyAllocation()
        XCTAssertEqual(slices.map(\.name), ["EU", "US"], "EU 250 > US 200")
        XCTAssertEqual(slices.map(\.value), [250, 200])
    }

    /// `cryptoAllocation` emits one slice per holding (by symbol), drops zero-value holdings, sorts
    /// descending.
    func testCryptoAllocationSlicesPerHoldingFiltersZeroAndSortsDescending() {
        let data = FinancialData(crypto: [
            crypto(symbol: "BTC", currentValue: 500),
            crypto(symbol: "ETH", currentValue: 800),
            crypto(symbol: "DOGE", currentValue: 0)  // zero → filtered out
        ])
        let slices = engine(data, now: date(2026, 6, 22)).cryptoAllocation()
        XCTAssertEqual(slices.map(\.name), ["ETH", "BTC"], "sorted desc; zero-value DOGE filtered")
        XCTAssertEqual(slices.map(\.value), [800, 500])
    }

    /// Allocation values are expressed in the display currency: a USD holding is converted via FX.
    func testCryptoAllocationConvertsToDisplayCurrency() {
        let converter = CurrencyConverter(snapshot: ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: ["USD": 1.25],
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "test"
        ))
        let data = FinancialData(crypto: [crypto(symbol: "BTC", currentValue: 125, currency: .usd)])
        let slices = AnalyticsEngine(
            data: data, converter: converter, displayCurrency: .eur, calendar: utc, now: date(2026, 6, 22)
        ).cryptoAllocation()
        XCTAssertEqual(slices.first?.value ?? 0, 100, accuracy: 0.01, "125 USD ÷ 1.25 = 100 EUR")
    }
}
