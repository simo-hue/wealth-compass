import type { ReactNode } from 'react';
import { ArrowLeftRight, Bitcoin, Gauge, Settings as SettingsIcon, TrendingUp } from 'lucide-react';
import { TEXT, WC } from '../tokens';
import { ScreenBackground, useInView } from '../ui';
import { useSim } from '../SimProvider';
import { tab as tabLabel } from '../strings';

/**
 * iPhone 16 Pro Max, in points.
 *
 * The screen is laid out at exactly 440×956 and then scaled to whatever width
 * the page gives it, so every measurement copied out of the Swift source — 18pt
 * card padding, 34pt safe-area inset, 49pt tab bar — is a literal number here
 * rather than something re-derived at a different scale.
 */
export const PHONE_W = 440;
export const PHONE_H = 956;
const STATUS_H = 59;
const TABBAR_H = 83;

export type TabKey = 'dashboard' | 'cashFlow' | 'investments' | 'crypto' | 'settings';

export const TAB_ORDER: TabKey[] = ['dashboard', 'cashFlow', 'investments', 'crypto', 'settings'];

const TAB_ICONS: Record<TabKey, typeof Gauge> = {
  dashboard: Gauge, //          gauge.with.dots.needle.67percent
  cashFlow: ArrowLeftRight, //  arrow.left.arrow.right
  investments: TrendingUp, //   chart.line.uptrend.xyaxis
  crypto: Bitcoin, //           bitcoinsign.circle
  settings: SettingsIcon, //    gearshape
};

function StatusBar() {
  return (
    <div
      style={{
        height: STATUS_H,
        display: 'flex',
        alignItems: 'flex-end',
        justifyContent: 'space-between',
        padding: '0 34px 8px',
        position: 'relative',
        zIndex: 3,
      }}
    >
      {/* Chrome, not content: the frozen 9:41 is part of the drawing of a phone,
          so it is hidden from assistive tech like the icon cluster beside it. */}
      <span aria-hidden="true" style={{ fontSize: 17, fontWeight: 600, letterSpacing: 0.2 }}>9:41</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 7 }} aria-hidden="true">
        <svg width="19" height="12" viewBox="0 0 19 12" fill="#fff">
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x={i * 5} y={9 - i * 3} width="3" height={3 + i * 3} rx="1" />
          ))}
        </svg>
        <svg width="17" height="12" viewBox="0 0 17 12" fill="none" stroke="#fff" strokeWidth="1.6" strokeLinecap="round">
          <path d="M1 4.2a11 11 0 0 1 15 0M3.9 7a7 7 0 0 1 9.2 0" />
          <circle cx="8.5" cy="10" r="1.1" fill="#fff" stroke="none" />
        </svg>
        <svg width="27" height="13" viewBox="0 0 27 13">
          <rect x="0.5" y="0.5" width="22" height="12" rx="3.8" fill="none" stroke="#fff" strokeOpacity="0.4" />
          <rect x="2" y="2" width="17" height="9" rx="2.4" fill="#fff" />
          <path d="M24.5 4.5v4a2.2 2.2 0 0 0 0-4z" fill="#fff" fillOpacity="0.4" />
        </svg>
      </span>
    </div>
  );
}

