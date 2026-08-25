import CoreGraphics
import CoreText
import Foundation
import ImageIO

// MARK: - Drawing context
//
// Thin, stateless-ish wrapper over a PDF `CGContext` that provides the handful of primitives the
// report needs: measured text, single-line cells with truncation, rules, fills and images.
//
// **Coordinate convention.** PDF space puts the origin at the bottom-left with y growing upward,
// which is miserable to lay out a document in. Every public API here takes *top-down* geometry
// (y measured downward from the top of the page) and flips at the last moment. Anything named
// `topDown` is in document space; anything handed to CoreGraphics has already been flipped.

struct PDFDrawingContext {
    let cg: CGContext
    let theme: ReportTheme
    /// The document's localised chrome. Carried here because it is per-document, like the theme,
    /// and because the chart layer needs one string of its own (the legend overflow row) without
    /// threading a parameter through every drawing entry point.
    let chrome: ReportChrome

    init(cg: CGContext, theme: ReportTheme, chrome: ReportChrome = ReportChrome()) {
        self.cg = cg
        self.theme = theme
        self.chrome = chrome
    }

    var pageSize: CGSize { theme.pageSize }
    var direction: ReportLayoutDirection { theme.direction }
    var palette: ReportPalette { theme.palette }

    // MARK: Coordinate flipping

    func flip(y: CGFloat) -> CGFloat { pageSize.height - y }

