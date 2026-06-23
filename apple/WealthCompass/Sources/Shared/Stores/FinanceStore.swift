import Foundation
import OSLog
import SwiftUI

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

struct FinanceImportResult {
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

        return lines.joined(separator: "\n\n")
    }
}

enum FinanceImportError: LocalizedError {
    case emptyFile
    case invalidJSON(String)
    case noSupportedRecords

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
            AppLocalization.string("No supported finance records were found in the selected JSON file.", appLanguage: appLanguage)
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
    private var cachedTotals: (version: Int, currency: Currency, rateStamp: Date?, value: FinanceTotals)?
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
    private let encoder: JSONEncoder
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
    /// Generation bookkeeping (main-actor only) used to know when the save pipeline is
    /// idle — both for correctness reasoning and for deterministic tests.
    private var lastEnqueuedSaveGeneration = 0
    private var lastProcessedSaveGeneration = 0
    private var saveIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var localPersistenceError: Error?
    private var lastMarketPriceRefreshAttemptAt: Date?

    private lazy var cloudSyncService = CloudKitSyncService(
        metadataStore: syncMetadataStore,
        snapshotProvider: { [weak self] in
            guard let self else { return [:] }
            return try self.data.cloudSyncRecords()
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
        encoder = FinanceJSONCoding.makeEncoder(prettyPrinted: true)

        let seedRecords = load()
        startSaveConsumer(seedRecords: seedRecords)
        let isSyncEnabled = settings?.isICloudSyncEnabled
            ?? UserDefaults.standard.bool(forKey: "wc_mobile_icloud_sync_enabled")
        if isSyncEnabled {
            Task { [weak self] in
                await self?.setICloudSyncEnabled(true, userInitiated: false)
            }
        }
    }

    deinit {
        saveContinuation?.finish()
        saveConsumerTask?.cancel()
    }

    var transactions: [Transaction] {
        data.transactions.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.createdAt > rhs.createdAt }
            return lhs.date > rhs.date
        }
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

    func addTransaction(type: TransactionType, amount: Double, category: String, description: String, date: Date, settings: AppSettings) {
        let transaction = Transaction(
            type: type,
            category: category,
            amount: amount,
            description: description,
            date: Calendar.current.startOfDay(for: date)
        )
        
        let delta = type == .income ? amount : -amount
        adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: delta)
        
