import Foundation

/// Lossy, forgiving JSON backup parser, extracted from FinanceStore (M1 / T4).
///
/// Decodes the interchange backup format (incl. legacy web shapes such as
/// `income`/`expenses`/`liquidity`, comma decimals, multiple date formats and
/// stringly-typed numbers) into a normalized `FinancialData`, counting skipped
/// records. `FinanceStore.importBackup` calls `parse(_:context:)` off the MainActor; everything else
/// here is file-private and nonisolated.
/// L55: value-type import context so `parse`/`normalize` can run OFF the MainActor. The import only
/// needs the display currency + the FX converter, both value types — so we snapshot them on the
/// MainActor and pass them into the detached parse (rather than the `@MainActor AppSettings`).
struct FinanceImportContext: Sendable {
    let displayCurrency: Currency
    let snapshot: ExchangeRateSnapshot?

    /// Converts an amount from `source` into the display currency, matching `AppSettings.convert`.
    func convert(_ value: Decimal, from source: Currency) -> Decimal {
        CurrencyConverter(snapshot: snapshot).convert(value, from: source, to: displayCurrency)
    }
}

enum FinanceImportService {
    /// Nonisolated so a caller can run it off the MainActor (L55). Build a `FinanceImportContext`
    /// on the MainActor first (see `FinanceStore.importBackup`).
    static func parse(_ payload: Data, context: FinanceImportContext) throws -> NormalizedFinanceImport {
        let imported: ImportedFinancialData
        do {
            imported = try JSONDecoder().decode(ImportedFinancialData.self, from: payload)
        } catch {
            throw FinanceImportError.invalidJSON(error.localizedDescription)
        }
        return imported.normalized(context: context)
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

    func normalized(context: FinanceImportContext) -> NormalizedFinanceImport {
        let importedTransactions = transactions.elements.compactMap { $0.model() }
        let importedRecurringTransactions = recurringTransactions.elements.compactMap { $0.model() }
        let importedIncome = income.elements.compactMap { $0.transaction() }
        let importedExpenses = expenses.elements.compactMap { $0.transaction() }
        let importedLiquidity = liquidity.elements.compactMap { $0.transaction(context: context) }
        let importedInvestments = investments.elements.compactMap { $0.model(defaultCurrency: context.displayCurrency) }
        let importedCrypto = crypto.elements.compactMap { $0.model(defaultCurrency: context.displayCurrency) }
        let importedLiabilities = liabilities.elements.compactMap { $0.model(defaultCurrency: context.displayCurrency) }
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
    let amount: Decimal?
    let description: String?
    let date: String?
    let currency: String?
    let createdAt: String?
    let updatedAt: String?
    let recurringTransactionID: UUID?
    let recurringOccurrenceDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case amount
        case description
        case date
        case currency
        case createdAt
        case updatedAt
        case recurringTransactionID
        case recurringOccurrenceDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        category = container.decodeImportedStringIfPresent(forKey: .category)
        amount = container.decodeImportedDecimalIfPresent(forKey: .amount)
        description = container.decodeImportedTextIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        recurringTransactionID = container.decodeUUIDIfPresent(forKey: .recurringTransactionID)
        recurringOccurrenceDate = container.decodeImportedStringIfPresent(forKey: .recurringOccurrenceDate)
    }

    func model() -> Transaction? {
        let currencyCode = Currency.importedCode(currency)
        guard
            let rawType = type?.lowercased(),
            let transactionType = TransactionType(rawValue: rawType),
            let amount = amount?.positiveImportedAmount.flatMap(importedMoney),
            let date = ImportDateParser.parseDateOnly(date),
            currencyCode.isRepresentable
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
            currency: currencyCode.optionalValue,
            createdAt: ImportDateParser.parse(createdAt) ?? date,
            updatedAt: ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? date,
            recurringTransactionID: recurringTransactionID,
            recurringOccurrenceDate: ImportDateParser.parse(recurringOccurrenceDate)
        )
    }
}

