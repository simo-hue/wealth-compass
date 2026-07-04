import CloudKit
import CryptoKit
import Foundation
import OSLog
import SwiftUI

enum CloudSyncStatus: Equatable, Sendable {
    case disabled
    case starting
    case syncing
    case upToDate(Date?)
    case waiting(String)          // transient & self-resolving (offline, throttled, preparing)
    case accountUnavailable(String) // not signed in to iCloud
    case actionNeeded(String)     // persistent, the user must act (storage full, restricted, account changed)
    case error(String)            // unexpected failure

    var title: LocalizedStringKey {
        switch self {
        case .disabled:
            "Off"
        case .starting:
            "Connecting"
        case .syncing:
            "Syncing"
        case .upToDate:
            "Up to Date"
        case .waiting:
            "Waiting to Sync"
        case .accountUnavailable:
            "iCloud Unavailable"
        case .actionNeeded:
            "Action Needed"
        case .error:
            "Sync Error"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .disabled:
            AppLocalization.string("Off", appLanguage: appLanguage)
        case .starting:
            AppLocalization.string("Connecting", appLanguage: appLanguage)
        case .syncing:
            AppLocalization.string("Syncing", appLanguage: appLanguage)
        case .upToDate:
            AppLocalization.string("Up to Date", appLanguage: appLanguage)
        case .waiting:
            AppLocalization.string("Waiting to Sync", appLanguage: appLanguage)
        case .accountUnavailable:
            AppLocalization.string("iCloud Unavailable", appLanguage: appLanguage)
        case .actionNeeded:
            AppLocalization.string("Action Needed", appLanguage: appLanguage)
        case .error:
            AppLocalization.string("Sync Error", appLanguage: appLanguage)
        }
    }

    var detail: String? {
        localizedDetail(appLanguage: nil)
    }

    func localizedDetail(appLanguage: String?) -> String? {
        switch self {
        case .disabled:
            AppLocalization.string("Your data remains on this device.", appLanguage: appLanguage)
        case .starting:
            AppLocalization.string("Checking the iCloud account and preparing CloudKit.", appLanguage: appLanguage)
        case .syncing:
            AppLocalization.string("Sending local changes and fetching updates from iCloud.", appLanguage: appLanguage)
        case .upToDate(let date):
            date.map {
                AppLocalization.string("Last synced \($0.formatted(date: .abbreviated, time: .shortened)).", appLanguage: appLanguage)
            } ?? AppLocalization.string("Local data is ready to sync.", appLanguage: appLanguage)
        case .waiting(let message), .accountUnavailable(let message), .actionNeeded(let message), .error(let message):
            AppLocalization.string(String.LocalizationValue(message), appLanguage: appLanguage)
        }
    }

    var isBusy: Bool {
        self == .starting || self == .syncing
    }

    enum Severity: Equatable, Sendable { case ok, info, attention, error }

    /// Visual severity for color + icon. Transient states (`.waiting`) are `.info` — calm and
    /// neutral, never red: being offline or throttled is normal operation, not a failure.
    var severity: Severity {
        switch self {
        case .disabled, .upToDate: .ok
        case .starting, .syncing, .waiting: .info
        case .accountUnavailable, .actionNeeded: .attention
        case .error: .error
        }
    }

    /// Tint for the status row's icon / title / detail, derived from `severity`.
    var tint: Color {
        switch severity {
        case .ok, .info: WCColor.textSecondary
        case .attention: WCColor.warning
        case .error: WCColor.destructive
        }
    }

    /// SF Symbol for the status row.
    var symbolName: String {
        switch self {
        case .disabled: "icloud.slash"
        case .starting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .waiting: "icloud"
        case .accountUnavailable, .actionNeeded: "exclamationmark.icloud"
        case .error: "xmark.icloud"
        }
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

    /// The result of applying a batch of remote mutations: the keys that were applied, and
    /// the keys that were skipped because their payload couldn't be decoded or its embedded
    /// id didn't match the record key (WC-H3). Skipping — rather than throwing — quarantines
    /// a single forward-incompatible / corrupt record so one bad record can't tear down the
    /// whole sync engine. The caller logs `skipped` and treats only `appliedKeys` as applied,
    /// so a skipped record's metadata is never advanced (no spurious tombstone).
    struct RemoteMutationOutcome {
        var appliedKeys: Set<CloudSyncRecordKey> = []
        var skipped: [(key: CloudSyncRecordKey, error: Error)] = []
    }

    @discardableResult
    mutating func applyCloudSyncMutations(_ mutations: [CloudSyncRemoteMutation]) -> RemoteMutationOutcome {
        var outcome = RemoteMutationOutcome()
        for mutation in mutations {
            do {
                switch mutation.key.type {
                case .transaction:
                    transactions = try Self.applying(mutation, to: transactions, decoding: Transaction.self)
                case .recurringTransaction:
                    recurringTransactions = try Self.applying(mutation, to: recurringTransactions, decoding: RecurringTransaction.self)
                case .investment:
                    investments = try Self.applying(mutation, to: investments, decoding: Investment.self)
                case .crypto:
                    crypto = try Self.applying(mutation, to: crypto, decoding: CryptoHolding.self)
                case .liability:
                    liabilities = try Self.applying(mutation, to: liabilities, decoding: Liability.self)
                case .snapshot:
                    snapshots = try Self.applying(mutation, to: snapshots, decoding: NetWorthSnapshot.self)
                }
                outcome.appliedKeys.insert(mutation.key)
            } catch {
                // WC-H3: quarantine one undecodable / id-mismatched record instead of
                // throwing. `applying` builds a new collection and only assigns it on
                // success, so a throw here leaves this entity's collection untouched and the
                // rest of the batch still applies. Excluding the key from `appliedKeys` means
                // the caller never advances its `knownLocalHashes` (no spurious tombstone),
                // mirroring the existing payloadless `remoteSnapshot(...)` nil-skip.
                outcome.skipped.append((mutation.key, error))
            }
        }
        return outcome
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
            throw CloudSyncError.invalidRecord("Record ID and payload ID do not match.")
        }
        if let index = updatedCollection.firstIndex(where: { $0.id == value.id }) {
            updatedCollection[index] = value
        } else {
            updatedCollection.append(value)
        }
        return updatedCollection
    }
}

