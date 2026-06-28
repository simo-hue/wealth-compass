import Foundation

/// Lossy, forgiving JSON backup parser, extracted from FinanceStore (M1 / T4).
///
/// Decodes the interchange backup format (incl. legacy web shapes such as
/// `income`/`expenses`/`liquidity`, comma decimals, multiple date formats and
/// stringly-typed numbers) into a normalized `FinancialData`, counting skipped
/// records. `FinanceStore.importBackup` calls `parse(_:settings:)`; everything else
/// here is file-private. `normalized()` is `@MainActor` because it reads `AppSettings`.
enum FinanceImportService {
    @MainActor
    static func parse(_ payload: Data, settings: AppSettings) throws -> NormalizedFinanceImport {
        let imported: ImportedFinancialData
        do {
            imported = try JSONDecoder().decode(ImportedFinancialData.self, from: payload)
        } catch {
            throw FinanceImportError.invalidJSON(error.localizedDescription)
        }
        return imported.normalized(settings: settings)
    }
}

struct NormalizedFinanceImport {
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
    private let recurringTransactions: LossyArray<ImportedRecurringTransaction>
    private let snapshots: LossyArray<ImportedSnapshot>

    private enum CodingKeys: String, CodingKey {
        case income
        case expenses
        case investments
        case crypto
        case liabilities
        case liquidity
        case transactions
        case recurringTransactions
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
        recurringTransactions = container.decodeLossyArrayIfPresent(ImportedRecurringTransaction.self, forKey: .recurringTransactions)
        snapshots = container.decodeLossyArrayIfPresent(ImportedSnapshot.self, forKey: .snapshots)
    }

    @MainActor
    func normalized(settings: AppSettings) -> NormalizedFinanceImport {
        let importedTransactions = transactions.elements.compactMap { $0.model() }
        let importedRecurringTransactions = recurringTransactions.elements.compactMap { $0.model() }
        let importedIncome = income.elements.compactMap { $0.transaction() }
        let importedExpenses = expenses.elements.compactMap { $0.transaction() }
        let importedLiquidity = liquidity.elements.compactMap { $0.transaction(settings: settings) }
        let importedInvestments = investments.elements.compactMap { $0.model() }
        let importedCrypto = crypto.elements.compactMap { $0.model() }
        let importedLiabilities = liabilities.elements.compactMap { $0.model(defaultCurrency: settings.currency) }
        let importedSnapshots = snapshots.elements.compactMap { $0.model() }

        let skippedTransactions = transactions.skippedCount + max(0, transactions.elements.count - importedTransactions.count)
        let skippedRecurringTransactions = recurringTransactions.skippedCount
            + max(0, recurringTransactions.elements.count - importedRecurringTransactions.count)
        let skippedIncome = income.skippedCount + max(0, income.elements.count - importedIncome.count)
        let skippedExpenses = expenses.skippedCount + max(0, expenses.elements.count - importedExpenses.count)
        let skippedLiquidity = liquidity.skippedCount + max(0, liquidity.elements.count - importedLiquidity.count)
        let skippedInvestments = investments.skippedCount + max(0, investments.elements.count - importedInvestments.count)
        let skippedCrypto = crypto.skippedCount + max(0, crypto.elements.count - importedCrypto.count)
        let skippedLiabilities = liabilities.skippedCount + max(0, liabilities.elements.count - importedLiabilities.count)
        let skippedSnapshots = snapshots.skippedCount + max(0, snapshots.elements.count - importedSnapshots.count)
        // Unique once so we can also count records dropped for a duplicate UUID (WC-L7) —
        // previously those vanished from the totals without incrementing `skippedRecords`.
        let uniqueTransactions = (importedTransactions + importedIncome + importedExpenses + importedLiquidity).uniquedByID()
        let uniqueRecurring = importedRecurringTransactions.uniquedByID()
        let uniqueInvestments = importedInvestments.uniquedByID()
        let uniqueCrypto = importedCrypto.uniquedByID()
        let uniqueLiabilities = importedLiabilities.uniquedByID()
        let uniqueSnapshots = importedSnapshots.uniquedByID()

        // Broken into simple binary ops to keep the type-checker fast.
        let combinedTransactionCount = importedTransactions.count + importedIncome.count
            + importedExpenses.count + importedLiquidity.count
        let droppedTransactions = combinedTransactionCount - uniqueTransactions.count
        let droppedRecurring = importedRecurringTransactions.count - uniqueRecurring.count
        let droppedInvestments = importedInvestments.count - uniqueInvestments.count
        let droppedCrypto = importedCrypto.count - uniqueCrypto.count
        let droppedLiabilities = importedLiabilities.count - uniqueLiabilities.count
        let droppedSnapshots = importedSnapshots.count - uniqueSnapshots.count
        let droppedDuplicates = droppedTransactions + droppedRecurring + droppedInvestments
            + droppedCrypto + droppedLiabilities + droppedSnapshots

        let skippedRecords = skippedTransactions + skippedRecurringTransactions + skippedIncome + skippedExpenses
            + skippedLiquidity + skippedInvestments + skippedCrypto + skippedLiabilities + skippedSnapshots
            + droppedDuplicates

        return NormalizedFinanceImport(
            data: FinancialData(
                transactions: uniqueTransactions,
                recurringTransactions: uniqueRecurring,
                investments: uniqueInvestments,
                crypto: uniqueCrypto,
                liabilities: uniqueLiabilities,
                snapshots: uniqueSnapshots
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
    let recurringTransactionID: UUID?
    let recurringOccurrenceDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case amount
        case description
        case date
        case createdAt
        case recurringTransactionID
        case recurringOccurrenceDate
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
        recurringTransactionID = container.decodeUUIDIfPresent(forKey: .recurringTransactionID)
        recurringOccurrenceDate = container.decodeImportedStringIfPresent(forKey: .recurringOccurrenceDate)
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
            amount: Decimal(amount),
            description: description ?? "",
            date: date,
            createdAt: ImportDateParser.parse(createdAt) ?? date,
            recurringTransactionID: recurringTransactionID,
            recurringOccurrenceDate: ImportDateParser.parse(recurringOccurrenceDate)
        )
    }
}

private struct ImportedRecurringTransaction: Decodable {
    let id: UUID?
    let type: String?
    let category: String?
    let amount: Double?
    let description: String?
    let startDate: String?
    let frequency: String?
    let nextDueDate: String?
    let endDate: String?
    let notificationsEnabled: Bool?
    let isActive: Bool?
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case amount
        case description
        case startDate
        case frequency
        case nextDueDate
        case endDate
        case notificationsEnabled
        case isActive
        case completedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        category = container.decodeImportedStringIfPresent(forKey: .category)
        amount = container.decodeImportedDoubleIfPresent(forKey: .amount)
        description = container.decodeImportedStringIfPresent(forKey: .description)
        startDate = container.decodeImportedStringIfPresent(forKey: .startDate)
        frequency = container.decodeImportedStringIfPresent(forKey: .frequency)
        nextDueDate = container.decodeImportedStringIfPresent(forKey: .nextDueDate)
        endDate = container.decodeImportedStringIfPresent(forKey: .endDate)
        notificationsEnabled = container.decodeImportedBoolIfPresent(forKey: .notificationsEnabled)
        isActive = container.decodeImportedBoolIfPresent(forKey: .isActive)
        completedAt = container.decodeImportedStringIfPresent(forKey: .completedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
    }

