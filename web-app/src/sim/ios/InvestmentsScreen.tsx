import { useState } from 'react';
import { ArrowDownRight, ArrowUpRight, Banknote, CircleCheck, Layers3, LineChart, TrendingUp } from 'lucide-react';
import { CHART_GEOGRAPHY_PALETTE, CHART_PALETTE, CHART_TYPE_PALETTE, TEXT, WC } from '../tokens';
import { AllocationCard, FinanceCard, InsetRow, MetricCard, PageHeader, PrimaryActionButton, SectionHeading } from '../ui';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import { allocationByGeography, allocationBySector, allocationByType, holdingValue, holdings, totals } from '../data';

/**
 * A port of Sources/iOS/Views/InvestmentsView.swift.
 *
 * Section order, the Overview/Positions segmented picker, metric titles, accents
 * and SF Symbol choices come from that file. VIEW-02 (the Type and Geography
 * rings, single-column on iPhone) and VIEW-07 (the Performance and Status cards)
 * are both reproduced, so this screen shows what the shipping iPhone build shows
 * rather than what the older App Store screenshot captured.
 */

/** AppSettings.redactionToken — inlined the same way AllocationCard inlines it. */
const REDACTION = '••••';

/** `.headline.monospaced()` / `.caption.monospaced()` on the position rows. */
const MONO = `ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace`;

/**
 * Every position carries its own `updatedAt` in the app; the shared demo dataset
 * has no per-position timestamp, so the snapshot date the Dashboard already
 * prints stands in for `latestUpdate` and for each row's "Updated …".
 */
const UPDATED_ON = '5 Jun 2026';

const TAB_KEYS = ['Overview', 'Positions'] as const;
type InvestmentsTab = (typeof TAB_KEYS)[number];

