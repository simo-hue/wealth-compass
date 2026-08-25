import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum ReportRenderError: LocalizedError {
    case couldNotCreatePDFContext
    case couldNotAttachOutline
    case cancelled

    var errorDescription: String? {
        switch self {
        case .couldNotCreatePDFContext: return "Could not create the PDF document."
        case .couldNotAttachOutline: return "Could not finalise the PDF document."
        case .cancelled: return "Export cancelled."
        }
    }
}

/// Renders a `ReportDocument` to a PDF file.
///
/// Pure CoreGraphics + CoreText + PDFKit: no SwiftUI, no UIKit, no AppKit, no app types. That is
/// deliberate — it keeps the whole renderer runnable from `scripts/render_sample_report.swift`
/// with the Command Line Tools alone, so the output can be inspected before anyone builds the app.
///
/// Structure: cover → (optional) contents → body. Body pages carry printed numbers 1…N; the cover
/// and contents are unnumbered, which is why the contents page can cite page numbers derived from
/// a single measure pass without a second layout iteration.
enum PDFReportRenderer {

    /// - Parameter progress: called with (completedPages, totalPages) on the calling thread as
    ///   each page is drawn. Total is known before drawing because pagination is a measure pass.
    /// - Parameter isCancelled: polled between pages so a large export can be abandoned.
    static func render(document: ReportDocument,
                       to url: URL,
                       progress: (@Sendable (Int, Int) -> Void)? = nil,
                       isCancelled: (@Sendable () -> Bool)? = nil) throws {
        do {
            try performRender(document: document, to: url, progress: progress, isCancelled: isCancelled)
        } catch {
            // A half-written PDF is still a structurally openable file, so leaving one behind at
            // the canonical export path hands the user a report that looks fine and is silently
            // truncated. Delete it on every failure path, cancellation included.
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func performRender(document: ReportDocument,
                                      to url: URL,
                                      progress: (@Sendable (Int, Int) -> Void)?,
                                      isCancelled: (@Sendable () -> Bool)?) throws {
        let theme = document.theme
        var mediaBox = CGRect(origin: .zero, size: theme.pageSize)

        guard let cg = CGContext(url as CFURL, mediaBox: &mediaBox, documentInfo(for: document)) else {
            throw ReportRenderError.couldNotCreatePDFContext
        }
        let context = PDFDrawingContext(cg: cg, theme: theme, chrome: document.chrome)

        let paginator = ReportPaginator(document: document, measuring: context)
        let layout = paginator.paginate()

        let contentsPages: [[ReportContentsEntry]]
        if ReportPaginator.needsContentsPage(
            bodyPageCount: layout.pageCount,
            sectionCount: document.sections.filter { !$0.isStructural }.count) {
            contentsPages = paginator.paginateContents(layout.contents)
        } else {
            contentsPages = []
        }

        // +1 for the finalisation step (closePDF plus the PDFKit outline pass). That work is a
        // meaningful share of a large export's wall-clock, so excluding it left the bar sitting at
        // 100% while the user waited — and left the last stretch unresponsive to Cancel.
        let totalPhysicalPages = 1 + contentsPages.count + layout.pageCount + 1
        var drawn = 0
        func tick() throws {
            drawn += 1
            if isCancelled?() == true { throw ReportRenderError.cancelled }
            progress?(drawn, totalPhysicalPages)
        }

        // Cover
        cg.beginPDFPage(nil)
        drawCover(document: document, context: context)
        cg.endPDFPage()
        try tick()

        // Contents
        for (index, entries) in contentsPages.enumerated() {
            cg.beginPDFPage(nil)
            drawContents(entries,
                         isFirstPage: index == 0,
                         document: document,
                         context: context)
            cg.endPDFPage()
            try tick()
        }

        // Body
        for page in layout.pages {
            cg.beginPDFPage(nil)
            if let anchor = page.sectionAnchor {
                context.addDestination(anchor)
            }
            drawRunningHead(page: page, document: document, context: context)
            drawFooter(page: page, totalBodyPages: layout.pageCount, document: document, context: context)
            for placed in page.blocks {
                draw(placed, document: document, context: context)
            }
            cg.endPDFPage()
            try tick()
        }

        // Honour a Cancel pressed during the last page rather than delivering the file anyway.
        if isCancelled?() == true { throw ReportRenderError.cancelled }
        cg.closePDF()
        try tick()
        if isCancelled?() == true { throw ReportRenderError.cancelled }

        // Second pass: PDFKit attaches the sidebar outline and document attributes. This exists
        // because CGPDFContextSetOutline throws inside convertOutlineTree on current OS versions
        // for every documented dictionary shape — verified. The link annotations emitted above
        // survive the rewrite.
        try attachOutline(to: url,
                          entries: layout.contents,
                          coverAndContentsPageCount: 1 + contentsPages.count,
                          metadata: document.metadata)
    }

    private static func documentInfo(for document: ReportDocument) -> CFDictionary {
        [
            kCGPDFContextTitle as String: document.metadata.documentTitle,
            kCGPDFContextAuthor as String: document.metadata.brandName,
            kCGPDFContextCreator as String: "\(document.metadata.brandName) \(document.metadata.appVersion)",
        ] as CFDictionary
    }

    // MARK: - Cover

    private static func drawCover(document: ReportDocument, context: PDFDrawingContext) {
        let theme = document.theme
        let metrics = theme.metrics
        let palette = theme.palette
        let metadata = document.metadata
        let width = theme.pageSize.width

        context.fill(CGRect(x: 0, y: 0, width: width, height: metrics.coverBandHeight),
                     color: palette.coverBackground)

        var y = metrics.marginTop

        if let png = metadata.brandMarkPNG {
            context.drawImage(png, in: CGRect(x: metrics.marginLeading,
                                              y: y,
                                              width: metrics.brandMarkSize,
                                              height: metrics.brandMarkSize))
            y += metrics.brandMarkSize + 22
        }

        context.drawLine(metadata.brandName,
                         role: .coverWordmark,
                         color: palette.brandBright,
                         in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth, height: 20))
        y += context.lineHeight(for: .coverWordmark) + 10

        let titleHeight = context.measure(metadata.documentTitle, role: .coverTitle, width: theme.contentWidth)
        context.draw(metadata.documentTitle,
                     role: .coverTitle,
                     color: palette.coverInk,
                     in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth, height: titleHeight))
        y += titleHeight + 8

        context.drawLine(metadata.scopeLine,
                         role: .coverSubtitle,
                         color: palette.coverInkMuted,
                         in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth, height: 20))

