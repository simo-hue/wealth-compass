import { useEffect, useState, type ComponentPropsWithoutRef } from 'react';
import { Outlet, useHref, useLinkClickHandler, useLocation, useResolvedPath } from 'react-router-dom';
import { REPO, appStore } from './links';
import './site.css';

/**
 * Chrome rules that need a media query, which inline styles cannot express.
 *
 * These belong in site.css next to the other breakpoints and should move there;
 * they are here only so that the layout and the stylesheet could be changed
 * independently. Everything is prefixed `wc-nav-` / `wc-site-` so nothing
 * collides when it does move.
 *
 * The breakpoint is 780px, not the 900px used elsewhere in site.css. Measured in
 * Chrome with the real faces: wordmark 164.7 + links 306.3 + store button 125.9
 * + two 28px gaps = 652.9px of bar, against a content box of 0.92 × viewport, so
 * the links start folding into the wordmark at 710px. 780 leaves a margin over
 * that without putting a menu button on tablets that have room for the real row.
 *
 * The links measured 281.3 and folded at 682 until the /open-source label stopped
 * saying "Open source" — see NAV. Renaming it cost 25px of row, and the cut still
 * clears the fold by 70. Re-measure here before lengthening a label again.
 */
const CHROME_CSS = `
.wc-site-shell {
  min-height: 100vh;
  /* iOS Safari counts the toolbar into 100vh, so the page is taller than the
     screen on first paint. dvh tracks the viewport that is actually visible;
     the vh above stays as the fallback for browsers that drop this line. */
  min-height: 100dvh;
}

.wc-site .wc-nav-bar { display: flex; align-items: center; gap: 28px; height: 62px; }
.wc-site .wc-nav { display: flex; align-items: center; gap: 22px; margin-left: auto; }
.wc-site .wc-nav-links { display: flex; gap: 22px; }
.wc-site .wc-nav-links a { font-size: 14px; color: var(--ink-muted); }
.wc-site .wc-nav-toggle { display: none; }

@media (max-width: 780px) {
  .wc-site .wc-nav-bar { gap: 16px; }
  .wc-site .wc-nav-toggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-muted);
    cursor: pointer;
  }
  /* The links leave the bar and become a sheet hanging under it. The bar keeps
     its 62px height either way, because .areas-device in site.css sticks at
     top: 78px and would slide under a taller header. */
  .wc-site .wc-nav-links {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    display: none;
    flex-direction: column;
    gap: 0;
    padding: 0.25rem var(--gutter) 0.75rem;
    background: var(--canvas-deep);
    border-bottom: 1px solid var(--rule-soft);
  }
  .wc-site .wc-nav[data-open='true'] .wc-nav-links { display: flex; }
  .wc-site .wc-nav-links a {
    display: flex;
    align-items: center;
    min-height: 46px;
    font-size: 1rem;
  }
  .wc-site .wc-nav-links a + a { border-top: 1px solid var(--rule-soft); }
  /* The growing underline is a pointer affordance and reads as a stray rule
     across a full-width row; the row borders already separate these. */
  .wc-site .wc-nav-links a::after { display: none; }
}

/* Below this the wordmark's text is what stops the bar fitting, and the compass
   alone is still a home link. Mark + menu + store button need 362.6px, which
   runs out at 403px; the cut is at 430 so that every common phone width lands on
   the same side of it and a font-metric difference during swap cannot push the
   store button off the edge. */
@media (max-width: 430px) {
  .wc-site .wc-wordmark-text { display: none; }
}
`;

