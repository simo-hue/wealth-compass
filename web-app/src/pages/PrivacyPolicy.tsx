import type { CSSProperties, ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { LICENSE, REPO, SUPPORT_EMAIL } from '../site/links';

/**
 * Apple's registered Privacy URL for the App Store listing, so it has to read as
 * a real policy rather than as marketing. Every factual claim below is checkable
 * in the public repository:
 *
 *   apple/WealthCompass/Resources/iOS/PrivacyInfo.xcprivacy    empty collected-data list, tracking false
 *   apple/WealthCompass/Resources/macOS/PrivacyInfo.xcprivacy   identical manifest for the Mac target
 *   Sources/Shared/Persistence/FinancePersistence.swift         the single local JSON file + file protection
 *   Sources/Shared/Services/APIConfiguration.swift              the four providers contacted, no proxy
 *   Sources/Shared/Services/CloudKitSyncService.swift           opt-in sync, container, record types
 *   Sources/Shared/Services/MarketDataService.swift             Keychain service for the API keys
 *   web-app/src/lib/supabase.ts, src/contexts/*                 the separate web app's own storage
 */

const REVISION = 'Effective 6 June 2026 · Revised 28 July 2026';

const measure = '68ch';

const bodyStyle: CSSProperties = {
  fontSize: '1.0625rem',
  lineHeight: 1.68,
  color: 'var(--ink-muted)',
  maxWidth: measure,
};

const linkStyle: CSSProperties = {
  color: 'var(--ink)',
  textDecoration: 'underline',
  textDecorationColor: 'var(--ink-faint)',
  textUnderlineOffset: '0.22em',
};

function P({ children }: { children: ReactNode }) {
  return <p style={bodyStyle}>{children}</p>;
}

/** Raises a phrase out of --ink-muted without bolding a whole line. */
function Key({ children }: { children: ReactNode }) {
  return <strong style={{ color: 'var(--ink)', fontWeight: 600 }}>{children}</strong>;
}

/** Identifiers you can grep for in the repo — set in the data face, like every figure on this site. */
function Id({ children }: { children: ReactNode }) {
  return (
    <span className="mono" style={{ fontSize: '0.88em', color: 'var(--ink)', wordBreak: 'break-word' }}>
      {children}
    </span>
  );
}

function Out({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" style={linkStyle}>
      {children}
    </a>
  );
}

function List({ items }: { items: ReactNode[] }) {
  return (
    <ul style={{ display: 'grid', gap: '0.85rem', margin: 0, padding: 0, listStyle: 'none', maxWidth: measure }}>
      {items.map((item, i) => (
        <li key={i} style={{ ...bodyStyle, maxWidth: 'none', display: 'grid', gridTemplateColumns: '1.5rem 1fr' }}>
          <span className="mono" aria-hidden="true" style={{ color: 'var(--ink-faint)' }}>
            —
          </span>
          <span>{item}</span>
        </li>
      ))}
    </ul>
  );
}

const SECTIONS: { id: string; title: string; body: ReactNode }[] = [
  {
    id: 'scope',
    title: 'What this policy covers',
    body: (
      <>
        <P>
          This policy covers the Wealth Compass apps for <Key>iPhone (iOS 17 and later)</Key> and{' '}
          <Key>Mac (macOS 14 and later)</Key> — listed on the App Store as Wealth Compass Tracker — and this
          website. The two apps are built from the same shared code and store data the same way, so
          everything below applies to both unless a sentence says otherwise.
        </P>
        <P>
          The project repository also contains an earlier browser version of Wealth Compass that runs on
          Supabase. It is a separate application with its own storage, described on its own terms in
          section 07. Nothing in it can reach the data held by the iPhone and Mac apps.
        </P>
        <P>
          Wealth Compass is written and published by Simone Mattioli, Verona, Italy. There is no company
          behind it and no other party with access to anything described here.
        </P>
      </>
    ),
  },
  {
    id: 'storage',
    title: 'What the apps store, and where',
    body: (
      <>
        <P>
          Everything you enter — transactions, recurring schedules, investments, cryptocurrency holdings,
          liabilities, categories, and net-worth snapshots — is written to a single JSON file inside the
          app's own container, at <Id>Application Support/Wealth Compass/wealth-compass-local-data.json</Id>.
          On iOS that file is written with complete-unless-open file protection, so it is encrypted at rest
          while the device is locked. <Key>None of it is transmitted to the developer</Key>, who runs no
          server that could receive it.
        </P>
        <List
          items={[
            <>
              Preferences — display currency, privacy mode, in-app language, the iCloud toggle — are kept in
              UserDefaults. Both privacy manifests declare that use with reason code <Id>CA92.1</Id>: app
              functionality, readable only by this app.
            </>,
            <>
              Optional market-data API keys are stored in the Keychain under the service{' '}
              <Id>com.wealthcompass.mobile.marketdata</Id>. They are not marked synchronizable, so they never
              reach iCloud Keychain or the sync described in section 03.
            </>,
            <>
              There is no registration, no account, and no sign-in screen. The apps carry no analytics,
              advertising, or attribution SDK — in fact they have no third-party dependencies at all, only
              Apple's own frameworks.
            </>,
          ]}
        />
      </>
    ),
  },
  {
    id: 'icloud',
    title: 'Optional iCloud sync',
    body: (
      <>
        <P>
          iCloud sync is <Key>off until you turn it on</Key> in Settings. With it on, the apps use CloudKit
          to keep your own devices in step: six record types — transactions, recurring transactions,
          investments, crypto holdings, liabilities and net-worth snapshots — are written to the{' '}
          <Key>private database</Key> of the container <Id>iCloud.com.wealthcompasstracker</Id>, under your
          Apple Account.
        </P>
        <P>
          That private database belongs to you. The developer has no access to it and receives no copy of
          it; Apple operates it under Apple's own privacy policy. Apple's push service is used to tell your
          other devices that something changed. Your API keys and the preferences in section 02 are never
          synced.
        </P>
        <P>
          Turning the toggle off stops sync. The synced copy can be removed from your Apple Account's iCloud
          storage settings, on the device or at iCloud.com.
        </P>
      </>
    ),
  },
  {
    id: 'network',
    title: 'Network requests and third-party providers',
    body: (
      <>
        <P>
          The apps contact four services, and only to carry out something you asked for. Each request goes
          from your device <Key>straight to the provider</Key>. There is no proxy or intermediary operated by
          the developer, so there is no point at which your keys, your IP address, or the symbols you look up
          pass through developer infrastructure.
        </P>
        <List
          items={[
            <>
              <Key>Frankfurter</Key> — European Central Bank reference exchange rates. Keyless. Refreshed
              when the stored rates are more than twelve hours old.
            </>,
            <>
              <Key>Finnhub</Key> — stock and ETF quotes, only once you supply an API key. The key travels as
              an <Id>X-Finnhub-Token</Id> request header.
            </>,
            <>
              <Key>CoinGecko</Key> — cryptocurrency prices and coin lookup, only once you supply an API key,
              sent as an <Id>x-cg-demo-api-key</Id> header.
            </>,
            <>
              <Key>Yahoo Finance</Key> — keyless fallback for instruments Finnhub's free tier cannot price,
              such as European-listed ETFs, and for resolving a ticker or ISIN to a concrete listing.
            </>,
          ]}
        />
        <P>
          A request carries only what the provider needs to answer it: a currency pair, a ticker symbol, an
          ISIN, or a coin identifier. It carries none of your amounts, balances, quantities or account
          names. A key is sent only to the provider that issued it. Providers see ordinary network metadata
          such as your IP address and handle it under their own privacy policies.
        </P>
      </>
    ),
  },
  {
    id: 'device',
    title: 'Device features you switch on',
    body: (
      <List
        items={[
          <>
            <Key>Face ID or Touch ID app lock.</Key> Authentication is performed by Apple's
            LocalAuthentication framework. The app receives a yes or a no; it never sees biometric data.
          </>,
          <>
            <Key>Reminders for recurring transactions</Key> are scheduled as local notifications. They are
            created on the device and pass through no server.
          </>,
          <>
            <Key>Export</Key> produces a PDF report or a JSON backup and hands the file to the share sheet.
            Where it goes next is your choice, and the file is then yours to manage.
          </>,
          <>
            <Key>Import</Key> reads a JSON backup or a broker statement you pick with the file picker —
            Trade Republic and Revolut CSV, Trade Republic PDF. Parsing happens on the device; the file is
            not uploaded anywhere.
          </>,
          <>
            <Key>Export Sync Diagnostics</Key> writes a support file containing counts, timings and error
            text only — no amounts and no records — which you then decide whether to send.
          </>,
        ]}
      />
    ),
  },
  {
    id: 'tracking',
    title: 'No tracking, advertising, or sale of data',
    body: (
      <>
        <P>
          Wealth Compass does not sell personal information, does not show advertising, does not use the
          Advertising Identifier, and does not track you across apps or websites owned by other companies.
        </P>
        <P>
          Both privacy manifests set <Id>NSPrivacyTracking</Id> to false and declare an empty{' '}
          <Id>NSPrivacyCollectedDataTypes</Id> list. That is what produces the{' '}
          <Key>Data Not Collected</Key> label on the App Store listing, and you can read the manifests
          yourself in the <Out href={REPO}>repository</Out>. The apps set no cookies. This website sets no
          cookies and loads nothing from a third party.
        </P>
      </>
    ),
  },
  {
    id: 'web',
    title: 'The separate web application',
    body: (
      <>
        <P>
          Before the Apple apps there was a browser version of Wealth Compass, and its code is still in the
          repository. It is <Key>source-available under the PolyForm Noncommercial 1.0.0 licence</Key> —
          which is not the same as open source, since it grants no commercial use — and it works differently
          from the App Store apps in ways that matter here.
        </P>
        <P>
          Whoever deploys it supplies their own Supabase project, hosting and API keys, and that person or
          organisation is responsible for the data in it. In that application, and not in the iPhone and Mac
          apps:
        </P>
        <List
          items={[
            <>
              Sign-in is by email and password against the operator's Supabase project. A deployment can
              restrict sign-in to one configured address.
            </>,
            <>
              Financial records live in that Supabase database rather than on your device, and interface
              preferences are held in browser <Id>localStorage</Id>.
            </>,
            <>
              A Finnhub API key entered there is written to the operator's <Id>profiles</Id> table — a
              database row, not a keychain.
            </>,
          ]}
        />
        <P>
          A copy of the web application is served from this site under <Id>/sw</Id>, and it functions only
          against a Supabase project whose credentials were supplied when the site was built. No account
          created there is connected to the App Store apps: none of its data reaches them, and none of
          theirs reaches it. <Key>The developer does not operate a consumer account service</Key> for the
          iPhone or Mac apps.
        </P>
      </>
    ),
  },
  {
    id: 'retention',
    title: 'Retention, and what you can delete',
    body: (
      <>
        <P>
          The developer retains nothing from the iPhone and Mac apps, because nothing from them is
          transmitted to the developer in the first place. What you can do:
        </P>
        <List
          items={[
            <>Edit or delete any individual record inside the app.</>,
            <>
              Use <Key>Delete All Data</Key> in Settings to erase the local database.
            </>,
            <>
              Turn off iCloud sync, and remove the app's iCloud data from your Apple Account's storage
              settings.
            </>,
            <>Delete the app, which removes its container and the local database with it.</>,
          ]}
        />
        <P>
          Files you exported stay wherever you saved or sent them. Only you can remove those.
        </P>
      </>
    ),
  },
  {
    id: 'children',
    title: 'Children',
    body: (
      <P>
        Wealth Compass is a general-purpose personal finance utility and is not directed to children. The
        apps ask for no personal information from anyone, and so do not knowingly collect any from children.
      </P>
    ),
  },
  {
    id: 'changes',
    title: 'Changes to this policy',
    body: (
      <P>
        This policy is revised when the apps' behaviour or the applicable rules change. The dates at the top
        of this page identify the current revision, and the history of this file is public in the{' '}
        <Out href={REPO}>repository</Out>.
      </P>
    ),
  },
  {
    id: 'contact',
    title: 'Contact',
    body: (
      <>
        <P>
          Wealth Compass is written and published by Simone Mattioli in Verona, Italy. For any question
          about this policy, or to ask what the apps do in a case it does not cover, write to{' '}
          <Out href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</Out>.
        </P>
        <P>
          The source behind every claim on this page is public. The licence it is published under is{' '}
          <Out href={LICENSE}>PolyForm Noncommercial 1.0.0</Out>.
        </P>
      </>
    ),
  },
];

/** Two digits, so the index and the section marks line up in the monospace face. */
const mark = (i: number) => String(i + 1).padStart(2, '0');

export const PrivacyPolicy = () => {
  return (
    <div className="page" style={{ paddingBlock: 'clamp(2.5rem, 6vw, 4.5rem) clamp(4rem, 9vw, 7rem)' }}>
      <header style={{ display: 'grid', gap: '1.1rem', maxWidth: measure }}>
        <p className="eyebrow">Legal</p>
        <h1 className="display display-l">Privacy policy</h1>
        <p className="mono" style={{ fontSize: 12, letterSpacing: '0.08em', color: 'var(--ink-faint)' }}>
          {REVISION}
        </p>
        <p className="lede" style={{ marginTop: '0.4rem' }}>
          Wealth Compass keeps your financial records on your own device. There is no account, no server
          run by the developer, and no analytics. This page sets out exactly what is stored, what leaves the
          device, and what you can delete.
        </p>
      </header>

      {/* The claims a reader most often wants, before the eleven sections that evidence them. */}
      <div
        className="source-strip"
        style={{ display: 'grid', gap: '1.1rem', maxWidth: measure, marginTop: 'clamp(2rem, 4vw, 3rem)' }}
      >
        <p className="eyebrow">In short</p>
        <List
          items={[
            <>No account. Nothing to sign up for and nothing to sign in to.</>,
            <>Your records are written to one file inside the app's own container on your device.</>,
            <>
              Both apps ship a privacy manifest declaring no collected data types and no tracking. That is
              the App Store's Data Not Collected label.
            </>,
            <>
              iCloud sync is off unless you turn it on. When on, records go to your own private iCloud
              database, which the developer cannot read.
            </>,
            <>Prices and exchange rates are fetched straight from the provider. Nothing sits in between.</>,
          ]}
        />
      </div>

      <nav aria-label="Contents" style={{ marginTop: 'clamp(2.5rem, 5vw, 3.5rem)' }}>
        <p className="eyebrow">Contents</p>
        <ol
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(16rem, 1fr))',
            gap: '0.6rem 2.5rem',
            margin: '1.1rem 0 0',
            padding: 0,
            listStyle: 'none',
          }}
        >
          {SECTIONS.map((section, i) => (
            <li key={section.id} style={{ display: 'grid', gridTemplateColumns: '2.25rem 1fr', alignItems: 'baseline' }}>
              <span className="mono" style={{ fontSize: 12, color: 'var(--ink-faint)' }}>
                {mark(i)}
              </span>
              <a href={`#${section.id}`} className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
                {section.title}
              </a>
            </li>
          ))}
        </ol>
      </nav>

      <div style={{ display: 'grid', marginTop: 'clamp(3rem, 6vw, 4.5rem)' }}>
        {SECTIONS.map((section, i) => (
          <section
            key={section.id}
            id={section.id}
            style={{
              display: 'grid',
              gap: '0.85rem',
              paddingTop: 'clamp(2.5rem, 5vw, 3.75rem)',
              paddingBottom: 'clamp(2.5rem, 5vw, 3.75rem)',
              borderTop: '1px solid var(--rule-soft)',
            }}
          >
            <p className="eyebrow">{mark(i)}</p>
            <h2 className="display display-m" style={{ maxWidth: '26ch' }}>
              {section.title}
            </h2>
            <div style={{ display: 'grid', gap: '1.1rem', marginTop: '0.35rem' }}>{section.body}</div>
          </section>
        ))}
      </div>

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '1rem 2rem',
          justifyContent: 'space-between',
          paddingTop: 'clamp(2rem, 4vw, 3rem)',
          borderTop: '1px solid var(--rule-soft)',
        }}
      >
        <Link to="/terms/" className="u-link" style={{ fontSize: 15 }}>
          Terms of service →
        </Link>
        <Link to="/support/" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
          Support
        </Link>
      </div>
    </div>
  );
};
