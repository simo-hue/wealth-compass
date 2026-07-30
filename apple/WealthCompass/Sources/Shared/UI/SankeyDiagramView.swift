import SwiftUI

/// The Money Flow diagram: income categories → a hub → expense categories, with hover inspection
/// and optional drill-through.
///
/// Geometry comes entirely from `SankeyLayout`, which is pure and unit-tested; this view only
/// styles it. Ribbons are `Shape`s rather than a single `Canvas` pass so that they morph when the
/// period changes and so each flow can carry its own accessibility element.
///
/// Pointer handling is deliberately *not* per-shape. Every drawn layer opts out of hit-testing and
/// a single transparent overlay resolves the pointer through `SankeyLayout.hitTest` — see that
/// method for why stacked `contentShape` modifiers cannot work on a chart whose elements span
/// three orders of magnitude in thickness.
struct SankeyDiagramView: View {
    let sankey: CashFlowSankey
    let settings: AppSettings
    var mode: SankeyLayout.Mode = .full
    var config: SankeyLayout.Config = .standard
    /// Called when a node backed by real transactions is clicked. Nil disables drill-through.
    var onSelect: ((CashFlowSankeyNode) -> Void)?

    /// Id of the flow the pointer resolved to, from the single overlay hit-test.
    @State private var hovered: String?
    /// Drives `diagramHeight`. Measured rather than taken from the inner `GeometryReader`, because
    /// the height has to be known to *propose* a size to that reader in the first place.
    @State private var measuredWidth: CGFloat = 0

