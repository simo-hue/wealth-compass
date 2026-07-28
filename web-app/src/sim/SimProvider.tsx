import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Lang, isRTL } from './strings';

/**
 * Simulation state, shared by every device screen on the page.
 *
 * The three controls exposed here are the three the simulated Settings screen
 * drives, so changing currency / privacy / language on the phone re-renders the
 * Mac window and every other screen at the same time — which is the point.
 */

/** `Currency` in FinanceModels.swift surfaces these four majors first. */
export const CURRENCIES = ['EUR', 'USD', 'GBP', 'CHF'] as const;
export type CurrencyCode = (typeof CURRENCIES)[number];

/**
 * Fixed demo rates against EUR. The real app fetches ECB reference rates from
 * Frankfurter and caches them with a 12h staleness window; nothing here talks to
 * a network, so these are frozen plausible values and are labelled as such in
 * the simulated Exchange Rates row.
 */
const RATES: Record<CurrencyCode, number> = { EUR: 1, USD: 1.0876, GBP: 0.8412, CHF: 0.9385 };

/** AppSettings.redactionToken */
const REDACTION = '••••';

/**
 * Foundation groups four-digit currency amounts (6.601,86 € in it-IT); Intl's
 * default `useGrouping: "auto"` does not, which made the metric cards disagree
 * with the app on exactly the magnitudes most likely to appear in them.
 * Asserted because the installed TypeScript lib still types useGrouping as a
 * boolean, though every target browser accepts the string form.
 *
 * The marketing routes are prerendered with renderToString and then hydrated, so
 * the build's Node must be full-ICU: a small-icu build resolves every locale but
 * `en-US` to the root locale, and the currency strings baked into the HTML would
 * then disagree with the ones the browser produces on hydration — every metric
 * card on the page, silently. `node -p process.versions.icu` on a full build
 * reports an ICU version; a small-icu build reports `undefined`.
 */
const CURRENCY_FORMAT = {
  style: 'currency',
  useGrouping: 'always',
} as unknown as Intl.NumberFormatOptions;

/**
 * `zh` and `zh-*`, but not `zha` (Zhuang) or any other three-letter tag that
 * happens to open with those two letters.
 */
const isChinese = (tag: string) => tag === 'zh' || tag.startsWith('zh-');

/**
 * Only Simplified Chinese is translated, and Simplified is harder for a
 * Traditional reader than the English fallback. The script subtag catches
 * `zh-Hant-*`; Taiwan, Hong Kong and Macau routinely send a bare `zh-TW` /
 * `zh-HK` / `zh-MO` with no script subtag, so the region has to be checked too.
 * Matching whole subtags rather than substrings keeps `zh-Hans-MO` — Simplified,
 * explicitly — out of the exclusion.
 */
const TRADITIONAL_SUBTAGS = new Set(['hant', 'tw', 'hk', 'mo']);
const readsTraditional = (tag: string) => {
  const parts = tag.split('-');
  return parts.includes('hans') ? false : parts.some((part) => TRADITIONAL_SUBTAGS.has(part));
};

interface SimState {
  currency: CurrencyCode;
  setCurrency: (c: CurrencyCode) => void;
  privacy: boolean;
  setPrivacy: (p: boolean) => void;
  lang: Lang;
  setLang: (l: Lang) => void;
  rtl: boolean;
  /** Converted + locale-formatted, redacted under privacy mode. `privateCurrency`. */
  money: (eur: number) => string;
  /** Same, but never redacted — for axis ticks that carry no absolute value. */
  moneyRaw: (eur: number) => string;
  /** `.number.precision(.fractionLength(1))` + "%", redacted under privacy mode. */
  percent: (value: number) => string;
  convert: (eur: number) => number;
}

const SimContext = createContext<SimState | null>(null);

export function SimProvider({ children }: { children: ReactNode }) {
  const [currency, setCurrency] = useState<CurrencyCode>('EUR');
  const [privacy, setPrivacy] = useState(false);
  const [lang, setLang] = useState<Lang>('en');

  /**
   * Start in English so the prerendered HTML and the first client render agree,
   * then adopt the visitor's language once mounted if the app ships it. The app
   * follows the system language the same way, so an Italian visitor seeing an
   * Italian phone on an English page is accurate, not a bug.
   */
  useEffect(() => {
    const preferred = navigator.languages?.[0] ?? navigator.language ?? 'en';
    const base = preferred.toLowerCase();
    const match = (['zh-Hans', 'it', 'de', 'fr', 'es', 'ja', 'ar', 'en'] as Lang[]).find((code) =>
      code === 'zh-Hans' ? isChinese(base) && !readsTraditional(base) : base.startsWith(code),
    );
    if (match && match !== 'en') setLang(match);
  }, []);

  const convert = useCallback((eur: number) => eur * RATES[currency], [currency]);

  const format = useCallback(
    (eur: number) =>
      new Intl.NumberFormat(lang, { ...CURRENCY_FORMAT, currency }).format(eur * RATES[currency]),
    [lang, currency],
  );

  const value = useMemo<SimState>(
    () => ({
      currency,
      setCurrency,
      privacy,
      setPrivacy,
      lang,
      setLang,
      rtl: isRTL(lang),
      money: (eur) => (privacy ? REDACTION : format(eur)),
      moneyRaw: format,
      percent: (v) =>
        privacy
          ? REDACTION
          : `${new Intl.NumberFormat(lang, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(v)}%`,
      convert,
    }),
    [currency, privacy, lang, format, convert],
  );

  return <SimContext.Provider value={value}>{children}</SimContext.Provider>;
}

export function useSim(): SimState {
  const ctx = useContext(SimContext);
  if (!ctx) throw new Error('useSim must be used inside <SimProvider>');
  return ctx;
}
