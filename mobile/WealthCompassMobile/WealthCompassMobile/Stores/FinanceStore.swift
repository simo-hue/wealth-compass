import Foundation
import SwiftUI

enum FinanceImportMode: String, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }
}

struct FinanceImportResult {
    let sourceFileName: String
    let mode: FinanceImportMode
    let transactions: Int
    let investments: Int
    let crypto: Int
    let liabilities: Int
    let snapshots: Int
    let generatedSnapshots: Int
    let categoriesAdded: Int
    let skippedRecords: Int

    var importedRecordCount: Int {
        transactions + investments + crypto + liabilities + snapshots
    }

    var message: String {
        var lines = [
            "\(mode.title) import completed for \(sourceFileName).",
            "\(transactions) transactions, \(investments) investments, \(crypto) crypto holdings, \(liabilities) liabilities, and \(snapshots) snapshots were imported."
        ]

        if generatedSnapshots > 0 {
            lines.append("\(generatedSnapshots) current snapshot was generated after import.")
        }

        if categoriesAdded > 0 {
            lines.append("\(categoriesAdded) custom cash-flow categories were added.")
        }

        if skippedRecords > 0 {
            lines.append("\(skippedRecords) malformed or incomplete records were skipped.")
        }

        return lines.joined(separator: "\n\n")
    }
}

