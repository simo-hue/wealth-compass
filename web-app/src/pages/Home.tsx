import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Horizon } from '../site/Horizon';
import { StoreButton } from '../site/SiteLayout';
import { appStore, LICENSE, REPO } from '../site/links';
import { SimProvider } from '../sim/SimProvider';
import { useElementWidth } from '../sim/ui';
import { IPhone, type TabKey } from '../sim/ios/IPhone';
import { DashboardScreen } from '../sim/ios/DashboardScreen';
import { CashFlowScreen } from '../sim/ios/CashFlowScreen';
import { InvestmentsScreen } from '../sim/ios/InvestmentsScreen';
import { CryptoScreen } from '../sim/ios/CryptoScreen';
import { SettingsScreen } from '../sim/ios/SettingsScreen';
import { MacWindow, type MacDestination } from '../sim/mac/MacWindow';
import { MacDashboard } from '../sim/mac/MacDashboard';
import { MacInvestments } from '../sim/mac/MacInvestments';
import { MacCashFlow } from '../sim/mac/MacCashFlow';

/**
 * Matches the breakpoint at which site.css reveals `.hero-mac`. Duplicated here
 * because the hero Mac is gated twice: CSS decides whether the stage is visible,
 * this decides whether its 1440×900 simulation is built at all.
 *
 * The two numbers have to agree. When this said 900px the whole Mac dashboard —
 * six metric cards, three donuts, a bar chart and a table — was mounted into a
 * `display: none` container for every viewport from 900 to 1179px, on exactly
 * the machines least able to afford it, and `useElementWidth` measured 0 on the
 * hidden box so the width handed to MacWindow was meaningless anyway.
 */
const HERO_MAC_QUERY = '(min-width: 1180px)';

/**
 * Every device on this page renders the same synthetic dataset, and unlabelled
 * money is the one thing on a finance site that must not be mistaken for a fact
 * about the product. Each device frame carries this caption *and* sits inside a
 * `data-nosnippet` block: the attribute is honoured by Google on a div, span or
 * section — no headers, no scripts, nothing a static host cannot serve — and
 * keeps the figures out of snippets and AI extraction while leaving them fully
 * rendered and indexed. The caption covers the engines that ignore it, and is
 * owed to the reader regardless.
 */
const SAMPLE_NOTE = 'Sample data. The figures are illustrative.';

/**
 * False during server render and during the client's first render, so the
 * prerendered HTML and hydration always agree; the real answer arrives in an
 * effect. Any content this gates can therefore only ever be added after
 * hydration, never swapped underneath it.
 */
function useMatchesAfterMount(query: string) {
  const [matches, setMatches] = useState(false);
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mql = window.matchMedia(query);
    const sync = () => setMatches(mql.matches);
    sync();
    mql.addEventListener('change', sync);
    return () => mql.removeEventListener('change', sync);
  }, [query]);
  return matches;
}

/** The five places the app actually is — the tab bar is the section's navigation. */
const AREAS: { tab: TabKey; eyebrow: string; title: string; body: string }[] = [
  {
    tab: 'dashboard',
    eyebrow: 'Dashboard',
    title: 'The whole picture, on one screen',
    body: 'Net worth, what it is made of, and how it got there. Cash, investments, crypto and debts are added up together, in a single currency, with the history behind the number.',
  },
  {
    tab: 'cashFlow',
    eyebrow: 'Cash flow',
    title: 'Where the money goes',
    body: 'Income and expenses by month, grouped by category. Mark a transaction as recurring and it books itself on schedule, with a local reminder if you want one.',
  },
  {
    tab: 'investments',
    eyebrow: 'Investments',
    title: 'Positions, cost basis, profit and loss',
    body: 'Stocks and ETFs priced from Finnhub using an API key you provide. See allocation by sector, by type and by geography, and what each position has actually done.',
  },
  {
    tab: 'crypto',
    eyebrow: 'Crypto',
    title: 'Coins, valued alongside everything else',
    body: 'Holdings priced from CoinGecko and converted into your currency, so crypto sits in the same total as your current account rather than in a separate app.',
  },
  {
    tab: 'settings',
    eyebrow: 'Settings',
    title: 'Your rules',
    body: 'Change the display currency, hide every figure with Privacy Mode, or switch language — the app speaks 35. The controls on this screen are live: change one and every screen on this page changes with it.',
  },
];

