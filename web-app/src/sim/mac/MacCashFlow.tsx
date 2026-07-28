import { useState, type ReactNode } from 'react';
import {
  ArrowDownLeft,
  ArrowDownRight,
  ArrowLeftRight,
  ArrowUpRight,
  Banknote,
  Check,
  ChevronDown,
  CircleArrowDown,
  CircleArrowUp,
  CirclePlus,
  Pause,
  Pencil,
  Percent,
  Play,
  Plus,
  Repeat,
  Search,
  Trash2,
  Wallet,
  X,
} from 'lucide-react';
import { CHART_PALETTE, TEXT, WC } from '../tokens';
import { FinanceCard, MetricCard, SectionHeading } from '../ui';
import { BarLabels, Bars, Donut } from '../charts';
import { Segmented } from '../controls';
import { useSim } from '../SimProvider';
import { t } from '../strings';
import { cashFlowTotals, monthlyCashFlow, recurring, topExpenses, totals, transactions } from '../data';

/**
 * A port of Sources/macOS/Views/MacCashFlowView.swift.
 *
 * The view is two panes behind a MacSelectorIsland: Overview (six summary cards,
 * the cash-flow trend, the expense ring, recent activity and the recurring
 * schedules) and Transactions (the filter bar plus the ledger). Section order,
 * headings, subtitles, metric titles and accents are that file's, including the
 * details that differ from the Dashboard — Recent Activity is subtitled "Your
 * latest cash flow" here, not "Your latest recorded cash movements".
 *
 * The pane is 1220pt wide inside MacWindow, so the `proxy.size.width >= 1_090`
 * branch is the one that renders: trend 55% / categories 45%, then activity 45% /
 * recurring 55%.
 */

const CASH_FLOW_RANGES = ['3M', '6M', '12M'] as const;
type CashFlowRange = (typeof CASH_FLOW_RANGES)[number];

/** MacCashFlowTab */
const TABS = ['Overview', 'Transactions'] as const;
type Tab = (typeof TABS)[number];

/** MacTransactionTypeFilter */
const TYPE_FILTERS = ['all', 'income', 'expense'] as const;
type TypeFilter = (typeof TYPE_FILTERS)[number];

/** AppSettings.redactionToken — SimProvider applies it inside money()/percent(), not as an export. */
const REDACTION = '••••';

/**
 * The two AnalyticsPeriod pickers have *different* defaults in the Swift —
 * `analyticsPeriod = .all` behind the expense ring, `transactionPeriod =
 * .thirtyDays` in the filter bar. The demo ledger is a single 30-day window, so
 * each is fixed at its real default rather than filtering nothing. Neither title
 * is in the extracted catalogue, so both are plain English (see report).
 */
const EXPENSE_PERIOD_LABEL = 'All Time';
const TRANSACTION_PERIOD_LABEL = 'Last 30 Days';

