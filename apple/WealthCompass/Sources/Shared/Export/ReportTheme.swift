import CoreGraphics
import CoreText
import Foundation

// MARK: - Paper

/// Physical page size. Chosen from the **system region** rather than the in-app language
/// override: an Italian user who runs the app in English still wants A4.
enum ReportPaper: String, Sendable, CaseIterable {
    case a4
    case usLetter

    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 595.276, height: 841.890)   // 210 × 297 mm
        case .usLetter: return CGSize(width: 612, height: 792)     // 8.5 × 11 in
        }
    }

    /// Regions that use US Letter as the default office paper size.
    private static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR"]

    static func forRegion(_ locale: Locale = .current) -> ReportPaper {
        guard let region = locale.region?.identifier else { return .a4 }
        return letterRegions.contains(region) ? .usLetter : .a4
    }
}

// MARK: - Direction

/// Page-level writing direction. CoreText already orders glyphs correctly within a line, so
/// this exists purely for *layout* mirroring: column order, cell alignment, header/footer sides
/// and chart legend placement.
enum ReportLayoutDirection: String, Sendable {
    case leftToRight
    case rightToLeft

    var isRTL: Bool { self == .rightToLeft }

    static func resolve(locale: Locale) -> ReportLayoutDirection {
        locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    /// Mirrors a leading/trailing alignment. Centre is unaffected.
    func resolved(_ alignment: ReportAlignment) -> ReportAlignment {
        guard isRTL else { return alignment }
        switch alignment {
        case .leading: return .trailing
        case .trailing: return .leading
        case .center: return .center
        }
    }
}

// MARK: - Colour

/// sRGB colour carried as plain components so the theme stays `Sendable` and free of CoreGraphics
/// object lifetimes. `cgColor` is built on demand at draw time.
struct ReportColor: Sendable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func opacity(_ value: CGFloat) -> ReportColor {
        ReportColor(red, green, blue, alpha: alpha * value)
    }
}

/// The printed palette. Deliberately **not** the app's `WCColor` set: the app is dark-only, and
/// its emerald (`#1FDB99`) is unreadable as text on white. The bright brand colour survives only
/// on the dark cover band, where it belongs.
struct ReportPalette: Sendable {
    var ink = ReportColor(0.086, 0.094, 0.114)
    var inkSecondary = ReportColor(0.290, 0.314, 0.341)
    var inkMuted = ReportColor(0.463, 0.490, 0.522)

    var hairline = ReportColor(0.863, 0.878, 0.898)
    var hairlineStrong = ReportColor(0.706, 0.733, 0.765)
    var zebra = ReportColor(0.961, 0.969, 0.976)
    var surface = ReportColor(1, 1, 1)

    /// Cover band. Dark navy so the (navy, rounded-square) app icon sits on a field of its own
    /// rather than floating on white as a sticker.
    var coverBackground = ReportColor(0.039, 0.102, 0.184)
    var coverInk = ReportColor(1, 1, 1)
    var coverInkMuted = ReportColor(1, 1, 1, alpha: 0.72)

    /// Print-safe emerald used for rules, headings and positive figures on white.
    var brand = ReportColor(0.055, 0.620, 0.420)
    /// The app's own `WCColor.primary` — only legible against the cover band.
    var brandBright = ReportColor(0.122, 0.859, 0.600)
    var accent = ReportColor(0.055, 0.541, 0.576)

    var positive = ReportColor(0.055, 0.620, 0.420)
    var negative = ReportColor(0.753, 0.224, 0.169)

    /// Categorical series colours. Ordered so that adjacent entries also differ in *lightness*,
    /// which keeps them separable when the report is printed in greyscale.
    var chart: [ReportColor] = [
        ReportColor(0.055, 0.620, 0.420),  // emerald
        ReportColor(0.122, 0.361, 0.545),  // deep blue
        ReportColor(0.878, 0.541, 0.118),  // amber
        ReportColor(0.478, 0.310, 0.749),  // violet
        ReportColor(0.078, 0.647, 0.690),  // teal
        ReportColor(0.753, 0.224, 0.169),  // red
        ReportColor(0.361, 0.478, 0.180),  // olive
        ReportColor(0.690, 0.341, 0.553),  // magenta
    ]

