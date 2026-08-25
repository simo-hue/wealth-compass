import CoreGraphics
import Foundation

// MARK: - Layout results

/// A block — or one chunk of a split table — placed at a known position on a known page.
struct PlacedBlock: Sendable {
    var block: ReportBlock
    /// Logical top-down origin (leading-origin x, y measured downward from the page top).
    var origin: CGPoint
    var size: CGSize
}

struct LaidOutPage: Sendable {
    /// Printed page number. Body pages are numbered 1…N; the cover and contents are unnumbered,
    /// so these numbers are what the contents page cites and what the footer prints.
    var pageNumber: Int
    var sectionTitle: String
    /// Set only on a section's first page, where the named PDF destination is anchored.
    var sectionAnchor: String?
    var blocks: [PlacedBlock]
}

/// One line of the contents page, and one node of the PDFKit outline.
struct ReportContentsEntry: Sendable {
    var title: String
    var anchor: String
    var pageNumber: Int
    /// 0 = section, 1 = subsection.
    var level: Int
}

struct PaginatedReport: Sendable {
    var pages: [LaidOutPage]
    var contents: [ReportContentsEntry]

    var pageCount: Int { pages.count }
}

// MARK: - Paginator

/// Measures every block and flows it onto pages.
///
/// This is a *measure* pass: it draws nothing. Because CoreText can size text without a graphics
/// context, pagination is exact rather than estimated — which is what lets the contents page cite
/// real page numbers, lets the progress UI report "page 34 of 112" before drawing starts, and lets
/// the arithmetic be unit-tested.
///
/// Only `.table` can be split across a page boundary. Everything else moves whole to the next page
/// when it does not fit.
struct ReportPaginator {
    let document: ReportDocument
    /// Used purely for text measurement; no drawing happens here.
    let measuring: PDFDrawingContext

    private var theme: ReportTheme { document.theme }
    private var metrics: ReportMetrics { theme.metrics }

    init(document: ReportDocument, measuring: PDFDrawingContext) {
        self.document = document
        self.measuring = measuring
    }

    // MARK: Entry point

    func paginate() -> PaginatedReport {
        var pages: [LaidOutPage] = []
        var contents: [ReportContentsEntry] = []

        let contentWidth = theme.contentWidth
        let originX = metrics.marginLeading
        let topY = theme.contentTop
        let maxY = topY + theme.contentHeight

        for section in document.sections {
            // Every section starts on a fresh page: the requirement was explicitly that sections
            // are visually separated, and a section beginning halfway down a page reads as a
            // continuation of the previous one.
            var current = LaidOutPage(pageNumber: pages.count + 1,
                                      sectionTitle: section.title,
                                      sectionAnchor: section.anchor,
                                      blocks: [])
            var cursor = topY

            contents.append(ReportContentsEntry(title: section.title,
                                                anchor: section.anchor,
                                                pageNumber: current.pageNumber,
                                                level: 0))

            func startNewPage() {
                pages.append(current)
                current = LaidOutPage(pageNumber: pages.count + 1,
                                      sectionTitle: section.title,
                                      sectionAnchor: nil,
                                      blocks: [])
                cursor = topY
            }

            for (index, block) in section.blocks.enumerated() {
                // Subsection anchors become second-level contents entries, resolved to whichever
                // page they actually land on — which is only knowable here, mid-flow.
                if case let .subheading(title, anchor) = block, let anchor {
                    let needed = height(of: block, width: contentWidth)
                    // Look ahead at what the heading actually introduces. Reserving a constant
                    // was not enough: a heading is followed by a table, and a table needs its
                    // caption, header and `tableMinimumOrphanRows` rows before the paginator will
                    // place any of it — so a heading could still strand alone at the page foot
                    // with its table starting overleaf, which is exactly what this guards against.
                    let following = section.blocks.indices.contains(index + 1)
                        ? minimumFollowingHeight(of: section.blocks[index + 1], width: contentWidth)
                        : 0
                    if cursor + needed + following > maxY, !current.blocks.isEmpty {
                        startNewPage()
                    }
                    contents.append(ReportContentsEntry(title: title,
                                                        anchor: anchor,
                                                        pageNumber: current.pageNumber,
                                                        level: 1))
                }

                if case let .table(table) = block {
                    var remaining = table
                    while true {
                        let available = maxY - cursor
                        let split = splitTable(remaining, availableHeight: available, width: contentWidth)

                        if let chunk = split.fitting {
                            let chunkHeight = height(ofTable: chunk, width: contentWidth)
                            current.blocks.append(PlacedBlock(
                                block: .table(chunk),
                                origin: CGPoint(x: originX, y: cursor),
                                size: CGSize(width: contentWidth, height: chunkHeight)))
                            cursor += chunkHeight + metrics.blockSpacing
                        }

                        guard let leftover = split.remainder else { break }
                        // Nothing fit and the page is already empty: the table's header alone
                        // exceeds a full page, which cannot happen with the current metrics but
                        // would otherwise spin forever. Bail rather than loop.
                        if split.fitting == nil && current.blocks.isEmpty { break }
                        startNewPage()
                        remaining = leftover
                    }
                    continue
                }

                let blockHeight = height(of: block, width: contentWidth)
                if cursor + blockHeight > maxY, !current.blocks.isEmpty {
                    startNewPage()
                }
                current.blocks.append(PlacedBlock(
                    block: block,
                    origin: CGPoint(x: originX, y: cursor),
                    size: CGSize(width: contentWidth, height: blockHeight)))
                cursor += blockHeight + metrics.blockSpacing
            }

            pages.append(current)
        }

        return PaginatedReport(pages: pages, contents: contents)
    }

