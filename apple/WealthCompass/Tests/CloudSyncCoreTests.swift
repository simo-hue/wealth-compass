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
        XCTAssertEqual(CloudKitSyncService.bootstrapDecision(pending: deletePending(), local: local, remote: remote), .local)
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
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.networkUnavailable)), .networkUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.networkFailure)), .networkUnavailable)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.serverResponseLost)), .connectionLost)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.quotaExceeded)), .quotaExceeded)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.requestRateLimited)), .rateLimited)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.zoneNotFound)), .zoneMissing)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: ckError(.internalError)), .unknown)
    }

    func testFailureCategoryMapsOwnErrors() {
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.accountUnavailable("x")), .notSignedIn)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.accountChanged), .accountChanged)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.invalidRecord("x")), .unknown)
        XCTAssertEqual(CloudKitSyncService.failureCategory(for: CloudSyncError.notRunning), .unknown)
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

    /// Network / quota / throttling / zone failures each become `.error` (never
    /// `.accountUnavailable`) with their own non-empty copy — the old behavior gave them
    /// all one indistinct message.
    func testSyncStatusGivesDistinctErrorCopyPerCategory() {
        let codes: [CKError.Code] = [.networkUnavailable, .serverResponseLost, .quotaExceeded, .requestRateLimited, .zoneNotFound]
        var messages: [String] = []
        for code in codes {
            guard case .error(let message) = CloudKitSyncService.syncStatus(for: ckError(code)) else {
                return XCTFail("\(code) must map to .error, not .accountUnavailable.")
            }
            XCTAssertFalse(message.isEmpty, "Empty message for \(code).")
            messages.append(message)
        }
        XCTAssertEqual(Set(messages).count, messages.count, "Each classified CKError code must produce distinct copy.")
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
