# iCloud Sync Plan

The applications currently use local-first storage. CloudKit should be introduced as a synchronization layer, not by placing the complete JSON database in iCloud Drive.

## Record Model

Use the user's private CloudKit database and one record per entity:

| Local entity | CloudKit record type |
| --- | --- |
| `Transaction` | `WCTransaction` |
| `RecurringTransaction` | `WCRecurringTransaction` |
| `Investment` | `WCInvestment` |
| `CryptoHolding` | `WCCryptoHolding` |
| `Liability` | `WCLiability` |
| `NetWorthSnapshot` | `WCNetWorthSnapshot` |

Each record should include the model UUID as `recordName`, `createdAt`, `updatedAt`, and a deletion tombstone where appropriate.

## Sync Behavior

1. Local edits save immediately and enqueue an outbox operation.
2. The sync engine uploads queued changes when iCloud is available.
3. Remote changes are fetched with `CKFetchRecordZoneChangesOperation`.
4. Changes merge into the local database by UUID and `updatedAt`.
5. Deletions use tombstones so offline devices do not restore removed records.
6. The UI observes local data only; CloudKit never becomes a blocking dependency.

Use a custom record zone in the private database and persist its server change token locally. Do not synchronize market-data API keys or biometric settings.

## Required Apple Configuration

Before implementation:

1. Create an iCloud container in the Apple Developer portal, for example `iCloud.com.wealthcompass`.
2. Add both app identifiers to that container.
3. Enable CloudKit and remote notifications for both targets.
4. Regenerate development and distribution provisioning profiles.
5. Add matching iCloud and `aps-environment` entitlements to both targets.
6. Create the CloudKit schema in the development environment, test migrations, then deploy it to production.

## Delivery Phases

1. Add an outbox, tombstones, sync metadata, and deterministic merge tests.
2. Implement CloudKit zone creation, upload, download, retry, and account-state handling.
3. Add sync status and error recovery to iPhone and Mac settings.
4. Test offline edits, concurrent edits, deletes, account switching, quota errors, and first-device bootstrap.
5. Enable production CloudKit only after migration and conflict tests pass.
