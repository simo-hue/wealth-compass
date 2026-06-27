import XCTest
@testable import WealthCompassMobile

/// Covers the off-main-actor save pipeline introduced for audit item M4: the serializing
/// `PersistenceCoordinator` and the non-blocking `FinanceStore.save()` that feeds it.
final class PersistenceCoordinatorTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Coordinator

    func testBurstSavesPersistLastSnapshotAndAdvanceBaseline() async throws {
        let persistence = InMemoryPersistence()
        let coordinator = makeCoordinator(persistence: persistence)
        await coordinator.seed([:])

        // Save N rapid, distinct snapshots in arrival order.
        let snapshots = (1...20).map { makeData(balance: Double($0)) }
        for snapshot in snapshots {
            _ = try await coordinator.save(snapshot)
        }

        // The persisted file equals the LAST snapshot.
        XCTAssertEqual(persistence.current, snapshots.last)

        // The baseline advanced to the last snapshot: re-saving it is a no-op diff.
        let resave = try await coordinator.save(snapshots.last!)
        XCTAssertFalse(resave.didChange)
    }

    func testSaveReportsChangeOnlyWhenDiffNonEmpty() async throws {
        let persistence = InMemoryPersistence()
        let coordinator = makeCoordinator(persistence: persistence)

        let base = makeData(balance: 100)
        await coordinator.seed(try base.cloudSyncRecords())

        // Identical snapshot → no change.
        let unchanged = try await coordinator.save(base)
        XCTAssertFalse(unchanged.didChange)

        // Mutated snapshot → change recorded.
        let mutated = makeData(balance: 250)
        let changed = try await coordinator.save(mutated)
        XCTAssertTrue(changed.didChange)
        XCTAssertEqual(persistence.current, mutated)
    }

    func testFailedSaveDoesNotCorruptBaseline() async throws {
        let persistence = ControllablePersistence()
        let coordinator = makeCoordinator(persistence: persistence)

        // Baseline is a known snapshot S0.
        let s0 = makeData(balance: 10)
        await coordinator.seed(try s0.cloudSyncRecords())

        // A save fails on disk.
        let s1 = makeData(balance: 20)
        persistence.shouldThrowOnSave = true
        do {
            _ = try await coordinator.save(s1)
            XCTFail("Expected the disk write to throw.")
        } catch {
            // expected
        }

        // The next good save must still diff against the ORIGINAL baseline S0 — proving the
        // failed attempt did not advance/corrupt it — and land on disk.
        persistence.shouldThrowOnSave = false
        let recovered = try await coordinator.save(s1)
        XCTAssertTrue(recovered.didChange, "Baseline should still be S0, so S0→S1 is a change.")
        XCTAssertEqual(persistence.current, s1)
    }

    func testApplyRemoteWritesAndAdvancesBaseline() async throws {
        let persistence = InMemoryPersistence()
        let coordinator = makeCoordinator(persistence: persistence)
        await coordinator.seed([:])

        let remote = makeData(balance: 999)
        try await coordinator.applyRemote(remote)
        XCTAssertEqual(persistence.current, remote)

        // Baseline advanced: a subsequent local save of the same data is a no-op diff.
        let outcome = try await coordinator.save(remote)
        XCTAssertFalse(outcome.didChange)
    }

    // MARK: - FinanceStore pipeline

    @MainActor
    func testFinanceStoreBurstPersistsFinalState() async {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence: persistence)
        let settings = makeSettings()

        for index in 1...25 {
            store.addTransaction(
                type: .income,
                amount: Decimal(index),
                category: "Salary",
                description: "Burst \(index)",
                date: fixedDate,
                currency: settings.currency,
                settings: settings
            )
        }

        await store.waitForPendingSaves()
        XCTAssertEqual(persistence.current?.transactions.count, 25)
    }

    @MainActor
    func testFinanceStoreRapidUpdatesLastWriteWins() async {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence: persistence)
        let settings = makeSettings()

        store.addTransaction(
            type: .expense,
            amount: 1,
            category: "Rent",
            description: "Original",
            date: fixedDate,
            currency: settings.currency,
            settings: settings
        )
        await store.waitForPendingSaves()
        let original = try! XCTUnwrap(store.transactions.first)

        for amount in 2...30 {
            store.updateTransaction(
                original,
                type: .expense,
                amount: Decimal(amount),
                category: "Rent",
                description: "Update \(amount)",
                date: fixedDate,
                currency: settings.currency,
                settings: settings
            )
        }

        await store.waitForPendingSaves()
        XCTAssertEqual(persistence.current?.transactions.count, 1)
        XCTAssertEqual(persistence.current?.transactions.first?.amount, 30)
    }

    @MainActor
    func testDiskFailureSetsPersistenceErrorOnMainActor() async {
        let persistence = ControllablePersistence()
        persistence.shouldThrowOnSave = true
        let store = makeStore(persistence: persistence)
        let settings = makeSettings()

        XCTAssertNil(store.persistenceError)
        store.addTransaction(
            type: .income,
            amount: 42,
            category: "Bonus",
            description: "Will fail",
            date: fixedDate,
            currency: settings.currency,
            settings: settings
        )

        await store.waitForPendingSaves()
        XCTAssertNotNil(store.persistenceError, "A disk failure must surface the H5 banner.")
    }

    // MARK: - Helpers

    private func makeCoordinator(persistence: FinancePersistence) -> PersistenceCoordinator {
        PersistenceCoordinator(
            persistence: persistence,
            metadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )
    }

    @MainActor
    private func makeStore(persistence: FinancePersistence) -> FinanceStore {
        FinanceStore(
            persistence: persistence,
            settings: nil,
            syncMetadataStore: CloudSyncMetadataStore(directoryName: "WealthCompassTests-\(UUID().uuidString)")
        )
    }

    @MainActor
    private func makeSettings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "WealthCompassTests-\(UUID().uuidString)")!)
    }

    private func makeData(balance: Double) -> FinancialData {
        FinancialData(
            liabilities: [
                Liability(
                    id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
                    name: "Loan",
                    currentBalance: Decimal(balance),
                    currency: .eur,
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ]
        )
    }
}

/// A thread-safe, in-memory `FinancePersistence` for tests.
private final class InMemoryPersistence: FinancePersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FinancialData?

    var locationDescription: String { "in-memory" }

    var current: FinancialData? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func load() throws -> FinancialData? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ data: FinancialData) throws {
        lock.lock(); defer { lock.unlock() }
        stored = data
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

/// An in-memory persistence whose `save` can be made to throw on demand. `load` always
/// succeeds so the store starts in a healthy state.
private final class ControllablePersistence: FinancePersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FinancialData?
    private var throwOnSave = false

    var shouldThrowOnSave: Bool {
        get { lock.lock(); defer { lock.unlock() }; return throwOnSave }
        set { lock.lock(); throwOnSave = newValue; lock.unlock() }
    }

    var locationDescription: String { "controllable" }

    var current: FinancialData? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func load() throws -> FinancialData? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ data: FinancialData) throws {
        lock.lock(); defer { lock.unlock() }
        if throwOnSave { throw TestPersistenceError.diskUnavailable }
        stored = data
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

private enum TestPersistenceError: Error {
    case diskUnavailable
}
