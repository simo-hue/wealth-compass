import CoreGraphics
import Foundation

/// Pure geometry for the Money Flow diagram.
///
/// Deliberately Foundation + CoreGraphics only, with no SwiftUI and no reference to the design
/// system. Two reasons: the same resolved geometry drives both the on-screen SwiftUI card and the
/// CoreGraphics renderer in the PDF report, and a dependency-free engine can be compiled and
/// executed headlessly, so the arithmetic below is verified rather than eyeballed.
///
/// Coordinates are **y-down** (SwiftUI / UIKit convention). The PDF renderer flips into this space
/// before calling in.
///
/// ## The invariant
///
/// Every ribbon has a constant thickness equal to `value * scale`, and one single scale is used
/// for the whole diagram. Because `CashFlowSankey` guarantees `inflows.sum == hub.value ==
/// outflows.sum`, the inflow ribbons stack to exactly the hub's height on its left edge and the
/// outflow ribbons stack to exactly the same height on its right edge. Nothing is fudged to make
/// the ends meet.
enum SankeyLayout {

    // MARK: - Configuration

    struct Config: Equatable {
        /// Width of the coloured bar at each end of the diagram.
        var nodeWidth: CGFloat = 11
        /// Vertical space between adjacent bars in a column.
        var nodeSpacing: CGFloat = 12
        /// Floor for the *drawn* bar so a sub-percent category still has something to point at.
        /// Purely a hit-target concession: the ribbon keeps its true scaled thickness, so the
        /// diagram never overstates a magnitude (see `SankeyNodeFrame.flowRect`).
        var minimumNodeHeight: CGFloat = 5
        /// Height reserved for one label — two lines, name over amount.
        var labelHeight: CGFloat = 32
        /// Minimum vertical clearance between two labels.
        var labelSpacing: CGFloat = 4
        /// Gap between a bar and its label.
        var labelInset: CGFloat = 8
        var preferredLabelWidth: CGFloat = 132
        var minimumLabelWidth: CGFloat = 64
        /// Clear ribbon run kept between a label and the hub, so the flows never collapse into a
        /// sliver squeezed between two blocks of text.
        var minimumRibbonRun: CGFloat = 36
        /// Where the Bezier control points sit along the horizontal span, as a fraction of it.
        /// 0.5 gives the symmetric S-curve of the reference.
        var curvature: CGFloat = 0.5

        static let standard = Config()

        /// The Dashboard card is shorter and narrower, so it trades label width for ribbon run.
        static let compact = Config(
            nodeWidth: 9,
            nodeSpacing: 10,
            labelHeight: 30,
            preferredLabelWidth: 116,
            minimumRibbonRun: 28
        )

        /// Print. Report type is smaller than the screen card's, so the label slots shrink to
        /// match — `labelHeight` has to track the actual rendered text or the de-collision pass
        /// reserves the wrong amount of room.
        static let report = Config(
            nodeWidth: 7,
            nodeSpacing: 7,
            minimumNodeHeight: 2.5,
            labelHeight: 21,
            labelSpacing: 3,
            labelInset: 6,
            preferredLabelWidth: 108,
            minimumLabelWidth: 48,
            minimumRibbonRun: 22
        )
    }

    /// Which shape to resolve.
    enum Mode: Equatable {
        /// Three columns: income → hub → expenses. The full-width card.
        case full
        /// Hub pinned to the left edge fanning right to the outflows only; `inflows` are ignored.
        /// One label column instead of two, which roughly doubles the ribbon run — that is what
        /// makes the diagram survive the Dashboard's narrow breakpoint.
        case fanOut
    }

    // MARK: - Output

    struct NodeFrame: Identifiable, Equatable {
        let id: String
        /// The bar as drawn, floored to `Config.minimumNodeHeight` and centred on `flowRect`.
        /// Use for the rounded rect and for hit-testing.
        let rect: CGRect
        /// The true, scale-accurate band. Ribbons attach here.
        let flowRect: CGRect
        let role: CashFlowSankeyRole
        let value: Double
        /// True when `rect` had to be inflated past `flowRect` to stay clickable.
        let isFloored: Bool
    }

    /// A ribbon, as four corners plus the horizontal control-point offset. The consumer builds:
    /// move → curve to target top → line down → curve back to source bottom → close. Storing
    /// points rather than a built path lets SwiftUI interpolate them for the period-change
    /// animation and lets CoreGraphics build a `CGPath` from the identical numbers.
    struct Ribbon: Identifiable, Equatable {
        let id: String
        let sourceID: String
        let targetID: String
        let value: Double
        let sourceTop: CGPoint
        let sourceBottom: CGPoint
        let targetTop: CGPoint
        let targetBottom: CGPoint
        /// Horizontal distance from each end to its Bezier control point.
        let controlOffset: CGFloat

