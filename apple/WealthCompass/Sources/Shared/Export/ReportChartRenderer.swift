import CoreGraphics
import Foundation

// MARK: - Chart renderer
//
// Charts are plotted by hand with CoreGraphics rather than with Swift Charts, for the same reason
// `ReportDocument` avoids app types: the whole export path then compiles and runs against
// Foundation + CoreGraphics alone, so `scripts/render_sample_report.swift` can exercise the real
// renderer without Xcode. Swift Charts would also force the drawing back onto the main actor and
// through a view host, neither of which a PDF context has.
//
// Everything below is laid out in the logical top-down space `PDFDrawingContext` exposes (y grows
// downward, x is leading-origin and mirrored for RTL). Only wedge, polyline and swatch geometry —
// which has to be handed to CoreGraphics as a `CGPath` — is converted with `pdfPoint`/`pdfRect`.
//
// Every incoming `Double` is treated as hostile. Values reach here through `CurrencyConverter`,
// which already refuses to emit NaN/Inf precisely because a non-finite number silently voids the
// geometry it feeds (see its comments); the same discipline is repeated here because the report
// also derives ratios, fractions and axis steps, each of which can manufacture a fresh NaN from
// perfectly finite inputs.

enum ReportChartRenderer {

    // MARK: - Entry points

    /// Draws a chart into a logical top-down rect. Never draws outside the rect.
    static func draw(_ chart: ReportChart, in rect: CGRect, context: PDFDrawingContext) {
        guard isFinite(rect), rect.width > 4, rect.height > 4 else { return }

        // The paginator sizes blocks from `height(for:)`, but a chart it had to squeeze — or one
        // whose legend overflowed — must still not bleed into the next block. Clipping is cheaper
        // than propagating a "remaining space" parameter through every helper.
        context.cg.saveGState()
        defer { context.cg.restoreGState() }
        context.cg.clip(to: context.pdfRect(rect))

        switch chart {
        case let .donut(slices, centerLabel, centerValue):
            drawDonut(slices: slices,
                      centerLabel: centerLabel,
                      centerValue: centerValue,
                      in: rect,
                      context: context)

        case let .groupedBars(groups, seriesLabels, axisFormatter):
            drawGroupedBars(groups: groups,
                            seriesLabels: seriesLabels,
                            axisFormatter: axisFormatter,
                            in: rect,
                            context: context)

        case let .area(points, axisFormatter, dateFormatter):
            drawArea(points: points,
                     axisFormatter: axisFormatter,
                     dateFormatter: dateFormatter,
                     in: rect,
                     context: context)

        case let .sankey(model, amountFormatter):
            drawSankey(model: model, amountFormatter: amountFormatter, in: rect, context: context)
        }
    }

    /// Height the chart needs. Usually `chart.height`, but a donut with more categories than the
    /// default box holds grows instead of silently collapsing them into "+ n more" — the legend is
    /// the informative half of an allocation ring, so it is worth the extra page.
    static func height(for chart: ReportChart, width: CGFloat, context: PDFDrawingContext) -> CGFloat {
        switch chart {
        case let .donut(slices, _, _):
            guard width > 0 else { return chart.height }
            let plotted = slices.filter { $0.value.isFinite && $0.value > 0 }
            guard plotted.count > 1 else { return chart.height }
            let rows = min(plotted.count, Layout.maxLegendRows)
            let needed = CGFloat(rows) * legendRowHeight(context) + Layout.legendVerticalPadding * 2
            return min(max(chart.height, needed), Layout.maxDonutHeight)

        case let .sankey(model, _):
            // Grow to whatever the busiest column needs to seat every label. Below that height the
            // layout starts dropping the smallest labels — acceptable on screen, where hovering
            // recovers them, but on paper a dropped label is simply gone.
            let needed = SankeyLayout.minimumHeight(
                inflowCount: model.inflows.count,
                outflowCount: model.outflows.count,
                config: .report
            )
            return min(max(chart.height, needed + Layout.legendVerticalPadding * 2), Layout.maxDonutHeight)

        case .groupedBars, .area:
            return chart.height
        }
    }

    // MARK: - Metrics

    private enum Layout {
        static let swatchSize: CGFloat = 6
        static let swatchCorner: CGFloat = 1.5
        static let swatchGap: CGFloat = 6

        /// Split between the ring and its legend. The ring reads at a glance; the legend carries
        /// the figures, so it gets the larger share.
        static let ringWidthFraction: CGFloat = 0.45
        static let ringLegendGap: CGFloat = 14
        static let innerRadiusFraction: CGFloat = 0.62
        static let maxOuterRadius: CGFloat = 100
        static let maxLegendRows = 20
        static let maxDonutHeight: CGFloat = 380
        static let legendVerticalPadding: CGFloat = 3
        static let legendEntryGap: CGFloat = 12
        static let minimumLegendLabelWidth: CGFloat = 34

        static let axisGap: CGFloat = 6
        static let axisWidthFraction: CGFloat = 0.28
        static let axisLabelGap: CGFloat = 3
        /// Target tick *intervals*, so a nice-rounded axis lands on 4-6 labels.
        static let tickIntervals = 4

