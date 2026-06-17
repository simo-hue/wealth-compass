import CloudKit
import CryptoKit
import Foundation
import OSLog

enum CloudSyncStatus: Equatable, Sendable {
    case disabled
    case starting
    case syncing
    case upToDate(Date?)
    case accountUnavailable(String)
    case error(String)

    var title: String {
        switch self {
        case .disabled:
            String(localized: "Off")
        case .starting:
            String(localized: "Connecting")
        case .syncing:
            String(localized: "Syncing")
        case .upToDate:
            String(localized: "Up to Date")
        case .accountUnavailable:
            String(localized: "iCloud Unavailable")
        case .error:
            String(localized: "Sync Error")
        }
    }

    var detail: String? {
        switch self {
        case .disabled:
            String(localized: "Your data remains on this device.")
        case .starting:
            String(localized: "Checking the iCloud account and preparing CloudKit.")
        case .syncing:
            String(localized: "Sending local changes and fetching updates from iCloud.")
        case .upToDate(let date):
            date.map {
                String(localized: "Last synced \($0.formatted(date: .abbreviated, time: .shortened)).")
            } ?? String(localized: "Local data is ready to sync.")
        case .accountUnavailable(let message), .error(let message):
            message
        }
    }

    var isBusy: Bool {
        self == .starting || self == .syncing
    }
}

enum CloudSyncRecordType: String, Codable, CaseIterable, Sendable {
    case transaction = "WCTransaction"
    case recurringTransaction = "WCRecurringTransaction"
    case investment = "WCInvestment"
    case crypto = "WCCryptoHolding"
    case liability = "WCLiability"
    case snapshot = "WCNetWorthSnapshot"

    fileprivate var recordNamePrefix: String {
        switch self {
        case .transaction: "transaction"
        case .recurringTransaction: "recurring"
        case .investment: "investment"
        case .crypto: "crypto"
        case .liability: "liability"
        case .snapshot: "snapshot"
        }
    }
}

struct CloudSyncRecordKey: Codable, Hashable, Sendable {
    let type: CloudSyncRecordType
    let id: UUID

    var storageKey: String {
        "\(type.recordNamePrefix):\(id.uuidString.lowercased())"
    }

    var recordName: String {
        storageKey
    }

    init(type: CloudSyncRecordType, id: UUID) {
        self.type = type
        self.id = id
    }

    init?(recordName: String) {
        let parts = recordName.split(separator: ":", maxSplits: 1).map(String.init)
        guard
            parts.count == 2,
            let type = CloudSyncRecordType.allCases.first(where: { $0.recordNamePrefix == parts[0] }),
            let id = UUID(uuidString: parts[1])
        else {
            return nil
        }
        self.init(type: type, id: id)
    }
}

struct CloudSyncRecordSnapshot: Sendable {
    let key: CloudSyncRecordKey
    let payload: Data
    let createdAt: Date
    let updatedAt: Date

    var payloadHash: String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}

struct CloudSyncRemoteMutation: Sendable {
    let key: CloudSyncRecordKey
    let payload: Data?
    let expectedPendingRevision: UUID?
}

struct CloudSyncChangeSet: Sendable {
    let changed: [CloudSyncRecordSnapshot]
    let deleted: [CloudSyncRecordKey]
    let changedAt: Date

    var isEmpty: Bool {
        changed.isEmpty && deleted.isEmpty
    }

    static func difference(
        from oldRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot],
        to newRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot],
        at date: Date = Date()
    ) -> CloudSyncChangeSet {
        let changed = newRecords.values.filter { record in
            oldRecords[record.key]?.payloadHash != record.payloadHash
        }
        let deleted = oldRecords.keys.filter { newRecords[$0] == nil }
        return CloudSyncChangeSet(changed: changed, deleted: deleted, changedAt: date)
    }
}