enum FinanceImportError: LocalizedError {
    case emptyFile
    case invalidJSON(String)
    case noSupportedRecords

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "The selected file is empty."
        case .invalidJSON(let details):
            "The selected file is not a valid Wealth Compass JSON backup. \(details)"
        case .noSupportedRecords:
            "No supported finance records were found in the selected JSON file."
        }
    }
}

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var data = FinancialData()

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageURL = documents.appendingPathComponent("wealth-compass-local-data.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    var transactions: [Transaction] {
        data.transactions.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.createdAt > rhs.createdAt }
            return lhs.date > rhs.date
        }
    }

    func addTransaction(type: TransactionType, amount: Double, category: String, description: String, date: Date, settings: AppSettings) {
        let transaction = Transaction(
            type: type,
            category: category,
            amount: amount,
            description: description,
            date: Calendar.current.startOfDay(for: date)
        )
        data.transactions.append(transaction)
        appendSnapshot(settings: settings)
        save()
    }

    func deleteTransaction(_ transaction: Transaction, settings: AppSettings) {
        data.transactions.removeAll { $0.id == transaction.id }
        appendSnapshot(settings: settings)
        save()
    }

    func upsertInvestment(_ investment: Investment, settings: AppSettings) {
        if let index = data.investments.firstIndex(where: { $0.id == investment.id }) {
            data.investments[index] = investment
        } else {
            data.investments.append(investment)
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
        if let index = data.crypto.firstIndex(where: { $0.id == holding.id }) {
            data.crypto[index] = holding
        } else {
            data.crypto.append(holding)
        }
        appendSnapshot(settings: settings)
        save()
    }

    func deleteCrypto(_ holding: CryptoHolding, settings: AppSettings) {
        data.crypto.removeAll { $0.id == holding.id }
        appendSnapshot(settings: settings)
        save()
    }

    func calculateTotals(settings: AppSettings) -> FinanceTotals {
        let income = data.transactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
        let expenses = data.transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }

        let totalLiquidity = income - expenses
        let totalInvestments = data.investments.reduce(0) {
            $0 + settings.convert($1.currentValue, from: $1.currency)
        }
        let totalCrypto = data.crypto.reduce(0) {
            $0 + settings.convert($1.currentValue, from: $1.currency)
        }
        let totalLiabilities = data.liabilities.reduce(0) {
            $0 + settings.convert($1.currentBalance, from: $1.currency)
        }
        let totalAssets = totalLiquidity + totalInvestments + totalCrypto

        return FinanceTotals(
            totalLiquidity: totalLiquidity,
            totalInvestments: totalInvestments,
            totalCrypto: totalCrypto,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: totalAssets - totalLiabilities
        )
    }

    func takeSnapshot(settings: AppSettings) {
        appendSnapshot(settings: settings)
        save()
    }

    private func appendSnapshot(settings: AppSettings) {
        let totals = calculateTotals(settings: settings)
        let snapshot = NetWorthSnapshot(
            date: Date(),
            totalAssets: totals.totalAssets,
            totalLiabilities: totals.totalLiabilities,
            netWorth: totals.netWorth,
            liquidity: totals.totalLiquidity,
            investments: totals.totalInvestments,
            crypto: totals.totalCrypto
        )
        data.snapshots.append(snapshot)
        data.snapshots.sort { $0.date < $1.date }
    }

    func monthlyCashFlow(for month: Date) -> MonthlyCashFlow {
        let calendar = Calendar.current
        let income = data.transactions
            .filter { $0.type == .income && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let expenses = data.transactions
            .filter { $0.type == .expense && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        return MonthlyCashFlow(monthlyIncome: income, monthlyExpenses: expenses)
    }

    func snapshots(range: TimeRange) -> [NetWorthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let cutoff: Date

        switch range {
        case .oneWeek:
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .oneMonth:
            cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        case .sixMonths:
            cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        case .oneYear:
            cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .all:
            cutoff = .distantPast
        }

        return data.snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { NetWorthPoint(date: $0.date, value: $0.netWorth) }
    }

    func cashFlowTrend(months: Int = 6) -> [CashFlowMonth] {
        let calendar = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"

        return stride(from: months - 1, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let monthKey = monthFormatter.string(from: date)
            let transactions = data.transactions.filter { monthFormatter.string(from: $0.date) == monthKey }
            let income = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let expense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

            return CashFlowMonth(
                monthKey: monthKey,
                monthLabel: labelFormatter.string(from: date),
                income: income,
                expense: expense
            )
        }
    }

    func expensesByCategory(period: AnalyticsPeriod) -> [CategoryTotal] {
        let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let total = grouped.values.reduce(0, +)

        return grouped.map { key, value in
            CategoryTotal(name: key, value: value, percentage: total > 0 ? (value / total) * 100 : 0)
        }
        .sorted { $0.value > $1.value }
    }

    func spendingTimeline(period: AnalyticsPeriod) -> [CategoryTotal] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        let expenses = filteredTransactions(period: period).filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses) { formatter.string(from: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        return grouped.map { CategoryTotal(name: $0.key, value: $0.value, percentage: 0) }
            .sorted { $0.name < $1.name }
    }

    func assetAllocation(settings: AppSettings) -> [AllocationSlice] {
        let totals = calculateTotals(settings: settings)
        return [
            AllocationSlice(name: "Investments", value: totals.totalInvestments, color: .blue),
            AllocationSlice(name: "Crypto", value: totals.totalCrypto, color: .orange),
            AllocationSlice(name: "Cash", value: totals.totalLiquidity, color: .green)
        ].filter { $0.value > 0 }
    }

    func investmentAllocation(settings: AppSettings) -> [AllocationSlice] {
        let grouped = Dictionary(grouping: data.investments, by: \.sector)
            .mapValues { items in
                items.reduce(0) { partial, investment in
                    partial + settings.convert(investment.currentValue, from: investment.currency)
                }
            }
        return grouped.enumerated().map { index, item in
            AllocationSlice(name: item.key, value: item.value, color: ColorPalette.chart[index % ColorPalette.chart.count])
        }
        .sorted { $0.value > $1.value }
    }

    func cryptoAllocation(settings: AppSettings) -> [AllocationSlice] {
        data.crypto.enumerated().map { index, holding in
            AllocationSlice(
                name: holding.symbol,
                value: settings.convert(holding.currentValue, from: holding.currency),
                color: ColorPalette.chart[index % ColorPalette.chart.count]
            )
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
    }

    func clearData() {
        data = FinancialData()
        try? FileManager.default.removeItem(at: storageURL)
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

        let imported: ImportedFinancialData
        do {
            imported = try JSONDecoder().decode(ImportedFinancialData.self, from: payload)
        } catch {
            throw FinanceImportError.invalidJSON(error.localizedDescription)
        }

        let normalized = imported.normalized(settings: settings)
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
            investments: normalized.data.investments.count,
            crypto: normalized.data.crypto.count,
            liabilities: normalized.data.liabilities.count,
            snapshots: normalized.data.snapshots.count,
            generatedSnapshots: shouldGenerateSnapshot ? 1 : 0,
            categoriesAdded: categoriesAdded,
            skippedRecords: normalized.skippedRecords
        )
    }

    private func filteredTransactions(period: AnalyticsPeriod) -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let start: Date

        switch period {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        case .threeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: now) ?? .distantPast
        case .yearToDate:
            start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? .distantPast
        case .all:
            return data.transactions
        }

        return data.transactions.filter { $0.date >= start && $0.date <= now }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let payload = try Data(contentsOf: storageURL)
            data = try decoder.decode(FinancialData.self, from: payload)
        } catch {
            data = FinancialData()
        }
    }

    private func save() {
        do {
            let payload = try encoder.encode(data)
            try payload.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save local finance data: \(error)")
        }
    }

    private func registerImportedCategories(from importedData: FinancialData, settings: AppSettings) -> Int {
        var added = 0
        for transaction in importedData.transactions {
            let existing = settings.transactionCategories(for: transaction.type)
            guard !existing.contains(where: { $0.caseInsensitiveCompare(transaction.category) == .orderedSame }) else {
                continue
            }

            if settings.addCustomTransactionCategory(transaction.category, for: transaction.type) != nil {
                added += 1
            }
        }
        return added
    }
}

