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
        /// Height reserved for a two-line label — name over amount.
        var labelHeight: CGFloat = 32
        /// Height of the collapsed form, name and amount on one line. Used whenever the pipe a
        /// label names is too thin to contain the two-line block, so the text stays within the flow
        /// it describes instead of spilling across its neighbours.
        var singleLineLabelHeight: CGFloat = 20
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
        /// The band every flow is guaranteed for *pointing* purposes, independent of how thin it is
        /// drawn. Affects `hitTest` only — never the geometry.
        var minimumHitThickness: CGFloat = 12

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
            singleLineLabelHeight: 13,
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

        /// The vertical band this ribbon occupies at a given x, clamped to its two ends so a point
        /// out in the label gutter still resolves against the nearest end rather than nothing.
        ///
        /// Both edges of a ribbon share one x-curve and differ only by a constant y offset, so the
        /// band is `topEdge(x) ... topEdge(x) + thickness`.
        func verticalSpan(atX x: CGFloat) -> ClosedRange<CGFloat>? {
            guard sourceTop.x.isFinite, targetTop.x.isFinite,
                  sourceTop.y.isFinite, targetTop.y.isFinite,
                  thickness.isFinite, controlOffset.isFinite
            else { return nil }

            let height = max(0, thickness)
            let lower = min(sourceTop.x, targetTop.x)
            let upper = max(sourceTop.x, targetTop.x)
            guard upper - lower > 0.0001 else {
                let top = min(sourceTop.y, targetTop.y)
                return top...(top + height)
            }

            let t = curveParameter(forX: min(max(x, lower), upper))
            let inv = 1 - t
            // The control points share their endpoints' y, so the y-curve collapses to a blend of
            // just the two end values.
            let top = sourceTop.y * (inv * inv * inv + 3 * inv * inv * t)
                + targetTop.y * (3 * inv * t * t + t * t * t)
            return top...(top + height)
        }

        /// Inverts the cubic's x-component by bisection. The x-curve is monotonic for any curvature
        /// the layout produces, and 32 halvings resolve well below a pixel.
        private func curveParameter(forX x: CGFloat) -> CGFloat {
            let x0 = sourceTop.x
            let x1 = targetTop.x
            let c1 = x0 + controlOffset
            let c2 = x1 - controlOffset

            func xAt(_ t: CGFloat) -> CGFloat {
                let inv = 1 - t
                return inv * inv * inv * x0
                    + 3 * inv * inv * t * c1
                    + 3 * inv * t * t * c2
                    + t * t * t * x1
            }

            var low: CGFloat = 0
            var high: CGFloat = 1
            let ascending = x1 >= x0
            for _ in 0..<32 {
                let mid = (low + high) / 2
                if (xAt(mid) < x) == ascending { low = mid } else { high = mid }
            }
            return (low + high) / 2
        }
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
        /// True when the label could not be seated inside the pipe it names — the renderer draws a
        /// leader line back to the flow so the name is still attributable.
        let isDisplaced: Bool
        /// 2 for name over amount, 1 for the collapsed single-line form. Chosen from the thickness
        /// of the pipe, never below 1: a label is dropped outright rather than emitted empty.
        let lineCount: Int
    }

    /// One label's sizing decision, taken before placement.
    private struct LabelPlan {
        let frame: NodeFrame
        /// The band the text should sit within — measured on the *ribbon at the label's own x*,
        /// not on the node's band, because by the time a flow reaches the label gutter it has
        /// curved away from the bar it started at.
        let band: ClosedRange<CGFloat>
        let lineCount: Int
        let height: CGFloat
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
        //
        // The surplus is deliberately NOT drawn as a flow. It is the money that never left, so it
        // gets no pipe and no bar in the right column; it becomes the unspent tail of the hub
        // instead. It stays in the model, so `outflows.sum == hub` still holds and the ribbons plus
        // that tail still account for every unit entering the hub.
        let drawnOutflows = outflows.filter { $0.role != .surplus }
        let spentValue = drawnOutflows.reduce(0.0) { $0 + $1.value }

        // Each column is measured against its OWN sum, because with the surplus withdrawn the two
        // sides no longer carry the same total. Taking the tightest result keeps one scale for the
        // whole diagram — so a ribbon's width still means the same thing wherever it is — while
        // guaranteeing the busier column still fits.
        let columnLoads: [(count: Int, sum: CGFloat)] = [
            (inflows.count, total),
            (drawnOutflows.count, CGFloat(spentValue))
        ].filter { $0.count > 0 && $0.sum > 0 }
        let candidates = columnLoads.compactMap { load -> CGFloat? in
            let usable = rect.height - CGFloat(load.count - 1) * config.nodeSpacing
            guard usable > 0 else { return nil }
            return usable / load.sum
        }
        guard let scale = candidates.min(), scale > 0, scale.isFinite else { return Resolved() }

        // The hub is only as tall as what actually attaches to it. In `.full` the inflows tile it
        // edge to edge, so it carries the whole period total. In `.fanOut` there are no inflows at
        // all, and sizing it by `total` there made it `total / spent` times too tall — 15.6x on
        // real data (2.748 € of income against 176,02 € of spending), which painted the hub bar
        // straight over the card's own title.
        let hubValue = inflows.isEmpty ? CGFloat(spentValue) : total
        let flowHeight = hubValue * scale

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
            drawnOutflows,
            x: rightNodeX,
            width: config.nodeWidth,
            in: rect,
            scale: scale,
            config: config
        )

        // The hub is one whole bar: the inflow ribbons tile all of it. The outflow ribbons leave
        // from a band centred on it, so income that was not spent reads as symmetric headroom above
        // and below the flows rather than as a labelled thing in its own right.
        let spentHeight = min(hubRect.height, CGFloat(spentValue) * scale)
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

        var outCursor = hubRect.midY - spentHeight / 2
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
        let leftLabelX = leftNodeX + config.nodeWidth + config.labelInset
        let leftLabels = placeLabels(
            labelPlans(for: inflowFrames, ribbons: resolved.ribbons, hubID: sankey.hub.id,
                       centreX: leftLabelX + labelWidth / 2, config: config),
            x: leftLabelX,
            width: labelWidth,
            alignment: .leading,
            bounds: bounds,
            config: config
        )
        let outLabelX = rightNodeX - config.labelInset - labelWidth
        let rightLabels = placeLabels(
            labelPlans(for: outflowFrames, ribbons: resolved.ribbons, hubID: sankey.hub.id,
                       centreX: outLabelX + labelWidth / 2, config: config),
            x: outLabelX,
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
        var hubCrowded = false
        if hubLabelWidth >= config.minimumLabelWidth, rect.height >= config.labelHeight {
            let placed = placeLabels(
                labelPlans(for: [hubFrame], ribbons: resolved.ribbons, hubID: sankey.hub.id,
                           centreX: hubLabelX + hubLabelWidth / 2, config: config),
                x: hubLabelX,
                width: hubLabelWidth,
                alignment: .leading,
                bounds: bounds,
                config: config
            )
            hubLabels = placed.labels
            hubCrowded = placed.isCrowded
        }
        resolved.labels = leftLabels.labels + hubLabels + rightLabels.labels
        resolved.isCrowded = leftLabels.isCrowded || rightLabels.isCrowded || hubCrowded

        return resolved
    }

    /// Resolves a pointer position to the flow it is pointing at, or nil when outside the diagram.
    ///
    /// This lives in the engine, hit-testing resolved geometry, rather than being a stack of
    /// per-shape `contentShape` modifiers in the view — and that is a correctness decision, not a
    /// tidiness one. Ribbon thickness spans three orders of magnitude in real data: a 0.7% flow is
    /// a ~1pt band no pointer can land on, while a 94% surplus covers most of the plot and swallows
    /// every hover aimed anywhere else. Containment alone therefore leaves most categories
    /// unreachable except via their label.
    ///
    /// So the search runs widest-target-first — labels, then bars, then the ribbon the pointer is
    /// inside, and finally the *nearest* ribbon in the same column. Exactly one flow resolves
    /// anywhere inside the diagram, which makes a hairline flow reachable through all the empty
    /// space around it while the big obvious masses still resolve to themselves.
    static func hitTest(
        _ resolved: Resolved,
        at point: CGPoint,
        hubID: String,
        minimumHitThickness: CGFloat = Config.standard.minimumHitThickness
    ) -> String? {
        guard point.x.isFinite, point.y.isFinite,
              let hub = resolved.node(id: hubID)
        else { return nil }

        // Labels draw on top and are by far the largest targets, so they win outright.
        if let label = resolved.labels.first(where: { $0.rect.contains(point) }) {
            return label.id
        }
        // Then the bars, inflated: a floored bar is 5pt tall and 11pt wide.
        if let bar = resolved.nodes.first(where: { $0.rect.insetBy(dx: -6, dy: -6).contains(point) }) {
            return bar.id
        }

        // Otherwise pick within the column the pointer is in. The hub's own midline splits them, so
        // the inflow and outflow fans are never in competition.
        let inbound = point.x < hub.rect.midX
        let candidates = resolved.ribbons.filter { inbound ? $0.targetID == hubID : $0.sourceID == hubID }
        guard !candidates.isEmpty else { return hub.id }

        var nearest: (id: String, distance: CGFloat, thickness: CGFloat)?
        for ribbon in candidates {
            guard let span = ribbon.verticalSpan(atX: point.x) else { continue }
            let endpointID = ribbon.sourceID == hubID ? ribbon.targetID : ribbon.sourceID
            if span.contains(point.y) {
                return endpointID          // genuinely inside a ribbon: unambiguous
            }
            // For the near-miss test only, inflate the band to a minimum pointable thickness. In
            // real data a category can be 0.7% of the month — a 2.5pt ribbon — while the flow next
            // to it is 88% and 337pt. Nearest-band alone would hand the small one only the few
            // points of gap around it, which is still not a target anyone can hit. This guarantees
            // every flow a usable band without touching what is *drawn*, so the picture stays
            // proportionally honest.
            let thickness = span.upperBound - span.lowerBound
            let pad = max(0, (minimumHitThickness - thickness) / 2)
            let low = span.lowerBound - pad
            let high = span.upperBound + pad
            let distance = point.y < low ? low - point.y : (point.y > high ? point.y - high : 0)
            // Ties go to the thinner flow: where two inflated bands overlap, the big one is
            // reachable across the rest of its span and the small one is not.
            if nearest == nil
                || distance < nearest!.distance
                || (distance == nearest!.distance && thickness < nearest!.thickness) {
                nearest = (endpointID, distance, thickness)
            }
        }
        return nearest?.id ?? hub.id
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
        config: Config,
        topY: CGFloat? = nil
    ) -> [NodeFrame] {
        guard !nodes.isEmpty else { return [] }
        let flowHeights = nodes.map { max(0, CGFloat($0.value) * scale) }
        let totalHeight = flowHeights.reduce(0, +) + CGFloat(nodes.count - 1) * config.nodeSpacing
        // `topY` pins the column instead of centring it. The spending column uses it whenever
        // there is an unspent tail: money leaves the top of the hub, so it should arrive at the top
        // of the column too. Centred, the ribbons dived from the hub's top edge down to a column
        // floating in the middle, and the empty space was split top and bottom instead of reading
        // as the one contiguous "not spent" region it actually is.
        var cursor = topY ?? (rect.midY - totalHeight / 2)

        return zip(nodes, flowHeights).map { node, height in
            let flowRect = CGRect(x: x, y: cursor, width: width, height: height)
            cursor += height + config.nodeSpacing

            // Inflate the drawn bar around the true band's centre. A band flush against the edge of
            // the rect would otherwise send the inflated bar over it — the bottom sliver of an
            // extreme long tail overhung by half the floor — so slide it back inside rather than
            // let it overhang. It still overlaps its own band, which is what makes it pointable.
            let drawnHeight = max(height, config.minimumNodeHeight)
            var drawnY = flowRect.midY - drawnHeight / 2
            drawnY = max(rect.minY, min(drawnY, rect.maxY - drawnHeight))
            let drawnRect = CGRect(x: x, y: drawnY, width: width, height: drawnHeight)
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

    /// Decides how tall each label may be, and where its text ought to sit.
    ///
    /// A label belongs to the pipe it names, so it is sized against that pipe's thickness and
    /// centred on that pipe's band where the label actually is. A thick flow gets the two-line
    /// block; a thin one collapses to a single line; one thinner than a single line cannot contain
    /// text at any size, and is seated as close as possible and marked displaced so a leader line
    /// is drawn instead.
    private static func labelPlans(
        for frames: [NodeFrame],
        ribbons: [Ribbon],
        hubID: String,
        centreX: CGFloat,
        config: Config
    ) -> [LabelPlan] {
        frames.map { frame in
            let band: ClosedRange<CGFloat>
            if frame.role == .hub {
                band = frame.flowRect.minY...frame.flowRect.maxY
            } else if let ribbon = ribbons.first(where: {
                ($0.sourceID == hubID ? $0.targetID : $0.sourceID) == frame.id
            }), let span = ribbon.verticalSpan(atX: centreX) {
                band = span
            } else {
                band = frame.flowRect.minY...frame.flowRect.maxY
            }
            let thickness = band.upperBound - band.lowerBound
            let twoLines = thickness >= config.labelHeight
            return LabelPlan(
                frame: frame,
                band: band,
                lineCount: twoLines ? 2 : 1,
                height: twoLines ? config.labelHeight : config.singleLineLabelHeight
            )
        }
    }

    /// Places one column's labels inside the pipes they name, then resolves any overlap.
    ///
    /// The reference implementation has exactly this defect — at ten categories its labels
    /// physically overlap. Folding the long tail makes collisions rare; this makes them
    /// impossible.
    private static func placeLabels(
        _ plans: [LabelPlan],
        x: CGFloat,
        width: CGFloat,
        alignment: Label.Alignment,
        bounds: ClosedRange<CGFloat>,
        config: Config
    ) -> (labels: [Label], isCrowded: Bool) {
        guard !plans.isEmpty else { return ([], false) }
        let span = bounds.upperBound - bounds.lowerBound

        func required(_ subset: [LabelPlan]) -> CGFloat {
            subset.reduce(0) { $0 + $1.height } + CGFloat(max(0, subset.count - 1)) * config.labelSpacing
        }

        /// Seats an already-fitting run: push down from the top, then lift back inside if the run
        /// overflowed the bottom. Heights vary per label now, so the cursor advances by each
        /// label's own height rather than a shared pitch.
        func seat(_ subset: [LabelPlan]) -> [Label] {
            var tops: [CGFloat] = []
            tops.reserveCapacity(subset.count)
            var cursor = bounds.lowerBound
            for plan in subset {
                let desired = (plan.band.lowerBound + plan.band.upperBound) / 2 - plan.height / 2
                let placed = max(desired, cursor)
                tops.append(placed)
                cursor = placed + plan.height + config.labelSpacing
            }
            if let last = tops.last, last + subset[subset.count - 1].height > bounds.upperBound {
                tops[tops.count - 1] = bounds.upperBound - subset[subset.count - 1].height
                for index in stride(from: tops.count - 2, through: 0, by: -1) {
                    tops[index] = min(tops[index], tops[index + 1] - subset[index].height - config.labelSpacing)
                }
            }
            return zip(subset, tops).map { plan, top in
                // "Inside the pipe" is the whole point of the adaptive sizing, so that — not
                // whether the label moved — is what marks it displaced and earns a leader line.
                let inside = top >= plan.band.lowerBound - 0.5
                    && top + plan.height <= plan.band.upperBound + 0.5
                return Label(
                    id: plan.frame.id,
                    rect: CGRect(x: x, y: top, width: width, height: plan.height),
                    alignment: alignment,
                    isDisplaced: !inside,
                    lineCount: plan.lineCount
                )
            }
        }

        guard required(plans) > span else { return (seat(plans), false) }

        // Not enough room to seat everyone. Spreading all of them evenly would still overlap — it
        // cannot not, once the run exceeds the span — which is the exact defect this pass exists to
        // prevent. So seat as many as genuinely fit, largest first, and leave the rest to the bar
        // and the hover detail row. `isCrowded` tells the view labels were dropped.
        var keep = Set<Int>()
        var running: [LabelPlan] = []
        for (offset, plan) in plans.enumerated().sorted(by: { lhs, rhs in
            lhs.element.frame.value == rhs.element.frame.value
                ? lhs.offset < rhs.offset
                : lhs.element.frame.value > rhs.element.frame.value
        }) {
            let candidate = running + [plan]
            guard required(candidate) <= span else { continue }
            running = candidate
            keep.insert(offset)
        }
        guard !keep.isEmpty else { return ([], true) }
        // Re-filtered in column order, so what survives still reads top-to-bottom.
        return (seat(plans.enumerated().filter { keep.contains($0.offset) }.map(\.element)), true)
    }
}
