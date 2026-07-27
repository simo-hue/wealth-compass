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

    private func buildDocument(sections: Set<ReportSection> = Set(ReportSection.allCases),
                               range: ReportDateRange = .allTime) -> ReportDocument {
        ReportDocumentBuilder(
            context: ReportBuildContext(
                data: data,
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
