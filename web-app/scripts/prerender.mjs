/**
 * Turns the built SPA into a set of real HTML files, one per marketing route.
 *
 * GitHub Pages has no rewrite rules. A cold request for /wealth-compass/privacy/ — the
 * URL registered with Apple as the app's privacy policy — asks for a file at that path,
 * and until this script existed there was none, so GitHub answered with its own 404 page
 * and the SPA never booted. Same for /faq/, the registered support URL.
 *
 * Run after `vite build` (client) and `vite build --ssr` (server). Reads the built
 * index.html as a template, renders each route through src/entry-server.tsx, and writes
 * dist/<route>/index.html — the file GitHub Pages serves for a directory URL.
 *
 * It also writes, from the same template:
 *   - dist/404.html         the SPA fallback, with the home page's identity stripped out
 *   - dist/<old>/index.html meta-refresh stubs for URLs that moved but still get traffic
 *   - dist/sitemap.xml      generated from ROUTES, so a route cannot ship unlisted
 *
 * TRAILING SLASHES. GitHub Pages 301s /wealth-compass/faq to /wealth-compass/faq/. Every
 * canonical, every sitemap <loc> and every internal link therefore uses the slashed form,
 * so the URL Google indexes is the URL that declares itself canonical. The home page is
 * /wealth-compass/ and is the one exception, because it already ends in a slash.
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO_ROOT = path.resolve(ROOT, '..');
const DIST = path.join(ROOT, 'dist');
const SSR_ENTRY = path.join(ROOT, 'node_modules', '.wc-ssr', 'entry-server.js');

const SITE = 'https://simo-hue.github.io/wealth-compass';

/**
 * The author's Person node lives on his personal site, at the root of this same host,
 * and this ID is how the two sites describe ONE human rather than two. Minting a second
 * Person under /wealth-compass/ would split the entity and throw away the only authority
 * signal a solo-developer finance app has.
 */
const PERSON_ID = 'https://simo-hue.github.io/#person';

/** Campaign tokens belong on the links a human clicks, not in structured data. */
const APP_STORE = 'https://apps.apple.com/us/app/wealth-compass-tracker/id6777399748';
const REPO = 'https://github.com/simo-hue/wealth-compass';
const LICENSE = 'https://polyformproject.org/licenses/noncommercial/1.0.0';

/** Read-only reference: the Apple app is the product this site describes. */
const APPLE = path.join(REPO_ROOT, 'apple', 'WealthCompass');
const PBXPROJ = path.join(APPLE, 'WealthCompass.xcodeproj', 'project.pbxproj');
const XCSTRINGS = path.join(APPLE, 'Sources', 'Shared', 'Resources', 'Localizable.xcstrings');

/**
 * The routes that exist as static files, with the head each one gets.
 *
 * The head is set here rather than in the components because React does not own the
 * document head in this app — there is no Helmet — and because a crawler that never
 * runs the bundle sees only what is in the file. `check` is a string that must appear
 * in the rendered body; it is how the build proves it emitted a page rather than an
 * empty shell. `crumb` is the page's label in its BreadcrumbList; `revisionFrom` names
 * a page whose copy carries a real revision date, which becomes the sitemap <lastmod>.
 */