    func model() -> RecurringTransaction? {
        guard
            let rawType = type?.lowercased(),
            let transactionType = TransactionType(rawValue: rawType),
            let amount = amount?.positiveImportedAmount,
            let startDate = ImportDateParser.parse(startDate),
            let rawFrequency = frequency?.lowercased(),
            let frequency = RecurringTransactionFrequency(rawValue: rawFrequency),
            let nextDueDate = ImportDateParser.parse(nextDueDate)
        else {
            return nil
        }

        let parsedEndDate = ImportDateParser.parse(endDate)
        let parsedCompletedAt = ImportDateParser.parse(completedAt)
        guard parsedEndDate.map({ $0 >= startDate }) ?? true else { return nil }

        return RecurringTransaction(
            id: id ?? UUID(),
            type: transactionType,
            category: category ?? "Other",
            amount: Decimal(amount),
            description: description ?? "",
            startDate: startDate,
            frequency: frequency,
            nextDueDate: nextDueDate,
            endDate: parsedEndDate,
            notificationsEnabled: notificationsEnabled ?? true,
            isActive: parsedCompletedAt == nil && (isActive ?? true),
            completedAt: parsedCompletedAt,
            createdAt: ImportDateParser.parse(createdAt) ?? startDate,
            updatedAt: ImportDateParser.parse(updatedAt) ?? startDate
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
            amount: Decimal(amount),
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
            amount: Decimal(amount),
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
        let convertedAmount = settings.convert(Decimal(abs(balance)), from: sourceCurrency)
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
            quantity: Decimal(quantity),
            costBasis: Decimal(costBasis),
            currentValue: Decimal(currentValue),
            currentPrice: Decimal(currentPrice),
            currency: Currency.imported(currency, default: .usd),
            geography: geography ?? "Other",
            sector: sector ?? "Other",
            isin: isin?.uppercased() ?? "",
            fees: Decimal(fees?.nonNegativeImportedAmount ?? 0),
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
            quantity: Decimal(quantity),
            avgBuyPrice: Decimal(avgBuyPrice?.nonNegativeImportedAmount ?? 0),
            currentPrice: Decimal(currentPrice?.nonNegativeImportedAmount ?? 0),
            currency: Currency.imported(currency, default: .usd),
            fees: Decimal(fees?.nonNegativeImportedAmount ?? 0),
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
            currentBalance: Decimal(balance),
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
            totalAssets: Decimal(totalAssets),
            totalLiabilities: Decimal(totalLiabilities),
            netWorth: Decimal(netWorth),
            liquidity: Decimal(liquidity?.finiteImportedAmount ?? 0),
            investments: Decimal(investments?.finiteImportedAmount ?? 0),
            crypto: Decimal(crypto?.finiteImportedAmount ?? 0),
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
        // WC-L6: an ISO date-time near midnight UTC, collapsed with the device's local calendar,
        // could land on the wrong calendar day (and thus the wrong cash-flow month). For values
        // that carry a time component (contain "T"), take the calendar day in UTC — the wire
        // format the web app emits. Pure "yyyy-MM-dd" values are already tz-stable, so they keep
        // the local startOfDay behavior unchanged.
        if rawValue?.trimmedForImport!.contains("T") == true {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .current
            return utc.startOfDay(for: date)
        }
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

    func decodeImportedBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
}

private extension Currency {
    static func imported(_ rawValue: String?, default defaultCurrency: Currency) -> Currency {
        guard let rawValue = rawValue?.trimmedForImport else { return defaultCurrency }
        return Currency(rawValue: rawValue.uppercased()) ?? defaultCurrency
    }
}

private extension Array where Element: Identifiable, Element.ID == UUID {
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
