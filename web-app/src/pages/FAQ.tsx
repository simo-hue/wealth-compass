import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { StoreButton } from '../site/SiteLayout';
import { ISSUES, REPO, SUPPORT_EMAIL } from '../site/links';

/**
 * This page is the Support URL registered with App Review
 * (apple/WealthCompass/fastlane/metadata/en-US/support_url.txt points here), so
 * it is read by people who already have the app and by reviewers checking the
 * privacy claims. Every answer below is about the iPhone/Mac app and is
 * traceable to a file in `apple/` — where a claim rests on one, the file is
 * named in the answer so it can be checked rather than believed.
 *
 * It replaces a version that described the app as a self-hosted Supabase web
 * app with Row Level Security and a Node.js setup guide. That described the
 * legacy `web-app/` program, not the shipped app; the web app now gets one
 * clearly-labelled section at the end.
 */

/**
 * `id` is the question's permanent fragment: /faq/#icloud-sync. It is written by
 * hand from what the question means, never generated — a React `useId` value like
 * ":R12ekb:" changes every build, and an anchor that moves is worse than none. It
 * is also the `url` of the matching Question in the JSON-LD below, which is what
 * lets an answer engine cite the one answer instead of the whole 40-item page.
 * Changing an id breaks any link already pointing at it; add, don't rename.
 */
type Item = { id: string; q: string; a: string[] };
type Section = { id: string; nav: string; title: string; items: Item[] };

