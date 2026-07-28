# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

- [ ] How to sync the cards' transactions automatically 
---

## PDF Report Export (added 2026-07-27)

The whole feature was written and verified without Xcode (this machine has Command Line Tools
only). What I could verify, and what I could not:

**Verified here**
- [x] `Sources/Shared` + `Sources/macOS` typecheck cleanly (`swiftc -typecheck`, 0 errors, 0 warnings).
- [x] The renderer compiles, runs, and produces correct PDFs — six sample variants inspected page by page.
- [x] `project.pbxproj` passes `plutil -lint`; every new build file resolves to a real file reference.
- [x] `Localizable.xcstrings` round-trips byte-exact; diff is additions only.
- [x] All 29 assertions in `Tests/ReportExportOptionsTests.swift` re-run against the real code and pass.

**Needs you, at a Mac with Xcode**
- [ ] **Build the iOS target.** `Sources/iOS/Views/SettingsView.swift` is the one file I could not
      typecheck — there is no iOS SDK here, so UIKit is unavailable. Its changes mirror the macOS
      ones exactly (export coordinator, two sheets, `performExport()`, plus a small
      `ExportShareSheet` `UIViewControllerRepresentable`), but it has never been compiled.
- [ ] **Build the macOS target** to confirm the asset catalogue compiles with the new
      `BrandMark.imageset` and that `NSImage(named: "BrandMark")` resolves at runtime.
- [ ] **Run the test suite** on a simulator:
      `xcodebuild test -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMobile -destination 'platform=iOS Simulator,name=iPhone 16'`
- [ ] **Eyeball the export sheet** on both platforms. The sheet itself was never rendered — only
      typechecked. Check the macOS fixed frame (460×560) is not clipping, and that the iOS sheet
      scrolls properly with "Choose Sections" expanded.
- [ ] **Check the share sheet / save panel** actually receive the file, and that the PDF opens in
      Preview / Files with the sidebar outline present.
- [ ] **Watch for sheet chaining on iOS specifically.** A PDF export dismisses the options sheet,
      may present the progress sheet ~400 ms later, then presents the share sheet when it finishes
      — up to three sheets in sequence. UIKit has historically dropped the second presentation when
      one begins before the previous dismissal animation completes. If the share sheet fails to
      appear on a fast export, the fix is to delay presenting `exportedFile` until the options
      sheet's dismissal completes. I could not reproduce or rule this out without an iOS runtime.
- [ ] **Translate the 81 new strings.** They are in `Localizable.xcstrings` as English-only
      entries; every non-English locale will currently show the English key. Open the catalogue in
      Xcode and translate, or run them through your usual translation pass.
- [ ] Optional: regenerate samples any time with
      `swiftc -swift-version 5 -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 $(find Sources/Shared -name '*.swift') scripts/render_sample_report.swift -o /tmp/rsr && /tmp/rsr /tmp/samples`

### Review pass (2026-07-27)

A six-dimension adversarial review found 14 confirmed bugs, all now fixed and re-verified here
(clean typecheck, six sample renders, pagination swept over 2,400 table shapes, reconciliation
checked across three date ranges with mixed currencies). Two notes for you:

- [ ] **The PDF can differ from the app's screen by one cent per foreign-currency record.** This is
      deliberate. The report books each posting at its rounded value so its own columns add up;
      `AnalyticsEngine` sums unrounded conversions and rounds once. They cannot both be used in one
      document — that was the bug. If you would rather the PDF match the screen exactly, the change
      is to drop `recordValue`'s rounding, and the cost is a statement whose printed opening +
      income + expenses no longer equals its printed closing.
- [ ] **`Tests/ReportRenderingTests.swift` is new** and registered in the project (slot `CA`). It
      has never been run — no XCTest on this machine — but every assertion in it was executed
      against the real code through a standalone driver first.

---

## Landing page rebuild (added 2026-07-27)

### Urgent — three App Store links are dead right now

Every sub-route 404s in production. `BrowserRouter` + GitHub Pages with no `404.html` means a cold
hit on a sub-path gets GitHub's 404; it only looks fine because clicking from `/` routes client-side.
Verified with curl:

| Status | URL | Role on your App Store listing |
|---|---|---|
| `200` | `/wealth-compass/` | — |
| **`404`** | `/wealth-compass/privacy` | **Privacy policy URL** |
| **`404`** | `/wealth-compass/faq` | **Support URL** |
| **`404`** | `/wealth-compass/terms` | **Marketing URL** |