        var thickness: CGFloat { sourceBottom.y - sourceTop.y }
    }

    struct Label: Identifiable, Equatable {
        enum Alignment: Equatable {
            /// Text runs rightwards from `rect.minX` — the left column and the hub.
            case leading
            /// Text is flush to `rect.maxX` — the right column, mirroring the reference.
            case trailing
        }

        let id: String
        let rect: CGRect
        let alignment: Alignment
        /// True when de-collision moved this label off its node's centre, so the view can draw a
        /// connector or drop the label if it prefers.
        let isDisplaced: Bool
    }

    struct Resolved: Equatable {
        var nodes: [NodeFrame] = []
        var ribbons: [Ribbon] = []
        var labels: [Label] = []
        /// Points per unit of currency. Zero for an empty diagram.
        var scale: CGFloat = 0
        /// True when the rect was too short to give every label its own slot, so labels are
        /// evenly distributed and may sit off their node's centre.
        var isCrowded: Bool = false

        func node(id: String) -> NodeFrame? { nodes.first { $0.id == id } }
        func label(id: String) -> Label? { labels.first { $0.id == id } }
    }

    // MARK: - Entry point

    /// Resolves the diagram into `rect`. Returns an empty result for a degenerate input rather
    /// than producing non-finite geometry — a NaN here would propagate into CoreGraphics.
    static func resolve(
        _ sankey: CashFlowSankey,
        in rect: CGRect,
        mode: Mode = .full,
        config: Config = .standard
    ) -> Resolved {
        guard !sankey.isEmpty,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0
        else { return Resolved() }

        let inflows = mode == .fanOut ? [] : sankey.inflows
        let outflows = sankey.outflows
        let total = CGFloat(sankey.total)
        guard total > 0 else { return Resolved() }

        // One scale for the whole diagram, sized so the *most crowded* column fits. Using a single
        // scale is what keeps every ribbon a constant thickness end to end; sizing it to the worst
        // column is what keeps that column inside the rect.
        let columns = [inflows.count, outflows.count].filter { $0 > 0 }
        let usableHeights = columns.map { rect.height - CGFloat($0 - 1) * config.nodeSpacing }
        guard let usableHeight = usableHeights.min(), usableHeight > 0 else { return Resolved() }
        let scale = usableHeight / total
        let flowHeight = total * scale

        // Horizontal bands.
        let hubRect: CGRect
        let leftNodeX: CGFloat
        let rightNodeX = rect.maxX - config.nodeWidth
        switch mode {
        case .full:
            leftNodeX = rect.minX
            hubRect = CGRect(
                x: rect.midX - config.nodeWidth / 2,
                y: rect.midY - flowHeight / 2,
                width: config.nodeWidth,
                height: flowHeight
            )
        case .fanOut:
            leftNodeX = rect.minX
            hubRect = CGRect(
                x: rect.minX,
                y: rect.midY - flowHeight / 2,
                width: config.nodeWidth,
                height: flowHeight
            )
        }

        let labelWidth = resolveLabelWidth(rect: rect, hubRect: hubRect, mode: mode, config: config)

        var resolved = Resolved(scale: scale)

        // MARK: Columns

        let inflowFrames = stack(
            inflows,
            x: leftNodeX,
            width: config.nodeWidth,
            in: rect,
            scale: scale,
            config: config
        )
        let outflowFrames = stack(
            outflows,
            x: rightNodeX,
            width: config.nodeWidth,
            in: rect,
            scale: scale,
            config: config
        )
        let hubFrame = NodeFrame(
            id: sankey.hub.id,
            rect: hubRect,
            flowRect: hubRect,
            role: .hub,
            value: sankey.hub.value,
            isFloored: false
        )
        resolved.nodes = inflowFrames + [hubFrame] + outflowFrames

        // MARK: Ribbons
        //
        // Each side stacks against the hub in column order with no gaps, so the stack height is
        // exactly `flowHeight` — the hub's height. That is the invariant made visible.

        var inCursor = hubRect.minY
        for frame in inflowFrames {
            let thickness = frame.flowRect.height
            resolved.ribbons.append(
                ribbon(
                    id: "\(frame.id)->\(sankey.hub.id)",
                    sourceID: frame.id,
                    targetID: sankey.hub.id,
                    value: frame.value,
                    fromX: frame.flowRect.maxX,
                    fromY: frame.flowRect.minY,
                    toX: hubRect.minX,
                    toY: inCursor,
                    thickness: thickness,
                    curvature: config.curvature
                )
            )
            inCursor += thickness
        }

        var outCursor = hubRect.minY
        for frame in outflowFrames {
            let thickness = frame.flowRect.height
            resolved.ribbons.append(
                ribbon(
                    id: "\(sankey.hub.id)->\(frame.id)",
                    sourceID: sankey.hub.id,
                    targetID: frame.id,
                    value: frame.value,
                    fromX: hubRect.maxX,
                    fromY: outCursor,
                    toX: frame.flowRect.minX,
                    toY: frame.flowRect.minY,
                    thickness: thickness,
                    curvature: config.curvature
                )
            )
            outCursor += thickness
        }

        // MARK: Labels

        let bounds = rect.minY...rect.maxY
        let leftLabels = placeLabels(
            for: inflowFrames,
            x: leftNodeX + config.nodeWidth + config.labelInset,
            width: labelWidth,
            alignment: .leading,
            bounds: bounds,
            config: config
        )
        let rightLabels = placeLabels(
            for: outflowFrames,
            x: rightNodeX - config.labelInset - labelWidth,
            width: labelWidth,
            alignment: .trailing,
            bounds: bounds,
            config: config
        )
        // The hub's label sits to its right, vertically centred on the bar — as in the reference.
        // In `.fanOut` the hub is the only thing on the left, so its label goes there too.
        //
        // Its width is clamped to the gap before the outflow label column: these are the only two
        // label columns that can meet horizontally, and on a narrow card an unclamped hub label
        // would run straight into them. Below `minimumLabelWidth` it is dropped rather than
        // squeezed — at the app's 520pt minimum pane the gap falls to ~45pt, where "Cash Flow" and
        // the amount would both truncate. The card's own header already states the period total.
        let rightLabelX = rightNodeX - config.labelInset - labelWidth
        let hubLabelX = hubRect.maxX + config.labelInset
        let hubLabelWidth = min(labelWidth, rightLabelX - hubLabelX - config.labelInset)
        var hubLabels: [Label] = []
        if hubLabelWidth >= config.minimumLabelWidth, rect.height >= config.labelHeight {
            let hubLabelY = min(
                max(hubRect.midY - config.labelHeight / 2, rect.minY),
                rect.maxY - config.labelHeight
            )
            hubLabels = [
                Label(
                    id: sankey.hub.id,
                    rect: CGRect(x: hubLabelX, y: hubLabelY, width: hubLabelWidth, height: config.labelHeight),
                    alignment: .leading,
                    isDisplaced: false
                )
            ]
        }
        resolved.labels = leftLabels.labels + hubLabels + rightLabels.labels
        resolved.isCrowded = leftLabels.isCrowded || rightLabels.isCrowded

        return resolved
    }