extension FinancialData {
    func cloudSyncRecords() throws -> [CloudSyncRecordKey: CloudSyncRecordSnapshot] {
        var records: [CloudSyncRecordKey: CloudSyncRecordSnapshot] = [:]

        func append<T: Encodable>(
            _ value: T,
            type: CloudSyncRecordType,
            id: UUID,
            createdAt: Date,
            updatedAt: Date
        ) throws {
            let key = CloudSyncRecordKey(type: type, id: id)
            records[key] = CloudSyncRecordSnapshot(
                key: key,
                payload: try FinanceJSONCoding.encode(value),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        for value in transactions {
            try append(value, type: .transaction, id: value.id, createdAt: value.createdAt, updatedAt: value.updatedAt)
        }
        for value in recurringTransactions {
            try append(
                value,
                type: .recurringTransaction,
                id: value.id,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
        }
        for value in investments {
            try append(value, type: .investment, id: value.id, createdAt: value.createdAt, updatedAt: value.updatedAt)
        }
        for value in crypto {
            try append(value, type: .crypto, id: value.id, createdAt: value.createdAt, updatedAt: value.updatedAt)
        }
        for value in liabilities {
            try append(value, type: .liability, id: value.id, createdAt: value.createdAt, updatedAt: value.updatedAt)
        }
        for value in snapshots {
            try append(value, type: .snapshot, id: value.id, createdAt: value.createdAt, updatedAt: value.updatedAt)
        }
        return records
    }

    mutating func applyCloudSyncMutations(_ mutations: [CloudSyncRemoteMutation]) throws {
        for mutation in mutations {
            switch mutation.key.type {
            case .transaction:
                transactions = try Self.applying(
                    mutation,
                    to: transactions,
                    decoding: Transaction.self
                )
            case .recurringTransaction:
                recurringTransactions = try Self.applying(
                    mutation,
                    to: recurringTransactions,
                    decoding: RecurringTransaction.self
                )
            case .investment:
                investments = try Self.applying(
                    mutation,
                    to: investments,
                    decoding: Investment.self
                )
            case .crypto:
                crypto = try Self.applying(
                    mutation,
                    to: crypto,
                    decoding: CryptoHolding.self
                )
            case .liability:
                liabilities = try Self.applying(
                    mutation,
                    to: liabilities,
                    decoding: Liability.self
                )
            case .snapshot:
                snapshots = try Self.applying(
                    mutation,
                    to: snapshots,
                    decoding: NetWorthSnapshot.self
                )
            }
        }
    }

    private static func applying<T: Codable & Identifiable>(
        _ mutation: CloudSyncRemoteMutation,
        to collection: [T],
        decoding type: T.Type
    ) throws -> [T] where T.ID == UUID {
        var updatedCollection = collection

        guard let payload = mutation.payload else {
            updatedCollection.removeAll { $0.id == mutation.key.id }
            return updatedCollection
        }

        let value = try FinanceJSONCoding.decode(type, from: payload)
        guard value.id == mutation.key.id else {
            throw CloudSyncError.invalidRecord(String(localized: "Record ID and payload ID do not match."))
        }
        if let index = updatedCollection.firstIndex(where: { $0.id == value.id }) {
            updatedCollection[index] = value
        } else {
            updatedCollection.append(value)
        }
        return updatedCollection
    }
}

private enum CloudSyncPendingOrigin: String, Codable, Sendable {
    case inventory
    case localChange
}

private enum CloudSyncPendingMutation: Codable, Equatable, Sendable {
    case save(modifiedAt: Date, revision: UUID, origin: CloudSyncPendingOrigin, allowsResurrection: Bool)
    case delete(deletedAt: Date, revision: UUID)

    var revision: UUID {
        switch self {
        case .save(_, let revision, _, _), .delete(_, let revision):
            revision
        }
    }
}

private struct CloudSyncRecordState: Codable, Sendable {
    var systemFields: Data?
    var pending: CloudSyncPendingMutation?
    var isTombstone = false
    var deletedAt: Date?
}

private struct CloudSyncMetadata: Codable, Sendable {
    var schemaVersion = 1
    var accountRecordName: String?
    var engineState: Data?
    var bootstrapCompleted = false
    var zoneReady = false
    var records: [String: CloudSyncRecordState] = [:]
    var knownLocalHashes: [String: String] = [:]
    var lastSyncAt: Date?
}

final class CloudSyncMetadataStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileManager: FileManager
    private let url: URL
    private var cached: CloudSyncMetadata

    init(
        fileManager: FileManager = .default,
        directoryName: String = "Wealth Compass",
        fileName: String = "wealth-compass-cloud-sync.json"
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        url = applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)

        if
            let data = try? Data(contentsOf: url),
            let decoded = try? FinanceJSONCoding.decode(CloudSyncMetadata.self, from: data)
        {
            cached = decoded
        } else {
            cached = CloudSyncMetadata()
        }
    }

    fileprivate func read() -> CloudSyncMetadata {
        lock.withLock { cached }
    }

    fileprivate func update<T>(_ body: (inout CloudSyncMetadata) throws -> T) throws -> T {
        try lock.withLock {
            var updated = cached
            let result = try body(&updated)
            try persist(updated)
            cached = updated
            return result
        }
    }

    func pendingRevision(for key: CloudSyncRecordKey) -> UUID? {
        read().records[key.storageKey]?.pending?.revision
    }

    func reconcileLocalInventory(_ records: [CloudSyncRecordKey: CloudSyncRecordSnapshot]) throws {
        try update { metadata in
            let hashes = Dictionary(uniqueKeysWithValues: records.map { ($0.key.storageKey, $0.value.payloadHash) })
            let now = Date()

            for record in records.values {
                let storageKey = record.key.storageKey
                guard metadata.knownLocalHashes[storageKey] != record.payloadHash else { continue }
                var state = metadata.records[storageKey] ?? CloudSyncRecordState()
                let origin: CloudSyncPendingOrigin = metadata.knownLocalHashes[storageKey] == nil
                    && !metadata.bootstrapCompleted ? .inventory : .localChange
                state.pending = .save(
                    modifiedAt: now,
                    revision: UUID(),
                    origin: origin,
                    allowsResurrection: state.isTombstone
                )
                state.isTombstone = false
                state.deletedAt = nil
                metadata.records[storageKey] = state
            }

            for storageKey in metadata.knownLocalHashes.keys where hashes[storageKey] == nil {
                guard let key = CloudSyncRecordKey(recordName: storageKey) else { continue }
                var state = metadata.records[storageKey] ?? CloudSyncRecordState()
                state.pending = .delete(deletedAt: now, revision: UUID())
                state.isTombstone = true
                state.deletedAt = now
                metadata.records[key.storageKey] = state
            }
            metadata.knownLocalHashes = hashes
        }
    }

    func recordLocalChanges(
        _ changes: CloudSyncChangeSet,
        currentRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot]
    ) throws {
        guard !changes.isEmpty else { return }
        try update { metadata in
            for record in changes.changed {
                let storageKey = record.key.storageKey
                var state = metadata.records[storageKey] ?? CloudSyncRecordState()
                state.pending = .save(
                    modifiedAt: changes.changedAt,
                    revision: UUID(),
                    origin: .localChange,
                    allowsResurrection: state.isTombstone
                )
                state.isTombstone = false
                state.deletedAt = nil
                metadata.records[storageKey] = state
            }

            for key in changes.deleted {
                let storageKey = key.storageKey
                var state = metadata.records[storageKey] ?? CloudSyncRecordState()
                state.pending = .delete(deletedAt: changes.changedAt, revision: UUID())
                state.isTombstone = true
                state.deletedAt = changes.changedAt
                metadata.records[storageKey] = state
            }

            metadata.knownLocalHashes = Dictionary(
                uniqueKeysWithValues: currentRecords.map { ($0.key.storageKey, $0.value.payloadHash) }
            )
        }
    }

