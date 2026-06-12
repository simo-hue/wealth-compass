import Foundation

protocol ExchangeRatePersistence {
    func load() -> ExchangeRateSnapshot?
    func save(_ snapshot: ExchangeRateSnapshot)
}

struct LocalExchangeRatePersistence: ExchangeRatePersistence {
    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        directoryName: String = "Wealth Compass",
        fileName: String = "exchange-rates.json"
    ) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        storageURL = applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func load() -> ExchangeRateSnapshot? {
        migrateFromUserDefaultsIfNeeded()

        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        guard let snapshot = try? decoder.decode(ExchangeRateSnapshot.self, from: data),
              snapshot.isValid else { return nil }
        return snapshot
    }

    func save(_ snapshot: ExchangeRateSnapshot) {
        createStorageDirectoryIfNeeded()
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    // MARK: - Migration

    /// One-time migration from the legacy UserDefaults-based storage to file-based.
    /// Reads the old key, writes the snapshot to file, then removes the UserDefaults entry.
    private func migrateFromUserDefaultsIfNeeded() {
        guard !fileManager.fileExists(atPath: storageURL.path) else { return }

        let legacyKey = "wc_mobile_exchange_rate_snapshot"
        guard let legacyData = UserDefaults.standard.data(forKey: legacyKey) else { return }
        guard let snapshot = try? decoder.decode(ExchangeRateSnapshot.self, from: legacyData),
              snapshot.isValid else {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }

        createStorageDirectoryIfNeeded()
        try? legacyData.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private func createStorageDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
