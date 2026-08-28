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

    // MARK: - Period windows

    /// "Last 7 Days" must cover seven calendar days, not eight.
    ///
    /// The window was built as `now - 7 days` and then compared inclusively at *both* ends, so a
    /// span already seven days long admitted an eighth. Every relative period had the same off-by-one.
    func testRelativePeriodsCoverExactlyTheirOwnLength() {
        let today = date(2026, 8, 24)
        // One expense per day for the twelve days ending today.
        let rows = (0..<12).compactMap { offset -> Transaction? in
            guard let day = utc.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return tx(.expense, 100, "Food", day)
        }
        let engine = engine(FinancialData(transactions: rows), now: today)

        XCTAssertEqual(
            engine.expensesByCategory(period: .sevenDays).first?.value, 700,
            "Last 7 Days counted a day it should not have"
        )
        XCTAssertEqual(engine.expensesByCategory(period: .thirtyDays).first?.value, 1200)
    }

    /// Future-dated rows are excluded from every period — including All Time.
    ///
    /// `.all` returned the raw array, so the same screen showed one figure in the category donut and
    /// another in the Money Flow diagram beside it, which re-clamps to today for exactly this reason.
    /// `calculateTotals` has excluded them since deep-audit L51.
    func testAllTimeExcludesFutureDatedTransactionsLikeEveryOtherPeriod() {
        let today = date(2026, 8, 24)
        let data = FinancialData(transactions: [
            tx(.expense, 100, "Food", date(2026, 8, 1)),
            tx(.expense, 900, "Rent", date(2026, 12, 1)),
        ])
        let engine = engine(data, now: today)

        XCTAssertEqual(
            engine.expensesByCategory(period: .all).map(\.value), [100],
            "All Time counted spending that has not happened yet"
        )
        // The two views of the same period must agree.
        let sankeyOutflow = engine.cashFlowSankey(period: .all).outflows
            .filter { $0.role == .expense }
            .reduce(0.0) { $0 + $1.value }
        XCTAssertEqual(sankeyOutflow, 100, accuracy: 0.001)
    }

    /// The dashboard must not contradict itself about money that has not moved yet.
    ///
    /// `calculateTotals` excluded future-dated rows (deep-audit L51) while `monthlyCashFlow` and
    /// `cashFlowTrend` counted them, so one screen showed Cash 1 000 in the header and Monthly
    /// Income 4 000 in the card beneath it. `ReportDocumentBuilder` documented this and worked
    /// around it with a private settled engine — for the PDF only.
    func testMonthlyCashFlowAndTrendExcludeFutureDatedRows() {
        let today = date(2026, 8, 24)
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 8, 1)),
            tx(.income, 3000, "Invoice", date(2026, 8, 30)),
            tx(.expense, 200, "Food", date(2026, 8, 2)),
            tx(.expense, 500, "Rent", date(2026, 8, 31)),
        ])
        let engine = engine(data, now: today)

        XCTAssertEqual(engine.calculateTotals().totalLiquidity, 800)
        XCTAssertEqual(engine.monthlyCashFlow(for: today).monthlyIncome, 1000, "income card counts unsettled money")
        XCTAssertEqual(engine.monthlyCashFlow(for: today).monthlyExpenses, 200, "expense card counts unsettled money")
        XCTAssertEqual(engine.cashFlowTrend(months: 1).first?.income ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(engine.cashFlowTrend(months: 1).first?.expense ?? 0, 200, accuracy: 0.001)
    }

    /// Holdings rank by what they are worth, not by the size of their raw number.
    ///
    /// Sorting `currentValue` directly compares figures denominated in different currencies, so a
    /// ¥1,000,000 position (≈ €6,000) outranked a €50,000 one — while every value rendered on those
    /// same rows is converted, making the order contradict the numbers beside it. The Overview grids
    /// take only the top five or six, so a genuinely larger holding could vanish from "Top Holdings".
    func testHoldingsRankByConvertedValue() {
        let converter = CurrencyConverter(snapshot: nil)
        let convert: (Decimal, Currency) -> Decimal = { converter.convert($0, from: $1, to: .eur) }

        let yen = Investment(type: .stock, symbol: "JPY1", name: "Yen position", quantity: 1,
                             costBasis: 0, currentValue: 1_000_000, currentPrice: 1_000_000,
                             currency: .jpy, geography: "JP", sector: "Tech", isin: "", fees: 0)
        let euro = Investment(type: .stock, symbol: "EUR1", name: "Euro position", quantity: 1,
                              costBasis: 0, currentValue: 50_000, currentPrice: 50_000,
                              currency: .eur, geography: "EU", sector: "Tech", isin: "", fees: 0)

        XCTAssertEqual(
            [yen, euro].rankedByValue(convert).map(\.symbol), ["EUR1", "JPY1"],
            "ranked by the raw number instead of the converted value"
        )
    }

    /// Equal-valued holdings keep a stable order rather than shuffling between renders.
    func testEqualValuedHoldingsBreakTiesDeterministically() {
        let convert: (Decimal, Currency) -> Decimal = { value, _ in value }
        let b = Investment(type: .stock, symbol: "BBB", name: "B", quantity: 1, costBasis: 0,
                           currentValue: 100, currentPrice: 100, currency: .eur,
                           geography: "", sector: "", isin: "", fees: 0)
        let a = Investment(type: .stock, symbol: "AAA", name: "A", quantity: 1, costBasis: 0,
                           currentValue: 100, currentPrice: 100, currency: .eur,
                           geography: "", sector: "", isin: "", fees: 0)
        XCTAssertEqual([b, a].rankedByValue(convert).map(\.symbol), ["AAA", "BBB"])
    }

    /// The transaction lists and the analytics must agree on where a period starts.
    ///
    /// They were three separate copies of the rule and all three disagreed: the engine counted N
    /// days, the Mac list N+1 snapped to midnight, the iOS list N+1 unsnapped. Drilling into a
    /// Money Flow node therefore listed more rows, and a larger sum, than the node itself.
    func testPeriodWindowIsOneDefinition() {
        let now = date(2026, 8, 24)
        XCTAssertEqual(AnalyticsPeriod.sevenDays.firstIncludedDay(relativeTo: now, calendar: utc),
                       utc.startOfDay(for: date(2026, 8, 18)))
        XCTAssertEqual(AnalyticsPeriod.thirtyDays.firstIncludedDay(relativeTo: now, calendar: utc),
                       utc.startOfDay(for: date(2026, 7, 26)))
        XCTAssertNil(AnalyticsPeriod.all.firstIncludedDay(relativeTo: now, calendar: utc))

        // Year to date still starts on 1 January.
        XCTAssertEqual(AnalyticsPeriod.yearToDate.firstIncludedDay(relativeTo: now, calendar: utc),
                       utc.startOfDay(for: date(2026, 1, 1)))

        // And the window the engine actually applies matches it, day for day.
        let rows = (0..<10).compactMap { offset -> Transaction? in
            utc.date(byAdding: .day, value: -offset, to: now).map { tx(.expense, 10, "Food", $0) }
        }
        let counted = engine(FinancialData(transactions: rows), now: now)
            .expensesByCategory(period: .sevenDays).first?.value ?? 0
        XCTAssertEqual(counted, 70, accuracy: 0.001, "the engine counted a different number of days")
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

    // MARK: - #9: the currency backfill must not race across devices

    /// #9a truth table. The backfill stamps legacy rows with THIS device's base currency — a setting
    /// that deliberately does not sync — and records the result as an authoritative local edit, so a
    /// sync-enabled device must not run it before it has seen the server's copy of those rows.
    func testShouldBackfillCurrenciesWaitsForBootstrapOnlyWhenSyncing() {
        XCTAssertTrue(
            FinancialData.shouldBackfillCurrencies(isSyncEnabled: false, bootstrapCompleted: false),
            "With sync off there is no other device to disagree with — stamp immediately, as before."
        )
        XCTAssertTrue(FinancialData.shouldBackfillCurrencies(isSyncEnabled: false, bootstrapCompleted: true))
        XCTAssertFalse(
            FinancialData.shouldBackfillCurrencies(isSyncEnabled: true, bootstrapCompleted: false),
            "Syncing but never merged with the server: defer to the next launch rather than guess."
        )
        XCTAssertTrue(FinancialData.shouldBackfillCurrencies(isSyncEnabled: true, bootstrapCompleted: true))
    }

    /// #9b: stamping must bump `updatedAt`, and must leave an already-stamped row completely alone.
    ///
    /// Without the bump the stamped copy kept its original timestamp, so the other device's
    /// unstamped copy of the same record tied it exactly and the merge fell through to its
    /// payload-hash tie-break — which is how the currency ended up decided by a coin flip.
    func testBackfillStampsCurrencyAndUpdatedAtInOnePass() throws {
        let stampedAt = Date(timeIntervalSince1970: 9_000)
        let original = Date(timeIntervalSince1970: 1_000)
        let legacyTransaction = Transaction(
            type: .income, category: "Salary", amount: 10, description: "",
            date: date(2026, 6, 1), createdAt: original, updatedAt: original
        )
        let legacySnapshot = NetWorthSnapshot(
            date: date(2026, 6, 1), totalAssets: 100, totalLiabilities: 0,
            netWorth: 100, liquidity: 100, investments: 0, crypto: 0,
            createdAt: original, updatedAt: original
        )
        let alreadyTagged = NetWorthSnapshot(
            date: date(2026, 6, 2), totalAssets: 100, totalLiabilities: 0,
            netWorth: 100, liquidity: 100, investments: 0, crypto: 0, currency: .eur,
            createdAt: original, updatedAt: original
        )

        let (migrated, changed) = FinancialData(
            transactions: [legacyTransaction],
            snapshots: [legacySnapshot, alreadyTagged]
        ).backfillingCurrencies(base: .usd, now: stampedAt)

        XCTAssertTrue(changed)
        XCTAssertEqual(migrated.transactions[0].currency, .usd)
        XCTAssertEqual(migrated.transactions[0].updatedAt, stampedAt, "A stamped row must be strictly newer than the copy it collides with.")
        let stamped = try XCTUnwrap(migrated.snapshots.first { $0.id == legacySnapshot.id })
        XCTAssertEqual(stamped.currency, .usd)
        XCTAssertEqual(stamped.updatedAt, stampedAt)
        let untouched = try XCTUnwrap(migrated.snapshots.first { $0.id == alreadyTagged.id })
        XCTAssertEqual(untouched.currency, .eur, "An already-stamped row must not be re-stamped…")
        XCTAssertEqual(untouched.updatedAt, original, "…and its timestamp must not move either.")
    }

    /// The edge #9b opens, and the reason every row in the pass shares one `now`.
    ///
    /// `updatedAt` is the primary key of `supersedesForCollapse`, so bumping it changes which
    /// same-day snapshot survives a collapse. Two legacy rows stamped in the same pass must stay
    /// *tied* there, so the collapse falls through to `date` and then `id` — a rule computed from
    /// the rows themselves, which every device therefore resolves identically. Per-row timestamps
    /// would instead hand the decision to iteration order, and two devices would disagree.
    ///
    /// The pair here is deliberately arranged so the two rules disagree: the row with the *older*
    /// original `updatedAt` carries the *greater* id. Recency would keep `recentlyEdited`; the tie
    /// plus the id tie-break keeps `editedLongAgo`. That is a real change in which legacy same-day
    /// row survives — it applies only to rows that predate the currency field *and* share a day,
    /// and what matters is that it is convergent rather than order-dependent.
    func testStampingLeavesTwoLegacySameDayRowsTiedOnUpdatedAt() throws {
        let day = date(2026, 6, 1)
        let recentlyEdited = NetWorthSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: day, totalAssets: 1, totalLiabilities: 0, netWorth: 1, liquidity: 1,
            investments: 0, crypto: 0, updatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let editedLongAgo = NetWorthSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            date: day, totalAssets: 2, totalLiabilities: 0, netWorth: 2, liquidity: 2,
            investments: 0, crypto: 0, updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(
            [recentlyEdited, editedLongAgo].collapsedByCalendarDay(calendar: utc).first?.id,
            recentlyEdited.id,
            "Unstamped, recency decides."
        )

        let (migrated, _) = FinancialData(snapshots: [recentlyEdited, editedLongAgo])
            .backfillingCurrencies(base: .usd, now: Date(timeIntervalSince1970: 9_000))
        let stampedRecent = try XCTUnwrap(migrated.snapshots.first { $0.id == recentlyEdited.id })
        let stampedOld = try XCTUnwrap(migrated.snapshots.first { $0.id == editedLongAgo.id })

        XCTAssertEqual(stampedRecent.updatedAt, stampedOld.updatedAt, "One pass, one instant — the pair must stay tied.")
        XCTAssertTrue(stampedOld.supersedesForCollapse(stampedRecent), "Tied on updatedAt and date, the greater id wins.")
        // And the same answer whichever order the rows arrive in, on either device.
        XCTAssertEqual(
            migrated.snapshots.collapsedByCalendarDay(calendar: utc).first?.id,
            migrated.snapshots.reversed().collapsedByCalendarDay(calendar: utc).first?.id
        )
        XCTAssertEqual(migrated.snapshots.collapsedByCalendarDay(calendar: utc).first?.id, editedLongAgo.id)
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
    /// transactions are excluded. Every row here is dated on or before `now`, so this covers month
    /// filtering alone — settlement is covered by
    /// `testMonthlyCashFlowAndTrendExcludeFutureDatedRows`.
    func testMonthlyCashFlowSumsOnlyTheGivenMonthByType() {
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 6, 1)),
            tx(.income, 200, "Bonus", date(2026, 6, 20)),   // same month, already settled
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

    // MARK: - Money Flow (Sankey)

    /// The invariant the whole diagram rests on. `SankeyLayout` stacks ribbons against the hub edge
    /// by cursor, so any drift here renders as a bare stretch of hub.
    private func assertConserved(_ sankey: CashFlowSankey, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let inflow = sankey.inflows.reduce(0) { $0 + $1.value }
        let outflow = sankey.outflows.reduce(0) { $0 + $1.value }
        XCTAssertEqual(inflow, sankey.total, accuracy: 1e-9, "\(label): inflows reach the hub", file: file, line: line)
        XCTAssertEqual(outflow, sankey.total, accuracy: 1e-9, "\(label): outflows reach the hub", file: file, line: line)
        // Ids feed `ForEach`; a node collision silently drops a node, and because a link's id is
        // derived from its endpoints', it drops a whole ribbon of real money too.
        XCTAssertEqual(Set(sankey.nodes.map(\.id)).count, sankey.nodes.count, "\(label): node ids unique", file: file, line: line)
        XCTAssertEqual(Set(sankey.links.map(\.id)).count, sankey.links.count, "\(label): link ids unique", file: file, line: line)
        XCTAssertTrue(sankey.nodes.allSatisfy { $0.share.isFinite }, "\(label): shares finite", file: file, line: line)
    }

    func testCashFlowSankeySurplusMonth() {
        let data = FinancialData(transactions: [
            tx(.income, 17248, "Salary", date(2026, 7, 2)),
            tx(.income, 1419, "Freelance", date(2026, 7, 5)),
            tx(.expense, 9559, "Housing", date(2026, 7, 3)),
            tx(.expense, 761, "Food", date(2026, 7, 8)),
        ])
        let sankey = engine(data, now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays)

        XCTAssertEqual(sankey.total, 18667, accuracy: 0.001, "hub is total income")
        XCTAssertEqual(sankey.inflows.map(\.title), ["Salary", "Freelance"], "ranked descending")
        XCTAssertEqual(sankey.outflows.map(\.role), [.expense, .expense, .surplus], "surplus pinned last")
        XCTAssertEqual(sankey.outflows.last?.value ?? 0, 8347, accuracy: 0.001, "surplus = income − expenses")
        XCTAssertFalse(sankey.outflows.last?.isDrillable ?? true, "surplus has no rows behind it")
        assertConserved(sankey, "surplus")
    }

    func testCashFlowSankeyDeficitMonthDrawsFromSavings() {
        let data = FinancialData(transactions: [
            tx(.income, 2000, "Salary", date(2026, 7, 2)),
            tx(.expense, 3500, "Housing", date(2026, 7, 3)),
        ])
        let sankey = engine(data, now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays)

        XCTAssertEqual(sankey.total, 3500, accuracy: 0.001, "hub is total spending when overspending")
        XCTAssertEqual(sankey.inflows.map(\.role), [.income, .shortfall])
        XCTAssertEqual(sankey.inflows.last?.value ?? 0, 1500, accuracy: 0.001)
        XCTAssertFalse(sankey.outflows.contains { $0.role == .surplus }, "surplus and shortfall are exclusive")
        assertConserved(sankey, "deficit")
    }

    /// The imbalance threshold has to be *relative*. A fixed half-cent floor is both too coarse for
    /// a sub-cent month — where a real imbalance is most of the diagram — and too fine at 1e14,
    /// where pure `Double` summation residue exceeds it and draws a hairline "€0.00" ribbon.
    func testCashFlowSankeyConservesAtBothExtremesOfMagnitude() {
        for (income, expense) in [(0.01, 0.006), (0.006, 0.002), (0.002, 0.006), (1000.0, 999.996)] {
            let data = FinancialData(transactions: [
                tx(.income, income, "Salary", date(2026, 7, 2)),
                tx(.expense, expense, "Housing", date(2026, 7, 3)),
            ])
            assertConserved(
                engine(data, now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays),
                "tiny \(income)/\(expense)"
            )
        }

        let third = 111_111_111_111_111.11
        let huge = FinancialData(transactions: [
            tx(.income, third * 3, "Salary", date(2026, 7, 2)),
            tx(.expense, third, "Housing", date(2026, 7, 3)),
            tx(.expense, third, "Food", date(2026, 7, 4)),
            tx(.expense, third, "Transport", date(2026, 7, 5)),
        ])
        let sankey = engine(huge, now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays)
        XCTAssertFalse(sankey.outflows.contains { $0.role == .surplus }, "float residue is not a surplus")
        XCTAssertFalse(sankey.inflows.contains { $0.role == .shortfall }, "float residue is not a shortfall")
        assertConserved(sankey, "1e14")
    }

    func testCashFlowSankeyFoldsTheLongTail() {
        var rows = [tx(.income, 50_000, "Salary", date(2026, 7, 1))]
        for index in 1...12 {
            rows.append(tx(.expense, Double(1000 - index * 50), "Cat\(String(format: "%02d", index))", date(2026, 7, 2)))
        }
        let sankey = engine(FinancialData(transactions: rows), now: date(2026, 7, 29))
            .cashFlowSankey(period: .thirtyDays)

        let expenses = sankey.outflows.filter { $0.role == .expense }
        XCTAssertEqual(expenses.count, 8, "top 7 plus one bucket")
        let bucket = expenses.last
        XCTAssertTrue(bucket?.isFolded ?? false)
        XCTAssertEqual(bucket?.categories.count, 5)
        XCTAssertEqual(bucket?.value ?? 0, bucket?.folded.reduce(0) { $0 + $1.value } ?? -1, accuracy: 0.001)
        XCTAssertTrue(bucket?.isDrillable ?? false, "the bucket filters to all of its categories")
        XCTAssertNil(bucket?.colorIndex, "the bucket is styled neutrally, not from the palette")
        assertConserved(sankey, "fold")
    }

    /// A lone leftover keeps its own node: replacing one category with "Smaller categories" hides
    /// its name and buys no room.
    func testCashFlowSankeyDoesNotFoldASingleLeftover() {
        var rows = [tx(.income, 50_000, "Salary", date(2026, 7, 1))]
        for index in 1...8 { rows.append(tx(.expense, Double(1000 - index * 50), "Cat\(index)", date(2026, 7, 2))) }
        let sankey = engine(FinancialData(transactions: rows), now: date(2026, 7, 29))
            .cashFlowSankey(period: .thirtyDays)

        let expenses = sankey.outflows.filter { $0.role == .expense }
        XCTAssertEqual(expenses.count, 8)
        XCTAssertFalse(expenses.contains(where: \.isFolded))
    }

    /// "Other" is a default category on both sides *and* the fallback every import path writes, so
    /// it must rank on its own merits and never merge into the synthetic bucket.
    func testCashFlowSankeyKeepsARealOtherCategorySeparateFromTheBucket() {
        var rows = [
            tx(.income, 50_000, "Salary", date(2026, 7, 1)),
            tx(.expense, 10_034, "Other", date(2026, 7, 2)),
        ]
        for index in 1...12 {
            rows.append(tx(.expense, Double(500 - index * 20), "Cat\(String(format: "%02d", index))", date(2026, 7, 2)))
        }
        let sankey = engine(FinancialData(transactions: rows), now: date(2026, 7, 29))
            .cashFlowSankey(period: .thirtyDays)

        XCTAssertEqual(sankey.outflows.first?.title, "Other", "ranks first on value")
        XCTAssertEqual(sankey.outflows.first?.value ?? 0, 10_034, accuracy: 0.001)
        XCTAssertFalse(sankey.outflows.first?.isFolded ?? true)
        XCTAssertFalse(sankey.outflows.first { $0.isFolded }?.categories.contains("Other") ?? true)
        assertConserved(sankey, "real Other")
    }

    /// Real category ids are namespaced away from the synthetic ones, so a category literally named
    /// "folded" cannot collide with the bucket — which would take a ribbon down with it.
    func testCashFlowSankeySurvivesACategoryNamedFolded() {
        var rows = [
            tx(.income, 50_000, "Salary", date(2026, 7, 1)),
            tx(.expense, 9_999, "folded", date(2026, 7, 2)),
            tx(.expense, 8_000, "cat-folded", date(2026, 7, 2)),
        ]
        for index in 1...12 {
            rows.append(tx(.expense, Double(500 - index * 20), "Cat\(String(format: "%02d", index))", date(2026, 7, 2)))
        }
        let sankey = engine(FinancialData(transactions: rows), now: date(2026, 7, 29))
            .cashFlowSankey(period: .thirtyDays)

        XCTAssertTrue(sankey.outflows.contains { $0.title == "folded" && !$0.isFolded })
        XCTAssertTrue(sankey.outflows.contains(where: \.isFolded))
        assertConserved(sankey, "folded collision")
    }

    func testCashFlowSankeyClampsFutureDatedRowsOnEveryPeriod() {
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 7, 1)),
            tx(.income, 5000, "Salary", date(2026, 12, 1)),   // post-dated recurring occurrence
            tx(.expense, 300, "Housing", date(2026, 7, 2)),
        ])
        for period in [AnalyticsPeriod.all, .yearToDate, .thirtyDays] {
            let sankey = engine(data, now: date(2026, 7, 29)).cashFlowSankey(period: period)
            XCTAssertEqual(sankey.total, 1000, accuracy: 0.001, "\(period.rawValue) excludes the future")
            assertConserved(sankey, period.rawValue)
        }
    }

    func testCashFlowSankeyDropsNonPositiveAndLabelsBlankCategories() {
        let data = FinancialData(transactions: [
            tx(.income, 1000, "Salary", date(2026, 7, 1)),
            tx(.expense, 500, "Housing", date(2026, 7, 2)),
            tx(.expense, -500, "Refund", date(2026, 7, 3)),
            tx(.expense, 0, "Zero", date(2026, 7, 4)),
            tx(.expense, 200, "", date(2026, 7, 5)),
        ])
        let sankey = engine(data, now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays)

        XCTAssertTrue(sankey.outflows.allSatisfy { $0.value > 0 }, "a negative ribbon has no geometry")
        XCTAssertFalse(sankey.outflows.contains { $0.title == "Refund" || $0.title == "Zero" })
        let blank = sankey.outflows.first { $0.categories == [""] }
        XCTAssertNotNil(blank, "a blank category still gets a node")
        XCTAssertFalse(blank?.title.isEmpty ?? true, "and a readable title rather than an empty box")
        assertConserved(sankey, "non-positive")
    }

    /// `Int.max` as a "never fold" sentinel used to overflow `limit + 1` and trap.
    func testCashFlowSankeyToleratesAnUnboundedNodeLimit() {
        var rows = [tx(.income, 5000, "Salary", date(2026, 7, 1))]
        for index in 1...13 { rows.append(tx(.expense, Double(100 + index), "Cat\(index)", date(2026, 7, 2))) }
        let sankey = engine(FinancialData(transactions: rows), now: date(2026, 7, 29))
            .cashFlowSankey(period: .thirtyDays, maxNodesPerSide: .max)

        XCTAssertEqual(sankey.outflows.filter { $0.role == .expense }.count, 13, "nothing folded")
        assertConserved(sankey, "Int.max")
    }

    func testCashFlowSankeyIsEmptyWithoutTransactions() {
        let sankey = engine(FinancialData(), now: date(2026, 7, 29)).cashFlowSankey(period: .thirtyDays)
        XCTAssertTrue(sankey.isEmpty)
        XCTAssertTrue(sankey.inflows.isEmpty && sankey.outflows.isEmpty && sankey.links.isEmpty)
    }

    /// `Decimal` addition returns NaN on overflow rather than trapping, and these values feed
    /// `SectorMark` geometry directly.
    func testExpensesByCategoryDropsOverflowedTotals() {
        let huge = Decimal.greatestFiniteMagnitude
        let data = FinancialData(transactions: [
            Transaction(type: .expense, category: "Overflow", amount: huge, description: "", date: date(2026, 7, 2)),
            Transaction(type: .expense, category: "Overflow", amount: huge, description: "", date: date(2026, 7, 3)),
            tx(.expense, 400, "Housing", date(2026, 7, 4)),
        ])
        let categories = engine(data, now: date(2026, 7, 29)).expensesByCategory(period: .thirtyDays)

        XCTAssertTrue(categories.allSatisfy { $0.value.isFinite }, "no NaN value reaches the chart")
        XCTAssertTrue(categories.allSatisfy { $0.percentage.isFinite }, "no NaN percentage reaches the chart")
        XCTAssertFalse(categories.contains { $0.name == "Overflow" })
        XCTAssertEqual(categories.first?.percentage ?? 0, 100, accuracy: 0.001, "percentages recomputed over the survivors")
    }

    // MARK: - Net-worth movement (dashboard hero)

    private func point(_ year: Int, _ month: Int, _ day: Int, _ value: Double) -> NetWorthPoint {
        NetWorthPoint(date: date(year, month, day), value: value)
    }

    /// A window that opens at zero has no baseline, and must not claim one.
    ///
    /// The hero printed the amount and the percentage side by side, and the percentage collapsed a
    /// near-zero opening value to a hard `0` — so a first snapshot of €0 followed by €10 000 of
    /// positions rendered "↑ €10 000.00 · 0.0% · 1W": a real movement labelled as no movement. The
    /// amount is still exact; only the ratio is unavailable, and `nil` is how the hero knows to
    /// draw an em dash instead of a number.
    func testNetWorthChangeReportsNoPercentageWhenTheWindowOpensAtZero() {
        let change = AnalyticsEngine.netWorthChange(in: [
            point(2026, 8, 1, 0),
            point(2026, 8, 8, 10_000),
        ])

        XCTAssertEqual(change?.value, 10_000, "the amount moved and must still be reported")
        XCTAssertNil(change?.percentage, "no baseline to express €10 000 as a share of")
    }

    /// The `> 1` floor is the definition of "near zero" and is unchanged by the fix — only what
    /// happens below it moved, from a misleading `0` to `nil`.
    func testNetWorthChangeReportsNoPercentageForASubUnitBaseline() {
        XCTAssertNil(
            AnalyticsEngine.netWorthChange(in: [point(2026, 8, 1, 0.5), point(2026, 8, 8, 500)])?.percentage,
            "a €0.50 opening value is not a baseline; 99 900% is not a useful number"
        )
        XCTAssertEqual(
            AnalyticsEngine.netWorthChange(in: [point(2026, 8, 1, 100), point(2026, 8, 8, 150)])?.percentage ?? 0,
            50, accuracy: 0.0001, "an ordinary window still reports its percentage"
        )
    }

    /// A negative opening value divides by its magnitude, so recovering toward zero reads positive.
    func testNetWorthChangeKeepsTheSignOfTheMovementNotOfTheBaseline() {
        let change = AnalyticsEngine.netWorthChange(in: [point(2026, 8, 1, -200), point(2026, 8, 8, -100)])
        XCTAssertEqual(change?.value ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(change?.percentage ?? 0, 50, accuracy: 0.0001, "debt halved is a 50% gain, not a loss")
    }

    /// Nothing at all to measure: no points, one point, or every point on the same day.
    func testNetWorthChangeIsNilWithoutASpanToMeasure() {
        XCTAssertNil(AnalyticsEngine.netWorthChange(in: []))
        XCTAssertNil(AnalyticsEngine.netWorthChange(in: [point(2026, 8, 1, 100)]))
        XCTAssertNil(
            AnalyticsEngine.netWorthChange(in: [point(2026, 8, 1, 100), point(2026, 8, 1, 400)]),
            "same date at both ends is not a window"
        )
    }

    // MARK: - Aggregate gain percentage (portfolio summaries)

    /// "No cost basis" is not "0% performance".
    ///
    /// The four portfolio summaries guarded on `costBasis > 0` and fell back to `0`, which the
    /// Performance card rendered as an ordinary "0.0%" under a green up-arrow — beside a Profit /
    /// Loss card showing a real gain. Reachable without anything exotic: the add form accepts a
    /// blank average buy price (only *both* prices blank is rejected).
    func testGainPercentIsUnavailableWithoutACostBasis() {
        XCTAssertNil(AnalyticsEngine.gainPercent(gain: 1_500, costBasis: 0))
        XCTAssertNil(AnalyticsEngine.gainPercent(gain: 0, costBasis: 0))
    }

    /// And where there *is* a basis it must agree with the rows underneath it, which have guarded
    /// on `!= 0` and divided by the magnitude since M10.
    func testGainPercentAgreesWithThePerRowGainLossPercent() {
        let holding = Investment(
            type: .stock, symbol: "SYM", name: "Name", quantity: 1, costBasis: 800,
            currentValue: 1_000, currentPrice: 1_000, currency: .eur,
            geography: "US", sector: "Tech", isin: "", fees: 0
        )
        XCTAssertEqual(
            AnalyticsEngine.gainPercent(gain: holding.gainLoss, costBasis: holding.costBasis) ?? 0,
            holding.gainLossPercent, accuracy: 0.0001
        )

        // A negative basis keeps the sign of the *gain*, exactly as the row does.
        XCTAssertEqual(
            AnalyticsEngine.gainPercent(gain: 50, costBasis: -100) ?? 0,
            50, accuracy: 0.0001
        )
    }

    // MARK: - Period membership (the transaction list's window)

    /// The list and the analytics beside it must answer the same question about the same day.
    ///
    /// The iOS transaction list applied its `<= today` bound only when the period had a lower bound
    /// too, and All Time has none — so a future-dated expense was listed and counted ("Showing 8 of
    /// 8") while the category donut, the Money Flow diagram and Recorded Cash on the same screen
    /// all excluded it. This walks every period and compares the shared predicate against what the
    /// engine actually returns.
    func testEveryPeriodAdmitsExactlyWhatTheEngineCounts() {
        let today = date(2026, 8, 24)
        let rows = [
            tx(.expense, 100, "Food", date(2025, 3, 4)),      // long past — All Time / YTD? no
            tx(.expense, 100, "Food", date(2026, 1, 6)),      // this year
            tx(.expense, 100, "Food", date(2026, 8, 20)),     // this week
            tx(.expense, 100, "Food", today),                 // today, the inclusive boundary
            tx(.expense, 900, "Rent", date(2026, 12, 1)),     // future — no period may admit it
        ]
        let data = FinancialData(transactions: rows)

        for period in AnalyticsPeriod.allCases {
            let admitted = rows
                .filter { period.includes($0.date, relativeTo: today, calendar: utc) }
                .map(\.date)
                .sorted()
            // `expensesByCategory` runs the engine's own `filteredTransactions`; every row here is
            // one expense of a known amount, so the total names how many the engine admitted.
            let engineTotal = engine(data, now: today).expensesByCategory(period: period)
                .reduce(Decimal(0)) { $0 + Decimal($1.value) }
            let admittedTotal = rows
                .filter { period.includes($0.date, relativeTo: today, calendar: utc) }
                .reduce(Decimal(0)) { $0 + $1.amount }

            XCTAssertEqual(
                admittedTotal, engineTotal,
                "\(period) — the list admits \(admittedTotal) while the engine counts \(engineTotal)"
            )
            XCTAssertFalse(
                admitted.contains(date(2026, 12, 1)),
                "\(period) admitted a future-dated row"
            )
            XCTAssertTrue(admitted.contains(today), "\(period) dropped today, its inclusive upper bound")
        }
    }

    /// The named case, stated on its own so a regression names itself.
    func testAllTimeIsBoundedAtTheTopEvenThoughItHasNoLowerBound() {
        let today = date(2026, 8, 24)
        XCTAssertNil(AnalyticsPeriod.all.firstIncludedDay(relativeTo: today, calendar: utc))
        XCTAssertTrue(AnalyticsPeriod.all.includes(date(2020, 1, 1), relativeTo: today, calendar: utc))
        XCTAssertFalse(
            AnalyticsPeriod.all.includes(date(2026, 8, 25), relativeTo: today, calendar: utc),
            "All Time is unbounded below, not above"
        )
    }

    // MARK: - Store-level memoization of localized analytics

    /// The cash-flow chart's month labels must follow an in-app language change.
    ///
    /// `CashFlowMonth.monthLabel` is formatted through
    /// `AppLocalization.effectiveLocale(appLanguage:)` — it is *data that is already translated*,
    /// printed verbatim on the x-axis — but `FinanceStore`'s trend cache keyed only on data
    /// version, currency, rate stamp, month count and the day. The root views re-`.id` on a
    /// language change, and a re-render cannot invalidate a cache that lives on the store, so the
    /// axis kept the old language until something unrelated moved the key: an edit, a currency
    /// change, or midnight. The sibling Sankey cache has keyed on `appLanguage` all along.
    ///
    /// This drives the store rather than the engine on purpose: the engine was never wrong.
    @MainActor
    func testCashFlowTrendLabelsFollowAnInAppLanguageChange() {
        let settings = makeSettings()
        let store = makeStore(settings: settings)

        settings.appLanguage = "en"
        let english = store.cashFlowTrend(months: 6, settings: settings).map(\.monthLabel)
        settings.appLanguage = "it"
        let italian = store.cashFlowTrend(months: 6, settings: settings).map(\.monthLabel)

        XCTAssertFalse(english.isEmpty, "the trend returned no months to label")
        XCTAssertNotEqual(english, italian, "the cache re-served the previous language's labels")

        // Ground truth: a store with nothing cached, asked the same question in Italian.
        let freshSettings = makeSettings()
        freshSettings.appLanguage = "it"
        XCTAssertEqual(
            italian,
            makeStore(settings: freshSettings).cashFlowTrend(months: 6, settings: freshSettings).map(\.monthLabel),
            "the labels after the switch are not what an uncached read returns"
        )
    }

    @MainActor
    private func makeSettings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
    }

    @MainActor
    private func makeStore(settings: AppSettings) -> FinanceStore {
        FinanceStore(
            persistence: EmptyPersistence(),
            settings: settings,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )
    }
}

/// Nothing on disk. The trend's month labels come from the calendar and the language, not from the
/// ledger, so an empty store is enough to ask which language they came back in.
private final class EmptyPersistence: FinancePersistence, @unchecked Sendable {
    var locationDescription: String { "in-memory (analytics cache test)" }
    func load() throws -> FinancePersistenceLoad? { nil }
    func save(_ data: FinancialData) throws {}
    func clear() throws {}
}
