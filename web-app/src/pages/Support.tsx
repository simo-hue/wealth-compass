import { Link } from 'react-router-dom';
import { ISSUES, SUPPORT_EMAIL } from '../site/links';

/**
 * The App Store's registered Support URL, so this page has two readers: someone
 * who owns the app and is stuck, and an App Review reviewer checking that support
 * exists and is real.
 *
 * Every instruction names the control it refers to — Settings section, button
 * title, and the app's own status wording — as it appears in
 * apple/WealthCompass/Sources. That is deliberate: it makes the page re-checkable
 * against the app instead of something the reader has to take on trust, and it
 * makes a divergence obvious the next time the UI moves.
 */

const MAILTO = `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('Wealth Compass support')}`;

type Topic = {
  id: string;
  /** Mono kicker, so ten topics can be scanned by area rather than read in order. */
  kind: string;
  title: string;
  intro: string;
  /** Where the control actually lives, per platform. Omitted when there is no single place. */
  where?: { platform: string; path: string }[];
  steps: string[];
  notes?: string[];
};

const TOPICS: Topic[] = [
  {
    id: 'backup',
    kind: 'Data',
    title: 'Back everything up to a JSON file',
    intro:
      'The JSON export is the whole database — every transaction, schedule, holding, liability and net-worth snapshot. The section and period pickers apply to the PDF only, so a backup is never partial.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ Data ▸ Export…' },
      { platform: 'Mac', path: 'Settings ▸ Import and Export ▸ Export…, or File ▸ Export… (⌘E)' },
    ],
    steps: [
      'Open the export sheet and set Format to JSON.',
      'Choose Export.',
      'On iPhone the share sheet opens — Save to Files, or send the file to yourself. On Mac a save panel asks where to put it.',
    ],
    notes: [
      'The file is named wealth-compass-backup-YYYY-MM-DD.json.',
      'Nobody else holds a copy. There is no account behind the app, so a lost backup cannot be reissued.',
    ],
  },
  {
    id: 'restore',
    kind: 'Data',
    title: 'Restore from a JSON backup',
    intro:
      'Import reads the same file the export writes. You decide whether it adds to what is already there or replaces it.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ Data ▸ Import Data' },
      { platform: 'Mac', path: 'Settings ▸ Import and Export ▸ Import Data…' },
    ],
    steps: [
      'Choose the mode. Merge adds new records and updates any record whose ID matches. Replace clears the current local finance data first, then imports.',
      'On iPhone the app asks as you start; on Mac the mode is the Import Behavior picker above the button.',
      'Pick the file. A summary sheet reports what was imported and how many records were skipped.',
    ],
    notes: [
      'Recurring schedules that came due while the backup sat unused are booked into Cash Flow during the import, and the summary says how many.',
      'The same importer also accepts a Revolut consolidated statement and a Trade Republic transaction export or statement PDF. The format is detected from the file — you never pick one.',
    ],
  },
  {
    id: 'pdf',
    kind: 'Data',
    title: 'Export a PDF report',
    intro:
      'The PDF is the readable version, the one to hand to an accountant. It is drawn on the device; nothing is uploaded to produce it.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ Data ▸ Export…' },
      { platform: 'Mac', path: 'File ▸ Export… (⌘E)' },
    ],
    steps: [
      'Set Format to PDF.',
      'Under Contents keep Full Report, or choose Choose Sections and tick from Overview, Cash Flow, Investments and Crypto.',
      'Under Period choose All Time, This Year, Last 12 Months, or a custom range.',
      'Export. A sheet counts the pages as they render, and Cancel stops it.',
    ],
    notes: [
      'The period bounds the transaction ledger only. Holdings are point-in-time and are always reported in full.',
      'Privacy Mode hides amounts on screen, but the PDF contains your real figures. The export sheet says so when Privacy Mode is on.',
    ],
  },
  {
    id: 'sync',
    kind: 'iCloud',
    title: 'iCloud sync is not syncing',
    intro:
      'Sync is off until you turn it on, and the switch is per device — a new iPhone or Mac starts local. Records travel through your own private CloudKit database.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ iCloud Sync' },
      { platform: 'Mac', path: 'Settings ▸ iCloud Sync' },
    ],
    steps: [
      'Turn on Sync Data with iCloud on every device you want included, and sign each of them in to the same iCloud account.',
      'Read the Status row. It names the actual problem rather than failing quietly.',
      'Waiting to Sync means offline, iCloud busy, or the sync data still being prepared. It clears itself, and your changes are already saved locally.',
      'Action Needed means something is yours to fix: iCloud storage full, iCloud restricted by Screen Time or device management, or the iCloud account on the device changed — in which case sync switched itself off so records could not cross accounts, and turning it back on resumes with the current account.',
      'Force Sync iCloud runs a fetch and send immediately.',
    ],
    notes: [
      'Currency, language, custom categories and the app lock are per device by design and never sync. Only finance records do.',
      'If it is still wrong, use Export Sync Diagnostics in the Data section — on iPhone a Share Sync Diagnostics row appears under it — and email me the file. It carries app and OS versions, record counts, sizes, timings and error text: no amounts, no account details.',
    ],
  },
  {
    id: 'finnhub',
    kind: 'Market data',
    title: 'Add a Finnhub key for stocks and ETFs',
    intro:
      'Automatic prices run on your own key, on the provider’s free tier. Requests go from your device straight to the provider; there is no server of mine in between.',
    steps: [
      'Create a free account at finnhub.io/register.',
      'Confirm the email and sign in.',
      'Open the API section of the dashboard and copy your key.',
      'In the app: Settings ▸ Market Data ▸ Finnhub API Key, paste it, then Verify & Save.',
    ],
    notes: [
      'The key is stored only once a live quote for Apple (AAPL) comes back, so a wrong key is refused there and then rather than failing later.',
      'Keys live in the device Keychain. They are never written into a backup, never synced to iCloud, and go only to the provider that issued them.',
      'European-listed ETFs that the Finnhub free tier will not price fall back to Yahoo Finance, which needs no key.',
    ],
  },
  {
    id: 'coingecko',
    kind: 'Market data',
    title: 'Add a CoinGecko key for crypto',
    intro: 'Same arrangement as Finnhub, on CoinGecko’s free Demo tier.',
    steps: [
      'Open coingecko.com/en/api/pricing and choose the free Demo tier.',
      'Create an account or sign in.',
      'Add a new key in the Developer Dashboard and copy it.',
      'In the app: Settings ▸ Market Data ▸ CoinGecko API Key, paste it, then Verify & Save.',
    ],
    notes: [
      'The key is stored only after a live Bitcoin price comes back.',
      'Remove Key, inside the same editor, deletes the stored credential from the Keychain.',
    ],
  },
  {
    id: 'prices',
    kind: 'Market data',
    title: 'Prices are not updating',
    intro:
      'None of this is required. You can type every price by hand and never add a key at all.',
    steps: [
      'Refresh by hand: Settings ▸ Market Data ▸ Refresh Market Data. The button is disabled when you hold no investments and no crypto.',
      'Read the alert. It names the provider and the reason — rate limit reached, key rejected, or no usable quote for a symbol.',
      'For one symbol that never prices, check the ticker. The app resolves a bare symbol or an ISIN through Yahoo’s search, but an unusual listing may need its exchange suffix, as in VWCE.MI.',
    ],
    notes: [
      'Automatic refresh runs when the app comes to the foreground and the oldest stored price is more than 15 minutes old, and it will not retry more often than every 5 minutes.',
      'Free tiers rate-limit. Repeated manual refreshes are the usual cause — wait a few minutes.',
      'Exchange rates are separate and need no key: ECB reference rates through Frankfurter, cached on the device, refreshed once they are over 12 hours old. Settings ▸ Exchange Rates ▸ Refresh Exchange Rates forces it.',
    ],
  },
  {
    id: 'lock',
    kind: 'Security',
    title: 'Face ID or Touch ID lock',
    intro:
      'One switch, named for whatever the device has: Face ID, Touch ID, Optic ID, or Biometrics.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ Security' },
      { platform: 'Mac', path: 'Settings ▸ Privacy & Security' },
    ],
    steps: [
      'Turn on the App Lock toggle and authenticate once to arm it.',
      'On iPhone the app locks whenever it leaves the foreground; on Mac when it stops being the active app.',
      'Turning the lock off asks for authentication too, so someone holding an unlocked device cannot quietly remove it.',
    ],
    notes: [
      'The prompt offers your device passcode as a fallback, so a biometric lockout cannot strand you outside your own records.',
      'If you add a fingerprint or re-enroll Face ID, the next unlock asks you to authenticate one more time. That is the enrollment check, not a failure.',
      'If the toggle will not arm, the message under it comes from the system — usually biometrics or a device passcode has not been set up yet.',
    ],
  },
  {
    id: 'reminders',
    kind: 'Reminders',
    title: 'Recurring reminders do not arrive',
    intro:
      'Reminders are local notifications and are set per schedule, not once for the whole app.',
    steps: [
      'Open the schedule in Cash Flow and check that Notify When Due is on.',
      'Permission is requested when you save a schedule with reminders on. Decline it and the app turns that schedule’s reminders off and tells you it has.',
      'If you declined earlier, allow notifications for Wealth Compass in your device’s system settings, then open the schedule and save it again.',
    ],
    notes: [
      'A schedule with no time of day fires at 09:00 local time.',
      'The next 60 due dates are queued with the system at any one time; later ones are added as earlier ones pass.',
      'With Privacy Mode on, the amount is left out of the notification text.',
      'The reminder does not book the transaction. Due occurrences are recorded when the app is next open — including any missed while it was closed — and the app reports how many were added.',
    ],
  },
  {
    id: 'erase',
    kind: 'Data',
    title: 'Delete all local data',
    intro:
      'One action, and there is no undo. Export a JSON backup first if there is any chance you want the data back.',
    where: [
      { platform: 'iPhone', path: 'Settings ▸ Data ▸ Erase Everything' },
      { platform: 'Mac', path: 'Settings ▸ Danger Zone ▸ Erase Everything…' },
    ],
    steps: [
      'Confirm the alert. The app deletes all finance data on this device and the copy in iCloud, your Finnhub and CoinGecko keys, and every preference, then returns to onboarding.',
      'If the iCloud deletion fails — usually no connection — you are offered Retry or Delete This Device Only.',
    ],
    notes: [
      'Another device signed in to the same iCloud account still holds its own copy, and can restore it to iCloud until you erase it there too.',
      'Deleting the app takes its local file with it. It does not remove the iCloud copy.',
    ],
  },
];

