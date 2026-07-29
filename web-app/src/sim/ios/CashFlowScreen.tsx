import { useState } from 'react';
import {
  ArrowDownLeft,
  ArrowUpRight,
  Calendar,
  Check,
  ChevronDown,
  CirclePlus,
  Inbox,
  ListFilter,
  Pause,
  Pencil,
  Percent,
  PieChart,
  Play,
  Plus,
  Repeat,
  Search,
  Wallet,
  X,
} from 'lucide-react';
import { CHART_PALETTE, TEXT, WC } from '../tokens';
import { FinanceCard, InsetRow, MetricCard, PageHeader, PrimaryActionButton, SectionHeading } from '../ui';
import { Donut } from '../charts';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import { type Activity, monthlyCashFlow, recurring, topExpenses, transactions } from '../data';

/**
 * A port of Sources/iOS/Views/CashFlowView.swift.
 *
 * The screen splits Overview / Transactions exactly as the Swift does (the
 * picker exists so iOS gets the searchable, uncapped list macOS already had).
 * Overview is summaryCards → recurringTransactions → analytics, and the donut in
 * `analytics` is the screen's only chart — the monthly bars belong to
 * DashboardView and MacCashFlowView, not here.
 *
 * Where lucide has no equivalent of an SF Symbol the nearest glyph is used.
 */

/** AnalyticsPeriod in FinanceModels.swift — rawValue, title key, and window. */
type AnalyticsPeriod = '7d' | '30d' | '3m' | 'ytd' | 'all';
const ANALYTICS_PERIODS: { value: AnalyticsPeriod; key: string; days: number | null }[] = [
  { value: '7d', key: 'Last 7 Days', days: 7 },
  { value: '30d', key: 'Last 30 Days', days: 30 },
  { value: '3m', key: 'Last 3 Months', days: 90 },
  { value: 'ytd', key: 'Year to Date', days: null },
  { value: 'all', key: 'All Time', days: null },
];

/**
 * Fills a catalogue string's format specifiers. The catalogue stores the English
 * "Showing %lld of %lld" as the positional `%1$lld … %2$lld` while the
 * translations use bare `%lld`, so both forms have to resolve — a plain
 * `.replace('%lld', …)` leaves the positional English untouched.
 */
const fmt = (template: string, ...values: (string | number)[]) => {
  let next = 0;
  return template.replace(/%(?:(\d+)\$)?(?:lld|ld|d|@)/g, (match, position?: string) => {
    const value = values[position ? Number(position) - 1 : next++];
    return value === undefined ? match : String(value);
  });
};

/**
 * The demo ledger is a single month, so the day-of-month is enough to window it
 * the way `transactionStartDate` windows real dates, and "now" is the newest row.
 */
const dayOf = (day: string) => parseInt(day, 10);
const LATEST_DAY = dayOf(transactions[0].day);

const withinPeriod = (activity: Activity, period: AnalyticsPeriod) => {
  const days = ANALYTICS_PERIODS.find((p) => p.value === period)?.days ?? null;
  return days === null || dayOf(activity.day) > LATEST_DAY - days;
};

/**
 * The app flags rows a schedule created (`transaction.recurringTransactionID`)
 * with a repeat glyph. data.ts carries no such link, so the equivalent rows are
 * the ones a schedule in `recurring` would have produced.
 */
const isScheduled = (activity: Activity) =>
  recurring.some((r) => r.category === activity.category && r.kind === activity.kind && r.amount === Math.abs(activity.amount));

