import CloudKit
import XCTest
@testable import WealthCompassMobile

final class CloudSyncCoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecordKeyRoundTripsThroughCloudKitRecordName() {
        let key = CloudSyncRecordKey(
            type: .recurringTransaction,
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        XCTAssertEqual(CloudSyncRecordKey(recordName: key.recordName), key)
        XCTAssertNil(CloudSyncRecordKey(recordName: "unsupported:not-a-uuid"))
    }

    func testChangeSetDetectsUpdatesAndDeletes() throws {
        let transactionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let liabilityID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let oldTransaction = makeTransaction(id: transactionID, amount: 10)
        var changedTransaction = oldTransaction
        changedTransaction.amount = 20
        changedTransaction.updatedAt = fixedDate.addingTimeInterval(60)

        let oldData = FinancialData(
            transactions: [oldTransaction],
            liabilities: [
                Liability(
                    id: liabilityID,
                    name: "Loan",
                    currentBalance: 500,
                    currency: .eur,
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ]
        )
        let newData = FinancialData(transactions: [changedTransaction])

        let changes = CloudSyncChangeSet.difference(
            from: try oldData.cloudSyncRecords(),
            to: try newData.cloudSyncRecords(),
            at: fixedDate
        )

        XCTAssertEqual(changes.changed.map(\.key), [
            CloudSyncRecordKey(type: .transaction, id: transactionID)
        ])
        XCTAssertEqual(changes.deleted, [
            CloudSyncRecordKey(type: .liability, id: liabilityID)
        ])
        XCTAssertEqual(changes.changedAt, fixedDate)
    }

    func testRemoteUpsertAndDeleteRoundTrip() throws {
        let transaction = makeTransaction(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            amount: 42
        )
        let source = FinancialData(transactions: [transaction])
        let snapshot = try XCTUnwrap(
            source.cloudSyncRecords()[CloudSyncRecordKey(type: .transaction, id: transaction.id)]
        )
        var destination = FinancialData()

        destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(
                key: snapshot.key,
                payload: snapshot.payload,
                expectedPendingRevision: nil
            )
        ])
        XCTAssertEqual(destination.transactions, [transaction])

        destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(
                key: snapshot.key,
                payload: nil,
                expectedPendingRevision: nil
            )
        ])
        XCTAssertTrue(destination.transactions.isEmpty)
    }

    /// WC-H3: a batch containing an undecodable payload and an id-mismatched record must
    /// skip exactly those two, apply the rest, report only the applied keys, and — the
    /// headline property — NOT throw. The throw is precisely what previously propagated to
    /// `handleEvent`'s catch and disabled the whole engine over one bad record; skipping
    /// keeps the engine running and the good records flowing.
    func testApplyCloudSyncMutationsQuarantinesBadRecordsAndAppliesTheRest() throws {
        let goodA = makeTransaction(id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!, amount: 11)
        let goodB = makeTransaction(id: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!, amount: 22)
        let records = try FinancialData(transactions: [goodA, goodB]).cloudSyncRecords()
        let snapA = try XCTUnwrap(records[CloudSyncRecordKey(type: .transaction, id: goodA.id)])
        let snapB = try XCTUnwrap(records[CloudSyncRecordKey(type: .transaction, id: goodB.id)])

        // A valid key carrying garbage bytes (forward-incompatible / corrupt payload).
        let undecodableKey = CloudSyncRecordKey(type: .transaction, id: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!)
        // goodB's payload delivered under a different record key (id mismatch).
        let mismatchKey = CloudSyncRecordKey(type: .transaction, id: UUID(uuidString: "80000000-0000-0000-0000-000000000008")!)

        var destination = FinancialData()
        let outcome = destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(key: snapA.key, payload: snapA.payload, expectedPendingRevision: nil),
            CloudSyncRemoteMutation(key: undecodableKey, payload: Data("not valid json".utf8), expectedPendingRevision: nil),
            CloudSyncRemoteMutation(key: mismatchKey, payload: snapB.payload, expectedPendingRevision: nil),
            CloudSyncRemoteMutation(key: snapB.key, payload: snapB.payload, expectedPendingRevision: nil)
        ])

        // The two valid records applied; the two bad ones were skipped (not thrown).
        XCTAssertEqual(Set(destination.transactions.map(\.id)), [goodA.id, goodB.id])
        XCTAssertEqual(outcome.appliedKeys, [snapA.key, snapB.key])
        XCTAssertEqual(Set(outcome.skipped.map(\.key)), [undecodableKey, mismatchKey])
    }

    /// WC-H3 corollary: when *every* record in the batch is undecodable, nothing applies and
    /// the applied-key set is empty (so the caller advances no metadata) — still no throw.
    func testApplyCloudSyncMutationsWithAllBadRecordsAppliesNothing() {
        let key = CloudSyncRecordKey(type: .investment, id: UUID(uuidString: "90000000-0000-0000-0000-000000000009")!)
        var destination = FinancialData()
        let outcome = destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(key: key, payload: Data("garbage".utf8), expectedPendingRevision: nil)
        ])

        XCTAssertTrue(destination.investments.isEmpty)
        XCTAssertTrue(outcome.appliedKeys.isEmpty)
        XCTAssertEqual(outcome.skipped.map(\.key), [key])
    }

    func testLegacyJSONMigrationAddsUpdatedAt() throws {
        let transaction = makeTransaction(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            amount: 75
        )
        let encoded = try FinanceJSONCoding.encode(FinancialData(transactions: [transaction]))
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var transactions = try XCTUnwrap(root["transactions"] as? [[String: Any]])
        transactions[0].removeValue(forKey: "updatedAt")
        root["transactions"] = transactions
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        let decoded = try FinanceJSONCoding.decodeFinancialData(from: legacyData)

        XCTAssertTrue(decoded.wasMigrated)
        XCTAssertEqual(decoded.data.transactions.first?.updatedAt, fixedDate)
    }

    // deep-audit H10: an explicit JSON `null` (not just an absent key) on a non-optional Date field
    // used to fail the whole-file decode; the migration must heal it like an absent value.
    func testLegacyJSONMigrationHealsExplicitNullUpdatedAt() throws {
        let transaction = makeTransaction(
            id: UUID(uuidString: "41000000-0000-0000-0000-000000000041")!,
            amount: 75
        )
        let encoded = try FinanceJSONCoding.encode(FinancialData(transactions: [transaction]))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var transactions = try XCTUnwrap(root["transactions"] as? [[String: Any]])
        transactions[0]["updatedAt"] = NSNull()  // explicit null, not a missing key
        root["transactions"] = transactions
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        let decoded = try FinanceJSONCoding.decodeFinancialData(from: legacyData)

        XCTAssertTrue(decoded.wasMigrated)
        XCTAssertEqual(decoded.data.transactions.count, 1, "the null-updatedAt row must not fail the whole decode")
        XCTAssertEqual(decoded.data.transactions.first?.updatedAt, fixedDate)
    }

    // deep-audit H08: one undecodable record (an unknown enum value here) must not zero the whole
    // dataset — it is skipped, the rest load, and its key is reported so the sync layer can preserve it.
    func testLossyDecodeSkipsUndecodableRecordAndReportsKey() throws {
        let goodID = UUID(uuidString: "42000000-0000-0000-0000-000000000042")!
        let badID = UUID(uuidString: "43000000-0000-0000-0000-000000000043")!
        let encoded = try FinanceJSONCoding.encode(FinancialData(transactions: [
            makeTransaction(id: goodID, amount: 10),
            makeTransaction(id: badID, amount: 20)
        ]))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var transactions = try XCTUnwrap(root["transactions"] as? [[String: Any]])
        let badIndex = try XCTUnwrap(transactions.firstIndex {
            ($0["id"] as? String)?.lowercased() == badID.uuidString.lowercased()
        })
        transactions[badIndex]["type"] = "teleportation"  // unknown TransactionType → element decode fails
        root["transactions"] = transactions
        let corruptData = try JSONSerialization.data(withJSONObject: root)

        let decoded = try FinanceJSONCoding.decodeFinancialData(from: corruptData)

        XCTAssertEqual(decoded.data.transactions.map(\.id), [goodID], "the good record still loads")
        XCTAssertEqual(
            decoded.skippedRecordKeys,
            [CloudSyncRecordKey(type: .transaction, id: badID)],
            "the undecodable record's key is reported for sync-preservation"
        )
    }

    @MainActor
    func testStopDuringPendingCloudSyncStartPreventsLateEngineCreation() async {
        let accountStatusGate = AccountStatusGate()
        let engineFactoryCalled = ThreadSafeFlag()
        var statuses: [CloudSyncStatus] = []
        let metadataStore = CloudSyncMetadataStore(
            directoryName: "WealthCompassTests-\(UUID().uuidString)"
        )
        let service = CloudKitSyncService(
            metadataStore: metadataStore,
            snapshotProvider: { [:] },
            remoteMutationHandler: { _ in [] },
            statusHandler: { status in
                statuses.append(status)
            },
            disableHandler: {},
            accountStatusProvider: {
                await accountStatusGate.waitForStatus()
            },
            userRecordIDProvider: {
                XCTFail("A stopped sync start should not continue to the user record lookup.")
                return CKRecord.ID(recordName: "test-user")
            },
            engineFactory: { _ in
                engineFactoryCalled.setTrue()
                throw TestCloudSyncLifecycleError.engineShouldNotStart
            }
        )

        let startTask = Task {
            await service.start(allowAccountReplacement: true)
        }
        await accountStatusGate.waitUntilBlocked()

        await service.stop()
        await accountStatusGate.resume(returning: .available)
        await startTask.value

        XCTAssertFalse(engineFactoryCalled.isSet)
        XCTAssertEqual(statuses.last, .disabled)
        XCTAssertFalse(statuses.contains { status in
            if case .error = status { return true }
            return false
        })
    }

    /// #7: the foreground `requestSync()` path must be sync-only. With no engine
    /// running it has to be a complete no-op — it must never run the startup work
    /// (`start()`), so it must not create the engine, check the iCloud account, look
    /// up the user record, reconcile inventory, or emit any status.
    @MainActor
    func testRequestSyncWithoutRunningEngineIsNoOp() async {
        let engineFactoryCalled = ThreadSafeFlag()
        var statuses: [CloudSyncStatus] = []
        let metadataStore = CloudSyncMetadataStore(
            directoryName: "WealthCompassTests-\(UUID().uuidString)"
        )
        let service = CloudKitSyncService(
            metadataStore: metadataStore,
            snapshotProvider: {
                XCTFail("requestSync must not reconcile local inventory without a running engine.")
                return [:]
            },
            remoteMutationHandler: { _ in [] },
            statusHandler: { statuses.append($0) },
            disableHandler: {},
            accountStatusProvider: {
                XCTFail("requestSync must not check the iCloud account; only start() may.")
                return .available
            },
            userRecordIDProvider: {
                XCTFail("requestSync must not look up the user record.")
                return CKRecord.ID(recordName: "test-user")
            },
            engineFactory: { _ in
                engineFactoryCalled.setTrue()
                throw TestCloudSyncLifecycleError.engineShouldNotStart
            }
        )

        await service.requestSync()

        XCTAssertFalse(engineFactoryCalled.isSet, "requestSync must not start the sync engine.")
        XCTAssertTrue(statuses.isEmpty, "requestSync must not emit a sync status when nothing is running.")
    }

    /// #6: a fetched CloudKit record with no `payload` must be skippable — the helper
    /// returns `nil` so `handleFetchedRecordZoneChanges` can skip the record instead of
    /// throwing (a throw would tear down the whole engine over one bad record). A
    /// well-formed record maps to a snapshot with the payload and timestamps preserved.
    func testRemoteSnapshotSkipsPayloadlessRecordAndMapsValidOne() throws {
        let key = CloudSyncRecordKey(type: .transaction, id: UUID())
        let record = CKRecord(
            recordType: CloudSyncRecordType.transaction.rawValue,
            recordID: CKRecord.ID(recordName: "any-record-name")
        )

        // No payload field → skip (nil), no throw.
        XCTAssertNil(CloudKitSyncService.remoteSnapshot(from: record, key: key))

        // Payload + timestamps present → a correctly-mapped snapshot.
        let payload = Data("payload".utf8)
        let created = Date(timeIntervalSince1970: 1_000)
        let updated = Date(timeIntervalSince1970: 2_000)
        record["payload"] = payload as NSData
        record["createdAt"] = created as NSDate
        record["updatedAt"] = updated as NSDate

        let snapshot = try XCTUnwrap(CloudKitSyncService.remoteSnapshot(from: record, key: key))
        XCTAssertEqual(snapshot.key, key)
        XCTAssertEqual(snapshot.payload, payload)
        XCTAssertEqual(snapshot.createdAt, created)
        XCTAssertEqual(snapshot.updatedAt, updated)
    }

    /// WC-H4: building a send batch must encode the per-entity snapshot ONCE, not once per
    /// record. `makeRecords` fetches the snapshot a single time and indexes it for every
    /// record in the batch, so a counting provider is invoked exactly once regardless of how
    /// many records the batch contains (previously the provider — a full-dataset JSON-encode
    /// + SHA-256 on the main actor — ran once per record).
    @MainActor
    func testMakeRecordsEncodesSnapshotOncePerBatch() async throws {
        let metadataStore = CloudSyncMetadataStore(
            directoryName: "WealthCompassTests-\(UUID().uuidString)"
        )

        // Seed three pending local saves so the batch contains multiple records.
        let txA = makeTransaction(id: UUID(uuidString: "11111111-0000-0000-0000-000000000001")!, amount: 5)
        let txB = makeTransaction(id: UUID(uuidString: "22222222-0000-0000-0000-000000000002")!, amount: 6)
        let txC = makeTransaction(id: UUID(uuidString: "33333333-0000-0000-0000-000000000003")!, amount: 7)
        let records = try FinancialData(transactions: [txA, txB, txC]).cloudSyncRecords()
        try metadataStore.recordLocalChanges(
            CloudSyncChangeSet(changed: Array(records.values), deleted: [], changedAt: fixedDate),
            currentRecords: records
        )

        let providerCalls = ThreadSafeCounter()
        let service = CloudKitSyncService(
            metadataStore: metadataStore,
            snapshotProvider: {
                providerCalls.increment()
                return records
            },
            remoteMutationHandler: { _ in [] },
            statusHandler: { _ in },
            disableHandler: {}
        )

        let zoneID = CKRecordZone.ID(zoneName: "WealthCompassZone", ownerName: CKCurrentUserDefaultName)
        let recordIDs = records.keys.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
        XCTAssertEqual(recordIDs.count, 3)

        let built = await service.makeRecords(for: recordIDs)

        XCTAssertEqual(providerCalls.value, 1, "The snapshot must be encoded once per batch, not once per record.")
        XCTAssertEqual(built.count, recordIDs.count, "Every pending record should be built from the single snapshot.")
    }

    // MARK: - Local-inventory drift guard (token-ahead-of-data self-heal)
    //
    // `reconcileLocalInventory` runs at every sync start. A record still tracked in
    // `knownLocalHashes` but missing from the local snapshot means the local finance DB changed
    // out of band (lost / reset / rolled back / corrupted) while this sync-metadata file survived —
    // the persisted change token is now ahead of the data it claims to have delivered. This MUST
    // re-fetch, never delete: a server tombstone would propagate one device's local loss to every
    // device. A genuine delete can't reach this path — `recordLocalChanges` prunes its hash at
    // delete time — which the second test pins down.

    /// Drift (a known-synced record vanished from local data with no recorded delete) discards the
    /// change token and re-arms bootstrap so the next sync re-pulls, and queues NO server delete for
    /// the missing record.
    func testReconcileLocalInventoryReFetchesOnDriftInsteadOfDeleting() throws {
        let store = CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        let txID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
        let key = CloudSyncRecordKey(type: .transaction, id: txID)
        let records = try FinancialData(transactions: [makeTransaction(id: txID, amount: 42)]).cloudSyncRecords()

        // The record is synced and tracked locally (present in knownLocalHashes).
        try store.recordLocalChanges(
            CloudSyncChangeSet(changed: Array(records.values), deleted: [], changedAt: fixedDate),
            currentRecords: records
        )
        XCTAssertNotNil(store.pendingRevision(for: key))

        // The local finance DB vanished out of band while THIS metadata file survived.
        let result = try store.reconcileLocalInventory([:])

        XCTAssertTrue(result.didDiscardToken, "Drift must discard the change token to force a full re-fetch.")
        XCTAssertEqual(result.driftedRecordKeys, [key])
        XCTAssertNil(
            store.pendingRevision(for: key),
            "Drift must NOT enqueue a server delete (tombstone) for the missing record — that would wipe every device."
        )
    }

    /// A properly recorded delete is NOT misclassified as drift: `recordLocalChanges` prunes its
    /// hash at delete time, so the next inventory reconcile leaves the token intact and keeps the
    /// pending tombstone queued (the delete still propagates to other devices).
    func testReconcileLocalInventoryKeepsRecordedDeleteAndDoesNotTreatItAsDrift() throws {
        let store = CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        let txAID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let txBID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
        let keyB = CloudSyncRecordKey(type: .transaction, id: txBID)
        let both = try FinancialData(
            transactions: [makeTransaction(id: txAID, amount: 1), makeTransaction(id: txBID, amount: 2)]
        ).cloudSyncRecords()
        let onlyA = try FinancialData(transactions: [makeTransaction(id: txAID, amount: 1)]).cloudSyncRecords()

        try store.recordLocalChanges(
            CloudSyncChangeSet(changed: Array(both.values), deleted: [], changedAt: fixedDate),
            currentRecords: both
        )
        // User deletes B: recorded through the normal delete path, which prunes B's hash.
        try store.recordLocalChanges(
            CloudSyncChangeSet(changed: [], deleted: [keyB], changedAt: fixedDate),
            currentRecords: onlyA
        )

        let result = try store.reconcileLocalInventory(onlyA)

        XCTAssertFalse(result.didDiscardToken, "A recorded delete must not trip the drift self-heal.")
        XCTAssertTrue(result.driftedRecordKeys.isEmpty)
        XCTAssertNotNil(
            store.pendingRevision(for: keyB),
            "The recorded delete must stay queued so it still propagates to other devices."
        )
    }

    // MARK: - #8b: surviving a failed remote apply

    /// **The upgrade guard.** An existing user's metadata file has no `needsFullRefetch` key, and it
    /// must still decode.
    ///
    /// `FinanceJSONCoding.makeDecoder()` is a plain `JSONDecoder`, and Swift's synthesized
    /// `Decodable` does NOT fall back to a property's default for a missing key — it throws
    /// `keyNotFound` (pinned below, because that is the language behaviour the design rests on).
    /// `readMetadata` classifies a decode failure as `.corrupt`, whose response is a blank slate:
    /// no change token, no bootstrap flag, no per-record state. So a *non-optional* new property
    /// here would have handed every existing user a full zone re-bootstrap on upgrade. The field is
    /// `Bool?` precisely so this file decodes, through `decodeIfPresent`, into `nil`.
    func testExistingMetadataWithoutTheNewKeyStillDecodes() throws {
        // First, the mechanism the field's Optionality is defending against.
        struct WithNonOptionalAddition: Codable { var existing = 0; var added = false }
        struct WithOptionalAddition: Codable { var existing = 0; var added: Bool? }
        let legacyRecord = Data(#"{"existing":7}"#.utf8)
        XCTAssertThrowsError(
            try FinanceJSONCoding.decode(WithNonOptionalAddition.self, from: legacyRecord),
            "A non-optional addition must fail on a file that predates it — the whole reason for Bool?."
        ) { error in
            guard case DecodingError.keyNotFound = error else {
                return XCTFail("Expected keyNotFound, got \(error)")
            }
        }
        XCTAssertEqual(try FinanceJSONCoding.decode(WithOptionalAddition.self, from: legacyRecord).existing, 7)

        // And now the real file: every field this build declares except the new one.
        let directoryName = "WealthCompassTests-\(UUID().uuidString)"
        let key = CloudSyncRecordKey(
            type: .transaction,
            id: UUID(uuidString: "44444444-0000-0000-0000-000000000004")!
        )
        try writeSyncMetadata(
            """
            {"schemaVersion":1,"accountRecordName":"_userrecordname","bootstrapCompleted":true,
             "zoneReady":true,"records":{"\(key.storageKey)":{"isTombstone":false}},
             "knownLocalHashes":{"\(key.storageKey)":"0f0f0f0f"}}
            """,
            directoryName: directoryName
        )

        let store = CloudSyncMetadataStore(directoryName: directoryName)
        XCTAssertFalse(store.needsFullRefetch, "An absent key must read as 'no re-fetch requested'.")
        XCTAssertTrue(
            store.isBootstrapCompleted,
            "The file was treated as corrupt — a blank slate, i.e. a full re-bootstrap for every existing user."
        )
        // The strongest evidence the file was really read: its `knownLocalHashes` still describe a
        // record, so reconciling against empty local data reports drift for exactly that record. A
        // blank slate would report none.
        let reconciliation = try store.reconcileLocalInventory([:])
        XCTAssertEqual(reconciliation.driftedRecordKeys, [key], "The persisted inventory did not survive the decode.")
    }

    /// The re-fetch request has to outlive the process: the batch is lost the moment CKSyncEngine
    /// advances its token, and the only place that can act on it is the next `start()`.
    func testFullRefetchRequestSurvivesRelaunch() throws {
        let directoryName = "WealthCompassTests-\(UUID().uuidString)"
        let store = CloudSyncMetadataStore(directoryName: directoryName)
        XCTAssertFalse(store.needsFullRefetch)

        try store.requestFullRefetch()
        XCTAssertTrue(store.needsFullRefetch)

        // A second store over the same file is what the next launch sees.
        XCTAssertTrue(
            CloudSyncMetadataStore(directoryName: directoryName).needsFullRefetch,
            "The request must be persisted — clearing `engineState` in memory does not work, the engine re-persists the advanced token."
        )
    }

    // MARK: - #3a: a collapsed-away record must not be reported as applied

    /// `applyRemoteMutations` applies the batch and *then* runs `sortedForStorage()`, whose same-day
    /// snapshot collapse drops the loser. Reporting that key as applied let the service write its
    /// hash into `knownLocalHashes` with no record behind it — a hash with nothing under it is the
    /// drift signature, so every launch discarded the change token and re-fetched the whole zone.
    func testCollapsedAwaySnapshotIsExcludedFromTheAppliedKeys() throws {
        // Identical `date`, so the two rows share a calendar day in every time zone.
        let day = fixedDate
        let loser = makeSnapshot(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000001")!,
            date: day,
            netWorth: 100,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let winner = makeSnapshot(
            id: UUID(uuidString: "88888888-0000-0000-0000-000000000002")!,
            date: day,
            netWorth: 200,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let loserKey = CloudSyncRecordKey(type: .snapshot, id: loser.id)
        let winnerKey = CloudSyncRecordKey(type: .snapshot, id: winner.id)

        let stored = FinancialData(snapshots: [loser, winner]).sortedForStorage()
        XCTAssertEqual(stored.snapshots.count, 1, "Two same-day rows must collapse to one.")
        XCTAssertEqual(stored.snapshots.first?.id, winner.id)
        XCTAssertTrue(winner.supersedesForCollapse(loser), "The survivor must be the one the total order picks.")

        // Both keys were applied by `applyCloudSyncMutations`; only one survived to be persisted.
        let applied: Set<CloudSyncRecordKey> = [loserKey, winnerKey]
        let reported = applied.intersection(stored.cloudSyncRecordKeys())
        XCTAssertEqual(reported, [winnerKey], "Only the record that reached the snapshot may be reported as applied.")
    }

    /// `cloudSyncRecordKeys()` exists to answer "what survived" without a full-dataset JSON encode
    /// on the main actor, so it walks the six collections a second time. This pins the two walks
    /// together — a seventh syncable collection added to one and not the other would silently make
    /// every record of that type read as collapsed-away.
    func testRecordKeysAgreeWithTheEncodedRecords() throws {
        let data = FinancialData(
            transactions: [makeTransaction(id: UUID(uuidString: "10000000-0000-0000-0000-0000000000A1")!, amount: 1)],
            recurringTransactions: [
                RecurringTransaction(
                    id: UUID(uuidString: "20000000-0000-0000-0000-0000000000A2")!,
                    type: .expense, category: "Housing", amount: 1200, description: "Rent",
                    startDate: fixedDate, frequency: .monthly, nextDueDate: fixedDate, endDate: nil,
                    notificationsEnabled: false, isActive: true, completedAt: nil,
                    createdAt: fixedDate, updatedAt: fixedDate
                )
            ],
            investments: [
                Investment(
                    id: UUID(uuidString: "30000000-0000-0000-0000-0000000000A3")!,
                    type: .stock, symbol: "AAPL", name: "Apple", quantity: 1, costBasis: 100,
                    currentValue: 120, currentPrice: 120, currency: .usd, geography: "US",
                    sector: "Tech", isin: "", fees: 0, updatedAt: fixedDate, createdAt: fixedDate
                )
            ],
            crypto: [
                CryptoHolding(
                    id: UUID(uuidString: "40000000-0000-0000-0000-0000000000A4")!,
                    symbol: "BTC", name: "Bitcoin", quantity: 1, avgBuyPrice: 100, currentPrice: 120,
                    currency: .usd, fees: 0, coinId: "bitcoin", updatedAt: fixedDate, createdAt: fixedDate
                )
            ],
            liabilities: [
                Liability(
                    id: UUID(uuidString: "50000000-0000-0000-0000-0000000000A5")!,
                    name: "Loan", currentBalance: 10, currency: .eur,
                    createdAt: fixedDate, updatedAt: fixedDate
                )
            ],
            snapshots: [
                makeSnapshot(
                    id: UUID(uuidString: "60000000-0000-0000-0000-0000000000A6")!,
                    date: fixedDate, netWorth: 1, updatedAt: fixedDate
                )
            ]
        )
        XCTAssertEqual(data.cloudSyncRecordKeys(), Set(try data.cloudSyncRecords().keys))
        XCTAssertEqual(data.cloudSyncRecordKeys().count, 6, "One key per syncable collection.")
    }

    private func makeSnapshot(id: UUID, date: Date, netWorth: Decimal, updatedAt: Date) -> NetWorthSnapshot {
        NetWorthSnapshot(
            id: id,
            date: date,
            totalAssets: netWorth,
            totalLiabilities: 0,
            netWorth: netWorth,
            liquidity: netWorth,
            investments: 0,
            crypto: 0,
            currency: .eur,
            createdAt: fixedDate,
            updatedAt: updatedAt
        )
    }

    /// Writes a sync-metadata file where `CloudSyncMetadataStore(directoryName:)` will look for it.
    private func writeSyncMetadata(_ json: String, directoryName: String) throws {
        let directory = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ).appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("wealth-compass-cloud-sync.json"))
    }

    // MARK: - #8 fetch-first bootstrap: per-record merge decision
    //
    // `bootstrapDecision` is the collision-avoidance heart of the first-sync merge: the
    // engine doesn't enqueue local inventory for upload until after the first fetch, and
    // for each fetched record this decides local-wins / remote-wins / identical. The
    // `.identical` outcome drops the local pending upload, which is what stops a second
    // already-populated device from re-inserting records that already exist remotely.

    private func bootstrapSnapshot(payload: String, updatedAt: Date, id: UUID = UUID()) -> CloudSyncRecordSnapshot {
        CloudSyncRecordSnapshot(
            key: CloudSyncRecordKey(type: .transaction, id: id),
            payload: Data(payload.utf8),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt
        )
    }

    private func inventoryPending() -> CloudSyncPendingMutation {
        .save(modifiedAt: Date(), revision: UUID(), origin: .inventory, allowsResurrection: false)
    }

    private func localChangePending() -> CloudSyncPendingMutation {
        .save(modifiedAt: Date(), revision: UUID(), origin: .localChange, allowsResurrection: false)
    }

    private func deletePending() -> CloudSyncPendingMutation {
        .delete(deletedAt: Date(), revision: UUID())
    }

    /// No local snapshot → adopt remote (there's nothing local to upload).
    func testBootstrapDecisionMissingLocalAdoptsRemote() {
        let remote = bootstrapSnapshot(payload: "remote", updatedAt: Date())
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: nil, local: nil, remote: remote), .remote)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: nil, remote: remote), .remote)
    }

    /// Identical payloads → `.identical`, so the local pending upload is dropped. This is
    /// the core zero-collision guarantee, and it short-circuits regardless of pending
    /// kind or timestamps.
    func testBootstrapDecisionIdenticalPayloadDropsUpload() {
        let local = bootstrapSnapshot(payload: "same", updatedAt: Date(timeIntervalSince1970: 1_000))
        let remote = bootstrapSnapshot(payload: "same", updatedAt: Date(timeIntervalSince1970: 8_000))
        XCTAssertEqual(local.payloadHash, remote.payloadHash)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: local, remote: remote), .identical)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: localChangePending(), local: local, remote: remote), .identical)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: nil, local: local, remote: remote), .identical)
    }

    /// A genuine local edit or a local delete wins over a differing remote, even if the
    /// remote is newer.
    func testBootstrapDecisionLocalChangeAndDeleteWinOverRemote() {
        let local = bootstrapSnapshot(payload: "local", updatedAt: Date(timeIntervalSince1970: 1_000))
        let remote = bootstrapSnapshot(payload: "remote", updatedAt: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: localChangePending(), local: local, remote: remote), .local)
        // `local:` is nil here on purpose — see `testPendingDeleteWithNoLocalSnapshotStillWins`.
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: deletePending(), local: nil, remote: remote), .local)
    }

    /// A pending delete must win even though it carries no local snapshot.
    ///
    /// A pending `.delete` *always* implies `local == nil` — removing the record from local data is
    /// what created the delete — so the `guard let local else { return .remote }` above the switch
    /// made the `.delete` arm unreachable in production, and every delete-vs-edit collision
    /// resolved to `.applyServer`. The assertion in the test above used to pass a non-nil `local`
    /// alongside a delete-pending, a combination that cannot occur, so it was green and proved
    /// nothing.
    ///
    /// Device A edits transaction R and uploads. Device B deletes R and sends before it fetches, so
    /// CloudKit rejects with `.serverRecordChanged` and hands back A's live record. B then adopted
    /// it — R reappeared on both devices and B's pending delete was cleared, with no error shown.
    func testPendingDeleteWithNoLocalSnapshotStillWins() {
        let remote = bootstrapSnapshot(payload: "remote", updatedAt: Date(timeIntervalSince1970: 9_000))

        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: deletePending(), local: nil, remote: remote),
            .local,
            "A deliberate local delete must not lose to the server copy it is deleting."
        )
        XCTAssertEqual(
            CloudKitSyncService.conflictAction(pending: deletePending(), local: nil, server: remote),
            .requeueLocal,
            "A delete-vs-edit collision must re-send the delete, not adopt the server record."
        )
    }

    /// A pending delete that transiently coexists with an *identical* local copy still short-circuits.
    ///
    /// `processSave` freezes the snapshot on the main actor and then awaits the coordinator, which
    /// writes the pending delete off-main — so a record re-created with the same id in that window
    /// leaves `data` holding it while the metadata still says `.delete`, and `snapshotProvider`
    /// reads `data` live. Resolving that to `.local` would upload a tombstone for a record that is
    /// present and byte-identical to the server's, deleting it on every other device before the
    /// next save diffed it back in.
    func testPendingDeleteWithAnIdenticalLocalCopyIsIdentical() {
        let payload = "same"
        let local = bootstrapSnapshot(payload: payload, updatedAt: Date(timeIntervalSince1970: 1_000))
        let remote = bootstrapSnapshot(payload: payload, updatedAt: Date(timeIntervalSince1970: 9_000))

        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: deletePending(), local: local, remote: remote),
            .identical,
            "An identical local copy must short-circuit before the delete arm."
        )
        XCTAssertEqual(
            CloudKitSyncService.conflictAction(pending: deletePending(), local: local, server: remote),
            .adoptServerIdentical,
            "The redundant upload must be dropped, not turned into a tombstone."
        )
    }

    /// With only inventory-origin pending (or none), the more recently updated side wins.
    func testBootstrapDecisionInventoryAndNilResolveByRecency() {
        let older = bootstrapSnapshot(payload: "old", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = bootstrapSnapshot(payload: "new", updatedAt: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: newer, remote: older), .local)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: nil, local: newer, remote: older), .local)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: older, remote: newer), .remote)
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: nil, local: older, remote: newer), .remote)
    }

    /// Equal timestamps fall back to a deterministic payload-hash tie-break, so two
    /// devices independently pick the *same* winner (no ping-pong). The chosen winner is
    /// the same record whichever side it's presented on.
    func testBootstrapDecisionEqualTimestampsTieBreakDeterministically() {
        let when = Date(timeIntervalSince1970: 5_000)
        let local = bootstrapSnapshot(payload: "alpha", updatedAt: when)
        let remote = bootstrapSnapshot(payload: "omega", updatedAt: when)
        XCTAssertNotEqual(local.payloadHash, remote.payloadHash)

        let expected: CloudKitSyncService.BootstrapDecision = local.payloadHash > remote.payloadHash ? .local : .remote
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: local, remote: remote), expected)

        let expectedSwapped: CloudKitSyncService.BootstrapDecision = remote.payloadHash > local.payloadHash ? .local : .remote
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: remote, remote: local), expectedSwapped)
    }

    /// Convergence — the *property*, asserted directly rather than by re-deriving the hash formula.
    /// For a genuine timestamp tie between two independently-edited versions of one record, BOTH
    /// devices must end up holding the SAME payload, or they ping-pong forever. Checks several
    /// payload pairs so both hash orderings are exercised, and that a real difference never reports
    /// `.identical`. (Why client `updatedAt` and not server `modificationDate` is documented on
    /// `bootstrapDecision`; this tie-break is the convergent fallback, not a correctness hole.)
    func testBootstrapDecisionTieBreakIsConvergentAcrossDevices() {
        let when = Date(timeIntervalSince1970: 5_000)
        let payloadPairs = [("alpha", "omega"), ("aaa", "zzz"), ("record-A", "record-B"), ("one", "two")]
        for (p1, p2) in payloadPairs {
            let a = bootstrapSnapshot(payload: p1, updatedAt: when)
            let b = bootstrapSnapshot(payload: p2, updatedAt: when)
            XCTAssertNotEqual(a.payloadHash, b.payloadHash, "pair (\(p1), \(p2)) needs distinct payloads")

            // Device A sees (local: a, remote: b); device B sees the mirror image.
            let decisionOnA = CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: a, remote: b)
            let decisionOnB = CloudKitSyncService.bootstrapDecision(pending: inventoryPending(), local: b, remote: a)

            let winnerHashOnA = (decisionOnA == .local) ? a.payloadHash : b.payloadHash
            let winnerHashOnB = (decisionOnB == .local) ? b.payloadHash : a.payloadHash
            XCTAssertEqual(winnerHashOnA, winnerHashOnB, "devices diverged for (\(p1), \(p2))")
            XCTAssertNotEqual(decisionOnA, .identical, "distinct payloads must not resolve identical")
        }
    }

    // MARK: - #6 / deep-audit H12: one delete-vs-edit rule at all three sites
    //
    // The same delete-vs-edit collision used to resolve three different ways, so two devices in
    // the same state reached opposite outcomes purely on send/fetch ordering. All three sites now
    // route through `deleteVsEdit`, which is delete-wins: clock-independent, unlike recency, which
    // compares two devices' wall clocks and hands the collision to whichever clock is skewed.
    // These tests therefore pin the *absence* of recency as much as the presence of the rule.

    private func resurrectionPending() -> CloudSyncPendingMutation {
        .save(modifiedAt: Date(), revision: UUID(), origin: .localChange, allowsResurrection: true)
    }

    /// The rule itself: the delete wins, and only an explicit resurrection opt-in beats it.
    func testDeleteVsEditIsDeleteWinsUnlessResurrectionIsAllowed() {
        XCTAssertEqual(CloudKitSyncService.deleteVsEdit(allowsResurrection: false), .deleteWins)
        XCTAssertEqual(CloudKitSyncService.deleteVsEdit(allowsResurrection: true), .editWins)
    }

    /// The point of the unification: one (delete, edit) pair, the same outcome at every site.
    ///
    /// The pair is the reported failure — device A deletes R at T1, device B edits R at T2 > T1 —
    /// with the edit deliberately NEWER than the delete, which is the input that used to split the
    /// three sites apart. `bootstrapDecision` sees it as a local delete vs the server's live edit
    /// (B sends first), `tombstoneBootstrapDecision` as a fetched tombstone vs a local edit (B
    /// fetches first), and `resolveServerConflict` as a rejected upload against a server tombstone.
    /// The third has no pure entry point of its own — it is an actor method that mutates metadata —
    /// so the assertion here is on the `deleteVsEdit` call it now makes, with `allowsResurrection`
    /// read off the same pending it inspects.
    func testDeleteVsEditAgreesAtAllThreeCallSites() {
        let deletedAt = Date(timeIntervalSince1970: 1_000)
        let newerEdit = bootstrapSnapshot(payload: "edit", updatedAt: Date(timeIntervalSince1970: 2_000))

        // Site 1 — `bootstrapDecision`: the delete is the local side, so delete-wins is `.local`.
        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: deletePending(), local: nil, remote: newerEdit),
            .local,
            "A local delete must beat a newer server edit."
        )
        // Site 2 — `tombstoneBootstrapDecision`: the delete is the remote side, so it applies.
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: nil, local: newerEdit, remoteDeletedAt: deletedAt),
            .applyDelete,
            "A remote delete must beat a newer local edit — the same collision, the same answer."
        )
        // Site 3 — `resolveServerConflict`, via the rule it consults for a server tombstone.
        XCTAssertEqual(
            CloudKitSyncService.deleteVsEdit(allowsResurrection: false),
            .deleteWins,
            "A server tombstone must beat the local save that collided with it."
        )
    }

    /// `allowsResurrection` must be checked BEFORE anything else — this is the test that guards
    /// `d199fc7` (tombstone compaction keeping the marker) from being silently undone.
    ///
    /// A record restored from a backup carries its ORIGINAL `updatedAt`, which is necessarily
    /// *older* than the `deletedAt` of the tombstone it is colliding with. Under the recency rule
    /// this decision used to apply, and under plain delete-wins, that restore loses and the record
    /// is deleted again — the exact bug `d199fc7` fixed by making the compacted tombstone keep the
    /// marker so the re-created record is flagged `allowsResurrection == true`. That flag is only
    /// worth keeping if it is consulted first.
    func testResurrectionOverridesRecency() {
        let deletedAt = Date(timeIntervalSince1970: 9_000)
        let restoredFromBackup = bootstrapSnapshot(payload: "restored", updatedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertLessThan(restoredFromBackup.updatedAt, deletedAt, "A restore is older than the delete it collides with.")

        XCTAssertEqual(
            CloudKitSyncService.deleteVsEdit(allowsResurrection: true),
            .editWins,
            "Resurrection must outrank the delete, regardless of which side is newer."
        )
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(
                pending: resurrectionPending(),
                local: restoredFromBackup,
                remoteDeletedAt: deletedAt
            ),
            .keepLocal,
            "A restored backup must survive the tombstone it was deleted by."
        )
    }

    /// A local edit made after the remote deletion no longer survives it.
    ///
    /// This test asserted `.keepLocal` — deep-audit H12's recency rule, that a local record newer
    /// than `remoteDeletedAt` is a later write and resurrects. Unified onto delete-wins, that input
    /// applies the deletion instead. The inversion is deliberate: recency compared two devices'
    /// wall clocks, so the outcome turned on clock skew that nothing here can measure, and it was
    /// the reason this site disagreed with the other two.
    func testTombstoneAppliesEvenWhenTheLocalEditIsNewerThanTheDeletion() {
        let deletedAt = Date(timeIntervalSince1970: 1_000)
        let newerLocal = bootstrapSnapshot(payload: "local", updatedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: nil, local: newerLocal, remoteDeletedAt: deletedAt),
            .applyDelete
        )
    }

    /// A deletion newer than the local record wins — unchanged by the unification.
    func testTombstoneAppliesWhenDeletionNewerThanLocal() {
        let deletedAt = Date(timeIntervalSince1970: 2_000)
        let olderLocal = bootstrapSnapshot(payload: "local", updatedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: nil, local: olderLocal, remoteDeletedAt: deletedAt),
            .applyDelete
        )
    }

    /// A pending save that opted into resurrection wins even when older than the deletion (existing behaviour).
    func testTombstoneResurrectionPendingAlwaysKeepsLocal() {
        let deletedAt = Date(timeIntervalSince1970: 5_000)
        let olderLocal = bootstrapSnapshot(payload: "local", updatedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: resurrectionPending(), local: olderLocal, remoteDeletedAt: deletedAt),
            .keepLocal
        )
    }

    /// Post-bootstrap there is no local snapshot, so remote deletions stay authoritative.
    func testTombstoneAppliesWhenNoLocalRecord() {
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: nil, local: nil, remoteDeletedAt: Date()),
            .applyDelete
        )
    }

    /// A tie (local.updatedAt == deletedAt) applies the deletion. It always did, but for the other
    /// reason — "not strictly newer" — and it is kept because a timestamp tie is the one input a
    /// re-introduced recency comparison would be most tempted to resolve the other way.
    func testTombstoneEqualTimestampAppliesDelete() {
        let when = Date(timeIntervalSince1970: 3_000)
        let local = bootstrapSnapshot(payload: "local", updatedAt: when)
        XCTAssertEqual(
            CloudKitSyncService.tombstoneBootstrapDecision(pending: nil, local: local, remoteDeletedAt: when),
            .applyDelete
        )
    }

    /// #15 step 2: resolution for a non-deleted save conflict. The headline property is
    /// the safety boundary — a deliberate local edit or delete must NEVER be overwritten
    /// by the server (never `.applyServer`); the server is only adopted for records with
    /// no deliberate local change when it's newer.
    func testConflictActionRouting() {
        let older = bootstrapSnapshot(payload: "old", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = bootstrapSnapshot(payload: "new", updatedAt: Date(timeIntervalSince1970: 9_000))
        let same = bootstrapSnapshot(payload: "x", updatedAt: Date(timeIntervalSince1970: 5_000))
        let sameOtherTime = bootstrapSnapshot(payload: "x", updatedAt: Date(timeIntervalSince1970: 6_000))

        // Safety boundary: a real local edit / delete always keeps local, even vs a newer server.
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: localChangePending(), local: older, server: newer), .requeueLocal)
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: deletePending(), local: older, server: newer), .requeueLocal)

        // Identical payload → drop the redundant upload (no data apply).
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: inventoryPending(), local: same, server: sameOtherTime), .adoptServerIdentical)

        // No deliberate local edit + server newer → adopt the server payload.
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: inventoryPending(), local: older, server: newer), .applyServer)
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: nil, local: older, server: newer), .applyServer)

        // No deliberate edit but local is newer → keep local.
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: inventoryPending(), local: newer, server: older), .requeueLocal)

        // Unreadable server payload (nil) → keep local; never apply nil.
        XCTAssertEqual(CloudKitSyncService.conflictAction(pending: inventoryPending(), local: older, server: nil), .requeueLocal)
    }

    // MARK: - #9b: a stamped legacy row must win recency, not a coin flip

    /// The failure this fixes, and the fix, on the two decisions that resolve it.
    ///
    /// `backfillingCurrencies` stamps legacy rows with this device's base currency — which does not
    /// sync — and `save()` records that as `origin: .localChange`. Two devices with different base
    /// currencies therefore produce two different payloads for the same record id. While the stamp
    /// left `updatedAt` alone, those payloads carried *identical* timestamps, so both
    /// `bootstrapDecision` and `conflictAction` fell through to the payload-hash tie-break and the
    /// user's legacy money was denominated by whichever hash happened to sort higher. Bumping
    /// `updatedAt` makes the stamped copy strictly newer, so it wins on recency instead.
    func testStampedLegacyRowBeatsTheUnstampedCopyOnRecency() throws {
        let original = Date(timeIntervalSince1970: 1_000)
        let legacy = Transaction(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000009")!,
            type: .income, category: "Salary", amount: 1234, description: "",
            date: fixedDate, currency: nil, createdAt: original, updatedAt: original
        )
        let key = CloudSyncRecordKey(type: .transaction, id: legacy.id)
        let unstamped = try XCTUnwrap(try FinancialData(transactions: [legacy]).cloudSyncRecords()[key])

        // What the other device still holds vs. what this one just stamped.
        let (migrated, didChange) = FinancialData(transactions: [legacy])
            .backfillingCurrencies(base: .usd, now: Date(timeIntervalSince1970: 5_000))
        XCTAssertTrue(didChange)
        let stamped = try XCTUnwrap(try migrated.cloudSyncRecords()[key])
        XCTAssertNotEqual(stamped.payloadHash, unstamped.payloadHash, "The stamp changes the payload — that is the collision.")
        XCTAssertGreaterThan(stamped.updatedAt, unstamped.updatedAt)

        // Both decisions now resolve on recency, from either side of the wire.
        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: nil, local: stamped, remote: unstamped), .local,
            "The stamped copy is the later write and must win the bootstrap merge."
        )
        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: nil, local: unstamped, remote: stamped), .remote,
            "…and must win it from the other device's point of view too."
        )
        XCTAssertEqual(
            CloudKitSyncService.conflictAction(pending: nil, local: stamped, server: unstamped), .requeueLocal
        )
        XCTAssertEqual(
            CloudKitSyncService.conflictAction(pending: nil, local: unstamped, server: stamped), .applyServer
        )

        // And the state before the fix, kept as the record of what "arbitrary" meant here: with the
        // timestamps tied, nothing but the payload hash separates the two, so the outcome flips with
        // the bytes rather than with anything the user did.
        var stampedWithOriginalTimestamp = try XCTUnwrap(migrated.transactions.first)
        stampedWithOriginalTimestamp.updatedAt = original
        let tied = try XCTUnwrap(try FinancialData(transactions: [stampedWithOriginalTimestamp]).cloudSyncRecords()[key])
        XCTAssertEqual(tied.updatedAt, unstamped.updatedAt)
        XCTAssertEqual(
            CloudKitSyncService.bootstrapDecision(pending: nil, local: tied, remote: unstamped),
            tied.payloadHash > unstamped.payloadHash ? .local : .remote,
            "Tied timestamps hand the currency to a hash comparison — the coin flip #9b removes."
        )
    }

    // MARK: - #14 sync error classification
    //
    // Before #14, `forceICloudSync()` rethrew every post-sync failure as `invalidRecord`
    // and `report(_:)` only special-cased a couple of CKError codes. These cover the pure
    // classifier that now drives both: the error → category map, and the category →
    // user-facing status (account problems must stay `.accountUnavailable`, never `.error`,
    // and each classified code must carry its own message).

    private func ckError(_ code: CKError.Code) -> CKError {
        CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue))
    }

    func testFailureCategoryMapsCKErrorCodes() {
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.notAuthenticated)), .notSignedIn)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.managedAccountRestricted)), .restricted)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.networkUnavailable)), .networkUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.networkFailure)), .networkUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.serverResponseLost)), .connectionLost)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.serviceUnavailable)), .temporarilyUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.accountTemporarilyUnavailable)), .temporarilyUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.quotaExceeded)), .quotaExceeded)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.requestRateLimited)), .rateLimited)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.zoneBusy)), .rateLimited)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.zoneNotFound)), .zoneMissing)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.internalError)), .unknown)
    }

    func testFailureCategoryMapsOwnErrors() {
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.accountUnavailable("x")), .notSignedIn)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.accountChanged), .accountChanged)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.invalidRecord("x")), .unknown)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.notRunning), .unknown)
    }

    /// #12 metadata compaction: a fully-settled tombstone keeps its **marker** and loses its bulk.
    ///
    /// This used to drop the entry outright, on the stated grounds that "every entity id is a
    /// one-shot UUID: a pruned id is never re-created". `FinanceImportService` preserves ids when a
    /// backup carries them, so restoring a backup taken before a delete re-creates the record under
    /// its original id — and with the entry gone `recordLocalChanges` rebuilds it with
    /// `allowsResurrection: state.isTombstone` == false, the upload collides with the server
    /// tombstone, and `resolveServerConflict` deletes it again while the import reports success.
    ///
    /// `systemFields` is the expensive part (an `NSKeyedArchiver` blob) and is what compaction is
    /// actually for; the marker it leaves behind is about a hundred bytes.
    func testCompactionKeepsTheTombstoneMarkerAndDropsTheBulk() {
        let systemFields = Data(repeating: 0xAB, count: 512)
        let records: [String: CloudSyncRecordState] = [
            "live": CloudSyncRecordState(systemFields: systemFields, pending: nil, isTombstone: false, deletedAt: nil),
            "settled": CloudSyncRecordState(systemFields: systemFields, pending: nil, isTombstone: true, deletedAt: fixedDate),
            "pendingDelete": CloudSyncRecordState(systemFields: systemFields, pending: deletePending(), isTombstone: true, deletedAt: fixedDate)
        ]
        let knownHashes = ["live": "hash"] // settled + pendingDelete are no longer locally present

        let compacted = CloudKitSyncService.compactingSettledTombstones(from: records, knownLocalHashes: knownHashes)

        XCTAssertEqual(compacted.count, 3, "no entry is dropped — the marker is what stops a resurrection")
        // `CloudSyncRecordState` is not `Equatable`, so compare the fields that matter.
        XCTAssertEqual(compacted["live"]?.systemFields, systemFields, "a live record keeps its bulk")
        XCTAssertEqual(compacted["live"]?.isTombstone, false)
        XCTAssertEqual(compacted["pendingDelete"]?.systemFields, systemFields,
                       "an in-flight delete is untouched — it still needs its system fields to send")
        XCTAssertNotNil(compacted["pendingDelete"]?.pending, "and keeps its pending mutation")

        let settled = compacted["settled"]
        XCTAssertEqual(settled?.isTombstone, true, "the marker survives — this is the whole fix")
        // Informational since the delete-vs-edit unification: `deletedAt` was last read for a
        // decision by `tombstoneBootstrapDecision`'s recency comparison, and a settled tombstone
        // has no pending, so it is never the value re-uploaded either. Kept as the record of when.
        XCTAssertEqual(settled?.deletedAt, fixedDate, "and the date it was deleted")
        XCTAssertNil(settled?.systemFields, "but the bulk is gone, which is what compaction is for")
        XCTAssertNil(settled?.pending)
    }

    /// #13: the opportunistic foreground sync runs only when nothing is already syncing — manual
    /// (`isSynchronizing`) or engine-driven (`engineSyncActivity`) — and the debounce window has
    /// elapsed, so it never duplicates an in-flight automatic sync.
    func testOpportunisticSyncGate() {
        let interval: TimeInterval = 30
        func gate(_ syncing: Bool, _ activity: Int, _ since: TimeInterval) -> Bool {
            CloudKitSyncService.shouldRunOpportunisticSync(
                isSynchronizing: syncing, engineSyncActivity: activity,
                secondsSinceLastSync: since, minimumInterval: interval
            )
        }
        XCTAssertTrue(gate(false, 0, 31), "idle + debounce elapsed → run")
        XCTAssertFalse(gate(true, 0, 31), "a manual sync in flight → stand down")
        XCTAssertFalse(gate(false, 1, 31), "an engine-driven automatic sync in flight → stand down (#13)")
        XCTAssertFalse(gate(false, 0, 10), "still within the debounce window → stand down")
    }

    /// #7: bootstrap may only be latched by a fetch that demonstrably reached the server.
    ///
    /// `.didFetchChanges` carries no error, and `automaticallySync = true` schedules an engine
    /// cycle before connectivity exists, so enabling sync offline used to complete bootstrap on an
    /// empty fetch — after which `handleFetchedRecordZoneChanges` skips loading local records
    /// entirely and reconnecting uploads the whole local dataset over the server's copy. `zoneReady`
    /// is the proof, since only a server round-trip can set it. Thin on purpose: the event wiring
    /// around this cannot be tested (`CKSyncEngine.Event` has no public initializer), so what is
    /// pinned here is the condition itself.
    func testShouldCompleteBootstrapRequiresAZoneRoundTrip() {
        XCTAssertFalse(
            CloudKitSyncService.shouldCompleteBootstrap(bootstrapCompleted: false, zoneReady: false),
            "a fetch that never reached the server must not latch bootstrap"
        )
        XCTAssertTrue(
            CloudKitSyncService.shouldCompleteBootstrap(bootstrapCompleted: false, zoneReady: true),
            "the zone was delivered, so the merge really did run"
        )
        XCTAssertFalse(
            CloudKitSyncService.shouldCompleteBootstrap(bootstrapCompleted: true, zoneReady: true),
            "bootstrap is one-shot — already done stays done"
        )
    }

    /// The anti-mislabel guarantee: an account failure resolves to `.accountUnavailable`
    /// (so Settings reads "iCloud Unavailable"), preserving a custom sign-in message when
    /// present; the not-signed-in CKError falls back to canned copy.
    func testSyncStatusRoutesAccountFailuresToAccountUnavailable() {
        XCTAssertEqual(
            CloudKitSyncService.syncStatus(for: CloudSyncError.accountUnavailable("Please sign in.")),
            .accountUnavailable("Please sign in.")
        )
        guard case .accountUnavailable(let message) = CloudKitSyncService.syncStatus(for: ckError(.notAuthenticated)) else {
            return XCTFail("notAuthenticated must map to .accountUnavailable.")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// Each common failure now maps to the right *tone*: transient conditions become `.waiting`
    /// (info severity — never a red error), persistent user-actionable ones become `.actionNeeded`
    /// (attention), and only the genuinely unexpected stays `.error`. Distinct, non-empty copy per
    /// category (the old behaviour collapsed several into one message — and showed offline as red).
    func testSyncStatusRoutesEachCategoryToTheRightToneAndSeverity() {
        // Transient & self-resolving → calm `.waiting` / `.info` (one representative code per category).
        let transient: [CKError.Code] = [.networkUnavailable, .serverResponseLost, .serviceUnavailable, .requestRateLimited, .zoneNotFound]
        var messages: [String] = []
        for code in transient {
            let status = CloudKitSyncService.syncStatus(for: ckError(code))
            guard case .waiting(let message) = status else {
                return XCTFail("\(code) must be a calm .waiting status, not an error.")
            }
            XCTAssertFalse(message.isEmpty, "Empty message for \(code).")
            XCTAssertEqual(status.severity, .info, "\(code) must read as info severity, never error/red.")
            messages.append(message)
        }
        XCTAssertEqual(Set(messages).count, messages.count, "Each transient category must produce distinct copy.")

        // Persistent — the user must act → `.actionNeeded` / `.attention`.
        for code in [CKError.Code.quotaExceeded, .managedAccountRestricted] {
            let status = CloudKitSyncService.syncStatus(for: ckError(code))
            guard case .actionNeeded(let message) = status, !message.isEmpty else {
                return XCTFail("\(code) must be a non-empty .actionNeeded status.")
            }
            XCTAssertEqual(status.severity, .attention)
        }
        XCTAssertEqual(CloudKitSyncService.syncStatus(for: CloudSyncError.accountChanged).severity, .attention)

        // Codes that share a category share their copy/tone (no spurious distinct messages).
        XCTAssertEqual(CloudKitSyncService.syncStatus(for: ckError(.networkFailure)),
                       CloudKitSyncService.syncStatus(for: ckError(.networkUnavailable)))
        XCTAssertEqual(CloudKitSyncService.syncStatus(for: ckError(.zoneBusy)),
                       CloudKitSyncService.syncStatus(for: ckError(.requestRateLimited)))

        // Sign-in stays its own actionable status; anything unexpected stays a real error.
        XCTAssertEqual(CloudKitSyncService.syncStatus(for: ckError(.notAuthenticated)).severity, .attention)
        XCTAssertEqual(CloudKitSyncService.syncStatus(for: ckError(.internalError)).severity, .error)
    }

    /// WC-L29: `synchronize` may report `.upToDate` on a `CKError.partialFailure` only when
    /// every per-item error is benign (retryable / a server-record conflict / a missing zone,
    /// matching what `handleSentRecordZoneChanges` already declines to throw on). A partial
    /// failure that carries a genuine rejection — or one with no introspectable item errors —
    /// must NOT be treated as benign, so it surfaces instead of reading "Up to Date."
    func testPartialFailureIsBenignOnlyWhenEveryItemIsRetryableOrConflict() {
        // Every item benign: retryable blip + first-sync conflict + zone recreation.
        XCTAssertTrue(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.networkUnavailable, .serverRecordChanged, .zoneNotFound, .batchRequestFailed])
        ))

        // .unknownItem (record-gone) is benign.
        XCTAssertTrue(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.unknownItem])
        ))
        // .serverRejectedRequest is NOT benign — a persistent rejection must surface (deep-audit M18).
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.serverRejectedRequest])
        ))
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.serverRejectedRequest, .networkUnavailable])
        ))

        // A single genuine rejection makes the whole partial failure non-benign.
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.serverRecordChanged, .quotaExceeded])
        ))
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(
            partialFailure(items: [.permissionFailure])
        ))

        // An opaque partial failure with no item errors is not benign (don't swallow it).
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(partialFailure(items: [])))

        // A non-partial-failure CKError is never a "benign partial failure".
        XCTAssertFalse(CloudKitSyncService.partialFailureIsBenign(ckError(.networkUnavailable)))
    }

    private func partialFailure(items: [CKError.Code]) -> CKError {
        var byItem: [CKRecord.ID: Error] = [:]
        for (index, code) in items.enumerated() {
            byItem[CKRecord.ID(recordName: "item-\(index)")] = NSError(domain: CKError.errorDomain, code: code.rawValue)
        }
        return CKError(_nsError: NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: byItem.isEmpty ? [:] : [CKPartialErrorsByItemIDKey: byItem]
        ))
    }

    // MARK: - #22 step 1: sent-side per-record failure routing
    //
    // `CKSyncEngine.Event.SentRecordZoneChanges` has no public initializer, so the engine-level
    // flow in `handleSentRecordZoneChanges` can't be unit-tested. The per-record decision was
    // therefore extracted into the pure `sentRecordFailureResolution`, which IS testable here —
    // the caller just performs the side effects (requeue / recreate zone / conflict / throw) the
    // routing selects. These lock in the exact branch behaviour of the original inline ladder,
    // including the easy-to-regress edges (stale-revision precedence; `serverRecordChanged`
    // without an attached server record is fatal, not a conflict).

    func testSentRecordFailureResolutionRoutesEachFailureKind() {
        let rev = UUID()
        typealias Resolution = CloudKitSyncService.SentRecordFailureResolution

        func resolve(
            _ code: CKError.Code,
            retryable: Bool = false,
            hasServer: Bool = false,
            serverDeleted: Bool = false,
            failed: UUID? = rev,
            current: UUID? = rev
        ) -> Resolution {
            CloudKitSyncService.sentRecordFailureResolution(
                errorCode: code,
                errorIsRetryable: retryable,
                hasServerRecord: hasServer,
                serverRecordIsDeleted: serverDeleted,
                failedRevision: failed,
                currentRevision: current
            )
        }

        // Stale failure (the pending revision moved on) → re-send the latest, whatever the error.
        XCTAssertEqual(resolve(.serverRecordChanged, hasServer: true, failed: UUID(), current: rev), .staleRequeue)
        XCTAssertEqual(resolve(.zoneNotFound, failed: UUID(), current: rev), .staleRequeue,
                       "the stale check takes precedence over the zone-recreation path")
        XCTAssertEqual(resolve(.permissionFailure, failed: UUID(), current: rev), .staleRequeue)

        // `serverRecordChanged` WITH a server record routes by the server's deleted flag.
        XCTAssertEqual(resolve(.serverRecordChanged, hasServer: true, serverDeleted: false), .nonDeletedConflict)
        XCTAssertEqual(resolve(.serverRecordChanged, hasServer: true, serverDeleted: true), .deletedConflict)

        // `serverRecordChanged` WITHOUT a server record has nothing to merge → not retryable → fatal.
        XCTAssertEqual(resolve(.serverRecordChanged, hasServer: false), .fatal)

        // Zone gone → recreate it (and a nil failed revision skips the stale check entirely).
        XCTAssertEqual(resolve(.zoneNotFound), .zoneRecreation)
        XCTAssertEqual(resolve(.zoneNotFound, failed: nil, current: rev), .zoneRecreation)

        // A retryable blip re-enqueues; a genuine rejection throws (fatal).
        XCTAssertEqual(resolve(.networkUnavailable, retryable: true), .retryableRequeue)
        XCTAssertEqual(resolve(.quotaExceeded, retryable: false), .fatal)
        XCTAssertEqual(resolve(.permissionFailure, retryable: false), .fatal)

        // Record gone (stale changeTag for a server-deleted record) → clear systemFields, re-create.
        XCTAssertEqual(resolve(.unknownItem), .recordGone)
        // A persistent server rejection is fatal, not recordGone, so it surfaces (deep-audit M18).
        XCTAssertEqual(resolve(.serverRejectedRequest), .fatal)
        // Stale-revision check still takes precedence over recordGone/fatal.
        XCTAssertEqual(resolve(.unknownItem, failed: UUID(), current: rev), .staleRequeue)
        XCTAssertEqual(resolve(.serverRejectedRequest, failed: UUID(), current: rev), .staleRequeue)
    }

    /// The retryable-error set the sent-side classifier trusts (`errorIsRetryable`) and that
    /// `partialFailureIsBenign` mirrors: transient transport/throttle blips retry; anything
    /// definitive does not. In particular `serverRecordChanged` and `zoneNotFound` are NOT
    /// retryable — they're routed explicitly *before* the retryable check, so this pins down
    /// that they'd otherwise fall to fatal/their own branch rather than being silently retried.
    func testIsRetryableCoversTransientErrorsOnly() {
        // `.resultsTruncated` is deliberately absent: Apple deprecated it with "Will not be
        // returned", so asserting on it is coverage of a branch CloudKit can no longer reach — and
        // it was the source of one of the project's two compiler warnings. `isRetryable` still
        // handles it defensively; only the assertion is gone.
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable,
                     .requestRateLimited, .zoneBusy, .batchRequestFailed] {
            XCTAssertTrue(CloudKitSyncService.isRetryable(ckError(code)), "\(code) should retry")
        }
        for code in [CKError.Code.notAuthenticated, .quotaExceeded, .permissionFailure,
                     .serverRecordChanged, .zoneNotFound, .internalError, .serverRejectedRequest,
                     .unknownItem] {
            XCTAssertFalse(CloudKitSyncService.isRetryable(ckError(code)), "\(code) must not retry")
        }
    }

    /// #22 step 2 (after #12): on a realistic metadata set compaction reclaims the bytes rather
    /// than the entries.
    ///
    /// The claim this test used to make — `records.count` converging to `knownLocalHashes.count`,
    /// 317 down to 238 — is the one deliberately given up, because dropping the entry is what let a
    /// restored backup delete itself again. The saving is now measured where it actually mattered:
    /// `systemFields`, an `NSKeyedArchiver` blob per record, against a ~100-byte marker.
    func testCompactionReclaimsBytesRatherThanEntries() {
        let systemFields = Data(repeating: 0xAB, count: 512)
        var records: [String: CloudSyncRecordState] = [:]
        var knownHashes: [String: String] = [:]
        for i in 0..<238 {
            let k = "live-\(i)"
            records[k] = CloudSyncRecordState(systemFields: systemFields, pending: nil, isTombstone: false, deletedAt: nil)
            knownHashes[k] = "hash-\(i)"
        }
        for i in 0..<79 {
            records["dead-\(i)"] = CloudSyncRecordState(systemFields: systemFields, pending: nil, isTombstone: true, deletedAt: fixedDate)
        }
        XCTAssertEqual(records.count, 317)

        let compacted = CloudKitSyncService.compactingSettledTombstones(from: records, knownLocalHashes: knownHashes)

        XCTAssertEqual(compacted.count, 317, "every entry is kept — the marker suppresses resurrection")
        let deadBytes = (0..<79).compactMap { compacted["dead-\($0)"]?.systemFields?.count }.reduce(0, +)
        XCTAssertEqual(deadBytes, 0, "but every settled tombstone gave up its systemFields blob")
        let liveBytes = (0..<238).compactMap { compacted["live-\($0)"]?.systemFields?.count }.reduce(0, +)
        XCTAssertEqual(liveBytes, 238 * 512, "and no live record lost anything")
        XCTAssertTrue((0..<79).allSatisfy { compacted["dead-\($0)"]?.isTombstone == true },
                      "all 79 markers survive")
    }

    // MARK: - #23 sync diagnostics export buffer
    //
    // `SyncDiagnosticsLog` is the in-memory source for the "Export Sync Diagnostics" action (the
    // live `.debug` telemetry lines aren't persisted, so OSLogStore can't retrieve them). Tests
    // use fresh instances (not `.shared`) to stay hermetic.

    /// Keeps only the most recent `capacity` lines, evicting the oldest (FIFO), so memory stays
    /// bounded however long the app runs.
    func testSyncDiagnosticsLogEvictsOldestBeyondCapacity() {
        let log = SyncDiagnosticsLog(capacity: 3)
        for i in 1...5 { log.record("line\(i)") }
        let snapshot = log.snapshot()
        XCTAssertEqual(snapshot.count, 3, "must not exceed capacity")
        XCTAssertTrue(snapshot[0].hasSuffix("line3"), "oldest two evicted")
        XCTAssertTrue(snapshot[1].hasSuffix("line4"))
        XCTAssertTrue(snapshot[2].hasSuffix("line5"), "newest retained, in order")
    }

    /// Each line is prefixed with an `MM-dd HH:mm:ss.SSS` timestamp and preserves the message
    /// verbatim. The date half is load-bearing: the ring buffer spans several days, so a time-only
    /// stamp left an export ambiguous about whether two lines were one night or three days apart.
    ///
    /// The shape is asserted whole rather than by counting separators. This test previously pinned
    /// only `prefix(12)` and a decimal-point count, so when the formatter gained the `MM-dd` prefix
    /// it began slicing `"08-24 17:14:"` and failed on a missing `.` — reporting a format change as
    /// a punctuation bug. Matching the entire stamp says what actually broke.
    func testSyncDiagnosticsLogPrependsTimestampAndPreservesMessage() throws {
        let log = SyncDiagnosticsLog(capacity: 10)
        log.record("save records=238 changed=2 deleted=0 ms=41")
        let line = try XCTUnwrap(log.snapshot().first)
        XCTAssertTrue(line.hasSuffix("save records=238 changed=2 deleted=0 ms=41"), "message preserved")
        let stamp = String(line.prefix(18))  // "MM-dd HH:mm:ss.SSS"
        XCTAssertEqual(stamp.count, 18)
        // Digits collapse to "d" so one assertion pins separators, field widths and ordering at
        // once. (The separators themselves are ICU pattern literals, so they are never
        // locale-substituted — only the digits vary.)
        let shape = stamp.map { $0.isNumber ? "d" : String($0) }.joined()
        XCTAssertEqual(shape, "dd-dd dd:dd:dd.ddd", "stamp is MM-dd HH:mm:ss.SSS")
        // `Character.isNumber` is true for Arabic-Indic digits too, so the shape check alone would
        // stay green if the formatter lost its `en_US_POSIX` locale and rendered ٠٨-٢٤ under ar_EG —
        // leaving a support export nobody can read. This is the assertion that pins the locale.
        XCTAssertTrue(stamp.allSatisfy { $0.isASCII }, "formatter stays pinned to en_US_POSIX")
    }

    /// `clear()` empties the buffer.
    func testSyncDiagnosticsLogClearEmptiesBuffer() {
        let log = SyncDiagnosticsLog(capacity: 10)
        log.record("a")
        log.record("b")
        XCTAssertEqual(log.snapshot().count, 2)
        log.clear()
        XCTAssertTrue(log.snapshot().isEmpty)
    }

    /// The buffer is the one telemetry piece touched from multiple actors (coordinator, store,
    /// sync service), so its lock must hold under contention: concurrent appends stay capped and
    /// never crash / corrupt the array.
    func testSyncDiagnosticsLogIsThreadSafeUnderConcurrentAppends() {
        let log = SyncDiagnosticsLog(capacity: 100)
        DispatchQueue.concurrentPerform(iterations: 1_000) { i in
            log.record("line\(i)")
        }
        let snapshot = log.snapshot()
        XCTAssertEqual(snapshot.count, 100, "stays capped under concurrency")
        XCTAssertTrue(snapshot.allSatisfy { $0.contains("line") }, "no torn writes")
    }

    private func makeTransaction(id: UUID, amount: Double) -> Transaction {
        Transaction(
            id: id,
            type: .expense,
            category: "Testing",
            amount: Decimal(amount),
            description: "Cloud sync test",
            date: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    // MARK: - Factory reset (purgeCloudData)

    /// The happy path deletes the WealthCompass zone exactly once and resolves cleanly.
    @MainActor
    func testPurgeCloudDataDeletesTheZoneWhenAccountIsAvailable() async throws {
        let deletedZoneName = ThreadSafeBox<String>()
        let service = makePurgeTestService(accountStatus: .available) { zoneID in
            deletedZoneName.value = zoneID.zoneName
        }

        try await service.purgeCloudData()

        XCTAssertEqual(deletedZoneName.value, "WealthCompassZone")
    }

    /// No iCloud account → `.accountUnavailable` (the caller wipes locally) and the zone
    /// delete is never attempted.
    @MainActor
    func testPurgeCloudDataThrowsAccountUnavailableAndSkipsDeleteWhenSignedOut() async {
        let deleterCalled = ThreadSafeFlag()
        let service = makePurgeTestService(accountStatus: .noAccount) { _ in
            deleterCalled.setTrue()
        }

        do {
            try await service.purgeCloudData()
            XCTFail("A signed-out purge must throw .accountUnavailable.")
        } catch CloudSyncError.accountUnavailable {
            // expected
        } catch {
            XCTFail("Expected .accountUnavailable, got \(error).")
        }
        XCTAssertFalse(deleterCalled.isSet, "A signed-out purge must not attempt a zone delete.")
    }

    /// An already-absent zone counts as success: the erase is complete by definition.
    @MainActor
    func testPurgeCloudDataTreatsMissingZoneAsSuccess() async throws {
        let service = makePurgeTestService(accountStatus: .available) { _ in
            throw self.makeCKError(.zoneNotFound)
        }

        try await service.purgeCloudData()  // must not throw
    }

    /// A genuine delete failure surfaces as `.syncFailed`, so the caller aborts with the
    /// local data still intact rather than half-erasing.
    @MainActor
    func testPurgeCloudDataSurfacesDeleteFailureAsSyncFailed() async {
        let service = makePurgeTestService(accountStatus: .available) { _ in
            throw self.makeCKError(.networkUnavailable)
        }

        do {
            try await service.purgeCloudData()
            XCTFail("A failed zone delete must throw .syncFailed.")
        } catch CloudSyncError.syncFailed {
            // expected
        } catch {
            XCTFail("Expected .syncFailed, got \(error).")
        }
    }

    private func makePurgeTestService(
        accountStatus: CKAccountStatus,
        zoneDeleter: @escaping CloudKitSyncService.ZoneDeleter
    ) -> CloudKitSyncService {
        CloudKitSyncService(
            metadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)"),
            snapshotProvider: { [:] },
            remoteMutationHandler: { _ in [] },
            statusHandler: { _ in },
            disableHandler: {},
            accountStatusProvider: { accountStatus },
            userRecordIDProvider: { CKRecord.ID(recordName: "test-user") },
            engineFactory: { _ in throw TestCloudSyncLifecycleError.engineShouldNotStart },
            zoneDeleter: zoneDeleter
        )
    }

    private func makeCKError(_ code: CKError.Code) -> CKError {
        CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue))
    }
}

private enum TestCloudSyncLifecycleError: Error {
    case engineShouldNotStart
}

private actor AccountStatusGate {
    private var statusContinuation: CheckedContinuation<CKAccountStatus, Never>?
    private var blockedContinuations: [CheckedContinuation<Void, Never>] = []

    func waitForStatus() async -> CKAccountStatus {
        blockedContinuations.forEach { $0.resume() }
        blockedContinuations.removeAll()
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func waitUntilBlocked() async {
        if statusContinuation != nil { return }
        await withCheckedContinuation { continuation in
            blockedContinuations.append(continuation)
        }
    }

    func resume(returning status: CKAccountStatus) {
        statusContinuation?.resume(returning: status)
        statusContinuation = nil
    }
}

private final class ThreadSafeFlag {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func setTrue() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Thread-safe call counter for asserting how many times a `@Sendable` provider closure ran.
private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// Thread-safe holder so a `@Sendable` test closure can record a value the test reads back.
private final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}