const ROUTES = [
  {
    path: '/',
    title: 'Wealth Compass — everything you own, owe, earn, and spend',
    description:
      'A local-first net-worth tracker for iPhone and Mac. Cash, investments, crypto and debts in one place, on your device. Free, no account, no tracking.',
    check: 'Everything you own, owe, earn, and spend.',
  },
  {
    path: '/faq',
    title: 'FAQ — Wealth Compass',
    description:
      'What Wealth Compass does, where your records live, what it costs, and what the licence permits. Answers for the iPhone and Mac apps.',
    check: 'Questions, answered',
    crumb: 'FAQ',
  },
  {
    path: '/support',
    title: 'Support — Wealth Compass',
    description:
      'Something not working in Wealth Compass for iPhone or Mac? Ten common problems with the exact fix, and two ways to reach a person.',
    check: 'Something is not working. Start here.',
    crumb: 'Support',
  },
  {
    path: '/open-source',
    title: 'Source available — Wealth Compass',
    description:
      'Every line of Wealth Compass is public, under PolyForm Noncommercial 1.0.0. Read it, build it, change it — just not commercially.',
    check: 'Source available. Not open source.',
    crumb: 'Source available',
  },
  {
    path: '/privacy',
    title: 'Privacy policy — Wealth Compass',
    description:
      'Wealth Compass stores your financial records on your own device. No account, no analytics, no third-party trackers. The full policy.',
    check: 'Privacy policy',
    crumb: 'Privacy policy',
    revisionFrom: 'src/pages/PrivacyPolicy.tsx',
  },
  {
    path: '/terms',
    title: 'Terms of service — Wealth Compass',
    description: 'The terms covering use of the Wealth Compass apps for iPhone and Mac, and of this site.',
    check: 'Terms of service',
    crumb: 'Terms of service',
    revisionFrom: 'src/pages/TermsOfService.tsx',
  },
];

/**
 * URLs that no longer exist as pages but still receive traffic — they were linked from
 * elsewhere on the web and from earlier App Store metadata. App.tsx redirects them once
 * the SPA is running, but a cold request never reaches the SPA: dist had no such
 * directory, so GitHub Pages answered 404.html with a 404 STATUS and a crawler dropped
 * the URL along with whatever signal pointed at it.
 *
 * A zero-second meta refresh is the only redirect a static host can express, and Google
 * treats it as a redirect and passes signals through it. These are deliberately NOT in
 * the sitemap — a sitemap lists destinations, not waypoints.
 */
const REDIRECTS = [
  { from: '/features', to: `${SITE}/#areas`, canonical: `${SITE}/`, label: 'What Wealth Compass does' },
  { from: '/founder', to: `${SITE}/#who`, canonical: `${SITE}/`, label: 'Who builds Wealth Compass' },
  { from: '/tutorial', to: `${SITE}/open-source/`, canonical: `${SITE}/open-source/`, label: 'Source available' },
];

/* ------------------------------------------------------------------ facts from source */

/**
 * Every locale the app actually ships, read from the string catalogue rather than typed
 * here, so the number in the structured data cannot drift from the number in the app.
 * 35 machine-comparable BCP-47 codes is the hard differentiator in this category, and a
 * hand-maintained list would be wrong within one release.
 */
async function appLocales() {
  const catalogue = JSON.parse(await readFile(XCSTRINGS, 'utf8'));
  const entries = Object.values(catalogue.strings ?? {});
  const seen = new Map();

  for (const entry of entries) {
    for (const locale of Object.keys(entry.localizations ?? {})) {
      seen.set(locale, (seen.get(locale) ?? 0) + 1);
    }
  }

  // The source language is shipped by definition — most strings carry no translation
  // entry for it because the key itself is the English copy. Everything else has to
  // clear a floor, so one stray half-imported locale cannot be claimed as supported.
  const floor = entries.length * 0.25;
  const locales = new Set([catalogue.sourceLanguage]);
  for (const [locale, count] of seen) if (count >= floor) locales.add(locale);

  return [...locales].sort();
}

/** Every value a build setting takes across the project's configurations. */
function settingValues(pbxproj, key) {
  return [...pbxproj.matchAll(new RegExp(`${key} = ([^;]+);`, 'g'))].map((m) => m[1].trim().replace(/^"|"$/g, ''));
}

const compareVersions = (a, b) => {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    if ((pa[i] ?? 0) !== (pb[i] ?? 0)) return (pa[i] ?? 0) - (pb[i] ?? 0);
  }
  return 0;
};

/**
 * What the App Store listing says the app runs on, taken from the deployment targets it
 * is actually built against. The lowest target across configurations is the honest floor
 * for an "or later" claim.
 */