private struct NormalizedFinanceImport {
    var data: FinancialData
    var skippedRecords: Int
}

private struct ImportedFinancialData: Decodable {
    private let income: LossyArray<ImportedIncomeEntry>
    private let expenses: LossyArray<ImportedExpenseEntry>
    private let investments: LossyArray<ImportedInvestment>
    private let crypto: LossyArray<ImportedCryptoHolding>
    private let liabilities: LossyArray<ImportedLiability>
    private let liquidity: LossyArray<ImportedLiquidityAccount>
    private let transactions: LossyArray<ImportedTransaction>
    private let snapshots: LossyArray<ImportedSnapshot>

    private enum CodingKeys: String, CodingKey {
        case income
        case expenses
        case investments
        case crypto
        case liabilities
        case liquidity
        case transactions
        case snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        income = container.decodeLossyArrayIfPresent(ImportedIncomeEntry.self, forKey: .income)
        expenses = container.decodeLossyArrayIfPresent(ImportedExpenseEntry.self, forKey: .expenses)
        investments = container.decodeLossyArrayIfPresent(ImportedInvestment.self, forKey: .investments)
        crypto = container.decodeLossyArrayIfPresent(ImportedCryptoHolding.self, forKey: .crypto)
        liabilities = container.decodeLossyArrayIfPresent(ImportedLiability.self, forKey: .liabilities)
        liquidity = container.decodeLossyArrayIfPresent(ImportedLiquidityAccount.self, forKey: .liquidity)
        transactions = container.decodeLossyArrayIfPresent(ImportedTransaction.self, forKey: .transactions)
        snapshots = container.decodeLossyArrayIfPresent(ImportedSnapshot.self, forKey: .snapshots)
    }

