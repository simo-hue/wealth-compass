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
        directoryName: String = "Wealth Compass",
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
            try createMigrationBackupIfNeeded(sourceData)
            try write(decoded.data)
        }
        return FinancePersistenceLoad(data: decoded.data, skippedRecordKeys: decoded.skippedRecordKeys)
    }

    func save(_ data: FinancialData) throws {
        try createStorageDirectoryIfNeeded()
        try write(data)
    }

    func clear() throws {
        // Also remove the one-time pre-CloudKit migration backup: it is a verbatim copy of
        // the user's finance data, so a "real and complete" erase must not leave it behind.
        let backupURL = storageURL.appendingPathExtension("pre-cloudkit-backup")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        try fileManager.removeItem(at: storageURL)
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
        try legacyData.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func createMigrationBackupIfNeeded(_ sourceData: Data) throws {
        let backupURL = storageURL.appendingPathExtension("pre-cloudkit-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try sourceData.write(to: backupURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func write(_ data: FinancialData) throws {
        let encoded = try FinanceJSONCoding.encode(data, prettyPrinted: true)
        try encoded.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