    func chartColor(_ index: Int) -> ReportColor {
        guard !chart.isEmpty else { return ink }
        return chart[index % chart.count]
    }

    init() {}
}

// MARK: - Metrics

struct ReportMetrics: Sendable {
    var marginLeading: CGFloat = 46
    var marginTrailing: CGFloat = 46
    var marginTop: CGFloat = 50
    var marginBottom: CGFloat = 48

    /// Running head band (brand mark + section name + rule) on every body page.
    var headerHeight: CGFloat = 30
    /// Footer band (page number + footer note).
    var footerHeight: CGFloat = 26

    var blockSpacing: CGFloat = 13
    var paragraphLeading: CGFloat = 1.32

    var tableHeaderHeight: CGFloat = 18
    var tableRowHeight: CGFloat = 16
    var tableSecondaryHeight: CGFloat = 11
    var tableCellPadding: CGFloat = 5
    /// A table chunk smaller than this is pushed to the next page rather than leaving an orphan.
    var tableMinimumOrphanRows: Int = 3

    var kpiHeight: CGFloat = 56
    var kpiSpacing: CGFloat = 10
    var kpisPerRow: Int = 3

    var coverBandHeight: CGFloat = 300
    var brandMarkSize: CGFloat = 76

    init() {}
}

// MARK: - Typography

enum ReportFontWeight: Sendable {
    case regular
    case medium
    case semibold
    case bold

    /// CoreText weight trait, in the -1…1 range CoreText expects.
    var traitValue: CGFloat {
        switch self {
        case .regular: return 0
        case .medium: return 0.23
        case .semibold: return 0.3
        case .bold: return 0.4
        }
    }
}

/// Every typographic role in the document, so sizes and weights are tuned in exactly one place.
enum ReportFontRole: Sendable {
    case coverTitle
    case coverSubtitle
    case coverMeta
    case coverWordmark

    case sectionTitle
    case sectionSubtitle
    case subheading

    case body
    case note

    case kpiLabel
    case kpiValue
    case kpiDetail

    case tableHeader
    case tableCell
    case tableSecondary
    case tableFooter
    case tableCaption

    case contentsTitle
    case contentsEntry
    case contentsSubEntry

    case runningHead
    case pageNumber

    case chartTitle
    case chartAxis
    case chartLegend
    case chartCenterValue
    case chartCenterLabel

    var size: CGFloat {
        switch self {
        case .coverTitle: return 31
        case .coverSubtitle: return 14
        case .coverMeta: return 9.5
        case .coverWordmark: return 15

        case .sectionTitle: return 19
        case .sectionSubtitle: return 10
        case .subheading: return 11.5

        case .body: return 9.5
        case .note: return 8

        case .kpiLabel: return 7.5
        case .kpiValue: return 15
        case .kpiDetail: return 8

        case .tableHeader: return 7.5
        case .tableCell: return 8.8
        case .tableSecondary: return 7.3
        case .tableFooter: return 8.8
        case .tableCaption: return 9

        case .contentsTitle: return 22
        case .contentsEntry: return 10.5
        case .contentsSubEntry: return 9

        case .runningHead: return 7.5
        case .pageNumber: return 7.5

        case .chartTitle: return 9.5
        case .chartAxis: return 7
        case .chartLegend: return 7.5
        case .chartCenterValue: return 13
        case .chartCenterLabel: return 7
        }
    }