    /// Converts a top-down rect into PDF space.
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: pageSize.height - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Mirrors a rect horizontally within the page when the document is right-to-left. Layout code
    /// can therefore compute everything in logical (leading-origin) coordinates and mirror once.
    func mirroredIfRTL(_ rect: CGRect) -> CGRect {
        guard direction.isRTL else { return rect }
        return CGRect(x: pageSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// Logical top-down rect → PDF space, mirroring for RTL. For explicit path construction
    /// (charts), where the automatic flipping inside `fill`/`draw` is not in play.
    func pdfRect(_ topDownRect: CGRect) -> CGRect { flip(mirroredIfRTL(topDownRect)) }

    /// Logical top-down point → PDF space, mirroring for RTL.
    func pdfPoint(_ topDownPoint: CGPoint) -> CGPoint {
        CGPoint(x: direction.isRTL ? pageSize.width - topDownPoint.x : topDownPoint.x,
                y: pageSize.height - topDownPoint.y)
    }

    // MARK: - Text attributes

    static func paragraphStyle(alignment: CTTextAlignment,
                               direction: ReportLayoutDirection,
                               lineHeightMultiple: CGFloat) -> CTParagraphStyle {
        var align = alignment
        var writing: CTWritingDirection = direction.isRTL ? .rightToLeft : .leftToRight
        var multiple = lineHeightMultiple

        return withUnsafePointer(to: &align) { alignPtr in
            withUnsafePointer(to: &writing) { writingPtr in
                withUnsafePointer(to: &multiple) { multiplePtr in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment,
                                                valueSize: MemoryLayout<CTTextAlignment>.size,
                                                value: alignPtr),
                        CTParagraphStyleSetting(spec: .baseWritingDirection,
                                                valueSize: MemoryLayout<CTWritingDirection>.size,
                                                value: writingPtr),
                        CTParagraphStyleSetting(spec: .lineHeightMultiple,
                                                valueSize: MemoryLayout<CGFloat>.size,
                                                value: multiplePtr),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
    }

    private static func ctAlignment(_ alignment: ReportAlignment) -> CTTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    /// Builds the attributed string for a role. Applies the role's uppercase/tracking treatment so
    /// callers never have to remember which labels are letter-spaced.
    ///
    /// `alignment` here is already **visual** — callers resolve logical→visual via
    /// `direction.resolved(_:)` first, because a column of figures deliberately opts out of that
    /// mirroring (see `drawLine`'s `isColumnar`).
    func attributedString(_ text: String,
                          role: ReportFontRole,
                          color: ReportColor,
                          alignment: ReportAlignment = .leading,
                          textDirection: ReportLayoutDirection? = nil,
                          lineHeightMultiple: CGFloat = 1,
                          sizeScale: CGFloat = 1) -> NSAttributedString {
        // Uppercasing is a *presentational* transform; it must not be applied to scripts without
        // case (Arabic, Hebrew, CJK, Thai), where `uppercased()` is a no-op anyway, so this is safe.
        let content = role.isUppercased ? text.uppercased() : text

        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: sizeScale == 1
                ? ReportFonts.font(role)
                : ReportFonts.font(size: role.size * sizeScale,
                                   weight: role.weight,
                                   tabularFigures: role.usesTabularFigures),
            kCTForegroundColorAttributeName as NSAttributedString.Key: color.cgColor,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: Self.paragraphStyle(
                alignment: Self.ctAlignment(alignment),
                direction: textDirection ?? direction,
                lineHeightMultiple: lineHeightMultiple),
        ]
        if role.tracking != 0 {
            // Tracking scales with the type. It is a per-character constant, so leaving it at full
            // size while shrinking the glyphs makes long uppercase headers un-shrinkable: Spanish
            // "GANANCIA / PÉRDIDA" is 18 characters, i.e. 14.4pt of letter-spacing that no font-size
            // reduction could ever recover.
            attributes[kCTKernAttributeName as NSAttributedString.Key] = role.tracking * sizeScale
        }
        return NSAttributedString(string: content, attributes: attributes)
    }

    // MARK: - Measurement

    /// Height a wrapped paragraph will occupy at `width`. Used by the paginator *before* anything
    /// is drawn, which is what makes pagination exact rather than estimated.
    func measure(_ text: String, role: ReportFontRole, width: CGFloat, lineHeightMultiple: CGFloat = 1) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let attributed = attributedString(text, role: role, color: palette.ink,
                                          alignment: direction.resolved(.leading),
                                          lineHeightMultiple: lineHeightMultiple)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            &fitRange)
        return ceil(size.height)
    }

    /// Rendered width of a single line, used for dot leaders, legends and right-aligned figures.
    func width(of text: String, role: ReportFontRole) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(
            attributedString(text, role: role, color: palette.ink))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func lineHeight(for role: ReportFontRole) -> CGFloat {
        let font = ReportFonts.font(role)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    // MARK: - Text drawing

    /// Draws wrapped text into a *logical* top-down rect (leading-origin; mirrored automatically in
    /// RTL). Returns the height actually consumed.
    @discardableResult
    func draw(_ text: String,
              role: ReportFontRole,
              color: ReportColor,
              in topDownRect: CGRect,
              alignment: ReportAlignment = .leading,
              lineHeightMultiple: CGFloat = 1) -> CGFloat {
        guard !text.isEmpty, topDownRect.width > 0, topDownRect.height > 0 else { return 0 }
        let attributed = attributedString(text, role: role, color: color,
                                          alignment: direction.resolved(alignment),
                                          lineHeightMultiple: lineHeightMultiple)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let rect = flip(mirroredIfRTL(topDownRect))
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, cg)
        return measure(text, role: role, width: topDownRect.width, lineHeightMultiple: lineHeightMultiple)
    }

    /// Draws a single line into a *logical* top-down rect, truncating with an ellipsis if it does
    /// not fit. This is the table-cell primitive: cells must never wrap, or row heights stop being
    /// predictable and pagination arithmetic breaks.
    ///
    /// - Parameter isNumeric: the text is a figure. Numerals always render left-to-right, so the
    ///   run is laid out with an LTR base direction whatever the document's script, and the line
    ///   becomes eligible for shrink-to-fit rather than truncation (see `shrunkToFit`).
    /// - Parameter isColumnar: the figure is one cell of a **column** of figures — a table's money
    ///   column, the contents page numbers. Only those opt out of RTL alignment mirroring: pinned
    ///   right in every script, which is what keeps decimal separators lined up down the column
    ///   while the column's *position* still mirrors with the rest of the table. A figure set
    ///   inside a label is not columnar and must sit on the same edge as the words around it —
    ///   pinning those made an Arabic KPI tile read label-right / value-left / detail-right, and
    ///   split the Sankey's two-line label across opposite edges of one rect.
    func drawLine(_ text: String,
                  role: ReportFontRole,
                  color: ReportColor,
                  in topDownRect: CGRect,
                  alignment: ReportAlignment = .leading,
                  isNumeric: Bool = false,
                  isColumnar: Bool = false) {
        guard !text.isEmpty, topDownRect.width > 0 else { return }
        let resolvedAlignment = isColumnar ? alignment : direction.resolved(alignment)
        let attributed = attributedString(text, role: role, color: color,
                                          alignment: resolvedAlignment,
                                          textDirection: isNumeric ? .leftToRight : nil)
        var line = CTLineCreateWithAttributedString(attributed)

        var lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if lineWidth > topDownRect.width {
            // Truncating an amount destroys it: "1.234.56…" cannot be read back, and the money
            // columns are exactly the figures the table exists to state. A column budget is 64.0pt
            // at A4, which fits up to six figures but not "$1,234,567.89" (65.5pt) or German
            // "1.234.567,89 €" (68.1pt); uppercase headers overflow far earlier, with German
            // "GEWINN / VERLUST" at 74.0pt and Spanish "GANANCIA / PÉRDIDA" at 81.5pt — every
            // export, at any portfolio size. A slightly smaller number is still exact, so shrink
            // to fit before falling back to an ellipsis.
            //
            // Only for short, meaning-dense content. Free text (names, descriptions, categories)
            // keeps truncating, because shrinking a long string to fit one line would make the
            // whole table ragged for no gain.
            if let fitted = shrunkToFit(text, role: role, color: color, alignment: resolvedAlignment,
                                        textDirection: isNumeric ? .leftToRight : nil,
                                        isNumeric: isNumeric,
                                        width: topDownRect.width, fullWidth: lineWidth) {
                line = fitted
                lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            } else {
                let ellipsis = CTLineCreateWithAttributedString(
                    attributedString("…", role: role, color: color))
                if let truncated = CTLineCreateTruncatedLine(line, Double(topDownRect.width), .end, ellipsis) {
                    line = truncated
                    lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                }
            }
        }

        let font = ReportFonts.font(role)
        let ascent = CTFontGetAscent(font)
        let rect = mirroredIfRTL(topDownRect)

        let x: CGFloat
        switch resolvedAlignment {
        case .leading: x = rect.minX
        case .center: x = rect.minX + (rect.width - lineWidth) / 2
        case .trailing: x = rect.maxX - lineWidth
        }

        cg.textPosition = CGPoint(x: x, y: flip(y: rect.minY + ascent))
        CTLineDraw(line, cg)
    }

    /// A line of `text` set small enough to fit `width`, or `nil` to fall back to truncation.
    ///
    /// Applies only to roles whose content is short and whose meaning does not survive an ellipsis:
    /// numeric cells and table headers. Each role sets its own floor, below which the text would be
    /// too small to read on paper and truncation is the honest outcome.
    private func shrunkToFit(_ text: String,
                             role: ReportFontRole,
                             color: ReportColor,
                             alignment: ReportAlignment,
                             textDirection: ReportLayoutDirection?,
                             isNumeric: Bool,
                             width: CGFloat,
                             fullWidth: CGFloat) -> CTLine? {
        // `.tableCell` is the role of *every* cell in a row, free text included, so the role alone
        // cannot express "amounts and headings only" — `isNumeric` is what actually distinguishes
        // them. Without this, a slightly-too-long Name rendered a size smaller than the cells
        // beside it, which is exactly the ragged table this was meant to avoid.
        guard role.shrinksToFit, isNumeric || role == .tableHeader else { return nil }
        // Start from the ratio the text actually needs rather than walking down from 0.96: a long
        // free-text cell would otherwise pay for every step before failing anyway. Tracking does
        // not scale perfectly linearly, so this is a starting estimate, not an answer.
        let estimate = fullWidth > 0 ? width / fullWidth : 1
        var scale = min(0.98, estimate)
        while scale >= role.minimumShrinkScale {
            let attributed = attributedString(text, role: role, color: color, alignment: alignment,
                                              textDirection: textDirection, sizeScale: scale)
            let candidate = CTLineCreateWithAttributedString(attributed)
            if CGFloat(CTLineGetTypographicBounds(candidate, nil, nil, nil)) <= width {
                return candidate
            }
            scale -= 0.02
        }
        return nil
    }

    // MARK: - Shapes

    func fill(_ topDownRect: CGRect, color: ReportColor) {
        guard topDownRect.width > 0, topDownRect.height > 0 else { return }
        cg.setFillColor(color.cgColor)
        cg.fill(flip(mirroredIfRTL(topDownRect)))
    }

    /// Horizontal rule spanning `width` at top-down `y`.
    func rule(x: CGFloat, y: CGFloat, width: CGFloat, thickness: CGFloat = 0.5, color: ReportColor) {
        fill(CGRect(x: x, y: y, width: width, height: thickness), color: color)
    }

    func strokePath(_ path: CGPath, color: ReportColor, lineWidth: CGFloat, dash: [CGFloat]? = nil) {
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        if let dash { cg.setLineDash(phase: 0, lengths: dash) }
        cg.addPath(path)
        cg.strokePath()
        cg.restoreGState()
    }

    func fillPath(_ path: CGPath, color: ReportColor) {
        cg.saveGState()
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
        cg.restoreGState()
    }

    // MARK: - Images

    /// Draws PNG data into a top-down rect, preserving aspect ratio and centring within the rect.
    func drawImage(_ data: Data, in topDownRect: CGRect) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }

        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let boxAspect = topDownRect.width / topDownRect.height
        var target = topDownRect
        if imageAspect > boxAspect {
            target.size.height = topDownRect.width / imageAspect
            target.origin.y += (topDownRect.height - target.height) / 2
        } else {
            target.size.width = topDownRect.height * imageAspect
            target.origin.x += (topDownRect.width - target.width) / 2
        }
        cg.draw(image, in: flip(mirroredIfRTL(target)))
    }

    // MARK: - Navigation

    /// Anchors a named destination at top-down `y` on the current page. Paired with `link(to:in:)`
    /// on the contents page and mirrored by the PDFKit outline pass.
    ///
    /// A section anchors at `y = 0` — the top of its own first page — while a subsection anchors at
    /// the heading itself, which is usually mid-page. The x stays 0 in both directions: it is the
    /// viewer's horizontal scroll position, not a text origin, and mirroring it would scroll an
    /// Arabic reader off the right edge of the page.
    func addDestination(_ name: String, topDownY: CGFloat = 0) {
        cg.addDestination(name as CFString, at: CGPoint(x: 0, y: flip(y: topDownY)))
    }

    /// Makes a top-down rect a clickable link to a named destination.
    func link(to name: String, in topDownRect: CGRect) {
        cg.setDestination(name as CFString, for: flip(mirroredIfRTL(topDownRect)))
    }
}