export function MacCashFlow() {
  const { money, percent, lang, privacy } = useSim();
  const [tab, setTab] = useState<Tab>('Overview');
  const [cashFlowRange, setCashFlowRange] = useState<CashFlowRange>('6M');
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [search, setSearch] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [hoveredCategory, setHoveredCategory] = useState<number | null>(null);

  const month = monthlyCashFlow[monthlyCashFlow.length - 1];
  const netSavings = month.income - month.expenses;
  const savingsRate = (netSavings / month.income) * 100;

  const months = monthlyCashFlow.slice(cashFlowRange === '3M' ? -3 : -6);
  // 6M/12M spans the whole ledger, which data.ts already totals; 3M re-totals the slice.
  const rangeTotals =
    cashFlowRange === '3M'
      ? months.reduce((sum, m) => ({ income: sum.income + m.income, expenses: sum.expenses + m.expenses }), {
          income: 0,
          expenses: 0,
        })
      : cashFlowTotals;
  const rangeNet = rangeTotals.income - rangeTotals.expenses;

  const expenseSlices = topExpenses.map((expense, i) => ({
    name: t(expense.name, lang),
    value: expense.value,
    color: CHART_PALETTE[i % CHART_PALETTE.length],
  }));
  const expenseTotal = expenseSlices.reduce((sum, slice) => sum + slice.value, 0);
  const activeSlice = hoveredCategory !== null ? expenseSlices[hoveredCategory] : null;

  const query = search.trim().toLowerCase();
  const filtered = transactions.filter((tx) => {
    const matchesType = typeFilter === 'all' || tx.kind === typeFilter;
    const matchesSearch =
      query === '' || tx.category.toLowerCase().includes(query) || t(tx.category, lang).toLowerCase().includes(query);
    return matchesType && matchesSearch;
  });

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      {/* The selector island is centred in the pane; the toolbar's primaryAction menu sits trailing. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '16px 24px' }}>
        <span style={{ flex: 1 }} />
        <SelectorIsland value={tab} onChange={setTab} options={TABS} render={(option) => t(option, lang)} />
        <div style={{ flex: 1, display: 'flex', justifyContent: 'flex-end', position: 'relative' }}>
          <button
            type="button"
            onClick={() => setAddOpen((open) => !open)}
            aria-expanded={addOpen}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              padding: '7px 14px',
              border: 'none',
              borderRadius: 20,
              cursor: 'pointer',
              background: WC.primary,
              color: 'rgba(0,0,0,0.85)',
              fontFamily: 'inherit',
              fontSize: TEXT.footnote,
              fontWeight: 600,
            }}
          >
            <Plus size={13} strokeWidth={3} /> {t('Add Transaction', lang)}
            <ChevronDown size={12} strokeWidth={3} />
          </button>
          {addOpen && (
            <div
              style={{
                position: 'absolute',
                top: 38,
                right: 0,
                zIndex: 2,
                display: 'grid',
                gap: 2,
                padding: 5,
                minWidth: 210,
                borderRadius: 10,
                background: 'rgba(30,33,40,0.96)',
                backdropFilter: 'blur(20px)',
                border: `1px solid ${WC.border}`,
                boxShadow: '0 12px 28px rgba(0,0,0,0.45)',
              }}
            >
              {/* "plus.circle" / "repeat.circle" — lucide has no circled repeat, so the
                  bare glyph stands in for the second. */}
              <MenuItem icon={<CirclePlus size={13} strokeWidth={2.2} />} label={t('One-Time Transaction', lang)} />
              <MenuItem icon={<Repeat size={13} strokeWidth={2.4} />} label={t('Recurring Transaction', lang)} />
            </div>
          )}
        </div>
      </div>

      {tab === 'Overview' ? (
        <div style={{ display: 'grid', gap: 20, padding: '4px 24px 36px', alignContent: 'start' }}>
          {/* summaryCards — six across at this pane width. */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 16 }}>
            <MetricCard
              title={t('Monthly Income', lang)}
              value={money(month.income)}
              icon={<ArrowUpRight size={15} strokeWidth={2.4} />}
            />
            <MetricCard
              title={t('Monthly Expenses', lang)}
              value={money(month.expenses)}
              icon={<ArrowDownRight size={15} strokeWidth={2.4} />}
              accent={WC.destructive}
            />
            <MetricCard
              title={t('Net Savings', lang)}
              value={money(netSavings)}
              icon={<Wallet size={15} strokeWidth={2.4} />}
              accent={netSavings >= 0 ? WC.primary : WC.destructive}
            />
            <MetricCard title={t('Savings Rate', lang)} value={percent(savingsRate)} icon={<Percent size={15} strokeWidth={2.4} />} />
            <MetricCard
              title={t('Transactions', lang)}
              /* monthlyTransactionCount — a count, so it redacts rather than converts. */
              value={privacy ? REDACTION : String(transactions.length)}
              icon={<ArrowLeftRight size={15} strokeWidth={2.4} />}
            />
            <MetricCard
              title={t('Total Cash', lang)}
              value={money(totals.cash)}
              icon={<Banknote size={15} strokeWidth={2.4} />}
              accent={totals.cash >= 0 ? WC.primary : WC.destructive}
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(340px, 55fr) 45fr', gap: 20, alignItems: 'stretch' }}>
            {/* cashFlowTrendCard */}
            <FinanceCard style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <SectionHeading title={t('Cash Flow', lang)} subtitle={t('Income and expenses by month', lang)} />
                </div>
                <Segmented options={CASH_FLOW_RANGES} value={cashFlowRange} onChange={setCashFlowRange} label="Cash-flow range" compact />
              </div>

              {privacy ? (
                <Concealed title={t('Cash-flow chart concealed', lang)} height={244} />
              ) : (
                <div>
                  <Bars data={months} height={244} label={t('Income and expenses by month', lang)} />
                  <BarLabels data={months} />
                </div>
              )}

              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 20 }}>
                <LegendItem color={WC.primary} title={t('Income', lang)} value={money(rangeTotals.income)} />
                <LegendItem color={WC.destructive} title={t('Expenses', lang)} value={money(rangeTotals.expenses)} />
                <span style={{ flex: 1 }} />
                <span style={{ display: 'grid', gap: 3, justifyItems: 'end' }}>
                  <span
                    style={{
                      fontSize: TEXT.caption2,
                      fontWeight: 700,
                      letterSpacing: '1px',
                      textTransform: 'uppercase',
                      color: WC.textTertiary,
                    }}
                  >
                    {cashFlowRange} NET
                  </span>
                  <span
                    style={{
                      fontSize: TEXT.subheadline,
                      fontWeight: 700,
                      fontVariantNumeric: 'tabular-nums',
                      color: rangeNet >= 0 ? WC.primary : WC.destructive,
                    }}
                  >
                    {money(rangeNet)}
                  </span>
                </span>
              </div>
            </FinanceCard>

            {/* expenseCategoriesCard — chartLegend is hidden in the Swift; the ring's
                centre readout is what names a category, on hover. */}
            <FinanceCard style={{ display: 'grid', gap: 16, alignContent: 'start' }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <SectionHeading title={t('Expense Categories', lang)} subtitle={t('Breakdown of recorded spending', lang)} />
                </div>
                <PickerPill label={EXPENSE_PERIOD_LABEL} width={142} />
              </div>
              <div style={{ display: 'grid', placeItems: 'center', minHeight: 250 }}>
                <Donut
                  slices={expenseSlices}
                  size={236}
                  innerRatio={0.62}
                  hovered={hoveredCategory}
                  onHover={setHoveredCategory}
                  label={t('Expense Categories', lang)}
                  center={
                    activeSlice ? (
                      <div style={{ display: 'grid', gap: 3, maxWidth: 132 }}>
                        <span
                          style={{
                            fontSize: TEXT.caption2,
                            fontWeight: 700,
                            letterSpacing: '1.3px',
                            textTransform: 'uppercase',
                            color: 'rgba(255,255,255,0.8)',
                          }}
                        >
                          {activeSlice.name}
                        </span>
                        <span
                          style={{
                            fontSize: TEXT.headline,
                            fontWeight: 700,
                            fontVariantNumeric: 'tabular-nums',
                            whiteSpace: 'nowrap',
                          }}
                        >
                          {money(activeSlice.value)}
                        </span>
                        <span style={{ fontSize: TEXT.caption2, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums' }}>
                          {percent(expenseTotal > 0 ? (activeSlice.value / expenseTotal) * 100 : 0)}
                        </span>
                      </div>
                    ) : (
                      <div style={{ display: 'grid', gap: 3, maxWidth: 132 }}>
                        <span style={{ fontSize: TEXT.caption2, fontWeight: 700, letterSpacing: '1.3px', color: WC.textTertiary }}>
                          {t('EXPENSES', lang)}
                        </span>
                        <span
                          style={{
                            fontSize: TEXT.headline,
                            fontWeight: 700,
                            fontVariantNumeric: 'tabular-nums',
                            whiteSpace: 'nowrap',
                          }}
                        >
                          {money(expenseTotal)}
                        </span>
                      </div>
                    )
                  }
                />
              </div>
            </FinanceCard>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(340px, 45fr) 55fr', gap: 20, alignItems: 'stretch' }}>
            {/* recentActivityCard — finance.transactions.prefix(6) */}
            <FinanceCard style={{ display: 'grid', gap: 14, alignContent: 'start' }}>
              <SectionHeading title={t('Recent Activity', lang)} subtitle={t('Your latest cash flow', lang)} />
              <div style={{ display: 'grid' }}>
                {transactions.slice(0, 6).map((tx, i, rows) => {
                  const income = tx.kind === 'income';
                  const tint = income ? WC.primary : WC.destructive;
                  return (
                    <div key={tx.id}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 0' }}>
                        <span
                          style={{
                            width: 32,
                            height: 32,
                            flexShrink: 0,
                            display: 'grid',
                            placeItems: 'center',
                            borderRadius: 9,
                            background: `${tint}1c`,
                            color: tint,
                          }}
                        >
                          {income ? <ArrowDownLeft size={13} strokeWidth={2.8} /> : <ArrowUpRight size={13} strokeWidth={2.8} />}
                        </span>
                        <div style={{ display: 'grid', gap: 3, flex: 1, minWidth: 0 }}>
                          <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: 'rgba(255,255,255,0.84)' }}>
                            {t(tx.category, lang)}
                          </span>
                          {/* ActivityRow falls back to the transaction type when there is no description. */}
                          <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>
                            {t(income ? 'Income' : 'Expense', lang)}
                          </span>
                        </div>
                        <div style={{ display: 'grid', gap: 3, justifyItems: 'end' }}>
                          <span
                            style={{
                              fontSize: TEXT.subheadline,
                              fontWeight: 600,
                              fontVariantNumeric: 'tabular-nums',
                              color: income ? WC.primary : 'rgba(255,255,255,0.8)',
                            }}
                          >
                            {signed(money(Math.abs(tx.amount)), income, privacy)}
                          </span>
                          <span style={{ fontSize: TEXT.caption2, color: WC.textFaint }}>{tx.day}</span>
                        </div>
                      </div>
                      {i < rows.length - 1 && <div style={{ height: 1, marginLeft: 44, background: WC.border }} />}
                    </div>
                  );
                })}
              </div>
            </FinanceCard>

            {/* recurringTransactionsCard */}
            <FinanceCard style={{ display: 'grid', gap: 14, alignContent: 'start' }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <SectionHeading title={t('Recurring Transactions', lang)} subtitle={t('Due schedules catch up on open', lang)} />
                </div>
                <span
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 5,
                    fontSize: TEXT.footnote,
                    fontWeight: 500,
                    color: WC.primary,
                  }}
                >
                  <Plus size={12} strokeWidth={2.6} /> {t('Add', lang)}
                </span>
              </div>
              <div style={{ display: 'grid', gap: 10 }}>
                {recurring.map((schedule) => {
                  const income = schedule.kind === 'income';
                  const tint = income ? WC.primary : WC.destructive;
                  return (
                    <div
                      key={schedule.id}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: 14,
                        padding: 12,
                        borderRadius: 8,
                        background: WC.cardElevated,
                      }}
                    >
                      {/* "arrow.up.right.circle.fill" / "arrow.down.right.circle.fill" —
                          lucide carries no diagonal arrow inside a circle, so the vertical
                          pair stands in; the direction, which is what reads, is the same. */}
                      <span style={{ color: tint, display: 'grid', flexShrink: 0 }}>
                        {income ? <CircleArrowUp size={22} strokeWidth={1.9} /> : <CircleArrowDown size={22} strokeWidth={1.9} />}
                      </span>
                      <div style={{ display: 'grid', gap: 5, flex: 1, minWidth: 0 }}>
                        <span style={{ fontSize: TEXT.headline, fontWeight: 600 }}>{t(schedule.category, lang)}</span>
                        <span style={{ display: 'flex', gap: 10, fontSize: TEXT.caption, color: WC.textTertiary }}>
                          <span>{schedule.cadence}</span>
                          {schedule.active ? (
                            <span>Next {schedule.nextDue}</span>
                          ) : (
                            <span style={{ color: WC.warning }}>{t('Paused', lang)}</span>
                          )}
                          <span>{t('No end date', lang)}</span>
                        </span>
                      </div>
                      <span
                        style={{
                          minWidth: 140,
                          textAlign: 'end',
                          fontSize: TEXT.headline,
                          fontWeight: 600,
                          fontVariantNumeric: 'tabular-nums',
                          color: tint,
                        }}
                      >
                        {signed(money(schedule.amount), income, privacy)}
                      </span>
                      <span style={{ display: 'flex', gap: 4, flexShrink: 0, color: WC.textTertiary }}>
                        <IconButton label={schedule.active ? 'Pause schedule' : 'Resume schedule'}>
                          {schedule.active ? <Pause size={12} strokeWidth={2.4} /> : <Play size={12} strokeWidth={2.4} />}
                        </IconButton>
                        <IconButton label={t('Finish schedule', lang)}>
                          <Check size={12} strokeWidth={2.6} />
                        </IconButton>
                        <IconButton label={t('Edit schedule', lang)}>
                          <Pencil size={12} strokeWidth={2.4} />
                        </IconButton>
                        <IconButton label="Delete schedule" tint={WC.destructive}>
                          <Trash2 size={12} strokeWidth={2.4} />
                        </IconButton>
                      </span>
                    </div>
                  );
                })}
              </div>
            </FinanceCard>
          </div>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 10, padding: '14px 24px 36px', alignContent: 'start' }}>
          {/* transactionFilters */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 24,
              padding: '14px 20px',
              borderRadius: 14,
              background: 'rgba(255,255,255,0.045)',
              backdropFilter: 'blur(18px) saturate(140%)',
              WebkitBackdropFilter: 'blur(18px) saturate(140%)',
              border: `1px solid ${WC.border}`,
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textTertiary }}>{t('Type', lang)}</span>
              <FilterSegmented
                value={typeFilter}
                onChange={setTypeFilter}
                options={TYPE_FILTERS}
                /* "All" has no entry in the catalogue — see the report. */
                render={(option) => (option === 'all' ? 'All' : t(option === 'income' ? 'Income' : 'Expense', lang))}
              />
            </div>

            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                width: 200,
                padding: '6px 10px',
                borderRadius: 8,
                background: 'rgba(255,255,255,0.05)',
              }}
            >
              <Search size={13} strokeWidth={2.2} color={WC.textTertiary} />
              <input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search"
                aria-label="Search"
                style={{
                  flex: 1,
                  minWidth: 0,
                  border: 'none',
                  outline: 'none',
                  background: 'transparent',
                  color: WC.textPrimary,
                  fontFamily: 'inherit',
                  fontSize: TEXT.footnote,
                }}
              />
              {search !== '' && (
                <button
                  type="button"
                  onClick={() => setSearch('')}
                  aria-label={t('Clear search', lang)}
                  style={{ border: 'none', background: 'none', padding: 0, cursor: 'pointer', color: WC.textTertiary, display: 'grid' }}
                >
                  <X size={13} strokeWidth={2.4} />
                </button>
              )}
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textTertiary }}>{t('Period', lang)}</span>
              <PickerPill label={TRANSACTION_PERIOD_LABEL} width={160} />
            </div>

            <span style={{ fontSize: TEXT.caption, fontVariantNumeric: 'tabular-nums', color: WC.textTertiary }}>
              Showing {filtered.length} of {transactions.length}
            </span>
          </div>

          {/* transactionTable — despite the name it is a LazyVGrid of
              GridItem(.adaptive(minimum: 360), spacing: 16) filled with transactionCard,
              not a Table. At this pane width the adaptive grid resolves to three columns. */}
          {filtered.length === 0 ? (
            /* ContentUnavailableView. The macOS wording ("No Matching Transactions" /
               "Change the search, type, or period filters.") is not among the 132
               extracted keys; the catalogue's equivalent iOS pair is used so the state
               still translates. */
            <div style={{ display: 'grid', gap: 6, justifyItems: 'center', padding: '40px 20px 24px' }}>
              <EmptyGlyph />
              <span style={{ fontSize: TEXT.headline, fontWeight: 600, color: WC.textSecondary }}>
                {t('No transactions found', lang)}
              </span>
              <span style={{ fontSize: TEXT.subheadline, color: WC.textTertiary }}>
                {t('No transactions match these filters', lang)}
              </span>
            </div>
          ) : (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))',
                gap: 16,
                paddingTop: 14,
                alignItems: 'stretch',
              }}
            >
              {filtered.map((tx) => {
                const income = tx.kind === 'income';
                const tint = income ? WC.primary : WC.destructive;
                return (
                  /* transactionCard(for:) */
                  <FinanceCard key={tx.id} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      <div style={{ display: 'grid', gap: 4, flex: 1, minWidth: 0 }}>
                        <span style={{ fontSize: TEXT.headline, fontWeight: 600, color: WC.textPrimary }}>
                          {t(tx.category, lang)}
                        </span>
                        {/* Label(type.title, systemImage:) — glyph then title, both tinted. */}
                        <span
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: 6,
                            fontSize: TEXT.subheadline,
                            fontWeight: 600,
                            color: tint,
                          }}
                        >
                          {income ? <ArrowDownLeft size={13} strokeWidth={2.8} /> : <ArrowUpRight size={13} strokeWidth={2.8} />}
                          {t(income ? 'Income' : 'Expense', lang)}
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: TEXT.headline,
                          fontWeight: 600,
                          fontVariantNumeric: 'tabular-nums',
                          color: tint,
                          flexShrink: 0,
                        }}
                      >
                        {signed(money(Math.abs(tx.amount)), income, privacy)}
                      </span>
                    </div>

                    {/* The description row and the "generated from a recurring schedule"
                        repeat badge both need fields the demo ledger does not carry, so
                        neither branch is drawn rather than invented. */}

                    {/* Spacer(minLength: 0) then Divider() — the footer sits on the floor
                        of the card so a row of cards agrees on its baseline. */}
                    <div style={{ marginTop: 'auto', height: 1, background: WC.border }} />

                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      <div style={{ display: 'grid', gap: 4, flex: 1, minWidth: 0 }}>
                        <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>{t('Date', lang)}</span>
                        <span style={{ fontSize: TEXT.subheadline, color: WC.textPrimary, fontVariantNumeric: 'tabular-nums' }}>
                          {tx.day}
                        </span>
                      </div>
                      <span style={{ display: 'flex', gap: 4, flexShrink: 0 }}>
                        <IconButton label={t('Edit Transaction', lang)}>
                          <Pencil size={12} strokeWidth={2.4} />
                        </IconButton>
                        <IconButton label={t('Delete Transaction', lang)} tint={WC.destructive}>
                          <Trash2 size={12} strokeWidth={2.4} />
                        </IconButton>
                      </span>
                    </div>
                  </FinanceCard>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** The +/− prefix ActivityRow puts in front of an amount — dropped entirely when redacted. */
