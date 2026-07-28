import type { ReactNode } from 'react';
import { ArrowLeftRight, Bitcoin, Gauge, Settings as SettingsIcon, TrendingUp } from 'lucide-react';
import { WC } from '../tokens';
import { ScreenBackground, useInView } from '../ui';
import { useSim } from '../SimProvider';
import { t } from '../strings';

/**
 * A port of the `NavigationSplitView` in Sources/macOS/MacRootView.swift.
 *
 * Laid out at 1440×900 points and scaled, which matters: MacDashboardView
 * branches on `proxy.size.width >= 1_090` to decide whether the allocation and
 * cash-flow cards sit side by side. At 1440 with the 220pt sidebar the detail
 * pane is 1220pt, so the two-column branch is the one that renders here — the
 * same one in the App Store screenshots.
 */
export const MAC_W = 1440;
export const MAC_H = 900;
const SIDEBAR_W = 220;

export type MacDestination = 'dashboard' | 'cashFlow' | 'investments' | 'crypto' | 'settings';

/** MacDestination.allCases, with its `systemImage` for each case. */
const DESTINATIONS: { key: MacDestination; title: string; Icon: typeof Gauge }[] = [
  { key: 'dashboard', title: 'Dashboard', Icon: Gauge },
  { key: 'cashFlow', title: 'Cash Flow', Icon: ArrowLeftRight },
  { key: 'investments', title: 'Investments', Icon: TrendingUp },
  { key: 'crypto', title: 'Crypto', Icon: Bitcoin },
  { key: 'settings', title: 'Settings', Icon: SettingsIcon },
];

function TrafficLights() {
  return (
    // Logical insets, so under RTL the buttons follow the window controls to the
    // leading (right) corner along with the rest of the chrome.
    <div style={{ display: 'flex', gap: 8, paddingBlockStart: 19, paddingInlineStart: 20 }} aria-hidden="true">
      {['#ff5f57', '#febc2e', '#28c840'].map((color) => (
        <span key={color} style={{ width: 12, height: 12, borderRadius: '50%', background: color }} />
      ))}
    </div>
  );
}

export function MacWindow({
  width = 980,
  selection,
  onSelect,
  children,
  label = 'Simulated Mac',
}: {
  width?: number;
  selection: MacDestination;
  onSelect: (destination: MacDestination) => void;
  children: ReactNode;
  /**
   * Names this window's sidebar in a screen reader's landmarks list. A page that
   * mounts more than one Mac must give each a different value, or the list shows
   * several identical entries with no way to tell them apart.
   */
  label?: string;
}) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const { lang, rtl } = useSim();
  const scale = width / MAC_W;

  return (
    <div ref={ref} style={{ width, height: MAC_H * scale, position: 'relative', flexShrink: 0 }}>
      <div
        style={{
          width: MAC_W,
          height: MAC_H,
          transform: `scale(${scale})`,
          transformOrigin: 'top left',
          position: 'absolute',
          inset: 0,
          borderRadius: 12,
          overflow: 'hidden',
          boxShadow: '0 60px 120px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.07)',
          display: 'flex',
          // AppKit mirrors a NavigationSplitView whole, so under RTL the sidebar
          // moves to the trailing edge. Reversing the row rather than setting dir
          // here keeps the attribute on the two .wc-screen elements, which is
          // where sim.css hooks the RTL title gradient.
          flexDirection: rtl ? 'row-reverse' : 'row',
        }}
      >
        {/* Sidebar */}
        <div
          className="wc-screen"
          lang={lang}
          dir={rtl ? 'rtl' : 'ltr'}
          style={{
            width: SIDEBAR_W,
            flexShrink: 0,
            background: 'rgba(22,26,34,0.92)',
            borderInlineEnd: '1px solid rgba(255,255,255,0.06)',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <TrafficLights />
          <div style={{ paddingBlock: '18px 8px', paddingInline: '16px 12px' }}>
            <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: 0.4, color: WC.textFaint, textTransform: 'uppercase' }}>
              Wealth Compass Tracker
            </span>
          </div>
          <nav style={{ display: 'grid', gap: 2, padding: '0 8px' }} aria-label={`${label} sidebar`}>
            {DESTINATIONS.map(({ key, title, Icon }) => {
              const selected = key === selection;
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => onSelect(key)}
                  aria-current={selected ? 'page' : undefined}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 10,
                    padding: '7px 10px',
                    border: 'none',
                    borderRadius: 7,
                    cursor: 'pointer',
                    textAlign: 'start',
                    fontSize: 13,
                    fontWeight: 500,
                    color: selected ? '#fff' : WC.textSecondary,
                    background: selected ? 'rgba(31,219,153,0.18)' : 'transparent',
                    transition: 'background-color 140ms ease, color 140ms ease',
                  }}
                >
                  <Icon size={15} strokeWidth={2.1} color={selected ? WC.primary : WC.textTertiary} />
                  {t(title, lang)}
                </button>
              );
            })}
          </nav>
        </div>

        {/* Detail pane. The Dashboard deliberately has no visible toolbar bar —
            see the comment above `body` in MacDashboardView.swift. */}
        <div
          className="wc-screen"
          // lang, not just dir: without it a speech synthesiser reads the Arabic,
          // Japanese and Chinese screens with English pronunciation rules.
          lang={lang}
          dir={rtl ? 'rtl' : 'ltr'}
          style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}
        >
          <ScreenBackground paused={!inView} />
          <div className="wc-scroll" style={{ flex: 1, minHeight: 0 }}>
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}