        // The facts block and the disclaimer are both anchored to the foot of the page rather than
        // floated under the band. A metadata block hanging directly below the banner leaves half
        // the cover visibly empty; pinning it low turns that space into deliberate whitespace, the
        // composition every printed annual report uses.
        var facts: [ReportKeyValue] = []
        if let period = metadata.periodLine {
            facts.append(ReportKeyValue(document.chrome.periodLabel, period))
        }
        facts.append(ReportKeyValue(document.chrome.baseCurrencyLabel, metadata.baseCurrencyLine))
        facts.append(ReportKeyValue(document.chrome.generatedLabel, metadata.generatedLine))

        let disclaimerHeight = context.measure(document.chrome.coverDisclaimer,
                                               role: .note,
                                               width: theme.contentWidth,
                                               lineHeightMultiple: 1.3)
        let disclaimerTop = theme.pageSize.height - metrics.marginBottom - disclaimerHeight
        let factsHeight = 22 + CGFloat(facts.count) * 24
        // Never let the facts collide with the band on a short page (US Letter is 50pt shorter).
        let factsTop = max(metrics.coverBandHeight + 46, disclaimerTop - 44 - factsHeight)

        y = factsTop
        context.rule(x: metrics.marginLeading, y: y, width: 54, thickness: 2, color: palette.brand)
        y += 22

        for fact in facts {
            context.drawLine(fact.label,
                             role: .kpiLabel,
                             color: palette.inkMuted,
                             in: CGRect(x: metrics.marginLeading, y: y, width: 150, height: 14))
            context.drawLine(fact.value,
                             role: .body,
                             color: palette.ink,
                             in: CGRect(x: metrics.marginLeading + 158, y: y - 2,
                                        width: theme.contentWidth - 158, height: 16))
            y += 24
        }