function signed(formatted: string, income: boolean, privacy: boolean) {
  return privacy ? formatted : `${income ? '+' : '−'}${formatted}`;
}

/** MacSelectorIsland — a 0.12-white capsule with hairline dividers between tabs. */
function SelectorIsland<T extends string>({
  options,
  value,
  onChange,
  render,
}: {
  options: readonly T[];
  value: NoInfer<T>;
  onChange: (next: NoInfer<T>) => void;
  render: (option: T) => string;
}) {
  return (
    <div
      role="tablist"
      aria-label="Cash flow section"
      style={{
        display: 'flex',
        alignItems: 'center',
        padding: 4,
        borderRadius: 999,
        background: '#1f1f1f',
        border: '1px solid rgba(255,255,255,0.1)',
        boxShadow: '0 2px 4px rgba(0,0,0,0.2)',
        flexShrink: 0,
      }}
    >
      {options.map((option, i) => (
        <div key={option} style={{ display: 'flex', alignItems: 'center' }}>
          <button
            type="button"
            role="tab"
            aria-selected={option === value}
            onClick={() => onChange(option)}
            style={{
              padding: '6px 16px',
              border: 'none',
              borderRadius: 999,
              cursor: 'pointer',
              fontFamily: 'inherit',
              fontSize: 14,
              fontWeight: 500,
              color: option === value ? '#fff' : 'rgba(255,255,255,0.8)',
              background: option === value ? 'rgba(255,255,255,0.18)' : 'transparent',
              transition: 'background-color 200ms ease, color 200ms ease',
            }}
          >
            {render(option)}
          </button>
          {i < options.length - 1 && (
            <span style={{ width: 1, height: 14, margin: '0 6px', background: 'rgba(255,255,255,0.2)' }} />
          )}
        </div>
      ))}
    </div>
  );
}