private struct ImportedRecurringTransaction: Decodable {
    let id: UUID?
    let type: String?
    let category: String?
    let amount: Decimal?
    let description: String?
    let startDate: String?
    let frequency: String?
    let nextDueDate: String?
    let endDate: String?
    let currency: String?
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
        case currency
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
        amount = container.decodeImportedDecimalIfPresent(forKey: .amount)
        description = container.decodeImportedTextIfPresent(forKey: .description)
        startDate = container.decodeImportedStringIfPresent(forKey: .startDate)
        frequency = container.decodeImportedStringIfPresent(forKey: .frequency)
        nextDueDate = container.decodeImportedStringIfPresent(forKey: .nextDueDate)
        endDate = container.decodeImportedStringIfPresent(forKey: .endDate)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        notificationsEnabled = container.decodeImportedBoolIfPresent(forKey: .notificationsEnabled)
        isActive = container.decodeImportedBoolIfPresent(forKey: .isActive)
        completedAt = container.decodeImportedStringIfPresent(forKey: .completedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
    }

    func model() -> RecurringTransaction? {
        let currencyCode = Currency.importedCode(currency)
        guard
            let rawType = type?.lowercased(),
            let transactionType = TransactionType(rawValue: rawType),
            let amount = amount?.positiveImportedAmount.flatMap(importedMoney),
            let startDate = ImportDateParser.parse(startDate),
            let rawFrequency = frequency?.lowercased(),
            let frequency = RecurringTransactionFrequency(rawValue: rawFrequency),
            let nextDueDate = ImportDateParser.parse(nextDueDate),
            currencyCode.isRepresentable
        else {
            return nil
        }

        var parsedEndDate = ImportDateParser.parse(endDate)
        let parsedCompletedAt = ImportDateParser.parse(completedAt)
        // Normalize a date-only endDate to end-of-day (deep-audit L42): "2024-06-15" parses to local
        // midnight, so a same-calendar-day timed startDate ("…T09:00:00Z") would be > endDate and the
        // whole schedule would be dropped. End-of-day keeps its final occurrence inside the window.
        if let parsed = parsedEndDate, endDate?.trimmedForImport?.contains("T") == false {
            parsedEndDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: parsed)
        }
        guard parsedEndDate.map({ $0 >= startDate }) ?? true else { return nil }

        return RecurringTransaction(
            id: id ?? UUID(),
            type: transactionType,
            category: category ?? "Other",
            amount: amount,
            description: description ?? "",
            startDate: startDate,
            frequency: frequency,
            nextDueDate: nextDueDate,
            endDate: parsedEndDate,
            currency: currencyCode.optionalValue,
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
    let amount: Decimal?
    let description: String?
    let date: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case amount
        case description
        case date
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        type = container.decodeImportedStringIfPresent(forKey: .type)
        amount = container.decodeImportedDecimalIfPresent(forKey: .amount)
        description = container.decodeImportedTextIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
    }

    func transaction() -> Transaction? {
        guard
            let amount = amount?.positiveImportedAmount.flatMap(importedMoney),
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
            createdAt: ImportDateParser.parse(createdAt) ?? date,
            updatedAt: ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? date
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
    let amount: Decimal?
    let description: String?
    let date: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case amount
        case description
        case date
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        category = container.decodeImportedStringIfPresent(forKey: .category)
        amount = container.decodeImportedDecimalIfPresent(forKey: .amount)
        description = container.decodeImportedTextIfPresent(forKey: .description)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
    }

    func transaction() -> Transaction? {
        guard
            let amount = amount?.positiveImportedAmount.flatMap(importedMoney),
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
            createdAt: ImportDateParser.parse(createdAt) ?? date,
            updatedAt: ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(createdAt) ?? date
        )
    }
}

