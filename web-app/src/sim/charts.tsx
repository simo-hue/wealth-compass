import { useEffect, useId, useRef, useState } from 'react';
import { WC } from './tokens';
import { annularSector, linePath, project, segments } from './geometry';
import { useSim } from './SimProvider';
import { t } from './strings';

/* ------------------------------------------------------------------ Donut */

export interface DonutSlice {
  name: string;
  value: number;
  color: string;
}

/**
 * `.cornerRadius(5)` on a chart the app frames at 200pt (DesignSystem.swift:426),
 * so the radius scales with the ring the web draws.
 */
const SECTOR_CORNER = 5 / 200;

/**
 * The app's `AllocationChart` ring. Hovering a wedge dims the others to 0.3 and
 * swaps the centre readout — `.opacity(hoveredSlice == nil || hoveredSlice?.id
 * == slice.id ? 1.0 : 0.3)` in DesignSystem.swift. On iOS the same interaction
 * is a drag gesture, so pointer events cover both here.
 */
export function Donut({
  slices,
  size = 200,
  innerRatio = 0.72,
  center,
  onHover,
  hovered,
  label,
}: {
  slices: DonutSlice[];
  size?: number;
  innerRatio?: number;
  center?: React.ReactNode;
  onHover?: (index: number | null) => void;
  hovered?: number | null;
  label?: string;
}) {
  const { money, percent, privacy } = useSim();
  const titleId = useId();
  const descId = useId();
  const [internal, setInternal] = useState<number | null>(null);
  const active = hovered !== undefined ? hovered : internal;
  const setActive = (i: number | null) => {
    if (hovered === undefined) setInternal(i);
    onHover?.(i);
  };

  const cx = size / 2;
  const cy = size / 2;
  const outer = size / 2;
  const inner = outer * innerRatio;
  const segs = segments(slices.map((s) => s.value));
  const total = slices.reduce((sum, s) => sum + Math.max(s.value, 0), 0);

  /**
   * Every `SectorMark` carries `.accessibilityLabel(slice.name)` and an
   * `.accessibilityValue` of amount + share, collapsed to the redaction token in
   * Privacy Mode (DesignSystem.swift:350-351,461-465). `role="img"` makes the
   * svg a leaf in the accessibility tree, so per-path labels inside it would be
   * dropped — the same data goes in the description instead.
   */
  const description = slices
    .filter((s) => s.value > 0)
    .map((s) =>
      privacy
        ? `${s.name}: ${money(s.value)}`
        : `${s.name}: ${money(s.value)}, ${percent(total > 0 ? (s.value / total) * 100 : 0)}`,
    )
    .join('; ');

  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        role="img"
        aria-labelledby={label ? titleId : undefined}
        aria-describedby={description ? descId : undefined}
      >
        {label && <title id={titleId}>{label}</title>}
        {description && <desc id={descId}>{description}</desc>}
        {slices.map((slice, i) => {
          if (slice.value <= 0) return null;
          // Fill the inset outline and stroke it with 2 × corner: the stroke is
          // what restores the true radii and the exact slice angles. See
          // annularSector in geometry.ts.
          const wedge = annularSector(cx, cy, inner, outer, segs[i].startDeg, segs[i].endDeg, size * SECTOR_CORNER);
          return (
            <path
              key={slice.name}
              d={wedge.d}
              fill={slice.color}
              stroke={wedge.corner > 0 ? slice.color : 'none'}
              strokeWidth={wedge.corner * 2}
              strokeLinejoin="round"
              opacity={active === null || active === i ? 1 : 0.3}
              style={{ transition: 'opacity 150ms ease-in-out', cursor: 'default' }}
              onPointerEnter={() => setActive(i)}
              onPointerLeave={() => setActive(null)}
            />
          );
        })}
      </svg>
      {center !== undefined && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'grid',
            placeItems: 'center',
            pointerEvents: 'none',
            textAlign: 'center',
          }}
        >
          {center}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ Trail */

/** `.symbolSize(22)` is an area in square points, so the dot's radius is √(22/π). */
const DOT_RADIUS = Math.sqrt(22 / Math.PI);

/**
 * The net-worth area chart. Same generator as the hero horizon — see
 * geometry.ts — so the two lines are genuinely one curve.
 */
export function Trail({
  values,
  width = 600,
  height = 200,
  color = WC.primary,
  showDots = false,
  label,
}: {
  values: number[];
  width?: number;
  height?: number;
  color?: string;
  showDots?: boolean;
  label?: string;
}) {
  const { money } = useSim();
  const gradientId = useId();
  const titleId = useId();
  const descId = useId();
  const pts = project(values, width, height);

  // An empty series would otherwise produce an area path with no leading moveto,
  // which browsers reject outright rather than ignore.
  if (pts.length === 0) return null;

  const line = linePath(pts);
  // Swift closes the AreaMark at `yDomain.lowerBound` — the bottom of the plot,
  // not the lowest reading. `project` insets the series by `pad` on both sides,
  // so the bottom of this viewBox is that same floor.
  const area = pts.length > 1 ? `${line} L ${width} ${height} L 0 ${height} Z` : null;

  /**
   * DashboardView.swift:259-260 labels every point with its date and value. The
   * series arrives here as bare numbers with no dates, and "ALL" is hundreds of
   * points, so the description carries the shape of the series instead of a
   * reading-by-reading transcript.
   */
  const description = `${values.length} points, ${money(values[0])} to ${money(values[values.length - 1])}, low ${money(
    Math.min(...values),
  )}, high ${money(Math.max(...values))}`;

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      width="100%"
      height={height}
      role="img"
      aria-labelledby={label ? titleId : undefined}
      aria-describedby={descId}
      style={{ display: 'block', overflow: 'visible' }}
    >
      {label && <title id={titleId}>{label}</title>}
      <desc id={descId}>{description}</desc>
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          {/* WCColor.primary.opacity(0.3) → 0.01, DashboardView.swift:242. */}
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0.01} />
        </linearGradient>
      </defs>
      {area && <path d={area} fill={`url(#${gradientId})`} />}
      <path
        d={line}
        fill="none"
        stroke={color}
        // StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round).
        strokeWidth={2.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
      {showDots &&
        pts.map(([x, y], i) => (
          // A filled circle cannot survive `preserveAspectRatio="none"` — it
          // renders as an ellipse, since x and y scale differently and
          // vectorEffect only governs strokes. A round cap on a zero-length
          // segment is a stroke, so it comes out circular at any aspect.
          <path
            key={i}
            d={`M ${x.toFixed(2)} ${y.toFixed(2)} L ${x.toFixed(2)} ${y.toFixed(2)}`}
            fill="none"
            stroke={color}
            strokeWidth={DOT_RADIUS * 2}
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
        ))}
    </svg>
  );
}