/**
 * The `.segmented` picker in the filter bar. `Segmented` from controls.tsx renders
 * its option values verbatim, which cannot carry a translated label, so this is the
 * same trough with a separate label mapping.
 */
function FilterSegmented<T extends string>({
  options,
  value,
  onChange,
  render,
}: {
  options: readonly T[];
  value: NoInfer<T>;
  onChange: (next: NoInfer<T>) => void;
  render: (option: T) => string;
}) {
  return (
    <div style={{ display: 'flex', gap: 2, width: 220, padding: 2, borderRadius: 9, background: 'rgba(118,118,128,0.24)' }}>
      {options.map((option) => {
        const selected = option === value;
        return (
          <button
            key={option}
            type="button"
            aria-pressed={selected}
            onClick={() => onChange(option)}
            style={{
              flex: 1,
              padding: '5px 0',
              border: 'none',
              borderRadius: 7,
              cursor: 'pointer',
              fontFamily: 'inherit',
              fontSize: 13,
              fontWeight: selected ? 600 : 500,
              color: selected ? WC.textPrimary : WC.textSecondary,
              background: selected ? 'rgba(120,124,134,0.72)' : 'transparent',
              boxShadow: selected ? '0 1px 3px rgba(0,0,0,0.28)' : 'none',
              transition: 'background-color 150ms ease, color 150ms ease',
            }}
          >
            {render(option)}
          </button>
        );
      })}
    </div>
  );
}

