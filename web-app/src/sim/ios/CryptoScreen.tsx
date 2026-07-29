import { useState } from 'react';
import { ArrowDownRight, ArrowUpRight, Banknote, Bitcoin, CircleCheck, Layers } from 'lucide-react';
import { CHART_PALETTE, TEXT, WC } from '../tokens';
import { AllocationCard, FinanceCard, InsetRow, MetricCard, PageHeader, PrimaryActionButton, SectionHeading } from '../ui';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import { type CryptoHolding, crypto, cryptoAllocation, cryptoValue, totals } from '../data';

/**
 * A port of Sources/iOS/Views/CryptoView.swift.
 *
 * Section order, the Overview/Holdings picker, the six metric cards and the
 * Top Performer / Biggest Loser leaderboard are all taken from that file. The
 * Swift screen also owns an add/edit sheet and a delete alert (`CryptoFormRoute`,
 * `holdingPendingDeletion`); a marketing simulation has nothing to submit, so the
 * tap targets are present but inert and those two flows are not ported.
 *
 * Every string below is keyed on the exact English literal from the Swift, which
 * is also its key in Localizable.xcstrings. All of them except "Overview" and
 * "How the portfolio is distributed" are still missing from the generated
 * strings.ts, so `t()` falls back to the key and they render in English for now;
 * adding them to scripts/extract-strings.py translates the screen with no change
 * here.
 */

/** CryptoTab — the two cases of the private enum at the top of CryptoView.swift. */
const CRYPTO_TABS = ['Overview', 'Holdings'] as const;
type CryptoTab = (typeof CRYPTO_TABS)[number];

/** AppSettings.redactionToken. */
const REDACTION = '••••';

/** QuantityPrecision.crypto — `fractionLength(0...8)` on the unit count. */
const QUANTITY_PRECISION = 8;

/**
 * The dataset carries no per-holding `updatedAt`, so the Status card and the
 * row captions reuse the one demo snapshot date the Dashboard already prints
 * rather than inventing a second timeline.
 */
const LAST_UPDATED = '5 Jun 2026';

/**
 * The catalogue's `%@` format strings. `t()` has no interpolation, so the token
 * is substituted here; the function replacer keeps `$&`-style sequences in the
 * substituted value literal.
 */
const fmt = (pattern: string, value: string, token = '%@') => pattern.replace(token, () => value);

/** `.font(.headline.monospaced())` on the symbol — SF Mono, with the usual fallbacks. */
const SF_MONO = `ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace`;

