import XCTest
@testable import WealthCompassMobile

/// Covers the off-main-actor save pipeline introduced for audit item M4: the serializing
/// `PersistenceCoordinator` and the non-blocking `FinanceStore.save()` that feeds it.
final class PersistenceCoordinatorTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Legacy date-healing migration

    /// Healing a missing date must not touch the money in the file.
    ///
    /// The migration re-serialized the whole document through `JSONSerialization`, which parses
    /// every fractional number as a binary `Double`. One absent `createdAt` therefore rewrote every
    /// amount in the database — `1234.56` became `1234.5599999999999` — and `load()` persisted the
    /// result, changing every record's sync hash and re-uploading the entire dataset.
    func testDateHealingMigrationPreservesExactAmounts() throws {
        // `createdAt` absent on the first row, explicitly null on the second: both trigger healing.
        let json = """
        {"transactions":[
          {"id":"11111111-1111-1111-1111-111111111111","type":"income","category":"Salary",
           "amount":1234.56,"description":"","date":"2026-01-01T00:00:00.000Z",
           "updatedAt":"2026-01-01T00:00:00.000Z"},
          {"id":"22222222-2222-2222-2222-222222222222","type":"expense","category":"Rent",
           "amount":99999999.99,"description":"","date":"2026-01-02T00:00:00.000Z",
           "updatedAt":"2026-01-02T00:00:00.000Z","createdAt":null}
        ],
         "crypto":[
          {"id":"33333333-3333-3333-3333-333333333333","symbol":"BTC","name":"Bitcoin",
           "quantity":0.12345678901234567,"avgBuyPrice":0.1,"currentPrice":1,"currency":"EUR",
           "fees":0,"coinId":"bitcoin","updatedAt":"2026-01-01T00:00:00.000Z"}
         ]}
        """
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: Data(json.utf8))

        XCTAssertTrue(decoded.wasMigrated, "fixture did not trigger the healing path")
        XCTAssertEqual(decoded.data.transactions.count, 2)

        XCTAssertEqual(decoded.data.transactions[0].amount, Decimal(string: "1234.56"))
        XCTAssertEqual(decoded.data.transactions[1].amount, Decimal(string: "99999999.99"))
        XCTAssertEqual(decoded.data.crypto.first?.quantity, Decimal(string: "0.12345678901234567"))
        XCTAssertEqual(decoded.data.crypto.first?.avgBuyPrice, Decimal(string: "0.1"))

        // And the healing itself still worked.
        XCTAssertNotNil(decoded.data.transactions[0].createdAt)
        XCTAssertNotNil(decoded.data.transactions[1].createdAt)
    }

    /// The H08 salvage path re-serialized each surviving record the same way, so one undecodable
    /// record used to corrupt the money on every *good* record beside it.
    func testLossySalvagePreservesExactAmountsOnSurvivingRecords() throws {
        let json = """
        {"transactions":[
          {"id":"11111111-1111-1111-1111-111111111111","type":"income","category":"Salary",
           "amount":1234.56,"description":"","date":"2026-01-01T00:00:00.000Z",
           "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},
          {"id":"22222222-2222-2222-2222-222222222222","type":"NOT_A_TYPE","category":"X",
           "amount":1,"description":"","date":"2026-01-02T00:00:00.000Z",
           "createdAt":"2026-01-02T00:00:00.000Z","updatedAt":"2026-01-02T00:00:00.000Z"}
        ]}
        """
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: Data(json.utf8))

        XCTAssertEqual(decoded.data.transactions.count, 1, "salvage path did not run as expected")
        XCTAssertEqual(decoded.skippedRecordKeys.count, 1, "the bad record's key must be preserved")
        XCTAssertEqual(
            decoded.data.transactions[0].amount, Decimal(string: "1234.56"),
            "a healthy record's amount was corrupted while salvaging its neighbour"
        )
    }

    /// A number outside `Decimal`'s range must not take the whole document with it.
    ///
    /// `Decimal` decoding throws for |x| >= 1e128 and for a nonzero |x| below ~1e-129, where
    /// `JSONSerialization` simply parsed. Routing the salvage path through a Decimal-backed tree
    /// therefore made one runaway value fail the *entire* file — precisely the file the salvage
    /// path exists to rescue — leaving the user on the recovery screen whose only action erases.
    func testOutOfRangeNumberDoesNotDefeatTheSalvagePath() throws {
        let json = """
        {"transactions":[
          {"id":"11111111-1111-1111-1111-111111111111","type":"income","category":"Salary",
           "amount":1234.56,"description":"","date":"2026-01-01T00:00:00.000Z",
           "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},
          {"id":"22222222-2222-2222-2222-222222222222","type":"NOT_A_TYPE","category":"X",
           "amount":1e300,"description":"","date":"2026-01-02T00:00:00.000Z",
           "createdAt":"2026-01-02T00:00:00.000Z","updatedAt":"2026-01-02T00:00:00.000Z"}
        ]}
        """
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: Data(json.utf8))

        XCTAssertEqual(decoded.data.transactions.count, 1, "the healthy record was lost with the bad one")
        XCTAssertEqual(decoded.data.transactions[0].amount, Decimal(string: "1234.56"))
        XCTAssertEqual(decoded.skippedRecordKeys.count, 1)
    }

    /// H08's other half: what `load()` protects, `save()` has to keep protecting.
    ///
    /// `load()` deliberately refuses to rewrite the file when anything was skipped, so an
    /// undecodable record — an unknown enum value written by a newer build and synced back —
    /// survives on disk for a version that can read it. But `save` wrote the lossy in-memory
    /// snapshot straight over the file, so the user's very first edit erased exactly what the load
    /// had gone out of its way to keep. With iCloud sync off, nothing else holds a copy.
    func testSavePreservesRecordsTheLoadHadToSkip() throws {
        let directoryName = "WealthCompassTests-\(UUID().uuidString)"
        let persistence = LocalFinancePersistence(directoryName: directoryName, fileName: "db.json")
        defer { try? persistence.clear() }

        let unreadableID = "22222222-2222-2222-2222-222222222222"
        let json = """
        {"transactions":[
          {"id":"11111111-1111-1111-1111-111111111111","type":"income","category":"Salary",
           "amount":1234.56,"description":"","date":"2026-01-01T00:00:00.000Z",
           "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},
          {"id":"\(unreadableID)","type":"NOT_A_TYPE","category":"Mystery",
           "amount":4321.99,"description":"","date":"2026-01-02T00:00:00.000Z",
           "createdAt":"2026-01-02T00:00:00.000Z","updatedAt":"2026-01-02T00:00:00.000Z"}
        ]}
        """
        let fileURL = try writeDatabase(json, directoryName: directoryName, fileName: "db.json")

        let loaded = try XCTUnwrap(try persistence.load())
        XCTAssertEqual(loaded.data.transactions.count, 1, "fixture did not exercise the salvage path")
        XCTAssertEqual(loaded.skippedRecordKeys.count, 1)

        // The user edits something; the store saves the snapshot the load produced.
        var edited = loaded.data
        edited.transactions[0].amount = Decimal(string: "2000")!
        try persistence.save(edited, preserving: loaded.skippedRecordKeys)

        let rewritten = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertTrue(rewritten.contains(unreadableID), "the first edit erased the record load had protected")
        XCTAssertTrue(rewritten.contains("NOT_A_TYPE"), "the record was kept but no longer verbatim")
        XCTAssertTrue(rewritten.contains("4321.99"), "the unreadable record's amount was rewritten")
        XCTAssertTrue(rewritten.contains("2000"), "the user's edit was not saved")

        // And it is still exactly one skipped record — not duplicated by the splice.
        let reloaded = try XCTUnwrap(try persistence.load())
        XCTAssertEqual(reloaded.data.transactions.count, 1)
        XCTAssertEqual(reloaded.data.transactions[0].amount, Decimal(string: "2000"))
        XCTAssertEqual(reloaded.skippedRecordKeys.count, 1, "the preserved record was duplicated")
    }

    /// A spliced save and an ordinary save must write the same bytes for the same data.
    ///
    /// The database file flaps whenever the two encoders disagree, because which one runs depends
    /// on whether a record happens to be decodable — a condition that flips when a newer build
    /// syncs a record back, and flips again when the app learns to read it. `33d40e0` fixed one
    /// half: the splice re-encoded without `.prettyPrinted`, so the first save after a
    /// skipped-record load collapsed the whole file to one line. It shipped without a test, and it
    /// left the other half in place — the splice encoder also carries `.withoutEscapingSlashes`
    /// and the ordinary save's did not. Measured on the same record before this fix:
    ///
    ///     ordinary save : "description" : "Rent 01\/02 landlord",
    ///     spliced  save : "description" : "Rent 01/02 landlord",
    ///
    /// So every user string containing a `/` — a free-text description, an imported Revolut or
    /// Trade Republic memo — still flipped on exactly the same trigger. Both halves are pinned
    /// here: the first two lines pin pretty-printing, the description line pins the escaping.
    func testSplicedSaveWritesTheSameBytesAsAnOrdinarySave() throws {
        let goodID = "11111111-1111-1111-1111-111111111111"
        let unreadableID = "22222222-2222-2222-2222-222222222222"
        func fixture(includingUnreadableRecord: Bool) -> Data {
            let unreadable = """
            ,{"id":"\(unreadableID)","type":"NOT_A_TYPE","category":"Mystery",
              "amount":4321.99,"description":"","date":"2026-01-02T00:00:00.000Z",
              "createdAt":"2026-01-02T00:00:00.000Z","updatedAt":"2026-01-02T00:00:00.000Z"}
            """
            return Data("""
            {"transactions":[
              {"id":"\(goodID)","type":"expense","category":"Rent",
               "amount":1234.56,"description":"Rent 01/02 landlord","date":"2026-01-01T00:00:00.000Z",
               "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}\
            \(includingUnreadableRecord ? unreadable : "")
            ]}
            """.utf8)
        }

        // The salvage path: one record survives, one is preserved as the subtree the file holds.
        let existing = fixture(includingUnreadableRecord: true)
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: existing)
        XCTAssertEqual(decoded.data.transactions.count, 1, "fixture did not exercise the salvage path")
        XCTAssertEqual(decoded.skippedRecordKeys.count, 1)

        let spliced = String(decoding: try FinanceJSONCoding.encodeFinancialData(
            decoded.data, preserving: decoded.skippedRecordKeys, from: existing
        ), as: UTF8.self)

        // The same data, saved the ordinary way — what the very next save writes once the record
        // becomes decodable, or once sync replaces it.
        let clean = try FinanceJSONCoding.decodeFinancialData(from: fixture(includingUnreadableRecord: false))
        XCTAssertTrue(clean.skippedRecordKeys.isEmpty)
        XCTAssertEqual(clean.data.transactions, decoded.data.transactions, "the two paths must see identical data")
        let ordinary = String(decoding: try FinanceJSONCoding.encode(clean.data, prettyPrinted: true), as: UTF8.self)

        let splicedLines = spliced.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let ordinaryLines = ordinary.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Pretty-printing, without hardcoding Foundation's exact spacing: a compact splice is one
        // line, so it cannot match the ordinary save's opening two.
        XCTAssertGreaterThan(splicedLines.count, 2, "the spliced save collapsed the file")
        XCTAssertEqual(Array(splicedLines.prefix(2)), Array(ordinaryLines.prefix(2)))

        // Escaping. `landlord` occurs only in the record both files share — the preserved record's
        // description is empty — so this is one line on each side.
        func descriptionLine(_ lines: [String], _ label: String) throws -> String {
            let matches = lines.filter { $0.contains("landlord") }
            XCTAssertEqual(matches.count, 1, "\(label): expected exactly one line for the shared record")
            return try XCTUnwrap(matches.first).trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(
            try descriptionLine(splicedLines, "spliced"),
            try descriptionLine(ordinaryLines, "ordinary"),
            "the same description is written differently depending on whether a record was spliced"
        )
        // And the direction the tie was broken: this app does not escape slashes anywhere.
        XCTAssertFalse(ordinary.contains(#"\/"#), "an ordinary save still escapes slashes")
        XCTAssertFalse(spliced.contains(#"\/"#), "a spliced save still escapes slashes")
    }

    /// The common path must not change: with nothing skipped, `save` writes the snapshot and only
    /// the snapshot — no stale record resurrected from whatever the file used to hold.
    func testSaveWithNothingSkippedWritesOnlyTheSnapshot() throws {
        let directoryName = "WealthCompassTests-\(UUID().uuidString)"
        let persistence = LocalFinancePersistence(directoryName: directoryName, fileName: "db.json")
        defer { try? persistence.clear() }

        let json = """
        {"transactions":[
          {"id":"11111111-1111-1111-1111-111111111111","type":"income","category":"Salary",
           "amount":1234.56,"description":"","date":"2026-01-01T00:00:00.000Z",
           "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}
        ]}
        """
        let fileURL = try writeDatabase(json, directoryName: directoryName, fileName: "db.json")

        let loaded = try XCTUnwrap(try persistence.load())
        XCTAssertTrue(loaded.skippedRecordKeys.isEmpty)
        try persistence.save(FinancialData(), preserving: loaded.skippedRecordKeys)

        let rewritten = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertFalse(rewritten.contains("11111111-1111-1111-1111-111111111111"), "a deleted record came back")
    }

    private func writeDatabase(_ json: String, directoryName: String, fileName: String) throws -> URL {
        let directory = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ).appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try Data(json.utf8).write(to: fileURL)
        return fileURL
    }

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

    func load() throws -> FinancePersistenceLoad? {
        lock.lock(); defer { lock.unlock() }
        return stored.map { FinancePersistenceLoad(data: $0) }
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

    func load() throws -> FinancePersistenceLoad? {
        lock.lock(); defer { lock.unlock() }
        return stored.map { FinancePersistenceLoad(data: $0) }
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
