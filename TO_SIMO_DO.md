# TO SIMO DO

This document tracks **manual actions** and the **manual verification checklist** (builds + smoke
tests) for the Apple app deep-audit remediation. Claude keeps implementing batches without blocking;
you run the checks below whenever you're at a real Mac and report anything red.

---

- [ ] **Provider ID for campaign links.** `web-app/src/site/links.ts` has `PROVIDER_TOKEN = null`.
      Fill it in from App Store Connect → Payments and Financial Reports → Provider ID, and the
      store links start attributing per placement (`site-hero` vs `site-footer` vs `site-mac`) in App
      Analytics. Without it they still work and still attribute at the Web Referrers level.

### Decisions you took that need following through

- [ ] **The repo is not open source.** `LICENSE` is PolyForm Noncommercial 1.0.0 — source-available,
      with a noncommercial field-of-use restriction, which fails the OSI definition. You chose to keep
      the licence and fix the wording. **Exactly one place still claims otherwise**:
      `web-app/src/components/layout/Footer.tsx:18` ("Open source and privacy-first") — and nothing
      imports that file, so the string is not currently shipping. The rest are already correct:
      `FAQ.tsx:14` / `:34` are a file-header comment and `Support.tsx:23` is a field on the `Topic`
      type, and those pages now assert the opposite (`OpenSource.tsx:188` reads "Source available. Not
      open source."). `README.md:18` and `:105-112` say it plainly too.

### Factual corrections found while building

- [x] **DONE 2026-08-25. "38 languages" was wrong.** `Localizable.xcstrings` covers **35 locales**;
      `apple/WealthCompass/fastlane/metadata/` has 39 directories but several are regional variants of
      one language (en-AU/CA/GB/US, es-ES/MX, fr-CA/FR, pt-BR/PT). Neither count gives 38.
      `README.md:36` and the site both say 35 now. (Path updated 2026-08-09: the old root `metadata/`
      duplicate has been deleted.)

### Localization bugs in the app (found while extracting real strings)

Reproduced as-shipped on the site, because the site shows the app's actual translations.

- [x] **DONE 2026-08-25.** **`NET WORTH` in Spanish was `PATRIMONIO NETTO`** — Italian spelling.
      Fixed in `a5c166d`: `es` and `es-419` both hold `PATRIMONIO NETO` now, and `PATRIMONIO NETTO`
      survives only in the five correct `it` entries.
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
- [ ] **`web-app/src/components/layout/Footer.tsx:18`** still reads "Open source and privacy-first" —
      the last surviving open-source claim anywhere in the repo. Nothing imports that file, so it is
      not shipping; correct the string or delete the file before it gets wired back in. `README.md`
      is **not** the problem: `:36` already says 35 languages and `:18` / `:105-112` already say
      source-available, not open source.

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

Spanish `NET WORTH` (`PATRIMONIO NETTO`, Italian spelling) is **fixed** as of `a5c166d` — `es` and
`es-419` both hold `PATRIMONIO NETO`. Still outstanding from before: the Spanish `investments` tab
label is still the English `Investments` in `TabBarLabelResolver.swift`.

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
- [ ] **README.md**: the count (now 35, `:36`) and the "not open source" line within the first
      screenful (`:18`) are **done**. Still to do: the author block currently names you and links your
      personal site at `:20`, but ORCID only appears far down at `:132` — pull it into the first
      screenful. GitHub's licence detection returns `NOASSERTION` for PolyForm, so there is no
      machine-readable licence signal at all right now.
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

- **Enable GitHub Actions Permissions**: To allow the new automated deployment to work, go to your repository on GitHub -> **Settings** -> **Actions** -> **General** -> **Workflow permissions**. Select **Read and write permissions** and save. Otherwise, the deployment action will fail to push to the `gh-pages` branch.

---

## Deep audit — remaining findings (2026-08-25)

Eight parallel read-only audits over `apple/`, then three adversarial verification rounds.
**38 commits landed on `main`** (`50a7037`…`15d2983`): 6 of 8 P1s, ~45 P2s. Suite went 221 → 275,
green; both targets build. Full write-up with reasoning:
<https://claude.ai/code/artifact/12fa859e-cab4-403d-a677-0af1585c44f9>

Everything below is **audit output that I have not personally verified line-by-line**. Treat each as
a lead with a file:line, not a verdict.

### Two P1s deliberately left alone — they need your iPhone *and* your Mac

Nothing on a dev machine can exercise real `CKSyncEngine` convergence, so per the agreed policy these
were written up rather than changed. Both are data-loss shaped.

- [ ] **A remote edit can be destroyed on both devices.** `CloudKitSyncService.swift:1457-1465`.
      Post-bootstrap, a fetched remote change is discarded whenever *any* pending mutation exists
      locally, ignoring its `origin`. An `.inventory` pending is not a user edit — it is un-uploaded
      first-sync inventory — but it still wins, and `systemFields` is overwritten with the server's
      current tag, so the next send raises no conflict and overwrites the server with stale data.
      The sent-side twin (`conflictAction`, `:1921-1932`) documents the *opposite* policy for the same
      pending kind. Fix is to check pending **origin**, not pending presence.
      *Repro:* device B freshly installed with imported data; let its first fetch complete but kill
      the network before its inventory upload finishes. Edit the same record on A. Bring B back.
- [ ] **Deleting iCloud data doesn't stick.** `CloudKitSyncService.swift:1330-1347`.
      `CKSyncEngineFetchedZoneDeletion.reason` is never inspected, so `.purged` and
      `.encryptedDataReset` are treated as "recreate the zone and re-upload everything". Apple's
      header is explicit that for both you must delete local data and *not* resend it. This also
      defeats "Erase Everything, including iCloud" from a second device.
      *Repro:* delete the app's data from iCloud settings on one device with the other running.

### Sync P2s that *are* test-provable (pure logic, no device needed)

- [ ] `:1479-1480` — the bootstrap `.local` branch requeues a key without ensuring a pending
      mutation exists, so when `pending == nil` the winning local value is enqueued but never sent.
      Permanent silent divergence. The sibling tombstone branch 30 lines above handles exactly this.
- [ ] `:712-718` — a delete overwrites pending state unconditionally, so a create-then-delete faster
      than one send cycle uploads a tombstone for a record the server never held. Those are never
      hard-deleted, so the zone accumulates them and every new device downloads them.
- [ ] `:1526-1528` — any throw inside `handleFetchedRecordZoneChanges` abandons the whole batch, but
      the engine is never told, so the change token advances past changes that were never applied.
- [ ] `:1664-1665` — `case .fatal: throw` aborts the classification loop mid-way, dropping the
      resolutions of every record not yet classified in that batch.
- [ ] `:1196-1200` — `didFetchRecordZoneChanges.error` is discarded and `.didFetchChanges` sets
      `bootstrapCompleted = true` unconditionally, so a fetch that failed part-way counts as a
      completed bootstrap — which is the precondition for the first P1 above.

### PDF export

- [x] **DONE 2026-08-25.** `ReportDocumentBuilder.swift:497-518` — inside a custom date range, the Cash Flow KPI row and
      the Monthly Trend chart are computed from `now`, not from `options.dateRange`, so a 2024 export
      prints 2026 figures under a cover page stating the 2024 period. The comments two blocks below
      state this rule and were applied to the Money Flow and category totals only.
- [x] **DONE 2026-08-25.** `:394-399` — the allocation donut's centre is labelled `Total Assets` but carries `ringTotal`,
      which differs whenever cash is net-negative. Two different figures under one label, one page.
- [x] **DONE 2026-08-25.** `:524-529` — the Money Flow sums unrounded conversions while the category table sums rounded
      ones, so the same category prints two amounts. Needs foreign-currency rows to show.
- [x] **DONE 2026-08-25.** `:928-930` — when no FX snapshot exists the appendix prints a note saying fallback rates were
      used and then **omits the rate table**, i.e. the one case where figures are least reproducible.
- [x] **DONE 2026-08-25.** `:250-263` — axis magnitude suffixes `B`/`M`/`k` are raw literals in all 35 languages
      (ja wants 万/億, de "Mio.", ru "млн").
- [x] **DONE 2026-08-25.** `:635-639` — the future-dated note is `String(format:)`-substituted after a plain lookup, so a
      catalog `variations.plural` entry can never fire. Also no plural handling for English.
- [x] **DONE 2026-08-25.** `:654-660` — the month-subtotal label is written into cell 0, which is the 61.9pt Date column,
      so every subtotal row truncates while 243pt of adjacent cells sit empty.
- [x] **DONE 2026-08-25.** `PDFReportRenderer.swift:288-291` — every contents row is a hyperlink but destinations are only
      registered for section anchors, so all level-1 contents links are dead (~20 of ~25 rows).
- [x] **DONE 2026-08-25.** `PDFReportRenderer.swift:6-18` — `ReportRenderError` returns raw English; both Settings screens
      surface it. Every sibling error type has `localizedDescription(appLanguage:)`.
- [x] **DONE 2026-08-25.** `PDFReportRenderer.swift:453-456`, `ReportChartRenderer.swift:444-463` — `isNumeric: true` with
      `.leading` alignment pins text to the opposite page edge in RTL, so each KPI tile reads
      label-right / value-left / detail-right.
- [ ] **Known and deliberate:** long translated table headers still truncate. `GANANCIA / PÉRDIDA`
      needs ~0.65 scale (a 4.8pt heading) against a 64.0pt column. Either the column budget or the
      translation has to give; pinned by a test so the choice stays visible.

### macOS layout and lifecycle

- [ ] `MacCryptoView.swift:183` — a fixed 400pt performance card (`.frame(width: 400)`) beside the
      allocation donut in a non-reflowing `HStack`. At the 520pt window minimum the donut gets ~48pt. `MacInvestmentsView`
      already solved this (tag L24); Crypto was never migrated.
- [ ] `MacCashFlowView.swift:644-737` — the Transactions filter bar is a fixed-width row needing
      ~950pt; it clips at the default window size once the category chip is present.
- [ ] `MacPlatformServices.swift` — no `applicationShouldTerminate`, so ⌘Q with an editor sheet open
      discards everything typed. The codebase treats this as a bug elsewhere (tag L13).
- [ ] `MacRootView.swift:59-66` — the inactive-window privacy shield is an overlay on the root group,
      so a presented sheet floats above it and stays legible during app switching.
- [x] **DONE 2026-08-25.** `MacEditorSheet.swift:282-291` — Sector/Geography pickers don't keep an out-of-list current
      value selectable, unlike the Category picker (tag DA-H06), so an imported value shows blank.
- [x] **DONE 2026-08-25.** `MacSettingsView.swift:158-165` — `@Published` mutated inline inside `.onChange(initial: true)`
      during the same view update. `MacCashFlowView:457-464` defers the identical case in a `Task`.
- [ ] `WealthCompassMacApp.swift:60-94` — ⌘E and ⌘1-5 aren't disabled during onboarding, so a stale
      export token fires later and drops the user into Settings with the sheet open.
- [x] **DONE 2026-08-25.** `MacDashboardView.swift:9` — default net-worth range is `.oneYear` on Mac, `.oneWeek` on iPhone.

### iOS

- [ ] `LockView.swift:70-78` — the one-shot biometric prompt is consumed while the app is
      backgrounding, and the `.onChange` meant to re-arm it is registered only after `LockView`
      mounts, i.e. after the transition it watches for. The user lands on the lock screen with no
      prompt. (The lock itself is **not** bypassable.)
- [x] **DONE 2026-08-25.** `SettingsView.swift:80,81,540,546` — `categoryGroup(title: String)` splices an English noun into
      a translated sentence: German reads "Noch keine benutzerdefinierten income-Kategorien."
- [ ] `DashboardView.swift:131` — `heldCurrenciesUsingSeedRate` is the only derived Dashboard value
      not memoized on `dataVersion`, and it runs per frame while scrubbing the net-worth chart.
- [ ] `RecurringTransactionNotificationService.swift:82` — **the project's one remaining compiler
      warning**, and the one thing blocking the Swift 6 language mode: `[AnyHashable: Any]` crossing
      into a main-actor-isolated `didReceiveRemoteNotification`. I tried `nonisolated`,
      `@preconcurrency` on the method, and `@preconcurrency` on the conformance — the first two do
      not silence it and the third is rejected outright ("has no effect"), so I reverted rather than
      leave a guess in place. Nothing reads `userInfo` (a CloudKit silent push only signals "the zone
      changed"), so dropping the parameter or restating the requirement may be the real answer. Worth
      ten minutes with the Swift 6 migration guide rather than more guessing.
      (The second warning is gone: the deprecated `resultsTruncated` assertion in
      `Tests/CloudSyncCoreTests.swift` was deleted, and `:860-863` is now a comment recording that it
      *was* the warning source. The one surviving `.resultsTruncated` reference,
      `CloudKitSyncService.swift:2039`, is deliberate defensive handling — leave it.)

### Store, services, import

- [ ] `FinanceStore.swift` — there is **no** `upsertLiability` / `deleteLiability`. Liabilities count
      in totals, allocation and sync but can only enter via import or CloudKit, and can never be
      edited or removed in either app.
- [ ] `FinanceStore.swift:206` — `iCloudSyncError` is written in twelve places and read by no view, so
      the WC-LOCK1 "saved locally but not queued for iCloud" message can never reach a user.
- [ ] `FinanceStore.swift:1074-1076` — `snapshots(range:)` is unused *and* mis-wired (defaults to
      `.eur` with a nil-rate converter); the mis-wiring itself is at `AnalyticsEngine.swift:16-17`.
      Latent P1 the moment anyone calls it. (`:1031-1035` is now `appendSnapshot`.)
- [ ] `FinanceStore.swift:1732-1738` — retain cycle between the store and its save-consumer task;
      `deinit` never runs, so tests leak a store per instance.
- [ ] `FinanceStore.swift:982-986` / `1136-1145` — complementary currency-coverage gaps:
      `hasForeignCurrencyExposure` omits transactions, `heldCurrenciesUsingSeedRate` omits
      liabilities and recurring schedules.
- [ ] `FinanceStore.swift:1232-1254` — plaintext JSON backups accumulate in `tmp/` forever;
      `pruneStaleExports` only runs on the PDF path despite its comment claiming both.
- [ ] `FinancePersistence.swift:72-81` — H08-skipped records are preserved on disk only until the
      user's next edit, which rewrites the file from the lossy in-memory snapshot. With iCloud sync
      off nothing else holds a copy.
- [ ] `FinanceImportService.swift:1015-1020` — `Currency.imported` substitutes the display currency for
      any ISO code outside the ECB set, mislabelling the money instead of skipping it. The Revolut
      parser in the same pipeline makes the opposite (correct) choice and is locked in by a test.
- [ ] `FinanceImportService.swift:959-969` — string amounts blindly swap `,` for `.` (`:962` does
      `.replacingOccurrences(of: ",", with: ".")`), so `"1,234"` imports as **1.234** — a thousand
      times too small. `BrokerImportParsing.flexibleDecimal` in the sibling file already
      implements the correct last-separator-wins rule and is reachable from here.
- [ ] `BrokerStatementImportService.swift:752-764` — Revolut crypto hardcodes `.eur` while discarding
      the currency symbol present in the cell, and stamps `updatedAt: Date()`, so every re-import
      wins `mergedByID` and wipes user-edited `avgBuyPrice` / `coinId`.
- [ ] `BrokerStatementImportService.swift:508,720` — broker parsers can emit two records with the
      same deterministic UUID and never `uniquedByID()` them, so one silently vanishes at sync time
      without incrementing `skippedRecords`. The JSON path solves this (tag WC-L7).
- [ ] `MarketDataService.swift:659` — `let pool = eligible.isEmpty ? candidates : eligible` widens
      symbol matching to non-equity quote types, contradicting the method's own contract.

### Corrections to my own commit messages

- `a710629` claims the month-subtotal label is "more in German". It isn't: the key `"subtotal"` has
  **zero** localizations, so it renders English in all 34 locales. The truncation it fixed was real
  (118pt of English label in a 62pt column); only the German half of the sentence was wrong.
- The PDF report's whole vocabulary is still in that state — `subtotal`, `Appendix`, `Contents`,
  `Closing Balance`, `Effective Date` and the rest are present in the catalog with no translations.
  That is the single largest untranslated cluster left and it is all one screen's worth of work.

### Two smaller things found while fixing the PDF

- [ ] `ReportDocumentBuilder.swift:718-721` — with zero transactions in the selected range the ledger
      early-returns before its Opening/Income/Expenses/Closing row, leaving the bounded export's
      lone Net Savings tile unaccompanied. All figures are zero so nothing is wrong, but the section
      reads oddly.
- [x] **DONE 2026-08-25.** The Monthly Trend chart was capped at twelve bars, which silently dropped
      months the ledger still reported — `.last12Months` spans thirteen calendar months, and a
      multi-year export charted only its tail. Cap removed; pinned by a test.

### A trap worth knowing about

`xcodebuild -only-testing:WealthCompassTests/<Class>/<method>` silently selected **nothing** here and
still reported `** TEST SUCCEEDED **`. I used it three times to check that a new test fails against
the pre-fix code, and all three checks were vacuous — an unconditional `XCTFail` inside the test
still "passed". Run the **full suite** for before/after verification; it is about two minutes and it
actually executes the test.

### Notes for whoever picks this up

- **`extractionState: "stale"` is not proof a key is dead.** 452 call sites localize at runtime via
  `L(…)`, `AppLocalization.string(…)` and `settings.localized(…)`, none of which Xcode's extractor
  sees. Of 42 stale-marked keys, 10 are live.
- **Every string written by an agent is `state: "needs_review"`**, never `"translated"`. That is how
  you tell machine output from human-blessed values. The `PATRIMONIO NETTO` bug was invisible for
  precisely one reason: it was marked `translated`.
- **~42% of the UI is still untranslated per language** — mean 327.8 of 785 keys per non-English
  locale, i.e. 41.8%. Half of that is *absent* keys; the other half are entries that exist, are
  marked `needs_review`, and hold the English string verbatim — a class a naive "missing keys" count
  does not see.
- **Run the suite before releasing.** It was red on `main` through the 1.1.6 release, on two stale
  assertions, which is why nothing flagged it.
