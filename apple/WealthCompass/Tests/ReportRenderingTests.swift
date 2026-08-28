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

    /// Every contents row is drawn as a hyperlink, so every one of them has to arrive somewhere.
    ///
    /// `context.addDestination` was called only where `LaidOutPage.sectionAnchor` was set — a
    /// section's first page — while the paginator also emits a level-1 contents entry for every
    /// subheading anchor. In a full report that is roughly 20 of 25 rows drawn as clickable
    /// rectangles pointing at a name no page ever defines. The file itself shows which is which:
    /// a resolved named destination becomes a `PDFActionGoTo` carrying a page, an unresolved one
    /// leaves the annotation with no action at all.
    func testEveryContentsRowLinksToARealPage() throws {
        let document = contentsFixture()
        let pdf = try renderedPDF(document)

        var links = 0
        var resolved = 0
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "Link" {
                links += 1
                if let goTo = annotation.action as? PDFActionGoTo, goTo.destination.page != nil {
                    resolved += 1
                }
            }
        }

        // Two sections and three subheadings: five contents rows, five links.
        XCTAssertEqual(links, 5, "the contents page stopped linking its rows")
        XCTAssertEqual(resolved, links,
                       "\(links - resolved) contents rows point at a destination no page defines")
    }

    /// The sidebar resolves entries by page index rather than by name, so it was never broken and
    /// must not change while the in-page links are being fixed.
    func testOutlineKeepsItsTwoLevelShape() throws {
        let pdf = try renderedPDF(contentsFixture())
        let root = try XCTUnwrap(pdf.outlineRoot, "the PDF lost its outline")

        XCTAssertEqual(root.numberOfChildren, 2)
        let first = try XCTUnwrap(root.child(at: 0))
        XCTAssertEqual(first.label, "One")
        XCTAssertEqual(first.numberOfChildren, 2, "the first section's subsections left the sidebar")
        XCTAssertNotNil(try XCTUnwrap(first.child(at: 0)).destination?.page)
        XCTAssertEqual(try XCTUnwrap(root.child(at: 1)).numberOfChildren, 1)
    }

    // MARK: - Right-to-left

    /// In Arabic and Hebrew a KPI tile must read as one block against one edge.
    ///
    /// `isNumeric` used to pin the alignment of every figure. That is right for a money *column* —
    /// pinned right, decimal separators lined up down the page — and wrong for a figure set inside
    /// a label. The tile stacks label, value and detail into rects of the same x and width, so
    /// mirroring the two text lines while pinning the middle one printed label-right / value-left /
    /// detail-right: the headline figure of every tile sitting alone on the wrong side.
    func testRightToLeftKPIValueHugsTheSameEdgeAsItsLabel() throws {
        let pdf = try kpiDocument(direction: .rightToLeft)
        let page = try XCTUnwrap(pdf.page(at: 1))
        // The detail line rather than the label: `.kpiDetail` carries no tracking, so PDFKit
        // extracts it verbatim and its box is the drawn box. `.kpiLabel`'s 0.8pt letter-spacing
        // both splits the extracted text ("CA SH") and pushes its right edge in by the trailing kern.
        let detail = try XCTUnwrap(drawnBounds(of: "dd", on: page, in: pdf), "the tile detail is not on the page")
        let value = try XCTUnwrap(drawnBounds(of: "1234", on: page, in: pdf), "the tile value is not on the page")

        XCTAssertEqual(value.maxX, detail.maxX, accuracy: 1,
                       "the value is pinned to the opposite edge of the tile from its own label")
    }

    /// The same tile left-to-right, unchanged: every line of it starts at the leading edge.
    func testLeftToRightKPIValueStillHugsTheLeadingEdge() throws {
        let pdf = try kpiDocument(direction: .leftToRight)
        let page = try XCTUnwrap(pdf.page(at: 1))
        let detail = try XCTUnwrap(drawnBounds(of: "dd", on: page, in: pdf))
        let value = try XCTUnwrap(drawnBounds(of: "1234", on: page, in: pdf))
        XCTAssertEqual(value.minX, detail.minX, accuracy: 1)
    }

    /// A money column keeps the opt-out that was written for it.
    ///
    /// The column's *position* mirrors with the rest of the table, but the figures inside stay
    /// right-aligned in every script — that is what keeps "1.234,56" and "12,00" sharing a decimal
    /// separator down the column. Narrowing the opt-out to columns must not lose this.
    func testRightToLeftMoneyColumnStaysRightAlignedInsideItsCell() throws {
        let table = ReportTable(
            columns: [
                ReportColumn("Date", weight: 1.2),
                ReportColumn("Description", weight: 2.8),
                ReportColumn("Amount", weight: 1.4, alignment: .trailing, isNumeric: true),
            ],
            rows: [ReportRow(["d", "row", "9"]), ReportRow(["d", "row", "1234567"])],
            footer: nil,
            caption: nil)
        let pdf = try renderedPDF(makeDocument(table, theme: ReportTheme(direction: .rightToLeft)))
        let page = try XCTUnwrap(pdf.page(at: 1))

        let short = try XCTUnwrap(drawnBounds(of: "9", on: page, in: pdf))
        let long = try XCTUnwrap(drawnBounds(of: "1234567", on: page, in: pdf))
        XCTAssertEqual(short.maxX, long.maxX, accuracy: 0.5,
                       "the amounts stopped sharing a right edge, so the column no longer aligns")
    }

    /// A Money Flow label is two lines of one label in one rect: a category name over its amount.
    ///
    /// Pinning the amount put those two lines on opposite edges of that rect in RTL — measured at
    /// 85pt apart on an A4 page — so one label read as two unrelated fragments. Which edge they
    /// share depends on the side of the hub the node sits on, so the assertion takes either as long
    /// as both lines agree on it.
    func testRightToLeftSankeyLabelKeepsItsTwoLinesTogether() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func date(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = dayOfMonth; comps.hour = 12
            return try XCTUnwrap(utc.date(from: comps))
        }

        // Two income categories so no category's amount equals the hub total, and none of the
        // printed figures is a substring of another — the search has to find the right label's line.
        let sankey = AnalyticsEngine(
            data: FinancialData(transactions: [
                Transaction(type: .income, category: "Salary", amount: 11000, description: "",
                            date: try date(2026, 7, 10)),
                Transaction(type: .income, category: "Freelance", amount: 6248, description: "",
                            date: try date(2026, 7, 10)),
                Transaction(type: .expense, category: "Housing", amount: 9559, description: "",
                            date: try date(2026, 7, 10)),
            ]),
            displayCurrency: .eur,
            calendar: utc,
            now: try date(2026, 7, 29)
        ).cashFlowSankey(period: .thirtyDays)

        let document = ReportDocument(
            metadata: ReportMetadata(brandName: "B", documentTitle: "T", scopeLine: "S",
                                     periodLine: nil, baseCurrencyLine: "EUR", generatedLine: "g",
                                     footerNote: "f", appVersion: "1", brandMarkPNG: nil),
            sections: [ReportSectionContent(anchor: "a", title: "Sec", blocks: [
                .chart(.sankey(model: sankey, amountFormatter: { "\(Int($0))" })),
            ])],
            theme: ReportTheme(direction: .rightToLeft))
        let pdf = try renderedPDF(document)
        let page = try XCTUnwrap(pdf.page(at: 1))

        // Salary and Freelance sit on one side of the hub, Housing on the other, so this covers
        // both the `.leading` and the `.trailing` label columns.
        for (title, amount) in [("Salary", "11000"), ("Freelance", "6248"), ("Housing", "9559")] {
            let name = try XCTUnwrap(drawnBounds(of: title, on: page, in: pdf), "\(title) was not drawn")
            let figure = try XCTUnwrap(drawnBounds(of: amount, on: page, in: pdf),
                                       "\(title)'s amount was not drawn")
            XCTAssertTrue(
                abs(name.maxX - figure.maxX) <= 1 || abs(name.minX - figure.minX) <= 1,
                "\(title)'s name and amount sit on opposite edges of one label rect: "
                    + "name \(name.minX)…\(name.maxX), amount \(figure.minX)…\(figure.maxX)"
            )
        }
    }

    /// A single-tile document in the given direction. Body page 1 is its only one — the cover is
    /// page 0 and a single section over a single page needs no contents page.
    private func kpiDocument(direction: ReportLayoutDirection) throws -> PDFDocument {
        let document = ReportDocument(
            metadata: ReportMetadata(brandName: "B", documentTitle: "T", scopeLine: "S",
                                     periodLine: nil, baseCurrencyLine: "EUR", generatedLine: "g",
                                     footerNote: "f", appVersion: "1", brandMarkPNG: nil),
            sections: [ReportSectionContent(anchor: "a", title: "Sec", blocks: [
                .kpis([ReportKPI(label: "CASH", value: "1234", detail: "dd")]),
            ])],
            theme: ReportTheme(direction: direction))
        return try renderedPDF(document)
    }

    /// Where PDFKit says `text` was drawn on `page`. Reading positions back out of the file is the
    /// only honest check on alignment, since the text extracts the same however it was placed.
    ///
    /// `findString` rather than `characterBounds(at:)`: the latter's indices drift against
    /// `page.string` wherever the extractor synthesises a newline, and it returned boxes spanning
    /// most of the page height.
    ///
    /// The document is a parameter rather than `page.document`, which is a back-reference the page
    /// does not keep alive: dropping the `PDFDocument` and holding only a page left every lookup
    /// returning nil.
    private func drawnBounds(of text: String, on page: PDFPage, in document: PDFDocument) -> CGRect? {
        // `bounds(for:)` doubles as the page filter: a selection on another page reports an empty
        // box here.
        for match in document.findString(text, withOptions: [.literal]) {
            let bounds = match.bounds(for: page)
            if bounds.width > 0, bounds.height > 0 { return bounds }
        }
        return nil
    }

    /// Two sections with anchored subheadings, long enough that the subsections land mid-document
    /// rather than all on one page. Two non-structural sections is what makes the renderer emit a
    /// contents page at all (`ReportPaginator.needsContentsPage`).
    private func contentsFixture(chrome: ReportChrome = ReportChrome()) -> ReportDocument {
        ReportDocument(
            metadata: ReportMetadata(brandName: "B", documentTitle: "T", scopeLine: "S",
                                     periodLine: nil, baseCurrencyLine: "EUR", generatedLine: "g",
                                     footerNote: "f", appVersion: "1", brandMarkPNG: nil),
            chrome: chrome,
            sections: [
                ReportSectionContent(anchor: "section-one", title: "One", blocks: [
                    .sectionTitle("One", subtitle: nil),
                    .subheading("Sub A", anchor: "one-a"),
                    .table(makeTable(rows: 40, twoLine: false, caption: "A")),
                    .subheading("Sub B", anchor: "one-b"),
                    .table(makeTable(rows: 40, twoLine: false, caption: "B")),
                ]),
                ReportSectionContent(anchor: "section-two", title: "Two", blocks: [
                    .sectionTitle("Two", subtitle: nil),
                    .subheading("Sub C", anchor: "two-a"),
                    .table(makeTable(rows: 10, twoLine: false, caption: "C")),
                ]),
            ])
    }

    /// Renders the document to a real PDF and returns every page's text.
    private func renderedText(_ document: ReportDocument) throws -> String {
        let pdf = try renderedPDF(document)
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func renderedPDF(_ document: ReportDocument) throws -> PDFDocument {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wc-render-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try PDFReportRenderer.render(document: document, to: url)
        return try XCTUnwrap(PDFDocument(url: url), "renderer produced an unopenable PDF")
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

    // MARK: - Narrow boxes

    /// Draws one line into a box `width` points wide and reads back what actually reached the page.
    ///
    /// Rendering and extracting is the only honest check here: the defect is entirely in the
    /// drawing layer, and every caller of `drawLine` passes it a rect it has already decided on.
    private func drawnLine(_ text: String, role: ReportFontRole, width: CGFloat) throws -> String {
        let theme = ReportTheme()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wc-drawline-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(origin: .zero, size: theme.pageSize)
        let cg = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        let context = PDFDrawingContext(cg: cg, theme: theme)
        cg.beginPDFPage(nil)
        context.drawLine(text, role: role, color: theme.palette.inkMuted,
                         in: CGRect(x: 60, y: 80, width: width, height: 12),
                         alignment: .center)
        cg.endPDFPage()
        cg.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: url), "drawing produced an unopenable PDF")
        return pdf.page(at: 0)?.string ?? ""
    }

    /// A box too narrow even for the ellipsis must not print the whole string anyway.
    ///
    /// `CTLineCreateTruncatedLine` returns NULL when the box cannot hold the truncation token — a
    /// little under 6pt for "…" at the 7pt axis face. The `if let` around it had no `else`, so the
    /// full-width line survived and was drawn at its full width, far outside the rect its caller
    /// reserved. The cash-flow chart is where this bites: a multi-year custom range divides the
    /// plot into 70-odd clusters ~5pt wide, and every month label was painted over its neighbours.
    func testALabelTooNarrowForAnEllipsisIsNotDrawnInFull() throws {
        let label = "September"

        for width in [1, 2, 3, 4, 5] as [CGFloat] {
            let drawn = try drawnLine(label, role: .chartAxis, width: width)
            XCTAssertFalse(
                drawn.contains(label),
                "the whole \(label.count)-character label reached a \(width)pt box: \"\(drawn)\""
            )
            // Whatever survives has to be something that *fits*: an ellipsis at most, or nothing.
            XCTAssertLessThanOrEqual(
                drawn.filter { !$0.isWhitespace }.count, 1,
                "more than one glyph was drawn into a \(width)pt box: \"\(drawn)\""
            )
        }

        // The two paths either side of it are unchanged: a box that fits prints the label whole,
        // and a box between the two prints a real truncation rather than nothing.
        XCTAssertTrue(try drawnLine(label, role: .chartAxis, width: 200).contains(label),
                      "a box with room to spare stopped printing the label in full")
        // Asserted as a prefix rather than by looking for "…": PDFKit's extractor drops the
        // ellipsis glyph, so a truncated line comes back as its surviving head ("Sept").
        let middle = try drawnLine(label, role: .chartAxis, width: 20)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(middle.isEmpty, "a 20pt box drew nothing where a truncation fits")
        XCTAssertFalse(middle.contains(label), "a 20pt box printed the label in full: \"\(middle)\"")
        XCTAssertTrue(label.hasPrefix(middle),
                      "a 20pt box drew \"\(middle)\", which is not a truncation of \(label)")
    }

    // MARK: - Page numbers

    /// Page numbers are figures, and the report sets every other figure in the reader's locale.
    ///
    /// The footer and the contents page built theirs by interpolating an `Int` into a string, which
    /// is `String(describing:)` — it neither groups nor shapes digits. An `ar_EG` report therefore
    /// printed its money in Arabic-Indic digits and "Page 3 of 12" in Latin ones on the same sheet.
    /// `ReportDocumentBuilder.count(_:)` already carries the same warning for entity counts.
    func testPageNumbersAreSetInTheReadersDigits() throws {
        let arabic = Locale(identifier: "ar_EG")
        // Not vacuous: this locale really does shape digits differently. Asserted rather than
        // assumed, because `ar` and `ar_AE` do not — they would make the whole test pass hollow.
        XCTAssertEqual(1.formatted(.number.locale(arabic)), "١")

        let pdf = try renderedPDF(contentsFixture(
            chrome: ReportChrome(pageFormat: "Page %1$@ of %2$@", locale: arabic)))

        let footers = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(footers.contains("Page ١ of"),
                      "the footer does not number its pages in the reader's digits")
        XCTAssertFalse(footers.contains("Page 1 of"),
                       "the footer still prints Latin page numbers into an Arabic-Indic document")

        // Physical page 1 is the contents page (page 0 is the cover, and `drawFooter` runs only on
        // body pages), so every digit on it is one this document printed against a contents entry.
        let contents = try XCTUnwrap(pdf.page(at: 1)?.string, "no contents page was rendered")
        XCTAssertTrue(contents.contains { "٠١٢٣٤٥٦٧٨٩".contains($0) },
                      "the contents page printed no Arabic-Indic digits at all")
        XCTAssertFalse(contents.contains { $0.isASCII && $0.isNumber },
                       "the contents page still cites Latin page numbers: \"\(contents)\"")
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
                               locale: Locale? = nil,
                               usesLiveRates: Bool = true) -> ReportDocument {
        let snapshot = usesLiveRates ? self.snapshot : nil
        return ReportDocumentBuilder(
            context: ReportBuildContext(
                data: data ?? self.data,
                converter: CurrencyConverter(snapshot: snapshot),
                baseCurrency: .eur,
                exchangeRateSnapshot: snapshot,
                appLanguage: nil,
                locale: locale ?? self.locale,
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

        // ...and the note beneath the ledger has to agree with the one row it is describing. The
        // note was a plain lookup with the count substituted afterwards by `String(format:)`, so
        // the catalog's plural variations could never be reached and every export read
        // "1 future-dated entries are listed in grey".
        var note: String?
        for block in document.sections.first(where: { $0.anchor == anchor })?.blocks ?? [] {
            if case let .note(text) = block, text.contains("future-dated") { note = text }
        }
        XCTAssertTrue(try XCTUnwrap(note, "the ledger stopped noting its future-dated rows")
                        .hasPrefix("1 future-dated entry is listed in grey."),
                      note ?? "")

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

    // MARK: - Cash-flow tiles

    /// Every block of the cash-flow section under test, in document order.
    private func cashFlowBlocks(_ document: ReportDocument) throws -> [ReportBlock] {
        try XCTUnwrap(document.sections.first { $0.anchor == ReportSection.cashFlow.anchor }?.blocks,
                      "the document has no cash-flow section")
    }

    /// The value cell of the ledger subtotal row whose label contains `month`.
    private func monthSubtotal(_ document: ReportDocument, month: String) throws -> String {
        for block in try cashFlowBlocks(document) {
            guard case let .table(table) = block else { continue }
            for row in table.rows where row.style == .subtotal {
                if row.cells.count > 3, row.cells[1].contains(month) { return row.cells[3] }
            }
        }
        XCTFail("no ledger subtotal row for \(month)")
        return ""
    }

    /// An All Time export's headline tiles have to be arithmetic the ledger below them agrees with.
    ///
    /// The bounded branch accumulates `signedAmount`, which rounds each conversion to the minor
    /// unit *before* summing, exactly as `roundedMoney` requires and exactly as the printed rows
    /// and month subtotals do. The unbounded branch went through `AnalyticsEngine.monthlyCashFlow`,
    /// which reduces over raw conversions — so an All Time report printed a "This Month" figure
    /// that did not equal the subtotal of the very rows it was summing, a few inches below it on
    /// the same page. An all-EUR fixture cannot show this: there has to be a conversion remainder
    /// to drift, which is why every row here is USD.
    func testAllTimeCashFlowTilesAgreeWithTheLedgerSubtotalUnderThem() throws {
        var monthly = FinancialData()
        monthly.transactions =
            (0..<120).map { index in
                Transaction(type: .income, category: "Salary", amount: 200,
                            description: "in-\(index)", date: day(2026, 7, 10), currency: .usd)
            } + (0..<80).map { index in
                Transaction(type: .expense, category: "Rent", amount: 200,
                            description: "out-\(index)", date: day(2026, 7, 11), currency: .usd)
            }

        // Guard against the fixture quietly going vacuous. 200 USD at 1.0842 is 184.4678… EUR, so
        // the rounded and the unrounded accumulations of the net 40 rows have to land on different
        // printed figures — otherwise this test would pass with the defect still in place.
        let converter = CurrencyConverter(snapshot: snapshot)
        var raw = converter.convert(Decimal(200), from: .usd, to: .eur)
        var perRow = Decimal()
        NSDecimalRound(&perRow, &raw, 2, .plain)
        XCTAssertNotEqual(perRow * 40, raw * 40, "the fixture no longer has a rounding remainder")

        let document = buildDocument(sections: [.cashFlow], range: .allTime, data: monthly)
        let netSavings = try XCTUnwrap(
            kpi(document, section: ReportSection.cashFlow.anchor, label: "Net Savings"),
            "the cash-flow section stopped printing a Net Savings tile")
        let subtotal = try monthSubtotal(document, month: "July 2026")

        XCTAssertEqual(
            amount(netSavings), amount(subtotal),
            """
            the Net Savings tile prints \(netSavings) while the ledger subtotal for the same month, \
            over the same rows, prints \(subtotal)
            """
        )
        XCTAssertEqual(amount(subtotal), perRow * 40, "the ledger subtotal is not the rounded sum")
    }

    // MARK: - Calendars

    /// The ledger's year headings and the row dates beneath them reckon in one calendar.
    ///
    /// An audit reported these as split — headings on the device calendar, the dates on the report
    /// *locale*'s — and they are not. `Date.FormatStyle.locale(_:)` sets the locale alone; the
    /// style's `calendar` stays at its `.autoupdatingCurrent` default, so a Thai locale still
    /// prints Gregorian years unless the *device* calendar is Buddhist — and the device calendar is
    /// precisely what `context.calendar` carries, since `FinanceStore.exportReportURL` passes
    /// `.current`. Grouping and formatting therefore already share one calendar system on every
    /// device.
    ///
    /// Pinned rather than left implicit because the obvious repair — deriving `context.calendar`
    /// from `context.locale` — would move the grouping to the locale's calendar while leaving the
    /// printed dates on the device's, manufacturing the exact split it was meant to close.
    func testLedgerYearHeadingsAgreeWithTheDatesPrintedUnderThem() throws {
        // The report's date styles format in `Calendar.autoupdatingCurrent` — which is the point
        // being pinned — so the assertion only means anything while the host agrees with the
        // Gregorian calendar this context is built with. In the app they cannot disagree, because
        // `context.calendar` is `.current`; in a test they can, so say so rather than let a host
        // misconfiguration read as a defect in the report.
        try XCTSkipUnless(Calendar.current.identifier == .gregorian,
                          "host calendar is \(Calendar.current.identifier), not Gregorian")

        let thai = Locale(identifier: "th_TH")
        // Not vacuous: this locale really does carry a different calendar, 543 years ahead of the
        // Gregorian one the context is built with.
        XCTAssertEqual(thai.calendar.component(.year, from: day(2024, 3, 15)), 2567)
        XCTAssertEqual(calendar.component(.year, from: day(2024, 3, 15)), 2024)

        let document = buildDocument(sections: [.cashFlow], range: .allTime, locale: thai)

        var heading: String?
        var rowsChecked = 0
        for block in try cashFlowBlocks(document) {
            switch block {
            case let .subheading(title, anchor) where anchor?.hasPrefix("ledger-") == true:
                heading = title
            case let .table(table):
                guard let year = heading else { continue }
                for row in table.rows where row.style != .subtotal {
                    XCTAssertTrue(
                        row.cells[0].contains(year),
                        "row dated \"\(row.cells[0])\" is filed under the heading \"\(year)\""
                    )
                    rowsChecked += 1
                }
            default:
                break
            }
        }
        XCTAssertGreaterThan(rowsChecked, 0, "no ledger rows were examined")
    }
}

/// Every entity count the exported report prints, read in a locale that groups thousands.
///
/// The in-app sites were swept by `AppSettings.privateCount(_:)` and are pinned by
/// `PrivacyRedactionTests.testWorkingTreeRendersNoUnformattedEntityCount`. The export was excluded
/// from that lint — the exemption is about redaction, and an export redacts nothing by design — so
/// its eight counts kept interpolating straight into a `String` and printed `1234` for every
/// reader, in every language.
///
/// **Why the locale and the language are set apart here.** `FinanceStore.exportReport` derives
/// `context.locale` from `AppLocalization.effectiveLocale(appLanguage:)`, which is `.current` when
/// no in-app override is set. `appLanguage: nil` with `locale: de_DE` is therefore not a contrived
/// pairing but the ordinary case: a reader in Germany who never opened the language picker. It also
/// keeps every label in English so this can find the rows by their English text while the numbers
/// are formatted for Germany, which is the only thing under test.
final class ReportCountFormattingTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 27; components.hour = 12
        return calendar.date(from: components)!
    }

    /// 1,234 of everything: the smallest count that separates a grouped rendering from a bare one
    /// in every locale this app ships, and the value the in-app twin
    /// (`PrivacyRedactionTests.testCountsAreFormattedForTheReadersLocale`) already uses.
    private static let population = 1_234

    private func makeData() -> FinancialData {
        var data = FinancialData()
        data.transactions = (0..<Self.population).map { index in
            Transaction(type: index.isMultiple(of: 2) ? .income : .expense, category: "Salary",
                        amount: 10, description: "t\(index)", date: now, currency: .eur)
        }
        data.recurringTransactions = (0..<Self.population).map { index in
            RecurringTransaction(
                type: .expense, category: "Rent", amount: 5, description: "r\(index)",
                startDate: now, frequency: .monthly, nextDueDate: now, endDate: nil,
                notificationsEnabled: false, isActive: true, completedAt: nil,
                createdAt: now, updatedAt: now)
        }
        data.investments = (0..<Self.population).map { index in
            Investment(type: .stock, symbol: "S\(index)", name: "n\(index)", quantity: 1,
                       costBasis: 10, currentValue: 12, currentPrice: 12, currency: .eur,
                       geography: "US", sector: "Tech", isin: "", fees: 0)
        }
        data.crypto = (0..<Self.population).map { index in
            CryptoHolding(symbol: "C\(index)", name: "c\(index)", quantity: 1, avgBuyPrice: 10,
                          currentPrice: 12, currency: .eur, fees: 0, coinId: "")
        }
        data.liabilities = (0..<Self.population).map { index in
            Liability(name: "l\(index)", currentBalance: 100, currency: .eur)
        }
        data.snapshots = (0..<Self.population).map { index in
            NetWorthSnapshot(date: calendar.date(byAdding: .day, value: -index, to: now)!,
                             totalAssets: 100, totalLiabilities: 0, netWorth: 100,
                             liquidity: 100, investments: 0, crypto: 0)
        }
        return data
    }

    private func buildDocument(locale: Locale) -> ReportDocument {
        ReportDocumentBuilder(
            context: ReportBuildContext(
                data: makeData(),
                converter: CurrencyConverter(snapshot: nil),
                baseCurrency: .eur,
                exchangeRateSnapshot: nil,
                appLanguage: nil,
                locale: locale,
                calendar: calendar,
                now: now,
                appVersion: "1", appBuild: "1", platformName: "test",
                brandMarkPNG: nil,
                paper: .a4,
                direction: .leftToRight),
            options: ReportExportOptions(format: .pdf,
                                         sections: Set(ReportSection.allCases),
                                         dateRange: .allTime)).build()
    }

    /// Every count the document prints, by the label it is printed against.
    private func printedCounts(_ document: ReportDocument) -> [String: String] {
        var found: [String: String] = [:]
        for section in document.sections {
            for block in section.blocks {
                switch block {
                case let .kpis(items):
                    for item in items where item.label == "Holdings" {
                        // The two `Holdings` tiles are identical in label and, here, in value; key
                        // them by section so neither can silently stand in for the other.
                        found["\(section.title) · Holdings"] = item.value
                    }
                case let .keyValues(rows):
                    for row in rows { found[row.label] = row.value }
                default:
                    break
                }
            }
        }
        return found
    }

    /// The eight sites, all of them, by the label the reader sees.
    private static let countLabels = [
        "Investments · Holdings", "Crypto · Holdings",
        "Transactions", "Recurring Rules", "Investments", "Crypto Holdings",
        "Liabilities", "Net Worth Snapshots",
    ]

    func testEveryPrintedEntityCountIsGroupedForTheReadersLocale() throws {
        let german = printedCounts(buildDocument(locale: Locale(identifier: "de_DE")))
        let french = printedCounts(buildDocument(locale: Locale(identifier: "fr_FR")))

        // Not asserted against a hardcoded "1 234": the French group separator is U+202F in current
        // CLDR and was U+00A0 before it, and pinning that would make this a test of ICU's data
        // rather than of the report. What the report owes the reader is the locale's own rendering.
        let expectedGerman = Self.population.formatted(.number.locale(Locale(identifier: "de_DE")))
        let expectedFrench = Self.population.formatted(.number.locale(Locale(identifier: "fr_FR")))
        XCTAssertEqual(expectedGerman, "1.234", "the German rendering has moved under the test")
        XCTAssertNotEqual(expectedFrench, expectedGerman, "the two locales must differ to be a test")

        for label in Self.countLabels {
            let printed = try XCTUnwrap(german[label], "no count printed against \"\(label)\"")
            XCTAssertNotEqual(
                printed, "1234",
                """
                "\(label)" prints \(Self.population) unformatted, so a German reader sees 1234 \
                rather than 1.234 — and so does every other reader, in every language.
                """
            )
            XCTAssertEqual(printed, expectedGerman, "\"\(label)\" is not grouped the German way")
            XCTAssertEqual(
                try XCTUnwrap(french[label]), expectedFrench,
                "\"\(label)\" ignores the reader's locale — it renders the same in de and fr"
            )
        }
    }
}