/** A `.pickerStyle(.menu)` pop-up button. */
function PickerPill({ label, width }: { label: string; width: number }) {
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 8,
        width,
        padding: '5px 8px 5px 10px',
        borderRadius: 6,
        background: 'rgba(255,255,255,0.07)',
        border: `1px solid ${WC.border}`,
        fontSize: TEXT.footnote,
        color: WC.textSecondary,
        flexShrink: 0,
      }}
    >
      {label}
      <ChevronDown size={12} strokeWidth={2.4} color={WC.textTertiary} />
    </span>
  );
}

function MenuItem({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <span
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 9,
        padding: '7px 10px',
        borderRadius: 6,
        fontSize: TEXT.footnote,
        color: WC.textPrimary,
      }}
    >
      <span style={{ color: WC.primary, display: 'grid' }}>{icon}</span>
      {label}
    </span>
  );
}

function IconButton({ children, label, tint = WC.textTertiary }: { children: ReactNode; label: string; tint?: string }) {
  return (
    <span
      role="img"
      aria-label={label}
      title={label}
      style={{
        width: 22,
        height: 22,
        display: 'grid',
        placeItems: 'center',
        borderRadius: 5,
        background: 'rgba(255,255,255,0.05)',
        color: tint,
      }}
    >
      {children}
    </span>
  );
}

