/**
 * The single demo dataset behind every simulated screen and the hero horizon.
 *
 * Two rules kept this honest and should keep it honest:
 *   1. Nothing is hard-coded twice. Totals derive from positions, allocations
 *      derive from totals. If a figure appears on two screens it is the same
 *      figure, because it came from here.
 *   2. Amounts are stored as plain EUR numbers. Currency and privacy redaction
 *      are applied at render time by src/sim/format.ts, so the Settings screen's
 *      live controls can re-render every screen without touching this file.
 *
 * The asset total (14.559,41 €) deliberately matches the App Store screenshots
 * in apple/app_store_images, so the store listing and the site show the same
 * portfolio. The positions were widened from the three in those screenshots
 * because a sector ring that is 98,4% one slice reads as a rendering bug.
 */

export type Range = '1W' | '1M' | '6M' | '1Y' | 'ALL';
export const RANGES: Range[] = ['1W', '1M', '6M', '1Y', 'ALL'];
const RANGE_DAYS: Record<Range, number> = { '1W': 7, '1M': 30, '6M': 182, '1Y': 365, ALL: 540 };

export interface Holding {
  symbol: string;
  name: string;
  type: 'ETF' | 'Stock';
  sector: string;
  geography: string;
  quantity: number;
  price: number;
  costBasis: number;
}

export interface CryptoHolding {
  symbol: string;
  name: string;
  quantity: number;
  price: number;
  costBasis: number;
  change24h: number;
}

/* -- Positions ----------------------------------------------------------- */

export const holdings: Holding[] = [
  { symbol: 'VWCE', name: 'Vanguard FTSE All-World', type: 'ETF', sector: 'All World', geography: 'Global', quantity: 25.0864, price: 158.66, costBasis: 3631.0 },
  { symbol: 'GOOGL', name: 'Alphabet Inc.', type: 'Stock', sector: 'Technology', geography: 'United States', quantity: 3.4923, price: 315.68, costBasis: 803.62 },
  { symbol: 'NFLX', name: 'Netflix, Inc.', type: 'Stock', sector: 'Consumer', geography: 'United States', quantity: 10.607, price: 70.55, costBasis: 714.35 },
  { symbol: 'ASML', name: 'ASML Holding N.V.', type: 'Stock', sector: 'Technology', geography: 'Netherlands', quantity: 1.2, price: 708.33, costBasis: 936.87 },
];

export const crypto: CryptoHolding[] = [
  { symbol: 'BTC', name: 'Bitcoin', quantity: 0.0089, price: 87651.69, costBasis: 611.4, change24h: 1.84 },
  { symbol: 'ETH', name: 'Ethereum', quantity: 0.142, price: 2510.35, costBasis: 402.18, change24h: -0.92 },
  { symbol: 'SOL', name: 'Solana', quantity: 1.05, price: 133.33, costBasis: 118.72, change24h: 3.41 },
];

export const cashAccounts = [
  { name: 'Current account', balance: 4180.42 },
  { name: 'Savings', balance: 2421.44 },
];

export const liabilities = [
  { name: 'Credit card', balance: 620.0 },
  { name: 'Student loan', balance: 1230.0 },
];

/* -- Derived totals ------------------------------------------------------- */

const round2 = (n: number) => Math.round(n * 100) / 100;

export const holdingValue = (h: Holding) => round2(h.quantity * h.price);
export const cryptoValue = (c: CryptoHolding) => round2(c.quantity * c.price);

export const totals = (() => {
  const investments = round2(holdings.reduce((s, h) => s + holdingValue(h), 0));
  const investmentsCost = round2(holdings.reduce((s, h) => s + h.costBasis, 0));
  const cryptoTotal = round2(crypto.reduce((s, c) => s + cryptoValue(c), 0));
  const cryptoCost = round2(crypto.reduce((s, c) => s + c.costBasis, 0));
  const cash = round2(cashAccounts.reduce((s, a) => s + a.balance, 0));
  const debt = round2(liabilities.reduce((s, l) => s + l.balance, 0));
  const assets = round2(cash + investments + cryptoTotal);
  return {
    cash,
    investments,
    investmentsCost,
    investmentsPL: round2(investments - investmentsCost),
    investmentsPLPercent: ((investments - investmentsCost) / investmentsCost) * 100,
    crypto: cryptoTotal,
    cryptoCost,
    cryptoPL: round2(cryptoTotal - cryptoCost),
    debt,
    assets,
    netWorth: round2(assets - debt),
  };
})();

/* -- Allocations ----------------------------------------------------------
   `AllocationSlice` in the app is { name, value, color }; colour is assigned by
   the caller from the relevant ColorPalette ramp, which is why these carry only
   name and value. */

export interface Slice {
  name: string;
  value: number;
}