async function appPlatform() {
  const pbxproj = await readFile(PBXPROJ, 'utf8');

  const lowest = (key) => {
    const values = settingValues(pbxproj, key);
    if (!values.length) throw new Error(`${key} not found in ${path.relative(REPO_ROOT, PBXPROJ)}`);
    return values.sort(compareVersions)[0];
  };

  // Ambiguity is not a fact. If the project ever carries two marketing versions at once
  // there is no single right answer, so the claim is dropped rather than guessed.
  const versions = [...new Set(settingValues(pbxproj, 'MARKETING_VERSION'))];

  return {
    operatingSystem: `iOS ${lowest('IPHONEOS_DEPLOYMENT_TARGET')} or later; macOS ${lowest('MACOSX_DEPLOYMENT_TARGET')} or later`,
    version: versions.length === 1 ? versions[0] : null,
  };
}

const MONTHS = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

/**
 * The revision date a policy page states in its own copy, as an ISO date for <lastmod>.
 * Parsed rather than duplicated, because a lastmod that disagrees with the visible date
 * is worse than no lastmod at all. Returns null if the wording changes — the sitemap
 * simply omits the element, which is valid, instead of the build inventing a date.
 */
async function revisionDate(relativePath) {
  const source = await readFile(path.join(ROOT, relativePath), 'utf8');
  const match = source.match(/Revised\s+(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/);
  if (!match) {
    console.warn(`  ! no "Revised <d> <Month> <YYYY>" in ${relativePath} — sitemap entry gets no lastmod`);
    return null;
  }

  const [, day, month, year] = match;
  const index = MONTHS.indexOf(month.toLowerCase());
  if (index < 0) {
    console.warn(`  ! unrecognised month ${JSON.stringify(month)} in ${relativePath} — no lastmod`);
    return null;
  }

  return `${year}-${String(index + 1).padStart(2, '0')}-${day.padStart(2, '0')}`;
}

/* ------------------------------------------------------------------- structured data */

const canonicalFor = (routePath) => (routePath === '/' ? `${SITE}/` : `${SITE}${routePath}/`);

/**
 * One entity graph, shared by every prerendered page.
 *
 * There is no Organization node on purpose: the privacy policy states in as many words
 * that there is no company behind this, so declaring one would have the structured data
 * contradict the page it sits on. The author is both author and publisher.
 *
 * There is no aggregateRating or review either. No review data exists to describe, and
 * inventing engagement signals on a personal-finance product is exactly the kind of
 * claim that earns a manual action.
 */
function entityGraph(route, facts) {
  const person = {
    '@type': 'Person',
    '@id': PERSON_ID,
    name: 'Simone Mattioli',
    givenName: 'Simone',
    familyName: 'Mattioli',
    url: 'https://simo-hue.github.io/',
    image: `${SITE}/images/founder.png`,
    address: {
      '@type': 'PostalAddress',
      addressLocality: 'Verona',
      addressRegion: 'Veneto',
      addressCountry: 'IT',
    },
    identifier: {
      '@type': 'PropertyValue',
      propertyID: 'ORCID',
      value: 'https://orcid.org/0009-0006-5047-8004',
    },
    sameAs: [
      'https://github.com/simo-hue',
      'https://orcid.org/0009-0006-5047-8004',
      'https://scholar.google.com/citations?user=uLGrDbIAAAAJ',
      'https://www.sciprofiles.com/profile/Mattioli-simone',
      'https://www.linkedin.com/in/simonemattioli2003/',
      'https://apps.apple.com/us/developer/simone-mattioli/id1896746638',
    ],
  };

  // SoftwareApplication, not MobileApplication: the same app ships for macOS, and the
  // mobile subtype would describe only half the product.
  const app = {
    '@type': 'SoftwareApplication',
    '@id': `${SITE}/#app`,
    name: 'Wealth Compass Tracker',
    alternateName: 'Wealth Compass',
    description: ROUTES[0].description,
    applicationCategory: 'FinanceApplication',
    operatingSystem: facts.platform.operatingSystem,
    ...(facts.platform.version ? { softwareVersion: facts.platform.version } : {}),
    author: { '@id': PERSON_ID },
    publisher: { '@id': PERSON_ID },
    isAccessibleForFree: true,
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'EUR',
      availability: 'https://schema.org/InStock',
      url: APP_STORE,
    },
    downloadUrl: APP_STORE,
    installUrl: APP_STORE,
    license: LICENSE,
    codeRepository: REPO,
    privacyPolicy: `${SITE}/privacy/`,
    image: `${SITE}/og.png`,
    inLanguage: facts.locales,
    sameAs: [APP_STORE, REPO],
  };

  // No SearchAction: there is no site search to point one at, and declaring an endpoint
  // that does not exist is a straightforward misrepresentation.
  const website = {
    '@type': 'WebSite',
    '@id': `${SITE}/#website`,
    url: `${SITE}/`,
    name: 'Wealth Compass',
    publisher: { '@id': PERSON_ID },
    inLanguage: 'en',
  };

  const graph = [person, app, website];

  // Worth the bytes here specifically: a project-page URL renders as
  // simo-hue.github.io › wealth-compass › faq in a result, which reads like a path on
  // somebody else's site. A breadcrumb replaces that with the site's own labels.
  if (route.crumb) {
    graph.push({
      '@type': 'BreadcrumbList',
      '@id': `${canonicalFor(route.path)}#breadcrumb`,
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'Wealth Compass', item: `${SITE}/` },
        { '@type': 'ListItem', position: 2, name: route.crumb, item: canonicalFor(route.path) },
      ],
    });
  }

  if (route.path === '/open-source') {
    graph.push({
      '@type': 'SoftwareSourceCode',
      '@id': `${SITE}/#source`,
      name: 'Wealth Compass',
      codeRepository: REPO,
      license: LICENSE,
      programmingLanguage: ['Swift', 'TypeScript'],
      author: { '@id': PERSON_ID },
    });
  }

  return { '@context': 'https://schema.org', '@graph': graph };
}

