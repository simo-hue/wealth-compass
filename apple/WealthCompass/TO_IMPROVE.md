# Wealth Compass — iCloud Sync & Related Improvements

Step-by-step backlog from code review + runtime investigation (macOS debug logs, iOS console). Items are ordered by priority within each section.

---

## Already addressed (verify, then remove debug code)

These fixes are in the codebase but still need a clean verification run before calling sync stable.

1. **Verify partial-failure handling**
   - Rebuild macOS + iOS with sync enabled on both devices.
   - Force sync several times; confirm Settings no longer shows a generic “Sync Error” when CloudKit returns `CKError.partialFailure` (Code 2) with per-record “record already exists” collisions.
   - Expected: status stays “Up to Date” or “Syncing”, engine retries automatically.

2. **Verify post-bootstrap fetch performance**
   - With bootstrap already complete, trigger a remote change from the other device.
   - Confirm macOS debug logs show `localRecordsEncoded: 0` in `handleFetchedRecordZoneChanges` (no full-dataset re-encode per batch).

3. **Verify first-sync collision batching**
   - On a test account, enable sync on two devices that already share the same local data.
   - Confirm iOS no longer freezes for minutes and macOS metadata writes are not one ~900 KB rewrite per conflicting record.

4. **Remove temporary debug instrumentation**
   - Delete all `// #region agent log` blocks and `wcDebugLog(...)` helpers from:
     - `Sources/Shared/Services/CloudKitSyncService.swift`
     - `Sources/Shared/Stores/FinanceStore.swift`
   - Do **not** ship localhost HTTP logging to TestFlight/App Store (it spams the network stack on physical devices).

---

## P0 — Critical bugs & reliability

### 5. Wire CloudKit silent push notifications (iOS + macOS)

