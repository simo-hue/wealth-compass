# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

- [x] **Marketing URL points at your Terms of Service.** ~~All 39 locales have
      `marketing_url = .../terms`.~~ **DONE 2026-08-09** — set to `.../` in all 39 locales; ships with
      the 1.1.6 metadata push (see the 1.1.6 release section at the end of this file).
- [x] **Support URL points at the FAQ, which describes the wrong product.** **URL DONE 2026-08-09** —
      `support_url` is now `.../support` in all 39 locales. The `/faq` *content* problem below is still
      open and unrelated to the URL change. `/faq` currently says
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

- [ ] **"38 languages" is wrong.** `Localizable.xcstrings` covers **35 locales**;
      `apple/WealthCompass/fastlane/metadata/` has 39 directories but several are regional variants of
      one language (en-AU/CA/GB/US, es-ES/MX, fr-CA/FR, pt-BR/PT). Neither count gives 38.
      `README.md:28` says 38. The site will say 35. (Path updated 2026-08-09: the old root `metadata/`
      duplicate has been deleted.)

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

- [x] **App Store Connect**: `marketing_url` `/terms` -> `/`, and `support_url` `/faq` -> `/support`
      (39 locales). **DONE 2026-08-09** in the metadata tree; reaches the store on the next
      `fastlane ios release` / `fastlane mac release`.
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
### Manual Actions Required: App Store Connect Upload
The versions and release notes for iOS and macOS have been updated locally.
- Build and archive the updated apps (v1.1.5, build 21) via Xcode.
- Upload the archives to App Store Connect.
- If using Fastlane `deliver`, execute it to push the new release notes to App Store Connect.

---
### Manual Actions Required: WC-LOCK1 locked-device fix (2026-08-09)

1. ~~**Build and run the test suite on a machine with Xcode.**~~ **DONE (2026-08-09).**
   `xcodebuild test -only-testing:WealthCompassTests/DataProtectionRecoveryTests` passed on the
   `WealthCompassMobile` scheme. Because the tests are hosted by the Mobile app, this also compiled the
   whole iOS target — so every `#if os(iOS)` branch, all of `Sources/iOS/`, and the Mobile-target
   `project.pbxproj` wiring for the two new files are now verified.

   **Still outstanding: build the Mac scheme once.** The macOS module typechecks via `swiftc`, but the
   `WealthCompassMac` target membership for `DataProtection.swift` and `FinanceDataUnavailableView.swift`
   was added by hand-editing `project.pbxproj` and only a real build proves it:
   ```
   cd apple
   xcodebuild -project WealthCompass/WealthCompass.xcodeproj -scheme WealthCompassMac \
     -destination 'platform=macOS' build
   ```

2. **Sync the string catalog.** New user-facing strings were added and are English-only:
   "Loading your data…", "Your Data Is Locked", "Data Unavailable", "Try Again", "Trying Again…",
   "Export Diagnostics", "Share Diagnostics", "Erase and Start Over", "Erase Data on This Device?",
   "Erase", "Cancel", plus the three branched reassurance lines in `FinanceDataUnavailableView`, the erase
   confirmation message, "Your data is protected and can't be read while this device is locked. Unlock the
   device to continue.", "Sync is paused until this device is unlocked.", "Your change was saved on this
   device, but could not be queued for iCloud yet.", and "Your data is locked. Sync resumes once this
   device is unlocked." Run the Xcode string-catalog sync and translate in
   `Sources/Shared/Resources/Localizable.xcstrings`.

3. **Decide the version bump.** `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` were deliberately left at
   1.1.5 (21) — a release decision, not a code one. Bump to 1.1.6 (22) in `project.pbxproj` if shipping
   this as a hotfix.