function TabBar({ active, onSelect, label }: { active: TabKey; onSelect: (t: TabKey) => void; label: string }) {
  const { lang } = useSim();
  return (
    <nav
      aria-label={`${label} tabs`}
      style={{
        height: TABBAR_H,
        paddingBottom: 22, // home-indicator inset
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'space-evenly',
        gap: 2,
        background: 'rgba(8,12,20,0.82)',
        backdropFilter: 'blur(28px)',
        WebkitBackdropFilter: 'blur(28px)',
        borderTop: '1px solid rgba(255,255,255,0.07)',
        position: 'relative',
        zIndex: 3,
      }}
    >
      {TAB_ORDER.map((key) => {
        const Icon = TAB_ICONS[key];
        const selected = key === active;
        return (
          <button
            key={key}
            type="button"
            onClick={() => onSelect(key)}
            aria-current={selected ? 'page' : undefined}
            style={{
              flex: 1,
              minWidth: 0,
              display: 'grid',
              justifyItems: 'center',
              gap: 3,
              padding: '7px 2px',
              margin: '4px 3px 0',
              borderRadius: 14,
              border: 'none',
              cursor: 'pointer',
              background: selected ? 'rgba(255,255,255,0.08)' : 'transparent',
              color: selected ? WC.primary : 'rgba(255,255,255,0.5)',
              transition: 'background-color 160ms ease, color 160ms ease',
            }}
          >
            <Icon size={23} strokeWidth={selected ? 2.4 : 2} />
            <span
              style={{
                fontSize: TEXT.caption2 - 1,
                fontWeight: selected ? 600 : 500,
                maxWidth: '100%',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
              }}
            >
              {tabLabel(key, lang)}
            </span>
          </button>
        );
      })}
    </nav>
  );
}

export function IPhone({
  width = 340,
  activeTab,
  onSelectTab,
  children,
  showChrome = true,
  label = 'Simulated app',
}: {
  width?: number;
  activeTab: TabKey;
  onSelectTab: (t: TabKey) => void;
  children: ReactNode;
  showChrome?: boolean;
  /**
   * Names this shell's tab bar in a screen reader's landmarks list. A page that
   * mounts more than one phone must give each a different value, or the list
   * shows several identical entries with no way to tell them apart.
   */
  label?: string;
}) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const { lang, rtl } = useSim();
  const scale = width / PHONE_W;

  return (
    <div ref={ref} style={{ width, height: PHONE_H * scale, position: 'relative', flexShrink: 0 }}>
      <div
        style={{
          width: PHONE_W,
          height: PHONE_H,
          transform: `scale(${scale})`,
          transformOrigin: 'top left',
          position: 'absolute',
          top: 0,
          left: 0,
        }}
      >
        {/* Titanium band. A 2px inner highlight does most of the work of making
            this read as metal rather than as a grey border. */}
        <div
          style={{
            position: 'absolute',
            inset: 0,
            borderRadius: 68,
            padding: 11,
            background: 'linear-gradient(150deg, #6f7580 0%, #2f343c 22%, #4a505a 52%, #23272e 78%, #5b616b 100%)',
            boxShadow: '0 40px 80px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.05)',
          }}
        >
          <div
            className="wc-screen"
            // The simulated language is the screen's language, not the page's:
            // without lang a speech synthesiser reads the Arabic, Japanese and
            // Chinese screens with English pronunciation rules.
            lang={lang}
            dir={rtl ? 'rtl' : 'ltr'}
            style={{
              width: '100%',
              height: '100%',
              borderRadius: 57,
              display: 'flex',
              flexDirection: 'column',
              boxShadow: 'inset 0 0 0 2px rgba(255,255,255,0.08)',
            }}
          >
            <ScreenBackground paused={!inView} />
            {showChrome && <StatusBar />}
            <div className="wc-scroll" style={{ flex: 1, minHeight: 0 }}>
              {children}
            </div>
            {showChrome && <TabBar active={activeTab} onSelect={onSelectTab} label={label} />}

            {/* Dynamic Island, above the content. */}
            <div
              aria-hidden="true"
              style={{
                position: 'absolute',
                top: 11,
                left: '50%',
                transform: 'translateX(-50%)',
                width: 125,
                height: 37,
                borderRadius: 19,
                background: '#000',
                zIndex: 5,
              }}
            />
            {/* Home indicator. */}
            <div
              aria-hidden="true"
              style={{
                position: 'absolute',
                bottom: 9,
                left: '50%',
                transform: 'translateX(-50%)',
                width: 144,
                height: 5,
                borderRadius: 3,
                background: 'rgba(255,255,255,0.32)',
                zIndex: 6,
              }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
