/**
 * Ported verbatim from apple/WealthCompass/Sources/Shared/UI/DesignSystem.swift.
 *
 * SwiftUI's `Color(red:green:blue:)` takes sRGB components in 0...1, so each hex
 * below is `round(component * 255)`. If `WCColor` changes in Swift, change it
 * here too — this file is the web mirror of it and nothing enforces that.
 *
 * These colours belong INSIDE a simulated device screen only. The marketing
 * chrome around the screens is defined in src/site/site.css and shares nothing
 * with this file on purpose.
 */

export const WC = {
  // WCColor
  background: '#04070c', // Color(red: 0.015, green: 0.026, blue: 0.047)
  card: '#0b101b', //       Color(red: 0.045, green: 0.064, blue: 0.105)
  cardElevated: '#131926', // Color(red: 0.075, green: 0.098, blue: 0.15)
  border: 'rgba(255,255,255,0.09)',

  // Text tokens. The Swift file notes these opacities are tuned to clear WCAG AA
  // on the app's dark surfaces (audit A3) — don't invent new faint whites.
  textPrimary: '#ffffff',
  textSecondary: 'rgba(255,255,255,0.70)',
  textTertiary: 'rgba(255,255,255,0.60)',
  textFaint: 'rgba(255,255,255,0.55)',

  primary: '#1fdb99', //     Color(red: 0.12, green: 0.86, blue: 0.60)
  accent: '#1ac7d1', //      Color(red: 0.10, green: 0.78, blue: 0.82)
  destructive: '#f24242', // Color(red: 0.95, green: 0.26, blue: 0.26)
  warning: '#f2a329', //     Color(red: 0.95, green: 0.64, blue: 0.16)

  // ScreenBackground's two gradient stops.
  sceneryWarm: '#081c1f', // Color(red: 0.03,  green: 0.11, blue: 0.12) @ 0.76
  sceneryCool: '#090a16', // Color(red: 0.035, green: 0.04, blue: 0.085) @ 0.72

  // The three stops behind the net-worth hero. Identical on both platforms —
  // DashboardView.swift:676-682 and MacDashboardView.swift:1092-1098 declare the
  // same teal → indigo → ink ramp.
  heroTop: '#061f21', //    Color(red: 0.025, green: 0.12, blue: 0.13)
  heroMid: '#09121f', //    Color(red: 0.035, green: 0.07, blue: 0.12)
  heroBottom: '#060a13', // Color(red: 0.025, green: 0.04, blue: 0.075)
} as const;

/** ColorPalette.chart — the dashboard / asset-allocation ramp. */
export const CHART_PALETTE = [
  WC.primary,
  '#0a84ff', // SwiftUI .blue on dark
  WC.warning,
  WC.destructive,
  '#bf5af2', // .purple
  '#ff375f', // .pink
  WC.accent,
] as const;

/** ColorPalette.chartType */
export const CHART_TYPE_PALETTE = [
  '#0a84ff', // .blue
  '#5e5ce6', // .indigo
  '#64d2ff', // .cyan
  '#bf5af2', // .purple
  '#66d4cf', // .mint
  '#40c8e0', // .teal
  WC.accent,
] as const;

/**
 * ColorPalette.chartGeography. The Swift comment (L56) explains the ordering:
 * consecutive entries differ in hue AND lightness, with a single warm accent and
 * a single red, so the two largest geographies never render as confusable
 * near-identical wedges. Preserve that ordering.
 */
export const CHART_GEOGRAPHY_PALETTE = [
  '#ff9f0a', // .orange — the single warm accent
  '#64d2ff', // .cyan
  '#30d158', // .green
  '#5e5ce6', // .indigo
  '#ffd60a', // .yellow
  WC.destructive, // the single red
  '#bf5af2', // .purple
] as const;

// SwiftUI's `.shadow(radius:)` is a Gaussian sigma, not a CSS blur length; the
// visually equivalent CSS blur is about twice it. Shadows in this file and in
// ui.tsx are therefore written `0 {y}px {2 × radius}px`, with the Swift call
// quoted alongside so the two can still be compared by eye.

/**
 * FinanceCard (DesignSystem.swift:126-157): .ultraThinMaterial, a white→card
 * diagonal film, a 1px white border and a soft drop shadow, clipped to a 20pt
 * continuous (squircle) corner. `corner-shape` is ignored everywhere it isn't
 * supported, which just leaves a plain rounded rect — the same fallback the
 * design already tolerates.
 *
 * This is the iOS surface. macOS uses `macCard` instead; they are genuinely
 * different views, not one view with a platform tweak.
 */