    // MARK: - Measurement

    func height(of block: ReportBlock, width: CGFloat) -> CGFloat {
        switch block {
        case let .sectionTitle(title, subtitle):
            var height = measuring.measure(title, role: .sectionTitle, width: width)
            if let subtitle, !subtitle.isEmpty {
                height += 3 + measuring.measure(subtitle, role: .sectionSubtitle, width: width)
            }
            // Accent rule beneath the title plus breathing room.
            return height + 10

        case let .subheading(title, _):
            return measuring.measure(title, role: .subheading, width: width) + 4

        case let .paragraph(text):
            return measuring.measure(text, role: .body, width: width, lineHeightMultiple: 1.35)

        case let .note(text):
            return measuring.measure(text, role: .note, width: width, lineHeightMultiple: 1.3)

        case let .kpis(items):
            guard !items.isEmpty else { return 0 }
            let perRow = max(1, metrics.kpisPerRow)
            let rows = Int(ceil(Double(items.count) / Double(perRow)))
            return CGFloat(rows) * metrics.kpiHeight + CGFloat(rows - 1) * metrics.kpiSpacing

        case let .chart(chart):
            return ReportChartRenderer.height(for: chart, width: width, context: measuring)

        case let .table(table):
            return height(ofTable: table, width: width)

        case let .keyValues(pairs):
            guard !pairs.isEmpty else { return 0 }
            return CGFloat(pairs.count) * (measuring.lineHeight(for: .body) + 4)

        case let .spacer(amount):
            return amount
        }
    }

    func height(ofTable table: ReportTable, width: CGFloat) -> CGFloat {
        var height: CGFloat = 0
        if let caption = table.caption, !caption.isEmpty {
            height += measuring.measure(caption, role: .tableCaption, width: width) + 4
        }
        height += metrics.tableHeaderHeight
        if table.rows.isEmpty {
            // Empty tables still print a "no entries" line so a missing section reads as
            // deliberately empty rather than as a rendering failure.
            height += metrics.tableRowHeight
        } else {
            height += table.rows.reduce(0) { $0 + rowHeight($1) }
        }
        if table.footer != nil {
            height += metrics.tableRowHeight + 2
        }
        return height
    }

    /// The least vertical space a block needs before the paginator will place *any* of it on the
    /// current page. For most blocks that is their full height; a table is splittable, so it only
    /// needs its caption, header and the minimum non-orphan run of rows.
    func minimumFollowingHeight(of block: ReportBlock, width: CGFloat) -> CGFloat {
        guard case let .table(table) = block else {
            return metrics.blockSpacing + height(of: block, width: width)
        }
        var minimum = metrics.blockSpacing + metrics.tableHeaderHeight
        if let caption = table.caption, !caption.isEmpty {
            minimum += measuring.measure(caption, role: .tableCaption, width: width) + 4
        }
        let rows = table.rows.prefix(metrics.tableMinimumOrphanRows)
        minimum += rows.isEmpty
            ? metrics.tableRowHeight
            : rows.reduce(0) { $0 + rowHeight($1) }
        return minimum
    }

    func rowHeight(_ row: ReportRow) -> CGFloat {
        metrics.tableRowHeight + (row.secondary.map { $0.isEmpty ? 0 : metrics.tableSecondaryHeight } ?? 0)
    }