/** The Apple logo, so the store button reads as a store button without an image. */
function AppleMark({ size = 19 }: { size?: number }) {
  return (
    <svg width={size} height={size * 1.22} viewBox="0 0 14 17" fill="currentColor" aria-hidden="true">
      <path d="M11.6 9c0-1.7 1.4-2.5 1.5-2.6-.8-1.2-2-1.3-2.5-1.4-1.1-.1-2.1.6-2.6.6-.5 0-1.4-.6-2.3-.6-1.2 0-2.3.7-2.9 1.8-1.2 2.1-.3 5.3.9 7 .6.8 1.3 1.8 2.2 1.7.9 0 1.2-.6 2.3-.6s1.4.6 2.3.5c.9 0 1.5-.8 2.1-1.7.7-1 .9-1.9.9-2-.1 0-1.9-.7-1.9-2.7zM9.9 3.4c.5-.6.8-1.4.7-2.2-.7 0-1.6.5-2.1 1.1-.4.5-.8 1.4-.7 2.2.8.1 1.6-.4 2.1-1.1z" />
    </svg>
  );
}

export function StoreButton({ placement, children }: { placement: Parameters<typeof appStore>[0]; children?: string }) {
  return (
    <a className="badge-store" href={appStore(placement)} target="_blank" rel="noopener noreferrer">
      <AppleMark />
      <span>
        <small>Free on the</small>
        {children ?? 'App Store'}
      </span>
    </a>
  );
}

/**
 * `<Link>`, except that a target resolving to the site root keeps its slash.
 *
 * GitHub Pages 301s /wealth-compass to /wealth-compass/, so the slashed form is
 * the URL it actually serves and the one the canonicals name. Paths below the
 * root carry their slash in the `to` string, but the root cannot: react-router's
 * useHref returns the bare basename for anything resolving to "/" — deliberately,
 * so that "the basename has full control over the presence of a trailing slash on
 * root links" — and the basename in App.tsx has none. That left the wordmark and
 * both "/#areas" links, eighteen of the site's internal links, pointing at a
 * redirect.
 *
 * Only the rendered href changes. useLinkClickHandler is the same hook <Link>
 * calls internally, so modifier-clicks, replace-on-same-URL and scroll handling
 * behave exactly as before. Adding the slash to BASENAME would fix this in one
 * character and is the better home for it, but App.tsx belongs to the routing
 * work; this is written so that both can be true — once the basename ends in a
 * slash, useHref already returns one and nothing here fires.
 */