export const financeCard: React.CSSProperties = {
  background: `linear-gradient(135deg, rgba(255,255,255,0.055), rgba(11,16,27,0.28)), rgba(255,255,255,0.055)`,
  backdropFilter: 'blur(18px) saturate(140%)',
  WebkitBackdropFilter: 'blur(18px) saturate(140%)',
  border: `1px solid ${WC.border}`,
  borderRadius: 20,
  boxShadow: '0 9px 32px rgba(0,0,0,0.16)', // .shadow(black .16, radius: 16, y: 9)
  padding: 18,
  // The card is the containing block for the hero scenery, which covers it.
  // backdrop-filter already establishes one; this states the dependency.
  position: 'relative',
  // @ts-expect-error -- corner-shape is not in the CSSProperties type yet.
  cornerShape: 'squircle',
};

/**
 * DashboardGlassCard (MacDashboardView.swift:910-943) — what every macOS screen
 * puts its content in. Not a variant of FinanceCard: the padding, corner, stroke
 * and shadow all differ, and its film fades white → clear rather than
 * white → card, so it reads a shade lighter over the same backdrop.
 *
 * `padding` is a parameter in Swift (default 20); the net-worth hero passes 0
 * and applies 24 to its own content so the scenery can reach the card edge.
 */
export const macCard: React.CSSProperties = {
  background: `linear-gradient(135deg, rgba(255,255,255,0.055), transparent), rgba(255,255,255,0.055)`,
  backdropFilter: 'blur(18px) saturate(140%)',
  WebkitBackdropFilter: 'blur(18px) saturate(140%)',
  border: '1px solid rgba(255,255,255,0.08)', // not WC.border — the Mac stroke is 0.08
  borderRadius: 18,
  boxShadow: '0 10px 36px rgba(0,0,0,0.18)', // .shadow(black .18, radius: 18, y: 10)
  padding: 20,
  position: 'relative',
  // @ts-expect-error -- corner-shape is not in the CSSProperties type yet.
  cornerShape: 'squircle',
};

/** InsetFinanceRow: a flatter, tighter inset surface at 15pt corners. */
export const insetRow: React.CSSProperties = {
  background: `linear-gradient(135deg, rgba(255,255,255,0.035), transparent), rgba(19,25,38,0.58)`,
  border: '1px solid rgba(255,255,255,0.055)',
  borderRadius: 15,
  padding: 14,
};

/**
 * The Apple system stack. Everything inside a device screen uses this, so the
 * simulation renders in the app's real typeface on the devices most visitors
 * browsing an Apple-app landing page are actually using.
 */
export const SF = `-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'SF Pro Display', 'Helvetica Neue', sans-serif`;

/** SwiftUI's `design: .rounded` — SF Pro Rounded, via the ui-rounded generic. */
export const SF_ROUNDED = `ui-rounded, 'SF Pro Rounded', ${SF}`;

/**
 * Resolved **iOS** text style sizes at the default Dynamic Type size (Large), so
 * the iPhone simulation scales like the real thing.
 *
 * Only the screens inside `sim/ios/` may use this. The Mac window lays out in
 * macOS points, where the same style names resolve much smaller — use MAC_TEXT
 * there, or every label comes out 20-36% too big.
 */
export const TEXT = {
  largeTitle: 34,
  title1: 28,
  title2: 22,
  title3: 20,
  headline: 17,
  body: 17,
  callout: 16,
  subheadline: 15,
  footnote: 13,
  caption: 12,
  caption2: 11,
} as const;

/**
 * Resolved **macOS** text style sizes (AppKit's `NSFont.preferredFont(forTextStyle:)`,
 * which is what SwiftUI's `.headline` / `.caption` and friends resolve to when
 * compiled against the macOS SDK).
 *
 * The ramp is far flatter than iOS's: .footnote, .caption and .caption2 all land
 * on 10pt and differ only in weight and tracking, and .headline is 13pt — the
 * same size as .body, distinguished by weight alone. That flatness is why the
 * Mac screens read as dense text rather than as a scaled-up phone.
 */
export const MAC_TEXT = {
  largeTitle: 26,
  title1: 22,
  title2: 17,
  title3: 15,
  headline: 13,
  body: 13,
  callout: 12,
  subheadline: 11,
  footnote: 10,
  caption: 10,
  caption2: 10,
} as const;
