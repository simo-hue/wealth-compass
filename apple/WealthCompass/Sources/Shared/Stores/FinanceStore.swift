import Foundation
import OSLog
import SwiftUI

/// Fast, allocation-free check for whether a file is a native JSON backup (vs. a broker CSV), used by
/// `FinanceStore.importFile`'s detached parse. Trusts a `.json` extension, otherwise peeks at the first
/// non-whitespace byte for a JSON opener. Free function so it stays nonisolated (callable off the MainActor).
fileprivate func financeImportLooksLikeJSON(_ data: Data, fileName: String) -> Bool {
    if fileName.lowercased().hasSuffix(".json") { return true }
    for byte in data.prefix(64) {
        switch byte {
        case 0x20, 0x09, 0x0A, 0x0D:
            continue // leading whitespace
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return true
        default:
            return false
        }
    }
    return false
}

enum FinanceImportMode: String, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        switch self {
        case .merge: AppLocalization.string("Merge", appLanguage: appLanguage)
        case .replace: AppLocalization.string("Replace", appLanguage: appLanguage)
        }
    }
}

struct FinanceImportResult: Identifiable {
    /// Fresh per import so presenting it re-triggers a `.sheet(item:)` each time.
    let id = UUID()
    let sourceFileName: String
    let mode: FinanceImportMode
    let transactions: Int
    let recurringTransactions: Int
    let investments: Int
    let crypto: Int
    let liabilities: Int
    let snapshots: Int
    let generatedSnapshots: Int
    let categoriesAdded: Int
    let skippedRecords: Int
    /// Human-readable name of the detected non-native source (e.g. "Revolut consolidated statement").
    /// `nil` for a native Wealth Compass JSON backup. Shown as the first summary line when present.
    var detectedSource: String? = nil

    var importedRecordCount: Int {
        transactions + recurringTransactions + investments + crypto + liabilities + snapshots
    }

    var message: String {
        message(appLanguage: nil)
    }

    func message(appLanguage: String?) -> String {
        var lines = [
            AppLocalization.string("\(mode.localizedTitle(appLanguage: appLanguage)) import completed for \(sourceFileName).", appLanguage: appLanguage),
            AppLocalization.string("\(transactions) transactions, \(recurringTransactions) recurring schedules, \(investments) investments, \(crypto) crypto holdings, \(liabilities) liabilities, and \(snapshots) snapshots were imported.", appLanguage: appLanguage)
        ]

        if generatedSnapshots > 0 {
            lines.append(AppLocalization.string("\(generatedSnapshots) current snapshot was generated after import.", appLanguage: appLanguage))
        }

        if categoriesAdded > 0 {
            lines.append(AppLocalization.string("\(categoriesAdded) custom cash-flow categories were added.", appLanguage: appLanguage))
        }

        if skippedRecords > 0 {
            lines.append(AppLocalization.string("\(skippedRecords) malformed or incomplete records were skipped.", appLanguage: appLanguage))
        }

        if let detectedSource {
            lines.insert(AppLocalization.string("Detected format: \(detectedSource).", appLanguage: appLanguage), at: 0)
        }

        return lines.joined(separator: "\n\n")
    }
}

enum FinanceImportError: LocalizedError {
    case emptyFile
    case invalidJSON(String)
    case noSupportedRecords
    case localPersistenceError
    case unrecognizedFormat
    case malformedCSV(String)

    var errorDescription: String? {
        localizedDescription(appLanguage: nil)
    }