    @MainActor
    func normalized(settings: AppSettings) -> NormalizedFinanceImport {
        let importedTransactions = transactions.elements.compactMap { $0.model() }
        let importedIncome = income.elements.compactMap { $0.transaction() }
        let importedExpenses = expenses.elements.compactMap { $0.transaction() }
        let importedLiquidity = liquidity.elements.compactMap { $0.transaction(settings: settings) }
        let importedInvestments = investments.elements.compactMap { $0.model() }
        let importedCrypto = crypto.elements.compactMap { $0.model() }
        let importedLiabilities = liabilities.elements.compactMap { $0.model(defaultCurrency: settings.currency) }
        let importedSnapshots = snapshots.elements.compactMap { $0.model() }

        let skippedTransactions = transactions.skippedCount + max(0, transactions.elements.count - importedTransactions.count)
        let skippedIncome = income.skippedCount + max(0, income.elements.count - importedIncome.count)
        let skippedExpenses = expenses.skippedCount + max(0, expenses.elements.count - importedExpenses.count)
        let skippedLiquidity = liquidity.skippedCount + max(0, liquidity.elements.count - importedLiquidity.count)
        let skippedInvestments = investments.skippedCount + max(0, investments.elements.count - importedInvestments.count)
        let skippedCrypto = crypto.skippedCount + max(0, crypto.elements.count - importedCrypto.count)
        let skippedLiabilities = liabilities.skippedCount + max(0, liabilities.elements.count - importedLiabilities.count)
        let skippedSnapshots = snapshots.skippedCount + max(0, snapshots.elements.count - importedSnapshots.count)
        let skippedRecords = skippedTransactions + skippedIncome + skippedExpenses + skippedLiquidity + skippedInvestments + skippedCrypto + skippedLiabilities + skippedSnapshots

        return NormalizedFinanceImport(
            data: FinancialData(
                transactions: (importedTransactions + importedIncome + importedExpenses + importedLiquidity).uniquedByID(),
                investments: importedInvestments.uniquedByID(),
                crypto: importedCrypto.uniquedByID(),
                liabilities: importedLiabilities.uniquedByID(),
                snapshots: importedSnapshots.uniquedByID()
            ).sortedForStorage(),
            skippedRecords: skippedRecords
        )
    }
}

private struct ImportedTransaction: Decodable {
    let id: UUID?
    let type: String?
    let category: String?
    let amount: Double?
    let description: String?
    let date: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case amount
        case description
        case date
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        category = container.decodeImportedStringIfPresent(forKey: .category)
        amount = container.decodeImportedDoubleIfPresent(forKey: .amount)
        description = container.decodeImportedStringIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model() -> Transaction? {
        guard
            let rawType = type?.lowercased(),
            let transactionType = TransactionType(rawValue: rawType),
            let amount = amount?.positiveImportedAmount,
            let date = ImportDateParser.parseDateOnly(date)
        else {
            return nil
        }

        return Transaction(
            id: id ?? UUID(),
            type: transactionType,
            category: category ?? "Other",
            amount: amount,
            description: description ?? "",
            date: date,
            createdAt: ImportDateParser.parse(createdAt) ?? date
        )
    }
}

private struct ImportedIncomeEntry: Decodable {
    let id: UUID?
    let type: String?
    let amount: Double?
    let description: String?
    let date: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case amount
        case description
        case date
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        amount = container.decodeImportedDoubleIfPresent(forKey: .amount)
        description = container.decodeImportedStringIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func transaction() -> Transaction? {
        guard
            let amount = amount?.positiveImportedAmount,
            let date = ImportDateParser.parseDateOnly(date)
        else {
            return nil
        }

        return Transaction(
            id: id ?? UUID(),
            type: .income,
            category: Self.categoryName(from: type),
            amount: amount,
            description: description ?? "",
            date: date,
            createdAt: ImportDateParser.parse(createdAt) ?? date
        )
    }

    private static func categoryName(from rawType: String?) -> String {
        switch rawType?.lowercased() {
        case "salary": "Salary"
        case "dividends": "Dividends"
        case "freelance": "Freelance"
        case "other": "Other"
        case .some(let value): value.importTitleCased
        case .none: "Other"
        }
    }
}

private struct ImportedExpenseEntry: Decodable {
    let id: UUID?
    let category: String?
    let amount: Double?
    let description: String?
    let date: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case amount
        case description
        case date
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        category = container.decodeImportedStringIfPresent(forKey: .category)
        amount = container.decodeImportedDoubleIfPresent(forKey: .amount)
        description = container.decodeImportedStringIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func transaction() -> Transaction? {
        guard
            let amount = amount?.positiveImportedAmount,
            let date = ImportDateParser.parseDateOnly(date)
        else {
            return nil
        }

        return Transaction(
            id: id ?? UUID(),
            type: .expense,
            category: category ?? "Other",
            amount: amount,
            description: description ?? "",
            date: date,
            createdAt: ImportDateParser.parse(createdAt) ?? date
        )
    }
}

