import { Children, Fragment, useState, type CSSProperties, type ReactNode } from 'react';
import {
  ArrowLeftRight,
  Bitcoin,
  Camera,
  Check,
  ChevronDown,
  ChevronRight,
  CircleCheck,
  CircleDollarSign,
  Cloud,
  CloudOff,
  CreditCard,
  Eye,
  EyeOff,
  FilePlus,
  HardDrive,
  Landmark,
  RefreshCw,
  Repeat,
  ShieldCheck,
  SlidersHorizontal,
  Stethoscope,
  TrendingUp,
  Trash2,
  Upload,
} from 'lucide-react';
import { TEXT, WC, insetRow } from '../tokens';
import { FinanceCard } from '../ui';
import { Switch } from '../controls';
import { CURRENCIES, useSim, type CurrencyCode } from '../SimProvider';
import { LANGUAGES, t, type Lang } from '../strings';
import { crypto, holdings, liabilities, recurring, trail, transactions } from '../data';

/**
 * A port of Sources/iOS/Views/SettingsView.swift.
 *
 * Section order follows that file exactly — Market Data sits between Custom
 * Categories and iCloud Sync, where `marketDataSection` is invoked, not at the
 * end. Row labels, footer captions, accent colours and the "Offline fallback"
 * exchange-rate state are the app's own.
 *
 * Three controls here are real, because they are what the rest of the page is
 * demonstrating: Base Currency, Privacy Mode and Language write straight into
 * the simulation context and re-render every other device on the page. The rest
 * (biometric lock, iCloud sync, export/import, API keys) hold local state or
 * none at all — the app's chrome without the app's side effects.
 *
 * Where lucide has no equivalent of an SF Symbol the nearest glyph is used:
 * CircleDollarSign for `coloncurrencysign`, ShieldCheck for `lock.shield`,
 * CircleCheck for `checkmark.icloud`, and RefreshCw for both
 * `arrow.triangle.2.circlepath` and `.circlepath.icloud`.
 */

/**
 * SwiftUI tints Button labels inside a `List` with the list's `.tint`, which
 * SettingsView sets to WCColor.primary — so every action row reads green and the
 * one destructive row reads red. Rows built from `Label`/`HStack` stay white.
 */
const ACTION = WC.primary;

/** SwiftUI `.blue` on dark, for the storage-mode chip. */
const BLUE = '#0a84ff';

/**
 * `AppSettings` keeps the demo rate table private to SimProvider, so the rates
 * shown here mirror it rather than reaching into a shared file. Units per 1 EUR;
 * these must stay equal to `RATES` in SimProvider.tsx. They are a frozen demo
 * set — nothing in the simulation calls the ECB — which is what the caption at
 * the bottom of that section says.
 */
const DEMO_RATES: Record<CurrencyCode, number> = { EUR: 1, USD: 1.0876, GBP: 0.8412, CHF: 0.9385 };

/** `Currency.displayName` — Locale.localizedString(forCurrencyCode:). */
function currencyName(code: CurrencyCode, lang: Lang): string {
  try {
    return new Intl.DisplayNames([lang], { type: 'currency' }).of(code) ?? code;
  } catch {
    return code;
  }
}