- [ ] I'm fixing this with prerendering in pass 2. Until that ships and you deploy, those links stay
      broken — so **deploy pass 2 before doing anything else with the listing**.

### App Store Connect changes (only you can make these)

- [ ] **Marketing URL points at your Terms of Service.** All 39 locales have
      `marketing_url = .../terms`. It should be `.../` — the "Developer Website" link on your product
      page currently sends people to legal boilerplate instead of the landing page.
- [ ] **Support URL points at the FAQ, which describes the wrong product.** `/faq` currently says
      Wealth Compass is self-hosted on Supabase, has "no official cloud SaaS version", stores data in
      "your own Supabase instance", and answers "How do I get started?" with a guide that opens
      "Node.js 18+ installed on your machine". Someone clicking Support from the store — or an App
      Review reviewer — lands there. Move it to `.../support`, which is genuinely about the app.
      I'll rewrite `/faq` in pass 2 either way.
- [ ] **Provider ID for campaign links.** `web-app/src/site/links.ts` has `PROVIDER_TOKEN = null`.
      Fill it in from App Store Connect → Payments and Financial Reports → Provider ID, and the
      store links start attributing per placement (`site-hero` vs `site-footer` vs `site-mac`) in App
      Analytics. Without it they still work and still attribute at the Web Referrers level.

### Decisions you took that need following through

- [ ] **The repo is not open source.** `LICENSE` is PolyForm Noncommercial 1.0.0 — source-available,
      with a noncommercial field-of-use restriction, which fails the OSI definition. You chose to keep
      the licence and fix the wording. Four places currently claim otherwise and I'll correct them in
      pass 2: `Footer` ("Open source and privacy-first"), `FAQ.tsx:14`, `FAQ.tsx:34`,
      `Support.tsx:23`. **`README.md` also needs the same correction** — that one is outside the web
      app so flag it if you'd rather do it yourself.

### Factual corrections found while building

- [ ] **"38 languages" is wrong.** `Localizable.xcstrings` covers **35 locales**; `metadata/` has 39
      directories but several are regional variants of one language (en-AU/CA/GB/US, es-ES/MX,
      fr-CA/FR, pt-BR/PT). Neither count gives 38. `README.md:28` says 38. The site will say 35.

### Localization bugs in the app (found while extracting real strings)

Reproduced as-shipped on the site, because the site shows the app's actual translations.

- [ ] **`NET WORTH` in Spanish is `PATRIMONIO NETTO`** — Italian spelling. Should be
      `PATRIMONIO NETO`.
- [ ] **`investments` tab label in Spanish is still the English `Investments`** in
      `TabBarLabelResolver.swift`. Regenerate via `scripts/add_tab_bar_localizations.py`.
- [ ] Untranslated (fall back to English in-app), from
      `python3 web-app/scripts/extract-strings.py`:
      `TOTAL` (fr, es, ja) · `Position` (de, fr) · `Transport` (de, fr, ja) ·
      `Recorded Cash`, `Total Assets`, `Top Expense Categories`,
      `Where recorded spending is concentrated`, `Your latest recorded cash movements`,
      `Your financial horizon`, `Savings Rate`, `Settings`, `Utilities`, `Salary` (all ja).
      Japanese is the biggest gap.

### FYI — your working tree switched branches mid-session

At **23:27:09** on 2026-07-27 something ran `git checkout gh-pages` while I was writing files (I ran
no git commands). Nothing was lost and I switched back to `main` with your go-ahead, but you may want
to work out what did it — a deploy script, an editor integration, or another terminal.

---

## Landing page — pass 2 complete (2026-07-28)

### Deploy when ready

```bash
cd web-app && npm run deploy
```

`npm run build` now runs client build -> SSR build -> prerender. After deploying, re-check the three
App Store URLs; they should all return 200 with content.

### Still needs you (unchanged from the earlier list, plus new items)

- [ ] **App Store Connect**: `marketing_url` `/terms` -> `/`, and `support_url` `/faq` -> `/support`
      (39 locales). Both still point at the wrong pages.
- [ ] **Provider ID** for campaign attribution — `web-app/src/site/links.ts`, `PROVIDER_TOKEN = null`.
- [ ] **README.md** still says "38 languages" and calls the project open source. Both are wrong: the
      catalogue has 35 locales and the licence is PolyForm Noncommercial (source-available). The
      website has been corrected; the README has not, because it is outside the site.