private struct ImportedLiquidityAccount: Decodable {
    let id: UUID?
    let type: String?
    let name: String?
    let balance: Double?
    let currency: String?
    let updatedAt: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case balance
        case currency
        case updatedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        name = container.decodeImportedStringIfPresent(forKey: .name)
        balance = container.decodeImportedDoubleIfPresent(forKey: .balance)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    @MainActor
    func transaction(settings: AppSettings) -> Transaction? {
        guard let balance, balance.isFinite, balance != 0 else { return nil }

        let sourceCurrency = Currency.imported(currency, default: settings.currency)
        let convertedAmount = settings.convert(abs(balance), from: sourceCurrency)
        guard convertedAmount > 0, convertedAmount.isFinite else { return nil }

        let accountName = name ?? type?.importTitleCased ?? "Liquidity Account"
        let importedDate = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? Date()
        let transactionType: TransactionType = balance >= 0 ? .income : .expense

        return Transaction(
            id: id ?? UUID(),
            type: transactionType,
            category: "Liquidity",
            amount: convertedAmount,
            description: "Imported liquidity account: \(accountName)",
            date: Calendar.current.startOfDay(for: importedDate),
            createdAt: ImportDateParser.parse(createdAt) ?? importedDate
        )
    }
}

private struct ImportedInvestment: Decodable {
    let id: UUID?
    let type: String?
    let symbol: String?
    let name: String?
    let quantity: Double?
    let costBasis: Double?
    let currentValue: Double?
    let currentPrice: Double?
    let currency: String?
    let geography: String?
    let sector: String?
    let isin: String?
    let fees: Double?
    let lastPriceUpdate: String?
    let updatedAt: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case symbol
        case name
        case quantity
        case costBasis
        case currentValue
        case currentPrice
        case currency
        case geography
        case sector
        case isin
        case fees
        case lastPriceUpdate
        case updatedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        symbol = container.decodeImportedStringIfPresent(forKey: .symbol)
        name = container.decodeImportedStringIfPresent(forKey: .name)
        quantity = container.decodeImportedDoubleIfPresent(forKey: .quantity)
        costBasis = container.decodeImportedDoubleIfPresent(forKey: .costBasis)
        currentValue = container.decodeImportedDoubleIfPresent(forKey: .currentValue)
        currentPrice = container.decodeImportedDoubleIfPresent(forKey: .currentPrice)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        geography = container.decodeImportedStringIfPresent(forKey: .geography)
        sector = container.decodeImportedStringIfPresent(forKey: .sector)
        isin = container.decodeImportedStringIfPresent(forKey: .isin)
        fees = container.decodeImportedDoubleIfPresent(forKey: .fees)
        lastPriceUpdate = container.decodeImportedStringIfPresent(forKey: .lastPriceUpdate)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model() -> Investment? {
        guard
            let symbol,
            let name,
            let quantity = quantity?.positiveImportedAmount
        else {
            return nil
        }

        let costBasis = costBasis?.nonNegativeImportedAmount ?? 0
        let currentPrice = currentPrice?.nonNegativeImportedAmount
            ?? currentValue.flatMap { quantity > 0 ? ($0 / quantity).nonNegativeImportedAmount : nil }
            ?? 0
        let currentValue = currentValue?.nonNegativeImportedAmount ?? quantity * currentPrice
        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(lastPriceUpdate) ?? Date()

        return Investment(
            id: id ?? UUID(),
            type: InvestmentType(rawValue: type?.lowercased() ?? "") ?? .other,
            symbol: symbol.uppercased(),
            name: name,
            quantity: quantity,
            costBasis: costBasis,
            currentValue: currentValue,
            currentPrice: currentPrice,
            currency: Currency.imported(currency, default: .usd),
            geography: geography ?? "Other",
            sector: sector ?? "Other",
            isin: isin?.uppercased() ?? "",
            fees: fees?.nonNegativeImportedAmount ?? 0,
            updatedAt: importedUpdatedAt,
            createdAt: ImportDateParser.parse(createdAt) ?? importedUpdatedAt
        )
    }
}