    func localizedDescription(appLanguage: String?) -> String {
        switch self {
        case .emptyFile:
            AppLocalization.string("The selected file is empty.", appLanguage: appLanguage)
        case .invalidJSON(let details):
            AppLocalization.string("The selected file is not a valid Wealth Compass JSON backup. \(details)", appLanguage: appLanguage)
        case .noSupportedRecords:
            AppLocalization.string("No supported finance records were found in the selected file.", appLanguage: appLanguage)
        case .localPersistenceError:
            AppLocalization.string("Changes cannot be saved until the local database load error is resolved.", appLanguage: appLanguage)
        case .unrecognizedFormat:
            AppLocalization.string("This file isn't a Wealth Compass backup or a supported Revolut / Trade Republic statement.", appLanguage: appLanguage)
        case .malformedCSV(let details):
            AppLocalization.string("The statement file could not be read. \(details)", appLanguage: appLanguage)
        }
    }
}

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var data = FinancialData() {
        didSet { dataVersion &+= 1 } // invalidates the derived-data cache (M3)
    }
    /// Monotonic counter bumped on every `data` mutation; part of the analytics cache key.
    private var dataVersion: Int = 0
    /// Memoized totals (M3). The key is the full set of inputs to `calculateTotals`
    /// — data version + display currency + rate-snapshot timestamp — so it can never
    /// return a stale result after a data, currency, or exchange-rate change.
    private var cachedTotals: (version: Int, currency: Currency, rateStamp: Date?, dayStamp: Date, value: FinanceTotals)?
    /// Cache of the encoded per-entity CloudKit sync snapshot, keyed by `dataVersion` (H4).
    /// `cloudSyncRecords()` is a full-dataset JSON-encode + SHA-256 and the snapshot provider
    /// can be invoked several times within one sync pass (send batch, bootstrap merge,
    /// conflict path). `dataVersion` bumps on every `data` mutation, so a version match is
    /// always current; a mismatch recomputes.
    private var cachedCloudSyncSnapshot: (version: Int, records: [CloudSyncRecordKey: CloudSyncRecordSnapshot])?
    /// Memoized date-sorted transactions (M6), keyed by `dataVersion`. `transactions` is read
    /// several times per render (list rows, counts, per-keystroke filters) and the sort is
    /// O(n log n) each time; caching collapses that to one sort per data mutation.
    private var cachedSortedTransactions: (version: Int, value: [Transaction])?
    /// Memoized chart net-worth series (deep-audit M15/M16): keyed like `cachedTotals` plus the range
    /// and the current day (the series cutoff + today's point move at midnight). The stored value is
    /// already downsampled for long spans.
    private var cachedSnapshotsForChart: (version: Int, currency: Currency, rateStamp: Date?, range: TimeRange, dayStamp: Date, value: [NetWorthPoint])?
    /// Memoized cash-flow analytics (deep-audit M27): each keyed like `cachedTotals` plus its own time
    /// window (the month itself / the current month / the current day) so the hover/resize hot path
    /// reuses them instead of re-filtering + re-grouping every frame.
    private var cachedMonthlyCashFlow: (version: Int, currency: Currency, rateStamp: Date?, month: Date, value: MonthlyCashFlow)?
    private var cachedCashFlowTrend: (version: Int, currency: Currency, rateStamp: Date?, months: Int, monthStamp: Date, value: [CashFlowMonth])?
    private var cachedExpensesByCategory: (version: Int, currency: Currency, rateStamp: Date?, period: AnalyticsPeriod, dayStamp: Date, value: [CategoryTotal])?
    /// Memoized monthly transaction count (deep-audit M27) — keyed by data version + month; avoids the
    /// O(n) filter re-running on every macOS cash-flow body/resize pass (and the sorted accessor).
    private var cachedMonthlyTransactionCount: (version: Int, month: Date, value: Int)?
    @Published private(set) var isRefreshingMarketPrices = false
    /// Per-item progress of the (serial, rate-limited) Finnhub refresh, for an "x of N"
    /// UI indicator (M7). Nil when not refreshing investments.
    @Published private(set) var marketRefreshProgress: (done: Int, total: Int)?
    @Published private(set) var iCloudSyncError: String?
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .disabled
    /// A user-visible, app-wide error set when a local save fails so the user is told
    /// their latest change did not persist (H5). Surfaced as a banner by the root views.
    @Published private(set) var persistenceError: String?

    private static let logger = Logger(subsystem: "com.wealthcompass.persistence", category: "FinanceStore")

    private let persistence: FinancePersistence
    private let syncMetadataStore: CloudSyncMetadataStore
    private weak var settings: AppSettings?
    /// Owns the off-main-actor save pipeline: JSON encoding, the SHA-256 diff baseline,
    /// the disk write and the sync-metadata recording all happen inside this actor so they
    /// never block the main actor during an edit (M4). It replaces the old `persistedData`
    /// field as the source of truth for diffing.
    private let coordinator: PersistenceCoordinator
    /// A single long-lived consumer drains this stream and forwards each snapshot to
    /// `coordinator.save` in arrival order, guaranteeing save ordering (and last-wins
    /// coalescing) even when mutations fire in bursts.
    private var saveContinuation: AsyncStream<Int>.Continuation?
    private var saveConsumerTask: Task<Void, Never>?
    /// L52: handle to the init-time "restore sync-enabled state" task, so a factory reset can cancel
    /// it before it (re)starts the CloudKit engine after the wipe cleared the sync flag.
    private var initialSyncEnableTask: Task<Void, Never>?

    /// M31: weak bridge to the single live store so an app-delegate remote-notification handler — which
    /// has no environment injection — can drive a push-triggered sync (`handleRemoteCloudKitPush`). The
    /// app constructs exactly one `FinanceStore`; a background CloudKit push must reach it directly (not
    /// via a view that may not be alive when the app is woken).
    static weak var current: FinanceStore?
    /// Generation bookkeeping (main-actor only) used to know when the save pipeline is
    /// idle — both for correctness reasoning and for deterministic tests.
    private var lastEnqueuedSaveGeneration = 0
    private var lastProcessedSaveGeneration = 0
    private var saveIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var localPersistenceError: Error?
    private var lastMarketPriceRefreshAttemptAt: Date?
    /// UserDefaults key persisting the market-price refresh throttle across launches (deep-audit L54).
    private static let marketPriceRefreshAttemptKey = "wc_mobile_last_market_price_refresh_attempt"
    /// Set by `load()` when the one-time WC-M1 currency backfill stamped legacy rows, so
    /// `init` can persist the migration once the save pipeline is up.
    private var needsCurrencyBackfillSave = false

    private lazy var cloudSyncService = CloudKitSyncService(
        metadataStore: syncMetadataStore,
        snapshotProvider: { [weak self] in
            guard let self else { return [:] }
            return try self.currentCloudSyncRecords()
        },
        remoteMutationHandler: { [weak self] mutations in
            guard let self else { return [] }
            return try await self.applyRemoteMutations(mutations)
        },
        statusHandler: { [weak self] status in
            self?.updateCloudSyncStatus(status)
        },
        disableHandler: { [weak self] in
            self?.settings?.isICloudSyncEnabled = false
        }
    )

    /// Returns the encoded per-entity sync snapshot, memoized by `dataVersion` (H4) so a
    /// full-dataset encode isn't repeated when the data hasn't changed between calls within
    /// a sync pass. Backs the sync service's `snapshotProvider`.
    private func currentCloudSyncRecords() throws -> [CloudSyncRecordKey: CloudSyncRecordSnapshot] {
        if let cache = cachedCloudSyncSnapshot, cache.version == dataVersion {
            return cache.records
        }
        let records = try data.cloudSyncRecords()
        cachedCloudSyncSnapshot = (dataVersion, records)
        return records
    }

    init(
        persistence: FinancePersistence = LocalFinancePersistence(),
        settings: AppSettings? = nil,
        syncMetadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore()
    ) {
        self.persistence = persistence
        self.settings = settings
        self.syncMetadataStore = syncMetadataStore
        self.coordinator = PersistenceCoordinator(
            persistence: persistence,
            metadataStore: syncMetadataStore
        )
        // Restore the persisted market-price refresh throttle (deep-audit L54) so it survives a cold
        // launch — otherwise a failed refresh would retry on every relaunch with no throttle window,
        // mirroring how AppSettings persists its exchange-rate retry state.
        lastMarketPriceRefreshAttemptAt = UserDefaults.standard.object(forKey: FinanceStore.marketPriceRefreshAttemptKey) as? Date

        // M31: register as the single live store so a background CloudKit push can reach us.
        Self.current = self

        let seedRecords = load()
        startSaveConsumer(seedRecords: seedRecords)
        // Persist the WC-M1 currency backfill (if any) now that the save pipeline exists; it
        // diffs against the on-disk baseline seeded above, so only the stamped rows are written.
        if needsCurrencyBackfillSave {
            save()
        }
        let isSyncEnabled = settings?.isICloudSyncEnabled
            ?? UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
        if isSyncEnabled {
            // L52: keep a handle so a factory reset mid-launch can cancel this before it restarts the
            // engine after the wipe cleared the flag (see wipeLocalState + the automatic-path guard in
            // setICloudSyncEnabled).
            initialSyncEnableTask = Task { [weak self] in
                await self?.setICloudSyncEnabled(true, userInitiated: false)
            }
        }
    }

    deinit {
        saveContinuation?.finish()
        saveConsumerTask?.cancel()
        initialSyncEnableTask?.cancel()
    }

    var transactions: [Transaction] {
        if let cache = cachedSortedTransactions, cache.version == dataVersion { return cache.value }
        let sorted = data.transactions.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.createdAt > rhs.createdAt }
            return lhs.date > rhs.date
        }
        cachedSortedTransactions = (dataVersion, sorted)
        return sorted
    }

    var recurringTransactions: [RecurringTransaction] {
        data.recurringTransactions
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                return lhs.nextDueDate < rhs.nextDueDate
            }
    }

    var storageLocationDescription: String {
        persistence.locationDescription
    }

    func addTransaction(type: TransactionType, amount: Decimal, category: String, description: String, date: Date, currency: Currency, settings: AppSettings) {
        let transaction = Transaction(
            type: type,
            category: category,
            amount: amount,
            description: description,
            date: Calendar.current.startOfDay(for: date),
            currency: currency
        )

        // Snapshots store liquidity in the display currency, so convert the transaction's
        // own-currency delta before adjusting history (WC-M1; no-op when currency == base).
        let delta: Decimal = type == .income ? amount : -amount
        adjustHistoricalSnapshots(from: transaction.date, transactionCurrency: currency, displayCurrency: settings.currency, liquidityDelta: settings.convert(delta, from: currency))

        data.transactions.append(transaction)
        appendSnapshot(settings: settings)
        save()
    }

    func deleteTransaction(_ transaction: Transaction, settings: AppSettings) {
        let delta: Decimal = transaction.type == .income ? -transaction.amount : transaction.amount
        let txCurrency = transaction.currency ?? settings.currency
        adjustHistoricalSnapshots(from: transaction.date, transactionCurrency: txCurrency, displayCurrency: settings.currency, liquidityDelta: settings.convert(delta, from: txCurrency))

        data.transactions.removeAll { $0.id == transaction.id }
        appendSnapshot(settings: settings)
        save()
    }

    func updateTransaction(_ transaction: Transaction, type: TransactionType, amount: Decimal, category: String, description: String, date: Date, currency: Currency, settings: AppSettings) {
        guard let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) else { return }

        let oldDelta: Decimal = transaction.type == .income ? -transaction.amount : transaction.amount
        let oldCurrency = transaction.currency ?? settings.currency
        adjustHistoricalSnapshots(from: transaction.date, transactionCurrency: oldCurrency, displayCurrency: settings.currency, liquidityDelta: settings.convert(oldDelta, from: oldCurrency))

        let newDate = Calendar.current.startOfDay(for: date)
        let newDelta: Decimal = type == .income ? amount : -amount
        adjustHistoricalSnapshots(from: newDate, transactionCurrency: currency, displayCurrency: settings.currency, liquidityDelta: settings.convert(newDelta, from: currency))

        data.transactions[index].type = type
        data.transactions[index].amount = amount
        data.transactions[index].category = category
        data.transactions[index].description = description
        data.transactions[index].date = newDate
        data.transactions[index].currency = currency
        data.transactions[index].updatedAt = Date()

        appendSnapshot(settings: settings)
        save()
    }

    func upsertRecurringTransaction(_ recurringTransaction: RecurringTransaction) {
        var updated = recurringTransaction
        updated.updatedAt = Date()
        if let index = data.recurringTransactions.firstIndex(where: { $0.id == updated.id }) {
            data.recurringTransactions[index] = updated
        } else {
            data.recurringTransactions.append(updated)
        }
        save()
    }

    func deleteRecurringTransaction(_ recurringTransaction: RecurringTransaction) {
        data.recurringTransactions.removeAll { $0.id == recurringTransaction.id }
        save()
    }

    func setRecurringTransactionActive(_ recurringTransaction: RecurringTransaction, isActive: Bool, now: Date = Date()) {
        guard let index = data.recurringTransactions.firstIndex(where: { $0.id == recurringTransaction.id }) else {
            return
        }

        var updated = data.recurringTransactions[index]
        guard !updated.isCompleted else { return }
        if isActive {
            guard let nextDueDate = updated.firstOccurrence(onOrAfter: now) else {
                updated.isActive = false
                updated.updatedAt = now
                data.recurringTransactions[index] = updated
                save()
                return
            }
            updated.nextDueDate = nextDueDate
        }
        updated.isActive = isActive
        updated.updatedAt = now
        data.recurringTransactions[index] = updated
        save()
    }

    func completeRecurringTransaction(_ recurringTransaction: RecurringTransaction) {
        data.recurringTransactions.removeAll { $0.id == recurringTransaction.id }
        save()
    }

    func setRecurringNotificationsEnabled(id: UUID, isEnabled: Bool) {
        guard let index = data.recurringTransactions.firstIndex(where: { $0.id == id }) else { return }
        data.recurringTransactions[index].notificationsEnabled = isEnabled
        data.recurringTransactions[index].updatedAt = Date()
        save()
    }

    /// L53: dedup key for an already-generated recurring occurrence — one (schedule, calendar-day) pair.
    private struct GeneratedOccurrenceKey: Hashable {
        let scheduleID: UUID
        let day: Date
    }

    @discardableResult
    func processDueRecurringTransactions(settings: AppSettings, now: Date = Date()) -> Int {
        guard !data.recurringTransactions.isEmpty else { return 0 }

        let calendar = Calendar.current
        // Bound retroactive catch-up: occurrences older than this window are skipped
        // (the schedule fast-forwards instead of mass-generating back-dated
        // transactions, each of which rewrites snapshot history). Matches the
        // snapshot-backfill window and guards against back-dated edits, long gaps,
        // and past nextDueDate values arriving via sync/import (H7).
        let maxCatchUpDays = 60
        let catchUpFloor = calendar.date(byAdding: .day, value: -maxCatchUpDays, to: now) ?? now
        var generatedCount = 0
        var schedulesChanged = false

        // L53: index every already-generated occurrence by (schedule, day) once, so the per-occurrence
        // dedup check below is an O(1) set lookup instead of an O(transactions) linear scan on every
        // iteration of the nested catch-up loop.
        var generatedOccurrences = Set<GeneratedOccurrenceKey>()
        for transaction in data.transactions {
            guard let id = transaction.recurringTransactionID,
                  let date = transaction.recurringOccurrenceDate else { continue }
            generatedOccurrences.insert(GeneratedOccurrenceKey(scheduleID: id, day: calendar.startOfDay(for: date)))
        }

        for index in data.recurringTransactions.indices {
            var schedule = data.recurringTransactions[index]
            guard schedule.isActive, !schedule.isCompleted else { continue }

            var occurrence = schedule.nextDueDate

            // Fast-forward past occurrences older than the catch-up window without
            // generating them, jumping to the first aligned occurrence in-window.
            if occurrence < catchUpFloor {
                if let caughtUp = schedule.firstOccurrence(onOrAfter: catchUpFloor, calendar: calendar) {
                    occurrence = caughtUp
                    schedule.nextDueDate = caughtUp
                    schedule.updatedAt = now
                    schedulesChanged = true
                } else {
                    // No safe forward occurrence (pathological back-date) — deactivate.
                    schedule.isActive = false
                    schedulesChanged = true
                    data.recurringTransactions[index] = schedule
                    continue
                }
            }

            var processedOccurrences = 0

            while occurrence <= now && processedOccurrences < 1_000 {
                if let endDate = schedule.endDate, occurrence > endDate {
                    schedule.isActive = false
                    schedulesChanged = true
                    break
                }

                // L53: O(1) dedup via the prebuilt set, keyed by calendar day — preserving M24's
                // same-day matching (a lossy/cross-source import reparses `recurringOccurrenceDate` with
                // a different time-of-day, and all current frequencies are ≥1-day-granular, so same-day
                // matching is exact).
                let occurrenceDay = calendar.startOfDay(for: occurrence)
                let alreadyGenerated = generatedOccurrences.contains(
                    GeneratedOccurrenceKey(scheduleID: schedule.id, day: occurrenceDay)
                )

                if !alreadyGenerated {
                    let occurrenceStartOfDay = occurrenceDay
                    let scheduleCurrency = schedule.currency ?? settings.currency
                    let delta: Decimal = schedule.type == .income ? schedule.amount : -schedule.amount
                    adjustHistoricalSnapshots(
                        from: occurrenceStartOfDay,
                        transactionCurrency: scheduleCurrency,
                        displayCurrency: settings.currency,
                        liquidityDelta: settings.convert(delta, from: scheduleCurrency)
                    )

                    data.transactions.append(
                        Transaction(
                            type: schedule.type,
                            category: schedule.category,
                            amount: schedule.amount,
                            description: schedule.description,
                            date: occurrenceStartOfDay,
                            currency: scheduleCurrency,
                            recurringTransactionID: schedule.id,
                            recurringOccurrenceDate: occurrence
                        )
                    )
                    generatedCount += 1
                    // L53: keep the set current so a later occurrence (or another schedule) can't
                    // re-generate this same (schedule, day) within this run.
                    generatedOccurrences.insert(GeneratedOccurrenceKey(scheduleID: schedule.id, day: occurrenceDay))
                }

                guard let next = schedule.frequency.nextDate(
                    after: occurrence,
                    anchoredTo: schedule.startDate,
                    calendar: calendar
                ) else {
                    schedule.isActive = false
                    schedulesChanged = true
                    break
                }

                occurrence = next
                schedule.nextDueDate = next
                schedule.updatedAt = now
                schedulesChanged = true
                processedOccurrences += 1
            }

            if let endDate = schedule.endDate, schedule.nextDueDate > endDate {
                schedule.isActive = false
                schedulesChanged = true
            }

            data.recurringTransactions[index] = schedule
        }

        if generatedCount > 0 {
            appendSnapshot(settings: settings)
        }
        if generatedCount > 0 || schedulesChanged {
            save()
        }
        return generatedCount
    }

    func upsertInvestment(_ investment: Investment, settings: AppSettings) {
        var updated = investment
        updated.updatedAt = Date()
        if let index = data.investments.firstIndex(where: { $0.id == updated.id }) {
            data.investments[index] = updated
        } else {
            data.investments.append(updated)
        }
        appendSnapshot(settings: settings)
        save()
    }

    func deleteInvestment(_ investment: Investment, settings: AppSettings) {
        data.investments.removeAll { $0.id == investment.id }
        appendSnapshot(settings: settings)
        save()
    }

    func upsertCrypto(_ holding: CryptoHolding, settings: AppSettings) {
        var updated = holding
        updated.updatedAt = Date()
        if let index = data.crypto.firstIndex(where: { $0.id == updated.id }) {
            data.crypto[index] = updated
        } else {
            data.crypto.append(updated)
        }
        appendSnapshot(settings: settings)
        save()
    }

    func deleteCrypto(_ holding: CryptoHolding, settings: AppSettings) {
        data.crypto.removeAll { $0.id == holding.id }
        appendSnapshot(settings: settings)
        save()
    }

    func shouldAutoRefreshMarketPrices(staleAfter: TimeInterval = 15 * 60, retryAfter: TimeInterval = 5 * 60, now: Date = Date()) -> Bool {
        guard !data.investments.isEmpty || !data.crypto.isEmpty else { return false }
        if let lastMarketPriceRefreshAttemptAt, now.timeIntervalSince(lastMarketPriceRefreshAttemptAt) < retryAfter {
            return false
        }

        let oldestPriceDate = (data.investments.map(\.updatedAt) + data.crypto.map(\.updatedAt)).min()
        guard let oldestPriceDate else { return true }
        return now.timeIntervalSince(oldestPriceDate) >= staleAfter
    }

    func refreshMarketPrices(finnhubAPIKey: String?, coingeckoAPIKey: String?, settings: AppSettings) async -> MarketPriceRefreshResult {
        guard !isRefreshingMarketPrices else {
            return MarketPriceRefreshResult(wasAlreadyRunning: true)
        }

        isRefreshingMarketPrices = true
        let attemptedAt = Date()
        lastMarketPriceRefreshAttemptAt = attemptedAt
        UserDefaults.standard.set(attemptedAt, forKey: FinanceStore.marketPriceRefreshAttemptKey)
        defer {
            isRefreshingMarketPrices = false
            marketRefreshProgress = nil
        }

        let trimmedFinnhubKey = finnhubAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFinnhubKey = trimmedFinnhubKey?.isEmpty == false
        let trimmedCoinGeckoKey = coingeckoAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCoinGeckoKey = trimmedCoinGeckoKey?.isEmpty == false
        var result = MarketPriceRefreshResult()
        var investmentQuotes: [UUID: MarketPriceQuote] = [:]
        // Each provider yields a price in its own (native) currency; the single conversion to the
        // holding's currency happens once at the apply loop below. H2 (never re-base a holding's
        // currency) holds because that conversion is a no-op when source == holding currency.
        var cryptoQuotes: [UUID: (id: String, price: Double, currency: Currency, asOf: Date)] = [:]

        if data.investments.isEmpty {
            result.skippedInvestments = []
        } else {
            // Finnhub is the primary quote source (US listings). Yahoo is a keyless fallback for
            // anything Finnhub can't price (European ETFs like VWCE) and, when no Finnhub key is
            // set at all, the sole source — so investments still auto-update without a key (I3).
            let finnhubClient: FinnhubQuoteClient?
            if let trimmedFinnhubKey, hasFinnhubKey {
                finnhubClient = FinnhubQuoteClient(apiKey: trimmedFinnhubKey)
            } else {
                finnhubClient = nil
            }
            let yahooClient = YahooQuoteClient()

            // Resolves a holding via Yahoo to a quote in the listing's native currency; the single
            // conversion to the holding's currency happens at the apply loop. `preferredCurrency`
            // still steers disambiguation toward the holding-currency listing (avoids an FX hop).
            func yahooQuote(for investment: Investment) async throws -> MarketPriceQuote {
                try await yahooClient.resolvedQuote(
                    symbol: investment.symbol,
                    isin: investment.isin,
                    name: investment.name,
                    preferredCurrency: investment.currency
                )
            }

            let total = data.investments.count
            var completed = 0
            marketRefreshProgress = (done: 0, total: total)
            // Pace requests to stay under Finnhub's free-tier limit; start small and
            // back off only if we actually get rate-limited (M7). NetworkRetry already
            // retries an individual 429 with backoff (M8); this spaces out the queue.
            var interRequestDelay: UInt64 = 300_000_000 // 0.3s
            // L47: once Finnhub returns a 429, trip a cooldown for the rest of this refresh so each
            // remaining USD holding doesn't independently re-run NetworkRetry's 3 attempts against an
            // already-rate-limited provider — route them to the keyless Yahoo fallback instead.
            var finnhubRateLimited = false
            for investment in data.investments {
                // Finnhub's free tier only prices US/USD listings and its /quote reports no currency,
                // so route only USD holdings to it (deep-audit H13). A non-USD holding goes straight
                // to Yahoo, which returns the listing's real currency — eliminating the "assume the
                // holding's currency" path that silently stored a USD price as e.g. EUR.
                if let finnhubClient, investment.currency == .usd, !finnhubRateLimited {
                    do {
                        investmentQuotes[investment.id] = try await finnhubClient.quote(for: investment.symbol)
                    } catch let marketError as MarketDataError {
                        switch marketError {
                        case .noQuote:
                            // Finnhub doesn't carry this listing (the European-ETF case). Fall back
                            // to Yahoo; a second failure names both providers.
                            do {
                                investmentQuotes[investment.id] = try await yahooQuote(for: investment)
                            } catch {
                                result.failedInvestments.append(
                                    "\(investment.symbol): \(Self.errorMessage(marketError, appLanguage: settings.appLanguage)) \(Self.errorMessage(error, appLanguage: settings.appLanguage))"
                                )
                            }
                        case .rateLimited:
                            // L47: trip the cooldown and fall back to keyless Yahoo for this holding too,
                            // so a rate limit degrades to the other provider instead of a hard failure
                            // (and every remaining USD holding skips Finnhub via the guard above).
                            finnhubRateLimited = true
                            interRequestDelay = min(interRequestDelay * 3, 3_000_000_000) // cap 3s
                            do {
                                investmentQuotes[investment.id] = try await yahooQuote(for: investment)
                            } catch {
                                result.failedInvestments.append(
                                    "\(investment.symbol): \(Self.errorMessage(marketError, appLanguage: settings.appLanguage)) \(Self.errorMessage(error, appLanguage: settings.appLanguage))"
                                )
                            }
                        default:
                            result.failedInvestments.append("\(investment.symbol): \(Self.errorMessage(marketError, appLanguage: settings.appLanguage))")
                        }
                    } catch {
                        result.failedInvestments.append("\(investment.symbol): \(Self.errorMessage(error, appLanguage: settings.appLanguage))")
                    }
                } else {
                    // No Finnhub key, or a non-USD holding (deep-audit H13): Yahoo (keyless) reports
                    // the listing's native currency, so the apply loop stores the price in the
                    // holding's currency without assuming USD.
                    do {
                        investmentQuotes[investment.id] = try await yahooQuote(for: investment)
                    } catch {
                        result.failedInvestments.append("\(investment.symbol): \(Self.errorMessage(error, appLanguage: settings.appLanguage))")
                    }
                }
                completed += 1
                marketRefreshProgress = (done: completed, total: total)
                if completed < total {
                    try? await Task.sleep(nanoseconds: interRequestDelay)
                }
            }
        }

        if hasCoinGeckoKey, let trimmedCoinGeckoKey, !data.crypto.isEmpty {
            // Resolve each holding to a CoinGecko id: explicit coinId / built-in map first, then a
            // /search fallback (I2) so coins outside the built-in map — e.g. "S" — still price
            // instead of being skipped outright.
            let searchClient = CoinGeckoPriceClient(apiKey: trimmedCoinGeckoKey)
            var lookups: [UUID: String] = [:]
            for holding in data.crypto {
                if let coinID = holding.coinGeckoID {
                    lookups[holding.id] = coinID
                }
            }
            for holding in data.crypto where lookups[holding.id] == nil {
                // Non-fatal: a search miss/error just leaves the holding unresolved → skipped below.
                if let resolved = try? await searchClient.searchCoinID(symbol: holding.symbol, name: holding.name) {
                    lookups[holding.id] = resolved
                }
                // M25: pace /search so a first-time refresh with several new coins doesn't burst past
                // CoinGecko's demo-tier rate limit. Resolved ids are persisted (the coinId backfill in
                // the apply loop below), so search runs once per new coin, not on every refresh.
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            let unresolvedIDs = Set(data.crypto.map(\.id)).subtracting(lookups.keys)
            result.skippedCrypto = data.crypto
                .filter { unresolvedIDs.contains($0.id) }
                .map { "\($0.symbol): no matching CoinGecko coin" }

            if !lookups.isEmpty {
                do {
                    // Request every distinct holding currency in one batched call.
                    let neededCurrencies = Array(Set(data.crypto.compactMap { lookups[$0.id] != nil ? $0.currency : nil }))
                    let client = CoinGeckoPriceClient(apiKey: trimmedCoinGeckoKey, currencies: neededCurrencies)
                    let table = try await client.priceTable(for: Array(lookups.values))
                    for holding in data.crypto {
                        guard let coinID = lookups[holding.id] else { continue }
                        guard
                            let coinQuote = table[coinID],
                            let resolved = coinQuote.resolved(in: holding.currency)
                        else {
                            result.failedCrypto.append("\(holding.symbol): no CoinGecko price for \(coinID)")
                            continue
                        }
                        // Store the native price + its currency; the apply loop converts once. H2:
                        // resolved.currency is the holding's own unless CoinGecko lacked it.
                        cryptoQuotes[holding.id] = (coinID, resolved.price, resolved.currency, coinQuote.asOf)
                    }
                } catch {
                    result.failedCrypto = data.crypto
                        .filter { lookups[$0.id] != nil }
                        .map { "\($0.symbol): \(Self.errorMessage(error, appLanguage: settings.appLanguage))" }
                }
            }
        } else if !data.crypto.isEmpty {
            result.skippedCrypto = data.crypto.map { "\($0.symbol): CoinGecko key missing" }
        }

        // "Last updated" must reflect when the user refreshed, not the quote's market timestamp.
        // Assigning the market `asOf` here made the row show the previous market close (e.g. an
        // old date after a weekend refresh) and skewed `shouldAutoRefreshMarketPrices` staleness.
        // Date() matches every other store mutation and the dialog's "Last refresh" line; one
        // timestamp for the whole pass so all touched holdings and `result.refreshedAt` agree.
        let refreshedAt = Date()
        // M26: only append a snapshot + persist/sync when a price actually changed, not merely because
        // a holding was re-priced with the same value (updatedRecordCount counts every re-priced holding).
        var didChangeData = false

        for index in data.investments.indices {
            guard let quote = investmentQuotes[data.investments[index].id] else { continue }
            // Convert into the holding's currency at the single storage boundary (an unknown source
            // currency — Finnhub — is assumed to be the holding's), dropping a non-finite quote
            // rather than corrupting stored money (WC-A1 / WC-H1).
            guard let price = storedPrice(quote.price, from: quote.currency, to: data.investments[index].currency, settings: settings) else { continue }
            // Only write (and bump updatedAt → re-sync) when the price actually moved, so a refresh
            // that re-confirms an unchanged price doesn't churn CloudKit (I1). The count still
            // reflects every holding we re-priced.
            if data.investments[index].currentPrice != price {
                data.investments[index].currentPrice = price
                data.investments[index].currentValue = data.investments[index].quantity * price
                data.investments[index].updatedAt = refreshedAt
                didChangeData = true
            }
            result.updatedInvestments += 1
        }

        for index in data.crypto.indices {
            guard let update = cryptoQuotes[data.crypto[index].id] else { continue }
            // Same single conversion boundary as investments (H2: a no-op when already in-currency).
            guard let price = storedPrice(update.price, from: update.currency, to: data.crypto[index].currency, settings: settings) else { continue }
            let coinIDWasEmpty = data.crypto[index].coinId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Bump updatedAt only on a real content change — a new price or a first-time coinId
            // backfill — so unchanged holdings don't re-sync every refresh (I1).
            if data.crypto[index].currentPrice != price || coinIDWasEmpty {
                data.crypto[index].currentPrice = price
                if coinIDWasEmpty {
                    data.crypto[index].coinId = update.id
                }
                data.crypto[index].updatedAt = refreshedAt
                didChangeData = true
            }
            result.updatedCrypto += 1
        }

        if didChangeData {
            appendSnapshot(settings: settings)
            save()
        }

        result.refreshedAt = refreshedAt
        return result
    }

    /// Single conversion boundary for a freshly fetched market price: converts a `Double` price in
    /// `sourceCurrency` — or the holding's own currency when the source is unknown (Finnhub) — into
    /// `holdingCurrency`, crossing to `Decimal` at the money boundary. Returns nil for a non-finite
    /// quote so a bad value is dropped, not stored (WC-A1 / WC-H1). The convert is a no-op when
    /// source == holding currency, so H2 (never re-base a holding's currency) holds.
    private func storedPrice(
        _ price: Double,
        from sourceCurrency: Currency?,
        to holdingCurrency: Currency,
        settings: AppSettings
    ) -> Decimal? {
        let converted = settings.convert(price, from: sourceCurrency ?? holdingCurrency, to: holdingCurrency)
        return Decimal(finite: converted)
    }

    private let snapshotEngine = SnapshotEngine()

    /// Builds a pure analytics engine bound to the current data + settings (M1).
    private func analytics(_ settings: AppSettings) -> AnalyticsEngine {
        AnalyticsEngine(
            data: data,
            converter: settings.currencyConverter,
            displayCurrency: settings.currency,
            appLanguage: settings.appLanguage
        )
    }

    func calculateTotals(settings: AppSettings) -> FinanceTotals {
        let rateStamp = settings.exchangeRateSnapshot?.fetchedAt
        // Totals now exclude future-dated transactions (deep-audit L51), so the cache must invalidate
        // at midnight — mirror `cachedSnapshotsForChart`'s day stamp.
        let dayStamp = Calendar.current.startOfDay(for: Date())
        if let cache = cachedTotals,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp,
           cache.dayStamp == dayStamp {
            return cache.value
        }
        let totals = analytics(settings).calculateTotals()
        cachedTotals = (dataVersion, settings.currency, rateStamp, dayStamp, totals)
        return totals
    }

    func hasForeignCurrencyExposure(relativeTo baseCurrency: Currency) -> Bool {
        data.investments.contains { $0.currency != baseCurrency }
            || data.crypto.contains { $0.currency != baseCurrency }
            || data.liabilities.contains { $0.currency != baseCurrency }
    }

    func takeSnapshot(settings: AppSettings) {
        appendSnapshot(settings: settings)
        save()
    }

    private func appendSnapshot(settings: AppSettings) {
        let totals = calculateTotals(settings: settings)
        // Tag the row with the base currency the totals are in (deep-audit H11).
        data.snapshots = snapshotEngine.appendingSnapshot(to: data.snapshots, totals: totals, currency: settings.currency)
    }

    private func adjustHistoricalSnapshots(from date: Date, transactionCurrency: Currency, displayCurrency: Currency, liquidityDelta: Decimal) {
        data.snapshots = snapshotEngine.adjustingHistoricalSnapshots(data.snapshots, from: date, transactionCurrency: transactionCurrency, displayCurrency: displayCurrency, liquidityDelta: liquidityDelta)
    }

    func monthlyCashFlow(for month: Date, settings: AppSettings) -> MonthlyCashFlow {
        let rateStamp = settings.exchangeRateSnapshot?.fetchedAt
        let calendar = Calendar.current
        // Normalize the key to the month itself: callers pass `Date()`, which would otherwise never
        // hit the cache; `monthlyCashFlow` groups by `.month` so any date in the month is equivalent.
        let monthKey = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        if let cache = cachedMonthlyCashFlow,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp,
           cache.month == monthKey {
            return cache.value
        }
        let result = analytics(settings).monthlyCashFlow(for: month)
        cachedMonthlyCashFlow = (dataVersion, settings.currency, rateStamp, monthKey, result)
        return result
    }

    func monthlyTransactionCount(for month: Date) -> Int {
        let calendar = Calendar.current
        let monthKey = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        if let cache = cachedMonthlyTransactionCount, cache.version == dataVersion, cache.month == monthKey {
            return cache.value
        }
        // Filter `data.transactions` directly (not the sorted `transactions` accessor) — a count
        // needs no ordering, so this avoids the O(n log n) sort on every cash-flow body pass (M27).
        let count = data.transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }.count
        cachedMonthlyTransactionCount = (dataVersion, monthKey, count)
        return count
    }

    func snapshots(range: TimeRange) -> [NetWorthPoint] {
        AnalyticsEngine(data: data).snapshots(range: range)
    }

    func snapshotsForChart(range: TimeRange, settings: AppSettings) -> [NetWorthPoint] {
        let rateStamp = settings.exchangeRateSnapshot?.fetchedAt
        // The series' range cutoff and today's live point move at midnight, so key on the day too.
        let dayStamp = Calendar.current.startOfDay(for: Date())
        if let cache = cachedSnapshotsForChart,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp,
           cache.range == range,
           cache.dayStamp == dayStamp {
            return cache.value
        }
        let totals = calculateTotals(settings: settings)
        let result = analytics(settings).snapshotsForChart(range: range, currentNetWorth: totals.netWorth.doubleValue)
        cachedSnapshotsForChart = (dataVersion, settings.currency, rateStamp, range, dayStamp, result)
        return result
    }

    func cashFlowTrend(months: Int = 6, settings: AppSettings) -> [CashFlowMonth] {
        let rateStamp = settings.exchangeRateSnapshot?.fetchedAt
        let calendar = Calendar.current
        // The rolling window ends at the current month, so include it in the key (data changes within
        // the month already bump dataVersion; this catches a month rollover with no data change).
        let monthStamp = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        if let cache = cachedCashFlowTrend,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp,
           cache.months == months,
           cache.monthStamp == monthStamp {
            return cache.value
        }
        let result = analytics(settings).cashFlowTrend(months: months)
        cachedCashFlowTrend = (dataVersion, settings.currency, rateStamp, months, monthStamp, result)
        return result
    }

    func expensesByCategory(period: AnalyticsPeriod, settings: AppSettings) -> [CategoryTotal] {
        let rateStamp = settings.exchangeRateSnapshot?.fetchedAt
        // The period windows (last 7/30 days, YTD…) are relative to today, so include the day.
        let dayStamp = Calendar.current.startOfDay(for: Date())
        if let cache = cachedExpensesByCategory,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp,
           cache.period == period,
           cache.dayStamp == dayStamp {
            return cache.value
        }
        let result = analytics(settings).expensesByCategory(period: period)
        cachedExpensesByCategory = (dataVersion, settings.currency, rateStamp, period, dayStamp, result)
        return result
    }

    func assetAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).assetAllocation()
    }

    /// L33: the magnitude of net cash liabilities excluded from the asset-allocation ring (a donut
    /// can't render a negative wedge), or `nil` when cash is non-negative. Lets the ring show a
    /// footnote explaining why its total is higher than the signed net-worth header.
    func assetAllocationExcludedCash(settings: AppSettings) -> Decimal? {
        let liquidity = calculateTotals(settings: settings).totalLiquidity
        return liquidity < 0 ? -liquidity : nil
    }

    /// L40: held currencies that are absent from an otherwise-present exchange-rate snapshot and so
    /// silently convert through their approximate offline seed rate. Returns `[]` when there is no
    /// snapshot yet (a separate "rates not fetched" state) or when every held currency is covered, so
    /// callers can show a "rates may be incomplete" indicator only when it genuinely applies. Sorted
    /// by code for a stable display.
    func heldCurrenciesUsingSeedRate(settings: AppSettings) -> [Currency] {
        guard let snapshot = settings.exchangeRateSnapshot else { return [] }
        var held: Set<Currency> = [settings.currency] // the display currency converts too
        for investment in data.investments { held.insert(investment.currency) }
        for holding in data.crypto { held.insert(holding.currency) }
        for transaction in data.transactions { if let currency = transaction.currency { held.insert(currency) } }
        return held
            .filter { snapshot.unitsPerBaseCurrency(for: $0) == nil }
            .sorted { $0.rawValue < $1.rawValue }
    }

    func investmentAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).investmentAllocation()
    }

    func investmentTypeAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).investmentTypeAllocation()
    }

    func investmentGeographyAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).investmentGeographyAllocation()
    }

    func cryptoAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).cryptoAllocation()
    }

    /// The result of a factory reset, so the UI can word its feedback honestly.
    enum EraseOutcome: Sendable {
        case complete            // device + iCloud copy both wiped
        case localOnlyNoAccount  // device wiped; no iCloud account, so there was nothing to delete server-side
        case localOnly           // device wiped; iCloud copy deliberately left ("delete this device only")
    }

    /// Factory reset ("Erase Everything"). When `deleteCloud` is true, the entire iCloud zone
    /// is deleted FIRST; if that genuinely fails (network/CloudKit) the error propagates and
    /// **the local data is left untouched**, so we never destroy the last copy while claiming a
    /// complete erase. A missing iCloud account is not a failure — it just means there is no
    /// server copy to remove (`.localOnlyNoAccount`). After the cloud step (or immediately, on
    /// the `deleteCloud == false` "delete this device only" escape hatch) the local wipe is
    /// unconditional and best-effort.
    @discardableResult
    func eraseEverything(deleteCloud: Bool) async throws -> EraseOutcome {
        var outcome: EraseOutcome = deleteCloud ? .complete : .localOnly

        if deleteCloud {
            do {
                try await cloudSyncService.purgeCloudData()
            } catch CloudSyncError.accountUnavailable(_) {
                // No usable iCloud account → nothing to delete server-side. Not a failure:
                // fall through to the local wipe and report it honestly.
                outcome = .localOnlyNoAccount
            }
            // Any other error (network/CloudKit) propagates: the caller keeps the local data
            // and offers Retry / Delete this device only.
        }

        await wipeLocalState()
        return outcome
    }

    /// Removes everything this device persists and resets the store to a clean, empty state so
    /// the same long-lived `FinanceStore` instance keeps working after the user re-onboards.
    /// Best-effort throughout: a single failing step must not strand the erase half-done.
    private func wipeLocalState() async {
        // L52: cancel any still-pending init-time sync-enable task first, so it can't resume after the
        // stop() below and re-start the engine against the just-erased state.
        initialSyncEnableTask?.cancel()
        initialSyncEnableTask = nil
        await waitForPendingSaves()
        // Ensure the engine is down before we reset metadata, on every path (the no-account
        // and escape-hatch paths never went through `purgeCloudData`'s own `stop()`).
        await cloudSyncService.stop()

        data = FinancialData()
        try? persistence.clear()          // finance DB + the pre-CloudKit backup sidecar
        try? syncMetadataStore.reset()    // safety net for the local-only / escape-hatch paths
        await coordinator.seed([:])       // reset the diff baseline to match the now-empty DB

        settings?.resetToDefaults()
        KeychainCredentialStore.shared.deleteAll()
        // Scheduled "recurring due" notifications are cancelled by the platform caller — the
        // notification service is platform-specific (iOS/macOS wrappers), so it can't be
        // named from shared code.

        iCloudSyncError = nil
        persistenceError = nil
        localPersistenceError = nil
        cloudSyncStatus = .disabled
        marketRefreshProgress = nil
    }

    func exportBackupURL() async throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "wealth-compass-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        // L55: encode the whole dataset + write off the MainActor so a large DB doesn't freeze the UI.
        // The backup is machine-read, so drop pretty-printing (FinanceJSONCoding.encode defaults to compact).
        let dataCopy = data
        try await Task.detached {
            let payload = try FinanceJSONCoding.encode(dataCopy)
            try payload.write(to: url, options: .atomic)
        }.value
        return url
    }

    /// Writes the recent in-memory sync/persistence telemetry (counts / bytes / ms + errors —
    /// never payloads or amounts; see `SyncDiagnosticsLog`) to a temp `.txt` for the "Export Sync
    /// Diagnostics" support action, and returns its URL. A small non-identifying header (app
    /// version, platform, OS, whether sync is on) precedes the lines. Contains no iCloud account
    /// info and no financial data (#23).
    func exportSyncDiagnosticsURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: Date())

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var lines = [
            "Wealth Compass sync diagnostics",
            "version \(version) (\(build)) · \(platform) · \(os)",
            "iCloud sync: \(isICloudSyncEnabledResolved ? "on" : "off")",
            "generated \(stamp)",
            "(counts/bytes/ms + errors only — no financial data, no account info)",
            ""
        ]
        lines.append(contentsOf: SyncDiagnosticsLog.shared.snapshot())
        let text = lines.joined(separator: "\n") + "\n"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-compass-sync-diagnostics-\(stamp).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    /// Unified import entry point: auto-detects a native JSON backup vs. a supported broker/bank CSV
    /// (Revolut / Trade Republic) by content, parses off the MainActor, then applies via `applyImport`.
    /// The UI calls this so the user never has to pick a format.
    func importFile(from url: URL, mode: FinanceImportMode, settings: AppSettings) async throws -> FinanceImportResult {
        guard localPersistenceError == nil else {
            throw FinanceImportError.localPersistenceError
        }

        let didAccessResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // L55: read + detect + parse off the MainActor; the @Published mutations in applyImport stay on it.
        let context = FinanceImportContext(displayCurrency: settings.currency, snapshot: settings.exchangeRateSnapshot)
        let fileName = url.lastPathComponent
        let parsed = try await Task.detached { () -> (normalized: NormalizedFinanceImport, source: String?) in
            let payload = try Data(contentsOf: url)
            guard !payload.isEmpty else { throw FinanceImportError.emptyFile }
            if financeImportLooksLikeJSON(payload, fileName: fileName) {
                return (try FinanceImportService.parse(payload, context: context), nil)
            }
            let outcome = try BrokerStatementImportService.parse(payload, context: context)
            return (outcome.normalized, outcome.format.displayName)
        }.value

        return try applyImport(
            parsed.normalized,
            mode: mode,
            settings: settings,
            sourceFileName: fileName,
            detectedSource: parsed.source
        )
    }

    /// JSON-backup–only import, retained for existing callers/tests. `importFile` supersedes it for the UI.
    func importBackup(from url: URL, mode: FinanceImportMode, settings: AppSettings) async throws -> FinanceImportResult {
        // Fail loudly if the local DB failed to load: save() is a no-op while `localPersistenceError`
        // is set, so mutating in-memory `data` and reporting success would silently discard the import
        // (deep-audit M28). Mirrors the guards in setICloudSyncEnabled / applyRemoteMutations.
        guard localPersistenceError == nil else {
            throw FinanceImportError.localPersistenceError
        }

        let didAccessResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // L55: read + parse/normalize off the MainActor (the heavy JSON work that used to freeze the UI
        // on a large file). Security-scoped access is process-wide, so it covers the detached read; the
        // value-type `FinanceImportContext` carries the only settings the parser needs. The @Published
        // mutations below stay on the MainActor.
        let context = FinanceImportContext(displayCurrency: settings.currency, snapshot: settings.exchangeRateSnapshot)
        let normalized = try await Task.detached {
            let payload = try Data(contentsOf: url)
            guard !payload.isEmpty else { throw FinanceImportError.emptyFile }
            return try FinanceImportService.parse(payload, context: context)
        }.value

        return try applyImport(
            normalized,
            mode: mode,
            settings: settings,
            sourceFileName: url.lastPathComponent,
            detectedSource: nil
        )
    }

    /// Shared tail for every import path: validates, registers categories, merges/replaces, snapshots,
    /// persists, and builds the summary. Runs on the MainActor (mutates `@Published data`).
    private func applyImport(
        _ normalized: NormalizedFinanceImport,
        mode: FinanceImportMode,
        settings: AppSettings,
        sourceFileName: String,
        detectedSource: String?
    ) throws -> FinanceImportResult {
        guard normalized.data.hasImportableContent else {
            throw FinanceImportError.noSupportedRecords
        }

        let categoriesAdded = registerImportedCategories(from: normalized.data, settings: settings)

        switch mode {
        case .replace:
            data = normalized.data.sortedForStorage()
        case .merge:
            data = data.merged(with: normalized.data).sortedForStorage()
        }

        let shouldGenerateSnapshot = normalized.data.snapshots.isEmpty
        if shouldGenerateSnapshot {
            appendSnapshot(settings: settings)
        }
        save()

        return FinanceImportResult(
            sourceFileName: sourceFileName,
            mode: mode,
            transactions: normalized.data.transactions.count,
            recurringTransactions: normalized.data.recurringTransactions.count,
            investments: normalized.data.investments.count,
            crypto: normalized.data.crypto.count,
            liabilities: normalized.data.liabilities.count,
            snapshots: normalized.data.snapshots.count,
            generatedSnapshots: shouldGenerateSnapshot ? 1 : 0,
            categoriesAdded: categoriesAdded,
            skippedRecords: normalized.skippedRecords,
            detectedSource: detectedSource
        )
    }

    /// Loads the local DB into memory and returns the per-record snapshot that should seed
    /// the coordinator's diff baseline (empty on a load failure, so no save is attempted
    /// until the load error is resolved).
    @discardableResult
    private func load() -> [CloudSyncRecordKey: CloudSyncRecordSnapshot] {
        do {
            let loaded = try persistence.load()
            let loadedData = loaded?.data ?? FinancialData()
            // Deep-audit H08: keys the decode had to skip (undecodable records) — passed to the
            // inventory reconcile below so they're preserved on the server, not tombstoned.
            let skippedRecordKeys = loaded?.skippedRecordKeys ?? []
            // WC-M1 one-time migration: stamp legacy currency-less transactions/schedules with
            // the base currency so old cash stays anchored to it instead of floating when the
            // user later changes their base currency. Records below are taken from the original
            // (pre-migration) `loadedData`, so the post-init save persists exactly these stamps.
            let (migrated, didBackfill) = loadedData.backfillingCurrencies(base: settings?.currency ?? .eur)
            needsCurrencyBackfillSave = didBackfill
            // Plain assignment, not withAnimation: `load()` can run during a view update, where
            // animating a `@Published` write emits "Publishing changes from within view updates"
            // warnings — same reasoning as the remote-apply path below (WC-#17).
            self.data = migrated
            self.localPersistenceError = nil
            self.iCloudSyncError = nil

            do {
                let records = try loadedData.cloudSyncRecords()
                try syncMetadataStore.reconcileLocalInventory(records, skipped: skippedRecordKeys)
                return records
            } catch {
                iCloudSyncError = AppLocalization.string(
                    "Local data loaded, but iCloud sync metadata could not be prepared. \(error.localizedDescription)",
                    appLanguage: settings?.appLanguage
                )
                cloudSyncStatus = .error(iCloudSyncError ?? error.localizedDescription)
                return (try? loadedData.cloudSyncRecords()) ?? [:]
            }
        } catch {
            // Plain assignment, not withAnimation — see the success path above (WC-#17).
            self.localPersistenceError = error
            self.iCloudSyncError = error.localizedDescription
            self.cloudSyncStatus = .error(
                AppLocalization.string(
                    "The local database could not be loaded. The original file was left untouched. \(error.localizedDescription)",
                    appLanguage: settings?.appLanguage
                )
            )
            return [:]
        }
    }

    /// Starts the single long-lived consumer that serializes saves onto the coordinator.
    /// `bufferingNewest(1)` coalesces bursts: while one save runs, only the most recent
    /// queued tick survives, and the consumer always reads the latest `data` (last write
    /// wins).
    private func startSaveConsumer(seedRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot]) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        saveContinuation = continuation
        saveConsumerTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.seed(seedRecords)
            for await generation in stream {
                await self.processSave(generation: generation)
            }
        }
    }

    /// Off-main-actor save: the coordinator does the encode/diff/write/record work; this
    /// method only reads the snapshot and updates main-actor-owned UI state.
    ///
    /// The snapshot is read *live* from `data` here — not frozen when `save()` enqueued the
    /// tick — so a queued local save can never clobber a CloudKit remote mutation that
    /// landed in between: it always persists the latest in-memory state, and a redundant
    /// tick simply diffs to an empty change set.
    private func processSave(generation: Int) async {
        let snapshot = data
        do {
            let outcome = try await coordinator.save(snapshot)
            iCloudSyncError = nil
            persistenceError = nil
            if outcome.didChange {
                await cloudSyncService.localChangesRecorded()
            }
        } catch {
            // Do NOT crash on a disk error (H5): in DEBUG `assertionFailure` aborted the
            // app, and in release the failure was only visible in Settings. Log it and
            // publish an app-wide error so the user learns their change didn't persist.
            Self.logger.error("Failed to save local finance data: \(error.localizedDescription, privacy: .public)")
            SyncDiagnosticsLog.shared.record("ERROR save failed: \(error.localizedDescription)")
            iCloudSyncError = error.localizedDescription
            persistenceError = AppLocalization.string(
                "Your latest change could not be saved to this device. \(error.localizedDescription)",
                appLanguage: settings?.appLanguage
            )
        }
        lastProcessedSaveGeneration = generation
        if lastProcessedSaveGeneration == lastEnqueuedSaveGeneration {
            let waiters = saveIdleWaiters
            saveIdleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private func save() {
        guard localPersistenceError == nil else {
            iCloudSyncError = AppLocalization.string(
                "Changes cannot be saved until the local database load error is resolved.",
                appLanguage: settings?.appLanguage
            )
            return
        }

        // Non-blocking: nudge the serial consumer and return. All encoding, hashing and
        // disk I/O happen off the main actor inside the coordinator.
        lastEnqueuedSaveGeneration += 1
        saveContinuation?.yield(lastEnqueuedSaveGeneration)
    }

    /// Test hook: suspends until the save pipeline has drained every enqueued snapshot.
    func waitForPendingSaves() async {
        if lastProcessedSaveGeneration == lastEnqueuedSaveGeneration { return }
        await withCheckedContinuation { continuation in
            saveIdleWaiters.append(continuation)
        }
    }

    /// Whether iCloud sync is enabled, resolved from settings (falling back to the
    /// persisted default when settings aren't attached yet).
    private var isICloudSyncEnabledResolved: Bool {
        settings?.isICloudSyncEnabled
            ?? UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
    }

    func forceICloudSync() async throws {
        guard isICloudSyncEnabledResolved else {
            throw CloudSyncError.notRunning
        }
        await cloudSyncService.synchronize()
        // Rethrow with the matching error type so Settings can show meaningful copy: an
        // account problem is an account problem, not a bogus "invalid record" (#14).
        switch cloudSyncStatus {
        case .accountUnavailable(let message):
            throw CloudSyncError.accountUnavailable(message)
        case .actionNeeded(let message), .error(let message):
            throw CloudSyncError.syncFailed(message)
        // .waiting is transient (offline/throttled): the calm status row already shows it, so a
        // manual Force Sync doesn't raise an alarming alert.
        case .disabled, .starting, .syncing, .upToDate, .waiting:
            break
        }
    }

    func setICloudSyncEnabled(_ isEnabled: Bool, userInitiated: Bool = true) async {
        if isEnabled {
            guard localPersistenceError == nil else { return }
            // L52: an automatic (init-time restore) enable must re-check the resolved flag right before
            // starting — a factory reset that cleared it between scheduling and running this must not
            // resurrect the engine. A user-initiated enable is itself the source of truth for the flag.
            if !userInitiated {
                guard isICloudSyncEnabledResolved else { return }
            }
            await cloudSyncService.start(allowAccountReplacement: userInitiated)
        } else {
            await cloudSyncService.stop()
        }
    }

    /// Cold launch / app becoming active: make sure the sync engine is running. Starts
    /// it only if it isn't already up, and never forces a sync when already running —
    /// use `requestICloudSync()` for opportunistic foreground syncing (#7).
    func ensureICloudSyncRunning() async {
        guard isICloudSyncEnabledResolved else { return }
        await cloudSyncService.start(allowAccountReplacement: false)
    }

    /// Opportunistic, debounced sync (e.g. on returning to the foreground). No-ops if
    /// sync is disabled or the engine isn't running yet.
    func requestICloudSync() async {
        guard isICloudSyncEnabledResolved else { return }
        await cloudSyncService.requestSync()
    }

    /// M31: a CloudKit silent push means a remote device changed the zone. Ensure the engine is up and
    /// fetch/send promptly — bypassing the foreground opportunistic-sync debounce, since a push already
    /// means "there is a change now". No-op when sync is disabled.
    func syncForRemotePush() async {
        guard isICloudSyncEnabledResolved else { return }
        await cloudSyncService.start(allowAccountReplacement: false) // idempotent; ensures the engine is up
        await cloudSyncService.synchronize()
    }

    /// M31: entry point for the app-delegate remote-notification handlers, which have no environment
    /// injection — routes a received CloudKit push to the single live store's push sync.
    static func handleRemoteCloudKitPush() async {
        await current?.syncForRemotePush()
    }

    private func applyRemoteMutations(
        _ mutations: [CloudSyncRemoteMutation]
    ) async throws -> Set<CloudSyncRecordKey> {
        guard localPersistenceError == nil else {
            throw localPersistenceError ?? CloudSyncError.invalidRecord(
                AppLocalization.string("The local database is unavailable.", appLanguage: settings?.appLanguage)
            )
        }

        let interval = SyncSignpost.persistence.begin("applyRemote")
        let start = DispatchTime.now()
        let incoming = mutations.count
        var applicable = 0
        var applied = 0
        var skipped = 0
        defer {
            SyncSignpost.persistence.emit("applyRemote muts=\(incoming) applicable=\(applicable) applied=\(applied) skipped=\(skipped) ms=\(SyncSignpost.persistence.ms(since: start))")
            SyncSignpost.persistence.end("applyRemote", interval)
        }

        let applicableMutations = mutations.filter {
            syncMetadataStore.pendingRevision(for: $0.key) == $0.expectedPendingRevision
        }
        applicable = applicableMutations.count
        guard !applicableMutations.isEmpty else { return [] }

        var updatedData = data
        let outcome = updatedData.applyCloudSyncMutations(applicableMutations)
        skipped = outcome.skipped.count
        for skip in outcome.skipped {
            // WC-H3: a single undecodable / forward-incompatible record is quarantined here
            // (logged, not thrown) so it can't propagate to handleEvent's catch and disable
            // the whole engine. It's reported as not-applied below, so its metadata
            // (knownLocalHashes) is never advanced and no spurious tombstone is enqueued.
            Self.logger.error("Skipped undecodable remote record \(skip.key.recordName, privacy: .public) (type \(skip.key.type.rawValue, privacy: .public)): \(skip.error.localizedDescription, privacy: .public)")
            SyncDiagnosticsLog.shared.record("ERROR skipped remote record \(skip.key.recordName) (type \(skip.key.type.rawValue)): \(skip.error.localizedDescription)")
        }
        // Nothing decoded — don't persist or advance the baseline; report none-applied so
        // every key is treated as not-applied by the caller.
        guard !outcome.appliedKeys.isEmpty else { return [] }
        updatedData = updatedData.sortedForStorage()
        // Update the in-memory data synchronously on the main actor so the UI stays
        // responsive and reads stay consistent. Plain assignment (no withAnimation):
        // remote applies are driven from CloudKit callbacks and can land during a SwiftUI
        // view update, which makes `withAnimation` emit "Publishing changes from within
        // view updates" and forces expensive animation transactions during bulk sync.
        data = updatedData
        iCloudSyncError = nil
        // Route the disk write through the coordinator so local + remote writes serialize
        // and never interleave, and so the diff baseline advances to the applied records.
        try await coordinator.applyRemote(updatedData)
        applied = outcome.appliedKeys.count
        return outcome.appliedKeys
    }

    private func updateCloudSyncStatus(_ status: CloudSyncStatus) {
        cloudSyncStatus = status
        switch status {
        case .error(let message), .accountUnavailable(let message), .actionNeeded(let message):
            iCloudSyncError = message
        // .waiting is transient, not a failure → don't raise the error flag (keeps the UI calm).
        case .disabled, .starting, .syncing, .upToDate, .waiting:
            if localPersistenceError == nil {
                iCloudSyncError = nil
            }
        }
    }

    // L26: resolve app-defined errors through their appLanguage-aware description so market-refresh
    // failure summaries follow the in-app language instead of the system locale.
    private static func errorMessage(_ error: Error, appLanguage: String?) -> String {
        if let error = error as? MarketDataError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? ExchangeRateError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? FinanceImportError { return error.localizedDescription(appLanguage: appLanguage) }
        if let error = error as? CloudSyncError { return error.localizedDescription(appLanguage: appLanguage) }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func registerImportedCategories(from importedData: FinancialData, settings: AppSettings) -> Int {
        var added = 0
        let categories = importedData.transactions.map { ($0.type, $0.category) }
            + importedData.recurringTransactions.map { ($0.type, $0.category) }

        for (type, category) in categories {
            let existing = settings.transactionCategories(for: type)
            guard !existing.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) else {
                continue
            }

            if settings.addCustomTransactionCategory(category, for: type) != nil {
                added += 1
            }
        }
        return added
    }
}

extension FinancialData {
    var hasImportableContent: Bool {
        !transactions.isEmpty || !recurringTransactions.isEmpty || !investments.isEmpty
            || !crypto.isEmpty || !liabilities.isEmpty || !snapshots.isEmpty
    }

    /// One-time WC-M1 / deep-audit H11 migration: stamps legacy transactions, recurring schedules,
    /// and net-worth snapshots that predate the per-record `currency` field (so their `currency` is
    /// `nil`) with `base`. This freezes pre-existing cash **and stored history** at the base currency
    /// in effect at first launch after the update, instead of letting them silently re-value when the
    /// user later changes their base currency. Stamped snapshots then reconvert correctly on a base
    /// change (`AnalyticsEngine.snapshots`) rather than being read at the wrong scale.
    func backfillingCurrencies(base: Currency) -> (data: FinancialData, didChange: Bool) {
        var copy = self
        var changed = false
        for index in copy.transactions.indices where copy.transactions[index].currency == nil {
            copy.transactions[index].currency = base
            changed = true
        }
        for index in copy.recurringTransactions.indices where copy.recurringTransactions[index].currency == nil {
            copy.recurringTransactions[index].currency = base
            changed = true
        }
        for index in copy.snapshots.indices where copy.snapshots[index].currency == nil {
            copy.snapshots[index].currency = base
            changed = true
        }
        return (copy, changed)
    }

    func sortedForStorage() -> FinancialData {
        FinancialData(
            transactions: transactions.sorted {
                if $0.date == $1.date { return $0.createdAt > $1.createdAt }
                return $0.date > $1.date
            },
            recurringTransactions: recurringTransactions.sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                if $0.isActive != $1.isActive { return $0.isActive }
                return $0.nextDueDate < $1.nextDueDate
            },
            investments: investments.sorted { $0.currentValue > $1.currentValue },
            crypto: crypto.sorted { $0.currentValue > $1.currentValue },
            liabilities: liabilities.sorted { $0.updatedAt > $1.updatedAt },
            // Collapse any duplicate same-day snapshots (deep-audit H14) before storing. This is the
            // shared chokepoint for replace-import, merge-import, and the remote-apply path, so a
            // cross-device or imported duplicate can't survive to be double-corrected. Already
            // returns rows sorted ascending by date.
            snapshots: snapshots.collapsedByCalendarDay()
        )
    }
}

