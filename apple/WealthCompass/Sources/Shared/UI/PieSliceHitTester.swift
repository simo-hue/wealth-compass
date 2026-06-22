import CoreGraphics
import Foundation

/// Shared pie/donut hit-testing geometry (M2).
///
/// Previously copy-pasted in ~4 views (`AllocationChart`, iOS `CashFlowView`,
/// `MacDashboardView`, `MacCashFlowView`). Returns the index of the slice under a
/// touch/pointer location so each call site can map it back to its own slice type.
enum PieSliceHitTester {
    /// The index of the slice hit at `location` within `rect`, or `nil` when the point
    /// is outside the donut band. `values` are the slice magnitudes in draw order
    /// (clockwise from 12 o'clock, matching the app's pie rendering).
    static func sliceIndex(
        at location: CGPoint,
        in rect: CGRect,
        values: [Double],
        innerRadiusRatio: Double = 0.62
    ) -> Int? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y

        let distance = (dx * dx + dy * dy).squareRoot()
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * innerRadiusRatio
        guard distance >= innerRadius, distance <= radius else { return nil }

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let total = values.reduce(0, +)
        guard total > 0 else { return nil }

        let selectedValue = (angle / (2 * .pi)) * total
        var cumulative = 0.0
        for (index, value) in values.enumerated() {
            cumulative += value
            if selectedValue <= cumulative { return index }
        }
        return nil
    }
}
