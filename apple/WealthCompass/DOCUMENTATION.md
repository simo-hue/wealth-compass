# Documentation

- [2026-06-06 14:38]: Mac Dashboard Position Section Update
  - *Details*: Added a "Total Assets" card to the `MacDashboardView` Position section to ensure the dashboard width is fully occupied, fixing the layout gap after "Net Savings".
  - *Tech Notes*: Included `PositionMetricCard` mapping to `totals.totalAssets` in `LazyVGrid`.

- [2026-06-06 14:43]: Mac Dashboard Cards Height Alignment Fix
  - *Details*: Ensured that the dashboard cards in the Mac app ("Top Expense Categories", "Recent Activity", "Six-Month Cash Flow", "Asset Allocation") align perfectly by stretching their inner VStacks to the maximum available height.
  - *Tech Notes*: Applied `.frame(maxHeight: .infinity, alignment: .top)` to the content `VStack` inside `allocationCard`, `cashFlowCard`, `topExpensesCard`, and `recentActivityCard` in `MacDashboardView.swift`.
