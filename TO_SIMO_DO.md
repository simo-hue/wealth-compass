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

- [ ] **`-exportLocalizations` deletes 60 report keys, and marking them `manual` would stop it.**
      Not urgent — nothing in the build or the test path runs it, and no *translation* is at risk
      (all 64 keys it removes carry zero localizations; the 24 translated keys it cannot find are
      marked `stale` and kept verbatim). But it is a loaded gun: one export on a clean tree takes
      the catalog from 791 keys to 727, and 60 of the 64 are `ReportDocumentBuilder.swift`'s,
      reached through its `L(_ key: String)` wrapper (`:200`) which the extractor cannot see
      through. Adding `"extractionState" : "manual"` to those 60 entries removes the hazard
      permanently — verified: marking three of them dropped the removals to 61 and all three
      survived. The measurements and the interim workaround are in `apple/CLAUDE.md` → Build & test.

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
- [ ] `Sources/iOS/Services/RecurringTransactionNotificationService.swift:82` — **the project's one
      remaining compiler warning**, and the one thing blocking the Swift 6 language mode: `[AnyHashable: Any]` crossing
      into a main-actor-isolated `didReceiveRemoteNotification`. I tried `nonisolated`,
      `@preconcurrency` on the method, and `@preconcurrency` on the conformance — the first two do
      not silence it and the third is rejected outright ("has no effect"), so I reverted rather than
      leave a guess in place. Nothing reads `userInfo` (a CloudKit silent push only signals "the zone
      changed"), so dropping the parameter or restating the requirement may be the real answer. Worth
      ten minutes with the Swift 6 migration guide rather than more guessing.
      ⚠️ **Do not conclude this entry is stale without checking the right file and the right scheme.**
      Two files have nearly this name: the one above in `Sources/iOS/Services/`, and
      `Sources/Shared/Services/RecurringNotificationService.swift`, whose line 82 is an innocent
      `content.body` assignment. And the Mac scheme never compiles `Sources/iOS/`, so a clean **macOS**
      build emits zero Swift warnings and proves nothing here. A clean `WealthCompassMobile` build
      emits it, but **how many times depends on the destination**: twice against a concrete simulator,
      four times against `generic/platform=iOS Simulator`, which compiles arm64 and x86_64 (twice per
      arch). A *cached* build emits none. Count distinct warnings, not lines.
      Checked 2026-08-25 — both mistakes were made that day.
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

### Doc-comment audit coverage (2026-08-25)

Comments were audited against the code they describe, and 18 discrepancies were corrected — two of
which turned out to be live bugs rather than stale prose. Coverage was **not** uniform:

- **Read in full and verified**: all of `Sources/Shared/` — Models, Persistence, Services, Stores,
  Export, UI (40 files).
- **Partial**: the 21 files under `Sources/iOS/` and `Sources/macOS/` had every comment line scanned
  and individual claims spot-checked, but were not read end to end. Stale comments may remain there,
  particularly ones that cite point widths, column weights or SF Symbol names.

Numeric claims that were checked and are still accurate, so nobody re-measures them: the 64.0pt money
column (computes to 64.01), the ~62pt ledger Date column (61.9), "US Letter is 50pt shorter" (49.89),
the 0.70/0.78 shrink floors, the 8-colour palette and top-7 cap arithmetic, and the 8% axis floor.

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

### Deliberately not fixed — your call to overrule (2026-08-25)

Each of these was found by adversarial review, confirmed real, and left alone because fixing it means
changing a working feature's design rather than correcting a wrong implementation. Listed so the
decision is on the record instead of buried.

- [ ] **Privacy Mode still discloses the *sign* of a gain.** `DesignSystem.swift:396` tints `ValueDelta`
      with `value >= 0 ? WCColor.primary : WCColor.destructive`, so a fully redacted row still reads
      `•••• (••••)` in green or red. Same is true of the Profit/Loss cards' `accent:`. Masking it is a
      real design cost — a delta row with no colour reads as broken — so it needs a decision, not a
      patch.
- [ ] **`arrow.up.right` carries two meanings on the Dashboard.** `MacDashboardView.swift:263` uses it
      green for a net-worth *gain*; `:117` uses it red for Monthly *Expenses*, ~100pt below, and `:953`
      red for an expense in the activity list. Same on iOS (`DashboardView.swift:154` vs `:573`). The
      reviewer called this the same collision the arrow fix removed from `MacCashFlowView`. Counter-
      argument, and why it is still here: trend-sign and money-flow are different semantic families,
      colour separates them consistently within each, and the two never share a row. Changing dashboard
      iconography is a visual design decision.
- [ ] **PDF export is entirely unredacted, by design.** `ReportDocumentBuilder.swift` and
      `ReportChartRenderer.swift` render every amount and percentage with no `isPrivacyMode` check.
      This is not the same bug as the on-screen leaks — nothing is masked there, so nothing is given
      back — and `ExportOptionsView.swift:91` shows a `privacySection` warning before the user commits.
      Recorded so the omission is a choice rather than an oversight.
- [ ] **Two idioms now coexist for percentage redaction.** Most sites call `settings.privatePercent(…)`;
      `DesignSystem.swift:469` and `:588` keep the inline `isPrivacyMode ? redactionToken : percentage(…)`
      form because they derive a share from a total through a local helper. Both correct. Unifying is a
      refactor, not a fix.
- [ ] `AppSettings.privatePercent`'s doc comment still frames it as being for "the gain/loss rows". It
      now serves 14 sites. Narrow, not wrong.

### How the privacy leak was actually pinned (2026-08-25)

Worth copying next time: the first attempt shipped three tests that exercised `AppSettings.privatePercent`
in isolation. Reverting **all six** call sites left the suite fully green — they proved nothing about the
bug. The replacement, now `testWorkingTreeSourcesContainNoUnguardedPercentageRender`, reads the view
sources via `#filePath` and fails on a percentage render in a `View` body not covered by an
`isPrivacyMode` gate. It is a lint wearing a test's clothes, but it is the only form that fails when a
call site regresses — there is no supported way to read a rendered `Text` back.

Adversarial review then broke the first version of it: **seven live unredacted percentage renders sat in
the tree at once with the suite fully green.** What that cost, and what the current version does about it:

- It greps the **working tree, not the binary under test**. Proven by building the bundle from a leaky
  tree, restoring the sources, and running `test-without-building` against that same leaky binary —
  green. Any build-then-patch flow gets a false pass. Unfixable in this design; the test name and doc
  comment now say so outright.
- Its floor was **backwards**: routing three *more* sites through `privatePercent` — making the app
  strictly more private — dropped the scanned count below the floor and failed the suite. Replaced with
  checks that only trip when enumeration itself breaks (files read, lines read).
- **Allman braces broke it**, as did a comment containing a stray `{`. A test that fails on reformatting
  is worse than none. Now handled by a comment/string stripper.
- Its gate check accepted **any** `isPrivacyMode` anywhere in the enclosing block, so a live percentage
  dropped beside an unrelated privacy ternary passed green. Now the gate must cover the block header or
  the render's own expression.
- **The widest remaining hole, by design:** move a render into a `-> String` helper and the sweep stops
  seeing it. Confirmed empirically. Closing it means gating at call sites the sweep cannot follow.

The lesson generalises past this test: a lint over source text proves things about text. Prefer a test
that exercises the code whenever one is possible at all.

### Privacy Mode and chart geometry — one decision, nine charts (2026-08-25)

Redacting a number but drawing its proportion gives the number back. The app already agrees with that in
writing — `SankeyDiagramView.swift:54-56` refuses to redact-and-draw ("a ribbon's width *is* the
proportion, so the shape alone still tells a bystander where the money goes") and conceals its whole
chart, and macOS ships a component called `PrivacyChartCover` whose message is **"Values and proportions
are hidden."** It is applied inconsistently. Full inventory so this is decided once:

**Already concealed (the consistent set).** Net-worth charts `DashboardView.swift:193` /
`MacDashboardView.swift:299`; cash-flow bars `DashboardView.swift:416` / `MacDashboardView.swift:604` /
`MacCashFlowView.swift:296`; macOS asset donut `MacDashboardView.swift:440`; Sankey
`SankeyDiagramView.swift:53`. Every one of them now checks privacy **first** — see the ordering item
below, which was closed on the same day.

- [x] **A platform split that is a defect, not a preference.** iOS Asset Allocation
      (`DashboardView.swift:48`) drew true proportions in Privacy Mode while the **same chart** on macOS
      concealed. **Fixed 2026-08-25** by the item below — the iOS Dashboard ring is one of the eight, so
      concealing `AllocationChart` closed this with it. Note for anyone reading `MacDashboardView.swift:440`
      as "the macOS twin": that card is *not* an `AllocationChart` call site, it inlines its own
      `Chart`/`SectorMark`, so there was no redundant outer wrapper to collapse afterwards.
- [x] **Eight rings share one view and none of them conceal.** **Fixed 2026-08-25.** `AllocationChart`
      (`DesignSystem.swift:412`) now branches `privacy → empty → chart`, showing
      `MobilePrivacyChartCover("Allocation concealed" / "Values and proportions are hidden.")` in place of
      the ring — the same order the iOS net-worth and cash-flow cards now use
      (`DashboardView.swift:193`, `:416`) and the one its macOS counterpart uses. Ring, legend and
      footnote conceal together: a legend under a cover would restate the value ordering the cover just
      hid, and `DashboardView.swift:52-56`'s footnote would otherwise dangle under it. All nine call
      sites conceal: `DashboardView.swift:48` · `InvestmentsView.swift:59,62,63` · `CryptoView.swift:60` ·
      `MacInvestmentsView.swift:47,53,59` · `MacCryptoView.swift:141`.
- [x] **The iOS expense donut** `CashFlowView.swift:174` — **fixed 2026-08-25**, same cover, its own
      title (`Spending breakdown concealed`, a new key). Its top-six category list below the ring (now
      `:275`) deliberately **stays**: ranked lists are a separate decision, below.
- [ ] **Collapsed bar, surviving ranking.** `DashboardView.swift:553` collapses its bar to
      `width: 0` under Privacy Mode, but the leaderboard around it keeps rank badge (`:521`), category
      name (`:525`) and value-descending order (`:496`). The bar hides; the ranking does not. iOS only.
      The collapsed bar itself is now pinned: dropping the `settings.isPrivacyMode ? 0 :` is reported by
      `testWorkingTreeSourcesDrawNoUnconcealedDonut`, which matches a data-scaled `.frame`.
- [ ] **macOS allocation legend renders in Privacy Mode.** `MacDashboardView.swift:537-559` is a sibling
      of the privacy branch (`:440`), not part of it, so the cover never reaches it. Values redact at
      `:549`/`:552`; bucket order is fixed, so it discloses which buckets are non-zero. Left deliberately
      untouched by both the footnote fix and the ordering flip — closing it changes what macOS renders and
      is a decision of its own. iOS conceals its legend with the ring.
- [ ] **The net-worth card still says it is empty, in words, right above the cover.** Found while
      screenshotting the fix above on a fresh simulator with Privacy Mode on: the chart is concealed,
      and the same card prints "No snapshots" (`DashboardView.swift:307` / `MacDashboardView.swift:424`,
      the `snapshotFreshness` header) and "Add another snapshot to see movement"
      (`DashboardView.swift:163` / `MacDashboardView.swift:272`, the `rangeChange == nil` fallback).
      Both appear *only* when there is no history, so between them they hand back exactly the fact the
      ordering flip was made to hide. They are labels rather than chart branches, which is why the flip
      did not reach them, and `testWorkingTreeChecksPrivacyBeforeEmptiness` cannot see them either —
      it only knows about covers. Same shape as the item above it.
- [ ] **Ranked lists have no privacy awareness at all** — amounts redact, identity and order do not.
      One choke point: `FinanceModels.swift:635-649` (`rankedByValue`, takes no `AppSettings`). Sites:
      `InvestmentsView.swift:146` ↔ `MacInvestmentsView.swift:173-175,207`; `CryptoView.swift:204` ↔
      `MacCryptoView.swift:225-227,258`. The Top Performer / Biggest Loser cards
      (`CryptoView.swift:138-193` ↔ `MacCryptoView.swift:157-217`) are worse: their *existence* is gated
      on `gainLossPercent > 0` / `< 0` (`:143-144`), so the card appearing at all discloses the sign.

The three ticked items were fixed on 2026-08-25 (owner's call: conceal every ring). The three open ones
were left deliberately — ranked lists, their ordering and the Top Performer / Biggest Loser cards stay as
they are for now. No `Gauge`, `.trim(from:to:)`, `Canvas`, sparkline or heatmap exists anywhere, so this
list is complete for proportional geometry.

`SectorMark` is now pinned by `PrivacyRedactionTests.testWorkingTreeSourcesDrawNoUnconcealedDonut`, a
second source sweep beside the percentage one: it reports any donut not enclosed by an `isPrivacyMode`
branch. Same two caveats as its sibling — it greps the working tree rather than the binary, and it only
sees the spelling it looks for, so a new *kind* of proportional chart needs the pattern extended. It was
run against the pre-fix tree and reported exactly the two leaks above (and not the already-concealed
macOS donut), so it is not vacuous.

### Two near-identical privacy covers now coexist (2026-08-25)

Fallout from `e55f742`, worth one deliberate pass rather than leaving it to drift:

- [ ] **`MobilePrivacyChartCover` is misnamed now.** It is what the nine shared `AllocationChart` rings
      render, so macOS Investments and macOS Crypto show a cover called *Mobile*. Meanwhile
      `MacDashboardView.swift:448` still uses its own `PrivacyChartCover` — that card is **not** an
      `AllocationChart` call site (grep returns 0); it inlines its own `Chart`/`SectorMark`, which is
      why the two were never unified. They differ slightly: corner radius 15 vs 14, black .14 vs .12,
      `textTertiary` vs `textFaint`. Unifying changes macOS pixels, so it is a decision, not a cleanup.
      At minimum, rename the shared one — it is no longer mobile-only.
- [ ] **`Values and proportions are hidden.` is 7/35 `translated`, 28 `needs_review`.** Pre-existing, but
      this string went from **one** macOS-only site (`MacDashboardView.swift:450` — the "3" written here
      first counted the three macOS `PrivacyChartCover` calls, only one of which carries this message) to
      **eleven** charts across both platforms: that one, the nine `AllocationChart` rings, and the iOS
      expense donut. Far more users now read it. Highest-value single string to get translated properly.
- [ ] **`Spending breakdown concealed` is 1/35 `translated`, 34 `needs_review`.** Added so the iOS expense
      donut's cover names its own chart instead of borrowing `Allocation concealed` (which is 35/35). The
      34 are machine translations and have never been read by a speaker.
- [x] **Two conceal orderings disagree in this codebase — RESOLVED 2026-08-25 in favour of privacy
      first.** `SankeyDiagramView.swift:45-53` had argued it alone: "whether a period is empty is itself
      information". Every other chart checked emptiness first, so with Privacy Mode on and no data the
      user saw "No assets found" / "No recent cash flow" instead of a cover. Eight sites flipped:
      `DesignSystem.swift:429` (all nine `AllocationChart` rings at once), `CashFlowView.swift:174`,
      `DashboardView.swift:193` and `:416`, `MacDashboardView.swift:299`, `:440` and `:604`,
      `MacCashFlowView.swift:296`. It matters most on the four cards under a range picker: a bystander
      could walk 1W/1M/3M/6M/12M and map which windows hold data with every figure redacted.
      `testWorkingTreeChecksPrivacyBeforeEmptiness` pins it — against the pre-flip tree it reported all
      eight.

### Privacy Mode leaks existence, not just values — CLOSED (2026-08-25)

The chart work (`e55f742`, `24ffc78`) and the Dashboard label work (`b93f391`) established the rule:
Privacy Mode must not disclose *whether* data exists, only conceal what it is. A sweep of all eight
source directories then found **43 sites in that class; 6 are fixed, 37 are open.** They are the same
defect repeated, in three shapes.

**DONE.** Closed in `65bf189`, `fb5272c`, `f3fac7c`, `52c062a`, `96d535f` — **41 sites**, not 37. The
counts below were undercounts and the `DashboardView`/`MacDashboardView` line numbers were stale by the
24 lines `b93f391` inserted (anything after :149 had moved). Corrections: raw counts were **19** sites,
not 11 — the sweep missed `DashboardView.swift:352`, `MacDashboardView.swift:142`, and both `Showing N
of M` rows, the macOS one sitting *inside the filter bar*, which is the most direct form of the probe.
The `Never` fallbacks were **4**, not 8; the original entry collapsed a class count onto them. Kept below
as written, because the shapes are the useful part.

The app already agrees counts are sensitive — `InvestmentsView.swift:107` redacts
`investments.count` behind `settings.isPrivacyMode ? settings.redactionToken : …`. It just doesn't do it
consistently.

- [ ] **Raw counts printed with no redaction — 11 sites.** Sharpest: `SettingsView.swift:197-231` and
      `MacSettingsView.swift:473-483` print **six** unredacted entity counts, including
      `Text("\(finance.data.snapshots.count)")` — a direct readout of the exact fact `b93f391` just
      concealed on the Dashboard. Also `DashboardView.swift:341/354/372` ("0 positions", "0 holdings",
      "0 liabilities") against `InvestmentsView.swift:107`, which redacts the same number.
- [ ] **`if <collection>.isEmpty { EmptyState }` with no privacy branch — 14 sites.** Every *chart* got
      the privacy-first treatment; no *list or table* did. Both platforms' "No activity yet", "No
      recurring transactions", "No investments yet", "No crypto holdings yet". Two are worse than a
      plain empty state: `CashFlowView.swift:443-446` and `MacCashFlowView.swift:923-945` **distinguish**
      "you have no transactions" from "you have transactions, just not these" — and both are probeable
      through the filter controls, which is the walk-the-picker attack this codebase's own comments say
      must not exist.
- [ ] **Optional binding with a string fallback — 8 sites.** `?? settings.localized("Never")` appears
      four times (`InvestmentsView.swift:135`, `CryptoView.swift:128`, and both Mac twins), each inside
      the *same* `MetricCard` whose title already redacts a count.
- [ ] **The onboarding card** (`DashboardView.swift:41`, `MacDashboardView.swift:51`) is gated on
      `isCompletelyEmpty`, so its presence announces "this person has no financial data at all".
- [ ] **The recurring-insertion alert** (`ContentView.swift:204-208`, `MacRootView.swift:285-296`) fires
      only when `insertedCount > 0` and states the count. Notable because the same file already threads
      `showAmounts: !settings.isPrivacyMode` into the notification service — this is the one path that
      forgot.
- [ ] **A boundary call left alone deliberately:** `DashboardView.swift:514`
      `EmptyState(title: "No expenses for this period")` is separable from the ranked list that is out
      of scope, and it sits under an `AnalyticsPeriod` picker — the walk-the-picker probe again.

Fixing all 37 needs roughly **11 redaction decisions** (hide vs tokenise, per shape) and several new
catalog strings. That is a separate change and a separate review, not a continuation of this one.

**Out of scope by decision, confirmed present and untouched:** ranked lists, sort order, the iOS
spending category list, the macOS allocation legend (`MacDashboardView.swift:537-559`), and the Crypto
Top Performer / Biggest Loser cards.

### The instrument that finally worked (2026-08-25)

`testPrivacyModeConcealsWhetherSnapshotsExist` is the first privacy test here that exercises the **code**
rather than the source text. It renders the real `DashboardView` twice under Privacy Mode, varying only
`FinancialData.snapshots`, and requires byte-identical PNGs. Four instruments were measured first, and
three of them would have produced a vacuous test:

| instrument | result |
|---|---|
| `ImageRenderer(content: DashboardView(…))` | **same bytes for every input** — never draws the body |
| `drawHierarchy(afterScreenUpdates:)` offscreen | 6 KB blank; blank == blank, so it always passes |
| `UIAccessibility` tree walk | finds only UIKit segmented controls; SwiftUI publishes no `Text` |
| `UIHostingController` in a key `UIWindow` + `layer.render(in:)` | ~290 KB that moves with the data ✅ |

It carries a control assertion that fails if the renderer ever stops reading `snapshots` — without it,
the main assertion could silently become unfailable. Reach limit: the test bundle is iOS-hosted, so the
**macOS half of every fix in this series rests on review, not on a test.**

### Still open after the existence work (2026-08-25)

Three sites of the same family that the 41-site sweep surfaced but did not close.

- [ ] **A disabled control is an existence tell.** `SettingsView.swift:526` and
      `MacSettingsView.swift:426-429`: `.disabled(isRefreshingPrices || (investments.isEmpty &&
      crypto.isEmpty))` — *Refresh Prices* greys out precisely when the user holds no investments and no
      crypto. Un-disabling it changes function, so this needs a decision rather than a patch (enable it
      and no-op? always enable under Privacy Mode?).
- [ ] **The import-summary sheet prints raw counts** — `DesignSystem.swift:1004` (`statTile`) and `:1054`
      (`footnoteRow`): six category counts plus skipped/generated tallies, ungated. Transient and
      user-initiated, so lower severity than a persistent screen.
- [ ] **Sign-of-value leak via glyph and tint — 8 sites, and the card contradicts itself.**
      `MetricCard` picks `systemImage` and `accent` from the sign of the value while the figure itself
      reads `••••`: `DashboardView.swift:433`, `MacDashboardView.swift:131`, `CashFlowView.swift:164`,
      `MacCashFlowView.swift:251` (Net Savings); `InvestmentsView.swift:112`, `CryptoView.swift:109`,
      `MacInvestmentsView.swift:144`, `MacCryptoView.swift:112` (Profit/Loss). This is stronger than the
      `ValueDelta` tint item recorded earlier: at `CryptoView.swift:109-111` the **same card** redacts its
      `detail` to "Performance hidden" while its icon and accent still announce the sign, and the sibling
      Performance card two lines down is behind `if !settings.isPrivacyMode`. The intent to hide
      performance is already in the code; it is half-applied. A *value* leak, not an existence one.

### What the existence work could not prove

- **Every macOS change in this series rests on review, not on a test.** The bundle hosts
  `WealthCompassMobile`, so 19 macOS-side edits — `MacSettingsView`'s six rows, `MacDashboardView`'s
  liabilities caption / onboarding card / Recent Activity, `MacCashFlowView`'s Showing row and three
  empty-state properties, both Mac Investments/Crypto empty states and `Never` cards, and `MacRootView`'s
  alert — have no automated coverage at all.
- **The list empty-states (`f3fac7c`) do not close the bit, by design.** They stop the card *saying* it is
  empty, but the populated branch still draws rows, because ranked lists are out of scope. Measured, not
  argued: with Privacy Mode on, `CashFlowView` captures **592,013 bytes with no recurring schedule against
  585,887 with one**, before and after the commit alike. Closing it means covering the whole card.
- **A `Text` overload silently dropped locale formatting** (`96d535f`). `Text(privateCount(…))` where the
  helper returns `String` takes `Text`'s **verbatim** overload; `Text("\(count)")` takes the
  `LocalizedStringKey` one and applies grouping separators. The redacted branch looked right, so only the
  *visible* branch regressed — four figures of transactions lost their separator in every locale. If a
  privacy helper feeds a `Text`, return `Text`.

### The lock screen was the worst surface, and one leak remains there (2026-08-25)

`32650c7` fixed the severe one: with Privacy Mode on, the recurring reminder used to render
**"Recurring Expense due — Rent is scheduled."** on a locked phone. `showAmounts` gated only the figure;
`content.title` named the *type* and `content.body` named the *category*, outside the branch. Every other
leak in this audit needed someone holding the unlocked device. This one needed a table.

It is now `showDetails`, gating the whole notification — under Privacy Mode no property of the schedule
is read at all. Two premises in my brief were wrong and the fixer corrected them:
`MacRecurringTransactionNotificationService` is **not** a second class (it is an `enum` at
`MacPlatformServices.swift:65` holding a configured instance of the same shared actor), so this is the
**one place in the entire audit where a test covers macOS**; and there are **six** `sync` call sites, not
the two I named — `SettingsView:692`, `CashFlowView:702`, `MacSettingsView:929` and `MacCashFlowView:1036`
also pass the flag. All six pass it correctly.

- [ ] **Multiplicity still leaks a count on the lock screen.** Every privacy-mode reminder is now the
      same two constants, so N schedules due in the same minute post **N identical banners**. A bystander
      counts them. The obvious fix — key the request identifier on the fire time so they coalesce —
      **breaks the cancellation contract**: `deleteRecurringTransaction`, `completeRecurringTransaction`
      and `finishRecurringTransaction` (`CashFlowView:688,725`, `MacCashFlowView:1022,1061`) call
      `cancel(scheduleID:)` with **no following `sync`**, so a fire-time-keyed request would survive the
      delete and fire for a schedule that no longer exists. Doing it properly means making those four
      paths re-sync. Worth doing — it is the same class, on the most exposed surface in the app.
- [ ] **Arrival time still correlates with the schedule** — a banner on the 1st suggests rent. Inherent
      to having reminders at all; recorded so it is an accepted limitation rather than an oversight.

### Localization facts learned the hard way (2026-08-25)

- [ ] **There is no parent-locale fallback anywhere in the app.** `es-419` failed a coverage check for a
      key that `es` has, because `AppLocalization` loads the `.lproj` directly. Any key present in `es`
      but absent from `es-419` renders **English**, not Spanish. Worth a sweep — the same trap applies to
      `pt-BR`/`pt-PT`, `fr-CA`/`fr-FR`, `zh-Hans`/`zh-Hant`.
- [ ] **`Capital invested` is missing `sv`** (33 of 34). Predates this series.
- [ ] **157 catalog keys have zero localizations.** Not investigated.
- **A claim to stop repeating:** `ar` and `hi` render `1,234` in **Latin** digits here, not Arabic-Indic.
  Two commit messages and several doc comments in this series asserted otherwise. Measured, not assumed.
- **`%lld positions` and friends hold flat `stringUnit`s in all 34 locales.** Only **two** keys in the
  whole catalog use `variations.plural`. I asserted the opposite in a brief and it caused a real
  regression: the fixer swapped three well-translated count captions for fixed phrases that existed in
  only 6 locales, so 28 locales read English under Privacy Mode until `997e378` back-filled them.

### The lock screen, finished (2026-08-25)

`73e3b22` `866b3c7` `835415b` `5265c96` `796c2a1`. Suite 297 → **302**, green.

Two bugs, both worse than the one that started this thread:

- **`sync` cleared only *pending* notifications.** `cancel` and `cancelAll` both called
  `removeDeliveredNotifications`; `sync` did not. So turning Privacy Mode on rewrote the queue and left
  every already-delivered banner — *"Recurring Expense due / Rent: €1.450,00"* — sitting on the lock
  screen unchanged. Enabling Privacy Mode did nothing to what was already there, which is the normal
  case: people turn it on *because* schedules exist.
- **`cancelAll` could never reach a delivered notification at all.** It built its identifier list from
  `pendingNotificationRequests()`, then passed that list to `removeDeliveredNotifications` — but a
  delivered notification is no longer pending, so its identifier was never in the list. `cancelAll` is
  the **erase-everything** path (`SettingsView.swift:626`, `ContentView.swift:50`,
  `MacSettingsView.swift:922`, `MacRootView.swift:39`), so a factory reset left banners standing.

Both now go through one `clearScheduledReminders()` that unions pending **and** delivered identifiers.

> **Corrected 2026-08-25 (“take down the stale banners, not every banner”).** The paragraph that stood here said `sync` clears delivered
> *always* because "it is never called speculatively". **That is false.** Three paths reach `sync` with
> nothing about the delivered banners changed: a silent CloudKit push (`FinanceStore.swift:2004`
> assigns `data = updatedData`, and `RecurringTransaction`'s synthesised `==` covers `updatedAt` and
> `nextDueDate`, so a remote edit — or a bare `sortedForStorage()` reorder — fires
> `.onChange(of: finance.data.recurringTransactions)`); `processDueRecurringTransactions` returning 0
> while still writing schedules back (the dedup advance, catch-up fast-forward and both deactivation
> paths), which bypasses WC-L1's `guard insertedCount > 0` because the array mutation fires
> `.onChange` by itself; and backup import (`SettingsView.swift:665`, `MacSettingsView.swift:826`),
> which the caller list omitted entirely. The cost was that **editing one schedule dismissed every
> other schedule's unread banner**. `sync` now tears down only the delivered banners no live schedule
> still supports; `cancelAll` keeps the unconditional sweep.

Also fixed: banners now coalesce to **one per moment** under Privacy Mode (the previous agent's reason
for skipping this was refuted — `sync` tears down by prefix, so cancellation was never the blocker); the
notification test now asserts on the whole `UNNotificationRequest` rather than a mutable class a later
line could rewrite; and a ninth entity count was tokenised with a lint that pins the call sites.

- [x] **44 product-name translations across 13 locales, in 21 keys — all fixed 2026-08-25.** `zh-Hans`
      11, `hi` 6, `ar` 5, `ms` 5, `zh-Hant` 5, `tr` 4, plus `de/es/fr/it/pl/sk/th`. Eight locales were
      renaming the app in the *notification* strings alone (the brief said two); the same defect was
      spread through the rest of the catalog. **The note that used to stand here — that the standalone
      `Wealth Compass Tracker` key "is the display name, which some locales localize deliberately — do
      not fix that one" — was false.** `CFBundleDisplayName` is hardcoded (`Resources/iOS/Info.plist:7-8`,
      `project.pbxproj:973`/`:999`) and there is no `InfoPlist.xcstrings` in the build tree, so the
      catalog cannot reach the display name at all. That key is in-app UI text (`LockView.swift:33`,
      `MacPlatformServices.swift:97`, `MacRootView.swift:145`): in `ar/de/es/fr/it/zh-Hans` the unlock
      screen was showing a translated name above a home-screen icon that says "Wealth Compass Tracker".
      All 44 now hold the product name, spliced in place and marked `needs_review`, and
      `LocalizationTests.testNoLocaleRenamesTheAppInTheCatalog` sweeps every key whose English source
      names the app rather than one sentence.
- [ ] **Three dead catalog keys**, 35 locales each, no Swift reference (they were fixed along with the
      rest, since a dead key is one somebody wires up later, but they can equally be deleted):
      `%@ is scheduled. Open Wealth Compass Tracker to review it.`,
      `%@: %@. Wealth Compass Tracker records it while the app is active.` and
      `This permanently removes all local Wealth Compass Tracker data from this device.` — the last of
      which was **not** in the "two dead keys" this list previously named. There is also a bare
      `Wealth Compass` key carrying no localizations at all.
- [ ] **Eight bare-`String` counts in `ReportDocumentBuilder.swift`** (`:857`, `:950`, `:1070-1075`) —
      the same defect as the nine tokenised in the views: they print `1234`, not `1,234`/`1.234`, in
      every locale. In the PDF export, which the lint deliberately excludes.

**Nothing about delivery can be tested here.** Measured in the test host: `authorizationStatus.rawValue
== 0`, `center.add` retains **0 of 5** requests, `deliveredNotifications()` is callable but always empty.
So Commit A's coverage is a source lint and says so, and the identifier/trigger and coalescing tests
cover pure functions rather than the real queue. The lock-screen behaviour rests on reading the code.
