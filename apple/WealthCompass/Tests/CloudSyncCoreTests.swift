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

        try destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(
                key: snapshot.key,
                payload: snapshot.payload,
                expectedPendingRevision: nil
            )
        ])
        XCTAssertEqual(destination.transactions, [transaction])

        try destination.applyCloudSyncMutations([
            CloudSyncRemoteMutation(
                key: snapshot.key,
                payload: nil,
                expectedPendingRevision: nil
            )
        ])
        XCTAssertTrue(destination.transactions.isEmpty)
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

    private func makeTransaction(id: UUID, amount: Double) -> Transaction {
        Transaction(
            id: id,
            type: .expense,
            category: "Testing",
            amount: amount,
            description: "Cloud sync test",
            date: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
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
