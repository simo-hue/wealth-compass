import { useEffect, useRef, useState } from 'react';
import { ArrowDownRight, ArrowUpRight, Banknote, CircleCheck, Hash, Plus, TrendingUp } from 'lucide-react';
import { CHART_GEOGRAPHY_PALETTE, CHART_PALETTE, CHART_TYPE_PALETTE, TEXT, WC } from '../tokens';
import { AllocationCard, FinanceCard, MetricCard } from '../ui';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import {
  type Holding,
  allocationByGeography,
  allocationBySector,
  allocationByType,
  holdingValue,
  holdings,
  totals,
} from '../data';

/**
 * A port of Sources/macOS/Views/MacInvestmentsView.swift.
 *
 * The screen is two tabs behind one MacSelectorIsland: Overview (summary cards,
 * the three allocation rings, Top Holdings) and Positions (every holding as a
 * card). Both tabs render the same `investmentCard`, which is why it lives here
 * as one component rather than being inlined twice.
 *
 * Unlike the Dashboard there is no privacy chart cover anywhere in this view —
 * the rings stay drawn and redact their readouts through `money()`/`percent()`,
 * and privacy mode instead drops the Performance card and blanks the counts, as
 * `summaryCards(width:)` and `privateCount(_:)` do in Swift.
 */

/**
 * `investment.updatedAt`, which the demo dataset does not carry. The Mac
 * Dashboard already stamps the same instant on its snapshot row, and it is the
 * one in the App Store screenshot.
 */
const LAST_UPDATED = '5 Jun 2026 at 23:03';

/** AppSettings.redactionToken. */
const REDACTION = '••••';

type Tab = 'Overview' | 'Positions';
const TABS: Tab[] = ['Overview', 'Positions'];