    /// The rect height at which every label in the busiest column still gets its own slot.
    /// Callers use it as the card's `minHeight` so `Resolved.isCrowded` stays false in practice.
    static func minimumHeight(
        inflowCount: Int,
        outflowCount: Int,
        mode: Mode = .full,
        config: Config = .standard
    ) -> CGFloat {
        let counts = mode == .fanOut ? [outflowCount] : [inflowCount, outflowCount]
        let busiest = counts.max() ?? 0
        guard busiest > 0 else { return 0 }
        return CGFloat(busiest) * config.labelHeight + CGFloat(busiest - 1) * config.labelSpacing
    }

    // MARK: - Internals

    /// Stacks one column top-to-bottom, centred vertically in `rect`.
    private static func stack(
        _ nodes: [CashFlowSankeyNode],
        x: CGFloat,
        width: CGFloat,
        in rect: CGRect,
        scale: CGFloat,
        config: Config
    ) -> [NodeFrame] {
        guard !nodes.isEmpty else { return [] }
        let flowHeights = nodes.map { max(0, CGFloat($0.value) * scale) }
        let totalHeight = flowHeights.reduce(0, +) + CGFloat(nodes.count - 1) * config.nodeSpacing
        var cursor = rect.midY - totalHeight / 2

        return zip(nodes, flowHeights).map { node, height in
            let flowRect = CGRect(x: x, y: cursor, width: width, height: height)
            cursor += height + config.nodeSpacing

            // Inflate the drawn bar around the true band's centre, never shifting it.
            let drawnHeight = max(height, config.minimumNodeHeight)
            let drawnRect = CGRect(
                x: x,
                y: flowRect.midY - drawnHeight / 2,
                width: width,
                height: drawnHeight
            )
            return NodeFrame(
                id: node.id,
                rect: drawnRect,
                flowRect: flowRect,
                role: node.role,
                value: node.value,
                isFloored: drawnHeight > height
            )
        }
    }

