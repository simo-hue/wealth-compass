import Foundation
import OSLog

protocol ExchangeRatePersistence {
    func load() -> ExchangeRateSnapshot?
    func save(_ snapshot: ExchangeRateSnapshot)
    func clear()
}

struct LocalExchangeRatePersistence: ExchangeRatePersistence {
    private static let logger = Logger(subsystem: "com.wealthcompass.persistence", category: "ExchangeRates")
    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        directoryName: String = "Wealth Compass Tracker",
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
        // WC-LOCK1: separate "couldn't read it" from "read it and it's junk". The two used to
        // share one `clear()`, so a locked-device read denial *deleted* a perfectly good rate
        // cache — the same conflation that wiped sync metadata, with milder consequences.
        let data: Data
        do {
            data = try Data(contentsOf: storageURL)
        } catch {
            Self.logger.error("Could not read cached exchange rates (leaving the file intact): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // WC-LOCK1: a successful read proves the file is accessible right now, so re-stamp a cache
        // created under the old, stricter class. Without this an existing install keeps failing to
        // read its rates on every locked launch and falls back to the bundled offline table.
        DataProtection.upgradeProtectionClass(at: storageURL, fileManager: fileManager)

        guard let snapshot = try? decoder.decode(ExchangeRateSnapshot.self, from: data),
              snapshot.isValid else {
            // Genuinely corrupt or expired: clearing is right and is what unblocks the legacy
            // migration below (gated on `!fileExists`), which would otherwise never run again
            // (deep-audit L29).
            Self.logger.error("Discarding invalid cached exchange rates")
            clear()
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: ExchangeRateSnapshot) {
        createStorageDirectoryIfNeeded()
        // WC-L27: log instead of silently swallowing — a failed write means stale FX rates.
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: DataProtection.atomicWriteOptions)
        } catch {
            Self.logger.error("Failed to persist exchange-rate snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the cached rate file so a factory reset leaves no snapshot behind. The next
    /// launch falls back to the bundled offline rates until a fresh fetch succeeds.
    func clear() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        // WC-L27: a silently-failing clear would leave a stale rate cache after a factory reset.
        do {
            try fileManager.removeItem(at: storageURL)
        } catch {
            Self.logger.error("Failed to clear cached exchange rates on reset: \(error.localizedDescription, privacy: .public)")
        }
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
        // WC-L27: only drop the legacy key once the file write succeeded, and log failures
        // rather than losing the legacy snapshot silently.
        do {
            try legacyData.write(to: storageURL, options: DataProtection.atomicWriteOptions)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } catch {
            Self.logger.error("Failed to migrate legacy exchange rates: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createStorageDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