        data.transactions.append(transaction)
        appendSnapshot(settings: settings)
        save()
    }

    func deleteTransaction(_ transaction: Transaction, settings: AppSettings) {
        let delta = transaction.type == .income ? -transaction.amount : transaction.amount
        adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: delta)
        
        data.transactions.removeAll { $0.id == transaction.id }
        appendSnapshot(settings: settings)
        save()
    }

    func updateTransaction(_ transaction: Transaction, type: TransactionType, amount: Double, category: String, description: String, date: Date, settings: AppSettings) {
        guard let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        
        let oldDelta = transaction.type == .income ? -transaction.amount : transaction.amount
        adjustHistoricalSnapshots(from: transaction.date, liquidityDelta: oldDelta)
        
        let newDate = Calendar.current.startOfDay(for: date)
        let newDelta = type == .income ? amount : -amount
        adjustHistoricalSnapshots(from: newDate, liquidityDelta: newDelta)
        
        data.transactions[index].type = type
        data.transactions[index].amount = amount
        data.transactions[index].category = category
        data.transactions[index].description = description
        data.transactions[index].date = newDate
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

                let alreadyGenerated = data.transactions.contains { transaction in
                    guard
                        transaction.recurringTransactionID == schedule.id,
                        let generatedDate = transaction.recurringOccurrenceDate
                    else {
                        return false
                    }
                    return abs(generatedDate.timeIntervalSince(occurrence)) < 1
                }

                if !alreadyGenerated {
                    let occurrenceStartOfDay = calendar.startOfDay(for: occurrence)
                    let delta = schedule.type == .income ? schedule.amount : -schedule.amount
                    adjustHistoricalSnapshots(from: occurrenceStartOfDay, liquidityDelta: delta)
                    
                    data.transactions.append(
                        Transaction(
                            type: schedule.type,
                            category: schedule.category,
                            amount: schedule.amount,
                            description: schedule.description,
                            date: occurrenceStartOfDay,
                            recurringTransactionID: schedule.id,
                            recurringOccurrenceDate: occurrence
                        )
                    )
                    generatedCount += 1
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
        lastMarketPriceRefreshAttemptAt = Date()
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
        // Price is resolved into each holding's own currency at fetch time, so a
        // refresh never re-bases a holding's cost-basis currency (H2).
        var cryptoQuotes: [UUID: (id: String, price: Double, asOf: Date)] = [:]

        if data.investments.isEmpty {
            result.skippedInvestments = []
        } else if let trimmedFinnhubKey, hasFinnhubKey {
            let client = FinnhubQuoteClient(apiKey: trimmedFinnhubKey)
            let total = data.investments.count
            var completed = 0
            marketRefreshProgress = (done: 0, total: total)
            // Pace requests to stay under Finnhub's free-tier limit; start small and
            // back off only if we actually get rate-limited (M7). NetworkRetry already
            // retries an individual 429 with backoff (M8); this spaces out the queue.
            var interRequestDelay: UInt64 = 300_000_000 // 0.3s
            for investment in data.investments {
                do {
                    investmentQuotes[investment.id] = try await client.quote(for: investment.symbol)
                } catch {
                    result.failedInvestments.append("\(investment.symbol): \(Self.errorMessage(error))")
                    if let marketError = error as? MarketDataError, case .rateLimited = marketError {
                        interRequestDelay = min(interRequestDelay * 3, 3_000_000_000) // cap 3s
                    }
                }
                completed += 1
                marketRefreshProgress = (done: completed, total: total)
                if completed < total {
                    try? await Task.sleep(nanoseconds: interRequestDelay)
                }
            }
        } else {
            result.skippedInvestments = data.investments.map { "\($0.symbol): Finnhub key missing" }
        }

        if !data.crypto.isEmpty, !hasCoinGeckoKey {
            result.skippedCrypto = data.crypto.map { "\($0.symbol): CoinGecko key missing" }
        }

        let cryptoLookups: [UUID: String]
        if hasCoinGeckoKey {
            cryptoLookups = Dictionary(uniqueKeysWithValues: data.crypto.compactMap { holding -> (UUID, String)? in
                guard let coinID = holding.coinGeckoID else { return nil }
                return (holding.id, coinID)
            })
            let skippedCryptoIDs = Set(data.crypto.map(\.id)).subtracting(cryptoLookups.keys)
            result.skippedCrypto = data.crypto
                .filter { skippedCryptoIDs.contains($0.id) }
                .map { "\($0.symbol): CoinGecko ID missing" }
        } else {
            cryptoLookups = [:]
        }

        if let trimmedCoinGeckoKey, hasCoinGeckoKey, !cryptoLookups.isEmpty {
            do {
                // Request every distinct holding currency in one batched call.
                let neededCurrencies = Array(Set(data.crypto.compactMap { cryptoLookups[$0.id] != nil ? $0.currency : nil }))
                let client = CoinGeckoPriceClient(apiKey: trimmedCoinGeckoKey, currencies: neededCurrencies)
                let table = try await client.priceTable(for: Array(cryptoLookups.values))
                for holding in data.crypto {
                    guard let coinID = cryptoLookups[holding.id] else { continue }
                    guard
                        let coinQuote = table[coinID],
                        let resolved = coinQuote.resolved(in: holding.currency)
                    else {
                        result.failedCrypto.append("\(holding.symbol): no CoinGecko price for \(coinID)")
                        continue
                    }
                    // Always express the live price in the holding's own currency,
                    // converting only if the provider couldn't return that currency.
                    let priceInHoldingCurrency = settings.convert(resolved.price, from: resolved.currency, to: holding.currency)
                    cryptoQuotes[holding.id] = (coinID, priceInHoldingCurrency, coinQuote.asOf)
                }
            } catch {
                result.failedCrypto = data.crypto
                    .filter { cryptoLookups[$0.id] != nil }
                    .map { "\($0.symbol): \(Self.errorMessage(error))" }
            }
        }

        for index in data.investments.indices {
            guard let quote = investmentQuotes[data.investments[index].id] else { continue }
            data.investments[index].currentPrice = quote.price
            data.investments[index].currentValue = data.investments[index].quantity * quote.price
            data.investments[index].updatedAt = quote.asOf
            result.updatedInvestments += 1
        }

        for index in data.crypto.indices {
            guard let update = cryptoQuotes[data.crypto[index].id] else { continue }
            data.crypto[index].currentPrice = update.price
            // Note: holding.currency is intentionally NOT overwritten here (H2) — the
            // price above is already expressed in the holding's existing currency.
            if data.crypto[index].coinId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                data.crypto[index].coinId = update.id
            }
            data.crypto[index].updatedAt = update.asOf
            result.updatedCrypto += 1
        }

        if result.updatedRecordCount > 0 {
            appendSnapshot(settings: settings)
            save()
        }

        result.refreshedAt = Date()
        return result
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
        if let cache = cachedTotals,
           cache.version == dataVersion,
           cache.currency == settings.currency,
           cache.rateStamp == rateStamp {
            return cache.value
        }
        let totals = analytics(settings).calculateTotals()
        cachedTotals = (dataVersion, settings.currency, rateStamp, totals)
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
        data.snapshots = snapshotEngine.appendingSnapshot(to: data.snapshots, totals: totals)
    }

    private func adjustHistoricalSnapshots(from date: Date, liquidityDelta: Double) {
        data.snapshots = snapshotEngine.adjustingHistoricalSnapshots(data.snapshots, from: date, liquidityDelta: liquidityDelta)
    }

    func monthlyCashFlow(for month: Date) -> MonthlyCashFlow {
        AnalyticsEngine(data: data).monthlyCashFlow(for: month)
    }

    func snapshots(range: TimeRange) -> [NetWorthPoint] {
        AnalyticsEngine(data: data).snapshots(range: range)
    }

    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        AnalyticsEngine(data: data).cashFlowTrend(months: months)
    }

    func expensesByCategory(period: AnalyticsPeriod) -> [CategoryTotal] {
        AnalyticsEngine(data: data).expensesByCategory(period: period)
    }

    func spendingTimeline(period: AnalyticsPeriod) -> [CategoryTotal] {
        AnalyticsEngine(data: data).spendingTimeline(period: period)
    }

    func assetAllocation(settings: AppSettings) -> [AllocationSlice] {
        analytics(settings).assetAllocation()
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

    func clearData() {
        data = FinancialData()
        save()
    }

    func exportBackupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "wealth-compass-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let payload = try encoder.encode(data)
        try payload.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func importBackup(from url: URL, mode: FinanceImportMode, settings: AppSettings) throws -> FinanceImportResult {
        let didAccessResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let payload = try Data(contentsOf: url)
        guard !payload.isEmpty else { throw FinanceImportError.emptyFile }

        let normalized = try FinanceImportService.parse(payload, settings: settings)
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
            sourceFileName: url.lastPathComponent,
            mode: mode,
            transactions: normalized.data.transactions.count,
            recurringTransactions: normalized.data.recurringTransactions.count,
            investments: normalized.data.investments.count,
            crypto: normalized.data.crypto.count,
            liabilities: normalized.data.liabilities.count,
            snapshots: normalized.data.snapshots.count,
            generatedSnapshots: shouldGenerateSnapshot ? 1 : 0,
            categoriesAdded: categoriesAdded,
            skippedRecords: normalized.skippedRecords
        )
    }

    /// Loads the local DB into memory and returns the per-record snapshot that should seed
    /// the coordinator's diff baseline (empty on a load failure, so no save is attempted
    /// until the load error is resolved).
    @discardableResult
    private func load() -> [CloudSyncRecordKey: CloudSyncRecordSnapshot] {
        do {
            let loadedData = try persistence.load() ?? FinancialData()
            withAnimation {
                self.data = loadedData
                self.localPersistenceError = nil
                self.iCloudSyncError = nil
            }

            do {
                let records = try loadedData.cloudSyncRecords()
                try syncMetadataStore.reconcileLocalInventory(records)
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
            withAnimation {
                self.localPersistenceError = error
                self.iCloudSyncError = error.localizedDescription
                self.cloudSyncStatus = .error(
                    AppLocalization.string(
                        "The local database could not be loaded. The original file was left untouched. \(error.localizedDescription)",
                        appLanguage: settings?.appLanguage
                    )
                )
            }
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
        case .error(let message):
            throw CloudSyncError.syncFailed(message)
        case .disabled, .starting, .syncing, .upToDate:
            break
        }
    }

    func setICloudSyncEnabled(_ isEnabled: Bool, userInitiated: Bool = true) async {
        if isEnabled {
            guard localPersistenceError == nil else { return }
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

    private func applyRemoteMutations(
        _ mutations: [CloudSyncRemoteMutation]
    ) async throws -> Set<CloudSyncRecordKey> {
        guard localPersistenceError == nil else {
            throw localPersistenceError ?? CloudSyncError.invalidRecord(
                AppLocalization.string("The local database is unavailable.", appLanguage: settings?.appLanguage)
            )
        }

        let applicableMutations = mutations.filter {
            syncMetadataStore.pendingRevision(for: $0.key) == $0.expectedPendingRevision
        }
        guard !applicableMutations.isEmpty else { return [] }

        var updatedData = data
        try updatedData.applyCloudSyncMutations(applicableMutations)
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
        return Set(applicableMutations.map(\.key))
    }

    private func updateCloudSyncStatus(_ status: CloudSyncStatus) {
        cloudSyncStatus = status
        switch status {
        case .error(let message), .accountUnavailable(let message):
            iCloudSyncError = message
        case .disabled, .starting, .syncing, .upToDate:
            if localPersistenceError == nil {
                iCloudSyncError = nil
            }
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            snapshots: snapshots.sorted { $0.date < $1.date }
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
        let newRecords = try snapshot.cloudSyncRecords()
        let changes = CloudSyncChangeSet.difference(from: lastSavedRecords, to: newRecords)
        try persistence.save(snapshot)
        try metadataStore.recordLocalChanges(changes, currentRecords: newRecords)
        lastSavedRecords = newRecords
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