enum CloudSyncPendingOrigin: String, Codable, Sendable {
    case inventory
    case localChange
}

enum CloudSyncPendingMutation: Codable, Equatable, Sendable {
    case save(modifiedAt: Date, revision: UUID, origin: CloudSyncPendingOrigin, allowsResurrection: Bool)
    case delete(deletedAt: Date, revision: UUID)

    var revision: UUID {
        switch self {
        case .save(_, let revision, _, _), .delete(_, let revision):
            revision
        }
    }
}

struct CloudSyncRecordState: Codable, Sendable {
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
    /// Guards the in-memory `cached` value only. Held briefly for reads and for the in-memory
    /// portion of an update — never across a disk write (WC-M3), so `read()` (called on the
    /// hot CloudKitSyncService actor path) never blocks on I/O.
    private let dataLock = NSLock()
    /// Serializes the full-file disk writes in `persist`/`reset`, outside the `dataLock`
    /// critical section. `update` takes this before releasing `dataLock` (hand-over-hand), so
    /// writes land in the same order as the in-memory updates without holding `dataLock`
    /// across the write.
    private let writeLock = NSLock()
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
        dataLock.withLock { cached }
    }

    fileprivate func update<T>(_ body: (inout CloudSyncMetadata) throws -> T) throws -> T {
        dataLock.lock()
        var updated = cached
        let result: T
        do {
            result = try body(&updated)
        } catch {
            dataLock.unlock()
            throw error
        }
        // Compact fully-settled tombstones so the metadata file doesn't accumulate dead per-record
        // entries (#12) — safe because entity ids are one-shot UUIDs (a pruned id never returns).
        updated.records = CloudKitSyncService.pruningSettledTombstones(
            from: updated.records,
            knownLocalHashes: updated.knownLocalHashes
        )
        cached = updated
        // Hand-over-hand: take `writeLock` before releasing `dataLock` so concurrent updates
        // persist in the same order they committed in memory, then release `dataLock` so the
        // disk write happens outside its critical section (WC-M3). A persist failure throws
        // (surfaced by WC-M2 as a transient, non-fatal error); the in-memory value is already
        // committed and the next successful update re-persists it.
        writeLock.lock()
        dataLock.unlock()
        defer { writeLock.unlock() }
        try persist(updated)
        return result
    }

    /// Wipes all sync metadata back to a clean slate (no account, no engine state, no
    /// per-record state) and removes the backing file. Used by the factory reset — both
    /// after a zone delete and as the safety net on the local-only / escape-hatch paths
    /// where the zone delete didn't run.
    func reset() throws {
        dataLock.lock()
        cached = CloudSyncMetadata()
        // Same hand-over-hand discipline as `update`: wipe the in-memory value under
        // `dataLock`, then remove the file under `writeLock` (serialized with persists) so a
        // concurrent write can't race the removal, all without holding `dataLock` across I/O.
        writeLock.lock()
        dataLock.unlock()
        defer { writeLock.unlock() }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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
        let interval = SyncSignpost.sync.begin("metadata")
        let start = DispatchTime.now()
        defer { SyncSignpost.sync.end("metadata", interval) }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // No pretty-printing in production: the metadata file is rewritten on many events, so the
        // whitespace was pure I/O overhead (#12).
        let data = try FinanceJSONCoding.encode(metadata, prettyPrinted: false)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        SyncSignpost.sync.emit("metadata records=\(metadata.records.count) bytes=\(data.count) ms=\(SyncSignpost.sync.ms(since: start))")
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
    /// A sync attempt failed for a non-account reason (network, quota, throttling, …).
    /// Carries an already-resolved, user-meaningful message produced by
    /// `CloudKitSyncService.syncStatus(for:)`, so `forceICloudSync()` no longer has to
    /// mislabel these as `invalidRecord` (#14).
    case syncFailed(String)
    case notRunning

    var errorDescription: String? {
        localizedDescription(appLanguage: nil)
    }

    func localizedDescription(appLanguage: String?) -> String {
        switch self {
        case .accountUnavailable(let message), .invalidRecord(let message), .syncFailed(let message):
            AppLocalization.string(String.LocalizationValue(message), appLanguage: appLanguage)
        case .accountChanged:
            AppLocalization.string(
                "The iCloud account changed. Sync was disabled to prevent data from crossing accounts. Enable it again to sync with the current account.",
                appLanguage: appLanguage
            )
        case .notRunning:
            AppLocalization.string("iCloud sync is not running.", appLanguage: appLanguage)
        }
    }

    /// Title for a Force Sync failure alert in Settings: account problems read as
    /// "iCloud Unavailable"; every other failure as "Sync Failed". Lives on the error so
    /// both platforms' Settings screens pick the same title (#14).
    var alertTitleKey: String.LocalizationValue {
        switch self {
        case .accountUnavailable, .accountChanged:
            "iCloud Unavailable"
        case .invalidRecord, .syncFailed, .notRunning:
            "Sync Failed"
        }
    }
}

