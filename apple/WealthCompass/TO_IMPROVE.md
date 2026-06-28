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

> ⏸️ **Deferred (CODE_AUDIT C4).** The unused `aps-environment` entitlement + `UIBackgroundModes` were removed. Re-implementing real background sync means re-adding the APS entitlement (→ provisioning) plus the push/BGTask handlers below. This is the single biggest functional gap for a "syncs in the background" claim.

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

**Problem:** `configuration.automaticallySync = true` **and** `synchronize()` manually calls `fetchChanges` + `sendChanges`. Force sync and foreground refresh may overlap with engine-scheduled sync.

**Steps:**
1. Prefer relying on automatic sync for background/scheduled work.
2. Make `forceICloudSync()` only enqueue pending changes and call `sendChanges` if nothing is in flight, or use CKSyncEngine's recommended "sync now" API if available for your OS target.
3. Guard with `isSynchronizing` across both manual and delegate-triggered paths (already partial — extend and test). *(Note: #7 added the foreground `requestSync()` debounce, which reduces but doesn't fully remove the manual/automatic overlap.)*

---

## P2 — Correctness & edge cases

### 16. Guard chart inputs beyond currency conversion

**Problem:** macOS reported CoreGraphics NaN warnings. `AppSettings.convert()` is now guarded, but charts can still receive NaN from investment/crypto prices, division edge cases, or empty series during partial sync.

**Steps:**
1. Audit `MacDashboardView` / `DashboardView` chart data mappers; filter `!value.isFinite` before passing to Swift Charts.
2. Clamp net-worth change percentage when baseline is 0 (already partially handled — extend to all chart series).
3. Re-run with `CG_NUMERICS_SHOW_BACKTRACE=1` once to pinpoint any remaining source.

### 17. Remove remaining risky `withAnimation` on store loads

**Problem:** `FinanceStore.load()` still wraps data assignment in `withAnimation`. Same class of "Publishing changes from within view updates" warnings seen during sync.

**Steps:**
1. Use plain assignment on load/error paths (keep animation in views if needed).
2. Search for other `@Published` writes inside persistence/sync callbacks.

---

## P3 — Product / UX gaps

### 19. Settings that do not sync across devices

**Problem:** Only finance **records** sync via CloudKit. Per-device UserDefaults still hold: currency, privacy mode, custom categories, app language, API-related prefs.

**Steps:**
1. Document clearly in Settings UI: "Financial data syncs via iCloud; preferences are per device."
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

**Current:** `CloudSyncCoreTests` covers record keys, change sets, migration, stop-during-start, the foreground-sync no-op, `bootstrapDecision`, and `conflictAction`. Missing: bootstrap collision end-to-end, batched conflict handling, partial failure, metadata prune, debounced apply.

> **Constraint:** `CKSyncEngine` and its `Event` types have **no public initializer** and need a live CloudKit container, so engine-level flows can't be unit-tested in this harness — only the **pure** decision/transform logic is (as done for `bootstrapDecision` / `conflictAction` / `remoteSnapshot`). The engine-level guarantees rest on the 2-device verify pass. Prefer extracting pure helpers when adding coverage.

**Steps:**
1. Add tests with mock `CKSyncEngine` event payloads for `sentRecordZoneChanges` failure batches *(blocked by the constraint above — extract a pure planner instead).*
2. Add test: metadata prune reduces `records.count` toward `knownLocalHashes.count` (after #12).
3. ~~Add test: `refreshICloudSyncIfNeeded` does not recreate engine when already running~~ — partially covered by `testRequestSyncWithoutRunningEngineIsNoOp` (#7).

### 23. Structured sync logging (production-safe)

**Problem:** Debug session used localhost HTTP; production needs `OSLog` categories without PII.

**Steps:**
1. Add signposted intervals: `save`, `applyRemoteMutations`, `metadataPersist`, `synchronize`.
2. Log counts and durations only (record counts, bytes, ms) — never payloads or amounts.
3. Optional: hidden Settings "Export sync diagnostics" for support.

### 24. CI CloudKit schema / deployment check

**Problem:** DOCUMENTATION notes manual CloudKit Dashboard steps; easy to ship with schema mismatch.

**Steps:**
1. Add release checklist script verifying record types and fields exist in production container.
2. Document required record types: `WCTransaction`, `WCRecurringTransaction`, `WCInvestment`, `WCCryptoHolding`, `WCLiability`, `WCNetWorthSnapshot`.

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
| 13 — Dedupe manual + automatic sync | S | Less churn | ☐ open |
| 16 / 17 — Chart NaN guard + remove `withAnimation` on load | S | Robustness | ☐ open |
| 9 (remaining) — debounce remote apply + one write per batch | M | Fixes lag | 🟡 partial |
| 11 / 12 — Snapshot amplification + metadata pruning | M | Medium | ✅ done (2026-06-28) |
| 22 / 23 / 24 — More sync tests, OSLog signposts, CI schema check | M | Stability | ☐ open |
| 5 — CloudKit push wiring (background sync) | M–L | High (needs APS entitlement → provisioning) | ⏸️ deferred |
| 26 / 27 — Incremental persistence, snapshot model redesign | L | Scale | ☐ open |

Non-code follow-ups live in `TO_SIMO_DO.md` (translate new strings, manual provisioning if not auto-signed, optional proxy retirement, optional Finnhub stock-currency auto-detect) and the **SwiftLint** tooling note in `CODE_AUDIT.md`.

---

*Last updated: 2026-06-23 — pruned completed items (#4, #6, #7, #8, #10, #14, #15, #18, #25; full records in `DOCUMENTATION.md` + git) to keep this backlog focused on remaining work. #14 (forceICloudSync error classification) and #6/#7/#8/#15 landed 2026-06-23; M4 (#10/#18/#25) 2026-06-22. Originally from the 2026-06-20 sync investigation session (macOS structured logs + iOS console).*
