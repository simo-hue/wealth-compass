import { Link } from 'react-router-dom';
import { ISSUES, LICENSE, REPO, SUPPORT_EMAIL } from '../site/links';

/**
 * The licence page, and the one place in the site that is allowed to spend
 * --seal. The single use below is deliberate: if a second one ever
 * appears anywhere in this site, the token has stopped meaning "this is the
 * licence" and started meaning "accent colour".
 *
 * The stamp is aria-hidden because the sentence beside it says the same thing in
 * words, and a screen reader reading a decorative ring twice is worse than not
 * reading it at all.
 */
function LicenceSeal() {
  return (
    <div aria-hidden="true" style={{ color: 'var(--seal)', flexShrink: 0, lineHeight: 0 }}>
      <svg width="112" height="112" viewBox="0 0 112 112" fill="none">
        <circle cx="56" cy="56" r="54" stroke="currentColor" strokeWidth="1" opacity="0.42" />
        <circle cx="56" cy="56" r="47" stroke="currentColor" strokeWidth="1" strokeDasharray="1.5 4.5" opacity="0.75" />
        {/* font-family goes in `style`, not as a presentation attribute: Chrome
            does not substitute var() in presentation attributes, and the seal
            would silently fall back to the UA serif. */}
        <g
          fill="currentColor"
          fontSize="9.5"
          fontWeight="500"
          letterSpacing="1.5"
          textAnchor="middle"
          style={{ fontFamily: 'var(--data)' }}
        >
          <text x="56" y="46">SOURCE</text>
          <text x="56" y="59">AVAILABLE</text>
        </g>
        <line x1="34" y1="66" x2="78" y2="66" stroke="currentColor" strokeWidth="1" opacity="0.42" />
        <text
          x="56"
          y="79"
          fill="currentColor"
          fontSize="8"
          letterSpacing="1.2"
          textAnchor="middle"
          opacity="0.85"
          style={{ fontFamily: 'var(--data)' }}
        >
          NOT OSI
        </text>
      </svg>
    </div>
  );
}

/** Terminal blocks and the directory tree. Scrolls sideways rather than wrapping. */
function Code({ children, caption }: { children: string; caption?: string }) {
  return (
    <div
      style={{
        background: 'var(--canvas-deep)',
        border: '1px solid var(--rule)',
        borderRadius: 10,
        overflow: 'hidden',
      }}
    >
      {caption && (
        <p
          className="mono"
          style={{
            fontSize: 10,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            color: 'var(--ink-faint)',
            padding: '0.6rem 1rem 0',
          }}
        >
          {caption}
        </p>
      )}
      <pre
        className="mono"
        style={{
          margin: 0,
          padding: '0.9rem 1rem 1rem',
          fontSize: 13,
          lineHeight: 1.75,
          color: 'var(--ink)',
          overflowX: 'auto',
        }}
      >
        {children}
      </pre>
    </div>
  );
}

function Rule() {
  return <hr className="rule" style={{ marginBlock: 'clamp(3rem, 6vw, 5rem)' }} />;
}

/** A permission or a prohibition. The marker is a glyph, not a colour — the site
    palette is achromatic and yes/no in red and green is not available to it. */
function Clause({ mark, children }: { mark: '+' | '−'; children: React.ReactNode }) {
  return (
    <li style={{ display: 'flex', gap: '0.75rem', alignItems: 'baseline' }}>
      <span
        className="mono"
        aria-hidden="true"
        style={{ color: mark === '+' ? 'var(--ink)' : 'var(--ink-faint)', fontSize: 14, flexShrink: 0 }}
      >
        {mark}
      </span>
      <span style={{ color: 'var(--ink-muted)' }}>{children}</span>
    </li>
  );
}

function ClauseList({ title, note, mark, items }: {
  title: string;
  note: string;
  mark: '+' | '−';
  items: React.ReactNode[];
}) {
  return (
    <div
      style={{
        background: 'var(--surface)',
        border: '1px solid var(--rule)',
        borderRadius: 14,
        padding: 'clamp(1.25rem, 2.5vw, 1.75rem)',
        display: 'grid',
        gap: '1rem',
        alignContent: 'start',
      }}
    >
      <div style={{ display: 'grid', gap: '0.4rem' }}>
        <p className="eyebrow">{title}</p>
        <p style={{ fontSize: 14, color: 'var(--ink-faint)' }}>{note}</p>
      </div>
      <ul style={{ display: 'grid', gap: '0.7rem', margin: 0, padding: 0, listStyle: 'none' }}>
        {items.map((item, i) => (
          <Clause key={i} mark={mark}>
            {item}
          </Clause>
        ))}
      </ul>
    </div>
  );
}

