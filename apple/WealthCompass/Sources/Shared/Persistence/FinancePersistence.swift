import Foundation

protocol FinancePersistence: Sendable {
    var locationDescription: String { get }

    func load() throws -> FinancialData?
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

    func load() throws -> FinancialData? {
        try migrateLegacyFileIfNeeded()
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let sourceData = try Data(contentsOf: storageURL)
        let decoded = try FinanceJSONCoding.decodeFinancialData(from: sourceData)
        if decoded.wasMigrated {
            try createMigrationBackupIfNeeded(sourceData)
            try write(decoded.data)
        }
        return decoded.data
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
        try fileManager.copyItem(at: legacyURL, to: storageURL)
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