4. **Verify on a real locked device** (the one thing no simulator can prove — the simulator has no data
   protection at all): with iCloud sync on and the app force-quit, lock the phone, make a change on the
   Mac app to trigger a silent push, wait, then unlock and open the app. Expect: the data present
   immediately, no `ERROR synchronize` lines, and — because the fix deliberately does NOT skip work merely
   because the screen is locked — the push should now actually *sync in the background*, so look for a
   normal `synchronize ... result=ok` while the phone was locked. A `LAUNCH store init — context=bg` line
   confirms the background launch happened at all. Worth repeating once straight after a reboot without
   unlocking (before-first-unlock): there the load genuinely cannot succeed, and the expected trace is
   `ERROR load failed (NSCocoaErrorDomain 257) — device locked, will retry on unlock` followed by
   `RETRY load (protected data available)` / `RECOVERED load ok` after you unlock.

5. **Sanity-check the new failure screen once**, since it is the only UI the user can reach when a load
   fails and it now carries destructive actions. Easiest reproduction on the simulator: corrupt
   `wealth-compass-local-data.json` in the app container (write `{` into it), relaunch, and confirm you get
   "Data Unavailable" with Try Again / Export Diagnostics / Erase and Start Over, that the reassurance line
   does NOT mention iCloud when sync is off, and that Erase returns the app to onboarding.

6. **On your own device**: nothing to do. Your finance data is intact locally and in iCloud, but the sync
   metadata really was wiped, so the next launch will re-upload roughly 440 records with no `systemFields`
   — expect one heavy sync with "record already exists" collisions absorbed by the benign-partial-failure
   path. Do **not** run a factory reset of sync to "fix" it.

---
### Manual Actions Required: 1.1.6 release (2026-08-09)

Version is now **1.1.6 / build 22** and all 39 locales of metadata are written. Everything below has to
happen on the Mac with Xcode, from `apple/WealthCompass`.

1. **Create the 1.1.6 version in App Store Connect — TWICE, before running any lane.**
   Once for iOS and once for macOS: they are separate platforms on the same app record. The Deliverfile
   sets `skip_app_version_update(true)` (deliberately — so fastlane can never create or retarget a version
   behind your back while pushing 39 locales), which means deliver will fail with "Could not find version
   1.1.6" if the version isn't already there.

2. **Authenticate and Ship iOS**, then macOS:
   The Apple ID requires two-factor authentication, which means `fastlane` needs an app-specific password to upload to App Store Connect.
   - Go to [account.apple.com](https://account.apple.com), sign in, and generate an app-specific password.
   - Then set the environment variable and run the release lanes (always using `bundle exec`):
   ```
   cd apple/WealthCompass
   export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD="your-app-specific-password-here"
   bundle exec fastlane ios release
   bundle exec fastlane mac release
   ```

   **To upload ONLY the metadata** (e.g. if the binary already uploaded or if you just want to update screenshots/text):
   ```
   bundle exec fastlane ios metadata
   ```
   Both build, upload the binary, and push metadata. Neither submits for review — `submit_for_review(false)`
   is set on purpose. You press "Submit for Review" yourself in App Store Connect.

   If you'd rather test on TestFlight first: `fastlane ios beta`, then `fastlane ios release` after.

3. **Sanity-check the localized "What's New" in App Store Connect** before submitting, at least for the
   languages you read. The release notes are newly translated for all 39 locales (1.1.5 shipped the English
   string "new cash-flow graph" everywhere), and this is the one field a reviewer and your users both see.

4. **Optional but recommended — scrub your phone number.** `apple/WealthCompass/fastlane/metadata/review_information/`
   now lives in this repo, which is public on GitHub, and it contains your real name, email and
   `+393347985325`. App Review needs a reachable contact, but it does not have to be committed publicly.
   Either replace the file contents with placeholders and set the real values in App Store Connect by hand,
   or add `fastlane/metadata/review_information/` to `.gitignore` and keep it local-only. Say the word and
   I'll do either.

5. **Nothing needs doing about the old root `metadata/` folder** — it was a stale duplicate (312 files
   diverged, with contradictory URLs) that no tooling read, and it has been deleted. The single source of
   truth is now `apple/WealthCompass/fastlane/metadata/`.