function useSlashedHref(to: string): string {
  const href = useHref(to);
  const { pathname } = useResolvedPath(to);
  if (pathname !== '/') return href;

  // The href is pathname + search + hash concatenated; the slash belongs on the
  // pathname, so "/#areas" becomes "…/#areas" and not "…#areas/".
  const cut = href.search(/[?#]/);
  const path = cut === -1 ? href : href.slice(0, cut);
  return path.endsWith('/') ? href : `${path}/${cut === -1 ? '' : href.slice(cut)}`;
}

type SiteLinkProps = Omit<ComponentPropsWithoutRef<'a'>, 'href'> & { to: string };

function SiteLink({ to, children, ...rest }: SiteLinkProps) {
  const href = useSlashedHref(to);
  const onClick = useLinkClickHandler<HTMLAnchorElement>(to);
  return (
    <a {...rest} href={href} onClick={onClick}>
      {children}
    </a>
  );
}

/** The compass rose, drawn rather than imported — the product's own instrument. */
function Mark({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="10.2" fill="none" stroke="currentColor" strokeWidth="1.2" opacity="0.45" />
      <path d="M12 3.4 14.1 9.9 20.6 12 14.1 14.1 12 20.6 9.9 14.1 3.4 12 9.9 9.9Z" fill="currentColor" />
    </svg>
  );
}

/**
 * Anchor text is a relevance signal, and this row is the most repeated anchor
 * text on the site — every link here appears on all six pages. The label for
 * /open-source used to read "Open source", which is the one thing that page
 * exists to deny: its H1 is "Source available. Not open source." Twelve links a
 * page were telling a crawler the licence page was about the term it refutes.
 *
 * Every `to` carries a trailing slash because GitHub Pages 301s
 * /wealth-compass/faq to /wealth-compass/faq/, so the slashed form is the URL
 * that actually gets indexed and the one the canonicals point at. React Router
 * ignores trailing slashes when matching a route to the end, so the route table
 * in App.tsx is untouched. The home link stays "/" — it has no bare form.
 */
const NAV = [
  { label: 'The app', to: '/#areas' },
  { label: 'Source & licence', to: '/open-source/' },
  { label: 'FAQ', to: '/faq/' },
  { label: 'Support', to: '/support/' },
];

/** Two rules that fold into a cross, so the button says what it will do. */
function MenuMark({ open }: { open: boolean }) {
  // Each rule slides to the middle of the box and turns; together they cross.
  const bar = (y: number) => ({
    transform: open ? `translateY(${9 - y}px) rotate(${y < 9 ? 45 : -45}deg)` : 'none',
    transformOrigin: `9px ${y}px`,
    transition: 'transform 160ms ease-out',
  });
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
      <line x1="1.5" y1="5" x2="16.5" y2="5" style={bar(5)} />
      <line x1="1.5" y1="13" x2="16.5" y2="13" style={bar(13)} />
    </svg>
  );
}

function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const location = useLocation();

  // The nav's own Download button appears only once the hero's has scrolled
  // past, so there are never two competing primary actions on screen.
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 560);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  // Any navigation closes the sheet — keyed on `key` rather than `pathname` so
  // that the in-page /#areas link closes it too.
  useEffect(() => {
    setOpen(false);
  }, [location.key]);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const showStore = scrolled || location.pathname !== '/';

  return (
    <header
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 50,
        background: 'color-mix(in srgb, var(--canvas) 86%, transparent)',
        backdropFilter: 'blur(14px)',
        WebkitBackdropFilter: 'blur(14px)',
        borderBottom: '1px solid var(--rule-soft)',
      }}
    >
      <div className="page wc-nav-bar">
        <SiteLink to="/" style={{ display: 'flex', alignItems: 'center', gap: 9, flexShrink: 0 }}>
          <Mark />
          <span
            className="wc-wordmark-text"
            style={{ fontFamily: 'var(--display)', fontStretch: '112%', fontWeight: 700, fontSize: 15, letterSpacing: '-0.01em' }}
          >
            Wealth Compass
          </span>
        </SiteLink>

        {/* One landmark at both sizes: the same four links are the row on a
            desktop and the sheet on a phone, and CSS decides which — so the
            prerendered HTML and the first client render agree. */}
        <nav className="wc-nav" aria-label="Main" data-open={open}>
          {/* Ahead of the links in the DOM so that on a phone the button is
              reached before the sheet it opens. Both are laid out by CSS, so the
              order costs nothing visually. */}
          <button
            type="button"
            className="wc-nav-toggle"
            aria-label="Menu"
            aria-expanded={open}
            aria-controls="wc-nav-links"
            onClick={() => setOpen((value) => !value)}
          >
            <MenuMark open={open} />
          </button>
          <div className="wc-nav-links" id="wc-nav-links">
            {NAV.map((item) => (
              <SiteLink key={item.label} to={item.to} className="u-link">
                {item.label}
              </SiteLink>
            ))}
          </div>
        </nav>

        <div
          style={{
            flexShrink: 0,
            opacity: showStore ? 1 : 0,
            transform: showStore ? 'none' : 'translateY(-4px)',
            transition: 'opacity 160ms ease-out, transform 160ms ease-out',
            pointerEvents: showStore ? 'auto' : 'none',
          }}
        >
          <a
            className="badge-store"
            href={appStore('site-nav')}
            target="_blank"
            rel="noopener noreferrer"
            style={{ padding: '0.5rem 1rem', fontSize: 14, borderRadius: 8 }}
            tabIndex={showStore ? 0 : -1}
          >
            <AppleMark size={15} />
            Download
          </a>
        </div>
      </div>
    </header>
  );
}

