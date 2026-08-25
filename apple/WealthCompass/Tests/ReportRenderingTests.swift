import PDFKit
import XCTest
@testable import WealthCompassMobile

/// Regression cover for the two defect classes an adversarial review of the PDF export actually
/// reproduced: content silently lost when a table splits across pages, and printed figures that do
/// not add up once a foreign-currency record is involved.
///
/// Both were invisible in normal use — the export succeeded, the page count was right, and only a
/// reader adding a column up by hand would have noticed. So they are pinned here rather than left
/// to visual inspection of a sample.
final class ReportPaginationTests: XCTestCase {

    /// The paginator measures text, which needs a `CGContext`; a throwaway PDF context is the
    /// cheapest one that behaves identically to the real render path.
    private func makeMeasuringContext(theme: ReportTheme) throws -> PDFDrawingContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wc-pagination-measure-\(UUID().uuidString).pdf")
        var box = CGRect(origin: .zero, size: theme.pageSize)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return PDFDrawingContext(cg: context, theme: theme, chrome: ReportChrome())
    }

    /// A wide amount must stay readable rather than be truncated.
    ///
    /// The money columns budget 64.0pt at A4. Measured at the report's own 8.8pt tabular face,
    /// `$1,234,567.89` is 65.5pt and German `1.234.567,89 €` is 68.1pt, so both used to render as
    /// `1.234.56…` — destroying the one figure the table exists to state, in the totals row too.
    /// Rendering the real document and reading the text back is the only honest check: the defect
    /// lives in the drawing layer, not in the model.
    func testWideAmountsRenderInFullRatherThanTruncated() throws {
        let wide = "1.234.567,89 €"
        let table = ReportTable(
            columns: [
                ReportColumn("Symbol", weight: 0.9),
                ReportColumn("Name", weight: 1.9),
                ReportColumn("Quantity", weight: 1.1, alignment: .trailing, isNumeric: true),
                ReportColumn("Cost Basis", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("Value", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("Gain / Loss", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("%", weight: 0.85, alignment: .trailing, isNumeric: true),
            ],
            rows: [ReportRow(["VWCE", "Vanguard", "10", wide, wide, wide, "1,2"])],
            footer: ReportRow(["", "", "", wide, wide, wide, ""], style: .subtotal),
            caption: nil)

        let text = try renderedText(makeDocument(table, theme: ReportTheme()))
        XCTAssertTrue(text.contains(wide), "the amount was truncated; extracted text: \(text.prefix(400))")
        XCTAssertFalse(text.contains("1.234.56…"), "an ellipsized amount reached the page")
    }

    /// Amounts shrink; long *translated headers* still truncate, and deliberately so.
    ///
    /// `GANANCIA / PÉRDIDA` is 18 characters, and at the header's 0.8pt tracking that is 14.4pt of
    /// letter-spacing on top of roughly 81.5pt of semibold glyphs, against a 64.0pt column. Fitting
    /// it would need about 0.65 scale — a 4.9pt heading, which is not a fix. The column budget or
    /// the translation has to give; this test pins the current behaviour so the choice stays
    /// visible rather than silently regressing.
    func testOverlongTranslatedHeaderStillTruncatesRatherThanShrinkingToIllegibility() throws {
        let table = ReportTable(
            columns: [
                ReportColumn("Symbol", weight: 0.9),
                ReportColumn("Name", weight: 1.9),
                ReportColumn("Quantity", weight: 1.1, alignment: .trailing, isNumeric: true),
                ReportColumn("Cost Basis", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("Value", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("GANANCIA / PÉRDIDA", weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("%", weight: 0.85, alignment: .trailing, isNumeric: true),
            ],
            rows: [ReportRow(["A", "B", "1", "2", "3", "4", "5"])],
            footer: nil, caption: nil)

        let text = try renderedText(makeDocument(table, theme: ReportTheme()))
        // Name the header specifically: asserting on any "…" anywhere in the document would pass
        // for an ellipsis in an unrelated cell.
        let flattened = text.filter { !$0.isWhitespace }
        XCTAssertFalse(
            flattened.contains("GANANCIA/PÉRDIDA"),
            "the Spanish header now fits — revisit the column-budget note and the 0.70 floor"
        )
        XCTAssertTrue(flattened.contains("GANANCIA"), "the header vanished entirely rather than truncating")
    }

    /// Renders the document to a real PDF and returns every page's text.
    private func renderedText(_ document: ReportDocument) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wc-render-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try PDFReportRenderer.render(document: document, to: url)
        let pdf = try XCTUnwrap(PDFDocument(url: url), "renderer produced an unopenable PDF")
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func makeTable(rows: Int, twoLine: Bool, caption: String?) -> ReportTable {
        ReportTable(
            columns: [
                ReportColumn("Date", weight: 1.2),
                ReportColumn("Description", weight: 2.8),
                ReportColumn("Amount", weight: 1.4, alignment: .trailing, isNumeric: true),
            ],
            rows: (0..<rows).map {
                ReportRow(["d\($0)", "row-\($0)", "\($0).00"], secondary: twoLine ? "meta \($0)" : nil)
            },
            footer: ReportRow(["Total", "", "9999.00"], style: .subtotal),
            caption: caption)
    }

    private func makeDocument(_ table: ReportTable, theme: ReportTheme) -> ReportDocument {
        ReportDocument(
            metadata: ReportMetadata(brandName: "B", documentTitle: "T", scopeLine: "S",
                                     periodLine: nil, baseCurrencyLine: "EUR", generatedLine: "g",
                                     footerNote: "f", appVersion: "1", brandMarkPNG: nil),
            sections: [ReportSectionContent(anchor: "a", title: "Sec", blocks: [.table(table)])],
            theme: theme)
    }

    /// A table that splits must reproduce its rows exactly — same rows, same order, none dropped
    /// and none repeated — and must print its totals row exactly once.
    ///
    /// The original defect fired at roughly one row count in 25: when every row fitted but the
    /// footer did not, the continuation chunk was emitted with no rows at all, the renderer read
    /// that as "no data", printed "No entries recorded." and discarded the total outright.
    func testSplittingATableNeverLosesRowsOrTheTotalsRow() throws {
        let theme = ReportTheme(paper: .a4, direction: .leftToRight)
        let measuring = try makeMeasuringContext(theme: theme)

        for twoLine in [false, true] {
            for caption in ["Transactions — 2024", nil] {
                for rowCount in [1, 2, 3, 4, 5, 23, 24, 25, 39, 40, 41, 79, 80, 81, 120, 200] {
                    let table = makeTable(rows: rowCount, twoLine: twoLine, caption: caption)
                    let layout = ReportPaginator(document: makeDocument(table, theme: theme),
                                                 measuring: measuring).paginate()

                    var emitted: [String] = []
                    var footers = 0
                    for page in layout.pages {
                        for placed in page.blocks {
                            guard case let .table(chunk) = placed.block else { continue }
                            emitted += chunk.rows.map { $0.cells[1] }
                            if chunk.footer != nil { footers += 1 }
                        }
                    }

                    let label = "rows=\(rowCount) twoLine=\(twoLine) caption=\(caption != nil)"
                    XCTAssertEqual(emitted, (0..<rowCount).map { "row-\($0)" },
                                   "rows lost, duplicated or reordered — \(label)")
                    XCTAssertEqual(footers, 1, "totals row must appear exactly once — \(label)")
                }
            }
        }
    }
}

final class ReportReconciliationTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = dayOfMonth; components.hour = 12
        return calendar.date(from: components)!
    }

    private var now: Date { day(2026, 7, 27) }

    private var snapshot: ExchangeRateSnapshot {
        ExchangeRateSnapshot(baseCurrency: .eur, rates: ["USD": 1.0842],
                             effectiveDate: now, fetchedAt: now, provider: "Frankfurter")
    }

    /// Deliberately mixed-currency: with an all-EUR dataset every reconciliation check passes even
    /// with the arithmetic wrong, because no conversion remainder exists to drift.
    private var data: FinancialData {
        var data = FinancialData()
        data.transactions = [
            Transaction(type: .income, category: "Salary", amount: 3000, description: "a",
                        date: day(2024, 3, 15), currency: .eur),
            Transaction(type: .expense, category: "Rent", amount: 500, description: "b",
                        date: day(2024, 3, 20), currency: .eur),
            Transaction(type: .income, category: "Freelance", amount: 1000, description: "c",
                        date: day(2025, 1, 5), currency: .usd),
            Transaction(type: .expense, category: "Travel", amount: 250, description: "d",
                        date: day(2025, 6, 30), currency: .usd),
            Transaction(type: .income, category: "Salary", amount: 2000, description: "e",
                        date: day(2026, 2, 1), currency: .eur),
            Transaction(type: .expense, category: "Health", amount: 700, description: "f",
                        date: day(2026, 7, 26), currency: .eur),
            // Future-dated: printed, but excluded from every balance.
            Transaction(type: .expense, category: "Insurance", amount: 412.90, description: "future",
                        date: day(2026, 9, 1), currency: .eur),
        ]
        return data
    }

    /// `usesLiveRates: false` is the export that runs before the first rate refresh has landed.
    /// The snapshot is withheld from the converter *and* the context together, because
    /// `FinanceStore.exportReport` fills both from `AppSettings.exchangeRateSnapshot` — a document
    /// converted at live rates while describing fallback ones cannot occur in the app, and must not
    /// be constructible here either.
    private func buildDocument(sections: Set<ReportSection> = Set(ReportSection.allCases),
                               range: ReportDateRange = .allTime,
                               data: FinancialData? = nil,
                               usesLiveRates: Bool = true) -> ReportDocument {
        let snapshot = usesLiveRates ? self.snapshot : nil
        return ReportDocumentBuilder(
            context: ReportBuildContext(
                data: data ?? self.data,
                converter: CurrencyConverter(snapshot: snapshot),
                baseCurrency: .eur,
                exchangeRateSnapshot: snapshot,
                appLanguage: nil,
                locale: locale,
                calendar: calendar,
                now: now,
                appVersion: "1", appBuild: "1", platformName: "test",
                brandMarkPNG: nil,
                paper: .a4,
                direction: .leftToRight),
            options: ReportExportOptions(format: .pdf, sections: sections, dateRange: range)).build()
    }

    private func kpi(_ document: ReportDocument, section anchor: String, label: String) -> String? {
        for block in document.sections.first(where: { $0.anchor == anchor })?.blocks ?? [] {
            if case let .kpis(items) = block, let match = items.first(where: { $0.label == label }) {
                return match.value
            }
        }
        return nil
    }

    private func amount(_ string: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = locale
        // `decimalValue`, not `doubleValue`: going through Double reintroduces exactly the binary
        // representation error these tests exist to rule out.
        return formatter.number(from: string)?.decimalValue
    }

    /// The ledger states an identity — opening + income + expenses = closing — as four printed
    /// figures. It has to hold on the printed values, not on some higher-precision intermediate the
    /// reader cannot see.
    func testPrintedLedgerFiguresAddUpAcrossEveryDateRange() throws {
        for range in [ReportDateRange.allTime, .thisYear, .last12Months] {
            let document = buildDocument(sections: [.cashFlow], range: range)
            let anchor = ReportSection.cashFlow.anchor

            let opening = try XCTUnwrap(amount(try XCTUnwrap(kpi(document, section: anchor, label: "Opening Balance"))))
            let income = try XCTUnwrap(amount(try XCTUnwrap(kpi(document, section: anchor, label: "Income"))))
            let expenses = try XCTUnwrap(amount(try XCTUnwrap(kpi(document, section: anchor, label: "Expenses"))))
            let closing = try XCTUnwrap(amount(try XCTUnwrap(kpi(document, section: anchor, label: "Closing Balance"))))

            XCTAssertEqual(opening + income + expenses, closing,
                           "printed ledger figures do not reconcile for \(range.titleKey)")
        }
    }

    /// A bounded export must not print figures from outside the period its cover page states.
    ///
    /// The KPI row read `monthlyCashFlow(for: now)` and the trend `cashFlowTrend(months: 12)` — both
    /// anchored to today — so a 2024 export carried 2026 KPI values and twelve 2025-26 bars, under a
    /// 2024 heading, labelled "This Month". The Money Flow and category blocks had already been
    /// moved off their own windows for this reason.
    func testBoundedExportKeepsTheCashFlowSectionInsidePeriod() throws {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = 2024; comps.month = 3; comps.day = 1; comps.hour = 12
        let start = try XCTUnwrap(calendar.date(from: comps))
        comps.month = 5; comps.day = 31
        let end = try XCTUnwrap(calendar.date(from: comps))

        let document = buildDocument(sections: [.cashFlow], range: .custom(start: start, end: end))
        let anchor = ReportSection.cashFlow.anchor
        let blocks = try XCTUnwrap(document.sections.first(where: { $0.anchor == anchor })?.blocks)

        // "This Month" is only honest on an unbounded export.
        for block in blocks {
            if case let .kpis(items) = block {
                XCTAssertFalse(
                    items.contains { $0.label.contains("This Month") },
                    "a bounded export still labels a KPI 'This Month'"
                )
            }
        }

        // The trend spans the range's own months, not twelve counted back from today.
        var barCount: Int?
        for block in blocks {
            if case let .chart(chart) = block, case let .groupedBars(groups, _, _) = chart {
                barCount = groups.count
            }
        }
        XCTAssertEqual(barCount, 3, "trend should cover Mar–May 2024, not a window ending today")
    }

    /// The trend must cover every month the ledger beneath it does.
    ///
    /// A twelve-bar readability cap silently dropped the earliest month: `.last12Months` spans
    /// thirteen calendar months, so that month kept its ledger subtotal and lost its bar, and a
    /// range wider than a year charted only its tail against figures covering all of it.
    func testTrendCoversEveryMonthOfTheRange() throws {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
            return calendar.date(from: c)!
        }
        // Two full years — well past the old cap.
        let document = buildDocument(
            sections: [.cashFlow],
            range: .custom(start: date(2023, 1, 1), end: date(2024, 12, 31)))
        var barCount: Int?
        for block in document.sections.first(where: { $0.anchor == ReportSection.cashFlow.anchor })?.blocks ?? [] {
            if case let .chart(chart) = block, case let .groupedBars(groups, _, _) = chart {
                barCount = groups.count
            }
        }
        XCTAssertEqual(barCount, 24, "the chart silently dropped months the ledger still reports")
    }

    /// The Money Flow diagram and the category table beneath it must print the same figure for the
    /// same category.
    ///
    /// The diagram was built by the engine, which sums unrounded conversions, while every table in
    /// the report sums `recordValue` — rounded at the point of conversion, per `roundedMoney`. With
    /// foreign-currency rows the two drifted, so one page carried two amounts for one category.
    func testMoneyFlowAgreesWithTheCategoryTable() throws {
        // Enough foreign-currency rows for the remainder to accumulate. $1,000 at 1.0842 converts to
        // 922.33905…, so one row rounds away invisibly and the check would pass with the arithmetic
        // wrong; a hundred of them drift by more than a euro.
        var many = FinancialData()
        many.transactions = (0..<100).map { index in
            Transaction(type: .expense, category: "Rent", amount: 1000, description: "r\(index)",
                        date: day(2026, 3, 1), currency: .usd)
        }
        many.transactions.append(
            Transaction(type: .income, category: "Salary", amount: 500_000, description: "s",
                        date: day(2026, 1, 1), currency: .eur))

        let document = buildDocument(sections: [.cashFlow], data: many)
        let blocks = try XCTUnwrap(
            document.sections.first(where: { $0.anchor == ReportSection.cashFlow.anchor })?.blocks)

        var diagram: [String: Double] = [:]
        var table: [String: Decimal] = [:]
        for block in blocks {
            if case let .chart(chart) = block, case let .sankey(model, _) = chart {
                for node in model.outflows where node.role == .expense {
                    diagram[node.title] = node.value
                }
            }
            if case let .table(reportTable) = block,
               reportTable.columns.first?.title == "Category" {
                for row in reportTable.rows where row.cells.count >= 2 {
                    table[row.cells[0]] = amount(row.cells[1])
                }
            }
        }

        XCTAssertFalse(diagram.isEmpty, "no Money Flow diagram in the section")
        XCTAssertFalse(table.isEmpty, "no category table in the section")
        for (category, tabled) in table {
            let charted = try XCTUnwrap(diagram[category], "\(category) missing from the diagram")
            XCTAssertEqual(
                Decimal(charted), tabled,
                "\(category) prints a different amount on the diagram than in the table"
            )
        }
    }

    /// The running-balance column is the reader's audit trail; its final settled value is the same
    /// number as the closing-balance tile above it.
    func testFinalRunningBalanceMatchesTheClosingBalanceTile() throws {
        let document = buildDocument(sections: [.cashFlow])
        let anchor = ReportSection.cashFlow.anchor
        let closing = try XCTUnwrap(kpi(document, section: anchor, label: "Closing Balance"))

        var lastSettledBalance: String?
        for block in document.sections.first(where: { $0.anchor == anchor })?.blocks ?? [] {
            guard case let .table(table) = block,
                  table.columns.contains(where: { $0.title == "Balance" }) else { continue }
            for row in table.rows where row.style == .normal {
                lastSettledBalance = row.cells[4]
            }
        }
        XCTAssertEqual(lastSettledBalance, closing)
    }

    /// The same quantity printed in two sections must be character-for-character identical.
    ///
    /// This is what broke when the ledger started booking each posting at its rounded value while
    /// the Overview tile still came from `AnalyticsEngine`'s unrounded sum: one PDF, two different
    /// cash figures a page apart.
    func testOverviewCashMatchesTheLedgerClosingBalance() throws {
        let document = buildDocument()
        XCTAssertEqual(kpi(document, section: ReportSection.overview.anchor, label: "Cash"),
                       kpi(document, section: ReportSection.cashFlow.anchor, label: "Closing Balance"))
    }

    /// Future-dated rows are printed but must not reach any balance — the same rule
    /// `AnalyticsEngine.calculateTotals()` applies to cash.
    func testFutureDatedTransactionsArePrintedButExcludedFromBalances() throws {
        let document = buildDocument(sections: [.cashFlow])
        let anchor = ReportSection.cashFlow.anchor

        var excludedRows = 0
        for block in document.sections.first(where: { $0.anchor == anchor })?.blocks ?? [] {
            guard case let .table(table) = block,
                  table.columns.contains(where: { $0.title == "Balance" }) else { continue }
            excludedRows += table.rows.filter { $0.style == .excluded }.count
        }
        XCTAssertEqual(excludedRows, 1, "the future-dated row must still be printed, marked excluded")

        // 3000 - 500 + 922.34 - 230.58 + 2000 - 700, with the 412.90 future expense left out.
        XCTAssertEqual(amount(try XCTUnwrap(kpi(document, section: anchor, label: "Closing Balance"))),
                       Decimal(string: "4491.76"))
    }

    /// The offline export must disclose the rates it converted at, not just admit that it used
    /// some.
    ///
    /// `heldCurrencies()` and the rate table both sat inside `if let snapshot`, so the one export
    /// whose figures are least reproducible — every foreign amount converted at an approximate
    /// built-in seed — was also the only one that printed no rates at all. A reader given
    /// "€922.34" and told merely that "fallback rates were approximate" cannot check a single
    /// figure in the document.
    func testAppendixDisclosesFallbackRatesWhenNoSnapshotExists() throws {
        let document = buildDocument(usesLiveRates: false)
        let appendix = try XCTUnwrap(document.sections.first { $0.title == "Appendix" })

        var rateTable: ReportTable?
        for block in appendix.blocks {
            if case let .table(table) = block, table.columns.first?.title == "Currency" {
                rateTable = table
            }
        }
        let table = try XCTUnwrap(rateTable, "the appendix disclosed no exchange rates at all")

        // Without a snapshot the seeds are units per EUR by construction, so the column has to say
        // so rather than inherit a quote base from a snapshot that does not exist.
        XCTAssertEqual(table.columns[1].title, "Units per EUR")

        let usd = try XCTUnwrap(table.rows.first { $0.cells[0].hasPrefix("USD") },
                                "USD is held by the dataset but missing from the rate table")
        XCTAssertEqual(usd.cells[2], "Offline fallback rate")
        XCTAssertEqual(usd.style, .excluded, "an approximate rate must be marked as one")
        XCTAssertEqual(
            usd.cells[1],
            Currency.usd.fallbackUnitsPerEuro.formatted(
                .number.precision(.fractionLength(0...6)).locale(locale)),
            "the printed rate is not the one the conversions went through"
        )
    }

    /// With a snapshot the same table must still name the live rates as live — the fallback path
    /// above shares its construction, so a regression there would otherwise relabel every export.
    func testAppendixMarksLiveRatesAsLive() throws {
        let document = buildDocument()
        let appendix = try XCTUnwrap(document.sections.first { $0.title == "Appendix" })

        var rateTable: ReportTable?
        for block in appendix.blocks {
            if case let .table(table) = block, table.columns.first?.title == "Currency" {
                rateTable = table
            }
        }
        let table = try XCTUnwrap(rateTable)
        let usd = try XCTUnwrap(table.rows.first { $0.cells[0].hasPrefix("USD") })
        XCTAssertEqual(usd.cells[2], "Live rate")
        XCTAssertEqual(usd.cells[1], "1.0842")
    }

    /// The report books each posting at its rounded value; `AnalyticsEngine` sums unrounded
    /// conversions and rounds once. Both are defensible and they cannot both be used in one
    /// document — but the divergence must stay bounded by the rounding unit per foreign-currency
    /// record, never grow without limit.
    func testDivergenceFromAnalyticsEngineStaysBoundedByRounding() throws {
        let document = buildDocument(sections: [.cashFlow])
        let reported = try XCTUnwrap(amount(try XCTUnwrap(
            kpi(document, section: ReportSection.cashFlow.anchor, label: "Closing Balance"))))

        let engineCash = AnalyticsEngine(data: data,
                                         converter: CurrencyConverter(snapshot: snapshot),
                                         displayCurrency: .eur,
                                         appLanguage: nil,
                                         calendar: calendar,
                                         now: now).calculateTotals().totalLiquidity

        let foreignRecords = Decimal(data.transactions.filter { ($0.currency ?? .eur) != .eur }.count)
        XCTAssertLessThanOrEqual(abs(reported - engineCash), Decimal(string: "0.01")! * foreignRecords)
    }
}