        /// Slack at each end of a bar cluster so neighbouring clusters stay visually distinct.
        static let clusterInsetFraction: CGFloat = 0.14
        static let barWidthFraction: CGFloat = 0.84
        static let maxBarWidth: CGFloat = 26
        /// A non-zero value must leave a mark even when it rounds to nothing at this scale.
        static let minimumBarHeight: CGFloat = 0.6

        static let areaLineWidth: CGFloat = 1.4
        static let areaFillOpacity: CGFloat = 0.12
        static let areaMarkerRadius: CGFloat = 2.2
        static let maxDateLabels = 6
    }

    // MARK: - Numerical safety

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard value.isFinite else { return lower }
        guard upper > lower else { return lower }
        return min(max(value, lower), upper)
    }

    // MARK: - Axis scaling

    private struct AxisScale {
        var lower: Double
        var upper: Double
        var step: Double
        var ticks: [Double]

        var span: Double { upper - lower }
    }

    /// Rounds a raw axis step up to the nearest 1 / 2 / 2.5 / 5 / 10 × 10ⁿ, which is what makes
    /// tick labels read as round money rather than as arbitrary thirds of the data range.
    private static func niceStep(_ raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        let magnitude = pow(10, log10(raw).rounded(.down))
        guard magnitude.isFinite, magnitude > 0 else { return 1 }

        let fraction = raw / magnitude
        let nice: Double
        if fraction <= 1 {
            nice = 1
        } else if fraction <= 2 {
            nice = 2
        } else if fraction <= 2.5 {
            nice = 2.5
        } else if fraction <= 5 {
            nice = 5
        } else {
            nice = 10
        }

        let step = nice * magnitude
        return step.isFinite && step > 0 ? step : 1
    }

    /// - Parameter includeZero: bars are read as lengths from a baseline, so their axis must
    ///   contain zero. A value series is read as a shape, so its axis hugs the data instead.
    private static func makeScale(values: [Double],
                                  includeZero: Bool,
                                  intervals: Int = Layout.tickIntervals) -> AxisScale {
        let usable = values.filter { $0.isFinite }
        var lower = usable.min() ?? 0
        var upper = usable.max() ?? 0

        if includeZero {
            lower = min(lower, 0)
            upper = max(upper, 0)
        }
        if !lower.isFinite || !upper.isFinite {
            lower = 0
            upper = 1
        }
        if upper < lower {
            swap(&lower, &upper)
        }

        // Nothing to plot at all: every value was zero (or there were none). The axis still has to
        // be drawn, but subdividing an empty range would print tick labels — "€0.25", "€0.50" —
        // that assert a range the data does not have. One baseline is the honest answer.
        let isEmptyRange = lower == 0 && upper == 0

        // Enforce a *relative* floor on the span, not just a guard against an exactly-zero one.
        // Without it, a net worth that moved 0.1% over two years was nice-rounded straight onto
        // that band and rendered as a full-height climb — a visual lie, and one that contradicted
        // the app's own dashboards, which apply this same 8% floor via
        // `AnalyticsEngine.chartYDomain`. Kept numerically identical to that formula so the PDF and
        // the on-screen charts cannot drift apart.
        if !includeZero, upper > lower {
            let minimumSpread = max(abs(upper), 1) * 0.08
            if upper - lower < minimumSpread {
                let midpoint = (upper + lower) / 2
                lower = midpoint - minimumSpread / 2
                upper = midpoint + minimumSpread / 2
            }
        }

        if upper - lower <= 0 {
            // A zero-span axis divides by zero the moment a value is normalised. Open the band out
            // so an all-zero or perfectly flat series lands on a legible centred line.
            let padding = max(abs(upper) * 0.1, 1)
            if includeZero {
                if upper > 0 {
                    lower = 0
                } else if lower < 0 {
                    upper = 0
                } else {
                    lower = 0
                    upper = padding
                }
            } else {
                lower -= padding
                upper += padding
            }
        }
        if !(upper - lower).isFinite || upper - lower <= 0 {
            lower = 0
            upper = 1
        }

        let step = niceStep((upper - lower) / Double(max(intervals, 1)))
        var niceLower = (lower / step).rounded(.down) * step
        var niceUpper = (upper / step).rounded(.up) * step
        if !niceLower.isFinite || !niceUpper.isFinite || niceUpper - niceLower <= 0 {
            niceLower = lower
            niceUpper = upper
        }

        var ticks: [Double] = []
        if isEmptyRange {
            ticks = [0]
        } else {
            let count = Int((((niceUpper - niceLower) / step).rounded()).clampedToTickCount)
            if count > 0 {
                for index in 0...count {
                    let tick = niceLower + Double(index) * step
                    if tick.isFinite { ticks.append(tick) }
                }
            }
            if ticks.count < 2 {
                ticks = [niceLower, niceUpper]
            }
        }

        return AxisScale(lower: niceLower, upper: niceUpper, step: step, ticks: ticks)
    }

    private static func yPosition(for value: Double, scale: AxisScale, in plot: CGRect) -> CGFloat {
        let span = scale.span
        guard span.isFinite, span > 0, value.isFinite else { return plot.midY }
        let ratio = (value - scale.lower) / span
        guard ratio.isFinite else { return plot.midY }
        return plot.maxY - CGFloat(min(max(ratio, 0), 1)) * plot.height
    }

    /// Width reserved for the tick labels, measured from the widest one so the plot never has to
    /// guess. Capped, because one absurdly long figure must not eat the whole plot.
    private static func axisColumnWidth(ticks: [Double],
                                        formatter: (Double) -> String,
                                        limit: CGFloat,
                                        context: PDFDrawingContext) -> CGFloat {
        var widest: CGFloat = 0
        for tick in ticks where tick.isFinite {
            widest = max(widest, context.width(of: formatter(tick), role: .chartAxis))
        }
        guard widest > 0, limit > Layout.axisGap else { return 0 }
        return min(widest + Layout.axisGap, limit)
    }

    /// Gridlines plus their leading-side tick labels. Shared by the bar and area charts so both
    /// read as the same instrument.
    private static func drawGrid(scale: AxisScale,
                                 formatter: (Double) -> String,
                                 plot: CGRect,
                                 axisOrigin: CGFloat,
                                 axisWidth: CGFloat,
                                 bounds: CGRect,
                                 context: PDFDrawingContext) {
        let labelHeight = context.lineHeight(for: .chartAxis)
        let zeroTolerance = abs(scale.step) * 1e-6
        // The axis formatter is compact ("12.3k", 0-1 fraction digits), so a narrow range can round
        // several distinct ticks to the same string. Printing "410k" four times up the axis reads
        // as a rendering fault; keep the gridline and drop the repeated label.
        var lastLabel: String?

        for tick in scale.ticks where tick.isFinite {
            let y = yPosition(for: tick, scale: scale, in: plot)
            guard y.isFinite else { continue }

            // With negative values present the baseline is load-bearing: it is the line the bars
            // hang from, so it is drawn heavier than the surrounding grid.
            let isBaseline = abs(tick) <= zeroTolerance && scale.lower < 0
            context.rule(x: plot.minX,
                         y: y,
                         width: plot.width,
                         thickness: isBaseline ? 0.7 : 0.5,
                         color: isBaseline ? context.palette.hairlineStrong : context.palette.hairline)

            guard axisWidth > Layout.axisGap else { continue }
            let label = formatter(tick)
            guard label != lastLabel else { continue }
            lastLabel = label
            let boxY = clamp(y - labelHeight / 2, bounds.minY, bounds.maxY - labelHeight)
            context.drawLine(label,
                             role: .chartAxis,
                             color: context.palette.inkMuted,
                             in: CGRect(x: axisOrigin,
                                        y: boxY,
                                        width: axisWidth - Layout.axisGap,
                                        height: labelHeight),
                             // Pre-resolved: `isNumeric` pins the alignment as given, and the axis
                             // column has to hug the plot on whichever side the plot mirrored to.
                             alignment: context.direction.resolved(.trailing),
                             isNumeric: true)
        }
    }

    // MARK: - Swatches

    private static func drawSwatch(_ color: ReportColor, at rect: CGRect, context: PDFDrawingContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path = CGPath(roundedRect: context.pdfRect(rect),
                          cornerWidth: Layout.swatchCorner,
                          cornerHeight: Layout.swatchCorner,
                          transform: nil)
        context.fillPath(path, color: color)
    }

    private static func legendRowHeight(_ context: PDFDrawingContext) -> CGFloat {
        max(context.lineHeight(for: .chartLegend) + 4, Layout.swatchSize + 5)
    }

    // MARK: - Donut

    // MARK: - Money Flow (Sankey)

    /// Draws the Money Flow diagram. Geometry comes from `SankeyLayout` — the very engine behind
    /// the on-screen card — so the printed diagram cannot drift from the one in the app.
    private static func drawSankey(
        model: CashFlowSankey,
        amountFormatter: @Sendable (Double) -> String,
        in rect: CGRect,
        context: PDFDrawingContext
    ) {
        let layout = SankeyLayout.resolve(model, in: rect, config: .report)
        guard !layout.nodes.isEmpty else { return }

        let palette = context.theme.palette
        let nodes = Dictionary(model.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func color(for node: CashFlowSankeyNode?) -> ReportColor {
            guard let node else { return palette.brand }
            switch node.role {
            // The print palette's emerald, not the app's — `WCColor.primary` is unreadable on white.
            case .hub, .surplus, .income: return palette.brand
            case .shortfall: return palette.negative
            // `+ 1` skips the palette's emerald, which is `brand` — the colour this chart reserves
            // for income, the hub and the surplus. Without the offset the largest expense category
            // renders the same green as the money you kept. (`chartColor` wraps, so an eighth real
            // category lands back on emerald; it takes exactly eight un-folded expense categories
            // to reach, and a single reused hue in print is a far smaller problem than routinely
            // colouring the biggest expense green.)
            case .expense: return node.colorIndex.map { palette.chartColor($0 + 1) } ?? palette.inkMuted
            }
        }

        // Ribbons first, so the bars and labels sit above them.
        for ribbon in layout.ribbons where ribbon.thickness > 0.15 {
            // The non-hub end carries the meaning. A flat tint rather than a gradient: it prints
            // predictably and survives the greyscale the palette is already ordered for.
            let tinted = ribbon.sourceID == model.hub.id ? nodes[ribbon.targetID] : nodes[ribbon.sourceID]
            context.fillPath(ribbonPath(ribbon, context: context), color: color(for: tinted).opacity(0.22))
        }

        for frame in layout.nodes {
            guard let node = nodes[frame.id] else { continue }
            let radius = min(frame.rect.width / 2, frame.rect.height / 2, 2)
            let path = CGPath(
                roundedRect: context.pdfRect(frame.rect),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.fillPath(path, color: color(for: node))
        }

        // Leader lines, where de-collision moved a label off its bar.
        for label in layout.labels where label.isDisplaced {
            guard let frame = layout.node(id: label.id), frame.role != .hub else { continue }
            let trailing = label.alignment == .trailing
            let path = CGMutablePath()
            path.move(to: context.pdfPoint(
                CGPoint(x: trailing ? label.rect.maxX + 3 : label.rect.minX - 3, y: label.rect.midY)))
            path.addLine(to: context.pdfPoint(
                CGPoint(x: trailing ? frame.rect.minX - 2 : frame.rect.maxX + 2, y: frame.rect.midY)))
            context.strokePath(path, color: palette.hairlineStrong, lineWidth: 0.4)
        }

        // Labels: name over amount, as on screen.
        for label in layout.labels {
            guard let node = nodes[label.id] else { continue }
            let alignment: ReportAlignment = label.alignment == .trailing ? .trailing : .leading
            let lineHeight = context.lineHeight(for: .chartLegend)
            context.drawLine(
                node.title,
                role: .chartLegend,
                color: palette.ink,
                in: CGRect(x: label.rect.minX, y: label.rect.minY, width: label.rect.width, height: lineHeight),
                alignment: alignment
            )
            context.drawLine(
                amountFormatter(node.value),
                role: .chartAxis,
                color: node.role == .shortfall ? palette.negative : palette.inkSecondary,
                in: CGRect(
                    x: label.rect.minX,
                    y: label.rect.minY + lineHeight,
                    width: label.rect.width,
                    height: lineHeight
                ),
                alignment: alignment,
                isNumeric: true
            )
        }
    }

    /// A ribbon's outline in PDF space.
    ///
    /// The control points are computed in *logical* coordinates and converted alongside the
    /// anchors, because `pdfPoint` mirrors x for right-to-left documents — offsetting after the
    /// conversion would bend the curve the wrong way in Arabic and Hebrew.
    private static func ribbonPath(_ ribbon: SankeyLayout.Ribbon, context: PDFDrawingContext) -> CGPath {
        let offset = ribbon.controlOffset
        let path = CGMutablePath()
        path.move(to: context.pdfPoint(ribbon.sourceTop))
        path.addCurve(
            to: context.pdfPoint(ribbon.targetTop),
            control1: context.pdfPoint(CGPoint(x: ribbon.sourceTop.x + offset, y: ribbon.sourceTop.y)),
            control2: context.pdfPoint(CGPoint(x: ribbon.targetTop.x - offset, y: ribbon.targetTop.y))
        )
        path.addLine(to: context.pdfPoint(ribbon.targetBottom))
        path.addCurve(
            to: context.pdfPoint(ribbon.sourceBottom),
            control1: context.pdfPoint(CGPoint(x: ribbon.targetBottom.x - offset, y: ribbon.targetBottom.y)),
            control2: context.pdfPoint(CGPoint(x: ribbon.sourceBottom.x + offset, y: ribbon.sourceBottom.y))
        )
        path.closeSubpath()
        return path
    }

    private static func drawDonut(slices: [ReportSlice],
                                  centerLabel: String?,
                                  centerValue: String?,
                                  in rect: CGRect,
                                  context: PDFDrawingContext) {
        // A ring can only express positive shares. Negative or non-finite entries are dropped
        // rather than clamped, because a zero-width wedge with a legend row would be a lie.
        let plotted = slices.filter { $0.value.isFinite && $0.value > 0 }
        let total = plotted.reduce(0) { $0 + $1.value }
        guard !plotted.isEmpty, total.isFinite, total > 0 else { return }

        let ringWidth = min(rect.width * Layout.ringWidthFraction, rect.width)
        var outerRadius = min(ringWidth, rect.height) / 2 - 2
        outerRadius = min(outerRadius, Layout.maxOuterRadius)

        if outerRadius > 6 {
            let centre = CGPoint(x: rect.minX + ringWidth / 2, y: rect.midY)
            drawRing(plotted, total: total, centre: centre, outerRadius: outerRadius, context: context)
            drawCentreText(label: centerLabel,
                           value: centerValue,
                           centre: centre,
                           innerRadius: outerRadius * Layout.innerRadiusFraction,
                           context: context)
        }

        let legendX = rect.minX + ringWidth + Layout.ringLegendGap
        let legendRect = CGRect(x: legendX,
                                y: rect.minY + Layout.legendVerticalPadding,
                                width: rect.maxX - legendX,
                                height: max(0, rect.height - Layout.legendVerticalPadding * 2))
        drawDonutLegend(plotted, total: total, in: legendRect, context: context)
    }

    private static func drawRing(_ slices: [ReportSlice],
                                 total: Double,
                                 centre: CGPoint,
                                 outerRadius: CGFloat,
                                 context: PDFDrawingContext) {
        let innerRadius = outerRadius * Layout.innerRadiusFraction
        let origin = context.pdfPoint(centre)

        if slices.count == 1 {
            // `addArc` collapses when its start and end angles coincide, so a single slice cannot
            // be expressed as a wedge. Fill the disc and punch the hole out instead.
            let outerBox = CGRect(x: centre.x - outerRadius, y: centre.y - outerRadius,
                                  width: outerRadius * 2, height: outerRadius * 2)
            let innerBox = CGRect(x: centre.x - innerRadius, y: centre.y - innerRadius,
                                  width: innerRadius * 2, height: innerRadius * 2)
            context.fillPath(CGPath(ellipseIn: context.pdfRect(outerBox), transform: nil),
                             color: context.palette.chartColor(0))
            context.fillPath(CGPath(ellipseIn: context.pdfRect(innerBox), transform: nil),
                             color: context.palette.surface)
            return
        }

        // PDF space is y-up, so 12 o'clock is π/2 and clockwise means a decreasing angle.
        var cursor: Double = 0
        for (index, slice) in slices.enumerated() {
            let fraction = slice.value / total
            guard fraction.isFinite, fraction > 0 else { continue }

            let startAngle = Double.pi / 2 - cursor * 2 * Double.pi
            cursor += fraction
            let endAngle = Double.pi / 2 - min(cursor, 1) * 2 * Double.pi
            guard startAngle.isFinite, endAngle.isFinite, startAngle > endAngle else { continue }

            let wedge = CGMutablePath()
            wedge.move(to: point(on: origin, radius: outerRadius, angle: startAngle))
            wedge.addArc(center: origin, radius: outerRadius,
                         startAngle: CGFloat(startAngle), endAngle: CGFloat(endAngle),
                         clockwise: true)
            wedge.addLine(to: point(on: origin, radius: innerRadius, angle: endAngle))
            wedge.addArc(center: origin, radius: innerRadius,
                         startAngle: CGFloat(endAngle), endAngle: CGFloat(startAngle),
                         clockwise: false)
            wedge.closeSubpath()
            context.fillPath(wedge, color: context.palette.chartColor(index))
        }

        // Adjacent categorical colours can be close in value, and print gain closes the rest of
        // the gap. A surface-coloured radial hairline keeps the boundary visible on paper.
        let separators = CGMutablePath()
        cursor = 0
        for slice in slices {
            let fraction = slice.value / total
            guard fraction.isFinite, fraction > 0 else { continue }
            let angle = Double.pi / 2 - cursor * 2 * Double.pi
            cursor += fraction
            guard angle.isFinite else { continue }
            separators.move(to: point(on: origin, radius: innerRadius, angle: angle))
            separators.addLine(to: point(on: origin, radius: outerRadius, angle: angle))
        }
        context.strokePath(separators, color: context.palette.surface, lineWidth: 1)
    }

    private static func point(on centre: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: centre.x + radius * CGFloat(cos(angle)),
                y: centre.y + radius * CGFloat(sin(angle)))
    }

    private static func drawCentreText(label: String?,
                                       value: String?,
                                       centre: CGPoint,
                                       innerRadius: CGFloat,
                                       context: PDFDrawingContext) {
        let label = (label?.isEmpty ?? true) ? nil : label
        let value = (value?.isEmpty ?? true) ? nil : value
        guard label != nil || value != nil else { return }

        // Inscribed chord rather than the diameter, so a long figure does not touch the ring.
        let width = innerRadius * 1.76
        guard width > 12 else { return }

        let labelHeight = label == nil ? 0 : context.lineHeight(for: .chartCenterLabel)
        let valueHeight = value == nil ? 0 : context.lineHeight(for: .chartCenterValue)
        let spacing: CGFloat = (label != nil && value != nil) ? 1 : 0
        var y = centre.y - (labelHeight + spacing + valueHeight) / 2
        let x = centre.x - width / 2

        if let label {
            context.drawLine(label,
                             role: .chartCenterLabel,
                             color: context.palette.inkMuted,
                             in: CGRect(x: x, y: y, width: width, height: labelHeight),
                             alignment: .center)
            y += labelHeight + spacing
        }
        if let value {
            context.drawLine(value,
                             role: .chartCenterValue,
                             color: context.palette.ink,
                             in: CGRect(x: x, y: y, width: width, height: valueHeight),
                             alignment: .center,
                             isNumeric: true)
        }
    }

    private struct LegendRow {
        var color: ReportColor?
        var label: String
        var trailing: String
    }

    private static func drawDonutLegend(_ slices: [ReportSlice],
                                        total: Double,
                                        in rect: CGRect,
                                        context: PDFDrawingContext) {
        let rowHeight = legendRowHeight(context)
        guard rect.width > Layout.minimumLegendLabelWidth, rowHeight > 0, rect.height >= rowHeight else { return }

        let capacity = max(1, Int((rect.height / rowHeight).rounded(.down)))
        let rows = donutLegendRows(slices, total: total, capacity: capacity, context: context)
        guard !rows.isEmpty else { return }

        let swatchColumn = Layout.swatchSize + Layout.swatchGap
        var trailingWidth: CGFloat = 0
        for row in rows {
            trailingWidth = max(trailingWidth, context.width(of: row.trailing, role: .chartLegend))
        }
        trailingWidth = clamp(trailingWidth,
                              0,
                              max(0, rect.width - swatchColumn - Layout.minimumLegendLabelWidth))

        let textHeight = context.lineHeight(for: .chartLegend)
        var y = rect.minY + max(0, (rect.height - CGFloat(rows.count) * rowHeight) / 2)

        for row in rows {
            let textY = y + (rowHeight - textHeight) / 2

            // The overflow row carries no swatch but keeps the swatch indent, so every label in
            // the legend starts on the same vertical.
            if let color = row.color {
                drawSwatch(color,
                           at: CGRect(x: rect.minX,
                                      y: y + (rowHeight - Layout.swatchSize) / 2,
                                      width: Layout.swatchSize,
                                      height: Layout.swatchSize),
                           context: context)
            }
            let labelX = rect.minX + swatchColumn
            let labelWidth = rect.width - swatchColumn - trailingWidth - Layout.swatchGap

            context.drawLine(row.label,
                             role: .chartLegend,
                             color: context.palette.inkSecondary,
                             in: CGRect(x: labelX, y: textY, width: max(0, labelWidth), height: textHeight),
                             alignment: .leading)

            if !row.trailing.isEmpty, trailingWidth > 0 {
                context.drawLine(row.trailing,
                                 role: .chartLegend,
                                 color: context.palette.ink,
                                 in: CGRect(x: rect.maxX - trailingWidth,
                                            y: textY,
                                            width: trailingWidth,
                                            height: textHeight),
                                 alignment: context.direction.resolved(.trailing),
                                 isNumeric: true)
            }
            y += rowHeight
        }
    }

    private static func donutLegendRows(_ slices: [ReportSlice],
                                        total: Double,
                                        capacity: Int,
                                        context: PDFDrawingContext) -> [LegendRow] {
        guard capacity > 0 else { return [] }

        var visible = Array(slices.indices)
        var hidden = 0
        if slices.count > capacity {
            // Keep the largest allocations, but list them back in the ring's own order so a legend
            // entry always sits at the same ordinal as its wedge colour.
            let ranked = slices.indices.sorted { slices[$0].value > slices[$1].value }
            let kept = Set(ranked.prefix(max(0, capacity - 1)))
            visible = slices.indices.filter { kept.contains($0) }
            hidden = slices.count - visible.count
        }

        let percentFormatter = NumberFormatter()
        percentFormatter.locale = context.chrome.locale
        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 0
        percentFormatter.maximumFractionDigits = 1

        var rows: [LegendRow] = visible.map { index in
            let slice = slices[index]
            let fraction = slice.value / total
            let percent = fraction.isFinite
                ? (percentFormatter.string(from: NSNumber(value: fraction)) ?? "")
                : ""

            let trailing: String
            if slice.formattedValue.isEmpty {
                trailing = percent
            } else if percent.isEmpty {
                trailing = slice.formattedValue
            } else {
                trailing = "\(slice.formattedValue) · \(percent)"
            }
            return LegendRow(color: context.palette.chartColor(index),
                             label: slice.label,
                             trailing: trailing)
        }

        if hidden > 0 {
            rows.append(LegendRow(color: nil,
                                  label: String(format: context.chrome.legendOverflowFormat, hidden),
                                  trailing: ""))
        }
        return rows
    }

    // MARK: - Grouped bars

    private static func drawGroupedBars(groups: [ReportBarGroup],
                                        seriesLabels: [String],
                                        axisFormatter: @Sendable (Double) -> String,
                                        in rect: CGRect,
                                        context: PDFDrawingContext) {
        // A non-finite bar is treated as absent (zero length) rather than dropped, so the series
        // keeps its position inside the cluster and its colour keeps matching the legend.
        let clusters: [(label: String, values: [Double])] = groups.map { group in
            (group.label, group.values.map { $0.isFinite ? $0 : 0 })
        }
        let seriesCount = max(seriesLabels.count, clusters.map(\.values.count).max() ?? 0)
        let scale = makeScale(values: clusters.flatMap(\.values), includeZero: true)

        let legendHeight = seriesLabels.contains(where: { !$0.isEmpty })
            ? context.lineHeight(for: .chartLegend) + 6
            : 0
        let axisLabelHeight = context.lineHeight(for: .chartAxis)
        let plotTop = rect.minY + legendHeight
        let plotBottom = rect.maxY - axisLabelHeight - Layout.axisLabelGap
        guard plotBottom - plotTop > 20 else { return }

        if legendHeight > 0 {
            drawSeriesLegend(seriesLabels,
                             in: CGRect(x: rect.minX, y: rect.minY,
                                        width: rect.width, height: legendHeight - 6),
                             context: context)
        }

        let axisWidth = axisColumnWidth(ticks: scale.ticks,
                                        formatter: axisFormatter,
                                        limit: rect.width * Layout.axisWidthFraction,
                                        context: context)
        let plot = CGRect(x: rect.minX + axisWidth,
                          y: plotTop,
                          width: rect.width - axisWidth,
                          height: plotBottom - plotTop)
        guard plot.width > 10 else { return }

        drawGrid(scale: scale,
                 formatter: axisFormatter,
                 plot: plot,
                 axisOrigin: rect.minX,
                 axisWidth: axisWidth,
                 bounds: rect,
                 context: context)

        guard !clusters.isEmpty else { return }

        let clusterWidth = plot.width / CGFloat(clusters.count)
        let baselineY = yPosition(for: 0, scale: scale, in: plot)

        for (clusterIndex, cluster) in clusters.enumerated() {
            let clusterX = plot.minX + CGFloat(clusterIndex) * clusterWidth

            if seriesCount > 0 {
                let inset = clusterWidth * Layout.clusterInsetFraction
                let slot = max(0, clusterWidth - inset * 2) / CGFloat(seriesCount)
                let barWidth = min(max(slot * Layout.barWidthFraction, 0.8), Layout.maxBarWidth)

                for seriesIndex in 0..<seriesCount {
                    let value = seriesIndex < cluster.values.count ? cluster.values[seriesIndex] : 0
                    guard value != 0 else { continue }

                    let valueY = yPosition(for: value, scale: scale, in: plot)
                    var top = min(valueY, baselineY)
                    var height = abs(baselineY - valueY)
                    if height < Layout.minimumBarHeight {
                        height = Layout.minimumBarHeight
                        top = min(top, plot.maxY - Layout.minimumBarHeight)
                    }

                    let barX = clusterX + inset + CGFloat(seriesIndex) * slot + (slot - barWidth) / 2
                    context.fill(CGRect(x: barX, y: top, width: barWidth, height: height),
                                 color: context.palette.chartColor(seriesIndex))
                }
            }

            context.drawLine(cluster.label,
                             role: .chartAxis,
                             color: context.palette.inkMuted,
                             in: CGRect(x: clusterX + 1,
                                        y: plotBottom + Layout.axisLabelGap,
                                        width: max(0, clusterWidth - 2),
                                        height: axisLabelHeight),
                             alignment: .center)
        }
    }

    /// Horizontal series key. Entries that would run past the trailing edge are dropped rather
    /// than wrapped: a second legend line would change the block height the paginator already
    /// reserved.
    private static func drawSeriesLegend(_ labels: [String],
                                         in rect: CGRect,
                                         context: PDFDrawingContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let textHeight = context.lineHeight(for: .chartLegend)
        var x = rect.minX

        for (index, label) in labels.enumerated() where !label.isEmpty {
            let textWidth = context.width(of: label, role: .chartLegend)
            let entryWidth = Layout.swatchSize + 4 + textWidth
            guard x + entryWidth <= rect.maxX else { break }

            drawSwatch(context.palette.chartColor(index),
                       at: CGRect(x: x,
                                  y: rect.minY + (textHeight - Layout.swatchSize) / 2,
                                  width: Layout.swatchSize,
                                  height: Layout.swatchSize),
                       context: context)
            context.drawLine(label,
                             role: .chartLegend,
                             color: context.palette.inkSecondary,
                             in: CGRect(x: x + Layout.swatchSize + 4,
                                        y: rect.minY,
                                        width: textWidth,
                                        height: textHeight),
                             alignment: .leading)
            x += entryWidth + Layout.legendEntryGap
        }
    }

    // MARK: - Area

    private static func drawArea(points: [ReportLinePoint],
                                 axisFormatter: @Sendable (Double) -> String,
                                 dateFormatter: @Sendable (Date) -> String,
                                 in rect: CGRect,
                                 context: PDFDrawingContext) {
        // The builder sorts, but a snapshot series stitched from a backfill plus a live append has
        // been out of order before; sorting here costs nothing and the polyline depends on it.
        let series = points.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard !series.isEmpty else { return }

        let scale = makeScale(values: series.map(\.value), includeZero: false)
        let axisLabelHeight = context.lineHeight(for: .chartAxis)
        let plotTop = rect.minY + 2
        let plotBottom = rect.maxY - axisLabelHeight - Layout.axisLabelGap
        guard plotBottom - plotTop > 20 else { return }

        let axisWidth = axisColumnWidth(ticks: scale.ticks,
                                        formatter: axisFormatter,
                                        limit: rect.width * Layout.axisWidthFraction,
                                        context: context)
        let plot = CGRect(x: rect.minX + axisWidth,
                          y: plotTop,
                          width: rect.width - axisWidth,
                          height: plotBottom - plotTop)
        guard plot.width > 10 else { return }

        drawGrid(scale: scale,
                 formatter: axisFormatter,
                 plot: plot,
                 axisOrigin: rect.minX,
                 axisWidth: axisWidth,
                 bounds: rect,
                 context: context)

        let first = series[0].date.timeIntervalSinceReferenceDate
        let last = series[series.count - 1].date.timeIntervalSinceReferenceDate
        let timeSpan = last - first

        func xPosition(_ index: Int) -> CGFloat {
            guard series.count > 1 else { return plot.midX }
            if timeSpan.isFinite, timeSpan > 0 {
                let ratio = (series[index].date.timeIntervalSinceReferenceDate - first) / timeSpan
                guard ratio.isFinite else { return plot.minX }
                return plot.minX + CGFloat(min(max(ratio, 0), 1)) * plot.width
            }
            // Every sample carries the same timestamp: fall back to even spacing by ordinal.
            return plot.minX + CGFloat(index) / CGFloat(series.count - 1) * plot.width
        }

        var plotted: [CGPoint] = []
        if series.count == 1 {
            // One sample has no slope. A flat rule across the plot reads as "this is the level"
            // and, unlike a lone dot, still supports the area fill beneath it.
            let y = yPosition(for: series[0].value, scale: scale, in: plot)
            plotted = [CGPoint(x: plot.minX, y: y), CGPoint(x: plot.maxX, y: y)]
        } else {
            plotted = series.indices.map { index in
                CGPoint(x: xPosition(index),
                        y: yPosition(for: series[index].value, scale: scale, in: plot))
            }
        }
        plotted = plotted.filter { $0.x.isFinite && $0.y.isFinite }
        guard let start = plotted.first, let end = plotted.last, plotted.count >= 2 else { return }

        let fill = CGMutablePath()
        fill.move(to: context.pdfPoint(CGPoint(x: start.x, y: plot.maxY)))
        for point in plotted {
            fill.addLine(to: context.pdfPoint(point))
        }
        fill.addLine(to: context.pdfPoint(CGPoint(x: end.x, y: plot.maxY)))
        fill.closeSubpath()
        context.fillPath(fill, color: context.palette.brand.opacity(Layout.areaFillOpacity))

        let line = CGMutablePath()
        line.move(to: context.pdfPoint(start))
        for point in plotted.dropFirst() {
            line.addLine(to: context.pdfPoint(point))
        }
        context.strokePath(line, color: context.palette.brand, lineWidth: Layout.areaLineWidth)

        if series.count == 1 {
            let radius = Layout.areaMarkerRadius
            let marker = CGRect(x: plot.midX - radius, y: start.y - radius,
                                width: radius * 2, height: radius * 2)
            context.fillPath(CGPath(ellipseIn: context.pdfRect(marker), transform: nil),
                             color: context.palette.brand)
        }

        drawDateAxis(series,
                     dateFormatter: dateFormatter,
                     plot: plot,
                     labelHeight: axisLabelHeight,
                     xPosition: xPosition,
                     context: context)
    }

    private static func drawDateAxis(_ series: [ReportLinePoint],
                                     dateFormatter: @Sendable (Date) -> String,
                                     plot: CGRect,
                                     labelHeight: CGFloat,
                                     xPosition: (Int) -> CGFloat,
                                     context: PDFDrawingContext) {
        guard !series.isEmpty else { return }

        // Sample count is driven by how many labels actually fit, so a narrow chart thins out
        // rather than overprinting. The endpoints are always kept: they anchor the period.
        let sampleWidth = context.width(of: dateFormatter(series[0].date), role: .chartAxis)
        let slot = max(sampleWidth + 10, 30)
        let fits = max(2, Int((plot.width / slot).rounded(.down)))
        let wanted = min(Layout.maxDateLabels, min(fits, series.count))

        var indices: [Int] = []
        if wanted <= 1 || series.count == 1 {
            indices = [0]
        } else {
            for step in 0..<wanted {
                let raw = Double(step) * Double(series.count - 1) / Double(wanted - 1)
                guard raw.isFinite else { continue }
                let index = min(max(Int(raw.rounded()), 0), series.count - 1)
                if indices.last != index { indices.append(index) }
            }
            if indices.first != 0 { indices.insert(0, at: 0) }
            if indices.last != series.count - 1 { indices.append(series.count - 1) }
        }

        let y = plot.maxY + Layout.axisLabelGap
        // A short series can resolve several samples to the same formatted label (six points inside
        // one month all render as "Jul 26"). Drop the repeats rather than stacking identical labels
        // along the axis; the first and last are kept, so the span still reads correctly.
        var seenLabels = Set<String>()
        for (position, index) in indices.enumerated() {
            let text = dateFormatter(series[index].date)
            guard !text.isEmpty else { continue }
            let isEndpoint = position == 0 || position == indices.count - 1
            if !isEndpoint, !seenLabels.insert(text).inserted { continue }
            seenLabels.insert(text)

            let width = min(context.width(of: text, role: .chartAxis) + 2, plot.width)
            let box: CGRect
            let alignment: ReportAlignment
            if indices.count > 1 && position == 0 {
                box = CGRect(x: plot.minX, y: y, width: width, height: labelHeight)
                alignment = .leading
            } else if indices.count > 1 && position == indices.count - 1 {
                box = CGRect(x: plot.maxX - width, y: y, width: width, height: labelHeight)
                alignment = .trailing
            } else {
                let centre = series.count == 1 ? plot.midX : xPosition(index)
                let x = clamp(centre - width / 2, plot.minX, plot.maxX - width)
                box = CGRect(x: x, y: y, width: width, height: labelHeight)
                alignment = .center
            }
            // Dates are not `isNumeric`: unlike an amount column they carry script-dependent
            // words, so CoreText's own bidi ordering is the correct one.
            context.drawLine(text,
                             role: .chartAxis,
                             color: context.palette.inkMuted,
                             in: box,
                             alignment: alignment)
        }
    }
}

private extension Double {
    /// Guards the tick loop against a step that rounding has driven towards zero, which would
    /// otherwise ask for an unbounded number of gridlines.
    var clampedToTickCount: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 24)
    }
}