actor CloudKitSyncService: CKSyncEngineDelegate {
    typealias SnapshotProvider = @MainActor @Sendable () throws -> [CloudSyncRecordKey: CloudSyncRecordSnapshot]
    typealias RemoteMutationHandler = @MainActor @Sendable ([CloudSyncRemoteMutation]) async throws -> Set<CloudSyncRecordKey>
    typealias StatusHandler = @MainActor @Sendable (CloudSyncStatus) -> Void
    typealias DisableHandler = @MainActor @Sendable () -> Void
    typealias AccountStatusProvider = @Sendable () async throws -> CKAccountStatus
    typealias UserRecordIDProvider = @Sendable () async throws -> CKRecord.ID
    typealias EngineFactory = (CKSyncEngine.Configuration) throws -> CKSyncEngine
    /// Deletes the whole custom zone (every record + the zone itself) server-side. Injected
    /// so the factory-reset purge is unit-testable without a live CloudKit database.
    typealias ZoneDeleter = @Sendable (CKRecordZone.ID) async throws -> Void

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
    private let zoneDeleter: ZoneDeleter
    private let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?
    private var isSynchronizing = false
    /// Depth of in-flight engine-driven (automatic) fetch/send cycles, tracked from CKSyncEngine's
    /// will/did delegate events. Lets the opportunistic foreground sync (`requestSync`) stand down
    /// when the engine is already syncing on its own, instead of piling on a redundant fetch+send
    /// (#13). `isSynchronizing` only covers the manual `synchronize()` path; this covers the
    /// automatic one. Reset to 0 on engine teardown so it can never wedge `requestSync` shut.
    private var engineSyncActivity = 0
    private var isStarting = false
    // CloudKit awaits and CKSyncEngine callbacks can resume after a user toggles sync.
    private var syncRequested = false
    private var lifecycleGeneration = 0
    /// When the most recent `synchronize` actually began. Used to debounce the
    /// opportunistic foreground sync (`requestSync`) so repeatedly returning to the
    /// app doesn't trigger a full fetch+send each time. A user-initiated
    /// `synchronize()` (Force Sync) and change-driven sync are not gated by this.
    private var lastSyncStartedAt = Date.distantPast
    private let foregroundSyncMinimumInterval: TimeInterval = 30

    init(
        metadataStore: CloudSyncMetadataStore,
        snapshotProvider: @escaping SnapshotProvider,
        remoteMutationHandler: @escaping RemoteMutationHandler,
        statusHandler: @escaping StatusHandler,
        disableHandler: @escaping DisableHandler,
        accountStatusProvider: AccountStatusProvider? = nil,
        userRecordIDProvider: UserRecordIDProvider? = nil,
        engineFactory: @escaping EngineFactory = { CKSyncEngine($0) },
        zoneDeleter: ZoneDeleter? = nil
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
        // Capture the known-Sendable container (not the database) to sidestep any
        // CKDatabase Sendability question, mirroring the account-status default above.
        self.zoneDeleter = zoneDeleter ?? { zoneID in
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        }
    }

    /// Ensure the sync engine is running, performing the heavy startup (account
    /// check, inventory reconcile, engine setup, and one initial sync) only when it
    /// isn't already up. When the engine already exists this is a no-op — returning
    /// to the foreground must not re-run startup work; opportunistic syncing goes
    /// through `requestSync()` instead (#7).
    func start(allowAccountReplacement: Bool) async {
        syncRequested = true
        if engine != nil {
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
                    "Sign in to iCloud and allow iCloud access for this app before turning on sync."
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
        engineSyncActivity = 0
        if let existingEngine {
            await existingEngine.cancelOperations()
        }
        guard lifecycleGeneration == generation, !syncRequested else { return }
        await statusHandler(.disabled)
    }

    /// Hard-deletes the entire CloudKit zone (every record + the zone itself) for a factory
    /// reset, then wipes local sync metadata. The engine is stopped first so a fetched
    /// zone-deletion can't trigger the resurrection path (recreate zone + re-upload).
    ///
    /// Throws `.accountUnavailable` when there's no usable iCloud account — the caller treats
    /// that as "nothing to delete server-side" and proceeds with a local-only wipe. Throws
    /// `.syncFailed` when iCloud can't be reached or the delete genuinely fails, so the caller
    /// can abort with the local data still intact. A zone that's already gone counts as success.
    func purgeCloudData() async throws {
        let status: CKAccountStatus
        do {
            status = try await accountStatusProvider()
        } catch {
            throw CloudSyncError.syncFailed("Couldn't reach iCloud to delete your data. Check your connection and try again.")
        }

        switch status {
        case .available:
            break
        case .noAccount, .restricted:
            throw CloudSyncError.accountUnavailable("You're not signed in to iCloud, so there's no iCloud copy to delete.")
        default:
            throw CloudSyncError.syncFailed("Couldn't reach iCloud to delete your data. Check your connection and try again.")
        }

        // Tear the engine down before deleting so it can't observe the zone deletion and
        // resurrect it. `stop()` cancels in-flight operations and clears `engine`.
        await stop()

        do {
            try await zoneDeleter(zoneID)
        } catch {
            guard Self.isZoneAlreadyGone(error) else {
                throw CloudSyncError.syncFailed("The iCloud data couldn't be deleted. Check your connection and try again.")
            }
            // Nothing on the server to remove — a complete erase by definition.
        }

        try metadataStore.reset()
    }

    private static let zoneGoneCodes: Set<CKError.Code> = [.zoneNotFound, .unknownItem, .userDeletedZone]

    /// True when a delete failed only because the zone was already absent (so the erase is
    /// effectively complete), including a partial failure whose every item error says so.
    private static func isZoneAlreadyGone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if zoneGoneCodes.contains(ckError.code) { return true }
        if ckError.code == .partialFailure,
           let partials = ckError.partialErrorsByItemID?.values, !partials.isEmpty {
            return partials.allSatisfy { ($0 as? CKError).map { zoneGoneCodes.contains($0.code) } ?? false }
        }
        return false
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

    /// Opportunistic sync used on app activation. No-ops if the engine isn't running
    /// (it never starts it — that's `start()`'s job) and is debounced so rapid
    /// foreground transitions don't each trigger a full fetch+send (#7).
    func requestSync() async {
        guard syncRequested, let engine else { return }
        // Stand down unless nothing is already syncing — manual (`isSynchronizing`) or engine-driven
        // (`engineSyncActivity`) — and the debounce window has elapsed, so returning to the
        // foreground doesn't duplicate an in-flight automatic sync (#13). Force Sync
        // (`synchronize()`) is intentionally not gated by this: the user asked for an immediate sync.
        guard Self.shouldRunOpportunisticSync(
            isSynchronizing: isSynchronizing,
            engineSyncActivity: engineSyncActivity,
            secondsSinceLastSync: Date().timeIntervalSince(lastSyncStartedAt),
            minimumInterval: foregroundSyncMinimumInterval
        ) else { return }
        await synchronize(generation: lifecycleGeneration, using: engine)
    }

    /// Whether an opportunistic foreground sync should run: only when nothing is already syncing
    /// (manual or engine-driven) and the debounce window has elapsed (#13 / #7). Pure + `static` so
    /// the gate is unit-testable without a live engine — whose `Event`s have no public initializer.
    static func shouldRunOpportunisticSync(
        isSynchronizing: Bool,
        engineSyncActivity: Int,
        secondsSinceLastSync: TimeInterval,
        minimumInterval: TimeInterval
    ) -> Bool {
        !isSynchronizing && engineSyncActivity == 0 && secondsSinceLastSync >= minimumInterval
    }

    private func synchronize(generation: Int, using engine: CKSyncEngine) async {
        guard isCurrent(generation, engine: engine), !isSynchronizing else { return }
        isSynchronizing = true
        lastSyncStartedAt = Date()
        let interval = SyncSignpost.sync.begin("synchronize")
        let start = DispatchTime.now()
        var result = "ok"
        await statusHandler(.syncing)
        defer {
            SyncSignpost.sync.emit("synchronize ms=\(SyncSignpost.sync.ms(since: start)) result=\(result)")
            SyncSignpost.sync.end("synchronize", interval)
            finishSynchronizing(generation: generation, engine: engine)
        }
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
            // A partial failure means some records were rejected. The benign cases (first-sync
            // "record already exists" collisions, retryable blips, a zone being recreated) are
            // handled per-record in the sent/fetched event callbacks and retried by the engine,
            // so they're not user-facing — report `.upToDate`. But a partial failure that
            // carries a genuine rejection (quota, permission, server-rejected, …) must NOT be
            // mislabeled "Up to Date" — surface it so the user can see the records didn't sync
            // (WC-L29). The benign set matches `handleSentRecordZoneChanges`'s non-throw set.
            if let ckError = error as? CKError, Self.partialFailureIsBenign(ckError) {
                let date = Date()
                try? metadataStore.update { $0.lastSyncAt = date }
                await statusHandler(.upToDate(date))
            } else {
                result = "failed"
                await report(error)
            }
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
                engineSyncActivity = max(0, engineSyncActivity - 1)
                if !metadataStore.read().bootstrapCompleted {
                    try metadataStore.update { $0.bootstrapCompleted = true }
                    enqueuePendingRecordChanges(on: syncEngine)
                }

            case .willFetchChanges, .willSendChanges:
                // Track engine-driven (automatic) sync cycles so the opportunistic foreground sync
                // (`requestSync`) can stand down while the engine is already syncing, instead of
                // overlapping it with a redundant fetch+send (#13).
                engineSyncActivity += 1

            case .didSendChanges:
                engineSyncActivity = max(0, engineSyncActivity - 1)

            case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
                break

            @unknown default:
                Self.logger.info("Ignoring an unknown CKSyncEngine event.")
            }
        } catch {
            guard syncRequested, engine === syncEngine else { return }
            // WC-M2: only a genuine account change is fatal — tear the engine down (which
            // also disables sync to protect the previous account's data). Every other error
            // reaching this catch (a transient metadata-disk write now that WC-M3's `update`
            // is synchronous+throwing, a network blip, a non-retryable record save, an
            // engine-state encode) is reported but leaves the engine running so CKSyncEngine
            // retries — instead of permanently self-disabling sync over a recoverable
            // condition (which, with WC-H3, it was far too eager to do).
            if Self.failureCategory(for: error) == .accountChanged {
                Self.logger.error("CloudKit event handling hit a fatal account change: \(error.localizedDescription, privacy: .public)")
                SyncDiagnosticsLog.shared.record("ERROR account changed — sync disabled: \(error.localizedDescription)")
                await stopAfterFatalError(error)
            } else {
                Self.logger.error("CloudKit event handling failed (non-fatal, will retry): \(error.localizedDescription, privacy: .public)")
                await report(error)
            }
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
        let recordIDs = pending.compactMap { change -> CKRecord.ID? in
            switch change {
            case .saveRecord(let recordID), .deleteRecord(let recordID):
                return recordID
            @unknown default:
                return nil
            }
        }
        // WC-H4: encode the per-entity snapshot ONCE for the whole batch (inside
        // `makeRecords`) rather than once per record. The per-record provider closure below
        // just indexes the precomputed dictionary, so a B-record batch over an N-record
        // dataset performs one full-dataset encode, not B*N — and only one hop onto the
        // main actor instead of B.
        let records = await makeRecords(for: recordIDs)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            records[recordID]
        }
    }

    /// Builds the CloudKit records for a batch of pending record IDs, fetching the
    /// per-entity snapshot exactly once for the whole batch (WC-H4). Engine/lifecycle
    /// guarding is the caller's responsibility (`nextRecordZoneChangeBatch` already checks
    /// `syncRequested` / `engine === syncEngine`); keeping this free of the engine makes it
    /// unit-testable from just the metadata store and an injected snapshot provider.
    func makeRecords(for recordIDs: [CKRecord.ID]) async -> [CKRecord.ID: CKRecord] {
        let snapshot = (try? await snapshotProvider()) ?? [:]
        var records: [CKRecord.ID: CKRecord] = [:]
        for recordID in recordIDs {
            if let record = makeRecord(for: recordID, snapshot: snapshot) {
                records[recordID] = record
            }
        }
        return records
    }

    private func makeRecord(
        for recordID: CKRecord.ID,
        snapshot: [CloudSyncRecordKey: CloudSyncRecordSnapshot]
    ) -> CKRecord? {
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
            guard let entitySnapshot = snapshot[key] else {
                return nil
            }
            record["isDeleted"] = false as NSNumber
            record["payload"] = entitySnapshot.payload as NSData
            record["createdAt"] = entitySnapshot.createdAt as NSDate
            record["updatedAt"] = entitySnapshot.updatedAt as NSDate
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

    /// Builds the remote snapshot for a fetched CloudKit record, or returns `nil` when
    /// the record carries no `payload` (corrupt/incomplete). Callers skip a `nil` record
    /// rather than throwing, so a single bad record can't tear down the whole engine (#6).
    /// Pure and `static` so it stays unit-testable without a live `CKSyncEngine`.
    static func remoteSnapshot(from record: CKRecord, key: CloudSyncRecordKey) -> CloudSyncRecordSnapshot? {
        guard let payload = record["payload"] as? Data else { return nil }
        return CloudSyncRecordSnapshot(
            key: key,
            payload: payload,
            createdAt: record["createdAt"] as? Date ?? Date.distantPast,
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date.distantPast
        )
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        SyncSignpost.sync.emit("fetched mods=\(event.modifications.count) dels=\(event.deletions.count)")
        // The full local snapshot is only required during the initial bootstrap
        // merge (to compare local vs. remote). Once bootstrap is complete, remote
        // changes win directly, so we avoid re-encoding the entire dataset + SHA256
        // on every fetched batch (a heavy main-actor cost).
        let isBootstrapCompleted = metadataStore.read().bootstrapCompleted
        let localRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot] = isBootstrapCompleted
            ? [:]
            : try await snapshotProvider()
        let originalMetadata = metadataStore.read()
        var metadata = originalMetadata
        var mutations: [CloudSyncRemoteMutation] = []
        var pendingToRequeue = Set<CloudSyncRecordKey>()
        var touchedKeys = Set<CloudSyncRecordKey>()
        var skippedPayloadlessRecords = 0

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

            // #6: a record with no payload is corrupt/incomplete. Skip it instead of
            // throwing — a throw bubbles to `handleEvent`'s catch and tears down the
            // whole engine over one bad record. A clean skip leaves this key's metadata
            // (and any good local value) untouched; CKSyncEngine still advances its
            // change token for the batch, so the record isn't re-delivered unless it
            // changes again.
            guard let remoteSnapshot = Self.remoteSnapshot(from: record, key: key) else {
                Self.logger.error("Skipping CloudKit record \(record.recordID.recordName, privacy: .public) of type \(key.type.rawValue, privacy: .public): no payload.")
                skippedPayloadlessRecords += 1
                touchedKeys.remove(key)
                continue
            }
            let payload = remoteSnapshot.payload

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
                let decision = Self.bootstrapDecision(
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

        if skippedPayloadlessRecords > 0 {
            Self.logger.error("Skipped \(skippedPayloadlessRecords, privacy: .public) CloudKit record(s) with no payload in this fetch batch.")
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
            if Self.isRetryable(failure.error) {
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
        SyncSignpost.sync.emit("sent saved=\(event.savedRecords.count) failed=\(event.failedRecordSaves.count)")
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

        // Classify failures first. The common first-sync case is a flood of
        // `serverRecordChanged` collisions ("record to insert already exists") when
        // both devices uploaded the same records. Those non-deleted conflicts all do
        // the same thing (adopt the server's system fields, then resend as an update),
        // so we batch them into a single metadata write + single enqueue instead of
        // one full metadata-file rewrite per record.
        var nonDeletedConflicts: [(key: CloudSyncRecordKey, serverRecord: CKRecord)] = []
        var deletedServerConflicts: [(key: CloudSyncRecordKey, expectedRevision: UUID?, serverRecord: CKRecord)] = []
        var simpleRequeue = Set<CloudSyncRecordKey>()
        var needsZoneRecreation = false

        for failure in event.failedRecordSaves where failure.record.recordID.zoneID == zoneID {
            guard let key = CloudSyncRecordKey(recordName: failure.record.recordID.recordName) else { continue }
            let currentRevision = metadataStore.pendingRevision(for: key)
            let serverRecord = failure.error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
            let serverIsDeleted = (serverRecord?["isDeleted"] as? NSNumber)?.boolValue ?? false

            // The per-record decision is the pure `sentRecordFailureResolution`; this loop only
            // performs the side effects for each outcome (conflicts are batched below by kind).
            switch Self.sentRecordFailureResolution(
                errorCode: failure.error.code,
                errorIsRetryable: Self.isRetryable(failure.error),
                hasServerRecord: serverRecord != nil,
                serverRecordIsDeleted: serverIsDeleted,
                failedRevision: recordRevision(failure.record),
                currentRevision: currentRevision
            ) {
            case .staleRequeue, .retryableRequeue:
                simpleRequeue.insert(key)
            case .zoneRecreation:
                needsZoneRecreation = true
                simpleRequeue.insert(key)
            case .nonDeletedConflict:
                if let serverRecord { nonDeletedConflicts.append((key, serverRecord)) }
            case .deletedConflict:
                if let serverRecord { deletedServerConflicts.append((key, currentRevision, serverRecord)) }
            case .recordGone:
                // The server says this record no longer exists — the local systemFields carry
                // a stale recordChangeTag that turns every save into an "update" the server
                // rejects. Clear systemFields so the next attempt creates a fresh record.
                Self.logger.warning("Record \(key.storageKey, privacy: .public) gone from server — clearing systemFields for re-creation.")
                SyncDiagnosticsLog.shared.record("RECORD GONE \(key.storageKey) — clearing systemFields")
                try metadataStore.update { metadata in
                    var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
                    state.systemFields = nil
                    metadata.records[key.storageKey] = state
                }
                simpleRequeue.insert(key)
            case .fatal:
                throw failure.error
            }
        }

        if needsZoneRecreation {
            try metadataStore.update { $0.zoneReady = false }
            ensureZonePending(on: syncEngine)
        }

        if !nonDeletedConflicts.isEmpty {
            // #15: don't blindly re-upload a record just because its insert collided.
            // Compare each conflicting server record to the current local value via the
            // shared merge decision (`conflictAction`):
            //  - identical payload  -> adopt the server's system fields and DROP the
            //    pending upload (the concurrent-enable "hundreds of collisions" churn);
            //  - server wins (newer, and no deliberate local edit) -> apply the server
            //    payload locally and clear pending (step 2);
            //  - local wins (a real local edit, or local newer) -> requeue and re-upload
            //    as an update with the adopted system fields.
            let localRecords = (try? await snapshotProvider()) ?? [:]
            var conflictRequeue = Set<CloudSyncRecordKey>()
            var serverWins: [(key: CloudSyncRecordKey, snapshot: CloudSyncRecordSnapshot, expectedRevision: UUID?)] = []

            try metadataStore.update { metadata in
                for (key, serverRecord) in nonDeletedConflicts {
                    var state = metadata.records[key.storageKey] ?? CloudSyncRecordState()
                    state.systemFields = encodeSystemFields(serverRecord)
                    let serverSnapshot = Self.remoteSnapshot(from: serverRecord, key: key)

                    switch Self.conflictAction(pending: state.pending, local: localRecords[key], server: serverSnapshot) {
                    case .adoptServerIdentical:
                        state.pending = nil
                        state.isTombstone = false
                        state.deletedAt = nil
                        if let serverSnapshot {
                            metadata.knownLocalHashes[key.storageKey] = serverSnapshot.payloadHash
                        }
                    case .applyServer:
                        // Keep pending until the apply lands; cleared revision-safely below.
                        if let serverSnapshot {
                            serverWins.append((key, serverSnapshot, state.pending?.revision))
                        } else if state.pending != nil {
                            conflictRequeue.insert(key)
                        }
                    case .requeueLocal:
                        if state.pending != nil {
                            conflictRequeue.insert(key)
                        }
                    }

                    metadata.records[key.storageKey] = state
                }
            }
            simpleRequeue.formUnion(conflictRequeue)

            // Step 2: apply the server-wins payloads in one batched call, then clear their
            // pending in a revision-checked write — mirrors the deleted-conflict path. A
            // record whose local pending changed underneath (or that the apply skipped) is
            // requeued so the local change is re-sent rather than lost.
            if !serverWins.isEmpty {
                let appliedKeys = try await remoteMutationHandler(serverWins.map {
                    CloudSyncRemoteMutation(key: $0.key, payload: $0.snapshot.payload, expectedPendingRevision: $0.expectedRevision)
                })
                var applyRequeue = Set<CloudSyncRecordKey>()
                try metadataStore.update { metadata in
                    for win in serverWins {
                        guard appliedKeys.contains(win.key) else {
                            applyRequeue.insert(win.key)
                            continue
                        }
                        var state = metadata.records[win.key.storageKey] ?? CloudSyncRecordState()
                        guard state.pending?.revision == win.expectedRevision else {
                            if state.pending != nil { applyRequeue.insert(win.key) }
                            continue
                        }
                        state.pending = nil
                        state.isTombstone = false
                        state.deletedAt = nil
                        metadata.knownLocalHashes[win.key.storageKey] = win.snapshot.payloadHash
                        metadata.records[win.key.storageKey] = state
                    }
                }
                simpleRequeue.formUnion(applyRequeue)
            }
        }

        enqueue(keys: Array(simpleRequeue), on: syncEngine)

        for conflict in deletedServerConflicts {
            try await resolveServerConflict(
                for: conflict.key,
                expectedPendingRevision: conflict.expectedRevision,
                serverRecord: conflict.serverRecord,
                syncEngine: syncEngine
            )
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

    enum BootstrapDecision: Equatable {
        case local
        case remote
        case identical
    }

    /// First-sync (bootstrap) merge decision for one record: whether the local value
    /// wins, the remote value wins, or they're identical — in which case the local
    /// pending upload is dropped, which is what stops a second already-populated device
    /// from re-inserting records that already exist remotely (#8). Pure and `static`
    /// so the collision-avoidance logic stays unit-testable without a live CKSyncEngine.
    ///
    /// The recency comparison uses the **domain** `updatedAt` (a field both the local entity and the
    /// remote record carry), NOT CloudKit's server `modificationDate`. That is deliberate: the local
    /// side is a *pending* change not yet on the server, so it has no fresh server timestamp —
    /// comparing the remote's server date against the local's stale/absent one would make the remote
    /// win almost every time and systematically lose local edits. For an exact `updatedAt` tie on
    /// non-deliberate records the payload-hash comparison is the tie-break: arbitrary but total and
    /// **convergent** — each device computes `local.hash > remote.hash` over its mirror-image of the
    /// (local, remote) pair and therefore independently selects the *same* winner, with no server
    /// round-trip and no ping-pong (see `testBootstrapDecisionTieBreakIsConvergentAcrossDevices`).
    static func bootstrapDecision(
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

    enum ConflictAction: Equatable {
        case requeueLocal          // re-upload the local record (local wins, or server unreadable)
        case adoptServerIdentical  // server already holds the same payload — drop the redundant upload
        case applyServer           // server's payload wins — apply it locally, then clear pending
    }

    /// Resolution for one non-deleted save conflict (a `serverRecordChanged` rejection on
    /// upload): re-upload local, drop a redundant identical upload, or adopt the server's
    /// newer payload (#15). A thin, intention-revealing wrapper over `bootstrapDecision`,
    /// plus the defensive "unreadable server payload → keep local" edge. Because it routes
    /// through `bootstrapDecision`, a deliberate local edit (`.localChange`/`.delete`)
    /// never resolves to `applyServer`, so step 2 can't overwrite a real local change.
    static func conflictAction(
        pending: CloudSyncPendingMutation?,
        local: CloudSyncRecordSnapshot?,
        server: CloudSyncRecordSnapshot?
    ) -> ConflictAction {
        guard let server else { return .requeueLocal }
        switch bootstrapDecision(pending: pending, local: local, remote: server) {
        case .identical: return .adoptServerIdentical
        case .remote: return .applyServer
        case .local: return .requeueLocal
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

    static func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .resultsTruncated, .batchRequestFailed:
            true
        default:
            false
        }
    }

    /// Whether a `CKError.partialFailure` is fully recoverable — i.e. every per-item error is
    /// one the sent-side classifier (`handleSentRecordZoneChanges`) already declines to throw
    /// on: a retryable blip, a `.serverRecordChanged` conflict that's resolved per record, or
    /// a `.zoneNotFound` that triggers zone recreation. When true, `synchronize` may still
    /// report `.upToDate`; otherwise the batch contains a genuine rejection (quota, permission,
    /// server-rejected, invalid-arguments, …) that must surface to the user instead of being
    /// mislabeled "Up to Date" (WC-L29). A partial failure with no introspectable item errors
    /// is treated as non-benign, so an opaque failure isn't silently swallowed. Pure + static
    /// so it's unit-testable without a live CloudKit container, and kept in lock-step with the
    /// sent-side non-throw set so the two paths never disagree about the same error.
    static func partialFailureIsBenign(_ error: CKError) -> Bool {
        guard error.code == .partialFailure,
              let itemErrors = error.partialErrorsByItemID, !itemErrors.isEmpty else {
            return false
        }
        return itemErrors.values.allSatisfy { itemError in
            guard let ckError = itemError as? CKError else { return false }
            return isRetryable(ckError)
                || ckError.code == .serverRecordChanged
                || ckError.code == .zoneNotFound
                || ckError.code == .unknownItem
                || ckError.code == .serverRejectedRequest
        }
    }

    /// What `handleSentRecordZoneChanges` should do with a single failed record save. Extracted
    /// as a pure decision so the sent-side failure classification can be unit-tested directly:
    /// `CKSyncEngine.Event` has no public initializer (TO_IMPROVE #22), so the surrounding
    /// engine flow can't be exercised in tests, but this per-record routing — the part that
    /// decides which failures retry, conflict, recreate the zone, or surface — can. The caller
    /// performs the side effects (metadata writes, enqueue, throw) for each case.
    enum SentRecordFailureResolution: Equatable {
        case staleRequeue       // the failed upload's revision is no longer the pending one → re-send the latest
        case retryableRequeue   // a transient transport/throttle blip → re-enqueue and try again
        case zoneRecreation     // the zone is gone → mark it for recreation, then re-enqueue
        case nonDeletedConflict // server holds a different live copy → resolve via `conflictAction`
        case deletedConflict    // server copy is a tombstone → resolve via `resolveServerConflict`
        case recordGone         // record doesn't exist on server (stale changeTag) → clear systemFields, re-create as new
        case fatal              // a genuine rejection (quota / permission / server-rejected / …) → throw, surfacing it
    }

    /// Pure per-record routing for a sent-batch save failure. Kept in lock-step with
    /// `partialFailureIsBenign` (the non-throw set must agree): a stale-revision failure or a
    /// retryable blip re-enqueues, `zoneNotFound` recreates the zone, a `serverRecordChanged`
    /// that carries a server record routes by the server's deleted flag, `.unknownItem` /
    /// `.serverRejectedRequest` clear stale systemFields for a fresh re-creation, and
    /// everything else is fatal. Note a `serverRecordChanged` with NO attached server record
    /// has nothing to merge, so it falls through to the retryable/fatal decision (and is not
    /// retryable → fatal), exactly as the original inline ladder did.
    static func sentRecordFailureResolution(
        errorCode: CKError.Code,
        errorIsRetryable: Bool,
        hasServerRecord: Bool,
        serverRecordIsDeleted: Bool,
        failedRevision: UUID?,
        currentRevision: UUID?
    ) -> SentRecordFailureResolution {
        // A failure whose revision no longer matches the current pending one is stale: the local
        // value moved on after this upload was sent, so just re-enqueue to send the latest.
        if let failedRevision, currentRevision != failedRevision {
            return .staleRequeue
        }
        if errorCode == .serverRecordChanged, hasServerRecord {
            return serverRecordIsDeleted ? .deletedConflict : .nonDeletedConflict
        }
        if errorCode == .zoneNotFound {
            return .zoneRecreation
        }
        // "recordChangeTag specified, but record not found" — the local systemFields carry a
        // stale changeTag for a record the server no longer has (deleted out-of-band, zone
        // reset, etc.). Clearing systemFields lets the next attempt create a fresh record.
        if errorCode == .unknownItem || errorCode == .serverRejectedRequest {
            return .recordGone
        }
        return errorIsRetryable ? .retryableRequeue : .fatal
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
        engineSyncActivity = 0
        if let existingEngine {
            // This teardown runs from `handleEvent(_:syncEngine:)`'s catch block, i.e. while a
            // CKSyncEngine delegate callback is still on the current task. Awaiting a re-entrant
            // engine call (`cancelOperations()` ends up delivering further delegate events) from
            // there trips CKSyncEngine's serial-callback guard and crashes the process:
            //   "BUG IN CLIENT OF CLOUDKIT: Cannot await a call into CKSyncEngine from within a
            //    delegate callback if that function will end up calling back into the delegate."
            //   (CloudKit/CKSyncEngine.swift, EXC_BREAKPOINT)
            // CloudKit tracks "am I inside a callback?" with a task-local, so a *detached* task —
            // which inherits no task-locals — is the supported way to escape it. `engine` is
            // already nil above, so any callbacks that fire before cancellation lands are ignored.
            Task.detached { await existingEngine.cancelOperations() }
        }
        guard lifecycleGeneration == generation, !syncRequested else { return }
        await report(error)
    }

    /// Stable, user-meaningful classification of a sync failure, independent of the exact
    /// display copy. Extracted as a pure `static` map (CKError code / our own
    /// `CloudSyncError` → category) so it stays unit-testable without a live CloudKit
    /// container, and so account / network / quota / throttling failures are no longer
    /// collapsed into one generic status (#14).
    enum SyncFailureCategory: Equatable, Sendable {
        case notSignedIn            // not signed in to iCloud — surfaced as "iCloud Unavailable"
        case accountChanged         // the iCloud user changed; sync was disabled to protect data
        case restricted             // CloudKit blocked by device management / Screen Time
        case networkUnavailable     // offline / no usable connection
        case connectionLost         // the request reached iCloud but the response was lost
        case temporarilyUnavailable // iCloud / the account is briefly unavailable (booting, blip)
        case quotaExceeded          // the iCloud account is out of storage
        case rateLimited            // CloudKit throttled the request; it retries automatically
        case zoneMissing            // the sync zone isn't there yet / was removed
        case unknown                // anything else — fall back to the system description
    }

    /// Drops fully-settled tombstone states — deleted, acknowledged (no pending work), and no longer
    /// locally present — so the metadata file doesn't accumulate dead per-record entries (#12). Safe
    /// because every entity id is a one-shot UUID: a pruned id is never re-created, so its tombstone
    /// can never be needed to suppress a resurrection. Pure + `static` so it stays unit-testable.
    static func pruningSettledTombstones(
        from records: [String: CloudSyncRecordState],
        knownLocalHashes: [String: String]
    ) -> [String: CloudSyncRecordState] {
        records.filter { key, state in
            let settled = state.isTombstone && state.pending == nil && knownLocalHashes[key] == nil
            return !settled
        }
    }

    static func failureCategory(for error: Error) -> SyncFailureCategory {
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated: return .notSignedIn
            case .managedAccountRestricted: return .restricted
            case .networkUnavailable, .networkFailure: return .networkUnavailable
            case .serverResponseLost: return .connectionLost
            case .serviceUnavailable, .accountTemporarilyUnavailable: return .temporarilyUnavailable
            case .quotaExceeded: return .quotaExceeded
            case .requestRateLimited, .zoneBusy: return .rateLimited
            case .zoneNotFound: return .zoneMissing
            default: return .unknown
            }
        }
        if case CloudSyncError.accountUnavailable = error { return .notSignedIn }
        if case CloudSyncError.accountChanged = error { return .accountChanged }
        return .unknown
    }

    /// Maps a failure to the user-facing status to publish: account problems become
    /// `.accountUnavailable` (Settings reads "iCloud Unavailable" with a sign-in hint),
    /// everything else becomes `.error` with copy specific to the category — instead of
    /// the previous behavior where network / quota / throttling all shared one message.
    /// Pure + `static` so `report(_:)` is a thin actor wrapper and the mapping is testable.
    static func syncStatus(for error: Error) -> CloudSyncStatus {
        switch failureCategory(for: error) {
        case .notSignedIn:
            // Preserve a custom sign-in message (e.g. the start-time prompt) when present.
            if case CloudSyncError.accountUnavailable(let message) = error {
                return .accountUnavailable(message)
            }
            return .accountUnavailable("Sign in to iCloud to continue syncing.")
        case .accountChanged:
            return .actionNeeded(CloudSyncError.accountChanged.localizedDescription(appLanguage: nil))
        case .restricted:
            return .actionNeeded("iCloud is restricted on this device. Allow it in Screen Time or device-management settings to keep syncing.")
        case .quotaExceeded:
            return .actionNeeded("Your iCloud storage is full. Free up space or upgrade iCloud+ to keep syncing.")
        // Transient & self-resolving — calm "waiting", never a red error.
        case .networkUnavailable:
            return .waiting("You're offline. Changes are saved and will sync automatically when you reconnect.")
        case .connectionLost:
            return .waiting("The connection to iCloud was lost. Your changes are saved and will sync automatically when it's restored.")
        case .temporarilyUnavailable:
            return .waiting("iCloud is temporarily unavailable. Sync will resume automatically in a moment.")
        case .rateLimited:
            return .waiting("iCloud is busy right now. Sync will resume automatically in a moment.")
        case .zoneMissing:
            return .waiting("iCloud is still preparing your sync data. This usually resolves on the next sync.")
        case .unknown:
            return .error(error.localizedDescription)
        }
    }

    private func report(_ error: Error) async {
        Self.logger.error("CloudKit sync error: \(error.localizedDescription, privacy: .public)")
        SyncDiagnosticsLog.shared.record("ERROR synchronize: \(error.localizedDescription)")
        await statusHandler(Self.syncStatus(for: error))
    }
}

// MARK: - #23 Production-safe sync telemetry

/// A small, thread-safe, capped in-memory ring of recent sync/persistence telemetry + error
/// lines, kept so the "Export Sync Diagnostics" support action has something to share — the
/// `.debug` summary lines (see `SyncSignpost`) aren't persisted to the unified log by design,
/// so `OSLogStore` can't retrieve them after the fact. Only ever holds the app's own controlled
/// lines (counts / bytes / ms / error descriptions), never payloads or amounts, so the export is
/// PII-clean by construction.
///
/// Lock-guarded (deliberately NOT an `actor`) so `record(_:)` is synchronous and callable from
/// any context — including `PersistenceCoordinator`, whose actor methods contain no suspension
/// points by design (an `await` just to log would break that invariant).
final class SyncDiagnosticsLog: @unchecked Sendable {
    static let shared = SyncDiagnosticsLog()

    private let lock = NSLock()
    private let capacity: Int
    private var lines: [String] = []

    init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
        lines.reserveCapacity(self.capacity)
    }

    /// Appends one line (a `HH:mm:ss.SSS` timestamp is prepended here). Evicts the oldest lines
    /// once `capacity` is exceeded, so memory stays bounded regardless of how long the app runs.
    func record(_ message: String) {
        let line = "\(Self.timestamp()) \(message)"
        lock.withLock {
            lines.append(line)
            if lines.count > capacity {
                lines.removeFirst(lines.count - capacity)
            }
        }
    }

    /// A point-in-time copy of the buffered lines, oldest first.
    func snapshot() -> [String] {
        lock.withLock { lines }
    }

    /// Drops all buffered lines. Used by tests; not surfaced in the UI.
    func clear() {
        lock.withLock { lines.removeAll(keepingCapacity: true) }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }
}

/// Production-safe sync telemetry (#23). Wraps an `OSSignposter` interval (so the operation shows
/// as a timed lane in Instruments) and emits a `.debug` summary line that is both streamable live
/// (`log stream --predicate 'category == "Telemetry"'`) and copied into `SyncDiagnosticsLog` for
/// the export. Counts / bytes / ms only — never payloads or amounts; all interpolations are
/// `.public` so the (non-sensitive) numbers aren't redacted in the live stream.
///
/// `.debug` is chosen for zero production footprint: not persisted to the log store, materialized
/// only when actively streamed. The two shared instances are split by layer subsystem; both use a
/// dedicated `Telemetry` category so the whole pipeline filters with one predicate while staying
/// out of the existing `.error` categories. A reference type marked `@unchecked Sendable` so the
/// shared singletons can be touched from any actor (it only holds thread-safe OS logging types).
final class SyncSignpost: @unchecked Sendable {
    static let sync = SyncSignpost(subsystem: "com.wealthcompass.sync")
    static let persistence = SyncSignpost(subsystem: "com.wealthcompass.persistence")

    private let signposter: OSSignposter
    private let logger: Logger

    private init(subsystem: String) {
        self.signposter = OSSignposter(subsystem: subsystem, category: "Telemetry")
        self.logger = Logger(subsystem: subsystem, category: "Telemetry")
    }

    /// Begins a uniquely-identified signpost interval (unique id so nested/overlapping intervals
    /// of the same name don't collide). Pair with `end(_:_:)`, ideally via `defer`.
    func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Whole milliseconds elapsed since `start`, using a monotonic clock (safe across wall-clock
    /// changes).
    func ms(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)
    }

    /// Logs one telemetry line live (`.debug`, public) and copies it into the export buffer.
    func emit(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        SyncDiagnosticsLog.shared.record(message)
    }
}
