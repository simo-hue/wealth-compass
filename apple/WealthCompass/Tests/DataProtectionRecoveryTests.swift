import XCTest
@testable import WealthCompassMobile

/// WC-LOCK1 regression tests.
///
/// The original incident: a silent CloudKit push cold-launched the app while the device was locked,
/// so every file written with `.completeFileProtectionUnlessOpen` was unreadable. The finance store
/// came up empty and never retried (zeroed dashboard until a force-quit), and the sync-metadata
/// store mistook the read denial for "no file yet" and overwrote healthy metadata with an empty
/// document, discarding the change token and forcing a full re-bootstrap.
///
/// These tests reproduce that denial with `chmod 000`, which yields the very same
/// `NSCocoaErrorDomain` 257 (`NSFileReadNoPermissionError`) the device reported — no injected
/// reader, no fake error, no production seam that exists only for tests. The simulator has no data
/// protection, so POSIX permissions are the only faithful way to reach this code path there.
final class DataProtectionRecoveryTests: XCTestCase {
    private var directoryName = ""
    private var directoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryName = "WealthCompassTests-\(UUID().uuidString)"
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        directoryURL = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions first, or the directory itself can't be torn down.
        if let entries = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            for entry in entries {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: entry.path)
            }
        }
        try? FileManager.default.removeItem(at: directoryURL)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeUnreadable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        // Guard the test itself: running as root defeats POSIX permissions, and the test would
        // then silently assert nothing at all.
        XCTAssertThrowsError(try Data(contentsOf: url), "fixture is still readable — is this running as root?")
    }

    private func makeReadable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private var metadataURL: URL { directoryURL.appendingPathComponent("wealth-compass-cloud-sync.json") }
    private var financeURL: URL { directoryURL.appendingPathComponent("wealth-compass-local-data.json") }

    private func makeMetadataStore() -> CloudSyncMetadataStore {
        CloudSyncMetadataStore(directoryName: directoryName)
    }

    /// Settings backed by a throwaway `UserDefaults` suite and an isolated FX cache.
    ///
    /// Never pass `settings: nil` to `FinanceStore` here: it falls back to
    /// `UserDefaults.standard` for the iCloud-sync flag, so a leftover `true` in the test host
    /// would start the real CloudKit engine mid-test.
    @MainActor
    private func makeIsolatedSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: directoryName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: self.directoryName) }
        return AppSettings(
            userDefaults: defaults,
            exchangeRatePersistence: LocalExchangeRatePersistence(directoryName: directoryName)
        )
    }

    private func sampleRecords() throws -> [CloudSyncRecordKey: CloudSyncRecordSnapshot] {
        var data = FinancialData()
        data.transactions = [
            Transaction(
                type: .income,
                category: "Salary",
                amount: 1000,
                description: "test",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                currency: .eur
            )
        ]
        return try data.cloudSyncRecords()
    }

    // MARK: - The destructive half: metadata must never be overwritten when unreadable

    /// The core regression. Before the fix, constructing the store over an unreadable file yielded
    /// empty metadata and the next write persisted it, destroying the real change token.
    func testUnreadableMetadataIsNeverOverwritten() throws {
        // Establish real metadata on disk.
        let seeded = makeMetadataStore()
        try seeded.reconcileLocalInventory(try sampleRecords())
        let goodContents = try Data(contentsOf: metadataURL)
        XCTAssertGreaterThan(goodContents.count, 0)

        try makeUnreadable(metadataURL)

        // A fresh store over the unreadable file must come up inert...
        let store = makeMetadataStore()
        XCTAssertTrue(store.isUnavailable, "an unreadable metadata file must mark the store unavailable")

        // ...and refuse every write rather than clobbering it.
        XCTAssertThrowsError(try store.reconcileLocalInventory(try sampleRecords())) { error in
            guard case CloudSyncMetadataStoreError.unavailable = error else {
                return XCTFail("expected .unavailable, got \(error)")
            }
        }

        try makeReadable(metadataURL)
        XCTAssertEqual(
            try Data(contentsOf: metadataURL),
            goodContents,
            "the metadata file must be byte-identical — this is the wipe the user actually experienced"
        )
    }

    /// Once the file is readable again, the store adopts what is on disk — the real change token,
    /// not the blank slate it was holding.
    func testMetadataStoreRecoversAfterFileBecomesReadable() throws {
        let seeded = makeMetadataStore()
        let records = try sampleRecords()
        try seeded.reconcileLocalInventory(records)
        let expectedKey = try XCTUnwrap(records.keys.first)
        XCTAssertNotNil(seeded.pendingRevision(for: expectedKey))

        try makeUnreadable(metadataURL)
        let store = makeMetadataStore()
        XCTAssertTrue(store.isUnavailable)
        XCTAssertFalse(store.reloadIfUnavailable(), "still unreadable — recovery must report failure")

        try makeReadable(metadataURL)
        XCTAssertTrue(store.reloadIfUnavailable())
        XCTAssertFalse(store.isUnavailable)
        XCTAssertNotNil(
            store.pendingRevision(for: expectedKey),
            "recovery must adopt the on-disk record state, not keep the blank slate"
        )
        // Writes work again.
        XCTAssertNoThrow(try store.reconcileLocalInventory(records))
    }

    /// A missing file is a genuinely clean slate and must stay writable — the distinction the old
    /// `try?` collapsed.
    func testMissingMetadataStaysWritable() throws {
        let store = makeMetadataStore()
        XCTAssertFalse(store.isUnavailable)
        XCTAssertNoThrow(try store.reconcileLocalInventory(try sampleRecords()))
    }

    /// Readable but undecodable: nothing to preserve, so starting clean and healing the file is
    /// correct. This is the case that must NOT be fail-closed, or a corrupt file would wedge sync
    /// forever with no self-heal path.
    func testCorruptMetadataStartsCleanAndStaysWritable() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8).write(to: metadataURL)

        let store = makeMetadataStore()
        XCTAssertFalse(store.isUnavailable, "a corrupt file is recoverable by overwriting it")
        let records = try sampleRecords()
        XCTAssertNoThrow(try store.reconcileLocalInventory(records))
        // `CloudSyncMetadata` is file-private to CloudKitSyncService.swift, so assert on the
        // healed file's JSON shape rather than decoding it into the type.
        let healed = try JSONSerialization.jsonObject(with: try Data(contentsOf: metadataURL)) as? [String: Any]
        let healedRecords = try XCTUnwrap(healed?["records"] as? [String: Any])
        XCTAssertEqual(healedRecords.count, records.count, "the next write must heal a corrupt file")
    }

    /// A factory reset is the user explicitly asking for a clean slate, so it must work even while
    /// the store is inert — otherwise an unreadable file would leave no way out.
    func testResetSucceedsWhileUnavailableAndUnwedgesTheStore() throws {
        let seeded = makeMetadataStore()
        try seeded.reconcileLocalInventory(try sampleRecords())
        try makeUnreadable(metadataURL)

        let store = makeMetadataStore()
        XCTAssertTrue(store.isUnavailable)
        try makeReadable(metadataURL) // reset rewrites the file, so it must be writable
        XCTAssertNoThrow(try store.reset())
        XCTAssertFalse(store.isUnavailable)
        XCTAssertNoThrow(try store.reconcileLocalInventory(try sampleRecords()))
    }

    // MARK: - The visible half: an unreadable finance DB must not read as "no data"

    /// `LocalFinancePersistence.load()` must surface the denial as a thrown error, never as a
    /// successful load of an empty database — which is what rendered a zeroed dashboard.
    func testUnreadableFinanceDatabaseThrowsRatherThanReturningEmpty() throws {
        let persistence = LocalFinancePersistence(directoryName: directoryName)
        var data = FinancialData()
        data.transactions = [
            Transaction(
                type: .expense,
                category: "Groceries",
                amount: 42,
                description: "test",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                currency: .eur
            )
        ]
        try persistence.save(data)
        try makeUnreadable(financeURL)

        XCTAssertThrowsError(try persistence.load()) { error in
            XCTAssertTrue(
                DataProtection.isPermissionDenied(error),
                "expected a permission denial, got \(DataProtection.diagnosticCode(for: error))"
            )
        }

        // And the file is intact — a failed load must never mutate the database.
        try makeReadable(financeURL)
        let recovered = try XCTUnwrap(try persistence.load())
        XCTAssertEqual(recovered.data.transactions.count, 1)
    }

    /// Classification drives wording only, but it still has to be right for the message the user
    /// reads — and must not misfire on unrelated failures.
    func testPermissionDenialClassification() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertTrue(DataProtection.isPermissionDenied(denied))
        XCTAssertTrue(DataProtection.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSUnderlyingErrorKey: denied])
        ))
        XCTAssertFalse(DataProtection.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        XCTAssertFalse(DataProtection.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)))
        XCTAssertEqual(DataProtection.diagnosticCode(for: denied), "\(NSCocoaErrorDomain) \(NSFileReadNoPermissionError)")
    }

    // MARK: - Store-level behaviour

    /// End-to-end: an unreadable DB must produce `.failed(isLocked:)` — never `.loaded` over an
    /// empty dataset — and must recover in place, without a relaunch, once the file is readable.
    @MainActor
    func testFinanceStoreFailsThenRecoversWithoutRelaunch() async throws {
        let persistence = LocalFinancePersistence(directoryName: directoryName)
        var data = FinancialData()
        data.transactions = [
            Transaction(
                type: .income,
                category: "Salary",
                amount: 2500,
                description: "test",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                currency: .eur
            )
        ]
        try persistence.save(data)
        try makeUnreadable(financeURL)

        let settings = makeIsolatedSettings()
        let store = FinanceStore(
            persistence: persistence,
            settings: settings,
            syncMetadataStore: makeMetadataStore()
        )
        guard case .failed(_, let isLocked) = store.loadState else {
            return XCTFail("expected .failed, got \(store.loadState)")
        }
        XCTAssertTrue(isLocked)
        XCTAssertTrue(store.data.transactions.isEmpty)

        try makeReadable(financeURL)
        await store.retryLoadIfNeeded(reason: "test")

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.data.transactions.count, 1, "recovery must load the real dataset in place")

        // The save pipeline must be live again after recovery. (Only assertable here, not in the
        // command-line harness: a successful save reaches CloudKit, which needs the app host's
        // entitlements.)
        store.addTransaction(
            type: .expense,
            amount: 10,
            category: "Groceries",
            description: "after recovery",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            currency: .eur,
            settings: settings
        )
        await store.waitForPendingSaves()
        let persisted = try XCTUnwrap(try persistence.load())
        XCTAssertEqual(persisted.data.transactions.count, 2, "edits must persist normally after recovery")
    }

    /// Split failure: the finance DB is readable but the sync-metadata file is not. The two files
    /// carry independent protection classes and fail independently.
    ///
    /// Regression for the state this fix originally introduced: the store went `.loaded`, so
    /// `retryLoadIfNeeded` returned at its first guard and `reloadIfUnavailable()` — whose only
    /// call site is inside `performLoad` — became unreachable. Sync stayed down for the whole
    /// process and every edit wrote to disk successfully and then told the user it hadn't.
    @MainActor
    func testReadableDatabaseWithUnreadableMetadataRecoversAndNeverClaimsSaveFailed() async throws {
        let persistence = LocalFinancePersistence(directoryName: directoryName)
        var data = FinancialData()
        data.transactions = [
            Transaction(
                type: .income,
                category: "Salary",
                amount: 2500,
                description: "test",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                currency: .eur
            )
        ]
        try persistence.save(data)
        let beforeEdit = try Data(contentsOf: financeURL)

        // Establish real metadata, then make only that file unreadable.
        let seeded = makeMetadataStore()
        try seeded.reconcileLocalInventory(try data.cloudSyncRecords())
        try makeUnreadable(metadataURL)

        let settings = makeIsolatedSettings()
        let store = FinanceStore(
            persistence: persistence,
            settings: settings,
            syncMetadataStore: makeMetadataStore()
        )
        XCTAssertEqual(store.loadState, .loaded, "the DB is readable, so the real data must be shown")
        XCTAssertEqual(store.data.transactions.count, 1)

        store.addTransaction(
            type: .expense,
            amount: 7,
            category: "Groceries",
            description: "split state",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            currency: .eur,
            settings: settings
        )
        await store.waitForPendingSaves()

        XCTAssertNotEqual(try Data(contentsOf: financeURL), beforeEdit, "the edit must reach disk")
        XCTAssertNil(
            store.persistenceError,
            "the DB write succeeded — claiming the change could not be saved would be a lie, repeated on every edit"
        )
        XCTAssertNotNil(store.iCloudSyncError, "it must still be reported, as a sync degradation")

        // Recovery without a relaunch, via the foreground retry.
        try makeReadable(metadataURL)
        await store.retryLoadIfNeeded(reason: "test")
        XCTAssertFalse(makeMetadataStore().isUnavailable, "the metadata file must be intact and readable")
    }

    /// The reseed ordering in `retryLoadIfNeeded` is load-bearing, and a store-level test cannot
    /// see it (the file contents are correct either way). Asserted here at the coordinator level,
    /// where a stale baseline is directly observable: it re-marks already-synced records as
    /// pending, which is the full-dataset re-upload the ordering exists to prevent.
    ///
    /// `useCorrectBaseline: false` is included so the assertion is provably discriminating.
    @MainActor
    func testStaleDiffBaselineReMarksAlreadySyncedRecords() async throws {
        func revisionAfterEdit(useCorrectBaseline: Bool) async throws -> (before: UUID?, after: UUID?) {
            let persistence = LocalFinancePersistence(directoryName: directoryName)
            let metadata = makeMetadataStore()
            // Derived from the SAME value that gets saved: Transaction stamps fresh
            // createdAt/updatedAt per initialization, so a second sample would hash differently
            // and make even a correct baseline look stale.
            var base = FinancialData()
            base.transactions = [
                Transaction(
                    type: .income,
                    category: "Salary",
                    amount: 2500,
                    description: "test",
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    currency: .eur
                )
            ]
            try persistence.save(base)
            let baseRecords = try base.cloudSyncRecords()
            try metadata.reconcileLocalInventory(baseRecords)
            let watched = try XCTUnwrap(baseRecords.keys.first)
            let before = metadata.pendingRevision(for: watched)

            let coordinator = PersistenceCoordinator(persistence: persistence, metadataStore: metadata)
            await coordinator.seed(useCorrectBaseline ? baseRecords : [:])
            var edited = base
            edited.transactions.append(
                Transaction(
                    type: .expense,
                    category: "Groceries",
                    amount: 7,
                    description: "new",
                    date: Date(timeIntervalSince1970: 1_700_172_800),
                    currency: .eur
                )
            )
            _ = try await coordinator.save(edited)
            return (before, metadata.pendingRevision(for: watched))
        }

        let correct = try await revisionAfterEdit(useCorrectBaseline: true)
        XCTAssertEqual(correct.before, correct.after, "a correct baseline must leave already-synced records untouched")

        // Clean up between runs so the second pass starts from the same place.
        try? FileManager.default.removeItem(at: directoryURL)

        let stale = try await revisionAfterEdit(useCorrectBaseline: false)
        XCTAssertNotEqual(stale.before, stale.after, "an empty baseline re-marks everything — the check above is discriminating")
    }

    /// The write guard. While the DB is unreadable, a mutation must not reach disk — this is what
    /// stopped an empty in-memory dataset from being persisted over the user's real one.
    @MainActor
    func testMutationsAreNotPersistedWhileLoadFailed() async throws {
        let persistence = LocalFinancePersistence(directoryName: directoryName)
        var data = FinancialData()
        data.transactions = [
            Transaction(
                type: .income,
                category: "Salary",
                amount: 2500,
                description: "test",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                currency: .eur
            )
        ]
        try persistence.save(data)
        let goodContents = try Data(contentsOf: financeURL)
        try makeUnreadable(financeURL)

        let settings = makeIsolatedSettings()
        let store = FinanceStore(
            persistence: persistence,
            settings: settings,
            syncMetadataStore: makeMetadataStore()
        )
        store.addTransaction(
            type: .expense,
            amount: 10,
            category: "Groceries",
            description: "should not persist",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            currency: .eur,
            settings: settings
        )
        await store.waitForPendingSaves()

        try makeReadable(financeURL)
        XCTAssertEqual(
            try Data(contentsOf: financeURL),
            goodContents,
            "a write while the DB is unreadable must never touch the file"
        )
    }
}