### One fidelity question only a device can answer

- [ ] **Donut gap width.** Swift Charts' `angularInset: 2.5` insets *each edge* of a sector, which
      would make the visible gap between neighbours 5°, not 2.5°. The web currently uses 2.5° as the
      total gap. It could not be verified without running SwiftUI. If you have the app open, compare
      the ring's gaps with the site's and tell me — it is one constant in `segments()`
      (`web-app/src/sim/geometry.ts`).

### More localization gaps found in the app

The site shows the app's real translations, so these appear in English there too. Untranslated in
**all seven** non-English demo languages:
`Clear search`, `Crypto view`, `Erase Everything`, `Export Sync Diagnostics`, `Export...`,
`Share Sync Diagnostics`.
Untranslated in Japanese specifically (a large cluster): `Recorded Cash`, `Total Assets`,
`Savings Rate`, `Settings`, `Security`, `Snapshots`, `Search`, `Salary`, `Region & Language`,
`Recurring`, `Recurring Transaction(s)`, `Schedule completed`, `Showing %lld of %lld`, `Source`,
`Top Expense Categories`, `Where recorded spending is concentrated`,
`Your latest recorded cash movements`, `Your financial horizon`, `ECB`.
Plus: `Position` (de, fr), `Transport` (de, fr, ja), `Date`/`Mode`/`Performance` (fr), `OK` (it, de),
`Privacy` (it), `TOTAL` (fr, es, ja).
Run `python3 web-app/scripts/extract-strings.py` any time for the current list.

Still outstanding from before: Spanish `NET WORTH` is `PATRIMONIO NETTO` (Italian spelling), and the
Spanish `investments` tab label is still the English `Investments` in `TabBarLabelResolver.swift`.

### Stale branches you may want to delete

- `promotional-website` (Feb 2026) — the ancestor of the marketing pages, superseded by `web-app/`.
- `gh-pages-webapp` (Jun 2026) — an old deploy target whose workflow was deleted in `ba8c852`.

Neither is referenced by anything. `gh-pages` is the live one and must stay.

---

# SEO + GEO — actions only you can take (2026-07-28)

Two read-only audits (search optimisation; AI-answer-engine and entity authority) ran against the new
build and the live site. Everything inside `web-app/` is being fixed in code. **These are outside this
repo, and four of them outrank most of the code work.**

## 1. CRITICAL — an AI engine asked "who made Wealth Compass" answers wrong today

This was verified with live searches. The answer that comes back is:

> "Wealth Compass is a modern, **open-source** personal financial dashboard ... associated with Simone
> Mattioli, who is developing the project as his **final thesis** for his three-year degree in Computer
> Science at the University of Verona."

and separately, quoted verbatim from your GitHub About box:

> "built with **React and Supabase** ... real-time net worth tracking ..."

Every clause is stale or contradicted by the new site. Engines quote the GitHub **description field**
because it is short and structured — the README body is long and low-signal by comparison.

- [ ] **Rewrite the GitHub About description** at `github.com/simo-hue/wealth-compass`. Suggested:
      > A local-first net-worth tracker for iPhone and Mac. Free, no account, Data Not Collected.
      > Source-available under PolyForm Noncommercial 1.0.0 — not open source.
- [ ] **Fix the topics.** Currently: `dashboard, finance, finance-management, mattiolisimone,
      personal-finance-and-data-anlaysis, personal-finance-manager, personal-finance-tracker,
      personalfinanceapp, pwa, react, simonemattioli, typescript`. There is no `swift`, `swiftui`,
      `ios`, `macos`, `local-first` or `privacy` — so for the query *"local-first personal finance app
      Mac"* the engines currently return a competitor instead of you. (Also `personal-finance-and-data-anlaysis`
      is a typo and therefore a dead classification node.)
- [ ] **README.md**: "38 languages" → 35; add a one-line author block naming you with links to your
      personal site and ORCID; state "source-available under PolyForm Noncommercial 1.0.0 — not open
      source" within the first screenful. GitHub's licence detection returns `NOASSERTION` for PolyForm,
      so there is no machine-readable licence signal at all right now.
- [ ] **Pin `wealth-compass`** on your GitHub profile — it currently is not pinned, and your bio
      mentions "EVOLVE" rather than this app.

## 2. CRITICAL — your `robots.txt` and `llms.txt` are at a path no crawler reads

