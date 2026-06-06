import Foundation

protocol FinancePersistence {
    var locationDescription: String { get }

    func load() throws -> FinancialData?
    func save(_ data: FinancialData) throws
    func clear() throws
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
        let documentsURL = containerURL.appendingPathComponent("Documents")
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
        return documentsURL.appendingPathComponent(fileName)
    }

    private func syncFromICloudIfNeeded() throws {
        guard let iCloudURL = getICloudURL(), fileManager.fileExists(atPath: iCloudURL.path) else { return }
        
        let localExists = fileManager.fileExists(atPath: storageURL.path)
        
        if localExists {
            let localAttrs = try fileManager.attributesOfItem(atPath: storageURL.path)
            let iCloudAttrs = try fileManager.attributesOfItem(atPath: iCloudURL.path)
            
            if let localDate = localAttrs[.modificationDate] as? Date,
               let iCloudDate = iCloudAttrs[.modificationDate] as? Date {
                // If iCloud file is newer, copy it over the local file
                if iCloudDate > localDate {
                    try? fileManager.removeItem(at: storageURL)
                    try fileManager.copyItem(at: iCloudURL, to: storageURL)
                }
            }
        } else {
            // Local file doesn't exist, but iCloud does, copy it
            try createStorageDirectoryIfNeeded()
            try fileManager.copyItem(at: iCloudURL, to: storageURL)
        }
    }

    private func syncToICloud() throws {
        guard let iCloudURL = getICloudURL(), fileManager.fileExists(atPath: storageURL.path) else { return }
        
        // Remove existing iCloud file if needed
        if fileManager.fileExists(atPath: iCloudURL.path) {
            try? fileManager.removeItem(at: iCloudURL)
        }
        try fileManager.copyItem(at: storageURL, to: iCloudURL)
    }
}