const groupBy = (key: keyof Holding): Slice[] => {
  const map = new Map<string, number>();
  for (const h of holdings) map.set(String(h[key]), round2((map.get(String(h[key])) ?? 0) + holdingValue(h)));
  return [...map].map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value);
};

export const allocationBySector = () => groupBy('sector');
export const allocationByType = () => groupBy('type');
export const allocationByGeography = () => groupBy('geography');

/**
 * The dashboard ring shows gross assets. The app drops net-negative cash rather
 * than draw a negative wedge and explains the gap in a footnote (DesignSystem
 * L33); here cash is positive, so the ring total equals `totals.assets`.
 */
export const assetAllocation = (): Slice[] => [
  { name: 'Investments', value: totals.investments },
  { name: 'Cash', value: totals.cash },
  { name: 'Crypto', value: totals.crypto },
];

export const cryptoAllocation = (): Slice[] =>
  crypto.map((c) => ({ name: c.symbol, value: cryptoValue(c) })).sort((a, b) => b.value - a.value);

/* -- Cash flow ------------------------------------------------------------ */

export interface CashFlowMonth {
  month: string;
  income: number;
  expenses: number;
}

/**
 * Twelve months, oldest first, so the 3M / 6M / 12M picker
 * (`CashFlowTimeframe` in FinanceModels.swift, rawValues 3/6/12) has something
 * behind each of its three positions — `slice(-3)`, `slice(-6)`, `slice(-12)`.
 *
 * June is last and is the "current month" every screen reads as
 * `monthlyCashFlow[length - 1]`, so its 1.200,00 in / 758,00 out still has to
 * match the June ledger in `transactions` and the `topExpenses` breakdown.
 * The six older months are last year's Jul-Dec; all twelve labels are distinct,
 * so nothing here needs the "yyyy-MM" disambiguation key MacCashFlowView uses
 * to keep same-month-different-year bars apart on its 12M range.
 */
export const monthlyCashFlow: CashFlowMonth[] = [
  { month: 'Jul', income: 1200.0, expenses: 1042.6 },
  { month: 'Aug', income: 1200.0, expenses: 1385.75 },
  { month: 'Sep', income: 1640.0, expenses: 1128.3 },
  { month: 'Oct', income: 1200.0, expenses: 986.45 },
  { month: 'Nov', income: 1200.0, expenses: 1204.9 },
  { month: 'Dec', income: 2860.0, expenses: 2418.7 },
  { month: 'Jan', income: 1420.0, expenses: 1180.5 },
  { month: 'Feb', income: 3180.0, expenses: 2640.0 },
  { month: 'Mar', income: 1180.0, expenses: 980.2 },
  { month: 'Apr', income: 1520.93, expenses: 1310.4 },
  { month: 'May', income: 2096.0, expenses: 1740.33 },
  { month: 'Jun', income: 1200.0, expenses: 758.0 },
];

/** Income / expenses / net for an arbitrary window of the series. */
export const sumCashFlow = (months: CashFlowMonth[]) => {
  const income = round2(months.reduce((s, m) => s + m.income, 0));
  const expenses = round2(months.reduce((s, m) => s + m.expenses, 0));
  return { income, expenses, net: round2(income - expenses) };
};

/**
 * The whole series — i.e. the 12M window. A legend under the 3M or 6M range has
 * to re-total its own slice with `sumCashFlow`, because the three ranges now
 * genuinely differ.
 */
export const cashFlowTotals = sumCashFlow(monthlyCashFlow);

/**
 * Top expense categories for the trailing 30 days — sums to June's expenses.
 *
 * These are the app's own default categories
 * (AppSettings.defaultExpenseCategoryKeys), not invented ones, so every label
 * here has a real translation in the string catalogue and the language picker
 * translates the whole screen rather than most of it.
 */
export const topExpenses: Slice[] = [
  { name: 'Housing', value: 380.0 },
  { name: 'Food', value: 189.4 },
  { name: 'Transport', value: 74.2 },
  { name: 'Entertainment', value: 68.45 },
  { name: 'Utilities', value: 45.95 },
];

export interface Activity {
  id: number;
  /** A default category key — translatable via strings.ts. */
  category: string;
  day: string;
  amount: number;
  kind: 'income' | 'expense';
}

/**
 * The full ledger the Cash Flow screens list. June's rows sum to the June
 * figures in `monthlyCashFlow` (1.200,00 in / 758,00 out), so the list and the
 * bar chart agree — the app derives one from the other and so must this.
 */