export function MacInvestments() {
  const { money, percent, lang, privacy } = useSim();
  const [tab, setTab] = useState<Tab>('Overview');

  // `finance.data.investments.sorted { $0.currentValue > $1.currentValue }` — the
  // ordering both tabs use (VIEW-10 aligned the Positions table to it).
  const ranked = [...holdings].sort((a, b) => holdingValue(b) - holdingValue(a));
  const topHoldings = ranked.slice(0, 5);

  const gain = totals.investmentsPL;
  const gainPositive = gain >= 0;
  const performance = totals.investmentsPLPercent;
  const sectorCount = new Set(holdings.map((h) => h.sector).filter((s) => s.trim().length > 0)).size;
  const privateCount = (count: number) => (privacy ? REDACTION : String(count));

  // fillingFlexibleColumns(availableWidth:itemCount:) caps the column count at the
  // number of cards so a part-filled last row never leaves an empty trailing slot.
  // At this pane width its 190pt minimum resolves to 5 columns, so the shipping app
  // wraps the sixth card; app_store_images/MacOS/03.png is a wider window with all
  // six in one row, which is what this renders — as MacCashFlow's six cards do.
  // Privacy mode removes Performance, so the row is 6 wide or 5 wide.
  const summaryColumns = privacy ? 5 : 6;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      {/* The island is centred in the pane between two equal spacers. The window
          simulation has no toolbar bar, so the `.toolbar` primaryAction takes the
          trailing slot of this row — where MacCashFlow's Add menu sits. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '16px 24px' }}>
        <span style={{ flex: 1 }} />
        <SelectorIsland options={TABS} value={tab} onChange={setTab} label={t('Investments', lang)} />
        <div style={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'flex-end' }}>
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              padding: '7px 14px',
              borderRadius: 20,
              background: WC.primary,
              color: 'rgba(0,0,0,0.85)',
              fontSize: TEXT.footnote,
              fontWeight: 600,
              whiteSpace: 'nowrap',
              flexShrink: 0,
            }}
          >
            <Plus size={13} strokeWidth={3} /> {t('New Investment', lang)}
          </span>
        </div>
      </div>

      {tab === 'Overview' ? (
        <div style={{ display: 'grid', gap: 24, padding: 24, alignContent: 'start' }}>
          {/* summaryCards(width:) */}
          <div style={{ display: 'grid', gridTemplateColumns: `repeat(${summaryColumns}, 1fr)`, gap: 16 }}>
            <MetricCard
              title={t('Portfolio Value', lang)}
              value={money(totals.investments)}
              icon={<TrendingUp size={15} strokeWidth={2.4} />}
              accent="#0a84ff"
            />
            <MetricCard title={t('Positions', lang)} value={privateCount(holdings.length)} icon={<Hash size={15} strokeWidth={2.4} />} />
            <MetricCard
              title={t('Cost Basis', lang)}
              value={money(totals.investmentsCost)}
              icon={<Banknote size={15} strokeWidth={2.4} />}
            />
            <MetricCard
              title={t('Profit / Loss', lang)}
              value={money(gain)}
              icon={gainPositive ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />}
              accent={gainPositive ? WC.primary : WC.destructive}
            />
            {!privacy && (
              <MetricCard
                title={t('Performance', lang)}
                value={percent(performance)}
                icon={performance >= 0 ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />}
                accent={performance >= 0 ? WC.primary : WC.destructive}
              />
            )}
            {/* L19: the title is composed and already resolved, so it is passed verbatim. */}
            <StatusCard title={`Status • ${privateCount(sectorCount)} Sectors`} value={LAST_UPDATED} />
          </div>

          {/* L24: three flexible columns at >= 960pt of pane width — the detail pane
              here is 1220pt, so this is the branch that renders. */}
          {/* The cards stretch to the row height rather than sizing to their legends:
              a two-slice ring ends level with a three-slice one, as in 03.png. */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>
            <AllocationCard
              title={t('Allocation by Sector', lang)}
              subtitle={t('How the portfolio is distributed', lang)}
              slices={allocationBySector().map((slice, i) => ({ ...slice, color: CHART_PALETTE[i % CHART_PALETTE.length] }))}
              size={190}
            />
            <AllocationCard
              title={t('Allocation by Type', lang)}
              subtitle={t('How the portfolio is distributed', lang)}
              slices={allocationByType().map((slice, i) => ({
                // investmentTypeAllocation names its slices from `type.localizedTitle`,
                // unlike the sector and geography rings whose names are free text.
                name: t(slice.name, lang),
                value: slice.value,
                color: CHART_TYPE_PALETTE[i % CHART_TYPE_PALETTE.length],
              }))}
              size={190}
            />
            <AllocationCard
              title={t('Allocation by Geography', lang)}
              subtitle={t('How the portfolio is distributed', lang)}
              slices={allocationByGeography().map((slice, i) => ({
                ...slice,
                color: CHART_GEOGRAPHY_PALETTE[i % CHART_GEOGRAPHY_PALETTE.length],
              }))}
              size={190}
            />
          </div>

          {/* topHoldingsSection */}
          <div style={{ display: 'grid', gap: 16, paddingTop: 16, alignContent: 'start' }}>
            <span style={{ fontSize: TEXT.title2, fontWeight: 600, color: WC.textPrimary }}>{t('Top Holdings', lang)}</span>
            {topHoldings.length === 0 ? (
              <NoInvestments />
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: 16 }}>
                {topHoldings.map((holding) => (
                  <HoldingCard key={holding.symbol} holding={holding} />
                ))}
              </div>
            )}
          </div>
        </div>
      ) : (
        /* investmentTable — the same cards, every position, at 32pt padding. */
        <div style={{ padding: 32 }}>
          {ranked.length === 0 ? (
            <NoInvestments />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: 16 }}>
              {ranked.map((holding) => (
                <HoldingCard key={holding.symbol} holding={holding} />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * The last summary card. It is a MetricCard in every respect except the size of
 * its value: an abbreviated date + time is roughly half again as wide as the
 * 20pt title3 slot, so SwiftUI's `minimumScaleFactor(0.62)` shrinks it to fit,
 * while ui.tsx's MetricCard ellipsises instead. Rather than change the shared
 * card for one caller, the resolved size is applied here.
 */
function StatusCard({ title, value }: { title: string; value: string }) {
  const accent = WC.primary;
  return (
    <FinanceCard style={{ display: 'grid', gap: 15, alignContent: 'start' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
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
          <CircleCheck size={15} strokeWidth={2.4} />
        </span>
        <span
          style={{
            width: 5,
            height: 5,
            borderRadius: '50%',
            background: accent,
            opacity: 0.72,
            boxShadow: `0 0 4px ${accent}a6`,
            marginTop: 4,
          }}
        />
      </div>
      <div style={{ display: 'grid', gap: 4, minWidth: 0 }}>
        <span
          style={{
            fontSize: TEXT.caption,
            fontWeight: 500,
            color: WC.textTertiary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {title}
        </span>
        <span
          style={{
            fontSize: TEXT.footnote,
            fontWeight: 700,
            fontVariantNumeric: 'tabular-nums',
            color: WC.textPrimary,
            whiteSpace: 'nowrap',
          }}
        >
          {value}
        </span>
      </div>
    </FinanceCard>
  );
}

/** `investmentCard(for:)`. */
function HoldingCard({ holding }: { holding: Holding }) {
  const { money, percent, lang, privacy } = useSim();
  const value = holdingValue(holding);
  const gain = Math.round((value - holding.costBasis) * 100) / 100;
  // Investment.gainLossPercent — M10: guard only a zero denominator and divide by the
  // cost-basis magnitude, so a gain against a negative basis keeps its sign.
  const gainPercent = holding.costBasis !== 0 ? (gain / Math.abs(holding.costBasis)) * 100 : 0;
  const tint = gain >= 0 ? WC.primary : WC.destructive;

  return (
    <FinanceCard style={{ display: 'grid', gap: 16, alignContent: 'start' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ display: 'grid', gap: 4, flex: 1, minWidth: 0 }}>
          <span
            style={{
              fontSize: TEXT.headline,
              fontWeight: 600,
              color: WC.textPrimary,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {holding.name}
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: TEXT.subheadline, color: WC.textSecondary }}>
            <span style={{ fontWeight: 600 }}>{holding.symbol}</span>
            <span>•</span>
            <span>{t(holding.type, lang)}</span>
          </span>
        </div>
        <div style={{ display: 'grid', gap: 4, justifyItems: 'end', flexShrink: 0 }}>
          <span style={{ fontSize: TEXT.headline, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
            {money(value)}
          </span>
          {/* ValueDelta */}
          <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: tint }}>
            {money(gain)} ({percent(gainPercent)})
          </span>
        </div>
      </div>

      <div style={{ height: 1, background: WC.border }} />

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
        <div style={{ display: 'grid', gap: 4 }}>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{t('Quantity', lang)}</span>
          <span style={{ fontSize: TEXT.subheadline, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
            {/* privateNumber(_:fractionDigits: QuantityPrecision.investment) */}
            {privacy ? REDACTION : new Intl.NumberFormat(lang, { maximumFractionDigits: 6 }).format(holding.quantity)}
          </span>
        </div>
        <div style={{ display: 'grid', gap: 4 }}>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{t('Current Price', lang)}</span>
          <span style={{ fontSize: TEXT.subheadline, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
            {money(holding.price)}
          </span>
        </div>
        <div style={{ display: 'grid', gap: 4, justifyItems: 'end' }}>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{t('Last Updated', lang)}</span>
          <span style={{ fontSize: TEXT.subheadline, color: WC.textSecondary, whiteSpace: 'nowrap' }}>{LAST_UPDATED}</span>
        </div>
      </div>
    </FinanceCard>
  );
}

/** ContentUnavailableView("No Investments", systemImage: "chart.line.uptrend.xyaxis", …). */
function NoInvestments() {
  const { lang } = useSim();
  return (
    <div style={{ display: 'grid', gap: 10, justifyItems: 'center', padding: '40px 0 28px', textAlign: 'center' }}>
      <span
        style={{
          width: 46,
          height: 46,
          display: 'grid',
          placeItems: 'center',
          borderRadius: 14,
          background: 'rgba(31,219,153,0.09)',
          color: WC.primary,
          opacity: 0.78,
        }}
      >
        <TrendingUp size={22} strokeWidth={2.2} />
      </span>
      {/* "No Investments" has no entry in the generated catalogue, so t() returns the key. */}
      <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary }}>{t('No Investments', lang)}</span>
      <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>{t('Add stocks, ETFs, bonds, or other positions.', lang)}</span>
    </div>
  );
}

/**
 * MacSelectorIsland — a capsule trough (Color(white: 0.12) under a 10% white
 * stroke) with hairline dividers between the tabs and a single highlight capsule
 * that slides between them. SwiftUI gets the slide from `matchedGeometryEffect`
 * on one shared id; here the highlight is one absolutely-positioned element whose
 * measured frame transitions, which is the same trick with the same result.
 */
function SelectorIsland<T extends string>({
  options,
  value,
  onChange,
  label,
}: {
  options: readonly T[];
  value: NoInfer<T>;
  onChange: (next: NoInfer<T>) => void;
  label: string;
}) {
  const { lang } = useSim();
  const row = useRef<HTMLDivElement>(null);
  const [pill, setPill] = useState<{ left: number; width: number } | null>(null);

  useEffect(() => {
    const node = row.current?.querySelector<HTMLElement>(`[data-tab="${value}"]`);
    if (node) setPill({ left: node.offsetLeft, width: node.offsetWidth });
  }, [value, lang]);

  const highlight = 'rgba(255,255,255,0.18)';

  return (
    <div
      ref={row}
      role="tablist"
      aria-label={label}
      style={{
        position: 'relative',
        display: 'flex',
        alignItems: 'center',
        padding: 4,
        borderRadius: 999,
        background: '#1f1f1f',
        border: '1px solid rgba(255,255,255,0.1)',
        boxShadow: '0 2px 4px rgba(0,0,0,0.2)',
      }}
    >
      {pill && (
        <span
          aria-hidden="true"
          style={{
            position: 'absolute',
            top: 4,
            bottom: 4,
            left: pill.left,
            width: pill.width,
            borderRadius: 999,
            background: highlight,
            // .spring(response: 0.3, dampingFraction: 0.7) — a touch of overshoot.
            transition: 'left 300ms cubic-bezier(0.34, 1.28, 0.64, 1), width 300ms cubic-bezier(0.34, 1.28, 0.64, 1)',
          }}
        />
      )}
      {options.map((option, index) => {
        const selected = option === value;
        return (
          <span key={option} style={{ display: 'contents' }}>
            <button
              type="button"
              role="tab"
              data-tab={option}
              aria-selected={selected}
              onClick={() => onChange(option)}
              style={{
                position: 'relative',
                padding: '6px 16px',
                border: 'none',
                borderRadius: 999,
                cursor: 'pointer',
                fontSize: 14,
                fontWeight: 500,
                whiteSpace: 'nowrap',
                color: selected ? WC.textPrimary : 'rgba(255,255,255,0.8)',
                // Until the highlight has been measured it rides on the button itself,
                // so the first paint is identical to the measured one.
                background: selected && !pill ? highlight : 'transparent',
                transition: 'color 200ms ease',
              }}
            >
              {t(option, lang)}
            </button>
            {index < options.length - 1 && (
              <span aria-hidden="true" style={{ width: 1, height: 14, margin: '0 6px', background: 'rgba(255,255,255,0.2)', flexShrink: 0 }} />
            )}
          </span>
        );
      })}
    </div>
  );
}
