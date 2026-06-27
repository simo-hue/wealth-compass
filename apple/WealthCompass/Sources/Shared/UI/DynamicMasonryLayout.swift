import SwiftUI

/// A responsive masonry layout that automatically determines the number of columns
/// based on available width and a specified minimum column width.
struct DynamicMasonryLayout: Layout {
    var minColumnWidth: CGFloat = 380
    var spacing: CGFloat = 32

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // WC-L14: a `nil` proposal is handled by `?? 0`, but an *infinite* proposed width would
        // make `Int(...)` trap. Clamp non-finite widths to 0 (→ a single column).
        let proposed = proposal.width ?? 0
        let width = proposed.isFinite ? proposed : 0
        let columns = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
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
        let columns = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
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