    // MARK: - Table splitting

    struct TableSplit {
        /// The chunk that fits on the current page, or nil when not even the header plus the
        /// minimum row count fits.
        var fitting: ReportTable?
        /// Rows that did not fit, as a continuation table, or nil when the whole table fit.
        var remainder: ReportTable?
    }

    /// Splits a table so it flows across pages, repeating the column header on every chunk and
    /// carrying the totals row only onto the final one.
    func splitTable(_ table: ReportTable, availableHeight: CGFloat, width: CGFloat) -> TableSplit {
        let fullHeight = height(ofTable: table, width: width)
        if fullHeight <= availableHeight {
            return TableSplit(fitting: table, remainder: nil)
        }

        var overhead: CGFloat = metrics.tableHeaderHeight
        if let caption = table.caption, !caption.isEmpty {
            overhead += measuring.measure(caption, role: .tableCaption, width: width) + 4
        }

        var used = overhead
        var takenCount = 0
        for row in table.rows {
            let next = used + rowHeight(row)
            if next > availableHeight { break }
            used = next
            takenCount += 1
        }

        // Refuse to leave a stub of one or two rows stranded at the foot of a page — it reads as
        // an accident. Push the whole table to the next page instead.
        if takenCount < metrics.tableMinimumOrphanRows {
            return TableSplit(fitting: nil, remainder: table)
        }
        if takenCount >= table.rows.count {
            // Every row fits; only the footer pushed it over. Carry the LAST row onto the
            // continuation chunk with the footer rather than sending a row-empty table forward:
            // a chunk with no rows renders as "No entries recorded." and the totals row is lost
            // outright — silently deleting the one figure the table exists to state.
            let carried = max(1, table.rows.count - takenCount + 1)
            if table.rows.count - carried < metrics.tableMinimumOrphanRows {
                return TableSplit(fitting: nil, remainder: table)
            }
            var head = table
            head.rows = Array(table.rows.dropLast(carried))
            head.footer = nil
            var tail = table
            tail.rows = Array(table.rows.suffix(carried))
            tail.caption = continuedCaption(for: table)
            return TableSplit(fitting: head, remainder: tail)
        }

        var head = table
        head.rows = Array(table.rows.prefix(takenCount))
        head.footer = nil

        var tail = table
        tail.rows = Array(table.rows.dropFirst(takenCount))
        tail.caption = continuedCaption(for: table)

        return TableSplit(fitting: head, remainder: tail)
    }

    private func continuedCaption(for table: ReportTable) -> String? {
        guard let caption = table.caption, !caption.isEmpty else { return nil }
        // Strip a suffix already applied, so a table spanning four pages does not accumulate
        // "(continued) (continued) (continued)".
        let suffix = " " + document.chrome.continuedSuffix
        let base = caption.hasSuffix(suffix) ? String(caption.dropLast(suffix.count)) : caption
        return base + suffix
    }
}

// MARK: - Contents pagination

extension ReportPaginator {
    /// Splits contents entries across as many contents pages as they need. Almost always one page;
    /// a report with a decade of ledger years can need two.
    func paginateContents(_ entries: [ReportContentsEntry]) -> [[ReportContentsEntry]] {
        guard !entries.isEmpty else { return [] }

        let titleHeight = measuring.measure(document.chrome.contentsTitle,
                                            role: .contentsTitle,
                                            width: theme.contentWidth) + 18
        var pages: [[ReportContentsEntry]] = []
        var current: [ReportContentsEntry] = []
        var used = titleHeight
        let maxHeight = theme.contentHeight + metrics.headerHeight  // contents pages carry no running head

        for entry in entries {
            let lineHeight = entry.level == 0
                ? measuring.lineHeight(for: .contentsEntry) + 8
                : measuring.lineHeight(for: .contentsSubEntry) + 3
            if used + lineHeight > maxHeight, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(entry)
            used += lineHeight
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// Whether the report warrants a contents page at all.
    ///
    /// A four-holding crypto export would otherwise get three pages of scaffolding around two
    /// pages of content; a single-section Cash Flow export with seventy pages of ledger needs the
    /// navigation just as much as the full report does. So length earns a contents page on its own
    /// — but so does having more than one section, however short each one is, because that is the
    /// point at which the reader has somewhere to navigate *to*.
    static func needsContentsPage(bodyPageCount: Int, sectionCount: Int) -> Bool {
        sectionCount >= 2 || bodyPageCount > 4
    }
}
