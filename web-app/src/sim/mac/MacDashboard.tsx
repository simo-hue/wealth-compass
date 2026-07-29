import { Fragment, useState, type ReactNode } from 'react';
import {
  ArrowDownLeft,
  ArrowDownRight,
  ArrowDownToLine,
  ArrowUpRight,
  ArrowUpToLine,
  CreditCard,
  EyeOff,
  Percent,
  Plus,
} from 'lucide-react';
import { CHART_PALETTE, MAC_TEXT, SF_ROUNDED, WC } from '../tokens';
import { FinanceCard, MacCard, MacHeroScenery } from '../ui';
import { Bars, BarLabels, Donut, Trail, type DonutSlice } from '../charts';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import { MAC_H } from './MacWindow';
import {
  RANGES,
  type Activity,
  type CashFlowMonth,
  type Range,
  assetAllocation,
  liabilities,
  monthlyCashFlow,
  recentActivityMac,
  snapshotAgeDays,
  sumCashFlow,
  topExpenses,
  totals,
  trail,
  trailChange,
} from '../data';

/**
 * A port of Sources/macOS/Views/MacDashboardView.swift.
 *
 * The Mac says "Your financial horizon" where iOS says "Financial horizon", and
 * its allocation subtitle is "How investable assets are distributed" rather than
 * "How the portfolio is distributed". Both differences are real and preserved —
 * they are separate keys in the string catalogue.
 *
 * Two structural differences from the phone govern most of this file:
 *
 *   1. Type. The window lays out in macOS points, where the text styles resolve
 *      far smaller and far flatter than on iOS — .headline is 13, not 17, and
 *      .footnote/.caption/.caption2 all land on 10. Everything here reads from
 *      MAC_TEXT; nothing may read from TEXT.
 *   2. Surfaces. The dashboard's own cards are DashboardGlassCard, not
 *      FinanceCard (MacDashboardView.swift:910-943), so they use MacCard. The
 *      metric tiles are the exception: MetricCard is shared, and its body is a
 *      FinanceCard on both platforms (DesignSystem.swift:223) — only its type
 *      scale changes with the platform, which is why MacMetricCard below wraps
 *      the shared FinanceCard rather than MacCard.
 *
 * Privacy Mode also diverges from the phone rather than merely repeating it: the
 * Mac conceals the allocation ring (:445-449) where iOS keeps the donut visible,
 * and it flattens the top-expense bars (:750-753).
 */

const CASH_FLOW_RANGES = ['3M', '6M', '12M'] as const;
type CashFlowRange = (typeof CASH_FLOW_RANGES)[number];

/** CashFlowTimeframe's rawValue is the month count it covers (FinanceModels.swift:210-213). */
const CASH_FLOW_MONTHS: Record<CashFlowRange, number> = { '3M': 3, '6M': 6, '12M': 12 };

/**
 * The snapshot behind `snapshotFreshness`, as a fixed instant rather than a
 * pre-formatted string, so the date renders in the reader's language the way
 * `Date.formatted(date:.abbreviated, time:.shortened)` does in the app. Pinned to
 * UTC because the prerender runs in the build machine's zone and hydration runs
 * in the visitor's — a floating local time would disagree across the two.
 */
const LATEST_SNAPSHOT = new Date('2026-06-05T23:03:00Z');