export function SettingsScreen() {
  const { currency, setCurrency, privacy, setPrivacy, lang, setLang } = useSim();
  const [biometricLock, setBiometricLock] = useState(false);
  const [iCloudSync, setICloudSync] = useState(false);

  const rateFormat = new Intl.NumberFormat(lang, { minimumFractionDigits: 2, maximumFractionDigits: 4 });

  /**
   * `finance.data.snapshots.count`. data.ts has no snapshot array; its net-worth
   * history is the ALL trail, and `appendSnapshot` writes one snapshot per day,
   * so the span in days IS the count. Read off `daysAgo` rather than
   * `trail('ALL').length` because that array is thinned for SVG path length —
   * counting it would make a Settings row move whenever the chart's point budget
   * changes.
   */
  const snapshotCount = trail('ALL')[0].daysAgo + 1;

  return (
    <div style={{ display: 'grid', gap: 22, padding: '0 16px 28px', alignContent: 'start' }}>
      {/* .navigationTitle("Settings"), .navigationBarTitleDisplayMode(.large) */}
      <span style={{ fontSize: TEXT.largeTitle, fontWeight: 700, letterSpacing: '-0.4px', paddingTop: 6 }}>
        {t('Settings', lang)}
      </span>

      {/* --- settingsOverview ------------------------------------------- */}
      <FinanceCard style={{ display: 'grid', gap: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 13 }}>
          <span
            style={{
              width: 42,
              height: 42,
              flexShrink: 0,
              display: 'grid',
              placeItems: 'center',
              borderRadius: 12,
              background: 'rgba(31,219,153,0.11)',
              color: WC.primary,
            }}
          >
            <SlidersHorizontal size={18} strokeWidth={2.4} />
          </span>
          <div style={{ display: 'grid', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: TEXT.headline, fontWeight: 600 }}>{t('Your preferences', lang)}</span>
            <span style={{ fontSize: TEXT.caption, color: WC.textTertiary }}>
              {t('Privacy, sync, currency, and market data', lang)}
            </span>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <Chip icon={<CircleDollarSign size={12} strokeWidth={2.6} />} label={currency} color={WC.accent} />
          <Chip
            icon={privacy ? <EyeOff size={12} strokeWidth={2.6} /> : <Eye size={12} strokeWidth={2.6} />}
            label={privacy ? 'Private' : 'Visible'}
            color={WC.primary}
          />
          <Chip
            icon={iCloudSync ? <Cloud size={12} strokeWidth={2.6} /> : <HardDrive size={12} strokeWidth={2.6} />}
            label={iCloudSync ? 'iCloud' : 'Local'}
            color={BLUE}
          />
        </div>
      </FinanceCard>

      {/* --- Region & Language — both pickers are live ------------------- */}
      <Group title={t('Region & Language', lang)}>
        <PickerRow
          label={t('Language', lang)}
          selected={lang}
          options={LANGUAGES.map((l) => ({ id: l.code, label: l.label }))}
          onSelect={setLang}
        />
        <PickerRow
          /* "Base Currency" has no entry in the catalogue; see the report. */
          label="Base Currency"
          selected={currency}
          options={CURRENCIES.map((code) => ({ id: code, label: `${currencyName(code, lang)} (${code})` }))}
          onSelect={setCurrency}
        />
      </Group>

      {/* --- Privacy ------------------------------------------------------ */}
      <Group title={t('Privacy', lang)}>
        <ToggleRow
          icon={privacy ? <EyeOff size={17} strokeWidth={2.2} /> : <Eye size={17} strokeWidth={2.2} />}
          label={t('Privacy Mode', lang)}
          checked={privacy}
          onChange={setPrivacy}
        />
      </Group>

      {/* --- Security ----------------------------------------------------- */}
      <Group title={t('Security', lang)}>
        <ToggleRow
          icon={<ShieldCheck size={17} strokeWidth={2.2} />}
          /* "\(appLock.biometryName) App Lock" — Face ID on a Pro Max. */
          label="Face ID App Lock"
          checked={biometricLock}
          onChange={setBiometricLock}
        />
        <Caption>When enabled, Wealth Compass Tracker locks whenever the app leaves the foreground.</Caption>
      </Group>

      {/* --- Custom Categories — the empty state, as a fresh install shows it */}
      <Group title={t('Custom Categories', lang)}>
        <CategoryGroup title={t('Income', lang)} empty="No custom income categories yet." />
        <CategoryGroup title={t('Expense', lang)} empty="No custom expense categories yet." />
      </Group>

      {/* --- Market Data --------------------------------------------------- */}
      <Group title={t('Market Data', lang)}>
        <Row
          icon={<TrendingUp size={17} strokeWidth={2.2} />}
          label={t('Finnhub API Key', lang)}
          value="Not Set"
          trailing={<ChevronRight size={14} strokeWidth={2.8} color={WC.textSecondary} />}
        />
        <Row
          icon={<Bitcoin size={17} strokeWidth={2.2} />}
          label={t('CoinGecko API Key', lang)}
          value="Not Set"
          trailing={<ChevronRight size={14} strokeWidth={2.8} color={WC.textSecondary} />}
        />
        <Row icon={<RefreshCw size={17} strokeWidth={2.2} />} label="Refresh Market Data" tint={ACTION} />
      </Group>

      {/* --- iCloud Sync ---------------------------------------------------- */}
      <Group title={t('iCloud Sync', lang)}>
        <ToggleRow
          icon={<Cloud size={17} strokeWidth={2.2} />}
          label={t('Sync Data with iCloud', lang)}
          checked={iCloudSync}
          onChange={setICloudSync}
        />
        <Caption>
          Your financial data stays available locally and syncs across your devices through your private CloudKit
          database.
        </Caption>
        <Caption>Preferences like currency, categories, and language are set per device and don't sync.</Caption>
        {/* CloudSyncStatus — .disabled / .upToDate(nil), both `.ok` severity. */}
        <Row
          label="Status"
          trailing={
            <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: WC.textSecondary }}>
              {iCloudSync ? <CircleCheck size={15} strokeWidth={2.2} /> : <CloudOff size={15} strokeWidth={2.2} />}
              <span style={{ fontSize: TEXT.subheadline }}>{iCloudSync ? 'Up to Date' : 'Off'}</span>
            </span>
          }
        />
        <Caption>{iCloudSync ? 'Local data is ready to sync.' : 'Your data remains on this device.'}</Caption>
        {iCloudSync && (
          <Row icon={<RefreshCw size={17} strokeWidth={2.2} />} label={t('Force Sync iCloud', lang)} tint={ACTION} />
        )}
      </Group>

      {/* --- Data ------------------------------------------------------------ */}
      <Group title={t('Data', lang)}>
        <Row icon={<Upload size={17} strokeWidth={2.2} />} label={t('Export...', lang)} tint={ACTION} />
        <Row icon={<FilePlus size={17} strokeWidth={2.2} />} label={t('Import Data', lang)} tint={ACTION} />
        <Row icon={<Stethoscope size={17} strokeWidth={2.2} />} label={t('Export Sync Diagnostics', lang)} tint={ACTION} />
        <Row icon={<Trash2 size={17} strokeWidth={2.2} />} label={t('Erase Everything', lang)} tint={WC.destructive} />
      </Group>

      {/* --- Storage — the demo dataset's own counts ------------------------- */}
      <Group title={t('Storage', lang)}>
        <Row icon={<HardDrive size={17} strokeWidth={2.2} />} label={t('Mode', lang)} value={t('Local Only', lang)} />
        <Row
          icon={<ArrowLeftRight size={17} strokeWidth={2.2} />}
          label={t('Transactions', lang)}
          value={String(transactions.length)}
        />
        <Row icon={<Repeat size={17} strokeWidth={2.2} />} label={t('Recurring', lang)} value={String(recurring.length)} />
        <Row
          icon={<TrendingUp size={17} strokeWidth={2.2} />}
          label={t('Investments', lang)}
          value={String(holdings.length)}
        />
        <Row icon={<Bitcoin size={17} strokeWidth={2.2} />} label={t('Crypto', lang)} value={String(crypto.length)} />
        <Row
          icon={<CreditCard size={17} strokeWidth={2.2} />}
          label={t('Liabilities', lang)}
          value={String(liabilities.length)}
        />
        <Row icon={<Camera size={17} strokeWidth={2.2} />} label={t('Snapshots', lang)} value={String(snapshotCount)} />
      </Group>

      {/* --- Exchange Rates -------------------------------------------------- */}
      <Group title={t('Exchange Rates', lang)}>
        {/* No cached snapshot in the simulation, so this is the `else` branch. */}
        <Row
          icon={<Landmark size={17} strokeWidth={2.2} />}
          label={t('Source', lang)}
          value={t('Offline fallback', lang)}
          valueColor={WC.warning}
        />
        {CURRENCIES.filter((quote) => quote !== currency).map((quote) => (
          <Row
            key={quote}
            label={`1 ${currency}`}
            value={`${rateFormat.format(DEMO_RATES[quote] / DEMO_RATES[currency])} ${quote}`}
          />
        ))}
        <Row icon={<RefreshCw size={17} strokeWidth={2.2} />} label="Refresh Exchange Rates" tint={ACTION} />
        <Caption>ECB reference rates are refreshed automatically and cached locally for offline use.</Caption>
        {/* Simulation-only: the app really does fetch these; this page never does. */}
        <Caption color={WC.warning}>
          In this simulation the rates above are a fixed demo set, frozen in the page — no ECB request is ever made.
        </Caption>
      </Group>
    </div>
  );
}

