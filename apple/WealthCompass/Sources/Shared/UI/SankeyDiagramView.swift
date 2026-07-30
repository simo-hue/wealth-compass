import SwiftUI

/// The Money Flow diagram: income categories → a hub → expense categories, with hover inspection
/// and optional drill-through.
///
/// Geometry comes entirely from `SankeyLayout`, which is pure and unit-tested; this view only
/// styles it. Ribbons are `Shape`s rather than a single `Canvas` pass so that they morph when the
/// period changes, so hover hit-testing is per-ribbon with no hand-written point-in-shape maths,
/// and so each flow is its own accessibility element.
struct SankeyDiagramView: View {
    let sankey: CashFlowSankey
    let settings: AppSettings
    var mode: SankeyLayout.Mode = .full
    var config: SankeyLayout.Config = .standard
    /// Called when a node backed by real transactions is clicked. Nil disables drill-through.
    var onSelect: ((CashFlowSankeyNode) -> Void)?

    /// Id of the hovered node, or of a ribbon's non-hub endpoint when a ribbon is hovered — both
    /// resolve to "which flow is the user pointing at".
    @State private var hovered: String?

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
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: sankey)
        }
        // Headroom above the bare minimum. `minimumHeight` is the point at which labels merely
        // stop being *dropped*; laying out at exactly that value leaves most of them shunted off
        // their bars by the de-collision pass, because a long tail's desired positions all bunch
        // together. The extra third buys back most of that slack.
        .frame(minHeight: max(240, minimumDiagramHeight * 1.35))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Money Flow"))
    }

    // MARK: - Layers

    private func ribbons(_ layout: SankeyLayout.Resolved) -> some View {
        let nodes = nodesByID
        return ForEach(layout.ribbons) { ribbon in
            let shape = RibbonShape(ribbon: ribbon)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            color(for: nodes[ribbon.sourceID]).opacity(0.42),
                            color(for: nodes[ribbon.targetID]).opacity(0.42)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // The dim lives on a view modifier, not in the gradient's stops: SwiftUI does not
                // interpolate a `ShapeStyle` change, so folding it into the fill would make the
                // ribbons pop while the bars and labels cross-fade around them.
                .opacity(isLit(ribbon) ? 1 : 0.24)
                .contentShape(shape)
                .onContinuousHover { phase in
                    // Attribute the hover to the non-hub end: hovering a ribbon means "this flow",
                    // and the hub is on every flow.
                    updateHover(phase, id: ribbon.sourceID == sankey.hub.id ? ribbon.targetID : ribbon.sourceID)
                }
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
        let bar = RoundedRectangle(cornerRadius: min(3, frame.rect.width / 2), style: .continuous)
            .fill(color(for: node))
            .opacity(isLit(frame.id) ? 1 : 0.32)
            .frame(width: frame.rect.width, height: frame.rect.height)
            // A floored bar is only 5pt tall; widen the hit region so pointing at it is realistic.
            .contentShape(Rectangle().inset(by: -6))
            .onContinuousHover { updateHover($0, id: frame.id) }
            // The label carries the accessibility element for this node, so the bar stays silent
            // rather than announcing everything twice.
            .accessibilityHidden(true)

        if isDrillable(node) {
            bar.onTapGesture { select(node) }
        } else {
            bar
        }
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
        let base = labelContent(node)
            .frame(
                width: label.rect.width,
                height: label.rect.height,
                alignment: label.alignment == .trailing ? .trailing : .leading
            )
            .opacity(isLit(label.id) ? 1 : 0.38)
            .contentShape(Rectangle())
            .onContinuousHover { updateHover($0, id: label.id) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(node.title))
            .accessibilityValue(Text(accessibilityValue(for: node)))
            .help(helpText(for: node))

        if isDrillable(node) {
            base
                .onTapGesture { select(node) }
                .accessibilityAddTraits(.isButton)
                // Only offered where it does something — the hub and Surplus have no rows behind
                // them, and an action that silently no-ops is worse than no action.
                .accessibilityAction { select(node) }
        } else {
            base
        }
    }

    @ViewBuilder
    private func labelContent(_ node: CashFlowSankeyNode) -> some View {
        let alignment: HorizontalAlignment = isTrailingColumn(node) ? .trailing : .leading
        VStack(alignment: alignment, spacing: 1) {
            Text(node.title)
                .font(.subheadline.weight(isSynthetic(node) ? .semibold : .regular))
                .foregroundStyle(isSynthetic(node) ? Color.white : Color.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(settings.privateCurrency(node.value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(node.role == .shortfall ? WCColor.warning : WCColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: isTrailingColumn(node) ? .trailing : .leading)
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
        // One green for everything on the income side: "money in" is the signal that matters, and
        // there are rarely more than three sources to tell apart.
        case .hub, .surplus, .income:
            return WCColor.primary
        case .shortfall:
            return WCColor.warning
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

    private func updateHover(_ phase: HoverPhase, id: String) {
        switch phase {
        case .active:
            guard hovered != id else { return }
            withAnimation(.easeInOut(duration: 0.15)) { hovered = id }
        case .ended:
            guard hovered == id else { return }
            withAnimation(.easeInOut(duration: 0.15)) { hovered = nil }
        }
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