/**
 * escapeAttr is for attribute values and would mangle this. A script body is CDATA-ish:
 * the one sequence that can break out of it is a literal `</script`, so `<` is escaped
 * to its JSON unicode form, which parses back to the same string.
 */
const jsonLd = (data) => JSON.stringify(data).replace(/</g, '\\u003c');

/* -------------------------------------------------------------------------- templating */

/** Replaces the value of one `<meta {attr}="{name}" content="...">`, if it is there. */
function setMeta(html, attr, name, value) {
  const tag = new RegExp(`(<meta\\s+${attr}="${name}"[^>]*?content=")[\\s\\S]*?(")`, 'i');
  return tag.test(html) ? html.replace(tag, (_, open, close) => `${open}${escapeAttr(value)}${close}`) : html;
}

/** Only what can terminate an attribute or open a tag; the copy is otherwise literal. */
const escapeAttr = (value) => value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

const setTitle = (html, title) =>
  html.replace(/<title>[\s\S]*?<\/title>/i, () => `<title>${title.replace(/</g, '&lt;')}</title>`);

const beforeHeadEnd = (html, markup) => html.replace('</head>', () => `${markup}\n</head>`);

function withHead(template, route, facts) {
  const canonical = canonicalFor(route.path);
  let html = template;

  html = setTitle(html, route.title);
  html = html.replace(/(<link\s+rel="canonical"[^>]*?href=")[\s\S]*?(")/i, (_, open, close) => `${open}${canonical}${close}`);
  html = setMeta(html, 'name', 'description', route.description);
  html = setMeta(html, 'property', 'og:url', canonical);
  html = setMeta(html, 'property', 'og:title', route.title);
  html = setMeta(html, 'property', 'og:description', route.description);

  // The FAQPage block is rendered by FAQ.tsx into the body. This graph describes the
  // product, the author and the site, and deliberately declares no FAQPage of its own.
  html = beforeHeadEnd(html, `  <script type="application/ld+json">${jsonLd(entityGraph(route, facts))}</script>`);

  return html;
}

/**
 * The fallback served for every URL that is not a file. Inheriting the home page's title,
 * canonical and OG block made every broken URL look like the home page in crawl reports
 * and in social unfurls, so all three come off.
 *
 * The container stays empty, and must: main.tsx branches on whether it has children —
 * empty takes createRoot, prerendered takes hydrateRoot. Markup here would send every
 * unknown route down the hydrate path against the wrong tree.
 */