export function CashFlowScreen() {
  const { money, percent, lang } = useSim();

  const overview = t('Overview', lang);
  const transactionsTitle = t('Transactions', lang);
  const [tab, setTab] = useState<'overview' | 'transactions'>('overview');
  const [addMenuOpen, setAddMenuOpen] = useState(false);

  const [period, setPeriod] = useState<AnalyticsPeriod>('30d');
  const [transactionPeriod, setTransactionPeriod] = useState<AnalyticsPeriod>('30d');
  const [typeFilter, setTypeFilter] = useState<'all' | 'income' | 'expense'>('all');
  const [search, setSearch] = useState('');

  // monthlyCashFlow(for: Date()) — the current month's income, expenses and rate.
  const month = monthlyCashFlow[monthlyCashFlow.length - 1];
  const netSavings = Math.round((month.income - month.expenses) * 100) / 100;
  // MonthlyCashFlow.savingsRate: zero rather than NaN when nothing came in.
  const savingsRate = month.income > 0 ? (netSavings / month.income) * 100 : 0;

  /**
   * expensesByCategory(period:). data.ts documents `topExpenses` as the
   * trailing-30-day breakdown and it is exactly what grouping the ledger's
   * expense rows yields, so the wider windows use it as-is and only the 7-day
   * window has to regroup — the card and the ledger can never disagree.
   */
  const categories =
    period === '7d'
      ? groupExpenses(transactions.filter((tx) => withinPeriod(tx, period)))
      : topExpenses;
  const totalExpenses = Math.round(categories.reduce((s, c) => s + c.value, 0) * 100) / 100;

  const query = search.trim().toLowerCase();
  const filtered = transactions.filter((tx) => {
    const matchesType = typeFilter === 'all' || tx.kind === typeFilter;
    const matchesPeriod = withinPeriod(tx, transactionPeriod);
    // The app also searches the description; data.ts rows carry only a category.
    const matchesSearch = query === '' || t(tx.category, lang).toLowerCase().includes(query) || tx.category.toLowerCase().includes(query);
    return matchesType && matchesPeriod && matchesSearch;
  });

  return (
    <div style={{ display: 'grid', gap: 20, padding: '0 16px 28px', alignContent: 'start' }}>
      <PageHeader
        title={t('Cash flow', lang)}
        subtitle={t('Understand what comes in and where it goes.', lang)}
        trailing={
          /* The "+" is a Menu, not a button: One-Time or Recurring. */
          <div style={{ position: 'relative', flexShrink: 0 }}>
            <button
              type="button"
              onClick={() => setAddMenuOpen((open) => !open)}
              aria-expanded={addMenuOpen}
              style={{ display: 'block', padding: 0, border: 'none', background: 'transparent', cursor: 'pointer' }}
            >
              <PrimaryActionButton label={t('Add Transaction', lang)} />
            </button>
            {addMenuOpen && (
              <Popover>
                <MenuItem icon={<CirclePlus size={15} strokeWidth={2.2} />} label={t('One-Time', lang)} onClick={() => setAddMenuOpen(false)} />
                <MenuItem icon={<Repeat size={15} strokeWidth={2.2} />} label={t('Recurring', lang)} onClick={() => setAddMenuOpen(false)} />
              </Popover>
            )}
          </div>
        }
      />

      {/* cashFlowTabPicker. Segmented renders the option string itself, so the
          localized titles are the options and the selection maps back. */}
      <Segmented
        options={[overview, transactionsTitle]}
        value={tab === 'overview' ? overview : transactionsTitle}
        onChange={(next) => setTab(next === overview ? 'overview' : 'transactions')}
        label="Cash flow view"
      />

      {tab === 'overview' ? (
        <>
          {/* --- summaryCards ------------------------------------------- */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <MetricCard
              title={t('Monthly Income', lang)}
              value={money(month.income)}
              icon={<ArrowDownLeft size={15} strokeWidth={2.4} />}
              detail={t('This month', lang)}
            />
            <MetricCard
              title={t('Monthly Expenses', lang)}
              value={money(month.expenses)}
              icon={<ArrowUpRight size={15} strokeWidth={2.4} />}
              accent={WC.destructive}
              detail={t('This month', lang)}
            />
            <MetricCard
              title={t('Net Savings', lang)}
              value={money(netSavings)}
              icon={<Wallet size={15} strokeWidth={2.4} />}
              accent={netSavings >= 0 ? WC.primary : WC.destructive}
              detail={t('Income less expenses', lang)}
            />
            <MetricCard
              title={t('Savings Rate', lang)}
              value={percent(savingsRate)}
              icon={<Percent size={15} strokeWidth={2.4} />}
              detail={t('Of monthly income', lang)}
            />
          </div>

          {/* --- recurringTransactions ---------------------------------- */}
          <FinanceCard style={{ display: 'grid', gap: 14 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <SectionHeading title={t('Recurring Transactions', lang)} subtitle={t('Automatic income and expenses', lang)} />
              </div>
              <span
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 4,
                  flexShrink: 0,
                  color: WC.primary,
                  fontSize: TEXT.subheadline,
                  fontWeight: 600,
                }}
              >
                <Plus size={14} strokeWidth={2.8} />
                {t('Add', lang)}
              </span>
            </div>

            {recurring.length === 0 ? (
              <EmptyState title={t('No recurring transactions', lang)} icon={<Repeat size={22} strokeWidth={2} />} />
            ) : (
              <div style={{ display: 'grid', gap: 12 }}>
                {recurring.map((schedule) => {
                  const income = schedule.kind === 'income';
                  const tint = income ? WC.primary : WC.destructive;
                  return (
                    <InsetRow key={schedule.id}>
                      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                        <IconTile tint={tint}>
                          {income ? <ArrowDownLeft size={14} strokeWidth={2.8} /> : <ArrowUpRight size={14} strokeWidth={2.8} />}
                        </IconTile>

                        <div style={{ display: 'grid', gap: 5, flex: 1, minWidth: 0 }}>
                          <span style={{ fontSize: TEXT.subheadline, fontWeight: 600 }}>{t(schedule.category, lang)}</span>
                          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{t(schedule.cadence, lang)}</span>
                          {schedule.active ? (
                            <span style={{ fontSize: TEXT.caption, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums' }}>
                              {fmt(t('Next: %@', lang), schedule.nextDue)}
                            </span>
                          ) : (
                            <span style={{ fontSize: TEXT.caption, fontWeight: 600, color: WC.warning }}>{t('Paused', lang)}</span>
                          )}
                        </div>

                        <div style={{ display: 'grid', gap: 9, justifyItems: 'end', flexShrink: 0 }}>
                          <span style={{ fontSize: TEXT.subheadline, fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: tint }}>
                            {income ? '+' : '-'}
                            {money(schedule.amount)}
                          </span>
                          <span style={{ display: 'flex', alignItems: 'center', gap: 14, color: WC.primary }}>
                            <span role="img" aria-label={t('Finish schedule', lang)}>
                              <Check size={15} strokeWidth={2.6} />
                            </span>
                            <span role="img" aria-label={t(schedule.active ? 'Pause schedule' : 'Resume schedule', lang)}>
                              {schedule.active ? <Pause size={14} strokeWidth={2.6} fill="currentColor" /> : <Play size={14} strokeWidth={2.6} fill="currentColor" />}
                            </span>
                            <span role="img" aria-label={t('Edit schedule', lang)}>
                              <Pencil size={14} strokeWidth={2.4} />
                            </span>
                          </span>
                        </div>
                      </div>
                    </InsetRow>
                  );
                })}
              </div>
            )}

            <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>
              {t('Due schedules are recorded automatically while the app is active and caught up the next time it opens.', lang)}
            </span>
          </FinanceCard>

          {/* --- analytics ---------------------------------------------- */}
          <FinanceCard style={{ display: 'grid', gap: 16 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <SectionHeading title={t('Spending analytics', lang)} subtitle={t('Expenses grouped by category', lang)} />
              </div>
              <MenuPicker
                label="Period"
                value={period}
                onChange={setPeriod}
                options={ANALYTICS_PERIODS.map((p) => ({ value: p.value, title: t(p.key, lang) }))}
              />
            </div>

            {categories.length === 0 ? (
              <EmptyState title={t('No expenses for this period', lang)} icon={<PieChart size={22} strokeWidth={2} />} />
            ) : (
              <ExpenseDonut categories={categories} total={totalExpenses} />
            )}
          </FinanceCard>
        </>
      ) : (
        /* --- transactions --------------------------------------------- */
        <FinanceCard style={{ display: 'grid', gap: 14 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
            <span style={{ fontSize: TEXT.headline, fontWeight: 600, flex: 1, minWidth: 0 }}>{transactionsTitle}</span>
            <span style={{ fontSize: TEXT.caption, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums', flexShrink: 0 }}>
              {fmt(t('Showing %lld of %lld', lang), filtered.length, transactions.length)}
            </span>
          </div>

          {/* transactionFilters */}
          <Segmented
            options={[t('All', lang), t('Income', lang), t('Expense', lang)]}
            value={typeFilter === 'all' ? t('All', lang) : typeFilter === 'income' ? t('Income', lang) : t('Expense', lang)}
            onChange={(next) => setTypeFilter(next === t('Income', lang) ? 'income' : next === t('Expense', lang) ? 'expense' : 'all')}
            label="Transaction Type"
          />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: TEXT.subheadline, color: WC.textSecondary, flex: 1 }}>
              <Calendar size={14} strokeWidth={2.2} />
              {t('Period', lang)}
            </span>
            <MenuPicker
              label="Transaction Period"
              value={transactionPeriod}
              onChange={setTransactionPeriod}
              options={ANALYTICS_PERIODS.map((p) => ({ value: p.value, title: t(p.key, lang) }))}
            />
          </div>

          {/* transactionSearchField */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              padding: '9px 12px',
              borderRadius: 11,
              background: 'rgba(255,255,255,0.06)',
            }}
          >
            <Search size={15} strokeWidth={2.2} color={WC.textSecondary} />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t('Search', lang)}
              aria-label={t('Search', lang)}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              style={{
                flex: 1,
                minWidth: 0,
                border: 'none',
                outline: 'none',
                background: 'transparent',
                color: WC.textPrimary,
                font: 'inherit',
                fontSize: TEXT.subheadline,
              }}
            />
            {search !== '' && (
              <button
                type="button"
                onClick={() => setSearch('')}
                aria-label={t('Clear search', lang)}
                style={{
                  display: 'grid',
                  placeItems: 'center',
                  padding: 0,
                  border: 'none',
                  background: 'transparent',
                  color: WC.textSecondary,
                  cursor: 'pointer',
                }}
              >
                <X size={15} strokeWidth={2.4} />
              </button>
            )}
          </div>

          {transactions.length === 0 ? (
            <EmptyState title={t('No transactions found', lang)} icon={<Inbox size={22} strokeWidth={2} />} />
          ) : filtered.length === 0 ? (
            <EmptyState title={t('No transactions match these filters', lang)} icon={<ListFilter size={22} strokeWidth={2} />} />
          ) : (
            <div style={{ display: 'grid', gap: 12 }}>
              {filtered.map((tx) => {
                const income = tx.kind === 'income';
                const tint = income ? WC.primary : WC.destructive;
                return (
                  <InsetRow key={tx.id}>
                    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                      <IconTile tint={tint}>
                        {income ? <ArrowDownLeft size={14} strokeWidth={2.8} /> : <ArrowUpRight size={14} strokeWidth={2.8} />}
                      </IconTile>
                      <div style={{ display: 'grid', gap: 4, flex: 1, minWidth: 0 }}>
                        <span style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                          <span style={{ fontSize: TEXT.subheadline, fontWeight: 600 }}>{t(tx.category, lang)}</span>
                          {isScheduled(tx) && (
                            <span style={{ color: WC.primary, display: 'flex' }} aria-hidden="true">
                              <Repeat size={11} strokeWidth={2.6} />
                            </span>
                          )}
                          <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{tx.day}</span>
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: TEXT.subheadline,
                          fontWeight: 700,
                          fontVariantNumeric: 'tabular-nums',
                          color: tint,
                          flexShrink: 0,
                        }}
                      >
                        {income ? '+' : '-'}
                        {money(Math.abs(tx.amount))}
                      </span>
                    </div>
                  </InsetRow>
                );
              })}
            </div>
          )}
        </FinanceCard>
      )}
    </div>
  );
}

/** expensesByCategory — the ledger's expense rows, grouped and ranked. */
function groupExpenses(rows: Activity[]) {
  const map = new Map<string, number>();
  for (const row of rows) {
    if (row.kind !== 'expense') continue;
    map.set(row.category, (map.get(row.category) ?? 0) + Math.abs(row.amount));
  }
  return [...map]
    .map(([name, value]) => ({ name, value: Math.round(value * 100) / 100 }))
    .sort((a, b) => b.value - a.value);
}

/**
 * The analytics ring plus the six-row breakdown under it. The centre readout
 * follows the hovered wedge and falls back to EXPENSES + the period total,
 * exactly as `chartBackground` does in the Swift.
 */
function ExpenseDonut({ categories, total }: { categories: { name: string; value: number }[]; total: number }) {
  const { money, percent, lang } = useSim();
  const [hovered, setHovered] = useState<number | null>(null);
  const active = hovered !== null ? categories[hovered] : null;

  return (
    <>
      <div style={{ display: 'grid', placeItems: 'center', minHeight: 250 }}>
        <Donut
          size={230}
          innerRatio={0.62}
          hovered={hovered}
          onHover={setHovered}
          label={t('Spending analytics', lang)}
          slices={categories.map((c, i) => ({ ...c, color: CHART_PALETTE[i % CHART_PALETTE.length] }))}
          center={
            <div style={{ display: 'grid', gap: 3, maxWidth: 130 }}>
              <span
                style={{
                  fontSize: TEXT.caption2,
                  fontWeight: 700,
                  letterSpacing: '1.3px',
                  color: active ? 'rgba(255,255,255,0.8)' : WC.textTertiary,
                }}
              >
                {active ? t(active.name, lang).toUpperCase() : t('EXPENSES', lang)}
              </span>
              <span style={{ fontSize: TEXT.headline, fontWeight: 700, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>
                {money(active ? active.value : total)}
              </span>
              {active && (
                <span style={{ fontSize: TEXT.caption2, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums' }}>
                  {percent(total > 0 ? (active.value / total) * 100 : 0)}
                </span>
              )}
            </div>
          }
        />
      </div>

      {/* prefix(6). No colour swatch: the Swift chart is `.chartLegend(.hidden)`
          and these rows are plain name/amount/share — the ring is the legend. */}
      <div style={{ display: 'grid', gap: 10 }}>
        {categories.slice(0, 6).map((category, i) => (
          <div
            key={category.name}
            style={{ display: 'flex', alignItems: 'center', gap: 10 }}
            onPointerEnter={() => setHovered(i)}
            onPointerLeave={() => setHovered(null)}
          >
            <span style={{ fontSize: TEXT.subheadline, color: 'rgba(255,255,255,0.88)', flex: 1, minWidth: 0 }}>
              {t(category.name, lang)}
            </span>
            <span style={{ display: 'grid', gap: 2, justifyItems: 'end' }}>
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{money(category.value)}</span>
              <span style={{ fontSize: TEXT.caption, color: WC.textSecondary, fontVariantNumeric: 'tabular-nums' }}>
                {percent(total > 0 ? (category.value / total) * 100 : 0)}
              </span>
            </span>
          </div>
        ))}
      </div>
    </>
  );
}

/** The 34pt tinted glyph tile both row types lead with. */
function IconTile({ tint, children }: { tint: string; children: React.ReactNode }) {
  return (
    <span
      style={{
        width: 34,
        height: 34,
        display: 'grid',
        placeItems: 'center',
        borderRadius: 10,
        background: `${tint}1c`,
        color: tint,
        flexShrink: 0,
      }}
    >
      {children}
    </span>
  );
}

/** EmptyState — a 46pt tinted tile over a centred caption. */
function EmptyState({ title, icon }: { title: string; icon: React.ReactNode }) {
  return (
    <div style={{ display: 'grid', justifyItems: 'center', gap: 10, padding: '28px 0' }}>
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
 * `.pickerStyle(.menu)` with `.tint(WCColor.primary)` — a green label and
 * chevron that drops a translucent list. The period titles are far too long for
 * a segmented control on a phone, which is why the app picks a menu here too.
 */
function MenuPicker<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: NoInfer<T>;
  options: { value: T; title: string }[];
  onChange: (next: NoInfer<T>) => void;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const current = options.find((o) => o.value === value);

  return (
    <div style={{ position: 'relative', flexShrink: 0 }}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={label}
        aria-expanded={open}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 4,
          padding: 0,
          border: 'none',
          background: 'transparent',
          cursor: 'pointer',
          color: WC.primary,
          fontSize: TEXT.subheadline,
          fontWeight: 500,
          whiteSpace: 'nowrap',
        }}
      >
        {current?.title}
        <ChevronDown size={13} strokeWidth={2.6} />
      </button>
      {open && (
        <Popover>
          {options.map((option) => (
            <MenuItem
              key={option.value}
              label={option.title}
              selected={option.value === value}
              onClick={() => {
                onChange(option.value);
                setOpen(false);
              }}
            />
          ))}
        </Popover>
      )}
    </div>
  );
}

/** The floating panel a SwiftUI Menu drops. */
function Popover({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        position: 'absolute',
        top: 'calc(100% + 8px)',
        insetInlineEnd: 0,
        zIndex: 4,
        minWidth: 180,
        padding: 5,
        display: 'grid',
        gap: 1,
        borderRadius: 14,
        background: 'rgba(30,34,44,0.94)',
        backdropFilter: 'blur(24px) saturate(160%)',
        WebkitBackdropFilter: 'blur(24px) saturate(160%)',
        border: '1px solid rgba(255,255,255,0.09)',
        boxShadow: '0 14px 32px rgba(0,0,0,0.45)',
      }}
    >
      {children}
    </div>
  );
}

function MenuItem({
  label,
  icon,
  selected,
  onClick,
}: {
  label: string;
  icon?: React.ReactNode;
  selected?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={selected ? 'true' : undefined}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        width: '100%',
        padding: '9px 10px',
        border: 'none',
        borderRadius: 10,
        cursor: 'pointer',
        textAlign: 'start',
        background: 'transparent',
        color: WC.textPrimary,
        font: 'inherit',
        fontSize: TEXT.subheadline,
      }}
    >
      {icon}
      <span style={{ flex: 1, minWidth: 0 }}>{label}</span>
      {selected && <Check size={14} strokeWidth={2.6} color={WC.primary} />}
    </button>
  );
}
