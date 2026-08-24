import Foundation

/// Result of loading the local DB. Carries the decoded data plus any record keys that were present
/// in the file but couldn't be decoded and were skipped (deep-audit H08), so the sync layer can
/// keep those records out of the delete/tombstone path instead of losing them everywhere.
struct FinancePersistenceLoad: Sendable {
    let data: FinancialData
    let skippedRecordKeys: [CloudSyncRecordKey]

    init(data: FinancialData, skippedRecordKeys: [CloudSyncRecordKey] = []) {
        self.data = data
        self.skippedRecordKeys = skippedRecordKeys
    }
}

protocol FinancePersistence: Sendable {
    var locationDescription: String { get }

    func load() throws -> FinancePersistenceLoad?
    func save(_ data: FinancialData) throws
    func clear() throws

    /// Brings an already-existing store up to the current data-protection class (WC-LOCK1).
    /// Called after a successful load, i.e. while protected data is provably available.
    func upgradeProtectionClassIfNeeded()
}

extension FinancePersistence {
    /// No-op default so in-memory / test doubles don't have to care about on-disk protection.
    func upgradeProtectionClassIfNeeded() {}
}

/// Stateless file writer (it only holds immutable configuration), so it is safe to hand to
/// the off-main-actor `PersistenceCoordinator`. `FileManager.default` is itself documented
/// as thread-safe, hence the `@unchecked Sendable`.
struct LocalFinancePersistence: FinancePersistence, @unchecked Sendable {
    private let fileManager: FileManager
    private let storageURL: URL
    private let legacyStorageURLs: [URL]
    private let fileName: String

    var locationDescription: String {
        storageURL.path
    }

    init(
        fileManager: FileManager = .default,
        directoryName: String = "Wealth Compass Tracker",
        fileName: String = "wealth-compass-local-data.json"
    ) {
        self.fileManager = fileManager
        self.fileName = fileName

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        storageURL = applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        legacyStorageURLs = documents.map { [$0.appendingPathComponent(fileName)] } ?? []

    }

    func load() throws -> FinancePersistenceLoad? {
        try migrateLegacyFileIfNeeded()
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let sourceData = try Data(contentsOf: storageURL)
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: sourceData)
        // Only rewrite the file for a legacy migration when nothing was skipped (H08): the lossy
        // decode drops undecodable records from `decoded.data`, so persisting it here would erase
        // those records from disk. Leaving the file untouched preserves them for a future app
        // version that can read them; the harmless date-healing migration just re-runs next load.
        if decoded.wasMigrated && decoded.skippedRecordKeys.isEmpty {
            // Best-effort: a failed pre-CloudKit backup must not abort an otherwise-successful load
            // (deep-audit L30). The migrated-data write below stays fatal — that one must succeed.
            try? createMigrationBackupIfNeeded(sourceData)
            try write(decoded.data)
        }
        return FinancePersistenceLoad(data: decoded.data, skippedRecordKeys: decoded.skippedRecordKeys)
    }

    func save(_ data: FinancialData) throws {
        try createStorageDirectoryIfNeeded()
        try write(data)
    }

    /// WC-LOCK1: re-stamps **only the live finance DB** with the current protection class, so an
    /// install created before this fix stops being unreadable during a locked background launch.
    /// See `DataProtection.upgradeProtectionClass`.
    ///
    /// The `.pre-cloudkit-backup` sidecar is intentionally left out: it is a verbatim copy of the
    /// user's finance data that the app only ever *writes*, so relaxing its class would widen the
    /// at-rest exposure of a full plaintext copy for no benefit at all.
    func upgradeProtectionClassIfNeeded() {
        DataProtection.upgradeProtectionClass(at: storageURL, fileManager: fileManager)
    }

    func clear() throws {
        // Also remove the one-time pre-CloudKit migration backup: it is a verbatim copy of
        // the user's finance data, so a "real and complete" erase must not leave it behind.
        // Every copy is removed independently. `wipeLocalState` calls this as `try?`, so a single
        // throw part-way through would be swallowed *and* leave the remaining copies on disk — and
        // if the live DB were the one left, the next launch would restore everything the user had
        // just erased. The live DB is deleted first for the same reason: it is the copy that
        // actually comes back.
        var firstFailure: Error?
        func remove(_ url: URL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do { try fileManager.removeItem(at: url) } catch { firstFailure = firstFailure ?? error }
        }

        remove(storageURL)
        remove(storageURL.appendingPathExtension("pre-cloudkit-backup"))
        // The same reasoning applies to the pre-Application-Support database in `Documents/`, and
        // it was missed. `migrateLegacyFileIfNeeded` *copies* that file rather than moving it, so
        // it outlives the migration — and because the migration's guard is only "does the live file
        // exist?", leaving it here did not merely strand a plaintext copy of the user's finances on
        // disk after a full erase: the very next `load()` copied it back and restored everything
        // they had just deleted, which sync then republished.
        for legacyURL in legacyStorageURLs {
            remove(legacyURL)
        }
        if let firstFailure { throw firstFailure }
    }

    private func createStorageDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateLegacyFileIfNeeded() throws {
        guard !fileManager.fileExists(atPath: storageURL.path) else { return }
        guard let legacyURL = legacyStorageURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        try createStorageDirectoryIfNeeded()
        // Read + protected write instead of `copyItem` (deep-audit M14): `copyItem` inherits the
        // legacy Documents-container file's weaker protection class, whereas every other write here
        // applies `.completeFileProtectionUnlessOpen`. The finance DB is a small JSON blob, so
        // reading it into memory to re-write with protection is cheap.
        let legacyData = try Data(contentsOf: legacyURL)
        try legacyData.write(to: storageURL, options: DataProtection.atomicWriteOptions)
    }

    /// The one file that keeps `.completeFileProtectionUnlessOpen` (WC-LOCK1): it is written
    /// exactly once, only after a successful decode (so never during a locked launch), and is
    /// never read back by the app — so there is no reason to relax it alongside the live DB.
    private func createMigrationBackupIfNeeded(_ sourceData: Data) throws {
        let backupURL = storageURL.appendingPathExtension("pre-cloudkit-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try sourceData.write(to: backupURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func write(_ data: FinancialData) throws {
        let encoded = try FinanceJSONCoding.encode(data, prettyPrinted: true)
        try encoded.write(to: storageURL, options: DataProtection.atomicWriteOptions)
    }
}