    private func persist(_ metadata: CloudSyncMetadata) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try FinanceJSONCoding.encode(metadata, prettyPrinted: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

enum CloudSyncError: LocalizedError {
    case accountUnavailable(String)
    case accountChanged
    case invalidRecord(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let message), .invalidRecord(let message):
            message
        case .accountChanged:
            String(localized: "The iCloud account changed. Sync was disabled to prevent data from crossing accounts. Enable it again to sync with the current account.")
        case .notRunning:
            String(localized: "iCloud sync is not running.")
        }
    }
}

actor CloudKitSyncService: CKSyncEngineDelegate {
    typealias SnapshotProvider = @MainActor @Sendable () throws -> [CloudSyncRecordKey: CloudSyncRecordSnapshot]
    typealias RemoteMutationHandler = @MainActor @Sendable ([CloudSyncRemoteMutation]) throws -> Set<CloudSyncRecordKey>
    typealias StatusHandler = @MainActor @Sendable (CloudSyncStatus) -> Void
    typealias DisableHandler = @MainActor @Sendable () -> Void
    typealias AccountStatusProvider = @Sendable () async throws -> CKAccountStatus
    typealias UserRecordIDProvider = @Sendable () async throws -> CKRecord.ID
    typealias EngineFactory = (CKSyncEngine.Configuration) throws -> CKSyncEngine

    private static let containerIdentifier = "iCloud.com.wealthcompasstracker"
    private static let zoneName = "WealthCompassZone"
    private static let subscriptionID = "WealthCompassSyncSubscription"
    private static let schemaVersion: Int64 = 1
    private static let logger = Logger(subsystem: "com.wealthcompass.sync", category: "CloudKit")

    private let container: CKContainer
    private let database: CKDatabase
    private let metadataStore: CloudSyncMetadataStore
    private let snapshotProvider: SnapshotProvider
    private let remoteMutationHandler: RemoteMutationHandler
    private let statusHandler: StatusHandler
    private let disableHandler: DisableHandler
    private let accountStatusProvider: AccountStatusProvider
    private let userRecordIDProvider: UserRecordIDProvider
    private let engineFactory: EngineFactory
    private let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?
    private var isSynchronizing = false
    private var isStarting = false
    // CloudKit awaits and CKSyncEngine callbacks can resume after a user toggles sync.
    private var syncRequested = false
    private var lifecycleGeneration = 0

    init(
        metadataStore: CloudSyncMetadataStore,
        snapshotProvider: @escaping SnapshotProvider,
        remoteMutationHandler: @escaping RemoteMutationHandler,
        statusHandler: @escaping StatusHandler,
        disableHandler: @escaping DisableHandler,
        accountStatusProvider: AccountStatusProvider? = nil,
        userRecordIDProvider: UserRecordIDProvider? = nil,
        engineFactory: @escaping EngineFactory = { CKSyncEngine($0) }
    ) {
        let container = CKContainer(identifier: Self.containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
        self.metadataStore = metadataStore
        self.snapshotProvider = snapshotProvider
        self.remoteMutationHandler = remoteMutationHandler
        self.statusHandler = statusHandler
        self.disableHandler = disableHandler
        self.accountStatusProvider = accountStatusProvider ?? {
            try await container.accountStatus()
        }
        self.userRecordIDProvider = userRecordIDProvider ?? {
            try await container.userRecordID()
        }
        self.engineFactory = engineFactory
    }

    func start(allowAccountReplacement: Bool) async {
        syncRequested = true
        if let engine {
            await synchronize(generation: lifecycleGeneration, using: engine)
            return
        }
        guard !isStarting else {
            return
        }

        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isStarting = true
        await statusHandler(.starting)
        guard isCurrent(generation) else {
            finishStarting(generation: generation)
            return
        }

        do {
            guard try await accountStatusProvider() == .available else {
                throw CloudSyncError.accountUnavailable(
                    String(localized: "Sign in to iCloud and allow iCloud access for this app before turning on sync.")
                )
            }
            guard isCurrent(generation) else {
                finishStarting(generation: generation)
                return
            }

            let userRecordID = try await userRecordIDProvider()
            guard isCurrent(generation) else {
                finishStarting(generation: generation)
                return
            }

            let metadata = metadataStore.read()
            if
                let previousAccount = metadata.accountRecordName,
                previousAccount != userRecordID.recordName,
                !allowAccountReplacement
            {
                throw CloudSyncError.accountChanged
            }

            let currentRecords = try await snapshotProvider()
            guard isCurrent(generation) else {
                finishStarting(generation: generation)
                return
            }

            if metadata.accountRecordName != userRecordID.recordName {
                try resetMetadata(for: userRecordID.recordName)
            }
            try metadataStore.reconcileLocalInventory(currentRecords)
            let preparedMetadata = metadataStore.read()
            let stateSerialization = preparedMetadata.engineState.flatMap {
                try? FinanceJSONCoding.decode(CKSyncEngine.State.Serialization.self, from: $0)
            }
            var configuration = CKSyncEngine.Configuration(
                database: database,
                stateSerialization: stateSerialization,
                delegate: self
            )
            configuration.automaticallySync = true
            configuration.subscriptionID = Self.subscriptionID

            let engine = try engineFactory(configuration)
            guard isCurrent(generation) else {
                await engine.cancelOperations()
                finishStarting(generation: generation)
                return
            }

            self.engine = engine
            reconcileEngineState(engine)
            finishStarting(generation: generation)
            await synchronize(generation: generation, using: engine)
        } catch {
            if isCurrent(generation) {
                finishStarting(generation: generation)
                await handleStartFailure(error)
            }
        }
    }

    func stop() async {
        syncRequested = false
        isStarting = false
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let existingEngine = engine
        engine = nil
        isSynchronizing = false
        if let existingEngine {
            await existingEngine.cancelOperations()
        }
        guard lifecycleGeneration == generation, !syncRequested else { return }
        await statusHandler(.disabled)
    }

    func localChangesRecorded() async {
        guard syncRequested, let engine else { return }
        guard metadataStore.read().bootstrapCompleted else { return }
        enqueuePendingRecordChanges(on: engine)
    }

    func synchronize() async {
        guard syncRequested, let engine else { return }
        await synchronize(generation: lifecycleGeneration, using: engine)
    }

    private func synchronize(generation: Int, using engine: CKSyncEngine) async {
        guard isCurrent(generation, engine: engine), !isSynchronizing else { return }
        isSynchronizing = true
        await statusHandler(.syncing)
        defer { finishSynchronizing(generation: generation, engine: engine) }
        guard isCurrent(generation, engine: engine) else { return }

        do {
            let metadata = metadataStore.read()
            if !metadata.zoneReady {
                ensureZonePending(on: engine)
                try await engine.sendChanges()
                guard isCurrent(generation, engine: engine) else { return }
            }

            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            guard isCurrent(generation, engine: engine) else { return }

            if metadataStore.read().bootstrapCompleted {
                enqueuePendingRecordChanges(on: engine)
                try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
                guard isCurrent(generation, engine: engine) else { return }
            }

            let date = Date()
            try metadataStore.update { $0.lastSyncAt = date }
            await statusHandler(.upToDate(date))
        } catch {
            guard isCurrent(generation, engine: engine) else { return }
            await report(error)
        }
    }

    private func isCurrent(_ generation: Int, engine expectedEngine: CKSyncEngine? = nil) -> Bool {
        guard syncRequested, lifecycleGeneration == generation else { return false }
        if let expectedEngine {
            return engine === expectedEngine
        }
        return true
    }

    private func finishStarting(generation: Int) {
        guard lifecycleGeneration == generation else { return }
        isStarting = false
    }

    private func finishSynchronizing(generation: Int, engine expectedEngine: CKSyncEngine) {
        guard lifecycleGeneration == generation, engine === expectedEngine else { return }
        isSynchronizing = false
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncRequested, engine === syncEngine else { return }

        do {
            switch event {
            case .stateUpdate(let event):
                let data = try FinanceJSONCoding.encode(event.stateSerialization)
                try metadataStore.update { $0.engineState = data }

            case .accountChange(let event):
                try await handleAccountChange(event)

            case .fetchedDatabaseChanges(let event):
                try handleFetchedDatabaseChanges(event, syncEngine: syncEngine)

            case .fetchedRecordZoneChanges(let event):
                try await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)

            case .sentDatabaseChanges(let event):
                try handleSentDatabaseChanges(event, syncEngine: syncEngine)

            case .sentRecordZoneChanges(let event):
                try await handleSentRecordZoneChanges(event, syncEngine: syncEngine)

            case .didFetchChanges:
                if !metadataStore.read().bootstrapCompleted {
                    try metadataStore.update { $0.bootstrapCompleted = true }
                    enqueuePendingRecordChanges(on: syncEngine)
                }

            case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
                 .willSendChanges, .didSendChanges:
                break

            @unknown default:
                Self.logger.info("Ignoring an unknown CKSyncEngine event.")
            }
        } catch {
            guard syncRequested, engine === syncEngine else { return }
            Self.logger.error("CloudKit event handling failed: \(error.localizedDescription, privacy: .public)")
            await stopAfterFatalError(error)
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncRequested, engine === syncEngine else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self else { return nil }
            return await self.makeRecord(for: recordID, syncEngine: syncEngine)
        }
    }

    private func makeRecord(for recordID: CKRecord.ID, syncEngine: CKSyncEngine) async -> CKRecord? {
        guard syncRequested, engine === syncEngine else { return nil }
        guard recordID.zoneID == zoneID, let key = CloudSyncRecordKey(recordName: recordID.recordName) else {
            return nil
        }

        let metadata = metadataStore.read()
        guard let state = metadata.records[key.storageKey], let pending = state.pending else {
            return nil
        }

        let record = restoreRecord(from: state.systemFields, fallbackID: recordID)
        record["schemaVersion"] = Self.schemaVersion as NSNumber

        switch pending {
        case .delete(let deletedAt, let revision):
            record["isDeleted"] = true as NSNumber
            record["deletedAt"] = deletedAt as NSDate
            record["clientModifiedAt"] = deletedAt as NSDate
            record["revision"] = revision.uuidString as NSString
            record["payload"] = nil
            record["createdAt"] = nil
            record["updatedAt"] = nil

        case .save(let modifiedAt, let revision, _, _):
            guard
                let snapshot = try? await snapshotProvider()[key]
            else {
                return nil
            }
            record["isDeleted"] = false as NSNumber
            record["payload"] = snapshot.payload as NSData
            record["createdAt"] = snapshot.createdAt as NSDate
            record["updatedAt"] = snapshot.updatedAt as NSDate
            record["clientModifiedAt"] = modifiedAt as NSDate
            record["revision"] = revision.uuidString as NSString
            record["deletedAt"] = nil
        }
        return record
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) throws {
        if event.modifications.contains(where: { $0.zoneID == zoneID }) {
            try metadataStore.update { $0.zoneReady = true }
        }

        guard event.deletions.contains(where: { $0.zoneID == zoneID }) else { return }
        try metadataStore.update { metadata in
            metadata.zoneReady = false
            metadata.bootstrapCompleted = false
            metadata.engineState = nil
            for key in metadata.records.keys {
                metadata.records[key]?.systemFields = nil
                if metadata.knownLocalHashes[key] != nil {
                    metadata.records[key]?.pending = .save(
                        modifiedAt: Date(),
                        revision: UUID(),
                        origin: .inventory,
                        allowsResurrection: false
                    )
                }
            }
        }
        ensureZonePending(on: syncEngine)
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        let localRecords = try await snapshotProvider()
        let originalMetadata = metadataStore.read()
        var metadata = originalMetadata
        var mutations: [CloudSyncRemoteMutation] = []
        var pendingToRequeue = Set<CloudSyncRecordKey>()
        var touchedKeys = Set<CloudSyncRecordKey>()

        for modification in event.modifications where modification.record.recordID.zoneID == zoneID {
            let record = modification.record
            guard
                let key = CloudSyncRecordKey(recordName: record.recordID.recordName),
                record.recordType == key.type.rawValue
            else {
                continue
            }
            touchedKeys.insert(key)

            var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
            state.systemFields = encodeSystemFields(record)
            let remoteIsDeleted = (record["isDeleted"] as? NSNumber)?.boolValue ?? false
            let localSnapshot = localRecords[key]

            if remoteIsDeleted {
                let shouldKeepLocalSave: Bool
                if case .save(_, _, _, let allowsResurrection)? = state.pending {
                    shouldKeepLocalSave = allowsResurrection
                } else {
                    shouldKeepLocalSave = false
                }

                if shouldKeepLocalSave {
                    state.isTombstone = false
                    pendingToRequeue.insert(key)
                } else {
                    state.pending = nil
                    state.isTombstone = true
                    state.deletedAt = record["deletedAt"] as? Date ?? record.modificationDate ?? Date()
                    metadata.knownLocalHashes.removeValue(forKey: key.storageKey)
                    mutations.append(
                        CloudSyncRemoteMutation(
                            key: key,
                            payload: nil,
                            expectedPendingRevision: originalMetadata.records[key.storageKey]?.pending?.revision
                        )
                    )
                }
                metadata.records[key.storageKey] = state
                continue
            }

            guard let payload = record["payload"] as? Data else {
                throw CloudSyncError.invalidRecord(String(localized: "CloudKit record \(record.recordID.recordName) has no payload."))
            }
            let remoteSnapshot = CloudSyncRecordSnapshot(
                key: key,
                payload: payload,
                createdAt: record["createdAt"] as? Date ?? Date.distantPast,
                updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date.distantPast
            )

            if metadata.bootstrapCompleted {
                if state.pending != nil {
                    pendingToRequeue.insert(key)
                } else {
                    state.isTombstone = false
                    state.deletedAt = nil
                    metadata.knownLocalHashes[key.storageKey] = remoteSnapshot.payloadHash
                    mutations.append(
                        CloudSyncRemoteMutation(
                            key: key,
                            payload: payload,
                            expectedPendingRevision: originalMetadata.records[key.storageKey]?.pending?.revision
                        )
                    )
                }
            } else {
                let decision = bootstrapDecision(
                    pending: state.pending,
                    local: localSnapshot,
                    remote: remoteSnapshot
                )
                switch decision {
                case .local:
                    pendingToRequeue.insert(key)
                case .remote:
                    state.pending = nil
                    state.isTombstone = false
                    state.deletedAt = nil
                    metadata.knownLocalHashes[key.storageKey] = remoteSnapshot.payloadHash
                    mutations.append(
                        CloudSyncRemoteMutation(
                            key: key,
                            payload: payload,
                            expectedPendingRevision: originalMetadata.records[key.storageKey]?.pending?.revision
                        )
                    )
                case .identical:
                    state.pending = nil
                    state.isTombstone = false
                    state.deletedAt = nil
                    metadata.knownLocalHashes[key.storageKey] = remoteSnapshot.payloadHash
                }
            }
            metadata.records[key.storageKey] = state
        }

        for deletion in event.deletions where deletion.recordID.zoneID == zoneID {
            guard let key = CloudSyncRecordKey(recordName: deletion.recordID.recordName) else { continue }
            touchedKeys.insert(key)
            var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
            state.systemFields = nil
            state.pending = nil
            state.isTombstone = true
            state.deletedAt = Date()
            metadata.records[key.storageKey] = state
            metadata.knownLocalHashes.removeValue(forKey: key.storageKey)
            mutations.append(
                CloudSyncRemoteMutation(
                    key: key,
                    payload: nil,
                    expectedPendingRevision: originalMetadata.records[key.storageKey]?.pending?.revision
                )
            )
        }

        let appliedMutationKeys = mutations.isEmpty
            ? Set<CloudSyncRecordKey>()
            : try await remoteMutationHandler(mutations)
        let mutationKeys = Set(mutations.map(\.key))

        try metadataStore.update { currentMetadata in
            for key in touchedKeys {
                let storageKey = key.storageKey
                guard let plannedState = metadata.records[storageKey] else { continue }

                let expectedRevision = originalMetadata.records[storageKey]?.pending?.revision
                let currentRevision = currentMetadata.records[storageKey]?.pending?.revision
                let mutationWasApplied = !mutationKeys.contains(key) || appliedMutationKeys.contains(key)

                guard currentRevision == expectedRevision, mutationWasApplied else {
                    var currentState = currentMetadata.records[storageKey] ?? CloudSyncRecordState()
                    currentState.systemFields = plannedState.systemFields
                    currentMetadata.records[storageKey] = currentState
                    if currentState.pending != nil {
                        pendingToRequeue.insert(key)
                    }
                    continue
                }

                currentMetadata.records[storageKey] = plannedState
                if let hash = metadata.knownLocalHashes[storageKey] {
                    currentMetadata.knownLocalHashes[storageKey] = hash
                } else {
                    currentMetadata.knownLocalHashes.removeValue(forKey: storageKey)
                }
            }
        }
        enqueue(keys: Array(pendingToRequeue), on: syncEngine)
    }

    private func handleSentDatabaseChanges(
        _ event: CKSyncEngine.Event.SentDatabaseChanges,
        syncEngine: CKSyncEngine
    ) throws {
        if event.savedZones.contains(where: { $0.zoneID == zoneID }) {
            try metadataStore.update { $0.zoneReady = true }
        }

        for failure in event.failedZoneSaves where failure.zone.zoneID == zoneID {
            if isRetryable(failure.error) {
                ensureZonePending(on: syncEngine)
            } else {
                throw failure.error
            }
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        var pendingToRequeue = Set<CloudSyncRecordKey>()
        try metadataStore.update { metadata in
            for record in event.savedRecords where record.recordID.zoneID == zoneID {
                guard let key = CloudSyncRecordKey(recordName: record.recordID.recordName) else { continue }
                var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
                state.systemFields = encodeSystemFields(record)
                let savedRevision = recordRevision(record)

                if state.pending?.revision == savedRevision {
                    state.pending = nil
                    state.isTombstone = (record["isDeleted"] as? NSNumber)?.boolValue ?? false
                    state.deletedAt = record["deletedAt"] as? Date
                } else if state.pending == nil {
                    state.isTombstone = (record["isDeleted"] as? NSNumber)?.boolValue ?? false
                    state.deletedAt = record["deletedAt"] as? Date
                } else {
                    pendingToRequeue.insert(key)
                }
                metadata.records[key.storageKey] = state
            }
        }
        enqueue(keys: Array(pendingToRequeue), on: syncEngine)

        for failure in event.failedRecordSaves where failure.record.recordID.zoneID == zoneID {
            guard let key = CloudSyncRecordKey(recordName: failure.record.recordID.recordName) else { continue }
            let currentRevision = metadataStore.pendingRevision(for: key)
            if let failedRevision = recordRevision(failure.record), currentRevision != failedRevision {
                enqueue(keys: [key], on: syncEngine)
                continue
            }

            if failure.error.code == .serverRecordChanged,
               let serverRecord = failure.error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                try await resolveServerConflict(
                    for: key,
                    expectedPendingRevision: currentRevision,
                    serverRecord: serverRecord,
                    syncEngine: syncEngine
                )
            } else if failure.error.code == .zoneNotFound {
                try metadataStore.update { $0.zoneReady = false }
                ensureZonePending(on: syncEngine)
                enqueue(keys: [key], on: syncEngine)
            } else if isRetryable(failure.error) {
                enqueue(keys: [key], on: syncEngine)
            } else {
                throw failure.error
            }
        }
    }

    private func resolveServerConflict(
        for key: CloudSyncRecordKey,
        expectedPendingRevision: UUID?,
        serverRecord: CKRecord,
        syncEngine: CKSyncEngine
    ) async throws {
        let serverIsDeleted = (serverRecord["isDeleted"] as? NSNumber)?.boolValue ?? false
        var shouldApplyServerDelete = false
        var shouldRequeue = false
        let serverDeletedAt = serverRecord["deletedAt"] as? Date
            ?? serverRecord.modificationDate
            ?? Date()

        try metadataStore.update { metadata in
            var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
            state.systemFields = encodeSystemFields(serverRecord)

            guard state.pending?.revision == expectedPendingRevision else {
                metadata.records[key.storageKey] = state
                shouldRequeue = state.pending != nil
                return
            }

            if serverIsDeleted {
                if case .save(_, _, _, let allowsResurrection)? = state.pending, allowsResurrection {
                    shouldRequeue = true
                } else {
                    shouldApplyServerDelete = true
                }
            } else {
                shouldRequeue = state.pending != nil
            }
            metadata.records[key.storageKey] = state
        }

        if shouldRequeue {
            enqueue(keys: [key], on: syncEngine)
            return
        }

        if shouldApplyServerDelete {
            let appliedKeys = try await remoteMutationHandler([
                CloudSyncRemoteMutation(
                    key: key,
                    payload: nil,
                    expectedPendingRevision: expectedPendingRevision
                )
            ])

            guard appliedKeys.contains(key) else {
                enqueue(keys: [key], on: syncEngine)
                return
            }

            var newerChangeNeedsRequeue = false
            try metadataStore.update { metadata in
                var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
                guard state.pending?.revision == expectedPendingRevision else {
                    newerChangeNeedsRequeue = state.pending != nil
                    return
                }
                state.pending = nil
                state.isTombstone = true
                state.deletedAt = serverDeletedAt
                metadata.records[key.storageKey] = state
                metadata.knownLocalHashes.removeValue(forKey: key.storageKey)
            }
            if newerChangeNeedsRequeue {
                enqueue(keys: [key], on: syncEngine)
            }
        } else {
            enqueue(keys: [key], on: syncEngine)
        }
    }

    private enum BootstrapDecision {
        case local
        case remote
        case identical
    }

    private func bootstrapDecision(
        pending: CloudSyncPendingMutation?,
        local: CloudSyncRecordSnapshot?,
        remote: CloudSyncRecordSnapshot
    ) -> BootstrapDecision {
        guard let local else { return .remote }
        if local.payloadHash == remote.payloadHash {
            return .identical
        }

        switch pending {
        case .delete:
            return .local
        case .save(_, _, .localChange, _):
            return .local
        case .save(_, _, .inventory, _), nil:
            if local.updatedAt != remote.updatedAt {
                return local.updatedAt > remote.updatedAt ? .local : .remote
            }
            return local.payloadHash > remote.payloadHash ? .local : .remote
        }
    }

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async throws {
        switch event.changeType {
        case .signIn(let currentUser):
            let expectedAccount = metadataStore.read().accountRecordName
            guard expectedAccount == nil || expectedAccount == currentUser.recordName else {
                throw CloudSyncError.accountChanged
            }
        case .signOut, .switchAccounts:
            throw CloudSyncError.accountChanged
        @unknown default:
            throw CloudSyncError.accountChanged
        }
    }

    private func resetMetadata(for accountRecordName: String) throws {
        try metadataStore.update { metadata in
            metadata = CloudSyncMetadata(accountRecordName: accountRecordName)
        }
    }

    private func reconcileEngineState(_ engine: CKSyncEngine) {
        let metadata = metadataStore.read()
        let validPending = Set(metadata.records.compactMap { storageKey, state -> CKRecord.ID? in
            guard state.pending != nil, let key = CloudSyncRecordKey(recordName: storageKey) else { return nil }
            return recordID(for: key)
        })
        let stale = engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let recordID), .deleteRecord(let recordID):
                !validPending.contains(recordID)
            @unknown default:
                true
            }
        }
        engine.state.remove(pendingRecordZoneChanges: stale)

        if !metadata.zoneReady {
            ensureZonePending(on: engine)
        }
        if metadata.bootstrapCompleted {
            enqueuePendingRecordChanges(on: engine)
        }
    }

    private func ensureZonePending(on engine: CKSyncEngine) {
        let zone = CKRecordZone(zoneID: zoneID)
        let change = CKSyncEngine.PendingDatabaseChange.saveZone(zone)
        if !engine.state.pendingDatabaseChanges.contains(change) {
            engine.state.add(pendingDatabaseChanges: [change])
        }
    }

    private func enqueuePendingRecordChanges(on engine: CKSyncEngine) {
        let keys = metadataStore.read().records.compactMap { storageKey, state in
            state.pending == nil ? nil : CloudSyncRecordKey(recordName: storageKey)
        }
        enqueue(keys: keys, on: engine)
    }

    private func enqueue(keys: [CloudSyncRecordKey], on engine: CKSyncEngine) {
        let existing = Set(engine.state.pendingRecordZoneChanges)
        let changes = keys
            .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
            .filter { !existing.contains($0) }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    private func recordID(for key: CloudSyncRecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.recordName, zoneID: zoneID)
    }

    private func restoreRecord(from systemFields: Data?, fallbackID: CKRecord.ID) -> CKRecord {
        guard
            let systemFields,
            let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: systemFields)
        else {
            let key = CloudSyncRecordKey(recordName: fallbackID.recordName)
            return CKRecord(recordType: key?.type.rawValue ?? "WCUnknown", recordID: fallbackID)
        }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
            ?? CKRecord(
                recordType: CloudSyncRecordKey(recordName: fallbackID.recordName)?.type.rawValue ?? "WCUnknown",
                recordID: fallbackID
            )
    }

    private func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func recordRevision(_ record: CKRecord) -> UUID? {
        guard let value = record["revision"] as? String else { return nil }
        return UUID(uuidString: value)
    }

    private func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .resultsTruncated, .batchRequestFailed:
            true
        default:
            false
        }
    }

    private func handleStartFailure(_ error: Error) async {
        if case CloudSyncError.accountChanged = error {
            await disableHandler()
        }
        await report(error)
    }

    private func stopAfterFatalError(_ error: Error) async {
        syncRequested = false
        isStarting = false
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let existingEngine = engine
        engine = nil
        if case CloudSyncError.accountChanged = error {
            await disableHandler()
        }
        isSynchronizing = false
        if let existingEngine {
            await existingEngine.cancelOperations()
        }
        guard lifecycleGeneration == generation, !syncRequested else { return }
        await report(error)
    }

    private func report(_ error: Error) async {
        Self.logger.error("CloudKit sync error: \(error.localizedDescription, privacy: .public)")
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated:
                await statusHandler(.accountUnavailable(String(localized: "Sign in to iCloud to continue syncing.")))
            case .networkUnavailable, .networkFailure:
                await statusHandler(.error(String(localized: "The network is unavailable. Local changes are saved and will retry automatically.")))
            case .quotaExceeded:
                await statusHandler(.error(String(localized: "The iCloud account does not have enough available storage.")))
            default:
                await statusHandler(.error(cloudError.localizedDescription))
            }
        } else if case CloudSyncError.accountUnavailable(let message) = error {
            await statusHandler(.accountUnavailable(message))
        } else {
            await statusHandler(.error(error.localizedDescription))
        }
    }
}