/** One numbered step of the self-hosting guide. */
function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <li style={{ display: 'grid', gap: '0.85rem', paddingBlock: '1.75rem', borderTop: '1px solid var(--rule-soft)' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: '0.9rem' }}>
        <span className="mono num" style={{ fontSize: 12, color: 'var(--ink-faint)', letterSpacing: '0.1em' }}>
          {String(n).padStart(2, '0')}
        </span>
        <h3 className="display display-m" style={{ fontSize: '1.15rem' }}>
          {title}
        </h3>
      </div>
      <div style={{ display: 'grid', gap: '0.85rem', maxWidth: '68ch' }}>{children}</div>
    </li>
  );
}

const REPO_TREE = `wealth-compass/
├── apple/                        the native iPhone and Mac apps — SwiftUI, one Xcode project
│   └── WealthCompass/
│       ├── Sources/Shared/       domain code both platforms use
│       ├── Sources/iOS/          the iPhone app
│       ├── Sources/macOS/        the Mac app, built against the macOS SDK
│       ├── Resources/            asset catalogues and String Catalogues
│       └── WealthCompass.xcodeproj
├── web-app/                      the React + Supabase web app — and this page
│   ├── src/                      application source
│   ├── public/                   static assets and the PWA manifest
│   └── package.json              build, lint and deploy scripts
└── LICENSE                       PolyForm Noncommercial 1.0.0`;

const paragraph = { color: 'var(--ink-muted)', maxWidth: 'var(--measure)' } as const;