function notFoundHead(template) {
  let html = setTitle(template, 'Page not found — Wealth Compass');
  html = setMeta(html, 'name', 'description', 'This Wealth Compass page does not exist.');
  html = html.replace(/[ \t]*<link\s+rel="canonical"[^>]*>\n?/i, '');
  html = html.replace(/[ \t]*<meta\s+property="og:[^>]*>\n?/gi, '');
  html = html.replace(/[ \t]*<meta\s+name="twitter:[^>]*>\n?/gi, '');
  return html;
}

const redirectStub = ({ to, canonical, label }) => `<!doctype html>
<html lang="en">

<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Moved — Wealth Compass</title>

  <!-- A static host cannot answer 301, and this URL still receives traffic from older
       App Store metadata and from links elsewhere on the web. A zero-second refresh is
       read as a redirect and carries the signal through to the destination. -->
  <meta http-equiv="refresh" content="0; url=${escapeAttr(to)}" />
  <link rel="canonical" href="${escapeAttr(canonical)}" />
  <meta name="theme-color" content="#16202b" />
</head>

<body style="background:#16202b;color:#e8eef5;font:16px/1.5 system-ui,sans-serif;margin:0;padding:3rem 1.5rem">
  <p>This page has moved to <a href="${escapeAttr(to)}" style="color:#7fd4a8">${escapeAttr(label)}</a>.</p>
</body>

</html>
`;

/**
 * Generated from ROUTES rather than hand-kept in public/, so a route cannot be added
 * without appearing here. No <priority>: Google has said for years that it ignores it.
 */
function sitemap(entries) {
  const urls = entries
    .map(({ loc, lastmod }) =>
      ['  <url>', `    <loc>${escapeAttr(loc)}</loc>`, ...(lastmod ? [`    <lastmod>${lastmod}</lastmod>`] : []), '  </url>'].join('\n'),
    )
    .join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

/* -------------------------------------------------------------------------------- run */

const ROOT_DIV = /<div id="root">\s*<\/div>/;

const template = await readFile(path.join(DIST, 'index.html'), 'utf8');
if (!ROOT_DIV.test(template)) {
  throw new Error('dist/index.html has no empty <div id="root"></div> to render into');
}

const facts = { locales: await appLocales(), platform: await appPlatform() };
console.log(`  ${facts.locales.length} app locales · ${facts.platform.operatingSystem}\n`);

const { render } = await import(pathToFileURL(SSR_ENTRY).href);

await writeFile(path.join(DIST, '404.html'), notFoundHead(template));
console.log('  dist/404.html                    SPA fallback (empty shell)');

for (const route of ROUTES) {
  const body = render(route.path);

  if (!body.includes(route.check)) {
    throw new Error(`${route.path} rendered without its own content — expected to find ${JSON.stringify(route.check)}`);
  }

  const html = withHead(template, route, facts).replace(ROOT_DIV, () => `<div id="root">${body}</div>`);
  const file = route.path === '/' ? path.join(DIST, 'index.html') : path.join(DIST, route.path.slice(1), 'index.html');

  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, html);

  const name = path.relative(ROOT, file);
  console.log(`  ${name.padEnd(33)}${(body.length / 1024).toFixed(1)} kB rendered`);
}

for (const redirect of REDIRECTS) {
  const file = path.join(DIST, redirect.from.slice(1), 'index.html');
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, redirectStub(redirect));
  console.log(`  ${path.relative(ROOT, file).padEnd(33)}→ ${redirect.to}`);
}

const entries = [];
for (const route of ROUTES) {
  entries.push({
    loc: canonicalFor(route.path),
    lastmod: route.revisionFrom ? await revisionDate(route.revisionFrom) : null,
  });
}
await writeFile(path.join(DIST, 'sitemap.xml'), sitemap(entries));
console.log(`  dist/sitemap.xml                 ${entries.length} URLs`);

console.log(`\nPrerendered ${ROUTES.length} routes, ${REDIRECTS.length} redirect stubs. Every marketing URL is now a file.`);
