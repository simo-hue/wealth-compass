import CoreGraphics
import Foundation

// MARK: - Document model
//
// The report is described as a flat list of *blocks* per section, deliberately free of any
// app type (no `FinancialData`, no `AppSettings`, no SwiftUI). Everything here is strings,
// numbers and enums that were already formatted by `ReportDocumentBuilder` on the main actor.
//
// That split is the reason this whole layer is verifiable without Xcode: `ReportDocument` →
// `PDFReportRenderer` compiles and runs against Foundation + CoreGraphics + CoreText alone, so
// `scripts/render_sample_report.swift` can exercise the real renderer with synthetic fixtures.
// Keep it that way — resist the urge to reach for `Decimal`/`Currency`/`AnalyticsEngine` here.

/// One printable unit of content. Blocks are measured and flowed onto pages by
/// `ReportPaginator`; only `.table` can be split across a page boundary.
enum ReportBlock: Sendable {
    /// Opens a section. Always forces a page break before it (see `ReportPaginator`).
    case sectionTitle(String, subtitle: String?)
    /// A labelled group within a section. Becomes a second-level contents entry when
    /// `anchor` is non-nil.
    case subheading(String, anchor: String?)
    case paragraph(String)
    /// Smaller, muted body text — footnotes, reconciliation caveats, disclaimers.
    case note(String)
    /// A row of headline figures laid out in a responsive grid.
    case kpis([ReportKPI])
    case chart(ReportChart)
    case table(ReportTable)
    /// Two-column label/value list used by the appendix.
    case keyValues([ReportKeyValue])
    case spacer(CGFloat)
}

struct ReportKPI: Sendable {
    var label: String
    var value: String
    /// Optional second line under the value (e.g. "+12.4%" or "of total assets").
    var detail: String?
    var emphasis: Emphasis

    enum Emphasis: Sendable {
        case neutral
        case positive
        case negative
        /// Rendered in the brand accent — reserved for the single headline figure of a section.
        case headline
    }

    init(label: String, value: String, detail: String? = nil, emphasis: Emphasis = .neutral) {
        self.label = label
        self.value = value
        self.detail = detail
        self.emphasis = emphasis
    }
}

struct ReportKeyValue: Sendable {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

// MARK: - Tables

enum ReportAlignment: Sendable {
    case leading
    case center
    case trailing
}

struct ReportColumn: Sendable {
    var title: String
    /// Relative share of the content width. Weights are normalised, so they need not sum to 1.
    var weight: CGFloat
    var alignment: ReportAlignment
    /// Numeric columns get tabular figures so digits align down the column (see `ReportFonts`).
    var isNumeric: Bool

    init(_ title: String, weight: CGFloat, alignment: ReportAlignment = .leading, isNumeric: Bool = false) {
        self.title = title
        self.weight = weight
        self.alignment = alignment
        self.isNumeric = isNumeric
    }
}

struct ReportRow: Sendable {
    var cells: [String]
    /// Optional smaller muted line beneath the primary cells. This is how a 14-field
    /// `Investment` fits a portrait page without dropping data (see the two-line row decision):
    /// money on the primary line, `ISIN · Type · Sector · Geography · Fees` underneath.
    var secondary: String?
    var style: Style

    enum Style: Sendable {
        case normal
        /// Bold — month subtotals and section totals inside a table body.
        case subtotal
        /// Muted + italic marker — used for future-dated transactions, which
        /// `AnalyticsEngine.calculateTotals()` deliberately excludes from the cash balance.
        case excluded
    }

    init(_ cells: [String], secondary: String? = nil, style: Style = .normal) {
        self.cells = cells
        self.secondary = secondary
        self.style = style
    }
}

struct ReportTable: Sendable {
    var columns: [ReportColumn]
    var rows: [ReportRow]
    /// Pinned totals row drawn with a rule above it; repeated only on the final chunk when the
    /// table splits across pages.
    var footer: ReportRow?
    /// Caption printed above the table, and used as the "(continued)" label on later pages.
    var caption: String?
    var showsZebraStripes: Bool

    init(columns: [ReportColumn],
         rows: [ReportRow],
         footer: ReportRow? = nil,
         caption: String? = nil,
         showsZebraStripes: Bool = true) {
        self.columns = columns
        self.rows = rows
        self.footer = footer
        self.caption = caption
        self.showsZebraStripes = showsZebraStripes
    }
}

// MARK: - Charts
//
// Charts are hand-drawn CoreGraphics (see `ReportChartRenderer`) rather than Swift Charts,
// specifically so they compile and render inside the no-Xcode harness. Each spec carries a
// `@Sendable` axis formatter because tick values are derived from the plot geometry at draw
// time, so they cannot be pre-formatted by the builder like every other string here.

struct ReportSlice: Sendable {
    var label: String
    var value: Double
    /// Pre-formatted amount shown in the legend (e.g. "€12,345.67").
    var formattedValue: String
}

struct ReportBarGroup: Sendable {
    var label: String
    /// One value per series, in the same order as `ReportChart.groupedBars(seriesLabels:)`.
    var values: [Double]
}

struct ReportLinePoint: Sendable {
    var date: Date
    var value: Double
}

enum ReportChart: Sendable {
    /// Allocation ring with a side legend. `centerValue` is printed inside the hole.
    case donut(slices: [ReportSlice], centerLabel: String?, centerValue: String?)
    case groupedBars(groups: [ReportBarGroup],
                     seriesLabels: [String],
                     axisFormatter: @Sendable (Double) -> String)
    case area(points: [ReportLinePoint],
              axisFormatter: @Sendable (Double) -> String,
              dateFormatter: @Sendable (Date) -> String)