/** One `Section` of an `.insetGrouped` List: a caps header over a rounded card. */
function Group({ title, children }: { title: string; children: ReactNode }) {
  const rows = Children.toArray(children).filter(Boolean);
  return (
    <section style={{ display: 'grid', gap: 8 }}>
      <span
        style={{
          fontSize: TEXT.caption,
          fontWeight: 600,
          letterSpacing: '0.9px',
          textTransform: 'uppercase',
          color: WC.textFaint,
          padding: '0 16px',
        }}
      >
        {title}
      </span>
      <div style={{ ...insetRow, padding: 0, overflow: 'hidden' }}>
        {rows.map((row, i) => (
          <Fragment key={i}>
            {i > 0 && <div style={{ height: 1, background: 'rgba(255,255,255,0.06)', marginInlineStart: 14 }} />}
            {row}
          </Fragment>
        ))}
      </div>
    </section>
  );
}

/** A list row at the app's `defaultMinListRowHeight` of 50pt. */
function Row({
  icon,
  label,
  tint = WC.textPrimary,
  value,
  valueColor = WC.textSecondary,
  trailing,
  onClick,
}: {
  icon?: ReactNode;
  label: string;
  tint?: string;
  value?: string;
  valueColor?: string;
  trailing?: ReactNode;
  onClick?: () => void;
}) {
  const body = (
    <>
      {icon && <span style={{ display: 'grid', placeItems: 'center', color: tint, flexShrink: 0 }}>{icon}</span>}
      <span style={{ fontSize: TEXT.body, color: tint, flex: 1, minWidth: 0 }}>{label}</span>
      {value && (
        <span style={{ fontSize: TEXT.subheadline, color: valueColor, fontVariantNumeric: 'tabular-nums' }}>{value}</span>
      )}
      {trailing}
    </>
  );

  const style: CSSProperties = {
    minHeight: 50,
    width: '100%',
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    padding: '11px 14px',
    textAlign: 'start',
    background: 'transparent',
    border: 'none',
    font: 'inherit',
  };

  if (!onClick) return <div style={style}>{body}</div>;
  return (
    <button type="button" onClick={onClick} style={{ ...style, cursor: 'pointer' }}>
      {body}
    </button>
  );
}