/* ------------------------------------------------------------------- Bars */

/**
 * Monthly income vs expenses. The app rounds the top corners only; an SVG rect
 * with a uniform `rx` would round the baseline too, so each bar is a path.
 */
export function Bars({
  data,
  height = 168,
  label,
}: {
  data: { month: string; income: number; expenses: number }[];
  height?: number;
  label?: string;
}) {
  const { money, lang } = useSim();
  const gradientId = useId();
  const titleId = useId();
  const descId = useId();
  const ref = useRef<SVGSVGElement>(null);

  /**
   * The bars are laid out in CSS pixels rather than in a 0-100 box stretched to
   * fit, because `.cornerRadius(6)` is a *radius*: in a non-uniformly scaled
   * space it renders as an ellipse — at the phone's ~3.7× horizontal stretch the
   * default six-month view domed over completely. Until the first measurement
   * the viewBox still stretches, so the prerendered HTML shows bars of the right
   * shape at the wrong scale rather than no bars at all; 320 is close to the
   * phone card it usually lands in.
   */
  const [width, setWidth] = useState(320);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(([entry]) => {
      const measured = entry.contentRect.width;
      if (measured > 0) setWidth(measured);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  if (data.length === 0) return null;

  const max = data.reduce((m, d) => Math.max(m, d.income, d.expenses), 0) || 1;
  const groupWidth = width / data.length;
  const barWidth = groupWidth * 0.3;
  const pairGap = groupWidth * 0.072;
  // BarMark's `.cornerRadius(6)`, clamped: past half the bar width the top edge
  // doubles back on itself. Swift degrades the same way once its own bars get
  // thin enough.
  const radius = Math.min(6, barWidth / 2);

  const bar = (x: number, value: number) => {
    // The floor at `radius` keeps an empty month as a visible nub instead of an
    // inverted path.
    const h = Math.max((value / max) * height, radius);
    const y = height - h;
    return `M ${x} ${height} L ${x} ${y + radius} Q ${x} ${y} ${x + radius} ${y} L ${x + barWidth - radius} ${y} Q ${x + barWidth} ${y} ${x + barWidth} ${y + radius} L ${x + barWidth} ${height} Z`;
  };

  /** BarMark labels: month + type, valued with the amount. DashboardView.swift:428-429,438-439. */
  const description = data
    .map((d) => `${d.month}: ${t('Income', lang)} ${money(d.income)}, ${t('Expenses', lang)} ${money(d.expenses)}`)
    .join('; ');

  return (
    <svg
      ref={ref}
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      width="100%"
      height={height}
      role="img"
      aria-labelledby={label ? titleId : undefined}
      aria-describedby={descId}
      style={{ display: 'block' }}
    >
      {label && <title id={titleId}>{label}</title>}
      <desc id={descId}>{description}</desc>
      <defs>
        {/*
          `WCColor.primary.gradient` / `WCColor.destructive.opacity(0.8).gradient`.
          SwiftUI's `.gradient` shades the mark from the colour into a darker
          version of itself; against the near-black card, easing the same hue
          toward the surface reads the same and survives any colour being passed
          in. objectBoundingBox units mean each bar gets its own ramp, as each
          BarMark does.
        */}
        <linearGradient id={`${gradientId}-income`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={WC.primary} stopOpacity={1} />
          <stop offset="100%" stopColor={WC.primary} stopOpacity={0.72} />
        </linearGradient>
        <linearGradient id={`${gradientId}-expenses`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={WC.destructive} stopOpacity={0.8} />
          <stop offset="100%" stopColor={WC.destructive} stopOpacity={0.58} />
        </linearGradient>
      </defs>
      {data.map((d, i) => {
        const left = i * groupWidth + groupWidth / 2 - barWidth - pairGap / 2;
        return (
          <g key={d.month}>
            <path d={bar(left, d.income)} fill={`url(#${gradientId}-income)`} />
            <path d={bar(left + barWidth + pairGap, d.expenses)} fill={`url(#${gradientId}-expenses)`} />
          </g>
        );
      })}
    </svg>
  );
}

/** Month labels sit outside the non-uniformly-scaled SVG so text isn't stretched. */
export function BarLabels({ data }: { data: { month: string }[] }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${data.length}, 1fr)`, marginTop: 6 }}>
      {data.map((d) => (
        <span key={d.month} style={{ fontSize: 10, color: WC.textFaint, textAlign: 'center' }}>
          {d.month}
        </span>
      ))}
    </div>
  );
}