**Problem:** `CKSyncEngine` is configured with `subscriptionID`, iOS has `UIBackgroundModes` → `remote-notification`, and entitlements include APS — but there is **no** `registerForRemoteNotifications` and **no** `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (or macOS equivalent). Sync only runs when the app is foregrounded or the user taps “Force Sync”.

**Steps:**
1. In `AppNotificationDelegate` (iOS) and `MacAppDelegate` (macOS), call `UIApplication.shared.registerForRemoteNotifications()` / `NSApplication.shared.registerForRemoteNotifications()` after iCloud sync is enabled.
2. Implement `didRegisterForRemoteNotificationsWithDeviceToken` and log failures.
3. Implement `didReceiveRemoteNotification` and forward the payload to `CKSyncEngine` / trigger `finance.refreshICloudSyncIfNeeded()` or `cloudSyncService.synchronize()`.
4. Test: change data on device A, background device B, confirm B updates without manual force sync (may take up to a few minutes depending on CloudKit push latency).

### 6. Stop treating a single bad CloudKit record as a fatal sync stop

**Problem:** In `handleFetchedRecordZoneChanges`, a record with missing `payload` throws `CloudSyncError.invalidRecord`, which flows to `handleEvent` → `stopAfterFatalError` and tears down the whole engine.

**Steps:**
1. Replace the `throw` on missing payload with: log + skip record + optionally mark metadata tombstone.
2. Add a user-visible counter or “Sync warning” only if many records fail parsing, not for one corrupt record.
3. Add a unit test with a mock fetched record missing `payload`.

### 7. Fix `refreshICloudSyncIfNeeded()` calling `start()` on every activation

**Problem:** `ContentView` / `MacRootView` call `refreshICloudSyncIfNeeded()` whenever the app becomes active. That calls `cloudSyncService.start(...)`, which can re-run startup work (account checks, inventory reconcile, engine setup) even when the engine is already running.

**Steps:**
1. Split API into:
   - `ensureSyncRunning()` — start only if engine is nil.
   - `requestSync()` — call `cloudSyncService.synchronize()` when engine exists.
2. Use `requestSync()` on foreground; reserve `start()` for toggle-on and cold launch.
3. Add debounce (e.g. ignore duplicate foreground sync requests within 30–60 s unless user forced sync).

### 8. Improve first-sync strategy when both devices already have data

**Problem:** Enabling sync on two populated devices marks **every** local record as pending upload. Both sides attempt inserts; CloudKit returns hundreds of `serverRecordChanged` / “record to insert already exists”. Batching mitigates metadata I/O but the root race remains.

**Steps:**
1. On first sync for a device, **fetch remote zone changes before enqueueing local inventory uploads** (fetch-first bootstrap).
2. For each local record whose ID already exists remotely with identical payload hash, clear pending and adopt `systemFields` without uploading.
3. Only enqueue records that are truly local-only or locally newer (use existing `bootstrapDecision` logic, but run it **before** first send).
4. Add integration test: two in-memory stores with identical UUIDs → enable sync on both → expect zero insert collisions.

---

## P1 — Performance (main-thread / disk churn)

### 9. Batch remote mutations instead of one full JSON rewrite per CloudKit batch

**Problem:** `applyRemoteMutations` still decodes/applies all mutations then writes the **entire** `wealth-compass-local-data.json` and updates `@Published data` on the main actor. Logs showed 175 ms for 200 mutations and repeated UI invalidation.

**Steps:**
1. Apply mutations in memory once (already done).
2. Debounce persistence + `@Published` updates: coalesce mutations arriving within ~100–250 ms into one save + one UI publish.
3. Optionally move JSON encode/write off the main actor; publish to UI on main only after write succeeds.
4. Target: one disk write per CloudKit batch, not per internal retry.

### 10. Reduce cost of every local `save()` during sync

**Problem:** `FinanceStore.save()` calls `persistedData.cloudSyncRecords()` and `data.cloudSyncRecords()` on every change — full JSON encode + SHA256 of all records (~300 ms in logs for small edits).

**Steps:**
1. Track dirty record keys incrementally (set of changed/deleted IDs from mutation APIs).
2. Compute `CloudSyncChangeSet` from dirty keys only, not full-dataset diff.
3. Fall back to full diff only on load/import/repair.

### 11. Cap snapshot sync amplification from backfill

**Problem:** `appendSnapshot()` can create up to **60** backfill snapshots in one save; each snapshot is its own CloudKit record. A single market-price refresh or transaction can trigger dozens of sync uploads.

**Steps:**
1. During sync bootstrap or heavy backfill, write snapshots locally but enqueue **one** consolidated snapshot record (or defer backfill uploads until idle).
2. Consider syncing only “canonical” daily snapshots (e.g. one per calendar day) instead of every backfill row.
3. Add metric: snapshot record count vs transaction count in metadata.

### 12. Compact and prune sync metadata file

**Problem:** Logs showed `recordsCount: 317` but `knownHashesCount: 238` — ~80 stale metadata entries. File is ~900 KB with `prettyPrinted: true`, rewritten on many events.

**Steps:**
1. Prune `metadata.records` entries that are tombstones with no pending work and not in `knownLocalHashes`.
2. Stop pretty-printing metadata in production (`prettyPrinted: false`).
3. Consider splitting engine state vs per-record state if file keeps growing.

### 13. Avoid duplicate manual + automatic CKSyncEngine sync

**Problem:** `configuration.automaticallySync = true` **and** `synchronize()` manually calls `fetchChanges` + `sendChanges`. Force sync and foreground refresh may overlap with engine-scheduled sync.

**Steps:**
1. Prefer relying on automatic sync for background/scheduled work.
2. Make `forceICloudSync()` only enqueue pending changes and call `sendChanges` if nothing is in flight, or use CKSyncEngine’s recommended “sync now” API if available for your OS target.
3. Guard with `isSynchronizing` across both manual and delegate-triggered paths (already partial — extend and test).

---

## P2 — Correctness & edge cases

### 14. Fix misleading `forceICloudSync()` errors

**Problem:** Any post-sync error status is rethrown as `CloudSyncError.invalidRecord(message)`, even for network/quota/account errors.

**Steps:**
1. Map `cloudSyncStatus` cases to the correct error types (`accountUnavailable`, network, quota).
2. Surface distinct UI copy in Settings for each case.

### 15. Harden `resolveServerConflict` for non-deleted server records

**Problem:** When server record is not deleted and local pending exists, code requeues without merging remote payload. Usually OK after `systemFields` adoption, but if local pending is stale inventory upload, devices can ping-pong until pending clears.

**Steps:**
1. When server wins and payload hash equals local, clear pending (treat as identical).
2. When server wins and differs, apply remote mutation and supersede pending with a new local revision only if local change is newer (`updatedAt` / revision rules).

### 16. Guard chart inputs beyond currency conversion

**Problem:** macOS reported CoreGraphics NaN warnings. `AppSettings.convert()` is now guarded, but charts can still receive NaN from investment/crypto prices, division edge cases, or empty series during partial sync.

**Steps:**
1. Audit `MacDashboardView` / `DashboardView` chart data mappers; filter `!value.isFinite` before passing to Swift Charts.
2. Clamp net-worth change percentage when baseline is 0 (already partially handled — extend to all chart series).
3. Re-run with `CG_NUMERICS_SHOW_BACKTRACE=1` once to pinpoint any remaining source.

### 17. Remove remaining risky `withAnimation` on store loads

**Problem:** `FinanceStore.load()` still wraps data assignment in `withAnimation`. Same class of “Publishing changes from within view updates” warnings seen during sync.

**Steps:**
1. Use plain assignment on load/error paths (keep animation in views if needed).
2. Search for other `@Published` writes inside persistence/sync callbacks.

### 18. Replace `assertionFailure` on save errors in production

**Problem:** Failed local save calls `assertionFailure` — crashes debug builds and hides recoverable errors from users.

**Steps:**
1. Log via `Logger` + set `iCloudSyncError` / blocking banner.
2. Never assert on I/O failure in release.

---

## P3 — Product / UX gaps

### 19. Settings that do not sync across devices

**Problem:** Only finance **records** sync via CloudKit. Per-device UserDefaults still hold: currency, privacy mode, custom categories, app language, API-related prefs.

**Steps:**
1. Document clearly in Settings UI: “Financial data syncs via iCloud; preferences are per device.”
2. (Optional later) Sync a small `WCSettings` CloudKit record or use NSUbiquitousKeyValueStore for safe prefs (currency, categories, language).

### 20. Better sync status UX during long bootstrap

**Problem:** Users see “Syncing” or errors during large first sync with no progress.

**Steps:**
1. Expose pending upload/download counts from metadata (`pending` mutations count).
2. Show “Initial sync: 142/238 records” during bootstrap.
3. Disable force sync button only while truly busy; show last error with retry action.

### 21. Account / zone reset flow

**Problem:** Zone deletion handler resets bootstrap and re-enqueues all local records — correct but heavy; no user-facing explanation.

**Steps:**
1. Detect `zoneReady == false` + bootstrap reset and show one-time explanation.
2. Offer “Reset iCloud sync data” advanced action that clears metadata file and re-bootstrap cleanly (with strong warning).

---

## P4 — Testing & observability

### 22. Expand CloudKit test coverage

**Current:** `CloudSyncCoreTests` covers record keys, change sets, migration, and stop-during-start. Missing: bootstrap collision, batched conflict handling, partial failure, metadata prune, debounced apply.

**Steps:**
1. Add tests with mock `CKSyncEngine` event payloads for `sentRecordZoneChanges` failure batches.
2. Add test: metadata prune reduces `records.count` toward `knownLocalHashes.count`.
3. Add test: `refreshICloudSyncIfNeeded` does not recreate engine when already running (after API split in item 7).

### 23. Structured sync logging (production-safe)

**Problem:** Debug session used localhost HTTP; production needs `OSLog` categories without PII.

**Steps:**
1. Add signposted intervals: `save`, `applyRemoteMutations`, `metadataPersist`, `synchronize`.
2. Log counts and durations only (record counts, bytes, ms) — never payloads or amounts.
3. Optional: hidden Settings “Export sync diagnostics” for support.

### 24. CI CloudKit schema / deployment check

**Problem:** DOCUMENTATION notes manual CloudKit Dashboard steps; easy to ship with schema mismatch.

**Steps:**
1. Add release checklist script verifying record types and fields exist in production container.
2. Document required record types: `WCTransaction`, `WCRecurringTransaction`, `WCInvestment`, `WCCryptoHolding`, `WCLiability`, `WCNetWorthSnapshot`.

---

## P5 — Nice-to-have architecture

### 25. Move sync metadata off main actor

Long term: `CloudSyncMetadataStore` and JSON persistence for finance data should not block UI. Consider a dedicated serial queue/actor for disk I/O with main-actor-only `@Published` snapshots.

### 26. Incremental local persistence

Instead of rewriting full pretty-printed JSON on every change, append to a journal or use SQLite/GRDB with CloudKit as transport — large reduction in I/O for big datasets.

### 27. Snapshot model redesign

Store rolling net-worth history as chunked monthly aggregates locally; sync fewer, larger snapshot records — reduces CloudKit record count for heavy users.

---

## Suggested execution order (summary)

| Step | Item | Effort | Impact |
|------|------|--------|--------|
| 1 | 4 — Remove debug instrumentation | S | Required before release |
| 2 | 1–3 — Verify recent fixes | S | Confidence |
| 3 | 5 — CloudKit push wiring | M | High — background sync |
| 4 | 7 — Foreground sync API split + debounce | S | High — less churn |
| 5 | 8 — Fetch-first bootstrap | L | High — kills collision storm |
| 6 | 9–10 — Batch remote apply + incremental save diff | L | High — fixes lag |
| 7 | 11–12 — Snapshot + metadata pruning | M | Medium |
| 8 | 6 — Non-fatal corrupt records | S | Medium |
| 9 | 22 — Tests for 5–10 | M | Long-term stability |

---

*Last updated: 2026-06-20 — from sync investigation session (macOS structured logs + iOS console).*
