# Wealth Compass — iCloud Sync & Related Improvements

Step-by-step backlog from code review + runtime investigation (macOS debug logs, iOS console). Items are ordered by priority within each section.

> **Completed items have been pruned** from this backlog to keep it focused on remaining work; their full implementation records live in `DOCUMENTATION.md` + git history (and `CODE_AUDIT.md`, which is 100% done). **Item numbers are stable** — they're referenced in commit messages and docs — so the sequence below has intentional gaps. Removed as done: **#4, #6, #7, #8, #10, #14, #15, #18, #25**.

---

## Manual verification (2-device, in progress)

These fixes are in the codebase but still need a clean verification run on two iCloud devices before calling sync stable.

1. **Verify partial-failure handling**
   - Rebuild macOS + iOS with sync enabled on both devices.
   - Force sync several times; confirm Settings no longer shows a generic "Sync Error" when CloudKit returns `CKError.partialFailure` (Code 2) with per-record "record already exists" collisions.
   - Expected: status stays "Up to Date" or "Syncing", engine retries automatically.

2. **Verify post-bootstrap fetch performance**
   - With bootstrap already complete, trigger a remote change from the other device.
   - Confirm macOS debug logs show `localRecordsEncoded: 0` in `handleFetchedRecordZoneChanges` (no full-dataset re-encode per batch).