private struct ImportedCryptoHolding: Decodable {
    let id: UUID?
    let symbol: String?
    let name: String?
    let quantity: Double?
    let avgBuyPrice: Double?
    let currentPrice: Double?
    let currency: String?
    let fees: Double?
    let coinId: String?
    let lastPriceUpdate: String?
    let updatedAt: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case quantity
        case avgBuyPrice
        case currentPrice
        case currency
        case fees
        case coinId
        case lastPriceUpdate
        case updatedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        symbol = container.decodeImportedStringIfPresent(forKey: .symbol)
        name = container.decodeImportedStringIfPresent(forKey: .name)
        quantity = container.decodeImportedDoubleIfPresent(forKey: .quantity)
        avgBuyPrice = container.decodeImportedDoubleIfPresent(forKey: .avgBuyPrice)
        currentPrice = container.decodeImportedDoubleIfPresent(forKey: .currentPrice)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        fees = container.decodeImportedDoubleIfPresent(forKey: .fees)
        coinId = container.decodeImportedStringIfPresent(forKey: .coinId)
        lastPriceUpdate = container.decodeImportedStringIfPresent(forKey: .lastPriceUpdate)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model() -> CryptoHolding? {
        guard
            let symbol,
            let name,
            let quantity = quantity?.positiveImportedAmount
        else {
            return nil
        }

        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(lastPriceUpdate) ?? Date()

        return CryptoHolding(
            id: id ?? UUID(),
            symbol: symbol.uppercased(),
            name: name,
            quantity: quantity,
            avgBuyPrice: avgBuyPrice?.nonNegativeImportedAmount ?? 0,
            currentPrice: currentPrice?.nonNegativeImportedAmount ?? 0,
            currency: Currency.imported(currency, default: .usd),
            fees: fees?.nonNegativeImportedAmount ?? 0,
            coinId: coinId?.lowercased() ?? "",
            updatedAt: importedUpdatedAt,
            createdAt: ImportDateParser.parse(createdAt) ?? importedUpdatedAt
        )
    }
}

private struct ImportedLiability: Decodable {
    let id: UUID?
    let type: String?
    let name: String?
    let principal: Double?
    let currentBalance: Double?
    let currency: String?
    let updatedAt: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case principal
        case currentBalance
        case currency
        case updatedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        name = container.decodeImportedStringIfPresent(forKey: .name)
        principal = container.decodeImportedDoubleIfPresent(forKey: .principal)
        currentBalance = container.decodeImportedDoubleIfPresent(forKey: .currentBalance)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model(defaultCurrency: Currency) -> Liability? {
        guard let balance = (currentBalance ?? principal)?.nonNegativeImportedAmount else {
            return nil
        }

        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? Date()

        return Liability(
            id: id ?? UUID(),
            name: name ?? type?.importTitleCased ?? "Liability",
            currentBalance: balance,
            currency: Currency.imported(currency, default: defaultCurrency),
            createdAt: ImportDateParser.parse(createdAt) ?? importedUpdatedAt,
            updatedAt: importedUpdatedAt
        )
    }
}

private struct ImportedSnapshot: Decodable {
    let id: UUID?
    let date: String?
    let totalAssets: Double?
    let totalLiabilities: Double?
    let netWorth: Double?
    let liquidity: Double?
    let investments: Double?
    let crypto: Double?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case totalAssets
        case totalLiabilities
        case netWorth
        case liquidity
        case investments
        case crypto
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        totalAssets = container.decodeImportedDoubleIfPresent(forKey: .totalAssets)
        totalLiabilities = container.decodeImportedDoubleIfPresent(forKey: .totalLiabilities)
        netWorth = container.decodeImportedDoubleIfPresent(forKey: .netWorth)
        liquidity = container.decodeImportedDoubleIfPresent(forKey: .liquidity)
        investments = container.decodeImportedDoubleIfPresent(forKey: .investments)
        crypto = container.decodeImportedDoubleIfPresent(forKey: .crypto)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model() -> NetWorthSnapshot? {
        guard
            let date = ImportDateParser.parse(date),
            let netWorth,
            netWorth.isFinite
        else {
            return nil
        }

        let totalLiabilities = totalLiabilities?.finiteImportedAmount ?? 0
        let totalAssets = totalAssets?.finiteImportedAmount ?? netWorth + totalLiabilities

        return NetWorthSnapshot(
            id: id ?? UUID(),
            date: date,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: netWorth,
            liquidity: liquidity?.finiteImportedAmount ?? 0,
            investments: investments?.finiteImportedAmount ?? 0,
            crypto: crypto?.finiteImportedAmount ?? 0,
            createdAt: ImportDateParser.parse(createdAt) ?? date
        )
    }
}

private struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]
    var skippedCount: Int

    init() {
        elements = []
        skippedCount = 0
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var skippedCount = 0

        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                skippedCount += 1
                _ = try? container.decode(DiscardedJSONValue.self)
            }
        }

        self.elements = elements
        self.skippedCount = skippedCount
    }
}

private enum DiscardedJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: DiscardedJSONValue])
    case array([DiscardedJSONValue])
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .number(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
        }

        if let values = try? [DiscardedJSONValue](from: decoder) {
            self = .array(values)
            return
        }

        if let values = try? [String: DiscardedJSONValue](from: decoder) {
            self = .object(values)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }
}

private enum ImportDateParser {
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.trimmedForImport else { return nil }

        if let date = isoWithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = iso.date(from: value) {
            return date
        }
        if let date = dateOnlyFormatter.date(from: value) {
            return date
        }

        return nil
    }

    static func parseDateOnly(_ rawValue: String?) -> Date? {
        guard let date = parse(rawValue) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyArrayIfPresent<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> LossyArray<Element> {
        (try? decode(LossyArray<Element>.self, forKey: key)) ?? LossyArray<Element>()
    }

    func decodeImportedStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value.trimmedForImport
        }

        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return String(value)
        }

        if let value = try? decode(Bool.self, forKey: key) {
            return String(value)
        }

        return nil
    }

    func decodeImportedDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return value
        }

        if let value = try? decode(String.self, forKey: key) {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(normalized), parsed.isFinite {
                return parsed
            }
        }

        return nil
    }

    func decodeUUIDIfPresent(forKey key: Key) -> UUID? {
        guard let rawValue = decodeImportedStringIfPresent(forKey: key) else { return nil }
        return UUID(uuidString: rawValue)
    }
}

private extension Currency {
    static func imported(_ rawValue: String?, default defaultCurrency: Currency) -> Currency {
        guard let rawValue = rawValue?.trimmedForImport else { return defaultCurrency }
        return Currency(rawValue: rawValue.uppercased()) ?? defaultCurrency
    }
}

private extension FinancialData {
    var hasImportableContent: Bool {
        !transactions.isEmpty || !investments.isEmpty || !crypto.isEmpty || !liabilities.isEmpty || !snapshots.isEmpty
    }

    func merged(with incoming: FinancialData) -> FinancialData {
        FinancialData(
            transactions: transactions.mergedByID(with: incoming.transactions),
            investments: investments.mergedByID(with: incoming.investments),
            crypto: crypto.mergedByID(with: incoming.crypto),
            liabilities: liabilities.mergedByID(with: incoming.liabilities),
            snapshots: snapshots.mergedByID(with: incoming.snapshots)
        )
    }

    func sortedForStorage() -> FinancialData {
        FinancialData(
            transactions: transactions.sorted {
                if $0.date == $1.date { return $0.createdAt > $1.createdAt }
                return $0.date > $1.date
            },
            investments: investments.sorted { $0.currentValue > $1.currentValue },
            crypto: crypto.sorted { $0.currentValue > $1.currentValue },
            liabilities: liabilities.sorted { $0.updatedAt > $1.updatedAt },
            snapshots: snapshots.sorted { $0.date < $1.date }
        )
    }
}

private extension Array where Element: Identifiable, Element.ID == UUID {
    func mergedByID(with incoming: [Element]) -> [Element] {
        var merged = self
        for item in incoming {
            if let index = merged.firstIndex(where: { $0.id == item.id }) {
                merged[index] = item
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    func uniquedByID() -> [Element] {
        var seen = Set<UUID>()
        return filter { item in
            seen.insert(item.id).inserted
        }
    }
}

private extension Double {
    var finiteImportedAmount: Double? {
        isFinite ? self : nil
    }

    var positiveImportedAmount: Double? {
        isFinite && self > 0 ? self : nil
    }

    var nonNegativeImportedAmount: Double? {
        isFinite && self >= 0 ? self : nil
    }
}

private extension String {
    var trimmedForImport: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var importTitleCased: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }
}
