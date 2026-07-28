import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { Plus } from 'lucide-react';
import { SF_ROUNDED, TEXT, WC, financeCard, insetRow, macCard } from './tokens';
import { Donut, type DonutSlice } from './charts';
import { useSim } from './SimProvider';
import './sim.css';

/**
 * Ports of the reusable views in
 * apple/WealthCompass/Sources/Shared/UI/DesignSystem.swift.
 *
 * Sizes are the resolved values of the iOS text styles they use — .caption is
 * 12pt, .title3 is 20pt, and so on — so the proportions match the real app at
 * 1x. See TEXT in tokens.ts.
 */

/**
 * Measures the element it is attached to. Both device shells lay out at fixed
 * point dimensions and scale, so they need a real pixel width rather than a CSS
 * one. `initial` is what the prerendered HTML uses before hydration.
 */
export function useElementWidth<T extends HTMLElement>(initial: number) {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(initial);
  useEffect(() => {
    const node = ref.current;
    if (!node || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(([entry]) => {
      const next = entry.contentRect.width;
      if (next > 0) setWidth(next);
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  return { ref, width };
}

/** Pauses expensive decoration while a screen is scrolled out of view. */
export function useInView<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const node = ref.current;
    if (!node || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(([entry]) => setInView(entry.isIntersecting), { rootMargin: '80px' });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  return { ref, inView };
}

/** ScreenBackground: base colour, a diagonal gradient, and two drifting blurs. */
export function ScreenBackground({ paused }: { paused: boolean }) {
  return (
    <div className="wc-scenery" data-paused={paused} aria-hidden="true">
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `linear-gradient(135deg, ${WC.sceneryWarm}c2 0%, transparent 50%, ${WC.sceneryCool}b8 100%)`,
        }}
      />
      <span
        style={{
          width: '95%',
          maxWidth: 420,
          aspectRatio: '1',
          background: 'rgba(31,219,153,0.07)',
          filter: 'blur(80px)',
          right: '-25%',
          top: '-30%',
          animationName: 'wc-scenery-a',
        }}
      />
      <span
        style={{
          width: '75%',
          maxWidth: 320,
          aspectRatio: '1',
          background: 'rgba(26,199,209,0.045)',
          filter: 'blur(72px)',
          left: '-28%',
          bottom: '-24%',
          animationName: 'wc-scenery-b',
        }}
      />
    </div>
  );
}

export function FinanceCard({ children, style }: { children: ReactNode; style?: CSSProperties }) {
  return <div style={{ ...financeCard, ...style }}>{children}</div>;
}

/**
 * DashboardGlassCard (MacDashboardView.swift:910-943) — the macOS surface. It is
 * a different view from FinanceCard, not a variant of it, so the Mac screens use
 * this rather than passing overrides into FinanceCard.
 */
export function MacCard({
  children,
  padding,
  style,
}: {
  children: ReactNode;
  padding?: number;
  style?: CSSProperties;
}) {
  return <div style={{ ...macCard, ...(padding === undefined ? null : { padding }), ...style }}>{children}</div>;
}

/**
 * MobileHeroScenery (DashboardView.swift:673-702) — the wash behind the
 * net-worth hero: a teal → indigo → ink diagonal plus two blurred tint circles.
 *
 * Unlike ScreenBackground it has no `isAnimating`, so there is nothing to pause
 * and no reduced-motion case to answer: in the app this is a still image.
 *
 * Swift puts it in a ZStack under the hero's content and gives it `.padding(-18)`
 * so it bleeds back out over FinanceCard's own 18pt padding. Absolute positioning
 * reaches the same edges, since an abspos child resolves against the card's
 * padding box. `zIndex: -1` paints it above the card's fill and below the text,
 * the same trick `.wc-scenery` uses inside `.wc-screen`.
 */
export function MobileHeroScenery() {
  return (
    <HeroSceneryLayers
      radius={20}
      circles={[
        // .fill(primary .14) 240pt, blur 58, offset(x: w * 0.38, y: -h * 0.3)
        { size: 240, blur: 58, color: 'rgba(31,219,153,0.14)', left: '88%', top: '20%' },
        // .fill(accent .08) 200pt, blur 55, offset(x: -w * 0.38, y: h * 0.35)
        { size: 200, blur: 55, color: 'rgba(26,199,209,0.08)', left: '12%', top: '85%' },
      ]}
    />
  );
}

/**
 * HeroScenery (MacDashboardView.swift:1089-1124) — the Mac's hero wash. Same
 * three gradient stops as the phone's, but larger, softer circles placed
 * differently, plus a fourth layer the phone does not have: a white .055 → clear
 * top-to-middle sheen that lifts the top edge of the card.
 *
 * It sits inside `DashboardGlassCard(padding: 0)`, so unlike the phone's there is
 * no negative padding to undo — it already fills the card.
 */
export function MacHeroScenery() {
  return (
    <HeroSceneryLayers
      radius={18}
      circles={[
        // .fill(primary .13) 340pt, blur 70, offset(x: w * 0.33, y: -h * 0.34)
        { size: 340, blur: 70, color: 'rgba(31,219,153,0.13)', left: '83%', top: '16%' },
        // .fill(accent .08) 260pt, blur 64, offset(x: -w * 0.36, y: h * 0.34)
        { size: 260, blur: 64, color: 'rgba(26,199,209,0.08)', left: '14%', top: '84%' },
      ]}
      sheen
    />
  );
}

/**
 * Both hero sceneries differ only in corner, circle geometry and the Mac's extra
 * sheen, so they share one body. SwiftUI circle offsets are measured from the
 * centre; `left`/`top` above are those offsets folded into `50% ± offset`, with
 * the translate re-centring each circle on the resulting point.
 *
 * `blur` is passed straight through, matching the convention ScreenBackground
 * already set — SwiftUI's blur radius and CSS's blur length read the same at
 * these sizes, and the circles are pure decoration either way.
 */
function HeroSceneryLayers({
  radius,
  circles,
  sheen = false,
}: {
  radius: number;
  circles: { size: number; blur: number; color: string; left: string; top: string }[];
  sheen?: boolean;
}) {
  return (
    <div
      aria-hidden="true"
      style={{
        position: 'absolute',
        inset: 0,
        zIndex: -1,
        overflow: 'hidden',
        borderRadius: radius,
        pointerEvents: 'none',
        background: `linear-gradient(135deg, ${WC.heroTop}, ${WC.heroMid}, ${WC.heroBottom})`,
      }}
    >
      {circles.map((circle) => (
        <span
          key={circle.color + circle.left}
          style={{
            position: 'absolute',
            width: circle.size,
            height: circle.size,
            left: circle.left,
            top: circle.top,
            transform: 'translate(-50%, -50%)',
            borderRadius: '50%',
            background: circle.color,
            filter: `blur(${circle.blur}px)`,
          }}
        />
      ))}
      {sheen && (
        <span
          style={{
            position: 'absolute',
            inset: 0,
            background: 'linear-gradient(180deg, rgba(255,255,255,0.055), rgba(255,255,255,0) 50%)',
          }}
        />
      )}
    </div>
  );
}

export function InsetRow({ children, style }: { children: ReactNode; style?: CSSProperties }) {
  return <div style={{ ...insetRow, ...style }}>{children}</div>;
}

export function SectionHeading({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div style={{ display: 'grid', gap: 4 }}>
      <span style={{ fontSize: TEXT.headline, fontWeight: 600, color: WC.textPrimary }}>{title}</span>
      {subtitle && <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>{subtitle}</span>}
    </div>
  );
}

/**
 * PageHeader — 30pt SF Rounded bold with the white→green gradient, plus subtitle.
 *
 * The Swift HStack has both `spacing: 16` and a `Spacer(minLength: 8)`, so the
 * title block and the trailing control can never come closer than 40pt even when
 * the subtitle is long enough to truncate. The spacer below is that floor; the
 * text block shrinks into it rather than pushing through it.
 */
export function PageHeader({ title, subtitle, trailing }: { title: string; subtitle: string; trailing?: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
      <div style={{ display: 'grid', gap: 5, minWidth: 0, flex: '0 1 auto' }}>
        <span className="wc-title-gradient" style={{ fontFamily: SF_ROUNDED, fontSize: 30, fontWeight: 700, lineHeight: 1.1 }}>
          {title}
        </span>
        <span
          style={{
            fontSize: TEXT.subheadline,
            color: WC.textTertiary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {subtitle}
        </span>
      </div>
      <span style={{ flex: '1 1 auto', minWidth: 8 }} />
      {trailing}
    </div>
  );
}

/**
 * PrimaryActionButton — 44pt green circle, black glyph, soft green shadow.
 *
 * In the app this is a `Button` that presents a sheet. Nothing in the simulation
 * can present anything, so announcing it with the Swift's `accessibilityLabel`
 * offered screen-reader users an action that does not exist — and it was never
 * focusable or activatable to begin with. It is decoration here, and hidden as
 * such; the surrounding screen already names what it is. `label` stays in the
 * signature so the call sites keep mirroring the Swift.
 */
export function PrimaryActionButton({ label: _label }: { label: string }) {
  return (
    <span
      aria-hidden="true"
      style={{
        width: 44,
        height: 44,
        flexShrink: 0,
        display: 'grid',
        placeItems: 'center',
        borderRadius: '50%',
        background: `linear-gradient(180deg, ${WC.primary}, #17b880)`,
        boxShadow: `0 5px 20px rgba(31,219,153,0.24)`, // .shadow(primary .24, radius: 10, y: 5)
        color: 'rgba(0,0,0,0.82)',
      }}
    >
      <Plus size={19} strokeWidth={3} />
    </span>
  );
}

export function MetricCard({
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
      {/* HStack default alignment — the 5pt dot centres on the 34pt tile. */}
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
          style={{
            width: 5,
            height: 5,
            borderRadius: '50%',
            background: accent,
            opacity: 0.72,
            boxShadow: `0 0 4px ${accent}a6`,
          }}
        />
      </div>
      <div style={{ display: 'grid', gap: 4, minWidth: 0 }}>
        <span style={{ fontSize: TEXT.caption, fontWeight: 500, color: WC.textTertiary }}>{title}</span>
        <span
          style={{
            fontSize: TEXT.title3,
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
        {detail && <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>{detail}</span>}
      </div>
    </FinanceCard>
  );
}

/**
 * EmptyState (DesignSystem.swift:283-303) — a 46pt tinted glyph tile over a
 * centred caption, 28pt of vertical air, full width.
 *
 * The tile keeps its 0.09 fill at full strength: Swift dims only the symbol
 * (`primary.opacity(0.78)`), not the rounded rect behind it.
 *
 * The caption is on the iOS ramp, which is where all of its current callers are.
 * A Mac caller would need MAC_TEXT.subheadline instead.
 */
export function EmptyState({ title, icon }: { title: string; icon: ReactNode }) {
  return (
    <div style={{ display: 'grid', justifyItems: 'center', gap: 10, width: '100%', padding: '28px 0' }}>
      <span
        style={{
          width: 46,
          height: 46,
          display: 'grid',
          placeItems: 'center',
          borderRadius: 14,
          background: 'rgba(31,219,153,0.09)',
          color: 'rgba(31,219,153,0.78)',
        }}
      >
        {icon}
      </span>
      <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary, textAlign: 'center' }}>{title}</span>
    </div>
  );
}

/**
 * AllocationChart — the donut card with its centre readout and legend. The
 * legend is a separate render in Swift (L58) so hovering doesn't re-render it;
 * here the hover state lives in this component and the legend is memo-free but
 * cheap, so the same effect holds without the split.
 */
export function AllocationCard({
  title,
  subtitle,
  slices,
  size = 200,
  footnote,
  centerLabel = 'TOTAL',
}: {
  title: string;
  subtitle?: string;
  slices: DonutSlice[];
  size?: number;
  footnote?: string;
  /**
   * The idle caption inside the ring. iOS says "TOTAL" (DesignSystem.swift:375);
   * the Mac's asset ring says "ASSETS" (MacDashboardView.swift:484) because that
   * total deliberately excludes liabilities. Already-localized — the caller
   * resolves it, like the Swift's own uppercased labels.
   */
  centerLabel?: string;
}) {
  const { money, percent, privacy } = useSim();
  const [hovered, setHovered] = useState<number | null>(null);
  const total = slices.reduce((s, x) => s + x.value, 0);
  const active = hovered !== null ? slices[hovered] : null;

  return (
    <FinanceCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
      <SectionHeading title={title} subtitle={subtitle} />
      <div style={{ display: 'grid', placeItems: 'center' }}>
        <Donut
          slices={slices}
          size={size}
          hovered={hovered}
          onHover={setHovered}
          label={title}
          center={
            <div style={{ display: 'grid', gap: 3, maxWidth: size * 0.6 }}>
              <span
                style={{
                  fontSize: TEXT.caption2,
                  fontWeight: 700,
                  letterSpacing: '1.3px',
                  color: active ? active.color : WC.textFaint,
                }}
              >
                {active ? active.name.toUpperCase() : centerLabel}
              </span>
              <span
                style={{
                  fontSize: TEXT.headline,
                  fontWeight: 700,
                  fontVariantNumeric: 'tabular-nums',
                  color: WC.textPrimary,
                  whiteSpace: 'nowrap',
                }}
              >
                {money(active ? active.value : total)}
              </span>
              {active && (
                <span style={{ fontSize: TEXT.caption2, color: WC.textTertiary, fontVariantNumeric: 'tabular-nums' }}>
                  {/* M30: the share % reveals composition too, so it redacts with the amount. */}
                  {privacy ? '••••' : percent(total > 0 ? (active.value / total) * 100 : 0)}
                </span>
              )}
            </div>
          }
        />
      </div>
      <div style={{ display: 'grid', gap: 12 }}>
        {slices.map((slice, i) => (
          <div
            key={slice.name}
            style={{ display: 'flex', alignItems: 'center', gap: 10 }}
            onPointerEnter={() => setHovered(i)}
            onPointerLeave={() => setHovered(null)}
          >
            <span style={{ width: 10, height: 10, borderRadius: 3, background: slice.color, flexShrink: 0 }} />
            <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary }}>{slice.name}</span>
            <span style={{ flex: 1 }} />
            <span style={{ display: 'grid', gap: 2, justifyItems: 'end' }}>
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: WC.textPrimary }}>
                {money(slice.value)}
              </span>
              <span style={{ fontSize: TEXT.caption2, color: WC.textFaint, fontVariantNumeric: 'tabular-nums' }}>
                {privacy ? '••••' : percent(total > 0 ? (slice.value / total) * 100 : 0)}
              </span>
            </span>
          </div>
        ))}
      </div>
      {footnote && <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>{footnote}</span>}
    </FinanceCard>
  );
}