/// Serializes every local-database write off the main actor (audit M4).
///
/// Owns `persistence`, `metadataStore`, and the diff baseline (`lastSavedRecords`) — the
/// latter replaces `FinanceStore.persistedData` as the source of truth for diffing. Because
/// it is an actor whose methods contain no internal suspension points, calls run to
/// completion one at a time: local saves (via `save`) and remote applies (via `applyRemote`)
/// never interleave on disk, and the baseline always advances atomically with the write.
actor PersistenceCoordinator {
    struct SaveOutcome: Sendable {
        let didChange: Bool
    }

    private let persistence: FinancePersistence
    private let metadataStore: CloudSyncMetadataStore
    /// The per-record snapshot of what is currently on disk; the baseline every save diffs
    /// against. Advanced only after a successful write, so a failed write cannot corrupt it.
    private var lastSavedRecords: [CloudSyncRecordKey: CloudSyncRecordSnapshot] = [:]

    init(persistence: FinancePersistence, metadataStore: CloudSyncMetadataStore) {
        self.persistence = persistence
        self.metadataStore = metadataStore
    }

    /// Seeds the diff baseline from the records loaded at startup.
    func seed(_ records: [CloudSyncRecordKey: CloudSyncRecordSnapshot]) {
        lastSavedRecords = records
    }

    /// Encodes the snapshot, diffs it against the baseline, writes it to disk, records the
    /// changeset for CloudKit, then advances the baseline. All off the main actor.
    func save(_ snapshot: FinancialData) throws -> SaveOutcome {
        let interval = SyncSignpost.persistence.begin("save")
        let start = DispatchTime.now()
        defer { SyncSignpost.persistence.end("save", interval) }
        let newRecords = try snapshot.cloudSyncRecords()
        let changes = CloudSyncChangeSet.difference(from: lastSavedRecords, to: newRecords)
        try persistence.save(snapshot)
        try metadataStore.recordLocalChanges(changes, currentRecords: newRecords)
        lastSavedRecords = newRecords
        SyncSignpost.persistence.emit("save records=\(newRecords.count) changed=\(changes.changed.count) deleted=\(changes.deleted.count) ms=\(SyncSignpost.persistence.ms(since: start))")
        return SaveOutcome(didChange: !changes.isEmpty)
    }

    /// Persists a snapshot produced by applying remote mutations and advances the baseline
    /// to match. No changeset is recorded — the change originated remotely, and the sync
    /// engine has already updated its own metadata for these records.
    func applyRemote(_ snapshot: FinancialData) throws {
        let newRecords = try snapshot.cloudSyncRecords()
        try persistence.save(snapshot)
        lastSavedRecords = newRecords
    }
}