/** Backticks mark a filename, path or identifier. Not markdown — just this. */
const plain = (text: string) => text.replace(/`/g, '');

function withCode(text: string, keyBase: string) {
  return text.split(/`([^`]+)`/g).map((part, i) =>
    i % 2 === 1 ? (
      <code
        key={`${keyBase}-${i}`}
        className="mono"
        style={{ fontSize: '0.9em', color: 'var(--ink)', wordBreak: 'break-word' }}
      >
        {part}
      </code>
    ) : (
      part
    ),
  );
}

const SECTIONS: Section[] = [
  {
    id: 'app',
    nav: 'The app',
    title: 'What it is',
    items: [
      {
        id: 'what-is-wealth-compass',
        q: 'What is Wealth Compass?',
        a: [
          'A net-worth tracker for iPhone and Mac. You record what you own, owe, earn and spend — accounts, investments, crypto, liabilities, transactions — and it adds them up in one currency, keeps the history behind that number, and breaks down where the money went.',
          'It runs on your device. There is no account to create and no server of mine involved.',
        ],
      },
      {
        id: 'what-it-costs',
        q: 'What does it cost?',
        a: [
          'Nothing. Free on the App Store, with no in-app purchases, no subscription, no trial and no ads.',
          'This one is checkable in a second: there is no StoreKit anywhere in the source. The app has no code that could charge you.',
        ],
      },
      {
        id: 'one-app-both-devices',
        q: 'Do I buy it twice for iPhone and Mac?',
        a: [
          'No. It is one universal App Store listing — id `6777399748`, listed as Wealth Compass Tracker. Get it on either device and it is available on the other.',
        ],
      },
      {
        id: 'system-requirements',
        q: 'What do I need to run it?',
        a: [
          'iOS 17 or later on iPhone, macOS 14 or later on Mac. Those are the deployment targets in the Xcode project (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0`).',
        ],
      },
      {
        id: 'native-mac-app',
        q: 'Is the Mac version the iPhone app in a window?',
        a: [
          'No. The Mac target is built against the macOS SDK, not Mac Catalyst. It has desktop navigation, real tables, a menu bar with keyboard shortcuts, AppKit open and save panels, and an in-window Settings page.',
        ],
      },
      {
        id: 'getting-started',
        q: 'How do I get started?',
        a: [
          'Install it and open it. There is no sign-up step, so the first screen you see is the app.',
          'Add your first balance or transaction, then set the four things worth setting: base currency, language, whether Face ID or Touch ID unlocks the app, and — only if you want live prices — a market-data API key. All of it is in Settings, and all of it can wait.',
        ],
      },
      {
        id: 'bank-connections',
        q: 'Does it connect to my bank?',
        a: [
          'No. It does not link to financial institutions, place trades or move money. You enter records yourself, or import a broker statement file you downloaded.',
          'It is an informational tracking tool. It does not give financial advice and does not guarantee third-party price data.',
        ],
      },
      {
        id: 'other-platforms',
        q: 'Is there an Android, Windows or web version?',
        a: [
          'Not of this app. Wealth Compass for iPhone and Mac is the only shipped version. There is an older, separate web app in the same repository — see the last section.',
        ],
      },
    ],
  },
  {
    id: 'data',
    nav: 'Your data',
    title: 'Where your data lives',
    items: [
      {
        id: 'where-data-is-stored',
        q: 'Where is my data stored?',
        a: [
          'In one JSON file inside the app sandbox on your device: `Application Support/Wealth Compass/wealth-compass-local-data.json`.',
          'The iPhone app and the Mac app each keep their own copy. iCloud sync is what joins them, and only if you turn it on.',
        ],
      },
      {
        id: 'can-the-developer-see-my-data',
        q: 'Can you see my figures?',
        a: [
          'No. There is no account, no login and no developer-operated server anywhere in the app. There is no backend that could hold your records, which is a stronger answer than a promise not to look.',
        ],
      },
      {
        id: 'app-store-privacy-label',
        q: 'What does the App Store privacy label say?',
        a: [
          'Data Not Collected.',
          'It comes from `PrivacyInfo.xcprivacy`, present in both the iOS and macOS resources. It declares `NSPrivacyCollectedDataTypes` as an empty array and `NSPrivacyTracking` as false. The only entry in it is a required-reason declaration for UserDefaults (reason code `CA92.1`) — the app reading its own settings.',
        ],
      },
      {
        id: 'servers-contacted',
        q: 'Which servers does the app contact?',
        a: [
          'Four, each only when a feature you switched on needs it: `finnhub.io` for stock quotes, `api.coingecko.com` for crypto prices, `query1.finance.yahoo.com` as a keyless fallback for listings Finnhub cannot price, and `api.frankfurter.dev` for exchange rates. Plus Apple iCloud, if you enable sync.',
          'They are all listed in one short file, `APIConfiguration.swift`. There is no proxy of mine in the middle: every request goes straight from your device to the provider, so no server of mine sees your key, your address or which symbols you look up.',
        ],
      },
      {
        id: 'analytics-and-tracking-sdks',
        q: 'Are there analytics, ad or crash-reporting SDKs?',
        a: [
          'None. The Xcode project has no package dependencies at all — nothing third-party is linked into the app.',
        ],
      },
      {
        id: 'face-id-app-lock',
        q: 'Can I lock the app?',
        a: [
          'Yes. Face ID or Touch ID app lock, switched on in Settings. iPhone and Mac keep the setting separately, so locking one does not lock the other.',
        ],
      },
      {
        id: 'privacy-mode',
        q: 'What is Privacy Mode?',
        a: [
          'A switch that replaces every amount on screen with `••••` and covers each chart with a blurred panel, so you can open the app next to someone. It changes what is drawn, not what is stored, and it survives a restart.',
        ],
      },
      {
        id: 'privacy-mode-and-exports',
        q: 'Does Privacy Mode also hide figures in exports?',
        a: [
          'No, and that is deliberate. A PDF report or JSON backup contains the real amounts even while Privacy Mode is on, because a redacted financial statement is of no use to anyone. The export sheet tells you this before you export rather than letting you find out after you have shared the file.',
        ],
      },
      {
        id: 'icloud-sync',
        q: 'How does iCloud sync work?',
        a: [
          'It is off until you turn it on, in Settings, per device. When on, records go to your own private CloudKit database in the container `iCloud.com.wealthcompasstracker` — your iCloud account, not mine. Enable it on both devices to keep iPhone and Mac in step.',
          'A private CloudKit database is reachable only by the signed-in Apple Account. A developer cannot read it, and this one has no server-side component that could try.',
        ],
      },
      {
        id: 'api-key-storage',
        q: 'Are my API keys synced or backed up?',
        a: [
          'No. Finnhub and CoinGecko keys are stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which pins them to the device they were entered on and keeps them out of Keychain sync entirely. They never enter the JSON database, so they are never in a backup or in iCloud.',
        ],
      },
      {
        id: 'erase-everything',
        q: 'How do I delete everything?',
        a: [
          'Settings, then Erase Everything. It wipes the local database, your settings and the stored API keys, and can delete the iCloud zone in the same step.',
        ],
      },
      {
        id: 'offline-use',
        q: 'Does it work offline?',
        a: [
          'Yes, apart from fetching live prices. Exchange rates are cached locally after the first fetch and reused when there is no network, so conversion keeps working on a plane.',
        ],
      },
    ],
  },
  {
    id: 'prices',
    nav: 'Prices & rates',
    title: 'Prices, rates and currencies',
    items: [
      {
        id: 'stock-and-etf-prices',
        q: 'Where do stock and ETF prices come from?',
        a: [
          'Finnhub, using an API key you create and paste into Settings. Finnhub’s free tier covers US listings; when it returns no quote for a symbol — typically a European-listed UCITS ETF — the app falls back to Yahoo Finance’s keyless endpoint, which also reports the listing’s own currency so the value is not silently treated as dollars.',
        ],
      },
      {
        id: 'crypto-prices',
        q: 'Where do crypto prices come from?',
        a: [
          'CoinGecko. A demo key is optional and only raises your rate limit. Coins are matched to a CoinGecko id from a built-in map, or resolved through CoinGecko’s search when a holding has neither an id nor a known ticker.',
        ],
      },
      {
        id: 'why-bring-your-own-api-key',
        q: 'Why do I have to bring my own API key?',
        a: [
          'Because the alternative is worse. Shipping one shared key means routing every request through a server of mine, which would then see your address and every symbol and coin you hold. Your key goes directly to the provider instead, and the app keeps no record of the lookup.',
        ],
      },
      {
        id: 'is-an-api-key-required',
        q: 'Is a key required to use the app?',
        a: [
          'Only for automatic price refreshes. A Finnhub key is what unlocks investment price updates specifically. Without any key you can still enter and edit prices by hand, and every other part of the app is unaffected.',
        ],
      },
      {
        id: 'supported-currencies',
        q: 'Which currencies are supported?',
        a: [
          '31: EUR, USD, GBP and CHF first, then the rest of the ECB reference set. Each holding keeps its own currency and everything is converted into the base currency you pick.',
        ],
      },
      {
        id: 'exchange-rates',
        q: 'Where do the exchange rates come from?',
        a: [
          'European Central Bank reference rates, fetched through Frankfurter and cached on the device. Settings shows the effective date of the rates you are currently on, and tells you when it is falling back to the cached set.',
        ],
      },
    ],
  },
  {
    id: 'files',
    nav: 'Import & export',
    title: 'Getting data in and out',
    items: [
      {
        id: 'export-data',
        q: 'Can I export my data?',
        a: [
          'Yes, in two formats. A JSON backup is the complete database and can be imported back. A PDF report is a formatted statement — choose the whole thing or pick from overview, cash flow, investments and crypto, over all time, this year, the last 12 months, or a range you set.',
        ],
      },
      {
        id: 'import-a-backup',
        q: 'Can I import a backup?',
        a: [
          'Yes. Import a JSON backup either as a merge into what is already there, or as a replacement.',
        ],
      },
      {
        id: 'broker-statement-import',
        q: 'Can I import statements from my broker?',
        a: [
          'For the formats that have been implemented, yes: Trade Republic’s transaction export CSV, Revolut’s consolidated statement CSV, and two Trade Republic PDFs — the account statement and the net-worth statement, read with PDFKit on both platforms.',
          'The format is detected from the file’s contents, not its name. Every imported record gets a deterministic id derived from the row, so importing the same statement twice does not double your ledger. A Revolut PDF is rejected on purpose, because its CSV carries the same data more reliably.',
        ],
      },
      {
        id: 'recurring-transactions',
        q: 'Are recurring transactions supported?',
        a: [
          'Yes. Give a transaction a frequency and it books itself on schedule, with an optional local notification reminder. The reminder is a local notification scheduled on the device; nothing is sent anywhere.',
        ],
      },
      {
        id: 'net-worth-history',
        q: 'Where does the net-worth history come from?',
        a: [
          'The app takes its own snapshots locally as your figures change, so the history chart is built from your own past states rather than reconstructed.',
        ],
      },
    ],
  },
  {
    id: 'languages',
    nav: 'Languages',
    title: 'Languages',
    items: [
      {
        id: 'supported-languages',
        q: 'What languages does the app speak?',
        a: [
          '35, translated in `Localizable.xcstrings`. Among them Arabic and Hebrew, which the layout mirrors for right-to-left reading, plus both Chinese scripts, both Portuguese variants and both Spanish variants.',
          'The App Store listing says 33, and both numbers are right. Apple lists one Spanish and one Portuguese where the app actually ships two of each — `es` and `es-419`, `pt-BR` and `pt-PT` — so the store count is 35 minus those two.',
        ],
      },
      {
        id: 'in-app-language-picker',
        q: 'Can the app use a different language from my phone?',
        a: [
          'Yes. Settings has its own language picker, independent of the system language, so you can keep an English phone and an Italian app.',
        ],
      },
    ],
  },
  {
    id: 'source',
    nav: 'Source & licence',
    title: 'The source and the licence',
    items: [
      {
        id: 'source-available-not-open-source',
        q: 'Is Wealth Compass open source?',
        a: [
          'No, and the distinction is worth being precise about. It is source-available: every line is public on GitHub, and you can read it, build it and run it.',
          'The licence is PolyForm Noncommercial 1.0.0, which is not an OSI-approved open-source licence, because it restricts the field of use. Calling the project open source would be inaccurate, so it is not called that here.',
        ],
      },
      {
        id: 'what-the-licence-permits',
        q: 'What does the licence let me do?',
        a: [
          'Anything noncommercial. Read the code, build both apps yourself, modify them, run your own copy, host the web app for your own use — for personal study, research, experiment, testing, hobby projects or an amateur pursuit.',
          'What it does not permit is commercial use: selling it, shipping it inside a product you charge for, or running it as a paid service. If you want to do something commercial with it, write and ask.',
        ],
      },
      {
        id: 'verify-the-privacy-claims',
        q: 'How do I check the privacy claims for myself?',
        a: [
          'Do not take them on trust — each one is a small file. `PrivacyInfo.xcprivacy` is the empty collected-data declaration. `APIConfiguration.swift` is the complete list of hosts the app contacts. `MarketDataService.swift` holds the Keychain accessibility flag that keeps your keys off iCloud. `FinancePersistence.swift` is where the storage path is set.',
        ],
      },
      {
        id: 'report-a-bug-or-request-a-feature',
        q: 'I found a bug, or I want a feature.',
        a: [
          'Open an issue on GitHub with what you did and what happened, or email if the details are personal. Worth doing: the app sends no diagnostics of its own, so a bug you do not report is one I may never see.',
        ],
      },
    ],
  },
  {
    id: 'web',
    nav: 'The web app',
    title: 'The older web app',
    items: [
      {
        id: 'what-is-the-web-app',
        q: 'What is the web app, and how is it different?',
        a: [
          'Before the Apple apps there was a Wealth Compass web app, and its source is still in the repository under `web-app/`. It is a separate program that shares the product idea and the JSON backup format but no code.',
          'It is React, TypeScript and Vite in the browser, with Supabase behind it for storage and email-and-password sign-in, protected by Row Level Security. That means an account, and a database on a server. It is the opposite arrangement to the iPhone and Mac apps, and it is not what this site is about.',
        ],
      },
      {
        id: 'is-the-web-app-maintained',
        q: 'Is the web app still maintained?',
        a: [
          'It is not where the work goes. It still builds and still runs, and the licence permits you to host it yourself for personal use, but new features are built for iPhone and Mac.',
        ],
      },
      {
        id: 'self-hosting-the-web-app',
        q: 'If I self-host the web app, who holds the data?',
        a: [
          'You do, in your own Supabase project — a real database on a real server, yours to secure, update and back up. Worth saying plainly, because it is a different set of responsibilities from the Apple apps, which have no server for anyone to look after.',
        ],
      },
    ],
  },
];

const TOTAL = SECTIONS.reduce((n, section) => n + section.items.length, 0);

/**
 * The page's canonical URL, trailing slash included: GitHub Pages 301s
 * /wealth-compass/faq to /wealth-compass/faq/, so the slashed form is the one that
 * actually gets indexed and the only one worth naming in structured data.
 */
const FAQ_URL = 'https://simo-hue.github.io/wealth-compass/faq/';

/** The two nodes this page hangs off. Both are defined in scripts/prerender.mjs. */
const APP_ID = 'https://simo-hue.github.io/wealth-compass/#app';
const PERSON_ID = 'https://simo-hue.github.io/#person';

/**
 * Answers are plain strings, so the support page can also state them as data.
 *
 * Since Google's August 2023 change, FAQ rich results are reserved for well-known
 * government and health sites, so none of this will put anything extra on a SERP
 * for Wealth Compass. It stays because it is clean answer data for the engines
 * that do read it, and because `about` and `author` are what stop forty answers
 * about a product and a person from naming neither: they point at the same nodes
 * the prerenderer emits, so the FAQ joins one graph instead of floating free.
 * Each Question carries the fragment URL of its own answer.
 */
const FAQ_SCHEMA = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  '@id': `${FAQ_URL}#faq`,
  url: FAQ_URL,
  about: { '@id': APP_ID },
  author: { '@id': PERSON_ID },
  mainEntity: SECTIONS.flatMap((section) =>
    section.items.map((item) => ({
      '@type': 'Question',
      name: item.q,
      url: `${FAQ_URL}#${item.id}`,
      acceptedAnswer: { '@type': 'Answer', text: item.a.map(plain).join(' ') },
    })),
  ),
};