3. **Verify first-sync collision batching**
   - On a test account, enable sync on two devices that already share the same local data.
   - Confirm iOS no longer freezes for minutes and macOS metadata writes are not one ~900 KB rewrite per conflicting record. (#15 now also prevents re-uploading identical records and adopts a newer server copy for un-edited records.)

---

## P0 — Critical bugs & reliability

### 5. Wire CloudKit silent push notifications (iOS + macOS)

> ✅ **Done (M31, 2026-07-06).** Re-added `aps-environment` on both targets + iOS `remote-notification`
> background mode; `AppNotificationDelegate` (iOS) and `MacAppDelegate` (macOS) now
> `registerForRemoteNotifications()` once sync is enabled, log the device-token register/failure, and
> forward `didReceiveRemoteNotification` to `FinanceStore.handleRemoteCloudKitPush()` (which starts the
> engine and `synchronize()`s). Push-only (no BGTask) per the agreed ruling. **Manual step remaining:**
> enable Push Notifications on the App ID + add the capability in Xcode (provisioning) — see
> `TO_SIMO_DO.md`; the app won't sign until that's done. On-device 2-device propagation smoke test still
> pending.

**Problem:** `CKSyncEngine` is configured with `subscriptionID`, iOS has `UIBackgroundModes` → `remote-notification`, and entitlements include APS — but there is **no** `registerForRemoteNotifications` and **no** `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (or macOS equivalent). Sync only runs when the app is foregrounded or the user taps "Force Sync".

**Steps:**
1. In `AppNotificationDelegate` (iOS) and `MacAppDelegate` (macOS), call `UIApplication.shared.registerForRemoteNotifications()` / `NSApplication.shared.registerForRemoteNotifications()` after iCloud sync is enabled.
2. Implement `didRegisterForRemoteNotificationsWithDeviceToken` and log failures.
3. Implement `didReceiveRemoteNotification` and forward the payload to `CKSyncEngine` / trigger `finance.ensureICloudSyncRunning()` + `finance.requestICloudSync()` or `cloudSyncService.synchronize()`.
4. Test: change data on device A, background device B, confirm B updates without manual force sync (may take up to a few minutes depending on CloudKit push latency).

---

## P1 — Performance (main-thread / disk churn)

### 9. Batch remote mutations instead of one full JSON rewrite per CloudKit batch

> 🟡 **Partial (M4 landed steps 1 + 3).** `applyRemoteMutations` applies in memory once, updates `@Published data` on the main actor, then routes the JSON encode/write **off** the main actor through `PersistenceCoordinator.applyRemote` (serialized against local saves). **Remaining:** step 2 (debounce/coalesce mutations arriving within ~100–250 ms into one save + one `@Published` publish) and step 4 (one disk write per CloudKit batch, not per apply call). Moving off the whole-file rewrite folds into #26.

**Problem:** `applyRemoteMutations` still decodes/applies all mutations then writes the **entire** `wealth-compass-local-data.json` and updates `@Published data` on the main actor. Logs showed 175 ms for 200 mutations and repeated UI invalidation.

**Steps:**
1. Apply mutations in memory once (already done).
2. Debounce persistence + `@Published` updates: coalesce mutations arriving within ~100–250 ms into one save + one UI publish.
3. Optionally move JSON encode/write off the main actor; publish to UI on main only after write succeeds. *(done — M4)*
4. Target: one disk write per CloudKit batch, not per internal retry.

### 11. Cap snapshot sync amplification from backfill

> ✅ **Done (2026-06-28).** Took render-time carry-forward (a cleaner option than the original steps): `SnapshotEngine.appendingSnapshot` no longer materializes the up-to-60 carry-forward rows, and `AnalyticsEngine.snapshotsForChart.carryingForwardDailyGaps` fills inactive days flat at render time. A 172-day gap now adds 1 snapshot, not 62. Records sync only on real point-in-time changes. (DOCUMENTATION.md 2026-06-28.)

**Problem:** `appendSnapshot()` can create up to **60** backfill snapshots in one save; each snapshot is its own CloudKit record. A single market-price refresh or transaction can trigger dozens of sync uploads.

**Steps:**
1. During sync bootstrap or heavy backfill, write snapshots locally but enqueue **one** consolidated snapshot record (or defer backfill uploads until idle).
2. Consider syncing only "canonical" daily snapshots (e.g. one per calendar day) instead of every backfill row.
3. Add metric: snapshot record count vs transaction count in metadata.

### 12. Compact and prune sync metadata file

> ✅ **Done (2026-06-28).** `CloudKitSyncService.pruningSettledTombstones` drops settled-tombstone `records` entries on every metadata write (step 1); `prettyPrinted: false` (step 2). Step 3 (split engine vs per-record state) not needed yet. (DOCUMENTATION.md 2026-06-28.)

**Problem:** Logs showed `recordsCount: 317` but `knownHashesCount: 238` — ~80 stale metadata entries. File is ~900 KB with `prettyPrinted: true`, rewritten on many events.

**Steps:**
1. Prune `metadata.records` entries that are tombstones with no pending work and not in `knownLocalHashes`.
2. Stop pretty-printing metadata in production (`prettyPrinted: false`).
3. Consider splitting engine state vs per-record state if file keeps growing.

### 13. Avoid duplicate manual + automatic CKSyncEngine sync

> ✅ **Done (2026-06-28).** Added an `engineSyncActivity` counter (tracked from CKSyncEngine will/did fetch/send events) so the opportunistic foreground `requestSync()` stands down when the engine is already syncing automatically — gated by the pure, tested `shouldRunOpportunisticSync(...)`. Force Sync stays unconditional; the counter resets on engine teardown. Steps 1+3 covered; step 2 (Force Sync coalescing) intentionally not done — a user "sync now" should always run. (DOCUMENTATION.md 2026-06-28.)

**Problem:** `configuration.automaticallySync = true` **and** `synchronize()` manually calls `fetchChanges` + `sendChanges`. Force sync and foreground refresh may overlap with engine-scheduled sync.

**Steps:**
1. Prefer relying on automatic sync for background/scheduled work.
2. Make `forceICloudSync()` only enqueue pending changes and call `sendChanges` if nothing is in flight, or use CKSyncEngine's recommended "sync now" API if available for your OS target.
3. Guard with `isSynchronizing` across both manual and delegate-triggered paths (already partial — extend and test). *(Note: #7 added the foreground `requestSync()` debounce, which reduces but doesn't fully remove the manual/automatic overlap.)*

---

## P2 — Correctness & edge cases

### 16. Guard chart inputs beyond currency conversion

> ✅ **Done (2026-06-28).** Audit confirmed chart data is already finite (all `Decimal.doubleValue` + `snapshotsForChart` filter). The real risk was `chartDomain` trapping on a non-finite bound; extracted + hardened it into the tested `AnalyticsEngine.chartYDomain(for:)` (filters to finite, safe default for empty/all-non-finite), and both dashboards now `.filter(\.value.isFinite)` chart points at the boundary. Change-% / allocation-% divisions were already guarded. Step 3 (CG_NUMERICS backtrace) is in TO_SIMO_DO — the residual flood, if any, is geometric (ScreenBackground / chart spring). (DOCUMENTATION.md 2026-06-28.)

**Problem:** macOS reported CoreGraphics NaN warnings. `AppSettings.convert()` is now guarded, but charts can still receive NaN from investment/crypto prices, division edge cases, or empty series during partial sync.

**Steps:**
1. Audit `MacDashboardView` / `DashboardView` chart data mappers; filter `!value.isFinite` before passing to Swift Charts.
2. Clamp net-worth change percentage when baseline is 0 (already partially handled — extend to all chart series).
3. Re-run with `CG_NUMERICS_SHOW_BACKTRACE=1` once to pinpoint any remaining source.

### 17. Remove remaining risky `withAnimation` on store loads

> ✅ **Done (2026-06-28).** `FinanceStore.load()` (success + error paths) now uses plain `@Published` assignment, matching the remote-apply path. Grep confirms no `withAnimation` remains in Stores/Services/Persistence. (DOCUMENTATION.md 2026-06-28.)

**Problem:** `FinanceStore.load()` still wraps data assignment in `withAnimation`. Same class of "Publishing changes from within view updates" warnings seen during sync.

**Steps:**
1. Use plain assignment on load/error paths (keep animation in views if needed).
2. Search for other `@Published` writes inside persistence/sync callbacks.

---

## P3 — Product / UX gaps

### 19. Settings that do not sync across devices

> 🟡 **Partial (2026-06-30 — step 1 done).** Both Settings views now carry a complementary caption under the iCloud Sync toggle: *"Preferences like currency, categories, and language are set per device and don't sync."* — placed right after the existing "financial data syncs…" line (which is left untouched so its 29 catalog translations aren't orphaned). One new string to localize (`TO_SIMO_DO`). **Step 2 (actually syncing a prefs record) remains open and optional.** (DOCUMENTATION.md 2026-06-30.)

**Problem:** Only finance **records** sync via CloudKit. Per-device UserDefaults still hold: currency, privacy mode, custom categories, app language, API-related prefs.

**Steps:**
1. Document clearly in Settings UI: "Financial data syncs via iCloud; preferences are per device." *(done — 2026-06-30)*
2. (Optional later) Sync a small `WCSettings` CloudKit record or use NSUbiquitousKeyValueStore for safe prefs (currency, categories, language).

### 20. Better sync status UX during long bootstrap

**Problem:** Users see "Syncing" or errors during large first sync with no progress.

**Steps:**
1. Expose pending upload/download counts from metadata (`pending` mutations count).
2. Show "Initial sync: 142/238 records" during bootstrap.
3. Disable force sync button only while truly busy; show last error with retry action.

### 21. Account / zone reset flow

**Problem:** Zone deletion handler resets bootstrap and re-enqueues all local records — correct but heavy; no user-facing explanation.

**Steps:**
1. Detect `zoneReady == false` + bootstrap reset and show one-time explanation.
2. Offer "Reset iCloud sync data" advanced action that clears metadata file and re-bootstrap cleanly (with strong warning).

---

## P4 — Testing & observability

### 22. Expand CloudKit test coverage

> 🟢 **Steps 1 + 2 done (2026-06-30).** Extracted the sent-side per-record failure classification out of `handleSentRecordZoneChanges` into the pure `CloudKitSyncService.sentRecordFailureResolution(...)` (the engine flow stays untestable, but the routing now is) and pinned its behaviour with `testSentRecordFailureResolutionRoutesEachFailureKind` + `testIsRetryableCoversTransientErrorsOnly`. The refactor was proven behaviour-preserving in a standalone harness (new classifier ≡ old inline ladder across **300** input combinations, 0 divergences). Step 2: `testPruningConvergesRecordCountTowardKnownHashes` asserts the prune drives `records.count` → `knownLocalHashes.count` (317→238). **Remaining:** still no coverage for the *batched apply* of server-wins / debounced remote apply (those live inside the engine-driven path) and the end-to-end bootstrap-collision flow — both rest on the 2-device verify. (DOCUMENTATION.md 2026-06-30.)

**Current:** `CloudSyncCoreTests` covers record keys, change sets, migration, stop-during-start, the foreground-sync no-op, `bootstrapDecision`, `conflictAction`, the error classifier (`failureCategory`/`syncStatus`), `partialFailureIsBenign`, the prune predicate + count-convergence, the opportunistic-sync gate, the sent-side failure classifier (`sentRecordFailureResolution`/`isRetryable`), and `purgeCloudData`. Missing: bootstrap collision end-to-end, batched server-wins apply, debounced apply.

> **Constraint:** `CKSyncEngine` and its `Event` types have **no public initializer** and need a live CloudKit container, so engine-level flows can't be unit-tested in this harness — only the **pure** decision/transform logic is (as done for `bootstrapDecision` / `conflictAction` / `remoteSnapshot` / `sentRecordFailureResolution`). The engine-level guarantees rest on the 2-device verify pass. Prefer extracting pure helpers when adding coverage.

**Steps:**
1. Add tests with mock `CKSyncEngine` event payloads for `sentRecordZoneChanges` failure batches *(blocked by the constraint above — extract a pure planner instead).* **✅ done (2026-06-30): extracted `sentRecordFailureResolution` and tested the routing directly.**
2. Add test: metadata prune reduces `records.count` toward `knownLocalHashes.count` (after #12). **✅ done (2026-06-30): `testPruningConvergesRecordCountTowardKnownHashes`.**
3. ~~Add test: `refreshICloudSyncIfNeeded` does not recreate engine when already running~~ — partially covered by `testRequestSyncWithoutRunningEngineIsNoOp` (#7).

### 23. Structured sync logging (production-safe)

> ✅ **Done (2026-06-30).** Added `OSSignposter` intervals + `.debug` `Logger` summary lines (one `SyncSignpost` helper) at **6** sites — `save` (`PersistenceCoordinator.save`), `applyRemoteMutations`, `metadataPersist` (`CloudSyncMetadataStore.persist`), `synchronize`, plus per-batch `fetched`/`sent` record counts in the engine handlers. All under a dedicated **`Telemetry`** category on the existing per-layer subsystems (`com.wealthcompass.persistence` / `com.wealthcompass.sync`); counts/bytes/ms/result only, all `.public`, never payloads or amounts. `.debug` = zero production footprint (live-readable via `log stream`, not persisted). Step 3 done too: a visible **Export Sync Diagnostics** row in both Settings → Data sections shares a `.txt` sourced from a capped in-memory `SyncDiagnosticsLog` ring (since `.debug` lines aren't retrievable via `OSLogStore`); the buffer also captures the key `.error` paths, is PII-clean by construction, and is unit-tested. NB: this is *not* a reintroduction of the banned localhost-HTTP debug logging — OSLog was already shipping in 3 files; this is the sanctioned form. (DOCUMENTATION.md 2026-06-30.)

**Problem:** Debug session used localhost HTTP; production needs `OSLog` categories without PII.

**Steps:**
1. Add signposted intervals: `save`, `applyRemoteMutations`, `metadataPersist`, `synchronize`. **✅ done (2026-06-30) — plus per-batch `fetched`/`sent` counts.**
2. Log counts and durations only (record counts, bytes, ms) — never payloads or amounts. **✅ done (2026-06-30).**
3. Optional: hidden Settings "Export sync diagnostics" for support. **✅ done (2026-06-30) — a visible Settings → Data row, not hidden (easier to direct users to during support); sourced from the in-memory `SyncDiagnosticsLog` ring.**

### 24. CI CloudKit schema / deployment check

> ✅ **Done (2026-06-30).** `scripts/check_cloudkit_schema.py` derives the schema from the single source of truth (`CloudSyncRecordType` raw values + the `record["…"]` field keys in `CloudKitSyncService.swift`) and (1) prints a release checklist of the 6 record types + 8 fields to verify in the production container, and (2) acts as a **CI drift gate** — exit 1 if the source adds/removes a record type or field the embedded manifest doesn't know about (forcing a manifest + CloudKit Dashboard update before shipping). `--json` emits a machine-readable manifest. The one thing it can't do from CI without credentials is hit the live container — that stays a manual checklist confirm (logged in `TO_SIMO_DO`). Drift gate verified firing in both directions. (DOCUMENTATION.md 2026-06-30.)

**Problem:** DOCUMENTATION notes manual CloudKit Dashboard steps; easy to ship with schema mismatch.

**Steps:**
1. Add release checklist script verifying record types and fields exist in production container. **✅ done (2026-06-30): `scripts/check_cloudkit_schema.py` (source-derived checklist + drift gate; live-container confirm stays manual).**
2. Document required record types: `WCTransaction`, `WCRecurringTransaction`, `WCInvestment`, `WCCryptoHolding`, `WCLiability`, `WCNetWorthSnapshot`. **✅ done — the script enumerates them (+ the 8 shared fields) and fails if the enum drifts.**

---

## P5 — Nice-to-have architecture

### 26. Incremental local persistence

Instead of rewriting full pretty-printed JSON on every change, append to a journal or use SQLite/GRDB with CloudKit as transport — large reduction in I/O for big datasets. (Absorbs the "move off the whole-file rewrite" remainder of #9/#10.)

### 27. Snapshot model redesign

Store rolling net-worth history as chunked monthly aggregates locally; sync fewer, larger snapshot records — reduces CloudKit record count for heavy users.

---

## Suggested execution order (remaining)

| Item | Effort | Impact | Status |
|------|--------|--------|--------|
| 1–3 — Verify recent fixes on two devices | S | Confidence | ⏳ manual (in progress) |
| 13 — Dedupe manual + automatic sync | S | Less churn | ✅ done (2026-06-28) |
| 16 / 17 — Chart NaN guard + remove `withAnimation` on load | S | Robustness | ✅ done (2026-06-28) |
| 9 (remaining) — debounce remote apply + one write per batch | M | Fixes lag | 🟡 partial |
| 11 / 12 — Snapshot amplification + metadata pruning | M | Medium | ✅ done (2026-06-28) |
| 22 — More sync tests | S | Stability | 🟢 steps 1+2 done (2026-06-30) |
| 23 — OSLog signposts + diagnostics export | M | Observability | ✅ done (2026-06-30) |
| 24 — CI CloudKit schema check | S | Stability | ✅ done (2026-06-30) |
| 5 — CloudKit push wiring (background sync) | M–L | High | ✅ done (M31, 2026-07-06; needs Xcode capability + provisioning) |
| 26 / 27 — Incremental persistence, snapshot model redesign | L | Scale | ☐ open |

Non-code follow-ups live in `TO_SIMO_DO.md` (translate new strings, manual provisioning if not auto-signed, optional proxy retirement, optional Finnhub stock-currency auto-detect) and the **SwiftLint** tooling note in `CODE_AUDIT.md`.

---

*Last updated: 2026-06-23 — pruned completed items (#4, #6, #7, #8, #10, #14, #15, #18, #25; full records in `DOCUMENTATION.md` + git) to keep this backlog focused on remaining work. #14 (forceICloudSync error classification) and #6/#7/#8/#15 landed 2026-06-23; M4 (#10/#18/#25) 2026-06-22. Originally from the 2026-06-20 sync investigation session (macOS structured logs + iOS console).*