    /// Drawn height in points. Donuts need room for the legend; the plotted charts want a
    /// readable aspect ratio without eating a whole page.
    var height: CGFloat {
        switch self {
        case .donut: return 190
        case .groupedBars: return 200
        case .area: return 190
        }
    }
}

// MARK: - Sections & document

/// A titled run of blocks that always starts on a fresh page and contributes one first-level
/// contents entry.
struct ReportSectionContent: Sendable {
    /// Stable name used for the PDF link destination and the PDFKit outline entry.
    var anchor: String
    var title: String
    var subtitle: String?
    var blocks: [ReportBlock]
    /// True for sections the report always emits regardless of what the user picked (the
    /// appendix). They are excluded from the "is this document big enough to warrant a contents
    /// page" test — otherwise the appendix alone would push every two-page single-section export
    /// over the threshold and give it a one-entry index.
    var isStructural: Bool

    init(anchor: String,
         title: String,
         subtitle: String? = nil,
         blocks: [ReportBlock],
         isStructural: Bool = false) {
        self.anchor = anchor
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.isStructural = isStructural
    }
}

/// Everything the cover page and running header/footer need. Kept separate from the sections so
/// the renderer never has to reach back into app state for a title or a date.
struct ReportMetadata: Sendable {
    var brandName: String
    var documentTitle: String
    /// e.g. "Investments · Crypto" or the localised "Full report".
    var scopeLine: String
    /// e.g. "1 Jan 2024 – 27 Jul 2026", or nil when the report covers all time.
    var periodLine: String?
    var baseCurrencyLine: String
    var generatedLine: String
    /// Printed in the footer of every body page next to the page number.
    var footerNote: String
    var appVersion: String
    /// PNG bytes for the brand mark shown on the cover band. Nil renders the wordmark alone,
    /// which is also what the harness does.
    var brandMarkPNG: Data?
}

/// Localised chrome strings the renderer itself has to print. Everything else arrives
/// pre-formatted inside blocks.
struct ReportChrome: Sendable {
    var contentsTitle: String
    var pageFormat: String       // "Page %1$@ of %2$@"
    var continuedSuffix: String  // "(continued)"
    var noEntries: String        // shown in place of an empty table
    /// Legend overflow row on a donut with more categories than fit — "+ %lld more".
    var legendOverflowFormat: String
    /// The report's locale. The chart layer formats donut legend percentages itself (they depend
    /// on plot geometry, so the builder cannot pre-format them); without this it would use the
    /// system locale and print "24.1%" beside an amount rendered as "€1.234,00".
    var locale: Locale

    // Cover-page fact labels.
    var periodLabel: String
    var baseCurrencyLabel: String
    var generatedLabel: String
    /// Printed at the foot of the cover. States the provenance of the figures, which a report
    /// built entirely from self-reported data needs to say plainly.
    var coverDisclaimer: String

    init(contentsTitle: String = "Contents",
         pageFormat: String = "Page %1$@ of %2$@",
         continuedSuffix: String = "(continued)",
         noEntries: String = "No entries recorded.",
         legendOverflowFormat: String = "+ %lld more",
         locale: Locale = .current,
         periodLabel: String = "Period",
         baseCurrencyLabel: String = "Base currency",
         generatedLabel: String = "Generated",
         coverDisclaimer: String = "Prepared from data entered by the account holder. Market values reflect the most recent prices retrieved by the app and are not independently verified. This document is a personal record, not financial advice or a statement from a regulated institution.") {
        self.contentsTitle = contentsTitle
        self.pageFormat = pageFormat
        self.continuedSuffix = continuedSuffix
        self.noEntries = noEntries
        self.legendOverflowFormat = legendOverflowFormat
        self.locale = locale
        self.periodLabel = periodLabel
        self.baseCurrencyLabel = baseCurrencyLabel
        self.generatedLabel = generatedLabel
        self.coverDisclaimer = coverDisclaimer
    }
}

struct ReportDocument: Sendable {
    var metadata: ReportMetadata
    var chrome: ReportChrome
    var sections: [ReportSectionContent]
    var theme: ReportTheme

    init(metadata: ReportMetadata,
         chrome: ReportChrome = ReportChrome(),
         sections: [ReportSectionContent],
         theme: ReportTheme = ReportTheme()) {
        self.metadata = metadata
        self.chrome = chrome
        self.sections = sections
        self.theme = theme
    }
}