/** What support genuinely cannot do — worth stating before someone writes in. */
const LIMITS: { claim: string; detail: string }[] = [
  {
    claim: 'No bank connection',
    detail:
      'The app never contacts a bank or a broker to read your accounts. Every figure in it is one you entered, or one imported from a file you chose.',
  },
  {
    claim: 'No trades, no transfers',
    detail:
      'It cannot buy, sell, or move money. There is no payment or brokerage code in it at all.',
  },
  {
    claim: 'Not advice',
    detail:
      'Nothing in the app is a recommendation. I am not a licensed adviser, and support cannot tell you what to hold, buy, or sell.',
  },
  {
    claim: 'Prices can be wrong',
    detail:
      'Market prices and exchange rates come from third parties and can be delayed, incomplete, or unavailable. Check anything that matters against your broker.',
  },
  {
    claim: 'I cannot see your data',
    detail:
      'There is no account and no server holding your records, so I cannot look them up, restore them, or delete them on your behalf. That is the trade for keeping them on your device.',
  },
];

function TopicBlock({ topic, index }: { topic: Topic; index: number }) {
  return (
    <article
      id={topic.id}
      // The site nav is sticky at 62px; without this an anchor lands underneath it.
      style={{ scrollMarginTop: 82, paddingBlock: 'clamp(2rem, 4vw, 2.75rem)', borderTop: '1px solid var(--rule-soft)' }}
    >
      <p className="eyebrow">
        <span className="num">{String(index + 1).padStart(2, '0')}</span> · {topic.kind}
      </p>

      <h3
        style={{
          margin: '0.7rem 0 0.6rem',
          fontSize: 'clamp(1.125rem, 1.6vw, 1.3rem)',
          fontWeight: 600,
          letterSpacing: '-0.01em',
          lineHeight: 1.25,
          maxWidth: '34ch',
        }}
      >
        {topic.title}
      </h3>

      <p style={{ color: 'var(--ink-muted)', maxWidth: 'var(--measure)' }}>{topic.intro}</p>

      {topic.where && (
        <dl
          style={{
            display: 'grid',
            gap: '0.45rem 1rem',
            margin: '1.25rem 0 0',
            padding: '0.9rem 1.1rem',
            background: 'var(--surface)',
            border: '1px solid var(--rule)',
            borderRadius: 10,
          }}
        >
          {topic.where.map((row) => (
            <div key={row.platform} style={{ display: 'flex', flexWrap: 'wrap', gap: '0.25rem 0.9rem' }}>
              <dt
                className="mono"
                style={{
                  fontSize: 11,
                  letterSpacing: '0.14em',
                  textTransform: 'uppercase',
                  color: 'var(--ink-faint)',
                  minWidth: '4.5rem',
                }}
              >
                {row.platform}
              </dt>
              <dd className="mono" style={{ margin: 0, fontSize: 13, color: 'var(--ink)' }}>
                {row.path}
              </dd>
            </div>
          ))}
        </dl>
      )}

      <ol style={{ listStyle: 'none', display: 'grid', gap: '0.65rem', margin: '1.25rem 0 0', padding: 0 }}>
        {topic.steps.map((step, i) => (
          <li key={step} style={{ display: 'flex', gap: '0.85rem', maxWidth: 'var(--measure)' }}>
            <span className="num" style={{ fontSize: 12, color: 'var(--ink-faint)', paddingTop: 3, flexShrink: 0 }}>
              {i + 1}
            </span>
            <span style={{ color: 'var(--ink-muted)' }}>{step}</span>
          </li>
        ))}
      </ol>

      {topic.notes && (
        <ul style={{ listStyle: 'none', display: 'grid', gap: '0.5rem', margin: '1.25rem 0 0', padding: 0 }}>
          {topic.notes.map((note) => (
            <li
              key={note}
              style={{
                fontSize: 13,
                lineHeight: 1.5,
                color: 'var(--ink-faint)',
                maxWidth: '68ch',
                paddingLeft: '0.85rem',
                borderLeft: '1px solid var(--rule)',
              }}
            >
              {note}
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}

export const Support = () => {
  return (
    <>
      {/* ------------------------------------------------------------- header */}
      <section className="page" style={{ paddingBlock: 'clamp(3rem, 6vw, 5rem) clamp(2rem, 4vw, 3rem)' }}>
        <p className="eyebrow">Support · iPhone and Mac</p>
        <h1 className="display display-xl" style={{ maxWidth: '17ch', marginBlock: '0.8rem 1.2rem' }}>
          Something is not working. Start here.
        </h1>
        <p className="lede">
          Ten things that go wrong, each with the exact place in the app to fix it, and two ways to
          reach me when none of them is the answer. This covers the Wealth Compass apps for iPhone
          and Mac.
        </p>
        <ul className="spec-strip" style={{ marginTop: '1.5rem', padding: 0 }}>
          <li>iOS 17+</li>
          <li>macOS 14+</li>
          <li>No account</li>
          <li>Data on your device</li>
        </ul>
      </section>

      {/* ------------------------------------------------------------ contact */}
      <section className="page" aria-label="Contact" style={{ paddingBottom: 'clamp(2.5rem, 5vw, 4rem)' }}>
        <div className="source-strip" style={{ display: 'grid', gap: '1.75rem' }}>
          <div style={{ display: 'grid', gap: '0.8rem' }}>
            <p className="eyebrow">Reach a person</p>
            <p style={{ color: 'var(--ink-muted)', maxWidth: '58ch' }}>
              Wealth Compass is written and supported by one person, in Verona. That person is{' '}
              <a
                href="https://simo-hue.github.io/"
                rel="author noopener noreferrer"
                target="_blank"
                className="u-link"
                style={{ color: 'var(--ink)' }}
              >
                Simone Mattioli
              </a>
              , an independent developer who writes the code, ships the releases and answers this
              mailbox himself. I read everything and answer personally, usually within two or three
              working days, sometimes longer. If a week goes by with no reply, assume the message
              went astray and send it again. Fixes ship in the next App Store update rather than the
              same day.
            </p>
          </div>

          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '1rem 2.5rem', alignItems: 'baseline' }}>
            <a href={MAILTO} className="u-link mono" style={{ fontSize: 15 }}>
              {SUPPORT_EMAIL}
            </a>
            <a
              href={ISSUES}
              target="_blank"
              rel="noopener noreferrer"
              className="u-link"
              style={{ fontSize: 15, color: 'var(--ink-muted)' }}
            >
              File a GitHub issue →
            </a>
          </div>

          <div style={{ display: 'grid', gap: '1.25rem', borderTop: '1px solid var(--rule)', paddingTop: '1.5rem' }}>
            <div style={{ display: 'grid', gap: '0.7rem' }}>
              <p className="eyebrow">What to put in the message</p>
              <ul style={{ listStyle: 'none', display: 'grid', gap: '0.5rem', margin: 0, padding: 0 }}>
                {[
                  'Which app — iPhone or Mac — and its version. The Mac shows it under Wealth Compass ▸ About; on both platforms the sync diagnostics file carries it.',
                  'What you did, what happened, and what you expected instead.',
                  'For anything to do with iCloud, the file from Settings ▸ Data ▸ Export Sync Diagnostics.',
                  'Screenshots help. Blur anything you would not put on a postcard.',
                ].map((line) => (
                  <li key={line} style={{ color: 'var(--ink-muted)', maxWidth: '62ch' }}>
                    {line}
                  </li>
                ))}
              </ul>
            </div>

            <p style={{ fontSize: 13, color: 'var(--ink-faint)', maxWidth: '62ch' }}>
              Please do not send your JSON backup or an API key. The backup is your entire financial
              record, and I do not need either to find a bug. A problem you are happy to discuss in
              public is better filed as a GitHub issue — the source is public, and other people can
              add to it.
            </p>
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------------- index */}
      <section className="page" aria-label="Topics" style={{ paddingBottom: 'clamp(1.5rem, 3vw, 2.5rem)' }}>
        <p className="eyebrow" style={{ marginBottom: '0.9rem' }}>
          Jump to
        </p>
        <nav
          style={{ display: 'flex', flexWrap: 'wrap', gap: '0.55rem 1.5rem' }}
          aria-label="Support topics"
        >
          {TOPICS.map((topic, i) => (
            <a
              key={topic.id}
              href={`#${topic.id}`}
              className="u-link"
              style={{ fontSize: 14, color: 'var(--ink-muted)' }}
            >
              <span className="num" style={{ color: 'var(--ink-faint)', marginRight: '0.5rem' }}>
                {String(i + 1).padStart(2, '0')}
              </span>
              {topic.title}
            </a>
          ))}
        </nav>
      </section>

      {/* ------------------------------------------------------------- topics */}
      <section className="page" aria-label="Fixes" style={{ paddingBottom: 'clamp(3rem, 6vw, 5rem)' }}>
        <h2 className="display display-l" style={{ maxWidth: '20ch', marginBottom: '0.5rem' }}>
          Fixes, in the order people ask for them
        </h2>
        {TOPICS.map((topic, i) => (
          <TopicBlock key={topic.id} topic={topic} index={i} />
        ))}
      </section>

      {/* -------------------------------------------------------------- where */}
      <section className="page" aria-label="Where your data lives" style={{ paddingBottom: 'clamp(3rem, 6vw, 5rem)' }}>
        <div
          style={{
            display: 'grid',
            gap: '0.9rem',
            padding: 'clamp(1.5rem, 3vw, 2.25rem)',
            background: 'var(--canvas-deep)',
            border: '1px solid var(--rule-soft)',
            borderRadius: 14,
          }}
        >
          <p className="eyebrow">Where your records actually are</p>
          <p style={{ color: 'var(--ink-muted)', maxWidth: '62ch' }}>
            One JSON file inside the app’s own container, at Application Support ▸ Wealth Compass
            Tracker ▸ wealth-compass-local-data.json. On the Mac, Settings ▸ Local Storage prints the
            full path and lets you select it. Both platforms list how many transactions, schedules,
            investments, crypto holdings, liabilities and snapshots that file holds, which is the
            quickest way to confirm an import did what you expected.
          </p>
        </div>
      </section>

      {/* ------------------------------------------------------------- limits */}
      <section className="page" aria-label="What support cannot do" style={{ paddingBottom: 'clamp(3rem, 6vw, 5rem)' }}>
        <h2 className="display display-l" style={{ maxWidth: '18ch', marginBottom: '2rem' }}>
          What the app does not do
        </h2>
        <dl className="facts">
          {LIMITS.map((limit) => (
            <div key={limit.claim} className="fact">
              <dt>
                <span className="mono fact-claim">{limit.claim}</span>
              </dt>
              <dd>
                <p style={{ color: 'var(--ink-muted)', maxWidth: '52ch' }}>{limit.detail}</p>
              </dd>
            </div>
          ))}
        </dl>
      </section>

      {/* ---------------------------------------------------------- elsewhere */}
      <section className="cta" aria-label="More">
        <div className="page" style={{ display: 'grid', gap: '1.4rem', maxWidth: 'var(--measure)' }}>
          <p className="eyebrow">Elsewhere</p>
          <p style={{ color: 'var(--ink-muted)' }}>
            The <Link to="/faq/" className="u-link">FAQ</Link> answers what the app does before you
            buy it. The <Link to="/privacy/" className="u-link">privacy policy</Link> lists every
            network request it makes and why, and the{' '}
            <Link to="/terms/" className="u-link">terms</Link> cover the licence. The{' '}
            <Link to="/open-source/" className="u-link">source</Link> is public, so a claim on any of
            those pages can be checked rather than believed.
          </p>
          <p className="mono" style={{ fontSize: 12, color: 'var(--ink-faint)', letterSpacing: '0.06em' }}>
            SIMONE MATTIOLI · VERONA, ITALY ·{' '}
            <a href={MAILTO} className="u-link">
              {SUPPORT_EMAIL}
            </a>
          </p>
        </div>
      </section>
    </>
  );
};