This is a GitHub Pages **project** site on a sub-path. Per RFC 9309 crawlers only ever read robots.txt
from the origin root — `https://simo-hue.github.io/robots.txt`, which lives in your
**`simo-hue.github.io` repo**, not this one. That file currently has 118 sitemap URLs and **not one**
`/wealth-compass/` entry. So the new sitemap has no discovery path whatsoever.

In the `simo-hue.github.io` repo:

- [ ] Add to `robots.txt`: `Sitemap: https://simo-hue.github.io/wealth-compass/sitemap.xml`
      (a robots.txt may list several sitemaps) and `Disallow: /wealth-compass/sw/`.
- [ ] Add explicit `Allow: /` groups for **`OAI-SearchBot`**, **`ClaudeBot`**, **`Claude-SearchBot`**,
      **`Applebot`** and **`Applebot-Extended`**. All five are currently allowed only by the wildcard;
      the named agents in that file (`Claude-Web`, `anthropic-ai`) are legacy tokens. **Applebot matters
      unusually much here** — it feeds Siri and Spotlight, and this is an Apple-ecosystem product.
      Nothing changes behaviourally; the point is that the permission becomes deliberate so a future
      edit does not silently revoke it. ⚠️ Note a named group *replaces* the `*` group entirely, so any
      future `Disallow` must be repeated in every named group.
- [ ] **`llms.txt` already exists at your root and is being read — it just never mentions this app.**
      Add a section for it. Do NOT add an `llms.txt` to this repo; at a sub-path it would be as unread
      as the robots.txt.

## 3. HIGH — your personal site already has a Person entity; it is missing the good identifiers

`https://simo-hue.github.io/` serves a correct `Person` node with `@id` `.../#person`. The product
site's new JSON-LD **references that same `@id`** rather than minting a second one — two Person nodes
for one human would split the authority. But its `sameAs` currently lists Instagram and YouTube and
**not** ORCID, Scholar, SciProfiles or your Apple developer page.

- [ ] In the `simo-hue.github.io` repo, extend the Person `sameAs` to include:
      `https://orcid.org/0009-0006-5047-8004`,
      `https://scholar.google.com/citations?user=uLGrDbIAAAAJ`,
      `https://sciprofiles.com/profile/Mattioli-simone`,
      `https://apps.apple.com/us/developer/simone-mattioli/id1896746638`,
      and add `"identifier": {"@type":"PropertyValue","propertyID":"ORCID","value":"https://orcid.org/0009-0006-5047-8004"}`.
      ORCID is the one unambiguous, institution-backed identifier available — for a YMYL topic that is
      worth more than any number of social links.

## 4. HIGH — your own blog post about Wealth Compass links to everything except Wealth Compass

`https://simo-hue.github.io/blog/tech-projects/wealth-compass/` exists, is indexed, is in your root
sitemap, is written in the first person, and links to your résumé, the Rabbi e-bike project, CampFlow
and mattioli.OS — **but not to the App Store listing, the repo, or the product site.** It is the
strongest author→product edge available to you, on the same host, and it dead-ends.

- [ ] Add three links to that post: App Store listing, GitHub repo, `…/wealth-compass/`.

## 5. Search Console / Bing

- [ ] Create a **URL-prefix** property for `https://simo-hue.github.io/wealth-compass/` in Google Search
      Console and in Bing Webmaster Tools, and submit the sitemap. HTML-file verification works fine on
      GitHub Pages and does not violate the no-third-party-script rule. **Bing matters specifically
      because Microsoft Copilot's citations come from the Bing index.**

## 6. Name consistency — your name is rendered four different ways

| Source | Rendered as |
|---|---|
| Product site, App Store seller, privacy/terms | `Simone Mattioli` |
| ORCID (`given-names`) | `simone Mattioli` — lowercase |
| Google Scholar | `Mattioli Simone` — reversed |
| GitHub display name | `Mattioli Simone` — reversed |

Location disagrees too: the site says Verona; GitHub says Trentino Alto Adige. None of these is fatal
alone, but on a low-volume entity they lower the confidence with which a knowledge graph merges the
records into one person — which is the whole game here.

- [ ] ORCID: set credit name to `Simone Mattioli`; add the app and product-site URLs under
      "Websites & social links".
- [ ] Google Scholar: name → `Simone Mattioli`.
- [ ] GitHub: display name → `Simone Mattioli`.