/** A `Toggle` row — `.tint(WCColor.primary)` on the switch. */
function ToggleRow({
  icon,
  label,
  checked,
  onChange,
}: {
  icon: ReactNode;
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return <Row icon={icon} label={label} trailing={<Switch checked={checked} onChange={onChange} label={label} />} />;
}

/**
 * A `Picker` row. The app uses the menu style; expanding in place keeps the whole
 * interaction inside the simulated screen instead of dropping a browser menu on
 * top of it, and reads the same as `.pickerStyle(.inline)` does elsewhere in the
 * app.
 */
function PickerRow<T extends string>({
  label,
  options,
  selected,
  onSelect,
}: {
  label: string;
  options: readonly { id: T; label: string }[];
  selected: T;
  onSelect: (id: T) => void;
}) {
  const [open, setOpen] = useState(false);
  const current = options.find((option) => option.id === selected);

  return (
    <div>
      <Row
        label={label}
        value={current?.label}
        onClick={() => setOpen(!open)}
        trailing={
          <ChevronDown
            size={14}
            strokeWidth={2.8}
            color={WC.textSecondary}
            style={{ transform: open ? 'rotate(180deg)' : 'none', transition: 'transform 180ms ease' }}
          />
        }
      />
      {open && (
        <div style={{ display: 'grid', paddingBottom: 6 }}>
          {options.map((option) => {
            const isSelected = option.id === selected;
            return (
              <button
                key={option.id}
                type="button"
                onClick={() => {
                  onSelect(option.id);
                  setOpen(false);
                }}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  padding: '9px 14px',
                  paddingInlineStart: 30,
                  border: 'none',
                  background: isSelected ? 'rgba(255,255,255,0.05)' : 'transparent',
                  color: isSelected ? WC.textPrimary : WC.textSecondary,
                  font: 'inherit',
                  fontSize: TEXT.subheadline,
                  textAlign: 'start',
                  cursor: 'pointer',
                }}
              >
                <span style={{ flex: 1, minWidth: 0 }}>{option.label}</span>
                {isSelected && <Check size={15} strokeWidth={3} color={WC.primary} />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

/** A `.font(.caption)` explanatory row — the footers the app puts inside sections. */
function Caption({ children, color = WC.textSecondary }: { children: ReactNode; color?: string }) {
  return <div style={{ padding: '10px 14px', fontSize: TEXT.caption, color, lineHeight: 1.35 }}>{children}</div>;
}

/** `categoryGroup(title:type:categories:)`, in its empty state. */
function CategoryGroup({ title, empty }: { title: string; empty: string }) {
  return (
    <div style={{ padding: '13px 14px', display: 'grid', gap: 8 }}>
      <span style={{ fontSize: TEXT.subheadline, fontWeight: 600 }}>{title}</span>
      <span style={{ fontSize: TEXT.caption, color: WC.textSecondary }}>{empty}</span>
    </div>
  );
}

/** `settingsStatusChip` — a caption2 capsule at 10% tint. */
function Chip({ icon, label, color }: { icon: ReactNode; label: string; color: string }) {
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 5,
        padding: '7px 9px',
        borderRadius: 999,
        background: `${color}1a`,
        color,
        fontSize: TEXT.caption2,
        fontWeight: 600,
      }}
    >
      {icon}
      {label}
    </span>
  );
}