export function CryptoScreen() {
  const { money, percent, lang, privacy } = useSim();
  const [tab, setTab] = useState<CryptoTab>('Overview');

  // summary — total, cost basis and gain, exactly as CryptoView derives them.
  const gain = totals.cryptoPL;
  const gainPercent = totals.cryptoCost > 0 ? (gain / totals.cryptoCost) * 100 : 0;
  const up = gain >= 0;

  // Set(symbol).count over non-empty symbols, for the "Status • N Coins" title.
  const coinCount = new Set(crypto.map((c) => c.symbol).filter((s) => s.length > 0)).size;
  const coinCountLabel = privacy ? REDACTION : String(coinCount);

  // VIEW-06: the leaderboard renders only when a positive best and/or a negative
  // worst exists, so a portfolio that is uniformly up shows one card, not two.
  const ranked = [...crypto].sort((a, b) => gainLossPercent(b) - gainLossPercent(a));
  const best = ranked[0];
  const worst = ranked[ranked.length - 1];
  const hasBest = best !== undefined && gainLossPercent(best) > 0;
  const hasWorst = worst !== undefined && gainLossPercent(worst) < 0;

  const label = (key: CryptoTab) => t(key, lang);

  return (
    <div style={{ display: 'grid', gap: 20, padding: '0 16px 28px', alignContent: 'start' }}>
      <PageHeader
        title={t('Crypto assets', lang)}
        subtitle={t('Track holdings, allocation, and performance.', lang)}
        trailing={<PrimaryActionButton label={t('Add Crypto Holding', lang)} />}
      />

      {/* cryptoTabPicker — Picker("Crypto view") in .segmented style. The state is
          the English case name; the labels are resolved per render so switching
          language doesn't strand the selection on a stale translation. */}
      <Segmented
        options={CRYPTO_TABS.map(label)}
        value={label(tab)}
        onChange={(next) => setTab(next === label('Overview') ? 'Overview' : 'Holdings')}
        label={t('Crypto view', lang)}
      />

      {tab === 'Overview' ? (
        <>
          {/* --- summary ------------------------------------------------- */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <MetricCard
              title={t('Crypto Value', lang)}
              value={money(totals.crypto)}
              icon={<Bitcoin size={15} strokeWidth={2.4} />}
              accent={WC.warning}
              detail={t('Current market value', lang)}
            />
            <MetricCard
              title={t('Holdings', lang)}
              value={privacy ? REDACTION : String(crypto.length)}
              icon={<Layers size={15} strokeWidth={2.4} />}
              detail={t('Tracked assets', lang)}
            />
            <MetricCard
              title={t('Cost Basis', lang)}
              value={money(totals.cryptoCost)}
              icon={<Banknote size={15} strokeWidth={2.4} />}
              detail={t('Capital invested', lang)}
            />
            <MetricCard
              title={t('Profit / Loss', lang)}
              value={money(gain)}
              icon={up ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />}
              accent={up ? WC.primary : WC.destructive}
              detail={
                privacy
                  ? t('Performance hidden', lang)
                  : // The catalogue key is "%@%% performance" — `%@` is the bare number and `%%`
                    // the literal sign. percent() already carries the sign, so the adjacent pair
                    // is replaced as one token (every shipped translation keeps them adjacent).
                    fmt(t('%@%% performance', lang), percent(gainPercent), '%@%%')
              }
            />

            {/* VIEW-07: Performance % + Status (last-update recency + distinct-coin
                count) cards, matching macOS. The Performance card is dropped in
                Privacy Mode rather than redacted — its whole value is the number. */}
            {!privacy && (
              <MetricCard
                title={t('Performance', lang)}
                value={percent(gainPercent)}
                icon={
                  gainPercent >= 0 ? <ArrowUpRight size={15} strokeWidth={2.4} /> : <ArrowDownRight size={15} strokeWidth={2.4} />
                }
                accent={gainPercent >= 0 ? WC.primary : WC.destructive}
              />
            )}
            <MetricCard
              title={fmt(t('Status • %@ Coins', lang), coinCountLabel)}
              value={LAST_UPDATED}
              icon={<CircleCheck size={15} strokeWidth={2.4} />}
            />
          </div>

          {/* --- performanceSection --------------------------------------- */}
          {(hasBest || hasWorst) && (
            <FinanceCard style={{ display: 'grid', gap: 16 }}>
              {hasBest && <PerformanceRow title={t('Top Performer', lang)} holding={best} />}
              {hasBest && hasWorst && <div style={{ height: 1, background: WC.border }} />}
              {hasWorst && <PerformanceRow title={t('Biggest Loser', lang)} holding={worst} />}
            </FinanceCard>
          )}

          {/* --- AllocationChart -------------------------------------------
              AnalyticsEngine.cryptoAllocation picks ColorPalette.chart by the
              holding's index in `data.crypto` and only then sorts by value, so
              the colour follows the coin, not its rank. */}
          <AllocationCard
            title={t('Crypto Allocation', lang)}
            subtitle={t('How the portfolio is distributed', lang)}
            slices={cryptoAllocation().map((slice) => ({
              ...slice,
              color: CHART_PALETTE[crypto.findIndex((c) => c.symbol === slice.name) % CHART_PALETTE.length],
            }))}
          />
        </>
      ) : (
        /* --- holdingsList ------------------------------------------------ */
        <FinanceCard style={{ display: 'grid', gap: 14 }}>
          <SectionHeading title={t('Crypto holdings', lang)} subtitle={t('Tap a holding to edit its details', lang)} />
          {crypto.length === 0 ? (
            <EmptyState title={t('No crypto holdings yet', lang)} />
          ) : (
            <div style={{ display: 'grid', gap: 12 }}>
              {[...crypto]
                .sort((a, b) => cryptoValue(b) - cryptoValue(a))
                .map((holding) => (
                  <HoldingRow key={holding.symbol} holding={holding} />
                ))}
            </div>
          )}
        </FinanceCard>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------- rows */

/** performanceCard(title:holding:) — the leaderboard entry. */
function PerformanceRow({ title, holding }: { title: string; holding: CryptoHolding }) {
  const { money } = useSim();

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      <span style={{ fontSize: TEXT.headline, fontWeight: 600, color: WC.textPrimary }}>{title}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <CryptoIcon symbol={holding.symbol} />
        <div style={{ display: 'grid', gap: 4, flex: 1, minWidth: 0 }}>
          <span
            style={{
              fontSize: TEXT.subheadline,
              fontWeight: 500,
              color: WC.textPrimary,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {holding.name}
          </span>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{holding.symbol}</span>
        </div>
        <div style={{ display: 'grid', gap: 4, justifyItems: 'end', flexShrink: 0 }}>
          <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
            {money(cryptoValue(holding))}
          </span>
          <ValueDelta holding={holding} />
        </div>
      </div>
    </div>
  );
}

/** holdingRow(_:) — the inset row inside the Holdings tab. */
function HoldingRow({ holding }: { holding: CryptoHolding }) {
  const { money, lang, privacy } = useSim();
  const units = privacy
    ? REDACTION
    : new Intl.NumberFormat(lang, { minimumFractionDigits: 0, maximumFractionDigits: QUANTITY_PRECISION }).format(
        holding.quantity,
      );

  return (
    <InsetRow>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <CryptoIcon symbol={holding.symbol} />

        <div style={{ display: 'grid', gap: 6, flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
            <span style={{ fontFamily: SF_MONO, fontSize: TEXT.headline, fontWeight: 600, color: WC.textPrimary, flexShrink: 0 }}>
              {holding.symbol}
            </span>
            <span
              style={{
                fontSize: TEXT.caption,
                color: WC.textSecondary,
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
              }}
            >
              {holding.name}
            </span>
          </div>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums' }}>
            {fmt(t('%@ units', lang), units)}
          </span>
          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums' }}>
            {fmt(t('%@ / unit', lang), money(holding.price))}
          </span>
        </div>

        <div style={{ display: 'grid', gap: 4, justifyItems: 'end', flexShrink: 0, paddingLeft: 8 }}>
          <span style={{ fontSize: TEXT.subheadline, fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
            {money(cryptoValue(holding))}
          </span>
          <ValueDelta holding={holding} />
          {/* "Updated <date>". The dataset has no per-holding timestamp, so every row
              carries the one demo snapshot date the Status card and the Dashboard
              already print. */}
          <span style={{ fontSize: TEXT.caption2, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums' }}>
            {fmt(t('Updated %@', lang), LAST_UPDATED)}
          </span>
        </div>
      </div>
    </InsetRow>
  );
}

/**
 * ValueDelta — "<amount> (<percent>%)", green above zero and red below.
 *
 * Swift redacts only the amount and prints the percentage in the clear; here the
 * percentage goes through `percent()` like every other one on the site, which
 * redacts it too (the same call the allocation legend's share % makes).
 */
function ValueDelta({ holding }: { holding: CryptoHolding }) {
  const { money, percent } = useSim();
  const gain = cryptoValue(holding) - holding.costBasis;

  return (
    <span
      style={{
        fontSize: TEXT.subheadline,
        fontWeight: 600,
        fontVariantNumeric: 'tabular-nums',
        color: gain >= 0 ? WC.primary : WC.destructive,
        whiteSpace: 'nowrap',
      }}
    >
      {money(gain)} ({percent(gainLossPercent(holding))})
    </span>
  );
}

/** EmptyState(title:systemImage:) with "bitcoinsign.circle". */
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
          background: `${WC.primary}17`,
          color: `${WC.primary}c7`,
        }}
      >
        <Bitcoin size={22} strokeWidth={2.2} />
      </span>
      <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary, textAlign: 'center' }}>{title}</span>
    </div>
  );
}

/* ------------------------------------------------------------------ icon */

/**
 * CryptoIconView (DesignSystem.swift L630): a 38pt rounded square filled with the
 * symbol's tint at 15%, holding the uppercased first letter at 45% of the size.
 *
 * The ten tints are SwiftUI's system colours in their dark-mode variants, in the
 * order the Swift array declares them — the order is what decides which coin gets
 * which colour, so it is load-bearing and must not be re-sorted.
 */
const SYMBOL_TINTS = [
  '#ff453a', // .red
  '#0a84ff', // .blue
  '#30d158', // .green
  '#ff9f0a', // .orange
  '#bf5af2', // .purple
  '#ff375f', // .pink
  '#40c8e0', // .teal
  '#5e5ce6', // .indigo
  '#ffd60a', // .yellow
  '#66d4cf', // .mint
] as const;

/**
 * `hash = (hash &* 31) &+ Int(char)` over the symbol's UTF-8 bytes, then
 * `hash.magnitude % colors.count`.
 *
 * Swift's Int is 64-bit and both operators wrap, so this runs in BigInt clamped
 * to 64 bits — a JS number would lose precision past 2^53 and start picking a
 * different colour than the app does for longer symbols. WC-L13 guards the Swift
 * side against `abs(Int.min)` trapping; BigInt negation has no such edge, which
 * is why there is no guard here.
 */
function tintForSymbol(symbol: string): string {
  let hash = 0n;
  for (const byte of new TextEncoder().encode(symbol)) {
    hash = BigInt.asIntN(64, hash * 31n + BigInt(byte));
  }
  const magnitude = hash < 0n ? -hash : hash;
  return SYMBOL_TINTS[Number(magnitude % BigInt(SYMBOL_TINTS.length))];
}

function CryptoIcon({ symbol, size = 38 }: { symbol: string; size?: number }) {
  const tint = tintForSymbol(symbol);

  return (
    <span
      aria-hidden="true"
      style={{
        width: size,
        height: size,
        flexShrink: 0,
        display: 'grid',
        placeItems: 'center',
        borderRadius: 11,
        background: `${tint}26`, // .opacity(0.15)
        color: tint,
        fontSize: size * 0.45,
        fontWeight: 700,
        lineHeight: 1,
        // @ts-expect-error -- corner-shape is not in the CSSProperties type yet.
        cornerShape: 'squircle',
      }}
    >
      {symbol.slice(0, 1).toUpperCase()}
    </span>
  );
}

/** CryptoHolding.gainLossPercent — M10 divides by the cost-basis magnitude. */
function gainLossPercent(holding: CryptoHolding): number {
  return holding.costBasis !== 0 ? ((cryptoValue(holding) - holding.costBasis) / Math.abs(holding.costBasis)) * 100 : 0;
}