function Footer() {
  return (
    <footer style={{ borderTop: '1px solid var(--rule-soft)', marginTop: 'auto', background: 'var(--canvas-deep)' }}>
      <div className="page" style={{ paddingBlock: '3.5rem 2.5rem', display: 'grid', gap: '2.5rem' }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '2.5rem', justifyContent: 'space-between' }}>
          <div style={{ display: 'grid', gap: '0.9rem', maxWidth: '34ch' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
              <Mark size={20} />
              <span style={{ fontFamily: 'var(--display)', fontStretch: '112%', fontWeight: 700, fontSize: 15 }}>
                Wealth Compass
              </span>
            </span>
            <p style={{ fontSize: 14, color: 'var(--ink-muted)', lineHeight: 1.55 }}>
              A local-first net-worth tracker for iPhone and Mac. One universal purchase, free, no account.
            </p>
          </div>

          {/* Same two rules as NAV above: the anchor text describes the page it
              lands on, and every path ends in the slash GitHub Pages redirects
              to. */}
          <FooterColumn
            title="Product"
            links={[
              { label: 'The app', to: '/#areas' },
              { label: 'FAQ', to: '/faq/' },
              { label: 'Support', to: '/support/' },
            ]}
          />
          <FooterColumn
            title="Source"
            links={[
              { label: 'Source & licence', to: '/open-source/' },
              { label: 'Repository', href: REPO },
            ]}
          />
          <FooterColumn
            title="Legal"
            links={[
              { label: 'Privacy policy', to: '/privacy/' },
              { label: 'Terms of service', to: '/terms/' },
            ]}
          />
        </div>

        <hr className="rule" />

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '1rem 2rem', justifyContent: 'space-between', alignItems: 'center' }}>
          {/* Checkable in devtools, which is the point of saying it here. */}
          <p className="mono" style={{ fontSize: 11, color: 'var(--ink-faint)', letterSpacing: '0.04em' }}>
            This page sets no cookies and loads nothing from a third party.
          </p>
          {/* No year. new Date().getFullYear() bakes the build's year into the
              prerendered HTML, so it goes stale the moment the site is not
              redeployed for twelve months and mismatches at hydration on the 1st
              of January. A notice needs no year to be a notice, and a wrong one
              is worse than none. */}
          <p className="mono" style={{ fontSize: 11, color: 'var(--ink-faint)' }}>
            {/* The one link that ties the name in this notice to a person. The
                site otherwise names an author it never identifies, which is the
                weakest possible answer to "who wrote this" on a page about
                someone's money. rel="author" is the whole intervention: the
                credentials themselves stay off this site, where a publication
                list under a net-worth tracker would read as padding. */}
            ©{' '}
            <a
              className="u-link"
              href="https://simo-hue.github.io/"
              rel="author noopener noreferrer"
              target="_blank"
            >
              Simone Mattioli
            </a>{' '}
            · Verona
          </p>
        </div>
      </div>
    </footer>
  );
}

function FooterColumn({ title, links }: { title: string; links: { label: string; to?: string; href?: string }[] }) {
  return (
    <div style={{ display: 'grid', gap: '0.7rem', alignContent: 'start' }}>
      <p className="eyebrow">{title}</p>
      {links.map((link) =>
        link.href ? (
          <a key={link.label} href={link.href} target="_blank" rel="noopener noreferrer" className="u-link" style={{ fontSize: 14, color: 'var(--ink-muted)' }}>
            {link.label}
          </a>
        ) : (
          <SiteLink key={link.label} to={link.to!} className="u-link" style={{ fontSize: 14, color: 'var(--ink-muted)' }}>
            {link.label}
          </SiteLink>
        ),
      )}
    </div>
  );
}

export function SiteLayout() {
  return (
    <div className="wc-site wc-site-shell" style={{ display: 'flex', flexDirection: 'column' }}>
      <style>{CHROME_CSS}</style>
      <Nav />
      <main style={{ flex: 1 }}>
        <Outlet />
      </main>
      <Footer />
    </div>
  );
}
