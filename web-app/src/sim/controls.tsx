import { useRef, useSyncExternalStore, type KeyboardEvent } from 'react';
import { WC } from './tokens';
import { useSim } from './SimProvider';

/**
 * UIKit's segmented control in dark mode: a translucent grey trough with a
 * lighter raised pill behind the selection. Used for the net-worth range picker
 * (1W/1M/6M/1Y/ALL) and the cash-flow timeframe picker (3M/6M/12M), both of
 * which are `.pickerStyle(.segmented)` in the app.
 *
 * Exposed as a radio group, not a tab list: a UISegmentedControl mutates the
 * chart next to it rather than swapping panels, and VoiceOver announces its
 * segments as selected buttons. A tab role would promise a tabpanel that does
 * not exist. The radio-group keyboard model is APG's — one tab stop for the
 * whole control, arrows move focus and selection together.
 */
export function Segmented<T extends string>({
  options,
  value,
  onChange,
  label,
  compact = false,
}: {
  options: readonly T[];
  value: NoInfer<T>;
  // NoInfer matters here: a `Dispatch<SetStateAction<T>>` passed as onChange is
  // otherwise an inference site whose parameter is `T | ((prev: T) => T)`, which
  // fails the `extends string` constraint and collapses T back to `string`.
  onChange: (next: NoInfer<T>) => void;
  label: string;
  compact?: boolean;
}) {
  const { rtl } = useSim();
  const group = useRef<HTMLDivElement>(null);

  const selectedIndex = options.indexOf(value);
  // A value outside `options` would otherwise leave the control with no tab stop
  // at all, which is worse than parking it on the first segment.
  const rovingIndex = selectedIndex < 0 ? 0 : selectedIndex;

  const select = (index: number) => {
    onChange(options[index]);
    // The pressed segment is the one that must end up focused, and React has not
    // re-rendered yet, so this reads the live DOM rather than a stale ref list.
    group.current?.querySelectorAll<HTMLButtonElement>('[role="radio"]')[index]?.focus();
  };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    // Left/Right mirror under RTL the way a native radio group does; Up/Down are
    // block-axis keys and never mirror.
    const inline = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    const block = event.key === 'ArrowDown' ? 1 : event.key === 'ArrowUp' ? -1 : 0;
    const delta = inline * (rtl ? -1 : 1) + block;

    if (delta !== 0) {
      event.preventDefault();
      select((rovingIndex + delta + options.length) % options.length);
    } else if (event.key === 'Home') {
      event.preventDefault();
      select(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      select(options.length - 1);
    }
  };

  return (
    <div
      ref={group}
      role="radiogroup"
      aria-label={label}
      onKeyDown={onKeyDown}
      style={{
        display: 'flex',
        gap: 2,
        padding: 2,
        borderRadius: 9,
        background: 'rgba(118,118,128,0.24)',
        flexShrink: 0,
      }}
    >
      {options.map((option, index) => {
        const selected = index === selectedIndex;
        return (
          <button
            key={option}
            type="button"
            role="radio"
            aria-checked={selected}
            tabIndex={index === rovingIndex ? 0 : -1}
            onClick={() => select(index)}
            style={{
              flex: compact ? '0 0 auto' : 1,
              padding: compact ? '4px 10px' : '5px 0',
              border: 'none',
              borderRadius: 7,
              cursor: 'pointer',
              fontSize: 13,
              fontWeight: selected ? 600 : 500,
              fontVariantNumeric: 'tabular-nums',
              color: selected ? WC.textPrimary : WC.textSecondary,
              background: selected ? 'rgba(120,124,134,0.72)' : 'transparent',
              boxShadow: selected ? '0 1px 3px rgba(0,0,0,0.28)' : 'none',
              transition: 'background-color 150ms ease, color 150ms ease',
            }}
          >
            {option}
          </button>
        );
      })}
    </div>
  );
}

const REDUCED_MOTION = '(prefers-reduced-motion: reduce)';

/**
 * `getServerSnapshot` returns false so the prerendered HTML and the hydration
 * render agree; React re-reads the real query immediately after hydrating, which
 * a `useState` initialiser reading `matchMedia` could not do without a mismatch.
 */
function usePrefersReducedMotion() {
  return useSyncExternalStore(
    (onStoreChange) => {
      const query = window.matchMedia(REDUCED_MOTION);
      query.addEventListener('change', onStoreChange);
      return () => query.removeEventListener('change', onStoreChange);
    },
    () => window.matchMedia(REDUCED_MOTION).matches,
    () => false,
  );
}

/** iOS switch. Green when on, matching the app's `.tint` on Toggle. */
export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  const { rtl } = useSim();
  const reduced = usePrefersReducedMotion();

  // 51 wide with 2 of padding either side and a 27 knob leaves 20 of travel.
  // The knob is moved by `transform`, which is animatable; justify-content is
  // not, so flipping that instead made the knob jump while the track faded.
  // `transform` is also physical rather than logical, hence the sign flip —
  // UISwitch mirrors with the layout direction.
  const travel = checked ? (rtl ? -20 : 20) : 0;

  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      style={{
        width: 51,
        height: 31,
        flexShrink: 0,
        padding: 2,
        border: 'none',
        borderRadius: 16,
        cursor: 'pointer',
        background: checked ? WC.primary : 'rgba(120,120,128,0.32)',
        transition: reduced ? 'none' : 'background-color 200ms ease',
        display: 'flex',
        justifyContent: 'flex-start',
      }}
    >
      <span
        style={{
          width: 27,
          height: 27,
          flexShrink: 0,
          borderRadius: '50%',
          background: '#fff',
          boxShadow: '0 2px 4px rgba(0,0,0,0.25)',
          transform: `translateX(${travel}px)`,
          transition: reduced ? 'none' : 'transform 200ms ease',
        }}
      />
    </button>
  );
}