export function MacDashboard() {
  const { money, percent, lang, privacy } = useSim();
  // MacDashboardView.swift:9 — the Mac opens on .oneYear, not the phone's range.
  const [range, setRange] = useState<Range>('1Y');
  const [cashFlowRange, setCashFlowRange] = useState<CashFlowRange>('6M');
  const [hoveredMonth, setHoveredMonth] = useState<number | null>(null);

  const points = trail(range);
  const change = trailChange(range);
  const positive = change.value >= 0;

  const months = monthlyCashFlow.slice(-CASH_FLOW_MONTHS[cashFlowRange]);
  const windowTotals = sumCashFlow(months);
  const hovered = hoveredMonth === null ? null : months[hoveredMonth];
  const net = hovered ? hovered.income - hovered.expenses : windowTotals.net;

  const june = monthlyCashFlow[monthlyCashFlow.length - 1];
  const netSavings = june.income - june.expenses;
  const savingsRate = june.income > 0 ? (netSavings / june.income) * 100 : 0;
  // CategoryTotal.percentage is the share of *all* expenses in the period
  // (AnalyticsEngine.swift:250), not of the largest one — it is what sets the bar
  // widths, so a five-row card never fills its top bar to the end.
  const expenseTotal = topExpenses.reduce((sum, expense) => sum + expense.value, 0);

  const snapshotAge = t('%lldd ago', lang).replace('%lld', String(snapshotAgeDays));

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%', position: 'relative', isolation: 'isolate' }}>
      <MacDashboardBackdrop />

      {/* dashboardHeader — a fixed row, not scrolled. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 20, padding: '24px 24px 16px' }}>
        <div style={{ flex: 1, minWidth: 0, display: 'grid', gap: 5 }}>
          {/* @ScaledMetric headerSize = 30. */}
          <span className="wc-title-gradient" style={{ fontFamily: SF_ROUNDED, fontSize: 30, fontWeight: 700, lineHeight: 1.1 }}>
            {t('Your financial horizon', lang)}
          </span>
          <span style={{ fontSize: MAC_TEXT.subheadline, color: 'rgba(255,255,255,0.58)' }}>
            {t('A clear view of what you own, owe, earn, and spend.', lang)}
          </span>
        </div>

        {privacy && (
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              padding: '7px 11px',
              borderRadius: 999,
              background: 'rgba(255,255,255,0.07)',
              fontSize: MAC_TEXT.caption,
              fontWeight: 600,
              color: 'rgba(255,255,255,0.72)',
              flexShrink: 0,
            }}
          >
            <EyeOff size={12} strokeWidth={2.2} /> {t('Privacy on', lang)}
          </span>
        )}

        <span
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 6,
            padding: '7px 14px',
            borderRadius: 20,
            background: WC.primary,
            color: 'rgba(0,0,0,0.85)',
            fontSize: MAC_TEXT.body,
            fontWeight: 600,
            flexShrink: 0,
          }}
        >
          <Plus size={13} strokeWidth={3} /> {t('Add Transaction', lang)}
        </span>
      </div>

      <div style={{ display: 'grid', gap: 20, padding: '4px 24px 36px', alignContent: 'start' }}>
        {/* netWorthHero. Swift passes padding 0 and pads the content instead so the
            scenery reaches the card edge; in CSS an absolutely positioned child
            already resolves against the padding box, so the padding stays here. */}
        <MacCard padding={24} style={{ display: 'grid', gap: 18 }}>
          <MacHeroScenery />
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 24 }}>
            <div style={{ flex: 1, minWidth: 0, display: 'grid', gap: 8 }}>
              <span style={{ fontSize: MAC_TEXT.caption, fontWeight: 700, letterSpacing: '1.8px', color: WC.textTertiary }}>
                {t('NET WORTH', lang)}
              </span>
              {/* @ScaledMetric netWorthSize = 42. */}
              <span
                style={{
                  fontFamily: SF_ROUNDED,
                  fontSize: 42,
                  fontWeight: 700,
                  fontVariantNumeric: 'tabular-nums',
                  lineHeight: 1.05,
                  whiteSpace: 'nowrap',
                }}
              >
                {money(totals.netWorth)}
              </span>
              <span
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 7,
                  fontSize: MAC_TEXT.subheadline,
                  fontWeight: 600,
                  fontVariantNumeric: 'tabular-nums',
                  color: positive ? WC.primary : WC.destructive,
                }}
              >
                {positive ? <ArrowUpRight size={12} strokeWidth={2.6} /> : <ArrowDownRight size={12} strokeWidth={2.6} />}
                {money(Math.abs(change.value))}
                <span>{percent(Math.abs(change.percent))}</span>
                {/* The catalogue key is "for %@", so the range lands where each
                    language puts it rather than always trailing an English "for". */}
                <span style={{ color: WC.textTertiary }}>{t('for %@', lang).replace('%@', range)}</span>
              </span>
            </div>

            <div style={{ display: 'grid', gap: 12, justifyItems: 'end', flexShrink: 0 }}>
              <div style={{ paddingBottom: 2 }}>
                <Segmented options={RANGES} value={range} onChange={setRange} label="Net worth range" compact />
              </div>

              {/* snapshotFreshness (:402-423) — 4 days old, so the dot is warning. */}
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span
                  style={{ width: 7, height: 7, borderRadius: '50%', background: WC.warning, boxShadow: `0 0 4px ${WC.warning}bf` }}
                />
                <span style={{ display: 'grid', gap: 2, justifyItems: 'end' }}>
                  <span style={{ fontSize: MAC_TEXT.caption, fontWeight: 600, color: 'rgba(255,255,255,0.78)' }}>
                    {t('Latest snapshot %@', lang).replace('%@', snapshotAge)}
                  </span>
                  <span style={{ fontSize: MAC_TEXT.caption2, color: WC.textTertiary }}>
                    {new Intl.DateTimeFormat(lang, { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }).format(
                      LATEST_SNAPSHOT,
                    )}
                  </span>
                </span>
              </span>
            </div>
          </div>

          {privacy ? (
            <PrivacyChartCover
              title={t('Net-worth history concealed', lang)}
              message={t('Turn off Privacy Mode to reveal values and movement.', lang)}
              height={238}
            />
          ) : (
            <div style={{ height: 238 }}>
              <Trail
                values={points.map((p) => p.value)}
                height={238}
                showDots={points.length <= 40}
                label={t('Net-worth history', lang)}
              />
            </div>
          )}
        </MacCard>

        {/* keyMetrics (:99-144) — the >= 1080pt branch, five flexible columns. */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 16 }}>
          <MacMetricCard
            title={t('Monthly Income', lang)}
            value={money(june.income)}
            icon={<ArrowDownLeft size={15} strokeWidth={2.4} />}
            detail={t('This month', lang)}
          />
          <MacMetricCard
            title={t('Monthly Expenses', lang)}
            value={money(june.expenses)}
            icon={<ArrowUpRight size={15} strokeWidth={2.4} />}
            accent={WC.destructive}
            detail={t('This month', lang)}
          />
          <MacMetricCard
            title={t('Net Savings', lang)}
            value={money(netSavings)}
            icon={
              netSavings >= 0 ? <ArrowDownToLine size={15} strokeWidth={2.4} /> : <ArrowUpToLine size={15} strokeWidth={2.4} />
            }
            accent={netSavings >= 0 ? WC.primary : WC.destructive}
            detail={t('Income less expenses', lang)}
          />
          {/* No accent argument in Swift, so this tile keeps MetricCard's default. */}
          <MacMetricCard
            title={t('Savings Rate', lang)}
            value={percent(savingsRate)}
            icon={<Percent size={15} strokeWidth={2.4} />}
            detail={t('Of monthly income', lang)}
          />
          <MacMetricCard
            title={t('Liabilities', lang)}
            value={money(totals.debt)}
            icon={<CreditCard size={15} strokeWidth={2.4} />}
            accent={WC.destructive}
            detail={t('%lld liabilities', lang).replace('%lld', String(liabilities.length))}
          />
        </div>

        {/* allocationCard | cashFlowCard — the >= 1090pt branch. Both cards carry
            `.frame(maxHeight: .infinity, alignment: .top)`, so they stretch to the
            taller of the two and keep their content at the top. */}
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(340px, 0.34fr) 1fr', gap: 20 }}>
          <MacAllocationCard
            slices={assetAllocation().map((slice, i) => ({ ...slice, color: CHART_PALETTE[i % CHART_PALETTE.length] }))}
          />

          <MacCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <MacSectionHeading title={t('Cash Flow', lang)} subtitle={t('Income and expenses by month', lang)} />
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
                <Segmented
                  options={CASH_FLOW_RANGES}
                  value={cashFlowRange}
                  onChange={(next) => {
                    setCashFlowRange(next);
                    // The hover index addresses the visible window, so a shorter
                    // window would otherwise keep pointing past its own end.
                    setHoveredMonth(null);
                  }}
                  label="Cash-flow range"
                  compact
                />
                <span style={{ fontSize: MAC_TEXT.caption, fontWeight: 600, color: WC.primary, whiteSpace: 'nowrap' }}>
                  {t('View Cash Flow', lang)}
                </span>
              </div>
            </div>

            {privacy ? (
              <PrivacyChartCover
                title={t('Cash-flow chart concealed', lang)}
                message={t('Monthly amounts and proportions are hidden.', lang)}
                height={244}
              />
            ) : (
              <div>
                <HoverableBars
                  data={months}
                  height={244}
                  hovered={hoveredMonth}
                  onHover={setHoveredMonth}
                  label={t('Income and expenses by month', lang)}
                />
                <BarLabels data={months} />
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
              <CashFlowLegendItem
                color={WC.primary}
                title={t('Income', lang)}
                value={money(hovered ? hovered.income : windowTotals.income)}
              />
              <CashFlowLegendItem
                color={WC.destructive}
                title={t('Expenses', lang)}
                value={money(hovered ? hovered.expenses : windowTotals.expenses)}
              />
              <span style={{ flex: 1 }} />
              <span style={{ display: 'grid', gap: 3, justifyItems: 'end' }}>
                <span
                  style={{
                    fontSize: MAC_TEXT.caption2,
                    fontWeight: 700,
                    letterSpacing: '1px',
                    textTransform: 'uppercase',
                    color: WC.textFaint,
                  }}
                >
                  {hovered ? hovered.month : t('%@ NET', lang).replace('%@', cashFlowRange)}
                </span>
                <span
                  style={{
                    fontSize: MAC_TEXT.subheadline,
                    fontWeight: 700,
                    fontVariantNumeric: 'tabular-nums',
                    color: net >= 0 ? WC.primary : WC.destructive,
                  }}
                >
                  {money(net)}
                </span>
              </span>
            </div>
          </MacCard>
        </div>

        {/* topExpensesCard | recentActivityCard — the >= 1020pt branch. */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
          <MacCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
            <MacSectionHeading
              title={t('Top Expense Categories', lang)}
              subtitle={t('Where recorded spending is concentrated', lang)}
            />
            <div style={{ display: 'grid', gap: 15 }}>
              {topExpenses.map((expense, i) => {
                const share = expenseTotal > 0 ? (expense.value / expenseTotal) * 100 : 0;
                return (
                  <div key={expense.name} style={{ display: 'grid', gap: 8 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <span
                        style={{
                          width: 18,
                          fontSize: MAC_TEXT.caption2,
                          fontWeight: 700,
                          fontVariantNumeric: 'tabular-nums',
                          color: WC.textFaint,
                        }}
                      >
                        {i + 1}
                      </span>
                      <span
                        style={{
                          fontSize: MAC_TEXT.subheadline,
                          fontWeight: 500,
                          color: 'rgba(255,255,255,0.82)',
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                        }}
                      >
                        {t(expense.name, lang)}
                      </span>
                      <span style={{ flex: 1 }} />
                      <span
                        style={{
                          fontSize: MAC_TEXT.subheadline,
                          fontWeight: 600,
                          fontVariantNumeric: 'tabular-nums',
                          color: WC.textPrimary,
                        }}
                      >
                        {money(expense.value)}
                      </span>
                      <span
                        style={{
                          width: 48,
                          textAlign: 'end',
                          fontSize: MAC_TEXT.caption,
                          fontWeight: 500,
                          fontVariantNumeric: 'tabular-nums',
                          color: WC.textTertiary,
                        }}
                      >
                        {percent(share)}
                      </span>
                    </div>

                    {privacy ? (
                      // A true-width bar leaks the proportion the amount above it
                      // is hiding, so Privacy Mode flattens it (:750-753).
                      <div style={{ height: 5, borderRadius: 999, background: 'rgba(255,255,255,0.07)' }} />
                    ) : (
                      <div style={{ height: 5, borderRadius: 999, background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                        <div
                          style={{
                            width: `${Math.max(0, Math.min(share, 100))}%`,
                            height: '100%',
                            borderRadius: 999,
                            background: `linear-gradient(90deg, ${WC.warning}, rgba(242,66,66,0.82))`,
                          }}
                        />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </MacCard>

          <MacCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <MacSectionHeading title={t('Recent Activity', lang)} subtitle={t('Your latest recorded cash movements', lang)} />
              </div>
              <span style={{ fontSize: MAC_TEXT.caption, fontWeight: 600, color: WC.primary, whiteSpace: 'nowrap' }}>
                {t('View All', lang)}
              </span>
            </div>
            {/* One card of rows separated by inset dividers, not a stack of pills
                (:810-823) — and six rows on the Mac, where the phone shows five. */}
            <div style={{ display: 'grid' }}>
              {recentActivityMac.map((activity, i) => (
                <Fragment key={activity.id}>
                  <ActivityRow activity={activity} />
                  {i < recentActivityMac.length - 1 && (
                    <span style={{ height: 1, background: 'rgba(255,255,255,0.06)', marginInlineStart: 45 }} />
                  )}
                </Fragment>
              ))}
            </div>
          </MacCard>
        </div>
      </div>
    </div>
  );
}

/**
 * MacDashboardBackdrop (:1126-1149). The Dashboard is the one Mac page that does
 * not use the shared ScreenBackground: its wash is a shade cooler and, crucially,
 * still — one 520pt blur with no animation at all.
 *
 * The circle's y is measured from the top of the window rather than of the
 * scrolled content, which is what Swift offsets against; it therefore drifts as
 * the pane scrolls, where the app's stays put.
 */
function MacDashboardBackdrop() {
  return (
    <div
      aria-hidden="true"
      style={{
        position: 'absolute',
        inset: 0,
        zIndex: -1,
        overflow: 'hidden',
        // Color(0.035, 0.085, 0.105) @ .8 → clear → Color(0.035, 0.045, 0.085) @ .65,
        // over WCColor.background. Opaque on purpose: it is what hides the
        // animated scenery MacWindow paints behind every page.
        background: `linear-gradient(135deg, rgba(9,22,27,0.8) 0%, transparent 50%, rgba(9,11,22,0.65) 100%), ${WC.background}`,
      }}
    >
      <span
        style={{
          position: 'absolute',
          width: 520,
          height: 520,
          left: 'calc(50% + 420px)',
          top: MAC_H / 2 - 330,
          transform: 'translate(-50%, -50%)',
          borderRadius: '50%',
          background: 'rgba(31,219,153,0.055)',
          filter: 'blur(110px)',
        }}
      />
    </div>
  );
}

/** sectionHeading (:832-841) — a private helper of the Mac dashboard, on Mac type. */
function MacSectionHeading({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div style={{ display: 'grid', gap: 4 }}>
      <span style={{ fontSize: MAC_TEXT.headline, fontWeight: 600, color: WC.textPrimary }}>{title}</span>
      <span style={{ fontSize: MAC_TEXT.caption, color: WC.textTertiary }}>{subtitle}</span>
    </div>
  );
}

/**
 * MetricCard (DesignSystem.swift:197-258) as it resolves on macOS.
 *
 * The shared MetricCard in ui.tsx is the same view at iOS sizes; the geometry —
 * the FinanceCard body, the 34pt tile, the 5pt dot — is identical, and only the
 * three text styles move (.caption 12 → 10, .title3 20 → 15, .caption2 11 → 10).
 * The component takes no size props, so the Mac's copy lives here rather than as
 * a platform flag on a component every iOS screen also calls.
 */
function MacMetricCard({
  title,
  value,
  icon,
  accent = WC.primary,
  detail,
}: {
  title: string;
  value: string;
  icon: ReactNode;
  accent?: string;
  detail?: string;
}) {
  return (
    <FinanceCard style={{ display: 'grid', gap: 15, alignContent: 'start' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span
          style={{
            width: 34,
            height: 34,
            display: 'grid',
            placeItems: 'center',
            borderRadius: 10,
            background: `${accent}1f`,
            color: accent,
          }}
        >
          {icon}
        </span>
        <span
          style={{ width: 5, height: 5, borderRadius: '50%', background: accent, opacity: 0.72, boxShadow: `0 0 4px ${accent}a6` }}
        />
      </div>
      <div style={{ display: 'grid', gap: 4, minWidth: 0 }}>
        <span style={{ fontSize: MAC_TEXT.caption, fontWeight: 500, color: WC.textTertiary }}>{title}</span>
        <span
          style={{
            fontSize: MAC_TEXT.title3,
            fontWeight: 700,
            fontVariantNumeric: 'tabular-nums',
            color: WC.textPrimary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {value}
        </span>
        {detail && <span style={{ fontSize: MAC_TEXT.caption2, color: WC.textFaint }}>{detail}</span>}
      </div>
    </FinanceCard>
  );
}

/**
 * allocationCard (:425-561). Not the shared AllocationCard: that one is an iOS
 * card (FinanceCard, iOS type, a donut that stays drawn under Privacy Mode), and
 * all four differences show at once here. The ring is the shared Donut, which is
 * platform-free.
 */
function MacAllocationCard({ slices }: { slices: DonutSlice[] }) {
  const { money, percent, lang, privacy } = useSim();
  const [hovered, setHovered] = useState<number | null>(null);
  const total = slices.reduce((sum, slice) => sum + slice.value, 0);
  const active = hovered !== null ? slices[hovered] : null;

  return (
    <MacCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
      <MacSectionHeading title={t('Asset Allocation', lang)} subtitle={t('How investable assets are distributed', lang)} />

      {privacy ? (
        // The whole ring goes, not just the numbers: a visible donut still shows
        // the split it is meant to be hiding (:445-449). iOS decided the other
        // way and keeps its donut — this is a genuine platform difference.
        <PrivacyChartCover
          title={t('Allocation concealed', lang)}
          message={t('Values and proportions are hidden.', lang)}
          height={210}
        />
      ) : (
        <div style={{ height: 210, display: 'grid', placeItems: 'center' }}>
          <Donut
            slices={slices}
            size={210}
            hovered={hovered}
            onHover={setHovered}
            label={t('Asset Allocation', lang)}
            center={
              <div style={{ display: 'grid', gap: 3, maxWidth: 210 * 0.6 }}>
                <span
                  style={{
                    fontSize: MAC_TEXT.caption2,
                    fontWeight: 700,
                    letterSpacing: '1.3px',
                    color: active ? active.color : WC.textTertiary,
                  }}
                >
                  {/* "ASSETS", not "TOTAL": the ring is gross assets and leaves
                      liabilities out (:484). */}
                  {active ? active.name.toUpperCase() : t('ASSETS', lang)}
                </span>
                <span
                  style={{
                    fontSize: MAC_TEXT.headline,
                    fontWeight: 700,
                    fontVariantNumeric: 'tabular-nums',
                    color: WC.textPrimary,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {money(active ? active.value : total)}
                </span>
                {active && (
                  <span
                    style={{ fontSize: MAC_TEXT.caption2, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums' }}
                  >
                    {percent(total > 0 ? (active.value / total) * 100 : 0)}
                  </span>
                )}
              </div>
            }
          />
        </div>
      )}

      {/* The Mac legend is its own layout (:527-547): 11pt apart, a brighter name
          and a tertiary share. */}
      <div style={{ display: 'grid', gap: 11 }}>
        {slices.map((slice) => (
          <div key={slice.name} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ width: 10, height: 10, borderRadius: 3, background: slice.color, flexShrink: 0 }} />
            <span style={{ fontSize: MAC_TEXT.subheadline, fontWeight: 500, color: 'rgba(255,255,255,0.76)' }}>{slice.name}</span>
            <span style={{ flex: 1 }} />
            <span style={{ display: 'grid', gap: 2, justifyItems: 'end' }}>
              <span
                style={{
                  fontSize: MAC_TEXT.subheadline,
                  fontWeight: 600,
                  fontVariantNumeric: 'tabular-nums',
                  color: WC.textPrimary,
                }}
              >
                {money(slice.value)}
              </span>
              <span style={{ fontSize: MAC_TEXT.caption2, color: WC.textTertiary, fontVariantNumeric: 'tabular-nums' }}>
                {percent(total > 0 ? (slice.value / total) * 100 : 0)}
              </span>
            </span>
          </div>
        ))}
      </div>
    </MacCard>
  );
}

/**
 * The cash-flow chart's hover behaviour (:611,622,627-650): pointing at a month
 * dims every other bar to 0.3 and re-reads the legend for that month alone.
 *
 * Bars draws one svg for the whole series and exposes no per-bar handle, so the
 * dim is done by layering: the base copy fades to 0.3 as a whole and a second,
 * clipped copy re-draws the hovered column at full strength. The hover zones are
 * a separate grid on top, forced to LTR — the bars inside the svg are always
 * drawn in data order left to right, so mirroring the zones under RTL would pair
 * each zone with the wrong month.
 */
function HoverableBars({
  data,
  height,
  hovered,
  onHover,
  label,
}: {
  data: CashFlowMonth[];
  height: number;
  hovered: number | null;
  onHover: (index: number | null) => void;
  label: string;
}) {
  const column = 100 / data.length;

  return (
    <div style={{ position: 'relative' }}>
      <div style={{ opacity: hovered === null ? 1 : 0.3, transition: 'opacity 150ms ease-in-out' }}>
        <Bars data={data} height={height} label={label} />
      </div>

      {hovered !== null && (
        <div
          aria-hidden="true"
          style={{
            position: 'absolute',
            inset: 0,
            clipPath: `inset(0 ${(data.length - hovered - 1) * column}% 0 ${hovered * column}%)`,
          }}
        >
          <Bars data={data} height={height} />
        </div>
      )}

      <div
        aria-hidden="true"
        style={{
          position: 'absolute',
          inset: 0,
          direction: 'ltr',
          display: 'grid',
          gridTemplateColumns: `repeat(${data.length}, 1fr)`,
        }}
      >
        {data.map((month, i) => (
          <div key={month.month} onPointerEnter={() => onHover(i)} onPointerLeave={() => onHover(null)} />
        ))}
      </div>
    </div>
  );
}

/** CashFlowLegendItem (:945-965) — a 9×24 bar beside a two-line readout. */
function CashFlowLegendItem({ color, title, value }: { color: string; title: string; value: string }) {
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
      <span style={{ width: 9, height: 24, borderRadius: 3, background: color, flexShrink: 0 }} />
      <span style={{ display: 'grid', gap: 2 }}>
        <span style={{ fontSize: MAC_TEXT.caption2, fontWeight: 500, color: WC.textTertiary }}>{title}</span>
        <span
          style={{
            fontSize: MAC_TEXT.caption,
            fontWeight: 600,
            fontVariantNumeric: 'tabular-nums',
            color: 'rgba(255,255,255,0.82)',
          }}
        >
          {value}
        </span>
      </span>
    </span>
  );
}

/** ActivityRow (:967-1006). */
function ActivityRow({ activity }: { activity: Activity }) {
  const { money, lang, privacy } = useSim();
  const income = activity.kind === 'income';
  const tint = income ? WC.primary : WC.destructive;
  // signedAmount (:870-875): the sign is a real minus, and Privacy Mode replaces
  // the whole string rather than signing the redaction token.
  const amount = privacy ? money(activity.amount) : `${income ? '+' : '−'}${money(Math.abs(activity.amount))}`;

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 0' }}>
      <span
        style={{
          width: 32,
          height: 32,
          display: 'grid',
          placeItems: 'center',
          borderRadius: 9,
          background: `${tint}1c`, // .opacity(0.11)
          color: tint,
          flexShrink: 0,
        }}
      >
        {income ? <ArrowDownLeft size={12} strokeWidth={2.8} /> : <ArrowUpRight size={12} strokeWidth={2.8} />}
      </span>
      <div style={{ display: 'grid', gap: 3, flex: 1, minWidth: 0 }}>
        <span style={{ fontSize: MAC_TEXT.subheadline, fontWeight: 500, color: 'rgba(255,255,255,0.84)' }}>
          {t(activity.category, lang)}
        </span>
        {/* The demo rows carry no description, so the row falls back to the
            transaction type the way Swift's `description.isEmpty` branch does. */}
        <span style={{ fontSize: MAC_TEXT.caption2, color: WC.textFaint }}>{t(income ? 'Income' : 'Expense', lang)}</span>
      </div>
      <span style={{ display: 'grid', gap: 3, justifyItems: 'end' }}>
        {/* Only income is tinted. An expense is white .8 — the red lives in the
            icon, so a list of expenses doesn't read as a list of errors. */}
        <span
          style={{
            fontSize: MAC_TEXT.subheadline,
            fontWeight: 600,
            fontVariantNumeric: 'tabular-nums',
            color: income ? WC.primary : 'rgba(255,255,255,0.8)',
          }}
        >
          {amount}
        </span>
        <span style={{ fontSize: MAC_TEXT.caption2, color: WC.textFaint }}>{activity.day}</span>
      </span>
    </div>
  );
}

/** PrivacyChartCover (:1059-1087) — the Mac's cover, at 14pt corners over black .12. */
function PrivacyChartCover({ title, message, height }: { title: string; message: string; height: number }) {
  return (
    <div
      style={{
        height,
        display: 'grid',
        placeItems: 'center',
        padding: 16,
        textAlign: 'center',
        borderRadius: 14,
        background: 'rgba(0,0,0,0.12)',
        border: '1px solid rgba(255,255,255,0.05)',
      }}
    >
      <div style={{ display: 'grid', gap: 9, justifyItems: 'center' }}>
        <EyeOff size={MAC_TEXT.title2} strokeWidth={1.8} color="rgba(31,219,153,0.75)" />
        <span style={{ fontSize: MAC_TEXT.subheadline, fontWeight: 600, color: 'rgba(255,255,255,0.82)' }}>{title}</span>
        <span style={{ fontSize: MAC_TEXT.caption, color: WC.textFaint }}>{message}</span>
      </div>
    </div>
  );
}
