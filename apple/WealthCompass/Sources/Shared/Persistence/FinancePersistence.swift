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
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        return try decoder.decode(FinancialData.self, from: Data(contentsOf: storageURL))
    }

    func save(_ data: FinancialData) throws {
        try createStorageDirectoryIfNeeded()
        try encoder.encode(data).write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
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
}
