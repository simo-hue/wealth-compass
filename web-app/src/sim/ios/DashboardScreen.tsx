import { useState } from 'react';
import {
  ArrowDownLeft,
  ArrowDownRight,
  ArrowDownToLine,
  ArrowUpRight,
  Banknote,
  Bitcoin,
  Check,
  ChevronDown,
  CreditCard,
  Landmark,
  TrendingUp,
} from 'lucide-react';
import { CHART_PALETTE, SF_ROUNDED, TEXT, WC } from '../tokens';
import {
  AllocationCard,
  FinanceCard,
  InsetRow,
  MetricCard,
  MobileHeroScenery,
  PageHeader,
  PrimaryActionButton,
  SectionHeading,
} from '../ui';
import { Bars, BarLabels, Trail } from '../charts';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t, type Lang } from '../strings';
import {
  RANGES,
  type Range,
  type Slice,
  assetAllocation,
  crypto,
  holdings,
  liabilities,
  monthlyCashFlow,
  recentActivity,
  snapshotAgeDays,
  sumCashFlow,
  topExpenses,
  totals,
  trail,
  trailChange,
  transactions,
} from '../data';

/**
 * A port of Sources/iOS/Views/DashboardView.swift.
 *
 * Section order, headings, metric titles, accents and SF Symbol choices are all
 * taken from that file rather than reinvented — right down to Investments being
 * cyan-accented and Liabilities being red. Where lucide has no equivalent of an
 * SF Symbol the nearest glyph is used and noted.
 */

/** CashFlowTimeframe (FinanceModels.swift:210-231) — the label and its rawValue, a month count. */
const CASH_FLOW_RANGES = ['3M', '6M', '12M'] as const;
type CashFlowRange = (typeof CASH_FLOW_RANGES)[number];
const CASH_FLOW_MONTHS: Record<CashFlowRange, number> = { '3M': 3, '6M': 6, '12M': 12 };

/** AnalyticsPeriod (FinanceModels.swift:178-206) — rawValue and title key. */
type AnalyticsPeriod = '7d' | '30d' | '3m' | 'ytd' | 'all';
const ANALYTICS_PERIODS: { value: AnalyticsPeriod; key: string }[] = [
  { value: '7d', key: 'Last 7 Days' },
  { value: '30d', key: 'Last 30 Days' },
  { value: '3m', key: 'Last 3 Months' },
  { value: 'ytd', key: 'Year to Date' },
  { value: 'all', key: 'All Time' },
];

/**
 * The demo ledger is a single month, so the day-of-month is enough to window it
 * the way the analytics engine windows real dates, and row 0 is "now" — the same
 * reading CashFlowScreen makes of the same rows.
 */
const dayOf = (day: string) => parseInt(day, 10);
const LATEST_DAY = dayOf(transactions[0].day);

/**
 * expensesByCategory(period:) — AnalyticsEngine.swift:240-254. data.ts documents
 * `topExpenses` as the trailing-30-day breakdown and the ledger is that one
 * month, so every window from 30 days out regroups to exactly those rows; only
 * the 7-day window is a genuinely different slice.
 */
const expensesByCategory = (period: AnalyticsPeriod): Slice[] => {
  if (period !== '7d') return topExpenses;
  const map = new Map<string, number>();
  for (const row of transactions) {
    if (row.kind !== 'expense' || dayOf(row.day) <= LATEST_DAY - 7) continue;
    map.set(row.category, (map.get(row.category) ?? 0) + Math.abs(row.amount));
  }
  return [...map]
    .map(([name, value]) => ({ name, value: Math.round(value * 100) / 100 }))
    .sort((a, b) => b.value - a.value);
};

/**
 * The Net Savings card names the month its figure covers —
 * `Date().formatted(.dateTime.month(.wide).locale(effectiveLocale))`
 * (DashboardView.swift:379-382), i.e. the wide month name in the *in-app*
 * language, not the system one.
 *
 * The date is fixed rather than read from the clock: the demo's current month is
 * June, the last row of `monthlyCashFlow`, and the label has to name the month
 * the amount belongs to rather than the month the page happens to be visited.
 * Formatting in UTC keeps a negative-offset visitor from seeing "May".
 */
const DEMO_CURRENT_MONTH = Date.UTC(2026, 5, 1);
const wideMonth = (lang: Lang) =>
  new Intl.DateTimeFormat(lang, { month: 'long', timeZone: 'UTC' }).format(DEMO_CURRENT_MONTH);

/** Fills a catalogue string's `%@` placeholder, positional or bare. */
const fmt = (template: string, value: string) => template.replace(/%(?:\d+\$)?@/, () => value);