export const transactions: Activity[] = [
  { id: 1, category: 'Food', day: '24 Jun', amount: -42.18, kind: 'expense' },
  { id: 2, category: 'Salary', day: '20 Jun', amount: 1200.0, kind: 'income' },
  { id: 3, category: 'Entertainment', day: '18 Jun', amount: -28.5, kind: 'expense' },
  { id: 4, category: 'Transport', day: '16 Jun', amount: -14.9, kind: 'expense' },
  { id: 5, category: 'Housing', day: '15 Jun', amount: -380.0, kind: 'expense' },
  { id: 6, category: 'Food', day: '12 Jun', amount: -63.85, kind: 'expense' },
  { id: 7, category: 'Utilities', day: '10 Jun', amount: -45.95, kind: 'expense' },
  { id: 8, category: 'Food', day: '7 Jun', amount: -83.37, kind: 'expense' },
  { id: 9, category: 'Transport', day: '4 Jun', amount: -59.3, kind: 'expense' },
  { id: 10, category: 'Entertainment', day: '2 Jun', amount: -39.95, kind: 'expense' },
];

/**
 * DashboardView.swift:560 — `finance.transactions.prefix(5)`.
 *
 * Every row here stays inside June: CashFlowView's demo windowing reads only the
 * day-of-month out of `day` ("The demo ledger is a single month"), so a row from
 * an earlier month would land inside the 7-day window and pull the analytics
 * donut away from `topExpenses`.
 */
export const recentActivity: Activity[] = transactions.slice(0, 5);

/** MacDashboardView.swift:784 and MacCashFlowView.swift:499 — `prefix(6)`. */
export const recentActivityMac: Activity[] = transactions.slice(0, 6);

export interface Recurring {
  id: number;
  category: string;
  amount: number;
  kind: 'income' | 'expense';
  /** RecurringSchedule's cadence, as the app words it. */
  cadence: 'Monthly' | 'Weekly' | 'Yearly';
  nextDue: string;
  active: boolean;
}

export const recurring: Recurring[] = [
  { id: 1, category: 'Salary', amount: 1200.0, kind: 'income', cadence: 'Monthly', nextDue: '1 Jul', active: true },
  { id: 2, category: 'Housing', amount: 380.0, kind: 'expense', cadence: 'Monthly', nextDue: '5 Jul', active: true },
  { id: 3, category: 'Utilities', amount: 45.95, kind: 'expense', cadence: 'Monthly', nextDue: '10 Jul', active: true },
  { id: 4, category: 'Entertainment', amount: 9.99, kind: 'expense', cadence: 'Monthly', nextDue: '—', active: false },
];

/* -- Net-worth trail -------------------------------------------------------
   A deterministic curve, not a random walk: a linear trend plus two sine
   components plus a small repeatable jitter, normalised so the final point is
   exactly `totals.netWorth`. Deterministic matters because the hero horizon and
   the dashboard chart must draw the *same* line, and because Math.random() in
   render would change the page on every visit. */

export interface TrailPoint {
  /** Days before today. 0 is today. */
  daysAgo: number;
  value: number;
}

const TRAIL: TrailPoint[] = (() => {
  const n = RANGE_DAYS.ALL;
  const raw: number[] = [];
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    // Fixed-seed jitter: a cheap deterministic hash, no PRNG state to carry.
    const jitter = Math.sin(i * 12.9898) * 43758.5453;
    raw.push(
      0.62 * t + // the trend
        0.1 * Math.sin(t * Math.PI * 2.1) + // the long swell
        0.045 * Math.sin(t * Math.PI * 6.7 + 1.3) + // the plateau-and-step
        0.016 * Math.sin(t * Math.PI * 23 + 0.7) + // week-to-week movement
        // Kept small on purpose: the shorter ranges span few days, so the trend
        // contributes almost nothing across them and anything larger here reads
        // as ten ripples rather than a trail.
        0.0022 * (jitter - Math.floor(jitter) - 0.5),
    );
  }
  const lo = Math.min(...raw);
  const hi = Math.max(...raw);
  const last = raw[n - 1];
  // Map so the final point lands on net worth and the series spans a plausible
  // 18-month climb from roughly 58% of it.
  const floor = totals.netWorth * 0.58;
  const scale = (totals.netWorth - floor) / (last - lo);
  return raw.map((v, i) => ({ daysAgo: n - 1 - i, value: round2(floor + (v - lo) * scale) }));
})();

export const trail = (range: Range): TrailPoint[] => {
  const days = RANGE_DAYS[range];
  const slice = TRAIL.slice(-days);
  // Thin longer ranges so an SVG path stays under a couple hundred points.
  const step = Math.max(1, Math.ceil(slice.length / 120));
  const out = slice.filter((_, i) => i % step === 0);
  if (out[out.length - 1] !== slice[slice.length - 1]) out.push(slice[slice.length - 1]);
  return out;
};

export const trailChange = (range: Range) => {
  const points = trail(range);
  const first = points[0].value;
  const last = points[points.length - 1].value;
  return { value: round2(last - first), percent: ((last - first) / first) * 100 };
};

/** "Latest snapshot 4d ago" — the app shows snapshot freshness on the hero. */
export const snapshotAgeDays = 4;