export const OpenSource = () => {
  return (
    <>
      {/* ------------------------------------------------------------- opening */}
      <section className="page" style={{ paddingBlock: 'clamp(3rem, 7vw, 5.5rem) 0' }}>
        <p className="eyebrow">Where everything started</p>
        <h1 className="display display-xl" style={{ maxWidth: '15ch', marginBlock: '1rem 1.4rem' }}>
          Source available. Not open source.
        </h1>
        <p className="lede">
          Every line of Wealth Compass is public — the Apple apps and the web app that came before
          them. The licence is PolyForm Noncommercial 1.0.0. It lets you read, build, change and
          redistribute the software, and it stops at one line: you may not use it for a commercial
          purpose. That restriction is why this page does not call the project open source.
        </p>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '1.5rem', marginTop: '1.8rem' }}>
          <a href={REPO} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15 }}>
            The repository →
          </a>
          <a href={LICENSE} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
            Read the licence →
          </a>
        </div>
      </section>

      {/* ---------------------------------------------------------- the licence */}
      <section className="page" style={{ paddingTop: 'clamp(2.5rem, 5vw, 3.5rem)' }} aria-label="The licence">
        <div
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            alignItems: 'center',
            gap: 'clamp(1.5rem, 4vw, 3rem)',
            padding: 'clamp(1.5rem, 3vw, 2.5rem)',
            background: 'var(--surface)',
            border: '1px solid var(--rule)',
            borderRadius: 14,
          }}
        >
          <LicenceSeal />
          <div style={{ display: 'grid', gap: '0.9rem', flex: '1 1 30ch' }}>
            <p className="mono" style={{ fontSize: 12, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--ink-faint)' }}>
              PolyForm Noncommercial 1.0.0
            </p>
            <p style={{ fontSize: 'clamp(1.0625rem, 1.5vw, 1.25rem)', lineHeight: 1.5, maxWidth: '44ch' }}>
              Source-available. The Open Source Definition requires a licence not to restrict the field
              of endeavour; this one restricts it to noncommercial use, so it is not OSI-approved and
              the term open source does not apply to it.
            </p>
            <p style={{ fontSize: 14, color: 'var(--ink-faint)', maxWidth: '52ch' }}>
              The licence puts it in one sentence: any noncommercial purpose is a permitted purpose.
              Everything below is a summary. The file in the repository root is what actually binds.
            </p>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------ can and cannot */}
      <section className="page" style={{ paddingTop: 'clamp(3rem, 6vw, 5rem)' }} aria-label="What the licence permits">
        <h2 className="display display-l" style={{ maxWidth: '18ch', marginBottom: '2rem' }}>
          What you can and cannot do with it
        </h2>

        <div style={{ display: 'grid', gap: '1.25rem', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))' }}>
          <ClauseList
            title="You can"
            note="For any noncommercial purpose."
            mark="+"
            items={[
              'Read every line of both implementations, including the parts that handle your money.',
              'Build the Apple apps yourself in Xcode and run them on your own devices.',
              'Run the web app on your own machine or your own server, for your own use.',
              'Change it and build new work on top of it.',
              'Redistribute copies, as long as whoever receives them also receives these terms.',
              'Use it inside a charity, school, public research body, health or safety body, or government institution — the licence names those as permitted regardless of how they are funded.',
            ]}
          />
          <ClauseList
            title="You cannot"
            note="These are conditions of the licence, not preferences."
            mark="−"
            items={[
              'Use it for a commercial purpose — not the app, not a fork, not a component lifted out of it.',
              'Sell it, run it as a paid service, or bundle it into something you sell.',
              'Sublicense it or hand your rights to anyone else.',
              'Rely on a warranty. The software comes as is, and the author is not liable for what it does.',
            ]}
          />
        </div>

        <div style={{ display: 'grid', gap: '0.9rem', marginTop: '2rem', maxWidth: 'var(--measure)' }}>
          <p style={paragraph}>
            The dividing line is anticipated commercial application, not money changing hands today. A
            hobby project, private study, or a fork you run for yourself is inside it. A prototype for
            something you intend to sell is outside it, on the first day of the prototype.
          </p>
          <p style={paragraph}>
            Nothing in the licence stops the copyright holder from granting different terms to someone
            who asks. If you want to use this commercially,{' '}
            <a href={`mailto:${SUPPORT_EMAIL}`} className="u-link" style={{ color: 'var(--ink)' }}>
              ask
            </a>
            . This page is a plain-language summary written by the author, not legal advice.
          </p>
        </div>
      </section>

      <div className="page">
        <Rule />
      </div>

      {/* ------------------------------------------------------------- the repo */}
      <section className="page" aria-label="Repository layout">
        <p className="eyebrow">The repository</p>
        <h2 className="display display-l" style={{ maxWidth: '20ch', marginBlock: '0.7rem 1.2rem' }}>
          Two implementations, one product
        </h2>
        {/* Deliberately not the root README's "they share the JSON backup format":
            the web app can write a JSON backup but has no import path at all, so
            that sentence promises a round trip the code does not do. */}
        <p className="lede" style={{ marginBottom: '2rem' }}>
          One repository holds both. Not one line of code crosses between them — Swift on one side,
          TypeScript on the other. Both can write a JSON backup of your data; only the Apple apps can
          read one back in. Treat them as two implementations of one product, not two halves of it.
        </p>

        <Code caption="Repository layout">{REPO_TREE}</Code>

        <div style={{ display: 'grid', gap: '0.9rem', marginTop: '1.5rem' }}>
          <p style={paragraph}>
            <span className="mono" style={{ color: 'var(--ink)' }}>apple/</span> is the current
            product: the iPhone and Mac apps, one Xcode project, two targets, local-first storage in
            the app sandbox. Open{' '}
            <span className="mono" style={{ fontSize: 13 }}>apple/WealthCompass/WealthCompass.xcodeproj</span>{' '}
            and pick the target.
          </p>
          <p style={paragraph}>
            <span className="mono" style={{ color: 'var(--ink)' }}>web-app/</span> is the React app —
            and also this marketing site, which is built from the same bundle. The web app itself
            lives under the <span className="mono" style={{ fontSize: 13 }}>/sw</span> route and is
            loaded lazily, so none of Supabase reaches the page you are reading now.
          </p>
        </div>
      </section>

      <div className="page">
        <Rule />
      </div>

      {/* --------------------------------------------------------- self-hosting */}
      <section className="page" aria-label="Self-hosting the web app">
        <p className="eyebrow">Self-hosting the web app</p>
        <h2 className="display display-l" style={{ maxWidth: '20ch', marginBlock: '0.7rem 1.2rem' }}>
          Run your own copy of it
        </h2>
        <p className="lede">
          Five steps on any machine with Node and Git, plus a database schema you create by hand —
          there is no migration file to run. Read the caveats underneath first: this is the older
          implementation, and it is not local-first.
        </p>

        <ol style={{ margin: '2.5rem 0 0', padding: 0, listStyle: 'none', display: 'grid' }}>
          <Step n={1} title="Prerequisites">
            <p style={paragraph}>
              Node.js 18 or newer, Git, and a free Supabase account. A Finnhub API key is optional and
              only powers stock and ETF prices; without one the rest of the app still works.
            </p>
          </Step>

          <Step n={2} title="Clone and install">
            <p style={paragraph}>
              Everything below runs from <span className="mono" style={{ fontSize: 13 }}>web-app/</span>,
              not the repository root.
            </p>
            <Code>{`git clone ${REPO}.git
cd wealth-compass/web-app
npm install`}</Code>
          </Step>

          <Step n={3} title="Create a Supabase project">
            <p style={paragraph}>
              Create a project, enable email-and-password authentication, and create the six tables the
              app reads: <span className="mono" style={{ fontSize: 13 }}>assets</span>,{' '}
              <span className="mono" style={{ fontSize: 13 }}>liabilities</span>,{' '}
              <span className="mono" style={{ fontSize: 13 }}>liquidity_accounts</span>,{' '}
              <span className="mono" style={{ fontSize: 13 }}>portfolio_snapshots</span>,{' '}
              <span className="mono" style={{ fontSize: 13 }}>transactions</span> and{' '}
              <span className="mono" style={{ fontSize: 13 }}>profiles</span>. There is no migration
              file in the repository, so this part is manual. Sign-in is email and password only —
              there is no magic-link or one-time-code flow to configure.
            </p>
          </Step>

          <Step n={4} title="Write the .env">
            <p style={paragraph}>
              A <span className="mono" style={{ fontSize: 13 }}>.env</span> file in{' '}
              <span className="mono" style={{ fontSize: 13 }}>web-app/</span>, next to{' '}
              <span className="mono" style={{ fontSize: 13 }}>package.json</span>. The URL and anon key
              are in Supabase under Project Settings → API. The repository ships an{' '}
              <span className="mono" style={{ fontSize: 13 }}>env_example.txt</span> with the same
              names.
            </p>
            <Code caption="web-app/.env">{`VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key

# Optional
VITE_FINNHUB_API_KEY=stock_and_etf_prices
VITE_ALLOWED_EMAIL=only_this_address_may_sign_in`}</Code>
            <p style={{ ...paragraph, fontSize: 14 }}>
              The anon key is a public key and ends up in the built bundle by design. What protects
              your rows is Supabase Row Level Security, which you configure on the project —
              setting <span className="mono" style={{ fontSize: 13 }}>VITE_ALLOWED_EMAIL</span> is a
              convenience in the client, not a security boundary.
            </p>
          </Step>

          <Step n={5} title="Run it">
            <Code>{`npm run dev`}</Code>
            <p style={paragraph}>
              Vite is configured for port 8080, and the router is mounted at the{' '}
              <span className="mono" style={{ fontSize: 13 }}>/wealth-compass</span> sub-path because
              that is where GitHub Pages serves it. The app is therefore at{' '}
              <span className="mono" style={{ fontSize: 13 }}>http://localhost:8080/wealth-compass/sw</span>.
              To serve it from the root of your own domain, change{' '}
              <span className="mono" style={{ fontSize: 13 }}>base</span> in{' '}
              <span className="mono" style={{ fontSize: 13 }}>vite.config.ts</span> and{' '}
              <span className="mono" style={{ fontSize: 13 }}>BASENAME</span> in{' '}
              <span className="mono" style={{ fontSize: 13 }}>src/App.tsx</span> together — they have
              to agree. <span className="mono" style={{ fontSize: 13 }}>npm run build</span> puts a
              static bundle in <span className="mono" style={{ fontSize: 13 }}>dist/</span>.
            </p>
          </Step>
        </ol>
      </section>

      {/* -------------------------------------------------------------- caveats */}
      <section className="page" style={{ paddingTop: 'clamp(3rem, 6vw, 5rem)' }} aria-label="What the web app is not">
        <div
          style={{
            display: 'grid',
            gap: '1.1rem',
            padding: 'clamp(1.5rem, 3vw, 2.25rem)',
            background: 'var(--canvas-deep)',
            border: '1px solid var(--rule)',
            borderRadius: 14,
          }}
        >
          <p className="eyebrow">Before you invest an evening in it</p>
          <p style={paragraph}>
            The web app came first and the Apple apps replaced it. New work happens in{' '}
            <span className="mono" style={{ fontSize: 13 }}>apple/</span>; the last change to the web
            app's application code was moving it into its own directory. Check the commit history
            before you assume otherwise — that is the whole point of the source being public.
          </p>
          <p style={paragraph}>
            It is also not local-first, which is the one claim this site makes loudest about the Apple
            apps. The web app keeps your records in a Postgres database at Supabase. That database is
            yours, on your own account, and none of it reaches me — but it does leave your machine,
            and you are the one responsible for its access rules and its backups.
          </p>
          <p style={paragraph}>
            Deployment is manual: <span className="mono" style={{ fontSize: 13 }}>npm run deploy</span>{' '}
            builds and pushes to a <span className="mono" style={{ fontSize: 13 }}>gh-pages</span>{' '}
            branch. There is no CI workflow, no hosted instance you can sign up for, and no support
            commitment attached to a copy you run yourself.
          </p>
        </div>
      </section>

      {/* ---------------------------------------------------------------- close */}
      <section className="page" style={{ paddingBlock: 'clamp(3rem, 7vw, 6rem)' }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '1.5rem 2.5rem', alignItems: 'baseline' }}>
          <a href={REPO} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15 }}>
            Browse the source →
          </a>
          <a href={LICENSE} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
            LICENSE →
          </a>
          <a href={ISSUES} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
            Report a bug →
          </a>
          <Link to="/faq/" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
            Questions about the app →
          </Link>
        </div>
      </section>
    </>
  );
};
