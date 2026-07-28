import type { CSSProperties, ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { LICENSE, REPO, SUPPORT_EMAIL } from '../site/links';

/**
 * The legal substance here is the same four clauses the page has always carried —
 * acceptance, licence, disclaimer, limitations. What changed is factual: the
 * source is licensed PolyForm Noncommercial 1.0.0 (source-available, not open
 * source, see LICENSE at the repository root), the disclaimer names the party
 * making it, and the "last updated" line is a fixed date instead of
 * `new Date()` — which re-dated the document on every render and disagreed
 * between the prerendered HTML and the hydrated page.
 */

const REVISION = 'Revised 28 July 2026';

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

function Key({ children }: { children: ReactNode }) {
  return <strong style={{ color: 'var(--ink)', fontWeight: 600 }}>{children}</strong>;
}

function Out({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" style={linkStyle}>
      {children}
    </a>
  );
}

const SECTIONS: { id: string; title: string; body: ReactNode }[] = [
  {
    id: 'acceptance',
    title: 'Acceptance of terms',
    body: (
      <P>
        By accessing this website, or by downloading or using Wealth Compass for iPhone or Mac, you agree to
        be bound by these terms. If you do not agree to them, do not use the site or the apps.
      </P>
    ),
  },
  {
    id: 'licence',
    title: 'Use licence',
    body: (
      <>
        <P>
          Permission is granted to temporarily download one copy of the materials on this website for
          personal, non-commercial transitory viewing only.
        </P>
        <P>
          The Wealth Compass source code is published under the{' '}
          <Out href={LICENSE}>PolyForm Noncommercial License 1.0.0</Out>. It is{' '}
          <Key>source-available, not open source</Key>: the licence permits use, modification and
          redistribution for noncommercial purposes, and grants no commercial licence. Its full text governs
          what you may do with the code, and it sits at the root of the{' '}
          <Out href={REPO}>project repository</Out>.
        </P>
        <P>
          The iPhone and Mac apps are downloaded from the App Store free of charge. There are no in-app
          purchases and no subscription.
        </P>
      </>
    ),
  },
  {
    id: 'disclaimer',
    title: 'Disclaimer',
    body: (
      <>
        <P>
          The materials on this website and the Wealth Compass software are provided on an{' '}
          <Key>'as is'</Key> basis. Simone Mattioli makes no warranties, expressed or implied, and hereby
          disclaims and negates all other warranties including, without limitation, implied warranties or
          conditions of merchantability, fitness for a particular purpose, or non-infringement of
          intellectual property or other violation of rights.
        </P>
        <P>
          Wealth Compass does not provide financial advice. Every figure it shows is arithmetic over data
          you entered, combined with prices and exchange rates fetched from third-party providers, which can
          be delayed, incomplete or wrong. Projections are illustrations, not forecasts, and decisions about
          your money remain yours.
        </P>
      </>
    ),
  },
  {
    id: 'limitations',
    title: 'Limitations',
    body: (
      <P>
        In no event shall Simone Mattioli or his suppliers be liable for any damages (including, without
        limitation, damages for loss of data or profit, or due to business interruption) arising out of the
        use or inability to use Wealth Compass or the materials on this website.
      </P>
    ),
  },
  {
    id: 'contact',
    title: 'Contact',
    body: (
      <P>
        Wealth Compass is written and published by Simone Mattioli in Verona, Italy. Questions about these
        terms go to <Out href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</Out>. How the apps handle data is
        a separate document — see the <Link to="/privacy/" style={linkStyle}>privacy policy</Link>.
      </P>
    ),
  },
];

const mark = (i: number) => String(i + 1).padStart(2, '0');

export const TermsOfService = () => {
  return (
    <div className="page" style={{ paddingBlock: 'clamp(2.5rem, 6vw, 4.5rem) clamp(4rem, 9vw, 7rem)' }}>
      <header style={{ display: 'grid', gap: '1.1rem', maxWidth: measure }}>
        <p className="eyebrow">Legal</p>
        <h1 className="display display-l">Terms of service</h1>
        <p className="mono" style={{ fontSize: 12, letterSpacing: '0.08em', color: 'var(--ink-faint)' }}>
          {REVISION}
        </p>
        <p className="lede" style={{ marginTop: '0.4rem' }}>
          These terms cover this website, the Wealth Compass apps for iPhone and Mac, and the source code in
          the project repository.
        </p>
      </header>

      <div style={{ display: 'grid', marginTop: 'clamp(2.5rem, 5vw, 4rem)' }}>
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
        <Link to="/privacy/" className="u-link" style={{ fontSize: 15 }}>
          Privacy policy →
        </Link>
        <Link to="/support/" className="u-link" style={{ fontSize: 15, color: 'var(--ink-muted)' }}>
          Support
        </Link>
      </div>
    </div>
  );
};