private struct ImportedLiquidityAccount: Decodable {
    let id: UUID?
    let type: String?
    let name: String?
    let balance: Decimal?
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
        name = container.decodeImportedTextIfPresent(forKey: .name)
        balance = container.decodeImportedDecimalIfPresent(forKey: .balance)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func transaction(context: FinanceImportContext) -> Transaction? {
        guard let balance, balance.isFinite, balance != 0 else { return nil }

        guard let sourceCurrency = Currency.importedCode(currency).resolved(default: context.displayCurrency) else {
            return nil
        }
        guard let balanceValue = importedMoney(abs(balance)) else { return nil }
        let convertedAmount = context.convert(balanceValue, from: sourceCurrency)
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
            createdAt: ImportDateParser.parse(createdAt) ?? importedDate,
            updatedAt: importedDate
        )
    }
}

private struct ImportedInvestment: Decodable {
    let id: UUID?
    let type: String?
    let symbol: String?
    let name: String?
    let quantity: Decimal?
    let costBasis: Decimal?
    let currentValue: Decimal?
    let currentPrice: Decimal?
    let currency: String?
    let geography: String?
    let sector: String?
    let isin: String?
    let fees: Decimal?
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
        name = container.decodeImportedTextIfPresent(forKey: .name)
        quantity = container.decodeImportedDecimalIfPresent(forKey: .quantity)
        costBasis = container.decodeImportedDecimalIfPresent(forKey: .costBasis)
        currentValue = container.decodeImportedDecimalIfPresent(forKey: .currentValue)
        currentPrice = container.decodeImportedDecimalIfPresent(forKey: .currentPrice)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        geography = container.decodeImportedStringIfPresent(forKey: .geography)
        sector = container.decodeImportedStringIfPresent(forKey: .sector)
        isin = container.decodeImportedStringIfPresent(forKey: .isin)
        fees = container.decodeImportedDecimalIfPresent(forKey: .fees)
        lastPriceUpdate = container.decodeImportedStringIfPresent(forKey: .lastPriceUpdate)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model(defaultCurrency: Currency) -> Investment? {
        guard
            let symbol,
            let name,
            let quantity = quantity?.positiveImportedAmount,
            let resolvedCurrency = Currency.importedCode(currency).resolved(default: defaultCurrency)
        else {
            return nil
        }

        let costBasis = costBasis?.nonNegativeImportedAmount ?? 0
        let currentPrice = currentPrice?.nonNegativeImportedAmount
            ?? currentValue.flatMap { quantity > 0 ? ($0 / quantity).nonNegativeImportedAmount : nil }
            ?? 0
        let currentValue = currentValue?.nonNegativeImportedAmount ?? quantity * currentPrice
        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(lastPriceUpdate) ?? Date()

        guard
            let quantityValue = importedMoney(quantity),
            let costBasisValue = importedMoney(costBasis),
            let currentValueValue = importedMoney(currentValue),
            let currentPriceValue = importedMoney(currentPrice),
            let feesValue = importedMoney(orZero: fees?.nonNegativeImportedAmount)
        else {
            return nil
        }

        return Investment(
            id: id ?? UUID(),
            type: InvestmentType(rawValue: type?.lowercased() ?? "") ?? .other,
            symbol: symbol.uppercased(),
            name: name,
            quantity: quantityValue,
            costBasis: costBasisValue,
            currentValue: currentValueValue,
            currentPrice: currentPriceValue,
            currency: resolvedCurrency,
            geography: geography ?? "Other",
            sector: sector ?? "Other",
            isin: isin?.uppercased() ?? "",
            fees: feesValue,
            updatedAt: importedUpdatedAt,
            createdAt: ImportDateParser.parse(createdAt) ?? importedUpdatedAt
        )
    }
}

