# Documentation

- [2026-06-06 14:38]: Mac Dashboard Position Section Update
  - *Details*: Added a "Total Assets" card to the `MacDashboardView` Position section to ensure the dashboard width is fully occupied, fixing the layout gap after "Net Savings".
  - *Tech Notes*: Included `PositionMetricCard` mapping to `totals.totalAssets` in `LazyVGrid`.
