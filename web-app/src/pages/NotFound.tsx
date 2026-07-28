import { useEffect } from "react";
import { useLocation } from "react-router-dom";

/**
 * The 404, rendered outside SiteLayout on purpose: a not-found page should not
 * depend on the chrome of the site it is reporting a hole in. That left it with
 * no nav, no footer, and no styled way back, so it carries `wc-site` itself.
 * site.css already sits in the entry bundle — App.tsx imports SiteLayout
 * eagerly — so the palette and the type utilities are present without adding a
 * stylesheet.
 *
 * LINKS. Every href below is absolute and starts with the /wealth-compass/
 * prefix. `href="/"`, which this page used to carry, resolves on GitHub Pages to
 * https://simo-hue.github.io/ — the author's personal blog, a different site
 * entirely. They are plain anchors rather than <Link>, because GitHub Pages
 * serves this route from dist/404.html, which is the empty SPA shell: a full
 * navigation lands the reader on the prerendered document instead of a
 * client-rendered copy of it.
 *
 * TRAILING SLASHES. GitHub Pages 301s /wealth-compass/faq to
 * /wealth-compass/faq/, so the sub-pages are written in the slashed form the
 * server settles on and no link here spends a redirect.
 */

/** Must agree with BASENAME in src/App.tsx. Importing it from there would be a cycle — App.tsx imports this file. */
const SITE = "/wealth-compass/";

/* min-height needs two declarations and a style object cannot hold both keys.
   iOS Safari counts its toolbar into 100vh; dvh tracks what is actually visible. */
const SHELL_CSS = `.wc-404 { min-height: 100vh; min-height: 100dvh; }`;

const ELSEWHERE: { href: string; label: string; note: string }[] = [
  {
    href: `${SITE}faq/`,
    label: "FAQ",
    note: "What the app does, and what it deliberately does not.",
  },
  {
    href: `${SITE}support/`,
    label: "Support",
    note: "Ten things that go wrong, each with the place in the app to fix it.",
  },
  {
    href: `${SITE}privacy/`,
    label: "Privacy policy",
    note: "What is stored, what leaves the device, and what you can delete.",
  },
];

const NotFound = () => {
  const location = useLocation();

  useEffect(() => {
    console.error("404 Error: User attempted to access non-existent route:", location.pathname);
    // 404.html is the untouched template, so without this the tab still carries
    // the home page's title. Nothing prerenders this route, so nothing to fight.
    document.title = "Page not found · Wealth Compass";
  }, [location.pathname]);

  return (
    <div
      className="wc-site wc-404"
      style={{ display: "flex", flexDirection: "column", justifyContent: "center" }}
    >
      <style>{SHELL_CSS}</style>

      <main className="page" style={{ paddingBlock: "clamp(3rem, 10vw, 6rem)" }}>
        <p className="eyebrow">
          <span className="num">404</span> · Page not found
        </p>

        <h1 className="display display-l" style={{ maxWidth: "16ch", marginBlock: "0.9rem 1.2rem" }}>
          That page is not here.
        </h1>

        <p className="lede">
          The address does not match anything on this site. It may have been renamed since the link
          was written, or the link may have carried a typo.
        </p>

        <p style={{ marginTop: "1.8rem" }}>
          <a
            href={SITE}
            className="u-link"
            style={{ fontSize: 15, textDecoration: "underline", textUnderlineOffset: "0.22em" }}
          >
            Wealth Compass home →
          </a>
        </p>

        <ul
          style={{
            listStyle: "none",
            display: "grid",
            gap: "1.1rem",
            margin: "clamp(2rem, 5vw, 3rem) 0 0",
            padding: "clamp(1.25rem, 3vw, 1.75rem) 0 0",
            borderTop: "1px solid var(--rule-soft)",
            maxWidth: "var(--measure)",
          }}
        >
          {ELSEWHERE.map((item) => (
            <li key={item.href} style={{ display: "grid", gap: "0.3rem" }}>
              <a href={item.href} className="u-link" style={{ fontSize: 15 }}>
                {item.label} →
              </a>
              <span style={{ fontSize: 14, color: "var(--ink-faint)" }}>{item.note}</span>
            </li>
          ))}
        </ul>
      </main>
    </div>
  );
};

export default NotFound;