/** Scroll drives the tab bar; tapping a tab scrolls to its block. Both directions. */
function AreasSection() {
  const [tab, setTab] = useState<TabKey>('dashboard');
  const phoneBox = useElementWidth<HTMLDivElement>(300);
  const blockRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        const index = blockRefs.current.indexOf(visible.target as HTMLDivElement);
        if (index >= 0) setTab(AREAS[index].tab);
      },
      // A band across the middle of the viewport, so the active block is the one
      // the reader is actually looking at rather than whatever entered last.
      { rootMargin: '-45% 0px -45% 0px', threshold: 0 },
    );
    blockRefs.current.forEach((node) => node && observer.observe(node));
    return () => observer.disconnect();
  }, []);

  const goToTab = (next: TabKey) => {
    setTab(next);
    const index = AREAS.findIndex((area) => area.tab === next);
    blockRefs.current[index]?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  const Screen = {
    dashboard: DashboardScreen,
    cashFlow: CashFlowScreen,
    investments: InvestmentsScreen,
    crypto: CryptoScreen,
    settings: SettingsScreen,
  }[tab];

  return (
    <section id="areas" className="page areas" aria-label="What the app does">
      <div className="areas-device" data-nosnippet>
        {/* The caption sits *above* the phone here, unlike the other two frames.
            Under 900px .areas-device is sticky and its backdrop is a gradient
            that fades to transparent across its bottom fifth, so a caption below
            the device would have the scrolling copy running through it. The top
            of that gradient is opaque. */}
        <div style={{ display: 'grid', gap: '0.75rem', width: 'min(300px, 62vw)' }}>
          <p className="eyebrow" style={{ textAlign: 'center' }}>
            {SAMPLE_NOTE}
          </p>
          <div ref={phoneBox.ref}>
            <IPhone width={phoneBox.width} activeTab={tab} onSelectTab={goToTab} label="Feature tour iPhone">
              <Screen />
            </IPhone>
          </div>
        </div>
      </div>

      <div className="areas-copy">
        {AREAS.map((area, i) => (
          <div
            key={area.tab}
            ref={(node) => {
              blockRefs.current[i] = node;
            }}
            className="areas-block"
          >
            <p className="eyebrow">{area.eyebrow}</p>
            <h2 className="display display-l" style={{ marginBlock: '0.6rem 1rem' }}>
              {area.title}
            </h2>
            <p className="lede">{area.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/** The Mac gets width rather than a scaled-down copy of the phone. */
function MacSection() {
  const [destination, setDestination] = useState<MacDestination>('dashboard');
  const macBox = useElementWidth<HTMLDivElement>(1100);

  const Screen = {
    dashboard: MacDashboard,
    investments: MacInvestments,
    cashFlow: MacCashFlow,
    crypto: MacDashboard,
    settings: MacDashboard,
  }[destination];

  return (
    <section className="mac-section" aria-label="The Mac app">
      <div className="page" style={{ display: 'grid', gap: '1rem', marginBottom: '2.5rem' }}>
        <p className="eyebrow">Also on Mac · same purchase</p>
        <h2 className="display display-l" style={{ maxWidth: '18ch' }}>
          On the Mac, it spreads out
        </h2>
        <p className="lede">
          The same data, in a window with room for it. Six metrics across, three allocation rings side
          by side, and a table you can actually read. Buy it once and it is on both.
        </p>
      </div>

      <div data-nosnippet>
        <div className="mac-stage">
          <div ref={macBox.ref} className="mac-holder">
            <MacWindow width={macBox.width} selection={destination} onSelect={setDestination} label="Mac tour">
              <Screen />
            </MacWindow>
          </div>
        </div>
        <p className="page eyebrow" style={{ textAlign: 'center', marginTop: '1rem' }}>
          {SAMPLE_NOTE}
        </p>
      </div>
    </section>
  );
}

/**
 * Four claims, each checkable in under a minute without believing anything I say.
 *
 * Every proof that *can* be a link is one. A section headed "what you do not have
 * to take on faith" that then gives the reader nowhere to go is asking for faith,
 * and it is the one section on the site where the destination is the argument.
 * A proof with no `href` is a claim that is checkable by absence — inventing a
 * URL for it would undo the point.
 */
const PRIVACY_MANIFEST = `${REPO}/blob/main/apple/WealthCompass/Resources/iOS/PrivacyInfo.xcprivacy`;

const FACTS: {
  claim: string;
  detail: string;
  proofs: { label: string; href?: string }[];
}[] = [
  {
    claim: 'Data Not Collected',
    detail: "Apple's own privacy label on the App Store listing. The app declares no collected data types and no tracking.",
    proofs: [
      { label: "Apple's privacy label on the App Store", href: appStore('site-cta') },
      { label: 'The privacy manifest in the source', href: PRIVACY_MANIFEST },
    ],
  },
  {
    claim: 'No account',
    detail: 'There is nothing to sign up for. Your records live in one file in the app sandbox on your device.',
    proofs: [{ label: 'Nothing to verify — there is no sign-in screen' }],
  },
  {
    claim: 'Free, no purchases',
    detail: 'No in-app purchases, no subscription, no ads, no upsell. There is no purchase code in the app at all.',
    proofs: [{ label: 'The App Store listing — no in-app purchases', href: appStore('site-cta') }],
  },
  {
    claim: 'Source available',
    detail: 'Every line is public and you can build it yourself. Licensed PolyForm Noncommercial — source-available, not open source.',
    proofs: [
      { label: 'Read the source on GitHub', href: REPO },
      { label: 'The PolyForm Noncommercial licence', href: LICENSE },
    ],
  },
];

export const Home = () => {
  const [tab, setTab] = useState<TabKey>('dashboard');
  const [macDestination, setMacDestination] = useState<MacDestination>('dashboard');
  const macBox = useElementWidth<HTMLDivElement>(880);
  const phoneBox = useElementWidth<HTMLDivElement>(300);
  const heroMacVisible = useMatchesAfterMount(HERO_MAC_QUERY);

  return (
    <SimProvider>
      {/* ---------------------------------------------------------------- hero */}
      {/* Deliberately unclipped: an overflow rule here also cuts the devices' drop
          shadows off at the section edge. The full-bleed horizon is contained by
          .wc-site's overflow-x: clip instead — see the comment on it in site.css. */}
      <section style={{ position: 'relative', paddingTop: 'clamp(2.5rem, 5vw, 4.5rem)' }}>
        <div className="page" style={{ position: 'relative', zIndex: 1 }}>
          <div style={{ display: 'grid', gap: '1.6rem' }}>
            <p className="eyebrow">iPhone and Mac · one universal purchase</p>
            <h1 className="display display-xl" style={{ maxWidth: '16ch' }}>
              Everything you own, owe, earn, and spend.
            </h1>
            <p className="lede">
              Wealth Compass keeps your cash, investments, crypto and debts in one place and works out what
              they add up to. It runs on your device. There is no account to create.
            </p>

            <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '1.25rem', marginTop: '0.4rem' }}>
              <StoreButton placement="site-hero" />
              <a href={REPO} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
                Read the source
              </a>
            </div>

            <ul className="spec-strip" style={{ marginTop: '0.6rem', padding: 0 }}>
              <li>Free</li>
              <li>No account</li>
              <li>Data not collected</li>
              <li>iOS 17+ · macOS 14+</li>
            </ul>
          </div>
        </div>

        <div className="page hero-stage">
          {/* The trail runs the full viewport width as a hairline; inside the
              glass, the devices draw the same curve in the app's green. */}
          <div className="hero-horizon" aria-hidden="true">
            <Horizon />
          </div>

          <div data-nosnippet>
            <div className="hero-devices">
              {/* The stage is always in the DOM so it can be measured and so the
                  CSS breakpoint still governs layout; the Mac inside it is a whole
                  second dashboard — six metric cards, three donuts, a chart — and a
                  phone-sized visitor never sees it, so it is not built for them. */}
              <div ref={macBox.ref} className="hero-mac" style={{ flex: '1 1 0', minWidth: 0, maxWidth: 880 }}>
                {heroMacVisible && (
                  <MacWindow width={macBox.width} selection={macDestination} onSelect={setMacDestination} label="Hero Mac">
                    <MacDashboard />
                  </MacWindow>
                )}
              </div>
              <div ref={phoneBox.ref} className="hero-phone" style={{ flex: '0 0 auto', width: 'clamp(260px, 72vw, 310px)' }}>
                <IPhone width={phoneBox.width} activeTab={tab} onSelectTab={setTab} label="Hero iPhone">
                  <DashboardScreen />
                </IPhone>
              </div>
            </div>
            <p className="eyebrow" style={{ textAlign: 'center', marginTop: '1.5rem' }}>
              {SAMPLE_NOTE}
            </p>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------------- areas */}
      <AreasSection />

      {/* ----------------------------------------------------------------- mac */}
      <MacSection />

      {/* -------------------------------------------------------------- proof */}
      <section className="page" style={{ paddingBlock: 'clamp(4rem, 9vw, 8rem)' }} aria-label="What you can verify">
        <p className="eyebrow">What you do not have to take on faith</p>
        <h2 className="display display-l" style={{ maxWidth: '20ch', marginBlock: '0.7rem 2.5rem' }}>
          Four claims, all checkable
        </h2>
        <dl className="facts">
          {FACTS.map((fact) => (
            <div key={fact.claim} className="fact">
              <dt>
                <span className="mono fact-claim">{fact.claim}</span>
              </dt>
              <dd>
                <p style={{ color: 'var(--ink-muted)', maxWidth: '46ch' }}>{fact.detail}</p>
                {fact.proofs.map((proof) =>
                  proof.href ? (
                    <p key={proof.label} className="mono fact-proof">
                      {/* --ink-muted rather than the .fact-proof --ink-faint: this
                          one is a control, and it has to read as one. */}
                      <a
                        className="u-link"
                        href={proof.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ color: 'var(--ink-muted)' }}
                      >
                        {proof.label} ↗
                      </a>
                    </p>
                  ) : (
                    <p key={proof.label} className="mono fact-proof">
                      {proof.label}
                    </p>
                  ),
                )}
              </dd>
            </div>
          ))}
        </dl>
      </section>

      {/* ---------------------------------------------------------------- who */}
      <section id="who" className="page who" aria-label="Who builds this">
        {/* 208×208 for a 104px box, so it is already 2× on a Retina screen. It
            replaces a 944 KB PNG that was larger than every prerendered page on
            this site put together. The alt text is not decorative: this is the
            only image on a site whose job is to establish that a named person
            stands behind a money app. */}
        <img
          src={`${import.meta.env.BASE_URL}images/founder.webp`}
          alt="Simone Mattioli, the developer of Wealth Compass"
          width={104}
          height={104}
          loading="lazy"
          className="who-photo"
        />
        <div style={{ display: 'grid', gap: '0.9rem' }}>
          <p className="eyebrow">Who builds this</p>
          <h2 className="display display-m" style={{ maxWidth: '20ch' }}>
            Built by Simone Mattioli
          </h2>
          <p style={{ fontSize: 'clamp(1.125rem, 1.7vw, 1.4rem)', lineHeight: 1.45, maxWidth: '38ch' }}>
            I built Wealth Compass because I wanted one place to see everything. It is still the app I
            use for my own money.
          </p>
          <p className="mono" style={{ fontSize: 12, color: 'var(--ink-faint)', letterSpacing: '0.08em' }}>
            <a
              className="u-link"
              href="https://simo-hue.github.io/"
              target="_blank"
              rel="author noopener noreferrer"
            >
              SIMONE MATTIOLI
            </a>{' '}
            · VERONA, ITALY
          </p>
        </div>
      </section>

      {/* -------------------------------------------------------- source strip */}
      <section className="page" style={{ paddingBottom: 'clamp(4rem, 8vw, 7rem)' }}>
        <div className="source-strip">
          <div style={{ display: 'grid', gap: '0.8rem' }}>
            <p className="eyebrow">Where it started</p>
            <p style={{ color: 'var(--ink-muted)', maxWidth: '52ch' }}>
              Before the Apple apps there was a web app, and it is still here. The whole repository is
              public — read it, build it, or host the web version yourself. It is source-available under
              PolyForm Noncommercial, which is not the same thing as open source, and the difference is
              spelled out rather than glossed over.
            </p>
          </div>
          <Link to="/open-source/" className="u-link" style={{ fontSize: 15, whiteSpace: 'nowrap' }}>
            Read about the source →
          </Link>
        </div>
      </section>

      {/* ---------------------------------------------------------------- cta */}
      <section className="cta" aria-label="Download">
        <div className="page" style={{ display: 'grid', gap: '1.6rem', justifyItems: 'center', textAlign: 'center' }}>
          <h2 className="display display-l" style={{ maxWidth: '17ch' }}>
            Start with one number that is actually right
          </h2>
          <p className="lede" style={{ textAlign: 'center' }}>
            Free on the App Store. One purchase covers iPhone and Mac.
          </p>
          <StoreButton placement="site-cta" />
          <ul className="spec-strip" style={{ justifyContent: 'center', padding: 0, marginTop: '0.4rem' }}>
            <li>iOS 17+</li>
            <li>macOS 14+</li>
            <li>35 languages</li>
            <li>No account</li>
          </ul>
        </div>
      </section>
    </SimProvider>
  );
};