private struct ImportedCryptoHolding: Decodable {
    let id: UUID?
    let symbol: String?
    let name: String?
    let quantity: Decimal?
    let avgBuyPrice: Decimal?
    let currentPrice: Decimal?
    let currency: String?
    let fees: Decimal?
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
        name = container.decodeImportedTextIfPresent(forKey: .name)
        quantity = container.decodeImportedDecimalIfPresent(forKey: .quantity)
        avgBuyPrice = container.decodeImportedDecimalIfPresent(forKey: .avgBuyPrice)
        currentPrice = container.decodeImportedDecimalIfPresent(forKey: .currentPrice)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        fees = container.decodeImportedDecimalIfPresent(forKey: .fees)
        coinId = container.decodeImportedStringIfPresent(forKey: .coinId)
        lastPriceUpdate = container.decodeImportedStringIfPresent(forKey: .lastPriceUpdate)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model(defaultCurrency: Currency) -> CryptoHolding? {
        guard
            let symbol,
            let name,
            let quantity = quantity?.positiveImportedAmount
        else {
            return nil
        }

        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? ImportDateParser.parse(lastPriceUpdate) ?? Date()

        guard
            let quantityValue = importedMoney(quantity),
            let avgBuyPriceValue = importedMoney(orZero: avgBuyPrice?.nonNegativeImportedAmount),
            let currentPriceValue = importedMoney(orZero: currentPrice?.nonNegativeImportedAmount),
            let feesValue = importedMoney(orZero: fees?.nonNegativeImportedAmount),
            let resolvedCurrency = Currency.importedCode(currency).resolved(default: defaultCurrency)
        else {
            return nil
        }

        return CryptoHolding(
            id: id ?? UUID(),
            symbol: symbol.uppercased(),
            name: name,
            quantity: quantityValue,
            avgBuyPrice: avgBuyPriceValue,
            currentPrice: currentPriceValue,
            currency: resolvedCurrency,
            fees: feesValue,
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
    let principal: Decimal?
    let currentBalance: Decimal?
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
        name = container.decodeImportedTextIfPresent(forKey: .name)
        principal = container.decodeImportedDecimalIfPresent(forKey: .principal)
        currentBalance = container.decodeImportedDecimalIfPresent(forKey: .currentBalance)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        updatedAt = container.decodeImportedStringIfPresent(forKey: .updatedAt)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model(defaultCurrency: Currency) -> Liability? {
        guard
            let balance = (currentBalance ?? principal)?.nonNegativeImportedAmount.flatMap(importedMoney),
            let resolvedCurrency = Currency.importedCode(currency).resolved(default: defaultCurrency)
        else {
            return nil
        }

        let importedUpdatedAt = ImportDateParser.parse(updatedAt) ?? Date()

        return Liability(
            id: id ?? UUID(),
            name: name ?? type?.importTitleCased ?? "Liability",
            currentBalance: balance,
            currency: resolvedCurrency,
            createdAt: ImportDateParser.parse(createdAt) ?? importedUpdatedAt,
            updatedAt: importedUpdatedAt
        )
    }
}

private struct ImportedSnapshot: Decodable {
    let id: UUID?
    let date: String?
    let totalAssets: Decimal?
    let totalLiabilities: Decimal?
    let netWorth: Decimal?
    let liquidity: Decimal?
    let investments: Decimal?
    let crypto: Decimal?
    let currency: String?
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
        case currency
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeUUIDIfPresent(forKey: .id)
        date = container.decodeImportedStringIfPresent(forKey: .date)
        totalAssets = container.decodeImportedDecimalIfPresent(forKey: .totalAssets)
        totalLiabilities = container.decodeImportedDecimalIfPresent(forKey: .totalLiabilities)
        netWorth = container.decodeImportedDecimalIfPresent(forKey: .netWorth)
        liquidity = container.decodeImportedDecimalIfPresent(forKey: .liquidity)
        investments = container.decodeImportedDecimalIfPresent(forKey: .investments)
        crypto = container.decodeImportedDecimalIfPresent(forKey: .crypto)
        currency = container.decodeImportedStringIfPresent(forKey: .currency)
        createdAt = container.decodeImportedStringIfPresent(forKey: .createdAt)
    }

    func model() -> NetWorthSnapshot? {
        let currencyCode = Currency.importedCode(currency)
        guard
            let date = ImportDateParser.parse(date),
            let netWorth,
            netWorth.isFinite,
            currencyCode.isRepresentable
        else {
            return nil
        }

        let totalLiabilities = totalLiabilities?.finiteImportedAmount ?? 0
        let totalAssets = totalAssets?.finiteImportedAmount ?? netWorth + totalLiabilities

        guard
            let totalAssetsValue = importedMoney(totalAssets),
            let totalLiabilitiesValue = importedMoney(totalLiabilities),
            let netWorthValue = importedMoney(netWorth),
            let liquidityValue = importedMoney(orZero: liquidity?.finiteImportedAmount),
            let investmentsValue = importedMoney(orZero: investments?.finiteImportedAmount),
            let cryptoValue = importedMoney(orZero: crypto?.finiteImportedAmount)
        else {
            return nil
        }

        return NetWorthSnapshot(
            id: id ?? UUID(),
            date: date,
            totalAssets: totalAssetsValue,
            totalLiabilities: totalLiabilitiesValue,
            netWorth: netWorthValue,
            liquidity: liquidityValue,
            investments: investmentsValue,
            crypto: cryptoValue,
            currency: currencyCode.optionalValue,
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
        //
        // Deep-audit L44 (intentional, left as-is): taking the *UTC* day is deliberate for round-
        // tripping the web app's UTC wire format. The only case this is "wrong" is a hypothetical
        // third-party source that emits a non-UTC offset-bearing datetime (e.g. `...T23:30:00+09:00`),
        // where the intended local day and the UTC day differ — not something our own import path
        // produces, so we keep UTC for web-interop consistency rather than parse the offset.
        if rawValue?.trimmedForImport?.contains("T") == true {
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

    /// Free-text variant of `decodeImportedStringIfPresent` for human-readable fields (`name`,
    /// `description`). WC-L8: the permissive helper coerces JSON numbers/bools into strings, which is
    /// fine for id/currency/enum-like fields but turns a numeric `name`/`description` into `"123.0"`
    /// or `"true"`. For free text we only accept an actual JSON string. (Import stays lossy elsewhere.)
    func decodeImportedTextIfPresent(forKey key: Key) -> String? {
        (try? decode(String.self, forKey: key))?.trimmedForImport
    }

    /// Money and quantities, read as `Decimal`.
    ///
    /// `Decimal` first, because it reads the raw JSON token exactly. Going through `Double` stored
    /// `1234.56` as `1234.5599999999997952` and `99999999.99` as `99999999.99000000512` — the same
    /// corruption class the persistence layer was fixed for, and import was the last place money
    /// crossed binary floating point outside charts and FX (WC-A1, `MoneyDecimal.swift`).
    func decodeImportedDecimalIfPresent(forKey key: Key) -> Decimal? {
        if let value = try? decode(Decimal.self, forKey: key) {
            return value.finiteImportedAmount
        }

        // `Decimal` cannot decode every JSON number — it throws for |x| >= 1e128 and for a nonzero
        // |x| below ~1e-129. Accept those through `Double` so the field still parses; they are far
        // outside anything the app could store, and `Decimal(finite:)` rejects the unrepresentable.
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Decimal(finite: value)
        }

        if let value = try? decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            // Gate on `Double` to keep acceptance exactly as it was — `Decimal(string:)` is more
            // permissive about trailing junk — but take the value from `Decimal` so it stays exact.
            // This form stays first because it is the only one that reads exponent notation, which
            // a web backup really can carry: JavaScript's `String(0.0000001)` is `"1e-7"`, and a
            // separator-based normalizer would strip the `e` and read that as 17.
            //
            // The charset check is the other half of that gate. `Double` also reads *hex-float* and
            // *infinity* spellings, which `Decimal(string:)` does not — and rather than both
            // failing, the two disagree silently: `Double("0x10")` is 16 while
            // `Decimal(string: "0x10")` is **0**, and `Double("-inf")` is -inf while
            // `Decimal(string: "-inf")` is **0** too. Each stored a real, spendable zero for a cell
            // that says nothing of the kind. Restricting the gate to the characters a decimal
            // literal is made of leaves every actual number untouched and sends those to the skip.
            if normalized.allSatisfy(isDecimalLiteralCharacter),
               Double(normalized) != nil,
               let parsed = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) {
                return parsed.finiteImportedAmount
            }
            // Grouped thousands — the case the form above cannot express, and used to *drop*.
            // Swapping every "," for "." turned an English "1,234.56" and a European "1.234,56"
            // alike into "1.234.56", which fails the gate, so the field decoded to nil and the
            // whole record went with it. `BrokerImportParsing.flexibleDecimal` is this codebase's
            // one last-separator-wins normalizer (it already backs the Trade Republic and Revolut
            // parsers); reused rather than written a second time, because two normalizers that
            // disagree is how this class of bug comes back.
            //
            // Restricted to a bare number — optional leading sign, then ASCII digits and
            // separators only — because `flexibleDecimal` discards every other character, and
            // widening this decoder that far would read a stray "2026-01-01" in an amount field
            // as 2026 rather than skipping the record.
            // At least one digit is required: `Decimal(string: ".")` returns **0**, not nil, so
            // without this a bare separator parses as a real zero. A transaction survives that
            // (it needs a positive amount) but a snapshot's `netWorth` only has to be finite, and
            // a meaningless cell would become an on-screen net worth of zero.
            //
            // And the separators have to sit where a number's separators sit —
            // `hasNumericSeparatorLayout`. The digit check alone let `"1.2.3"` through as **123**
            // and `"9.9.9.9.9"` through as **99999**: `flexibleDecimal` is deliberately permissive
            // because it feeds a CSV tokenizer that has already decided the column is money, so it
            // strips separators it cannot explain instead of refusing. This decoder has no such
            // column to lean on, and inventing a number out of a malformed cell is the same defect
            // as misreading one — worse, because the record used to be *counted* as skipped and the
            // user was told. The layout check is the call-site gate that buys the reuse back;
            // `flexibleDecimal` itself stays exactly as permissive as its broker callers need.
            let unsigned = (trimmed.hasPrefix("-") || trimmed.hasPrefix("+")) ? String(trimmed.dropFirst()) : trimmed
            guard unsigned.contains(where: { $0.isASCII && $0.isWholeNumber }),
                  unsigned.allSatisfy({ $0.isASCII && ($0.isWholeNumber || $0 == "." || $0 == ",") }),
                  hasNumericSeparatorLayout(unsigned)
            else {
                return nil
            }
            return BrokerImportParsing.flexibleDecimal(trimmed)?.finiteImportedAmount
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

/// The characters a decimal literal can be made of, once commas have been folded to dots.
///
/// Everything `Double(_: String)` accepts *beyond* this set is a spelling `Decimal(string:)` reads
/// differently rather than not at all — see `decodeImportedDecimalIfPresent`.
private func isDecimalLiteralCharacter(_ character: Character) -> Bool {
    guard character.isASCII else { return false }
    return character.isWholeNumber || character == "." || character == "+" || character == "-"
        || character == "e" || character == "E"
}

/// Whether `unsigned` — already known to be ASCII digits and `.` / `,` only, with at least one
/// digit — has the separator layout of an actual number.
///
/// Resolved exactly the way `BrokerImportParsing.flexibleDecimal` resolves it, so the two never
/// disagree about what a string means: when both separators appear the later one is the decimal
/// point and the other groups thousands; a lone `,` or `.` is a decimal point; a repeated one
/// groups. On top of that resolution this asks the question `flexibleDecimal` deliberately does not:
///
/// * the decimal separator occurs **at most once** — `"1,2.3.4"` names two decimal points, and
/// * the grouping separator splits the integer part into **1–3 digits, then any number of groups of
///   2 or 3, then a final group of exactly 3** — `"1,234,567"` and `"12,34,567"` do, `"1.2.3"`,
///   `"1,23,45"` and `",,,5,,,"` do not.
///
/// The final-group-of-3 rule is what makes the shape a *grouping* rather than an arbitrary split; a
/// middle group of 2 is Indian lakh grouping (`"12,34,567.89"`, `"1,00,000"`).
///
/// An earlier version required **every** non-first group to be 3 and called that "deliberately
/// Western-only". That was a regression rather than a choice: the lakh forms parsed at the commit
/// immediately before this gate existed, `flexibleDecimal` — the normalizer this claims to mirror —
/// resolves all of them to the correct value, and `NumberFormatter(.decimal)` produces them for 51
/// locale identifiers, one of which (`hi`) this app ships. The Western-only argument also applied
/// verbatim to `"1,234.56"`, which was deliberately kept, so it never picked lakh grouping out in
/// the first place. Measured over every ASCII digit/separator string up to 8 characters (488,280 of
/// them): the widened rule accepts everything the narrow one did, accepts nothing the pre-gate code
/// rejected, and never changes a value — the only shape it adds is `1-2-3`.
private func hasNumericSeparatorLayout(_ unsigned: String) -> Bool {
    let dotCount = unsigned.reduce(0) { $1 == "." ? $0 + 1 : $0 }
    let commaCount = unsigned.reduce(0) { $1 == "," ? $0 + 1 : $0 }

    let decimalSeparator: Character?
    let groupingSeparator: Character?
    if dotCount > 0, commaCount > 0 {
        if (unsigned.lastIndex(of: ".") ?? unsigned.startIndex) > (unsigned.lastIndex(of: ",") ?? unsigned.startIndex) {
            guard dotCount == 1 else { return false }
            (decimalSeparator, groupingSeparator) = (".", ",")
        } else {
            guard commaCount == 1 else { return false }
            (decimalSeparator, groupingSeparator) = (",", ".")
        }
    } else if commaCount > 1 {
        (decimalSeparator, groupingSeparator) = (nil, ",")
    } else if dotCount > 1 {
        (decimalSeparator, groupingSeparator) = (nil, ".")
    } else {
        (decimalSeparator, groupingSeparator) = (commaCount == 1 ? "," : (dotCount == 1 ? "." : nil), nil)
    }

    var integerPart = Substring(unsigned)
    if let decimalSeparator, let index = unsigned.firstIndex(of: decimalSeparator) {
        integerPart = unsigned[unsigned.startIndex..<index]
        // A trailing decimal separator is fine (`"1.234,"` is a European `1234,`); the plain form
        // already accepts the ungrouped `"1,"`.
        guard unsigned[unsigned.index(after: index)...].allSatisfy(\.isWholeNumber) else { return false }
    }

    guard let groupingSeparator else { return integerPart.allSatisfy(\.isWholeNumber) }
    let groups = integerPart.split(separator: groupingSeparator, omittingEmptySubsequences: false)
    guard groups.count > 1, let first = groups.first, (1...3).contains(first.count) else { return false }
    guard groups.allSatisfy({ $0.allSatisfy(\.isWholeNumber) }) else { return false }
    guard groups.last?.count == 3 else { return false }
    return groups.dropFirst().dropLast().allSatisfy { $0.count == 2 || $0.count == 3 }
}

/// Every money value the importer stores passes through one of these.
///
/// `Decimal(Double)` returns `NSDecimalNumber.notANumber` for finite `Double`s whose magnitude
/// `Decimal` cannot hold — at *both* ends, `1e300` and `1e-300` each produce NaN. `JSONEncoder`
/// then writes the bare token `NaN`, which is not valid JSON, so the app persists a database it
/// cannot read back. The failure surfaces on the *next* launch, from outside the lossy-salvage
/// path, so there is no in-app recovery: the user is stuck on "could not be loaded" for good.
///
/// deep-audit H9 introduced `Decimal(finite:)` and applied it to market data and FX. Import — the
/// one path that ingests an arbitrary user-supplied file — never got it. Guarding the `Double` is
/// necessary but not sufficient; the *result* has to be checked too.
private func importedMoney(_ value: Decimal) -> Decimal? { value.finiteImportedAmount }

/// Absent means zero. Present-but-unrepresentable rejects the whole record rather than silently
/// zeroing a figure the user can see on screen.
private func importedMoney(orZero value: Decimal?) -> Decimal? {
    guard let value else { return 0 }
    return value.finiteImportedAmount
}

/// What a record's `currency` field turned out to be. Three outcomes, because the two that used to
/// be collapsed together mean opposite things: an *absent* field is a legacy row, while a *present*
/// code outside the modelled set is a row whose money this app cannot represent.
private enum ImportedCurrencyCode {
    /// No field, or a blank one — a row written before the field existed.
    case absent
    /// A code this app models.
    case known(Currency)
    /// A real code outside `Currency`. The record must be skipped, never relabelled.
    case unrepresentable

    /// For the four models whose `currency` is non-optional. `nil` means "skip this record".
    ///
    /// Falling back to the display currency here kept the number and changed its meaning — an
    /// `AED 5,000` row silently became `EUR 5,000`, which is worse than dropping it because
    /// nothing tells the user it happened. Skipping routes the row into `skippedRecords`, so the
    /// import summary reports it. This is the choice the Revolut parser already makes for an
    /// unrepresentable account section (`sectionCurrency` → `.unsupported` → the rows are skipped
    /// and counted rather than inheriting the previous section's currency).
    func resolved(default defaultCurrency: Currency) -> Currency? {
        switch self {
        case .absent: defaultCurrency
        case .known(let currency): currency
        case .unrepresentable: nil
        }
    }

    /// For the three models whose `currency` is `Currency?`.
    ///
    /// `nil` on those types means "a row written before the field existed, read it as the base
    /// currency" — a meaning that must be preserved for genuinely legacy backups and must *not* be
    /// applied to a row this app exported minutes ago. So `.absent` stays `nil` and `.known` is
    /// carried through. `.unrepresentable` also maps to `nil` here, which is why callers must check
    /// `isRepresentable` and skip the record first: reaching this for an unknown code would be the
    /// same silent re-denomination, just spelled `currency ?? base` downstream.
    var optionalValue: Currency? {
        switch self {
        case .absent, .unrepresentable: nil
        case .known(let currency): currency
        }
    }

    var isRepresentable: Bool {
        if case .unrepresentable = self { return false }
        return true
    }
}

private extension Currency {
    static func importedCode(_ rawValue: String?) -> ImportedCurrencyCode {
        guard let rawValue = rawValue?.trimmedForImport else { return .absent }
        guard let currency = Currency(rawValue: rawValue.uppercased()) else { return .unrepresentable }
        return .known(currency)
    }
}

private extension Double {
    var finiteImportedAmount: Double? {
        isFinite ? self : nil
    }
}

private extension Decimal {
    /// `NSDecimalNumber.notANumber` is the only non-finite value a `Decimal` can hold, and it is
    /// what `Decimal(Double)` yields for an out-of-range magnitude. Spelled out rather than using
    /// `isFinite`, which is now ambiguous between Foundation's own member and the app's extension.
    var finiteImportedAmount: Decimal? {
        (self as NSDecimalNumber) == NSDecimalNumber.notANumber ? nil : self
    }

    var positiveImportedAmount: Decimal? {
        finiteImportedAmount.flatMap { $0 > 0 ? $0 : nil }
    }

    var nonNegativeImportedAmount: Decimal? {
        finiteImportedAmount.flatMap { $0 >= 0 ? $0 : nil }
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