/**
 * Scoped to this page. The site stylesheet is shared and off-limits, and these
 * three rules need media queries that inline styles cannot express: the rail
 * only exists above 900px, and the grid only splits there too.
 */
const CSS = `
.faq-shell { display: grid; gap: clamp(2rem, 5vw, 3.25rem); }
.faq-rail { display: none; }
.faq-filter::placeholder { color: var(--ink-faint); opacity: 1; }
.faq-item { border-top: 1px solid var(--rule-soft); padding-block: 1.5rem; }
.faq-section:last-child .faq-item:last-child { border-bottom: 1px solid var(--rule-soft); }
@media (min-width: 900px) {
  .faq-shell { grid-template-columns: minmax(150px, 200px) 1fr; align-items: start; }
  .faq-rail {
    display: grid;
    gap: 0.6rem;
    position: sticky;
    top: 90px;
    align-self: start;
  }
  .faq-item { grid-template-columns: 1fr; }
}
`;

export const FAQ = () => {
  const [query, setQuery] = useState('');

  const needle = query.trim().toLowerCase();
  const results = useMemo(() => {
    if (!needle) return SECTIONS;
    return SECTIONS.map((section) => ({
      ...section,
      items: section.items.filter((item) =>
        plain(`${item.q} ${item.a.join(' ')}`).toLowerCase().includes(needle),
      ),
    })).filter((section) => section.items.length > 0);
  }, [needle]);

  const shown = results.reduce((n, section) => n + section.items.length, 0);

  return (
    <>
      <style>{CSS}</style>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(FAQ_SCHEMA) }} />

      {/* ------------------------------------------------------------- header */}
      <section className="page" style={{ paddingBlock: 'clamp(3rem, 6vw, 5rem) clamp(1.75rem, 3vw, 2.5rem)' }}>
        <p className="eyebrow">Support · iPhone and Mac</p>
        <h1 className="display display-xl" style={{ maxWidth: '14ch', marginBlock: '0.7rem 1.1rem' }}>
          Questions, answered
        </h1>
        <p className="lede">
          What the app does, where your records live, what it costs, and what the licence permits.
          Where an answer rests on something in the source, it names the file, so you can check it
          instead of believing it.
        </p>
        <ul className="spec-strip" style={{ marginTop: '1.4rem', padding: 0 }}>
          <li>Free</li>
          <li>No account</li>
          <li>Data not collected</li>
          <li>iOS 17+ · macOS 14+</li>
        </ul>
      </section>

      {/* ------------------------------------------------- filter and answers */}
      {/* The filter lives in the answers column rather than in the header, so it
          sits directly above the list it narrows and shares its left edge. */}
      <div className="page faq-shell" style={{ paddingBottom: 'clamp(3rem, 7vw, 6rem)' }}>
        <nav className="faq-rail" aria-label="Sections">
          {SECTIONS.map((section) => (
            <a
              key={section.id}
              href={`#faq-${section.id}`}
              className="u-link"
              style={{
                fontFamily: 'var(--data)',
                fontSize: 11,
                letterSpacing: '0.12em',
                textTransform: 'uppercase',
                color: 'var(--ink-faint)',
                justifySelf: 'start',
              }}
            >
              {section.nav}
            </a>
          ))}
        </nav>

        <div style={{ display: 'grid', gap: 'clamp(2.5rem, 5vw, 4rem)' }}>
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'flex-end', gap: '0.9rem 1.5rem' }}>
            <label style={{ flex: '1 1 20rem', display: 'grid', gap: '0.5rem', maxWidth: '28rem' }}>
              <span className="eyebrow">Filter</span>
              {/* No `outline: none` here: an inline outline would beat the site's
                  :focus-visible rule and leave the field with no focus ring. */}
              <input
                className="faq-filter"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="iCloud, licence, API key…"
                style={{
                  width: '100%',
                  fontFamily: 'var(--body)',
                  fontSize: 15,
                  color: 'var(--ink)',
                  background: 'var(--surface)',
                  border: '1px solid var(--rule)',
                  borderRadius: 10,
                  padding: '0.7rem 0.9rem',
                  WebkitAppearance: 'none',
                  appearance: 'none',
                }}
              />
            </label>
            <p
              className="mono"
              aria-live="polite"
              style={{ fontSize: 11, letterSpacing: '0.12em', textTransform: 'uppercase', color: 'var(--ink-faint)', paddingBottom: '0.85rem' }}
            >
              {needle ? `${shown} of ${TOTAL} questions` : `${TOTAL} questions`}
            </p>
          </div>

          {results.map((section) => (
            <section key={section.id} id={`faq-${section.id}`} className="faq-section" style={{ scrollMarginTop: 90 }}>
              <h2 className="display display-m" style={{ marginBottom: '1.25rem' }}>
                {section.title}
              </h2>

              {section.items.map((item) => (
                <div key={item.id} className="faq-item">
                  {/* The id sits on the heading, not the wrapper, so a citation
                      landing on /faq/#icloud-sync puts the question at the top of
                      the viewport with its answer under it. scrollMarginTop clears
                      the sticky header, as on the section wrappers. */}
                  <h3
                    id={item.id}
                    style={{
                      margin: 0,
                      fontSize: '1.0625rem',
                      fontWeight: 600,
                      lineHeight: 1.35,
                      maxWidth: '46ch',
                      scrollMarginTop: 90,
                    }}
                  >
                    {item.q}
                  </h3>
                  <div style={{ display: 'grid', gap: '0.75rem', marginTop: '0.7rem' }}>
                    {item.a.map((paragraph, i) => (
                      <p key={i} style={{ color: 'var(--ink-muted)', maxWidth: 'var(--measure)' }}>
                        {withCode(paragraph, `${item.id}-${i}`)}
                      </p>
                    ))}
                  </div>
                </div>
              ))}
            </section>
          ))}

          {results.length === 0 && (
            <div style={{ display: 'grid', gap: '1rem', paddingBlock: '3rem' }}>
              <p style={{ fontSize: '1.125rem' }}>Nothing here matches “{query.trim()}”.</p>
              <p style={{ color: 'var(--ink-muted)', maxWidth: 'var(--measure)' }}>
                Clear the filter to read all {TOTAL} answers, or ask directly — an unanswered question
                usually means this page is missing one.
              </p>
              {/* Trailing slash on purpose: GitHub Pages 301s /support to /support/,
                  so the unslashed form costs a redirect and splits the signal. */}
              <Link to="/support/" className="u-link" style={{ justifySelf: 'start', color: 'var(--ink-muted)' }}>
                Get in touch →
              </Link>
            </div>
          )}
        </div>
      </div>

      {/* ---------------------------------------------------------- still stuck */}
      <section className="page" style={{ paddingBottom: 'clamp(3rem, 7vw, 6rem)' }}>
        <div className="source-strip">
          <div style={{ display: 'grid', gap: '0.8rem' }}>
            <p className="eyebrow">Not answered here</p>
            <p style={{ color: 'var(--ink-muted)', maxWidth: '52ch' }}>
              Bugs and feature requests go to GitHub issues, where they stay visible. Anything with your
              own figures in it is better by email. Either way it reaches the one person who wrote the
              app.
            </p>
            <p className="mono" style={{ fontSize: 12, color: 'var(--ink-faint)', letterSpacing: '0.04em' }}>
              {SUPPORT_EMAIL}
            </p>
          </div>
          <div style={{ display: 'grid', gap: '0.7rem', justifyItems: 'start' }}>
            <Link to="/support/" className="u-link" style={{ fontSize: 15, whiteSpace: 'nowrap' }}>
              Support →
            </Link>
            <a href={ISSUES} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, whiteSpace: 'nowrap' }}>
              Open an issue →
            </a>
            <a href={REPO} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, whiteSpace: 'nowrap' }}>
              Read the source →
            </a>
          </div>
        </div>
      </section>

      {/* ---------------------------------------------------------------- cta */}
      <section className="cta" aria-label="Download">
        <div className="page" style={{ display: 'grid', gap: '1.5rem', justifyItems: 'center', textAlign: 'center' }}>
          <h2 className="display display-l" style={{ maxWidth: '18ch' }}>
            Nothing to sign up for
          </h2>
          <p className="lede" style={{ textAlign: 'center' }}>
            Free on the App Store. One download covers iPhone and Mac.
          </p>
          <StoreButton placement="site-cta" />
        </div>
      </section>
    </>
  );
};