    private static func ribbon(
        id: String,
        sourceID: String,
        targetID: String,
        value: Double,
        fromX: CGFloat,
        fromY: CGFloat,
        toX: CGFloat,
        toY: CGFloat,
        thickness: CGFloat,
        curvature: CGFloat
    ) -> Ribbon {
        Ribbon(
            id: id,
            sourceID: sourceID,
            targetID: targetID,
            value: value,
            sourceTop: CGPoint(x: fromX, y: fromY),
            sourceBottom: CGPoint(x: fromX, y: fromY + thickness),
            targetTop: CGPoint(x: toX, y: toY),
            targetBottom: CGPoint(x: toX, y: toY + thickness),
            controlOffset: (toX - fromX) * curvature
        )
    }

    /// Label width is whatever is left after reserving a clear ribbon run on each side, clamped to
    /// the configured band. Falls back to the minimum rather than going negative on a narrow card.
    private static func resolveLabelWidth(
        rect: CGRect,
        hubRect: CGRect,
        mode: Mode,
        config: Config
    ) -> CGFloat {
        // The tighter of the two half-spans decides, so both columns get the same width and the
        // diagram stays symmetric.
        let leftSpan = hubRect.minX - (rect.minX + config.nodeWidth + config.labelInset)
        let rightSpan = (rect.maxX - config.nodeWidth - config.labelInset) - hubRect.maxX
        let span = mode == .fanOut ? rightSpan : min(leftSpan, rightSpan)
        let available = span - config.minimumRibbonRun
        guard available.isFinite else { return config.minimumLabelWidth }
        return max(config.minimumLabelWidth, min(config.preferredLabelWidth, available))
    }

    /// Places one column's labels at their nodes' centres, then resolves any overlap.
    ///
    /// The reference implementation has exactly this defect — at ten categories its labels
    /// physically overlap. Folding the long tail makes collisions rare; this makes them
    /// impossible.
    private static func placeLabels(
        for frames: [NodeFrame],
        x: CGFloat,
        width: CGFloat,
        alignment: Label.Alignment,
        bounds: ClosedRange<CGFloat>,
        config: Config
    ) -> (labels: [Label], isCrowded: Bool) {
        guard !frames.isEmpty else { return ([], false) }
        let pitch = config.labelHeight + config.labelSpacing
        let span = bounds.upperBound - bounds.lowerBound
        let required = CGFloat(frames.count) * config.labelHeight
            + CGFloat(frames.count - 1) * config.labelSpacing

        /// Seats an already-fitting run: push down from the top, then lift back inside if the run
        /// overflowed the bottom. Terminates without escaping the top because the caller only
        /// invokes it when the run fits.
        func seat(_ subset: [NodeFrame]) -> [Label] {
            let desired = subset.map { $0.rect.midY - config.labelHeight / 2 }
            var tops: [CGFloat] = []
            tops.reserveCapacity(subset.count)
            var cursor = bounds.lowerBound
            for top in desired {
                let placed = max(top, cursor)
                tops.append(placed)
                cursor = placed + pitch
            }
            if let last = tops.last, last + config.labelHeight > bounds.upperBound {
                tops[tops.count - 1] = bounds.upperBound - config.labelHeight
                for index in stride(from: tops.count - 2, through: 0, by: -1) {
                    tops[index] = min(tops[index], tops[index + 1] - pitch)
                }
            }
            return zip(subset, zip(tops, desired)).map { frame, placement in
                Label(
                    id: frame.id,
                    rect: CGRect(x: x, y: placement.0, width: width, height: config.labelHeight),
                    alignment: alignment,
                    isDisplaced: abs(placement.0 - placement.1) > 0.5
                )
            }
        }

        guard required > span else { return (seat(frames), false) }

        // Not enough room to seat everyone. Spreading all of them evenly would still overlap — it
        // cannot not, once `required > span` — which is the exact defect this pass exists to
        // prevent. So seat as many as genuinely fit, largest first, and leave the rest to the bar
        // and the hover detail row. `isCrowded` tells the view labels were dropped.
        let capacity = max(0, Int((span + config.labelSpacing) / pitch))
        guard capacity > 0 else { return ([], true) }
        let keep = Set(
            frames.enumerated()
                .sorted { lhs, rhs in
                    lhs.element.value == rhs.element.value
                        ? lhs.offset < rhs.offset
                        : lhs.element.value > rhs.element.value
                }
                .prefix(capacity)
                .map(\.offset)
        )
        // Re-filtered in column order, so what survives still reads top-to-bottom.
        return (seat(frames.enumerated().filter { keep.contains($0.offset) }.map(\.element)), true)
    }
}
