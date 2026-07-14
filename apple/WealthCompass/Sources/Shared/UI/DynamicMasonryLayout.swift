import SwiftUI

/// A responsive masonry layout that automatically determines the number of columns
/// based on available width and a specified minimum column width.
struct DynamicMasonryLayout: Layout {
    var minColumnWidth: CGFloat = 380
    var spacing: CGFloat = 32
    /// Optional hard cap on the number of columns, regardless of how many `minColumnWidth`-wide
    /// columns would otherwise fit. Keeps form-style content (e.g. the Settings sections) from
    /// fanning out into many skinny columns on a very wide external display. `nil` (the default)
    /// preserves the original fit-as-many-as-possible behavior for existing callers.
    var maxColumns: Int? = nil

    private func columnCount(for width: CGFloat) -> Int {
        let fit = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
        if let maxColumns { return min(fit, max(1, maxColumns)) }
        return fit
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // WC-L14: an *infinite* proposed width would make `Int(...)` trap. A `nil`/non-finite
        // proposal used to clamp to width 0, collapsing to a zero-width single column (deep-audit
        // L61, latent). Fall back to the widest subview's ideal width (or `minColumnWidth`) instead,
        // computed lazily only when the proposal is unusable.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? max(minColumnWidth, subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? minColumnWidth)
        let columns = columnCount(for: width)
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))

        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let minIndex = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] }) ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            
            columnHeights[minIndex] += size.height + spacing
        }

        let maxHeight = (columnHeights.max() ?? spacing) - spacing
        return CGSize(width: width, height: max(0, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        let columns = columnCount(for: width)
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        
        var columnHeights = Array(repeating: bounds.minY, count: columns)

        for subview in subviews {
            let minIndex = columnHeights.indices.min(by: { columnHeights[$0] < columnHeights[$1] }) ?? 0
            let x = bounds.minX + CGFloat(minIndex) * (columnWidth + spacing)
            let y = columnHeights[minIndex]
            
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )
            
            columnHeights[minIndex] += size.height + spacing
        }
    }
}