export function DashboardScreen() {
  const { money, percent, lang, privacy, rtl } = useSim();
  // The three initial selections, DashboardView.swift:8,12,13.
  const [range, setRange] = useState<Range>('1W');
  const [cashFlowRange, setCashFlowRange] = useState<CashFlowRange>('6M');
  const [expensePeriod, setExpensePeriod] = useState<AnalyticsPeriod>('30d');

  const points = trail(range);
  const change = trailChange(range);
  const positive = change.value >= 0;

  // cashFlowTrend(months:) and the totals under it are both taken from the
  // selected window, so the legend re-totals its own slice rather than the year.
  const months = monthlyCashFlow.slice(-CASH_FLOW_MONTHS[cashFlowRange]);
  const flow = sumCashFlow(months);

  const currentMonth = monthlyCashFlow[monthlyCashFlow.length - 1];

  // `percentage` is the share of *total* spending in the period, computed before
  // the list is cut to five — so the top row reads 50,1%, not 100%.
  const categories = expensesByCategory(expensePeriod);
  const expenseTotal = categories.reduce((sum, category) => sum + category.value, 0);

  return (
    <div style={{ display: 'grid', gap: 20, padding: '0 16px 28px', alignContent: 'start' }}>
      <PageHeader
        title={t('Financial horizon', lang)}
        subtitle={t('Everything you own, owe, earn, and spend.', lang)}
        trailing={<PrimaryActionButton label={t('Add Transaction', lang)} />}
      />

      {/* --- Net-worth hero -------------------------------------------- */}
      <FinanceCard style={{ display: 'grid', gap: 17 }}>
        <MobileHeroScenery />
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ display: 'grid', gap: 6, flex: 1, minWidth: 0 }}>
            <span style={{ fontSize: TEXT.caption2, fontWeight: 700, letterSpacing: '1.7px', color: WC.textTertiary }}>
              {t('NET WORTH', lang)}
            </span>
            <span
              style={{
                fontFamily: SF_ROUNDED,
                fontSize: 35,
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
                gap: 6,
                fontSize: TEXT.caption,
                fontWeight: 600,
                fontVariantNumeric: 'tabular-nums',
                color: positive ? WC.primary : WC.destructive,
              }}
            >
              {positive ? <ArrowUpRight size={13} strokeWidth={2.6} /> : <ArrowDownRight size={13} strokeWidth={2.6} />}
              {money(Math.abs(change.value))}
              <span>{percent(Math.abs(change.percent))}</span>
              <span style={{ color: WC.textTertiary }}>{range}</span>
            </span>
          </div>
          {/* snapshotFreshness */}
          <div style={{ display: 'grid', gap: 5, justifyItems: 'end', flexShrink: 0 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: '50%',
                  background: WC.warning,
                  boxShadow: `0 0 4px ${WC.warning}bf`,
                }}
              />
              <span style={{ fontSize: TEXT.caption2, fontWeight: 600, color: 'rgba(255,255,255,0.66)' }}>
                {snapshotAgeDays}d ago
              </span>
            </span>
            <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>5 Jun 2026</span>
          </div>
        </div>

        <Segmented options={RANGES} value={range} onChange={setRange} label="Net worth range" />

        {privacy ? (
          /* MobilePrivacyChartCover */
          <div
            style={{
              height: 205,
              display: 'grid',
              placeItems: 'center',
              gap: 9,
              borderRadius: 15,
              background: 'rgba(0,0,0,0.14)',
              border: '1px solid rgba(255,255,255,0.05)',
              textAlign: 'center',
              padding: 16,
            }}
          >
            {/* Of the four cover strings only "Cash-flow chart concealed" is in
                strings.ts; the rest are in the app's catalogue but not in the
                extractor's key list, so `t` hands back the English until it is. */}
            <div style={{ display: 'grid', gap: 9, justifyItems: 'center' }}>
              <EyeSlash />
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, color: WC.textSecondary }}>
                {t('Net-worth history concealed', lang)}
              </span>
              <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>
                {t('Turn off Privacy Mode to reveal values and movement.', lang)}
              </span>
            </div>
          </div>
        ) : (
          <div style={{ height: 205 }}>
            <Trail values={points.map((p) => p.value)} height={205} showDots={points.length <= 32} label="Net-worth history" />
          </div>
        )}
      </FinanceCard>

      {/* --- Position -------------------------------------------------- */}
      <div style={{ display: 'grid', gap: 12 }}>
        <SectionHeading title={t('Position', lang)} subtitle={t('Balances derived from your activity and holdings', lang)} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <MetricCard
            title={t('Recorded Cash', lang)}
            value={money(totals.cash)}
            icon={<Banknote size={15} strokeWidth={2.4} />}
            detail={t('Income less expenses', lang)}
          />
          {/*
            The app's counts are catalogue plurals — "%lld positions",
            "%lld holdings", "%lld liabilities" (DashboardView.swift:337,350,368)
            — and none of those keys is in strings.ts, so `t` would fall back to
            English under every other language. Each count pairs with the nearest
            noun the catalogue does ship instead. Crypto has no standalone noun
            for "holdings", so it borrows Positions: the same count of the same
            kind of thing.
          */}
          <MetricCard
            title={t('Investments', lang)}
            value={money(totals.investments)}
            icon={<TrendingUp size={15} strokeWidth={2.4} />}
            accent="#64d2ff"
            detail={`${holdings.length} ${t('Positions', lang)}`}
          />
          <MetricCard
            title={t('Crypto', lang)}
            value={money(totals.crypto)}
            icon={<Bitcoin size={15} strokeWidth={2.4} />}
            accent={WC.warning}
            detail={`${crypto.length} ${t('Positions', lang)}`}
          />
          <MetricCard
            title={t('Total Assets', lang)}
            value={money(totals.assets)}
            icon={<Landmark size={15} strokeWidth={2.4} />}
            accent="#5e5ce6"
            detail={t('Across every asset', lang)}
          />
          <MetricCard
            title={t('Liabilities', lang)}
            value={money(totals.debt)}
            icon={<CreditCard size={15} strokeWidth={2.4} />}
            accent={WC.destructive}
            detail={`${liabilities.length} ${t('Liabilities', lang)}`}
          />
          <MetricCard
            title={t('Net Savings', lang)}
            value={money(currentMonth.income - currentMonth.expenses)}
            icon={<ArrowDownToLine size={15} strokeWidth={2.4} />}
            detail={wideMonth(lang)}
          />
        </div>
      </div>

      {/* --- Cash flow -------------------------------------------------- */}
      <FinanceCard style={{ display: 'grid', gap: 18 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <SectionHeading title={t('Cash Flow', lang)} subtitle={t('Income and expenses by month', lang)} />
          </div>
          <Segmented options={CASH_FLOW_RANGES} value={cashFlowRange} onChange={setCashFlowRange} label="Cash-flow range" compact />
        </div>
        {privacy ? (
          <div
            style={{
              height: 210,
              display: 'grid',
              placeItems: 'center',
              borderRadius: 15,
              background: 'rgba(0,0,0,0.14)',
              border: '1px solid rgba(255,255,255,0.05)',
              padding: 16,
              textAlign: 'center',
            }}
          >
            <div style={{ display: 'grid', gap: 9, justifyItems: 'center' }}>
              <EyeSlash />
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, color: WC.textSecondary }}>
                {t('Cash-flow chart concealed', lang)}
              </span>
              <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>
                {t('Monthly amounts and proportions are hidden.', lang)}
              </span>
            </div>
          </div>
        ) : (
          <div>
            <Bars data={months} height={210} label="Income and expenses by month" />
            <BarLabels data={months} />
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 18 }}>
          <Legend color={WC.primary} label={t('Income', lang)} value={money(flow.income)} />
          <Legend color={WC.destructive} label={t('Expenses', lang)} value={money(flow.expenses)} />
          <span style={{ flex: 1 }} />
          {/*
            The trailing "{range} NET" readout (DashboardView.swift:459-467). The
            catalogue key is "%@ NET"; it is not in strings.ts yet, so `t` falls
            back to it and the label reads in English until the key is added to
            the extractor's list.
          */}
          <div style={{ display: 'grid', gap: 3, justifyItems: 'end', textAlign: 'end', flexShrink: 0 }}>
            <span style={{ fontSize: TEXT.caption2, fontWeight: 700, letterSpacing: '1px', color: WC.textFaint }}>
              {fmt(t('%@ NET', lang), cashFlowRange)}
            </span>
            <span
              style={{
                fontSize: TEXT.caption,
                fontWeight: 700,
                fontVariantNumeric: 'tabular-nums',
                color: flow.net >= 0 ? WC.primary : WC.destructive,
              }}
            >
              {money(flow.net)}
            </span>
          </div>
        </div>
      </FinanceCard>

      {/* --- Asset allocation ------------------------------------------- */}
      <AllocationCard
        title={t('Asset Allocation', lang)}
        subtitle={t('How the portfolio is distributed', lang)}
        slices={assetAllocation().map((slice, i) => ({ ...slice, color: CHART_PALETTE[i % CHART_PALETTE.length] }))}
      />

      {/* --- Top expenses ------------------------------------------------ */}
      <FinanceCard style={{ display: 'grid', gap: 18 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <SectionHeading
              title={t('Top Expense Categories', lang)}
              subtitle={t('Where recorded spending is concentrated', lang)}
            />
          </div>
          <MenuPicker
            label={t('Period', lang)}
            value={expensePeriod}
            onChange={setExpensePeriod}
            options={ANALYTICS_PERIODS.map((period) => ({ value: period.value, title: t(period.key, lang) }))}
          />
        </div>
        <div style={{ display: 'grid', gap: 15 }}>
          {categories.slice(0, 5).map((expense, i) => {
            const share = expenseTotal > 0 ? (expense.value / expenseTotal) * 100 : 0;
            return (
              <div key={expense.name} style={{ display: 'grid', gap: 8 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                  <span
                    style={{
                      width: 17,
                      flexShrink: 0,
                      fontSize: TEXT.caption2,
                      fontWeight: 700,
                      fontVariantNumeric: 'tabular-nums',
                      color: WC.textFaint,
                    }}
                  >
                    {i + 1}
                  </span>
                  <span
                    style={{
                      fontSize: TEXT.subheadline,
                      fontWeight: 500,
                      color: 'rgba(255,255,255,0.8)',
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
                      fontSize: TEXT.subheadline,
                      fontWeight: 600,
                      fontVariantNumeric: 'tabular-nums',
                      color: WC.textPrimary,
                    }}
                  >
                    {money(expense.value)}
                  </span>
                  <span
                    style={{
                      width: 44,
                      flexShrink: 0,
                      textAlign: 'end',
                      fontSize: TEXT.caption,
                      fontWeight: 500,
                      fontVariantNumeric: 'tabular-nums',
                      color: WC.textTertiary,
                    }}
                  >
                    {percent(share)}
                  </span>
                </div>
                {/* Capsule over Capsule, 5pt tall. One gradient for every row — the
                    rank is the ordering, not the hue. */}
                <div style={{ height: 5, borderRadius: 2.5, background: 'rgba(255,255,255,0.06)', overflow: 'hidden' }}>
                  <div
                    style={{
                      // Privacy Mode collapses the bar to nothing
                      // (DashboardView.swift:547): the length *is* the share, so
                      // leaving it drawn would publish the composition the
                      // redacted numbers above it are hiding.
                      width: privacy ? 0 : `${Math.max(0, Math.min(share, 100))}%`,
                      height: '100%',
                      borderRadius: 2.5,
                      background: `linear-gradient(${rtl ? 'to left' : 'to right'}, ${WC.warning}, ${WC.destructive}d1)`,
                    }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </FinanceCard>

      {/* --- Recent activity --------------------------------------------- */}
      <FinanceCard style={{ display: 'grid', gap: 16 }}>
        <SectionHeading title={t('Recent Activity', lang)} subtitle={t('Your latest recorded cash movements', lang)} />
        <div style={{ display: 'grid', gap: 10 }}>
          {recentActivity.map((activity) => {
            const income = activity.kind === 'income';
            const tint = income ? WC.primary : WC.destructive;
            return (
              <InsetRow key={activity.id}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <span
                    style={{
                      width: 32,
                      height: 32,
                      display: 'grid',
                      placeItems: 'center',
                      borderRadius: 9,
                      background: `${tint}1c`,
                      color: tint,
                      flexShrink: 0,
                    }}
                  >
                    {income ? <ArrowDownLeft size={12} strokeWidth={2.8} /> : <ArrowUpRight size={12} strokeWidth={2.8} />}
                  </span>
                  <div style={{ display: 'grid', gap: 3, flex: '0 1 auto', minWidth: 0 }}>
                    <span
                      style={{
                        fontSize: TEXT.subheadline,
                        fontWeight: 500,
                        color: 'rgba(255,255,255,0.84)',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                      }}
                    >
                      {t(activity.category, lang)}
                    </span>
                    {/* VIEW-09 puts the row's own note here and moves the date to the
                        trailing column, so two same-day rows in one category stay
                        distinguishable. data.ts rows carry no note, which is the
                        empty-description case: the app falls back to the type. */}
                    <span
                      style={{
                        fontSize: TEXT.caption2,
                        color: WC.textFaint,
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                      }}
                    >
                      {t(income ? 'Income' : 'Expense', lang)}
                    </span>
                  </div>
                  <span style={{ flex: '1 1 auto', minWidth: 8 }} />
                  <div style={{ display: 'grid', gap: 3, justifyItems: 'end', textAlign: 'end', flexShrink: 0 }}>
                    <span
                      style={{
                        fontSize: TEXT.subheadline,
                        fontWeight: 600,
                        fontVariantNumeric: 'tabular-nums',
                        // Only income is tinted. An expense is white at .82 — red is
                        // reserved for the glyph, because a red *amount* on a ledger
                        // row reads as a loss rather than as an outflow.
                        color: income ? WC.primary : 'rgba(255,255,255,0.82)',
                      }}
                    >
                      {/* signedAmount (DashboardView.swift:633-638): the sign is part
                          of the amount, and privacy replaces the whole thing rather
                          than signing a redaction token. U+2212, as the Swift has. */}
                      {privacy ? money(activity.amount) : `${income ? '+' : '−'}${money(Math.abs(activity.amount))}`}
                    </span>
                    <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>{activity.day}</span>
                  </div>
                </div>
              </InsetRow>
            );
          })}
        </div>
      </FinanceCard>
    </div>
  );
}

/**
 * cashFlowLegend (DashboardView.swift:473-487) — an 8×24 rounded bar in the
 * series colour beside a two-line caption. `color.gradient` shades the swatch
 * into a darker version of itself; charts.tsx resolves that the same way, by
 * easing the same hue toward the surface.
 */
function Legend({ color, label, value }: { color: string; label: string; value: string }) {
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span
        style={{
          width: 8,
          height: 24,
          flexShrink: 0,
          borderRadius: 3,
          background: `linear-gradient(180deg, ${color}, ${color}b8)`,
        }}
      />
      <span style={{ display: 'grid', gap: 2 }}>
        <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>{label}</span>
        <span
          style={{
            fontSize: TEXT.caption,
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

/**
 * `.pickerStyle(.menu)` with the app's green tint — a label and chevron that
 * drops a translucent list. The app uses a menu rather than a segmented control
 * here because the period titles are far too long for five segments on a phone.
 */
function MenuPicker<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: NoInfer<T>;
  options: { value: T; title: string }[];
  onChange: (next: NoInfer<T>) => void;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const current = options.find((option) => option.value === value);

  return (
    <div style={{ position: 'relative', flexShrink: 0 }}>
      <button
        type="button"
        onClick={() => setOpen((isOpen) => !isOpen)}
        aria-label={label}
        aria-expanded={open}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 4,
          padding: 0,
          border: 'none',
          background: 'transparent',
          cursor: 'pointer',
          color: WC.primary,
          fontSize: TEXT.subheadline,
          fontWeight: 500,
          whiteSpace: 'nowrap',
        }}
      >
        {current?.title}
        <ChevronDown size={13} strokeWidth={2.6} />
      </button>
      {open && (
        /* The floating panel a SwiftUI Menu drops. */
        <div
          style={{
            position: 'absolute',
            top: 'calc(100% + 8px)',
            insetInlineEnd: 0,
            zIndex: 4,
            minWidth: 180,
            padding: 5,
            display: 'grid',
            gap: 1,
            borderRadius: 14,
            background: 'rgba(30,34,44,0.94)',
            backdropFilter: 'blur(24px) saturate(160%)',
            WebkitBackdropFilter: 'blur(24px) saturate(160%)',
            border: '1px solid rgba(255,255,255,0.09)',
            boxShadow: '0 14px 32px rgba(0,0,0,0.45)',
          }}
        >
          {options.map((option) => (
            <button
              key={option.value}
              type="button"
              aria-current={option.value === value ? 'true' : undefined}
              onClick={() => {
                onChange(option.value);
                setOpen(false);
              }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                width: '100%',
                padding: '9px 10px',
                border: 'none',
                borderRadius: 10,
                cursor: 'pointer',
                textAlign: 'start',
                background: 'transparent',
                color: WC.textPrimary,
                font: 'inherit',
                fontSize: TEXT.subheadline,
              }}
            >
              <span style={{ flex: 1, minWidth: 0 }}>{option.title}</span>
              {option.value === value && <Check size={14} strokeWidth={2.6} color={WC.primary} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** SF Symbol "eye.slash.fill" — MobilePrivacyChartCover's glyph. */
function EyeSlash() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={WC.primary} strokeOpacity={0.76} strokeWidth="1.8" strokeLinecap="round">
      <path d="M10.7 5.1A9.6 9.6 0 0 1 12 5c5 0 9 5 9 7a10.6 10.6 0 0 1-2.2 3M6.3 6.4C3.9 7.9 3 10.3 3 12c0 2 4 7 9 7 1.8 0 3.4-.6 4.7-1.5" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2M3 3l18 18" />
    </svg>
  );
}
