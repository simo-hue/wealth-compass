import Foundation

protocol FinancePersistence {
    var locationDescription: String { get }

    func load() throws -> FinancialData?
    func save(_ data: FinancialData) throws
    func clear() throws
    func forceICloudSync() throws -> FinancialData?
}

struct LocalFinancePersistence: FinancePersistence {
    private let fileManager: FileManager
    private let storageURL: URL
    private let legacyStorageURLs: [URL]
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> FinancialData? {
        try migrateLegacyFileIfNeeded()
        
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
        if isICloudSyncEnabled {
            try syncFromICloudIfNeeded()
        }
        
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        return try decoder.decode(FinancialData.self, from: Data(contentsOf: storageURL))
    }

    func save(_ data: FinancialData) throws {
        try createStorageDirectoryIfNeeded()
        try encoder.encode(data).write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
        if isICloudSyncEnabled {
            try syncToICloud()
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        try fileManager.removeItem(at: storageURL)
    }

    func forceICloudSync() throws -> FinancialData? {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
        guard isICloudSyncEnabled, let iCloudURL = getICloudURL() else { return try load() }
        
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        
        // Coordinate reading without .withoutChanges to force a synchronous download
        coordinator.coordinate(readingItemAt: iCloudURL, options: [], error: &coordinationError) { _ in }
        
        if let error = coordinationError {
            throw error
        }
        
        try syncFromICloudIfNeeded()
        try syncToICloud()
        
        return try load()
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

    private func getICloudURL() -> URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let dataURL = containerURL.appendingPathComponent("Data")
        if !fileManager.fileExists(atPath: dataURL.path) {
            try? fileManager.createDirectory(at: dataURL, withIntermediateDirectories: true)
        }
        return dataURL.appendingPathComponent(fileName)
    }

    private func syncFromICloudIfNeeded() throws {
        guard let iCloudURL = getICloudURL() else { return }
        
        do {
            let values = try iCloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                try fileManager.startDownloadingUbiquitousItem(at: iCloudURL)
                return
            }
        } catch {
            // Ignore if file doesn't exist or is not ubiquitous yet
        }
        
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        
        coordinator.coordinate(readingItemAt: iCloudURL, options: .withoutChanges, error: &coordinationError) { url in
            do {
                guard self.fileManager.fileExists(atPath: url.path) else { return }
                
                let localExists = self.fileManager.fileExists(atPath: self.storageURL.path)
                
                if localExists {
                    let localAttrs = try self.fileManager.attributesOfItem(atPath: self.storageURL.path)
                    let iCloudAttrs = try self.fileManager.attributesOfItem(atPath: url.path)
                    
                    if let localDate = localAttrs[.modificationDate] as? Date,
                       let iCloudDate = iCloudAttrs[.modificationDate] as? Date {
                        // If iCloud file is newer, copy to temp and replace safely
                        if iCloudDate > localDate {
                            let tempURL = self.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try self.fileManager.copyItem(at: url, to: tempURL)
                            _ = try self.fileManager.replaceItemAt(self.storageURL, withItemAt: tempURL)
                        }
                    }
                } else {
                    // Local file doesn't exist, but iCloud does, copy it
                    try self.createStorageDirectoryIfNeeded()
                    try self.fileManager.copyItem(at: url, to: self.storageURL)
                }
            } catch {
                readError = error
            }
        }
        
        if let error = readError ?? coordinationError {
            throw error
        }
    }

    private func syncToICloud() throws {
        guard let iCloudURL = getICloudURL(), fileManager.fileExists(atPath: storageURL.path) else { return }
        
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        
        coordinator.coordinate(writingItemAt: iCloudURL, options: .forReplacing, error: &coordinationError) { url in
            do {
                let data = try Data(contentsOf: self.storageURL)
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        
        if let error = writeError ?? coordinationError {
            throw error
        }
    }
}