    var weight: ReportFontWeight {
        switch self {
        case .coverTitle, .coverWordmark, .sectionTitle, .contentsTitle, .kpiValue,
             .chartCenterValue, .tableFooter:
            return .bold
        case .subheading, .tableHeader, .contentsEntry, .chartTitle:
            return .semibold
        case .coverSubtitle, .kpiLabel, .runningHead:
            return .medium
        default:
            return .regular
        }
    }

    /// Roles that carry figures get monospaced digits so columns line up down the page.
    var usesTabularFigures: Bool {
        switch self {
        case .kpiValue, .tableCell, .tableFooter, .tableSecondary, .chartAxis,
             .chartCenterValue, .pageNumber, .contentsEntry, .contentsSubEntry, .chartLegend:
            return true
        default:
            return false
        }
    }

    /// Uppercase, letter-spaced roles. Small caps-ish treatment for labels.
    var tracking: CGFloat {
        switch self {
        case .kpiLabel, .tableHeader, .runningHead, .coverWordmark: return 0.8
        default: return 0
        }
    }

    var isUppercased: Bool {
        switch self {
        case .kpiLabel, .tableHeader, .runningHead, .coverWordmark: return true
        default: return false
        }
    }
}

/// Builds CTFonts for a role. Cached per (size, weight, tabular) because a 100-page report asks
/// for the same handful of fonts tens of thousands of times, and `CTFontDescriptor` round-trips
/// are not free.
enum ReportFonts {
    private struct Key: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var tabular: Bool
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: CTFont] = [:]

    static func font(_ role: ReportFontRole) -> CTFont {
        font(size: role.size, weight: role.weight, tabularFigures: role.usesTabularFigures)
    }

    static func font(size: CGFloat, weight: ReportFontWeight, tabularFigures: Bool) -> CTFont {
        let key = Key(size: size, weight: weight.traitValue, tabular: tabularFigures)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = build(size: size, weight: weight, tabularFigures: tabularFigures)
        lock.lock()
        cache[key] = built
        lock.unlock()
        return built
    }

    private static func build(size: CGFloat, weight: ReportFontWeight, tabularFigures: Bool) -> CTFont {
        // Start from the UI system font (SF), which is what the app uses on screen. CoreGraphics
        // embeds a subset into the PDF — verified — including the automatic Arabic / CJK / Thai
        // fallback faces, so the document renders correctly off-platform.
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)

        var attributes: [CFString: Any] = [:]
        if weight != .regular {
            attributes[kCTFontTraitsAttribute] = [kCTFontWeightTrait: weight.traitValue]
        }
        if tabularFigures {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
            ]]
        }
        guard !attributes.isEmpty else { return base }

        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

// MARK: - Theme

struct ReportTheme: Sendable {
    var paper: ReportPaper
    var direction: ReportLayoutDirection
    var palette: ReportPalette
    var metrics: ReportMetrics

    init(paper: ReportPaper = .a4,
         direction: ReportLayoutDirection = .leftToRight,
         palette: ReportPalette = ReportPalette(),
         metrics: ReportMetrics = ReportMetrics()) {
        self.paper = paper
        self.direction = direction
        self.palette = palette
        self.metrics = metrics
    }

    var pageSize: CGSize { paper.size }

    /// Horizontal span available to content, between the margins.
    var contentWidth: CGFloat {
        paper.size.width - metrics.marginLeading - metrics.marginTrailing
    }

    /// Vertical span available to blocks on a body page, between the running head and footer.
    var contentHeight: CGFloat {
        paper.size.height
            - metrics.marginTop - metrics.marginBottom
            - metrics.headerHeight - metrics.footerHeight
    }

    /// Distance from the top of the page to the first block on a body page.
    var contentTop: CGFloat { metrics.marginTop + metrics.headerHeight }

    /// The content rect in *top-down* coordinates (y grows downward), which is how the paginator
    /// and every layout helper reason. `PDFDrawingContext` flips to PDF space at draw time.
    var contentRect: CGRect {
        CGRect(x: metrics.marginLeading, y: contentTop, width: contentWidth, height: contentHeight)
    }
}
