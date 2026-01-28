# TO SIMO DO

This document tracks manual actions and considerations for you to address.

- [ ] Check the new "Portfolio Allocation" chart in the Dashboard.
- [ ] Verify if the "Net Profit / Loss" chart needs a similar stylistic update to match the new legend style (currently it uses the default Recharts legend/tooltip style).
- [ ] Confirm if the colors in `COIN_COLORS` need any adjustment for better visibility in light mode (currently optimized for dark/glass mode).
- [ ] Verify that the mobile menu ("menu a tendina") now automatically closes when clicking a link.

# Chart Verification
- [ ] **Dashboard**: Verify "Cash Flow Trend" is not stretched vertically (should be ~250px height).
- [ ] **Dashboard**: Verify "**Top Expenses (30d)**" chart is visible below Cash Flow Trend and shows correct categories.
- [ ] **Dashboard**: Verify "**Top Expenses (30d)**" chart is visible below Cash Flow Trend and shows correct categories.
- [ ] **Dashboard**: Verify "**Recent Activity**" and "**Asset Allocation**" share the full height of the right column and align with the bottom of the left column.
- [ ] **Crypto**: Verify "Portfolio Allocation" chart has the **legend BELOW** the donut chart.
- [ ] **Dashboard**: Verify "Asset Allocation" chart has the **legend BELOW** the donut chart (not on the side).
- [ ] **Allocation Page**: Verify "Allocation Chart" is a Donut chart with legend BELOW.
- [ ] **Net Worth Page**: Verify "Net Worth Chart" is an Area chart with emerald gradient.
- [ ] **Analytics Page**: Verify "Cash Flow Analytics" has a Donut expense chart and Area spending timeline.
- [ ] **FIRE Calculator**: Verify "Net Worth Projection" has a green gradient area and clear dashed benchmark lines.
- [ ] **Mobile**: Verify "Expense Structure" chart is fully visible and not cut off on mobile screens.
- [ ] **Mobile**: Verify **Investments Page** shows "Allocation" chart at the TOP, followed by the table.
- [ ] **Investments Page**: Verify "Allocation" chart no longer has a double box/border.

# Deployment Verification
- [ ] Verify the Website at `https://libriperilcambiamento.github.io/wealth-compass/` (Should see Landing Page).
- [ ] Verify the login at `https://libriperilcambiamento.github.io/wealth-compass/sw/login` (Should see Login).
- [ ] Verify Dashboard access `https://libriperilcambiamento.github.io/wealth-compass/sw/dashboard` (After login).
- [ ] **Route Verification**: Verify that entering `/sw/login` manually works.
- [ ] **Route Verification**: Verify that clicking "Login" on the homepage works.
- [ ] **Route Verification**: Verify that after login, you are redirected to `/sw/dashboard`.