        context.draw(document.chrome.coverDisclaimer,
                     role: .note,
                     color: palette.inkMuted,
                     in: CGRect(x: metrics.marginLeading,
                                y: disclaimerTop,
                                width: theme.contentWidth,
                                height: disclaimerHeight),
                     lineHeightMultiple: 1.3)
    }

    // MARK: - Contents

    private static func drawContents(_ entries: [ReportContentsEntry],
                                     isFirstPage: Bool,
                                     document: ReportDocument,
                                     context: PDFDrawingContext) {
        let theme = document.theme
        let metrics = theme.metrics
        let palette = theme.palette
        var y = metrics.marginTop

        if isFirstPage {
            let titleHeight = context.measure(document.chrome.contentsTitle,
                                              role: .contentsTitle,
                                              width: theme.contentWidth)
            context.draw(document.chrome.contentsTitle,
                         role: .contentsTitle,
                         color: palette.ink,
                         in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth, height: titleHeight))
            y += titleHeight + 6
            context.rule(x: metrics.marginLeading, y: y, width: 54, thickness: 2, color: palette.brand)
            y += 18
        }

        for entry in entries {
            let role: ReportFontRole = entry.level == 0 ? .contentsEntry : .contentsSubEntry
            let color = entry.level == 0 ? palette.ink : palette.inkSecondary
            let indent: CGFloat = entry.level == 0 ? 0 : 18
            let lineHeight = context.lineHeight(for: role)
            let rowY = y

            let pageString = "\(entry.pageNumber)"
            let pageWidth = context.width(of: pageString, role: role) + 4
            let titleX = metrics.marginLeading + indent
            let titleWidth = context.width(of: entry.title, role: role)
            let available = theme.contentWidth - indent - pageWidth - 12

            context.drawLine(entry.title,
                             role: role,
                             color: color,
                             in: CGRect(x: titleX, y: rowY, width: min(titleWidth, available), height: lineHeight))

            // Dot leader between the title and the page number.
            let leaderStart = titleX + min(titleWidth, available) + 6
            let leaderEnd = metrics.marginLeading + theme.contentWidth - pageWidth - 6
            if leaderEnd > leaderStart {
                context.rule(x: leaderStart,
                             y: rowY + lineHeight * 0.62,
                             width: leaderEnd - leaderStart,
                             thickness: 0.5,
                             color: palette.hairlineStrong)
            }

            context.drawLine(pageString,
                             role: role,
                             color: color,
                             in: CGRect(x: metrics.marginLeading + theme.contentWidth - pageWidth,
                                        y: rowY, width: pageWidth, height: lineHeight),
                             alignment: .trailing,
                             isNumeric: true)

            // Whole row is clickable, not just the title.
            context.link(to: entry.anchor,
                         in: CGRect(x: metrics.marginLeading, y: rowY - 2,
                                    width: theme.contentWidth, height: lineHeight + 4))

            y += lineHeight + (entry.level == 0 ? 8 : 3)
        }
    }

    // MARK: - Page chrome

    private static func drawRunningHead(page: LaidOutPage,
                                        document: ReportDocument,
                                        context: PDFDrawingContext) {
        let theme = document.theme
        let metrics = theme.metrics
        let palette = theme.palette
        let y = metrics.marginTop - 18

        context.drawLine(document.metadata.brandName,
                         role: .runningHead,
                         color: palette.inkMuted,
                         in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth / 2, height: 12))

        context.drawLine(page.sectionTitle,
                         role: .runningHead,
                         color: palette.inkMuted,
                         in: CGRect(x: metrics.marginLeading + theme.contentWidth / 2, y: y,
                                    width: theme.contentWidth / 2, height: 12),
                         alignment: .trailing)

        context.rule(x: metrics.marginLeading, y: metrics.marginTop - 2,
                     width: theme.contentWidth, thickness: 0.5, color: palette.hairline)
    }

    private static func drawFooter(page: LaidOutPage,
                                   totalBodyPages: Int,
                                   document: ReportDocument,
                                   context: PDFDrawingContext) {
        let theme = document.theme
        let metrics = theme.metrics
        let palette = theme.palette
        let y = theme.pageSize.height - metrics.marginBottom + 6

        context.rule(x: metrics.marginLeading, y: y - 8, width: theme.contentWidth,
                     thickness: 0.5, color: palette.hairline)

        context.drawLine(document.metadata.footerNote,
                         role: .pageNumber,
                         color: palette.inkMuted,
                         in: CGRect(x: metrics.marginLeading, y: y, width: theme.contentWidth * 0.7, height: 12))

        let pageText = String(format: document.chrome.pageFormat, "\(page.pageNumber)", "\(totalBodyPages)")
        context.drawLine(pageText,
                         role: .pageNumber,
                         color: palette.inkMuted,
                         in: CGRect(x: metrics.marginLeading + theme.contentWidth * 0.7, y: y,
                                    width: theme.contentWidth * 0.3, height: 12),
                         alignment: .trailing)
    }

    // MARK: - Block dispatch

    private static func draw(_ placed: PlacedBlock,
                             document: ReportDocument,
                             context: PDFDrawingContext) {
        let theme = document.theme
        let palette = theme.palette
        let rect = CGRect(origin: placed.origin, size: placed.size)

        switch placed.block {
        case let .sectionTitle(title, subtitle):
            var y = rect.minY
            let titleHeight = context.measure(title, role: .sectionTitle, width: rect.width)
            context.draw(title, role: .sectionTitle, color: palette.ink,
                         in: CGRect(x: rect.minX, y: y, width: rect.width, height: titleHeight))
            y += titleHeight + 2
            if let subtitle, !subtitle.isEmpty {
                let subtitleHeight = context.measure(subtitle, role: .sectionSubtitle, width: rect.width)
                context.draw(subtitle, role: .sectionSubtitle, color: palette.inkMuted,
                             in: CGRect(x: rect.minX, y: y, width: rect.width, height: subtitleHeight))
                y += subtitleHeight + 3
            }
            context.rule(x: rect.minX, y: y + 3, width: 44, thickness: 2, color: palette.brand)

        case let .subheading(title, anchor):
            // The subsection's own destination, anchored at the heading rather than at the top of
            // whatever page it landed on. Every contents row is drawn as a hyperlink, but only
            // section anchors used to be registered, so all ~20 level-1 rows of a full report — the
            // ledger years, the allocation and holdings subsections, the appendix blocks — were
            // clickable rectangles pointing at a name no page defined, and a viewer resolves those
            // to nothing at all. The PDFKit outline pass builds the sidebar from page indices
            // instead and was never affected.
            if let anchor {
                context.addDestination(anchor, topDownY: rect.minY)
            }
            context.draw(title, role: .subheading, color: palette.ink,
                         in: CGRect(x: rect.minX, y: rect.minY, width: rect.width,
                                    height: context.measure(title, role: .subheading, width: rect.width)))

        case let .paragraph(text):
            context.draw(text, role: .body, color: palette.inkSecondary, in: rect, lineHeightMultiple: 1.35)

        case let .note(text):
            context.draw(text, role: .note, color: palette.inkMuted, in: rect, lineHeightMultiple: 1.3)

        case let .kpis(items):
            drawKPIs(items, in: rect, theme: theme, context: context)

        case let .chart(chart):
            ReportChartRenderer.draw(chart, in: rect, context: context)

        case let .table(table):
            drawTable(table, in: rect, document: document, context: context)

        case let .keyValues(pairs):
            var y = rect.minY
            let lineHeight = context.lineHeight(for: .body)
            for pair in pairs {
                context.drawLine(pair.label, role: .kpiLabel, color: palette.inkMuted,
                                 in: CGRect(x: rect.minX, y: y + 1, width: rect.width * 0.38, height: lineHeight))
                context.drawLine(pair.value, role: .body, color: palette.ink,
                                 in: CGRect(x: rect.minX + rect.width * 0.4, y: y,
                                            width: rect.width * 0.6, height: lineHeight))
                y += lineHeight + 4
            }

        case .spacer:
            break
        }
    }

    // MARK: - KPIs

    private static func drawKPIs(_ items: [ReportKPI],
                                 in rect: CGRect,
                                 theme: ReportTheme,
                                 context: PDFDrawingContext) {
        guard !items.isEmpty else { return }
        let metrics = theme.metrics
        let palette = theme.palette
        let perRow = max(1, metrics.kpisPerRow)
        let spacing = metrics.kpiSpacing
        let cellWidth = (rect.width - CGFloat(perRow - 1) * spacing) / CGFloat(perRow)

        for (index, item) in items.enumerated() {
            let row = index / perRow
            let column = index % perRow
            let cell = CGRect(x: rect.minX + CGFloat(column) * (cellWidth + spacing),
                              y: rect.minY + CGFloat(row) * (metrics.kpiHeight + spacing),
                              width: cellWidth,
                              height: metrics.kpiHeight)

            context.fill(cell, color: palette.zebra)
            // Accent stripe on the leading edge, brand-coloured for the headline figure.
            let stripeColor: ReportColor
            switch item.emphasis {
            case .headline: stripeColor = palette.brand
            case .positive: stripeColor = palette.positive
            case .negative: stripeColor = palette.negative
            case .neutral: stripeColor = palette.hairlineStrong
            }
            context.fill(CGRect(x: cell.minX, y: cell.minY, width: 2.5, height: cell.height), color: stripeColor)

            let inset = cell.insetBy(dx: 10, dy: 8)
            context.drawLine(item.label, role: .kpiLabel, color: palette.inkMuted,
                             in: CGRect(x: inset.minX + 2, y: inset.minY,
                                        width: inset.width - 2, height: 11))

            let valueColor: ReportColor
            switch item.emphasis {
            case .positive: valueColor = palette.positive
            case .negative: valueColor = palette.negative
            case .headline, .neutral: valueColor = palette.ink
            }
            context.drawLine(item.value, role: .kpiValue, color: valueColor,
                             in: CGRect(x: inset.minX + 2, y: inset.minY + 14,
                                        width: inset.width - 2, height: 19),
                             isNumeric: true)

            if let detail = item.detail, !detail.isEmpty {
                context.drawLine(detail, role: .kpiDetail, color: palette.inkMuted,
                                 in: CGRect(x: inset.minX + 2, y: inset.minY + 34,
                                            width: inset.width - 2, height: 11))
            }
        }
    }

    // MARK: - Tables

    /// Logical (leading-origin) column frames. In RTL these are mirrored as a whole by the drawing
    /// primitives, which puts logical column 0 at the visual right — exactly the column order an
    /// Arabic or Hebrew reader expects, with no explicit reversal needed here.
    static func columnFrames(_ columns: [ReportColumn], in rect: CGRect, padding: CGFloat) -> [CGRect] {
        let totalWeight = columns.reduce(0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0 else { return [] }
        var frames: [CGRect] = []
        var x = rect.minX
        for column in columns {
            let width = rect.width * (max(0, column.weight) / totalWeight)
            frames.append(CGRect(x: x + padding / 2, y: rect.minY,
                                 width: max(0, width - padding), height: rect.height))
            x += width
        }
        return frames
    }

    private static func drawTable(_ table: ReportTable,
                                  in rect: CGRect,
                                  document: ReportDocument,
                                  context: PDFDrawingContext) {
        let theme = document.theme
        let metrics = theme.metrics
        let palette = theme.palette
        var y = rect.minY

        if let caption = table.caption, !caption.isEmpty {
            let captionHeight = context.measure(caption, role: .tableCaption, width: rect.width)
            context.draw(caption, role: .tableCaption, color: palette.ink,
                         in: CGRect(x: rect.minX, y: y, width: rect.width, height: captionHeight))
            y += captionHeight + 4
        }

        let headerRect = CGRect(x: rect.minX, y: y, width: rect.width, height: metrics.tableHeaderHeight)
        let headerFrames = columnFrames(table.columns, in: headerRect, padding: metrics.tableCellPadding * 2)
        for (index, column) in table.columns.enumerated() where index < headerFrames.count {
            var frame = headerFrames[index]
            frame.origin.y += 4
            frame.size.height = 12
            context.drawLine(column.title, role: .tableHeader, color: palette.inkMuted,
                             in: frame, alignment: column.alignment, isNumeric: false)
        }
        y += metrics.tableHeaderHeight
        context.rule(x: rect.minX, y: y - 1, width: rect.width, thickness: 0.7, color: palette.hairlineStrong)

        // Only treat an empty table as "no data" when there is genuinely nothing to show. A chunk
        // can legitimately arrive with no rows but a totals footer; returning early here used to
        // drop that footer and print "No entries recorded." in its place.
        if table.rows.isEmpty {
            if table.footer == nil {
                context.drawLine(document.chrome.noEntries, role: .tableCell, color: palette.inkMuted,
                                 in: CGRect(x: rect.minX, y: y + 4, width: rect.width, height: 12))
                return
            }
        }

        for (index, row) in table.rows.enumerated() {
            let height = metrics.tableRowHeight
                + (row.secondary.map { $0.isEmpty ? 0 : metrics.tableSecondaryHeight } ?? 0)
            let rowRect = CGRect(x: rect.minX, y: y, width: rect.width, height: height)

            if table.showsZebraStripes, index % 2 == 1 {
                context.fill(rowRect, color: palette.zebra)
            }
            if row.style == .subtotal {
                context.rule(x: rect.minX, y: y, width: rect.width, thickness: 0.5, color: palette.hairlineStrong)
            }

            let cellRect = CGRect(x: rect.minX, y: y + 3, width: rect.width, height: metrics.tableRowHeight - 4)
            let frames = columnFrames(table.columns, in: cellRect, padding: metrics.tableCellPadding * 2)
            let role: ReportFontRole = row.style == .subtotal ? .tableFooter : .tableCell
            let color: ReportColor
            switch row.style {
            case .normal: color = palette.ink
            case .subtotal: color = palette.ink
            case .excluded: color = palette.inkMuted
            }

            for (index, column) in table.columns.enumerated()
            where index < frames.count && index < row.cells.count {
                context.drawLine(row.cells[index], role: role, color: color,
                                 in: frames[index], alignment: column.alignment,
                                 isNumeric: column.isNumeric)
            }

            if let secondary = row.secondary, !secondary.isEmpty {
                context.drawLine(secondary, role: .tableSecondary, color: palette.inkMuted,
                                 in: CGRect(x: rect.minX + metrics.tableCellPadding,
                                            y: y + metrics.tableRowHeight - 2,
                                            width: rect.width - metrics.tableCellPadding * 2,
                                            height: metrics.tableSecondaryHeight))
            }

            y += height
        }

        if let footer = table.footer {
            context.rule(x: rect.minX, y: y, width: rect.width, thickness: 0.7, color: palette.hairlineStrong)
            let footerRect = CGRect(x: rect.minX, y: y + 4, width: rect.width, height: metrics.tableRowHeight - 4)
            let frames = columnFrames(table.columns, in: footerRect, padding: metrics.tableCellPadding * 2)
            for (index, column) in table.columns.enumerated()
            where index < frames.count && index < footer.cells.count {
                context.drawLine(footer.cells[index], role: .tableFooter, color: palette.ink,
                                 in: frames[index], alignment: column.alignment,
                                 isNumeric: column.isNumeric)
            }
        }
    }

    // MARK: - Outline pass

    private static func attachOutline(to url: URL,
                                      entries: [ReportContentsEntry],
                                      coverAndContentsPageCount: Int,
                                      metadata: ReportMetadata) throws {
        guard let pdf = PDFDocument(url: url) else { throw ReportRenderError.couldNotAttachOutline }

        pdf.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: metadata.documentTitle,
            PDFDocumentAttribute.authorAttribute: metadata.brandName,
            PDFDocumentAttribute.subjectAttribute: metadata.scopeLine,
            PDFDocumentAttribute.creatorAttribute: "\(metadata.brandName) \(metadata.appVersion)",
        ]

        if !entries.isEmpty {
            let root = PDFOutline()
            var currentTop: PDFOutline?

            func destination(forPrintedPage printed: Int) -> PDFDestination? {
                // Printed body page 1 is the physical page after the cover and any contents pages.
                let index = coverAndContentsPageCount + printed - 1
                guard index >= 0, index < pdf.pageCount, let page = pdf.page(at: index) else { return nil }
                return PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))
            }

            for entry in entries {
                let node = PDFOutline()
                node.label = entry.title
                node.destination = destination(forPrintedPage: entry.pageNumber)

                if entry.level == 0 {
                    root.insertChild(node, at: root.numberOfChildren)
                    currentTop = node
                } else if let parent = currentTop {
                    parent.insertChild(node, at: parent.numberOfChildren)
                } else {
                    root.insertChild(node, at: root.numberOfChildren)
                }
            }
            pdf.outlineRoot = root
        }

        guard pdf.write(to: url) else { throw ReportRenderError.couldNotAttachOutline }
    }
}
