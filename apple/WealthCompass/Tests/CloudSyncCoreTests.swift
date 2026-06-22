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
