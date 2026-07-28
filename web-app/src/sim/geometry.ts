/**
 * Chart geometry, deliberately free of React so the hero horizon and the
 * in-device net-worth chart can generate the *same* line from the same code.
 * That shared path is what makes the signature work: the trail is continuous
 * across the bezel, and only its colour changes.
 */

export type Pt = [number, number];

/**
 * The net-worth series as straight segments.
 *
 * Both dashboards draw the line and the area under it with
 * `.interpolationMethod(.linear)` — DashboardView.swift:247,256 and
 * MacDashboardView.swift:325,334 — and apple/DOCUMENTATION.md records that
 * switch to `.linear` as a deliberate fix, not an accident. A spline through
 * daily snapshots invents movement between two readings that the app itself
 * never draws, which on a net-worth chart is a claim about money that isn't
 * true.
 */
export function linePath(pts: Pt[]): string {
  if (pts.length === 0) return '';
  const [x0, y0] = pts[0];
  const head = `M ${x0.toFixed(2)} ${y0.toFixed(2)}`;
  return pts
    .slice(1)
    .reduce((d, [x, y]) => `${d} L ${x.toFixed(2)} ${y.toFixed(2)}`, head);
}

/**
 * The name `site/Horizon.tsx` imports. The horizon's entire claim is that it is
 * the same curve as the chart inside the device, so it has to resolve to the
 * same generator — hence an alias rather than a second implementation. New code
 * should call `linePath`.
 */
export const smoothPath = linePath;

/** Map a value series into a box, with a little headroom top and bottom. */
export function project(values: number[], width: number, height: number, pad = 0.12): Pt[] {
  if (values.length === 0) return [];
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const span = hi - lo;
  const top = pad * height;
  const usable = height - top * 2;
  return values.map((v, i) => [
    values.length === 1 ? width / 2 : (i / (values.length - 1)) * width,
    // A flat series has no band to sit in. Centre it: normalising by a fallback
    // span of 1 would put every point at (v - lo) = 0, i.e. flat on the floor,
    // which reads as "you have nothing" rather than "nothing changed".
    top + (1 - (span === 0 ? 0.5 : (v - lo) / span)) * usable,
  ]);
}

/** Twelve o'clock is 0°, angles run clockwise, matching Swift Charts. */
function polar(cx: number, cy: number, r: number, deg: number): Pt {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

const fmt = ([x, y]: Pt) => `${x.toFixed(3)} ${y.toFixed(3)}`;
const deg = (rad: number) => (rad * 180) / Math.PI;

export interface Wedge {
  /** The *inset* outline. Fill it, and stroke it with `2 * corner`. */
  d: string;
  /** The corner radius actually available, after clamping. Half the stroke width. */
  corner: number;
}

/**
 * One donut wedge: `SectorMark(innerRadius: .ratio(0.72), angularInset: 2.5)`
 * with `.cornerRadius(5)` (DesignSystem.swift:341-349).
 *
 * The returned path is the sector shrunk by `corner` on all four sides. Fill it
 * *and* stroke it with `strokeWidth = 2 * corner`, `strokeLinejoin="round"`, and
 * the stroke grows it back by `corner` in every direction: outer edge back to
 * `rOuter`, inner edge back to `rInner`, both radial edges back onto the exact
 * `startDeg` / `endDeg` rays, with `corner`-radius fillets at the four corners.
 *
 * The point of the inset-and-stroke construction is that the ink lands inside
 * `[startDeg, endDeg]` and nowhere else. The obvious alternative — a thick
 * round-capped stroke on the mid-radius — cannot: a round cap reaches
 * `asin((thickness / 2) / mid)` past its endpoint, 9.4° at the app's ring size,
 * so every wedge overstates itself by ~18.7° and the allocation ring contradicts
 * the percentages printed in the legend directly beneath it.
 */
export function annularSector(
  cx: number,
  cy: number,
  rInner: number,
  rOuter: number,
  startDeg: number,
  endDeg: number,
  corner: number,
): Wedge {
  const spanDeg = endDeg - startDeg;

  // A lone slice is a full annulus: no ends, so no corners to round, and no
  // single arc command can express 360°.
  if (spanDeg >= 359.999) {
    const ring = (r: number, sweep: 0 | 1) =>
      `M ${fmt(polar(cx, cy, r, 0))} A ${r} ${r} 0 1 ${sweep} ${fmt(polar(cx, cy, r, 180))}` +
      ` A ${r} ${r} 0 1 ${sweep} ${fmt(polar(cx, cy, r, 0))} Z`;
    // Opposite winding punches the hole under the default nonzero fill rule.
    return { d: `${ring(rOuter, 1)} ${ring(rInner, 0)}`, corner: 0 };
  }

  const spanRad = (spanDeg * Math.PI) / 180;
  const c = Math.max(
    0,
    Math.min(
      corner,
      // Two fillets have to fit across the ring…
      (rOuter - rInner) / 2,
      // …and across the wedge. `rInner * sin(span / 2)` is the conservative
      // bound: the inset inner radius is larger still, so the angular inset
      // asin(c / rInner') it produces stays strictly under half the span and the
      // inner arc keeps a positive length. Wedges wider than a half-turn are
      // never the binding constraint.
      rInner * Math.sin(Math.min(spanRad, Math.PI) / 2),
    ),
  );

  const rO = rOuter - c;
  const rI = rInner + c;
  // Inset a radial edge sideways by `c`: the parallel line meets radius r at
  // asin(c / r), which is why the two ends of that edge sit at different angles.
  const aO = deg(Math.asin(Math.min(1, c / rO)));
  const aI = deg(Math.asin(Math.min(1, c / rI)));
  const large = (sweep: number) => (sweep > 180 ? 1 : 0);

  return {
    d:
      `M ${fmt(polar(cx, cy, rO, startDeg + aO))}` +
      ` A ${rO.toFixed(3)} ${rO.toFixed(3)} 0 ${large(spanDeg - 2 * aO)} 1 ${fmt(polar(cx, cy, rO, endDeg - aO))}` +
      ` L ${fmt(polar(cx, cy, rI, endDeg - aI))}` +
      ` A ${rI.toFixed(3)} ${rI.toFixed(3)} 0 ${large(spanDeg - 2 * aI)} 0 ${fmt(polar(cx, cy, rI, startDeg + aI))}` +
      ` Z`,
    corner: c,
  };
}

export interface Segment {
  startDeg: number;
  endDeg: number;
}

/**
 * Lay slices out around the ring, reserving `insetDeg` of gap after each drawn
 * slice — including the one that closes the ring at twelve o'clock.
 *
 * Only positive values are laid out and only they reserve a gap, so the ring
 * closes at exactly 360° whatever the input. Advancing the cursor past empty
 * slices too used to push the total to 360 + (empty × insetDeg): an allocation
 * with no crypto closed at 362.5° and the last wedge overpainted the first.
 * Empty slices come back as zero-length segments at the cursor.
 */
export function segments(values: number[], insetDeg = 2.5): Segment[] {
  const drawn = values.filter((v) => v > 0).length;
  const total = values.reduce((s, v) => s + Math.max(v, 0), 0) || 1;
  const gap = drawn > 1 ? insetDeg : 0;
  const sweep = 360 - gap * drawn;
  let cursor = 0;
  return values.map((v) => {
    if (v <= 0) return { startDeg: cursor, endDeg: cursor };
    const span = (v / total) * sweep;
    const seg = { startDeg: cursor, endDeg: cursor + span };
    cursor += span + gap;
    return seg;
  });
}