export function InvestmentsScreen() {
  const { money, percent, lang, privacy } = useSim();
  const [tab, setTab] = useState<InvestmentsTab>('Overview');

  // `summary` — total, cost basis and gain all derive from the positions, exactly
  // as calculateTotals + the reduce over costBasis do in Swift.
  const gain = totals.investmentsPL;
  const gainPositive = gain >= 0;
  const performance = totals.investmentsPLPercent;
  const performancePositive = performance >= 0;
  const sectorCount = new Set(holdings.map((h) => h.sector).filter((s) => s !== '')).size;
  const sectorCountLabel = privacy ? REDACTION : `${sectorCount}`;

  /**
   * Three of this screen's catalogue entries are format strings rather than whole
   * sentences — `Status • %@ Sectors`, `%@%% performance`, `Updated %@` — and Swift
   * resolves each through the catalogue before substituting. strings.ts does not
   * harvest them yet, so `t()` hands the format back unchanged and the substitution
   * still yields the English sentence; adding the keys to extract-strings.py is all
   * it takes for them to localize, including French's reordered "%@ mis à jour".
   */
  const fill = (key: string, value: string, placeholder = '%@') => t(key, lang).replace(placeholder, value);

  const tabLabels = TAB_KEYS.map((key) => t(key, lang));

  return (
    <div style={{ display: 'grid', gap: 20, padding: '0 16px 28px', alignContent: 'start' }}>
      <PageHeader
        title={t('Investments', lang)}
        subtitle={t('Follow positions, allocation, and performance.', lang)}
        trailing={<PrimaryActionButton label={t('Add Investment', lang)} />}
      />

      {/* investmentsTabPicker */}
      <Segmented
        options={tabLabels}
        value={t(tab, lang)}
        onChange={(next) => setTab(TAB_KEYS[tabLabels.indexOf(next)] ?? 'Overview')}
        label="Investments view"
      />

      {tab === 'Overview' ? (
        <>
          {/* --- summary ---------------------------------------------------- */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <MetricCard
              title={t('Portfolio Value', lang)}
              value={money(totals.investments)}
              icon={<TrendingUp size={15} strokeWidth={2.4} />}
              accent="#64d2ff"
              detail={t('Current market value', lang)}
            />
            <MetricCard
              title={t('Positions', lang)}
              value={privacy ? REDACTION : `${holdings.length}`}
              icon={<Layers3 size={15} strokeWidth={2.4} />}
              detail={t('Stocks, ETFs, and more', lang)}
            />
            <MetricCard
              title={t('Cost Basis', lang)}
              value={money(totals.investmentsCost)}
              icon={<Banknote size={15} strokeWidth={2.4} />}
              detail={t('Capital invested', lang)}
            />
            <MetricCard
              title={t('Profit / Loss', lang)}
              value={money(gain)}
              icon={gainPositive ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />}
              accent={gainPositive ? WC.primary : WC.destructive}
              detail={privacy ? t('Performance hidden', lang) : fill('%@%% performance', percent(performance), '%@%%')}
            />

            {/* VIEW-07: Performance % + Status (last-update recency + distinct-sector count). */}
            {!privacy && (
              <MetricCard
                title={t('Performance', lang)}
                value={percent(performance)}
                icon={
                  performancePositive ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />
                }
                accent={performancePositive ? WC.primary : WC.destructive}
              />
            )}
            <MetricCard
              title={fill('Status • %@ Sectors', sectorCountLabel)}
              value={UPDATED_ON}
              icon={<CircleCheck size={15} strokeWidth={2.4} />}
            />
          </div>

          <AllocationCard
            title={t('Allocation by Sector', lang)}
            subtitle={t('How the portfolio is distributed', lang)}
            slices={allocationBySector().map((slice, i) => ({ ...slice, color: CHART_PALETTE[i % CHART_PALETTE.length] }))}
          />
          {/* VIEW-02: match macOS, which also breaks the portfolio down by type and
              geography. Each ring has its own ramp — see ColorPalette. */}
          <AllocationCard
            title={t('Allocation by Type', lang)}
            subtitle={t('How the portfolio is distributed', lang)}
            slices={allocationByType().map((slice, i) => ({
              // The type ring labels its wedges with InvestmentType.localizedTitle,
              // unlike the free-text sector and geography rings.
              name: t(slice.name, lang),
              value: slice.value,
              color: CHART_TYPE_PALETTE[i % CHART_TYPE_PALETTE.length],
            }))}
          />
          <AllocationCard
            title={t('Allocation by Geography', lang)}
            subtitle={t('How the portfolio is distributed', lang)}
            slices={allocationByGeography().map((slice, i) => ({
              ...slice,
              color: CHART_GEOGRAPHY_PALETTE[i % CHART_GEOGRAPHY_PALETTE.length],
            }))}
          />
        </>
      ) : (
        /* --- investmentList ------------------------------------------------ */
        <FinanceCard style={{ display: 'grid', gap: 14 }}>
          <SectionHeading title={t('Positions', lang)} subtitle={t('Tap a position to edit its details', lang)} />
          {holdings.length === 0 ? (
            <EmptyState title={t('No investments yet', lang)} />
          ) : (
            <div style={{ display: 'grid', gap: 12 }}>
              {[...holdings]
                .sort((a, b) => holdingValue(b) - holdingValue(a))
                .map((holding) => {
                  const value = holdingValue(holding);
                  const delta = value - holding.costBasis;
                  // M10: divide by the magnitude of the cost basis so a gain keeps its sign.
                  const deltaPercent = holding.costBasis !== 0 ? (delta / Math.abs(holding.costBasis)) * 100 : 0;
                  const deltaColor = delta >= 0 ? WC.primary : WC.destructive;
                  return (
                    <InsetRow key={holding.symbol}>
                      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                        <span
                          style={{
                            width: 38,
                            height: 38,
                            flexShrink: 0,
                            display: 'grid',
                            placeItems: 'center',
                            borderRadius: 11,
                            background: 'rgba(100,210,255,0.11)',
                            color: '#64d2ff',
                            fontFamily: MONO,
                            fontSize: TEXT.caption,
                            fontWeight: 700,
                          }}
                        >
                          {holding.symbol.slice(0, 2)}
                        </span>

                        <div style={{ display: 'grid', gap: 6, flex: 1, minWidth: 0 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                            <span
                              style={{
                                fontFamily: MONO,
                                fontSize: TEXT.headline,
                                fontWeight: 600,
                                color: WC.textPrimary,
                                overflow: 'hidden',
                                textOverflow: 'ellipsis',
                                whiteSpace: 'nowrap',
                              }}
                            >
                              {holding.symbol}
                            </span>
                            <span
                              style={{
                                flexShrink: 0,
                                padding: '3px 7px',
                                borderRadius: 999,
                                background: 'rgba(31,219,153,0.11)',
                                color: WC.primary,
                                fontSize: TEXT.caption2,
                                fontWeight: 700,
                                textTransform: 'uppercase',
                              }}
                            >
                              {t(holding.type, lang)}
                            </span>
                          </div>
                          <span
                            style={{
                              fontSize: TEXT.subheadline,
                              color: WC.textSecondary,
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {holding.name}
                          </span>
                          <span
                            style={{
                              fontSize: TEXT.caption,
                              color: WC.textSecondary,
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {/* privateNumber(_:fractionDigits: QuantityPrecision.investment) */}
                            {privacy
                              ? REDACTION
                              : new Intl.NumberFormat(lang, { maximumFractionDigits: 6 }).format(holding.quantity)}
                            {' • '}
                            {holding.sector}
                          </span>
                        </div>

                        <div style={{ display: 'grid', gap: 4, justifyItems: 'end', flexShrink: 0 }}>
                          <span
                            style={{
                              fontSize: TEXT.subheadline,
                              fontWeight: 700,
                              fontVariantNumeric: 'tabular-nums',
                              color: WC.textPrimary,
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {money(value)}
                          </span>
                          {/* ValueDelta — "<amount> (<percent>%)", tinted by sign. */}
                          <span
                            style={{
                              fontSize: TEXT.subheadline,
                              fontWeight: 600,
                              fontVariantNumeric: 'tabular-nums',
                              color: deltaColor,
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {money(delta)} ({percent(deltaPercent)})
                          </span>
                          <span style={{ fontSize: TEXT.caption2, color: WC.textSecondary, whiteSpace: 'nowrap' }}>
                            {fill('Updated %@', UPDATED_ON)}
                          </span>
                        </div>
                      </div>
                    </InsetRow>
                  );
                })}
            </div>
          )}
        </FinanceCard>
      )}
    </div>
  );
}

/** EmptyState — the 46pt tinted glyph tile over a centred caption. */
function EmptyState({ title }: { title: string }) {
  return (
    <div style={{ display: 'grid', gap: 10, justifyItems: 'center', padding: '28px 0' }}>
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
        <LineChart size={22} strokeWidth={2} />
      </span>
      <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary, textAlign: 'center' }}>{title}</span>
    </div>
  );
}