Note: `sciprofiles.com` returns HTTP 403 to every automated fetch (Akamai bot protection). Keep it in
`sameAs`, but it cannot corroborate anything an engine can read.

## 7. App Store Connect

- [ ] `marketing_url` `/terms` → `/` and `support_url` `/faq` → `/support/` (39 locales) — still
      outstanding from the earlier list. The "Developer Website" link is one of the highest-trust
      corroboration edges Apple exposes, and it currently points at your terms of service.
- [ ] **The listing description never says source-available, never gives the language count, and never
      says one download covers iPhone and Mac.** Three sentences, free, and `apps.apple.com` is a domain
      every answer engine trusts for app questions.
- [ ] The listing shows **"Apple Vision: visionOS 1.0 or later"**, which the site never claims. Probably
      the default compatibility flag. Either acknowledge it or turn it off — don't leave a machine to
      reconcile a third platform on its own.
- [ ] Fill in `PROVIDER_TOKEN` in `web-app/src/site/links.ts` for per-placement attribution.

## 8. Earned mentions — worth one attempt each, in this order

Realistic ceiling is modest: 3 GitHub stars, no reviews, no press. None of this substitutes for items
1–5.

- A technical write-up **on your own blog** about what Apple's "Data Not Collected" label actually
  asserts and how to verify it from a privacy manifest, using this app as the worked example. You have
  already written most of it in the FAQ; it is genuinely novel material and it is on a domain you own.
- Show HN, once, labelled source-available.
- r/macapps and r/iosapps, following each subreddit's own self-promotion rules.
- Awesome-list PRs only where the app genuinely meets the list's stated criteria.
- Product Hunt, once.

**Do not** do directory-submission runs, solicit reviews, pay for "best of" placements, or seed
comments. On an entity this small, a sudden spike in mention volume is more likely to suppress you than
lift you — and it would be the one thing on this site that could not survive being made public.

---

# Status after deploy (2026-07-28)

**The site is live.** `gh-pages` is published and every route verified by curl against the real host.
Source is on the `landing-page-rebuild` branch, pushed — open the PR at
<https://github.com/simo-hue/wealth-compass/pull/new/landing-page-rebuild> (the `gh` CLI is not
installed on this machine, so it could not be opened from here).

## Now done in the repo — no longer your job

- ✅ **App Store URLs corrected in all 39 locales.** `metadata/*/marketing_url.txt` → `/`,
      `support_url.txt` → `/support/`, `privacy_url.txt` → `/privacy/`, all with trailing slashes so
      they resolve directly instead of through a 301. ⚠️ **These are fastlane metadata — they reach
      App Store Connect only on the next `deliver` run.**
- ✅ **"38 languages" → 35** in `README.md` and `apple/README.md`, verified against the catalogue.
- ✅ **The licence is now stated.** `README.md` has a Licence section explaining why PolyForm
      Noncommercial is not open source, a table of what it permits, and an author block. GitHub will
      still report `NOASSERTION` — PolyForm is not in its SPDX set — which the section says outright.
- ✅ **Superseded marketing code removed**: the old Features/Founder/Tutorial pages, `WebsiteLayout`,
      the six preview components, and `founder.png` (944 kB that shipped on every deploy for an image
      no page requested).
- ✅ A build-time guard now fails the build if any page references a same-site asset that is not in
      `dist`, after exactly that bug shipped a Person image pointing at a 404.

## Still yours, in priority order

1. **GitHub About box + topics** — §1 above. Unchanged and still the highest-leverage item: it is
   what answer engines quote, and it still describes the retired React/Supabase app as "open-source".
   I could not do this from here: it is a repo *setting*, not a file, and there is no `gh` CLI or API
   token on this machine. I am not going to pull a credential out of your keychain to change account
   settings.
2. **`fastlane deliver`** to push the corrected URLs to App Store Connect. The repo is right; the
   listing is not, until you run it.
3. **The four edits in the `simo-hue.github.io` repo** — §2, §3, §4 above: the sitemap line and AI
   crawler groups in the root `robots.txt`, the Wealth Compass block in the root `llms.txt`, the
   ORCID/Scholar/Apple-developer entries in the Person `sameAs`, and three links in your existing blog
   post. Four small text edits, worth batching into one session.
4. **Search Console + Bing** property for the `/wealth-compass/` prefix, then submit the sitemap.
5. Name normalisation on ORCID / Scholar / GitHub (§6), and the App Store description additions (§7).
6. Merge the PR.