/** CashFlowLegendItem — a 9×24 rounded swatch, then the title over the value. */
function LegendItem({ color, title, value }: { color: string; title: string; value: string }) {
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
      <span style={{ width: 9, height: 24, borderRadius: 3, background: color, flexShrink: 0 }} />
      <span style={{ display: 'grid', gap: 2 }}>
        <span style={{ fontSize: TEXT.caption2, fontWeight: 500, color: WC.textTertiary }}>{title}</span>
        <span
          style={{ fontSize: TEXT.caption, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: 'rgba(255,255,255,0.82)' }}
        >
          {value}
        </span>
      </span>
    </span>
  );
}

/** EmptyState with "eye.slash" — what macOS puts where the bar chart goes in privacy mode. */
function Concealed({ title, height }: { title: string; height: number }) {
  return (
    <div
      style={{
        minHeight: height,
        display: 'grid',
        placeItems: 'center',
        borderRadius: 15,
        background: 'rgba(0,0,0,0.14)',
        border: '1px solid rgba(255,255,255,0.05)',
      }}
    >
      <div style={{ display: 'grid', gap: 10, justifyItems: 'center' }}>
        <span
          style={{
            width: 46,
            height: 46,
            display: 'grid',
            placeItems: 'center',
            borderRadius: 14,
            background: `${WC.primary}17`,
          }}
        >
          <EyeSlash />
        </span>
        <span style={{ fontSize: TEXT.subheadline, fontWeight: 500, color: WC.textSecondary }}>{title}</span>
      </div>
    </div>
  );
}

/** SF Symbol "eye.slash" at EmptyState's 22pt. */
function EyeSlash() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={WC.primary} strokeOpacity={0.78} strokeWidth="1.8" strokeLinecap="round">
      <path d="M10.7 5.1A9.6 9.6 0 0 1 12 5c5 0 9 5 9 7a10.6 10.6 0 0 1-2.2 3M6.3 6.4C3.9 7.9 3 10.3 3 12c0 2 4 7 9 7 1.8 0 3.4-.6 4.7-1.5" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2M3 3l18 18" />
    </svg>
  );
}

/** SF Symbol "line.3.horizontal.decrease.circle" — the filtered-to-nothing glyph. */
function EmptyGlyph() {
  return (
    <span
      style={{
        width: 46,
        height: 46,
        display: 'grid',
        placeItems: 'center',
        borderRadius: 14,
        background: `${WC.primary}17`,
        marginBottom: 4,
      }}
    >
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={WC.primary} strokeOpacity={0.78} strokeWidth="1.9" strokeLinecap="round">
        <circle cx="12" cy="12" r="9" />
        <path d="M8 9.5h8M9 12h6M10.5 14.5h3" />
      </svg>
    </span>
  );
}
