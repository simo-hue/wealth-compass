import Foundation

/// What a node in the Money Flow (Sankey) diagram stands for.
///
/// Only `.income` and `.expense` are backed by real transaction categories. The rest are
/// synthetic: a Sankey is only readable when every unit entering the hub also leaves it, and
/// income rarely equals spending, so exactly one of `.surplus` / `.shortfall` absorbs the
/// difference.
enum CashFlowSankeyRole: String, Equatable, Sendable {
    /// A real income category, or the folded "Smaller categories" bucket on the income side.
    case income
    /// The single centre node every flow passes through.
    case hub
    /// A real expense category, or the folded "Smaller categories" bucket on the expense side.
    case expense
    /// Income that was not spent in the period. Mutually exclusive with `.shortfall`.
    case surplus
    /// Spending not covered by income in the period — drawn from savings. Mutually exclusive
    /// with `.surplus`.
    case shortfall
}

/// One box in the diagram. Deliberately colour-free: the model carries a `colorIndex` and the
/// presentation layer maps it onto its own palette (`ColorPalette.chart` on screen, `ReportColor`
/// in the PDF). That keeps this file — and everything downstream of it — compilable without
/// SwiftUI, which is what lets the geometry be verified headlessly.
struct CashFlowSankeyNode: Identifiable, Equatable, Sendable {
    /// Stable across re-renders so SwiftUI can interpolate a node's frame when the period
    /// changes. Role-prefixed because a name can legitimately appear on both sides — "Other" is
    /// a default category for income *and* expense.
    let id: String
    /// Already-resolved display string (localized through the engine's `appLanguage`), so
    /// callers render it verbatim instead of re-keying it through `LocalizedStringKey`.
    let title: String
    let value: Double
    let role: CashFlowSankeyRole
    /// Percent of the diagram total, pre-computed with the divide-by-zero and NaN guards applied
    /// once here rather than at each call site — the screen card's accessibility label and the PDF
    /// legend both need it, and chart geometry downstream must never see a NaN.
    let share: Double
    /// Rank among same-role real categories, largest first — a palette slot for presentations that
    /// want one. **`nil` whenever there is no real category behind the node**: the hub, surplus,
    /// shortfall and the folded bucket are all styled from `role` / `isFolded` instead. Optional
    /// rather than a sentinel so a consumer cannot index a palette with it by accident.
    ///
    /// Which roles actually consult it is the presentation's call. The macOS card reads it only on
    /// the expense side; the income side is uniformly green, because "money in" is the signal that
    /// matters there and there are rarely more than three sources.
    let colorIndex: Int?
    /// Transaction categories this node stands for: one entry for a real category, several for
    /// the folded bucket, none for hub / surplus / shortfall. Drives the drill-through filter.
    let categories: [String]
    /// What was folded into this node, largest first, for the hover detail row. Empty unless
    /// this is the "Smaller categories" bucket. Percentages are of the diagram total.
    let folded: [CategoryTotal]

    /// Only nodes backed by real transactions can be drilled into; clicking Surplus or the hub
    /// would filter to nothing.
    var isDrillable: Bool { !categories.isEmpty }
    var isFolded: Bool { !folded.isEmpty }
}

/// A ribbon. `value` is always the full value of its non-hub endpoint — the hub is a pass-through,
/// so each inflow and each outflow owns exactly one link.
struct CashFlowSankeyLink: Identifiable, Equatable, Sendable {
    var id: String { "\(sourceID)->\(targetID)" }
    let sourceID: String
    let targetID: String
    let value: Double
}

/// The whole diagram for one period.
///
/// Invariant, relied on by the layout engine: `inflows.sum == hub.value == outflows.sum`. It is
/// what makes the ribbons meet the hub edge-to-edge with no gap and no overlap.
struct CashFlowSankey: Equatable, Sendable {
    /// Left column: real categories descending by value, then the folded bucket, then any
    /// shortfall. Synthetic nodes are pinned below the real ones rather than sorted among them,
    /// so the eye can find them in a fixed place as the period changes.
    let inflows: [CashFlowSankeyNode]
    let hub: CashFlowSankeyNode
    /// Right column, ordered on the same rule, with any surplus pinned last.
    let outflows: [CashFlowSankeyNode]
    let links: [CashFlowSankeyLink]

    /// Every node in draw order. Both consumers need exactly this list — the layout to frame them,
    /// the renderers to resolve a link's endpoints — so it lives here rather than being rebuilt at
    /// each site.
    var nodes: [CashFlowSankeyNode] { inflows + [hub] + outflows }

    /// Both the total inflow and the total outflow — they are equal by construction.
    var total: Double { hub.value }

    /// `!(total > 0)` rather than `total <= 0` so a NaN total reads as empty instead of slipping
    /// through into CoreGraphics geometry (see the conversion guards in `AppSettings.convert`).
    var isEmpty: Bool { !(total > 0) }

    static func empty(hubTitle: String) -> CashFlowSankey {
        CashFlowSankey(
            inflows: [],
            hub: CashFlowSankeyNode(
                id: "hub",
                title: hubTitle,
                value: 0,
                role: .hub,
                share: 0,
                colorIndex: nil,
                categories: [],
                folded: []
            ),
            outflows: [],
            links: []
        )
    }
}