    private var nodesByID: [String: CashFlowSankeyNode] {
        Dictionary(sankey.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The height at which every label in the busiest column still gets its own slot. Below it the
    /// layout starts dropping the smallest labels, so callers give the card at least this much.
    var minimumDiagramHeight: CGFloat {
        SankeyLayout.minimumHeight(
            inflowCount: sankey.inflows.count,
            outflowCount: sankey.outflows.count,
            mode: mode,
            config: config
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Privacy is checked *before* emptiness on purpose: whether a period is empty is itself
            // information, and callers guard their own empty states on `!isPrivacyMode` expecting
            // this branch to win.
            if settings.isPrivacyMode {
                // Full conceal, matching the cash-flow trend chart. Redacting only the amounts
                // would be theatre here: a ribbon's width *is* the proportion, so the shape alone
                // still tells a bystander where the money goes.
                EmptyState(title: "Cash-flow chart concealed", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if sankey.isEmpty {
                EmptyState(title: "No cash flow in this period", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                diagram
                detailRow
            }
        }
    }

    private var diagram: some View {
        GeometryReader { proxy in
            let layout = SankeyLayout.resolve(
                sankey,
                in: CGRect(origin: .zero, size: proxy.size),
                mode: mode,
                config: config
            )
            ZStack(alignment: .topLeading) {
                ribbons(layout)
                leaderLines(layout)
                bars(layout)
                labels(layout)
            }
            // Exactly one hit-testing layer for the whole chart. Every drawn element opts out and
            // the overlay below resolves the pointer geometrically against the resolved layout —
            // see `SankeyLayout.hitTest` for why per-shape `contentShape` cannot work here.
            .allowsHitTesting(false)
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            updateHover(SankeyLayout.hitTest(layout, at: point, hubID: sankey.hub.id))
                        case .ended:
                            updateHover(nil)
                        }
                    }
                    // The pointer already resolved a flow on the way in, so a click needs no
                    // second hit-test — it acts on whatever is currently lit.
                    .onTapGesture {
                        if let id = hovered, let node = nodesByID[id] { select(node) }
                    }
                    .accessibilityHidden(true)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: sankey)
        }
        .frame(height: diagramHeight)
        // A geometry fault must never be able to paint over the card's header again: a mis-scaled
        // hub once drew 15x the card height and covered the title. The layout is bounded by
        // construction and asserted to be, so this only ever costs a clip that never fires.
        .clipped()
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SankeyWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(SankeyWidthKey.self) { width in
            guard width.isFinite, abs(width - measuredWidth) > 0.5 else { return }
            measuredWidth = width
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Money Flow"))
    }

    /// A Sankey reads as *flow* at roughly 3:1. Left to fill a wide window at a fixed minimum the
    /// card became a 6:1 letterbox in which the ribbons flatten into horizontal bars and the curve —
    /// the entire point of the chart — disappears. So height tracks width instead of standing still,
    /// which also hands the long tail's labels their own slots back rather than leaving them
    /// shunted onto leader lines.
    ///
    /// The label requirement still wins outright: `minimumHeight` is where labels merely stop being
    /// *dropped*, and laying out at exactly that leaves most of them displaced, so it carries a
    /// third again as headroom.
    private var diagramHeight: CGFloat {
        let aspect = min(520, max(280, measuredWidth * 0.30))
        return max(aspect, minimumDiagramHeight * 1.35)
    }

    // MARK: - Layers

    private func ribbons(_ layout: SankeyLayout.Resolved) -> some View {
        let nodes = nodesByID
        return ForEach(layout.ribbons) { ribbon in
            let shape = RibbonShape(ribbon: ribbon)
            let endpoint = nodes[ribbon.sourceID == sankey.hub.id ? ribbon.targetID : ribbon.sourceID]
            let remainder = endpoint.map(isRemainder) ?? false
            ZStack {
                shape.fill(
                    LinearGradient(
                        // The category's own colour is held across most of the ribbon and only
                        // blends into the hub's green near the middle. A plain end-to-end gradient
                        // dragged every inflow towards the hub's green, which undid the whole point
                        // of grading the income side — five sources came out as one mass.
                        stops: gradientStops(for: ribbon, nodes: nodes, remainder: remainder),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // Outlined rather than filled. It keeps its true proportional width — the diagram
                // never lies about magnitude — but on a high-savings month the surplus is
                // legitimately 94% of the chart, and at equal visual weight it turned the whole
                // card into one green mass with the actual spending buried inside it.
                if remainder {
                    shape.stroke(color(for: endpoint).opacity(0.8), lineWidth: 1)
                }
            }
            // The dim lives on a view modifier, not in the gradient's stops: SwiftUI does not
            // interpolate a `ShapeStyle` change, so folding it into the fill would make the
            // ribbons pop while the bars and labels cross-fade around them.
            .opacity(isLit(ribbon) ? 1 : 0.24)
            // The node's own label already announces the flow, with its share and its action.
            // Making ribbons elements too would read every flow twice.
            .accessibilityHidden(true)
        }
    }

    /// Drawn only where de-collision pushed a label off its bar, so the reader can still tell which
    /// sliver a name belongs to.
    private func leaderLines(_ layout: SankeyLayout.Resolved) -> some View {
        ForEach(layout.labels.filter(\.isDisplaced)) { label in
            if let frame = layout.node(id: label.id), frame.role != .hub {
                Path { path in
                    let trailing = label.alignment == .trailing
                    path.move(to: CGPoint(x: trailing ? label.rect.maxX + 4 : label.rect.minX - 4, y: label.rect.midY))
                    path.addLine(to: CGPoint(x: trailing ? frame.rect.minX - 3 : frame.rect.maxX + 3, y: frame.rect.midY))
                }
                .stroke(Color.white.opacity(isLit(label.id) ? 0.34 : 0.14), lineWidth: 0.75)
                .accessibilityHidden(true)
            }
        }
    }

    /// `.position` must stay the OUTERMOST modifier on everything here.
    ///
    /// It reports back the parent's full proposed size, so any `contentShape` / gesture / hit-test
    /// modifier placed after it covers the entire diagram rather than the element — and since the
    /// label layer draws last, one label would swallow every hover and click in the chart.
    private func bars(_ layout: SankeyLayout.Resolved) -> some View {
        let nodes = nodesByID
        return ForEach(layout.nodes) { frame in
            if let node = nodes[frame.id] {
                barBody(node, frame)
                    .position(x: frame.rect.midX, y: frame.rect.midY)
            }
        }
    }

    @ViewBuilder
    private func barBody(_ node: CashFlowSankeyNode, _ frame: SankeyLayout.NodeFrame) -> some View {
        let corner = RoundedRectangle(cornerRadius: min(3, frame.rect.width / 2), style: .continuous)
        Group {
            if isRemainder(node) {
                corner.fill(color(for: node).opacity(0.28))
                    .overlay(corner.stroke(color(for: node).opacity(0.85), lineWidth: 1))
            } else {
                corner.fill(color(for: node))
            }
        }
        .opacity(isLit(frame.id) ? 1 : 0.32)
        .frame(width: frame.rect.width, height: frame.rect.height)
        // The label carries the accessibility element for this node, so the bar stays silent
        // rather than announcing everything twice.
        .accessibilityHidden(true)
    }

    private func labels(_ layout: SankeyLayout.Resolved) -> some View {
        let nodes = nodesByID
        return ForEach(layout.labels) { label in
            if let node = nodes[label.id] {
                labelBody(node, label)
                    .position(x: label.rect.midX, y: label.rect.midY)
            }
        }
    }

    @ViewBuilder
    private func labelBody(_ node: CashFlowSankeyNode, _ label: SankeyLayout.Label) -> some View {
        // The label is the big, reliable target — a 5pt bar is not something to ask a pointer to
        // find, and it is the only target Switch Control can reach.
        let base = labelContent(node, trailing: label.alignment == .trailing, lineCount: label.lineCount)
            .frame(
                width: label.rect.width,
                height: label.rect.height,
                alignment: label.alignment == .trailing ? .trailing : .leading
            )
            .opacity(isLit(label.id) ? 1 : 0.38)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(node.title))
            .accessibilityValue(Text(accessibilityValue(for: node)))
            .help(helpText(for: node))

        if isDrillable(node) {
            base
                .accessibilityAddTraits(.isButton)
                // Only offered where it does something — the hub and Surplus have no rows behind
                // them, and an action that silently no-ops is worse than no action.
                .accessibilityAction { select(node) }
        } else {
            base
        }
    }


    /// `trailing` comes from the resolved label rather than the node's role: the surplus is an
    /// outflow, but it is now drawn as the hub's unspent tail and labelled in the hub's own
    /// left-aligned column, so role alone would align it the wrong way.
    @ViewBuilder
    private func labelContent(_ node: CashFlowSankeyNode, trailing: Bool, lineCount: Int) -> some View {
        let alignment: HorizontalAlignment = trailing ? .trailing : .leading
        // Two lines only where the pipe is thick enough to contain them; otherwise the name and the
        // amount collapse onto one, which nearly halves the block and keeps the text inside the flow
        // it names rather than spilling across its neighbours.
        Group {
            if lineCount >= 2 {
                VStack(alignment: alignment, spacing: 1) {
                    labelName(node)
                    labelAmount(node)
                }
            } else {
                HStack(spacing: 6) {
                    if trailing { Spacer(minLength: 0) }
                    labelName(node)
                    labelAmount(node)
                    if !trailing { Spacer(minLength: 0) }
                }
            }
        }
        // Labels sit over the ribbon field — the flows run the full width, under the gutters — so
        // without a scrim the hub's total in particular was unreadable against the mass of colour
        // behind it. Fitted to the text, not to the label slot, so it stays a soft backing rather
        // than a row of dark blocks.
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WCColor.background.opacity(0.62))
        )
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func labelName(_ node: CashFlowSankeyNode) -> some View {
        Text(node.title)
            .font(.subheadline.weight(isSynthetic(node) ? .semibold : .regular))
            .foregroundStyle(isSynthetic(node) ? Color.white : Color.white.opacity(0.82))
            .lineLimit(1)
            // Truncating the name is better than truncating the amount: a clipped category is
            // still recognisable, a clipped number is misinformation.
            .layoutPriority(0)
            .minimumScaleFactor(0.72)
    }

    private func labelAmount(_ node: CashFlowSankeyNode) -> some View {
        Text(settings.privateCurrency(node.value))
            .font(.caption.monospacedDigit())
            .foregroundStyle(node.role == .shortfall ? WCColor.warning : WCColor.textTertiary)
            .lineLimit(1)
            .layoutPriority(1)
            .minimumScaleFactor(0.72)
    }

    /// Mirrors the cash-flow card's legend row: the totals sit here until you point at something,
    /// then it becomes an inspector for whatever is under the pointer.
    private var detailRow: some View {
        let node = activeHover.flatMap { nodesByID[$0] }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if let node {
                    Text(node.title)
                } else {
                    Text("Total cash flow")
                }
            }
            .textCase(.uppercase)
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(.secondary)

            Text(settings.privateCurrency(node?.value ?? sankey.total))
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(node.map(color(for:)) ?? WCColor.primary)

            if let node, node.role != .hub {
                Text(verbatim: "\(node.share.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WCColor.textTertiary)
            }

            // The fold is only honest if you can see inside it.
            if let node, node.isFolded {
                Text(verbatim: node.folded.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(WCColor.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .accessibilityHidden(true)
    }

    // MARK: - Styling

    private func color(for node: CashFlowSankeyNode?) -> Color {
        guard let node else { return WCColor.primary }
        // Checked before the role: a fold bucket is a remainder on either side, and an income-side
        // one would otherwise come out green and read as a real source.
        if node.isFolded { return ColorPalette.flowFolded }
        switch node.role {
        case .hub:
            return WCColor.primary
        case .surplus:
            return ColorPalette.flowRemainder
        // The shortfall keeps its amber even though it is drawn in the same recessive outlined
        // style as the surplus: it is structurally a remainder, but it is also the one thing on
        // this chart that is *bad news*, and quieting the hue as well would bury it.
        case .shortfall:
            return WCColor.warning
        case .income:
            return node.colorIndex
                .map { ColorPalette.chartFlowIncome[$0 % ColorPalette.chartFlowIncome.count] }
                ?? WCColor.primary
        case .expense:
            return node.colorIndex
                .map { ColorPalette.chartFlow[$0 % ColorPalette.chartFlow.count] }
                ?? ColorPalette.flowFolded
        }
    }

    /// A node can be drilled into only when it is backed by real rows *and* someone is listening.
    private func isDrillable(_ node: CashFlowSankeyNode) -> Bool {
        node.isDrillable && onSelect != nil
    }

    /// Ribbon gradient stops. The non-hub end owns most of the run so each flow keeps its identity;
    /// only the stretch nearest the hub blends towards the hub's green.
    private func gradientStops(
        for ribbon: SankeyLayout.Ribbon,
        nodes: [String: CashFlowSankeyNode],
        remainder: Bool
    ) -> [Gradient.Stop] {
        // Quiet enough to stop dominating, solid enough to still read as a flow — at a lower alpha
        // the surplus band turned into a hole in the middle of the card.
        let alpha: Double = remainder ? 0.2 : 0.42
        let source = color(for: nodes[ribbon.sourceID]).opacity(alpha)
        let target = color(for: nodes[ribbon.targetID]).opacity(alpha)
        // Inflows run category -> hub, outflows hub -> category, so which end to hold flips.
        if ribbon.targetID == sankey.hub.id {
            return [.init(color: source, location: 0),
                    .init(color: source, location: 0.55),
                    .init(color: target, location: 1)]
        }
        return [.init(color: source, location: 0),
                .init(color: target, location: 0.45),
                .init(color: target, location: 1)]
    }

    /// Surplus and shortfall: the balancing term that makes the diagram conserve flow, not a
    /// category anyone spent money on. Drawn outlined instead of filled so it stops competing.
    private func isRemainder(_ node: CashFlowSankeyNode) -> Bool {
        node.role == .surplus || node.role == .shortfall
    }

    private func isSynthetic(_ node: CashFlowSankeyNode) -> Bool {
        node.role == .surplus || node.role == .shortfall || node.role == .hub
    }

    private func isTrailingColumn(_ node: CashFlowSankeyNode) -> Bool {
        node.role == .expense || node.role == .surplus
    }

    // MARK: - Interaction

    /// Nil when nothing is hovered — and also when the hovered node no longer exists.
    ///
    /// A node can vanish under the pointer (a sync applying, a recurring transaction posting, the
    /// period changing), and a removed view is not guaranteed to deliver its `.ended` hover phase.
    /// Without this the id would stick and leave the whole diagram permanently dimmed. Deriving it
    /// rather than storing it makes the state self-healing.
    private var activeHover: String? {
        guard let hovered, nodesByID[hovered] != nil else { return nil }
        return hovered
    }

    private func isLit(_ id: String) -> Bool {
        guard let hovered = activeHover else { return true }
        // Every flow passes through the hub, so it stays lit whenever anything is.
        return hovered == id || id == sankey.hub.id
    }

    private func isLit(_ ribbon: SankeyLayout.Ribbon) -> Bool {
        guard let hovered = activeHover else { return true }
        return hovered == ribbon.sourceID || hovered == ribbon.targetID
    }

    private func updateHover(_ id: String?) {
        guard hovered != id else { return }
        withAnimation(.easeInOut(duration: 0.15)) { hovered = id }
    }

    private func select(_ node: CashFlowSankeyNode) {
        // Surplus, shortfall and the hub have no rows behind them, so there is nothing to show.
        guard node.isDrillable, let onSelect else { return }
        onSelect(node)
    }

    private func accessibilityValue(for node: CashFlowSankeyNode) -> String {
        let amount = settings.privateCurrency(node.value)
        guard node.role != .hub, !settings.isPrivacyMode else { return amount }
        // One interpolated key rather than concatenation, so translators control the word order
        // instead of inheriting English's.
        let share = "\(node.share.formatted(.number.precision(.fractionLength(1))))%"
        return settings.localized("\(amount), \(share) of cash flow")
    }

    private func helpText(for node: CashFlowSankeyNode) -> String {
        // The bucket is both foldable and drillable, so it gets its contents *and* the invitation —
        // checking `isFolded` first would have hidden the fact that it can be opened.
        let contents = node.isFolded ? node.folded.map(\.name).joined(separator: ", ") : node.title
        guard isDrillable(node) else { return contents }
        return "\(contents) — \(settings.localized("Show these transactions"))"
    }
}

/// One ribbon.
///
/// The four corners share two x values (each end is vertical), so seven numbers describe it. They
/// nest into a balanced tree of `AnimatablePair`s because SwiftUI has no variadic animatable type —
/// verbose, but it is what lets a period change morph the ribbons instead of snapping them.
private struct RibbonShape: Shape {
    var sourceX: CGFloat
    var sourceTopY: CGFloat
    var sourceBottomY: CGFloat
    var targetX: CGFloat
    var targetTopY: CGFloat
    var targetBottomY: CGFloat
    var controlOffset: CGFloat

    init(ribbon: SankeyLayout.Ribbon) {
        sourceX = ribbon.sourceTop.x
        sourceTopY = ribbon.sourceTop.y
        sourceBottomY = ribbon.sourceBottom.y
        targetX = ribbon.targetTop.x
        targetTopY = ribbon.targetTop.y
        targetBottomY = ribbon.targetBottom.y
        controlOffset = ribbon.controlOffset
    }

    typealias Half = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    var animatableData: AnimatablePair<Half, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(sourceX, sourceTopY),
                    AnimatablePair(sourceBottomY, targetX)
                ),
                AnimatablePair(
                    AnimatablePair(targetTopY, targetBottomY),
                    controlOffset
                )
            )
        }
        set {
            sourceX = newValue.first.first.first
            sourceTopY = newValue.first.first.second
            sourceBottomY = newValue.first.second.first
            targetX = newValue.first.second.second
            targetTopY = newValue.second.first.first
            targetBottomY = newValue.second.first.second
            controlOffset = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // A mid-animation interpolation can pass through non-finite values if either endpoint was
        // non-finite; bail rather than hand CoreGraphics a NaN.
        guard sourceX.isFinite, sourceTopY.isFinite, sourceBottomY.isFinite,
              targetX.isFinite, targetTopY.isFinite, targetBottomY.isFinite,
              controlOffset.isFinite
        else { return path }

        let sourceTop = CGPoint(x: sourceX, y: sourceTopY)
        let sourceBottom = CGPoint(x: sourceX, y: sourceBottomY)
        let targetTop = CGPoint(x: targetX, y: targetTopY)
        let targetBottom = CGPoint(x: targetX, y: targetBottomY)

        path.move(to: sourceTop)
        path.addCurve(
            to: targetTop,
            control1: CGPoint(x: sourceTop.x + controlOffset, y: sourceTop.y),
            control2: CGPoint(x: targetTop.x - controlOffset, y: targetTop.y)
        )
        path.addLine(to: targetBottom)
        path.addCurve(
            to: sourceBottom,
            control1: CGPoint(x: targetBottom.x - controlOffset, y: targetBottom.y),
            control2: CGPoint(x: sourceBottom.x + controlOffset, y: sourceBottom.y)
        )
        path.closeSubpath()
        return path
    }
}

/// Carries the card's width up so the diagram can set a height proportional to it.
private struct SankeyWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
