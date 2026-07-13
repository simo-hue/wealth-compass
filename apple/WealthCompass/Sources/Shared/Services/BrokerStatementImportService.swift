import Foundation
import CryptoKit

/// CSV import for third-party broker / bank statements, auto-detected by content signature.
///
/// Two real formats are supported today, each recognized from its header/section markers so the
/// user never has to pick a provider:
///
/// * **Trade Republic** — the flat, one-row-per-transaction `Transaction export.csv`
///   (`datetime,date,account_type,category,type,asset_class,name,symbol,shares,price,amount,fee,tax,
///   currency,…`). Carries cash movements *and* securities trades.
/// * **Revolut** — the multi-section `consolidated_statement.csv` (per-currency account summaries,
///   an "End of Year holding statement" for crypto, then per-currency "Transaction statement" tables).
///
/// Both emit the same `NormalizedFinanceImport` the JSON backup importer produces, so the rest of the
/// import pipeline (`FinanceStore.importFile`, merge/replace, the summary sheet) is format-agnostic.
///
/// Design notes:
/// * **Net-worth fidelity.** Liquidity is `Σ transactions` (see `AnalyticsEngine`), so a securities BUY
///   becomes *both* an `Investment` holding (aggregated by ISIN) *and* a matching "Investments" expense
///   for the cash it consumed. Net worth stays exact at import (the only delta is the trade fee, which
///   really was paid).
/// * **Idempotency.** Every record's `id` is a deterministic UUID hashed from a stable key (Revolut/TR
///   `transaction_id`, an ISIN, a crypto symbol, or `section+date+description+amount+balance`). Re-importing
///   the same file — or a later export that repeats rows — updates in place via `FinancialData.mergedByID`
///   instead of duplicating.
/// * Holdings carry the **ISIN** (brokers don't export a ticker), so live-price refresh won't fire until
///   the user adds a ticker. Values are cost-based until then.
enum BrokerStatementImportService {
    /// The recognized on-disk formats. Public so tests and the summary UI can name what was detected.
    enum Format {
        case tradeRepublic
        case revolutStatement

        /// Human-readable label shown in the import summary ("Detected format: …").
        var displayName: String {
            switch self {
            case .tradeRepublic: "Trade Republic transaction export"
            case .revolutStatement: "Revolut consolidated statement"
            }
        }
    }

    struct Outcome {
        let format: Format
        let normalized: NormalizedFinanceImport
    }

    /// Sniffs `data` and returns the matching format, or `nil` if neither signature is present.
    /// Cheap and side-effect free — safe to call before committing to a full parse.
    static func detect(_ data: Data) -> Format? {
        guard let text = decodeText(data) else { return nil }
        // The TR export is the only one with this column trio in its header line.
        if let header = firstNonEmptyLine(text) {
            let lowered = header.lowercased()
            if lowered.contains("datetime"), lowered.contains("account_type"), lowered.contains("asset_class") {
                return .tradeRepublic
            }
        }
        // The Revolut statement is section-structured; any of these markers is a reliable tell.
        if text.contains("Current Accounts Summaries")
            || text.contains("Transaction statement")
            || text.range(of: "Revolut", options: .caseInsensitive) != nil {
            return .revolutStatement
        }
        return nil
    }

    /// Detects the format and parses `data` into a `NormalizedFinanceImport`.
    /// Throws `FinanceImportError.unrecognizedFormat` if no signature matches, or `.malformedCSV`
    /// if the file matches a format but yields no usable rows.
    static func parse(_ data: Data, context: FinanceImportContext) throws -> Outcome {
        guard let format = detect(data) else {
            throw FinanceImportError.unrecognizedFormat
        }
        guard let text = decodeText(data) else {
            throw FinanceImportError.malformedCSV("The file could not be read as text.")
        }
        let rows = CSVTokenizer.rows(from: text)
        guard !rows.isEmpty else {
            throw FinanceImportError.malformedCSV("The file contained no rows.")
        }

        let normalized: NormalizedFinanceImport
        switch format {
        case .tradeRepublic:
            normalized = TradeRepublicCSVParser.parse(rows: rows, context: context)
        case .revolutStatement:
            normalized = RevolutStatementCSVParser.parse(rows: rows, context: context)
        }
        return Outcome(format: format, normalized: normalized)
    }

    // MARK: - Text decoding

    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Some exports are Latin-1 / Windows-1252; fall back before giving up.
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return nil
    }

    private static func firstNonEmptyLine(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

// MARK: - RFC 4180 CSV tokenizer

/// Minimal, dependency-free CSV reader. Handles quoted fields, embedded commas/newlines, and the
/// `""` escaped-quote convention. Returns rows of raw (untrimmed) fields; callers trim as needed.
enum CSVTokenizer {
    static func rows(from text: String, delimiter: Character = ",") -> [[String]] {
        // Normalize line endings FIRST: Swift treats a CRLF as a single Character (grapheme cluster), so a
        // char-by-char scan would never see `\n` as a row terminator in a Windows/CRLF-encoded export and
        // would collapse the whole file into one row. Collapsing CRLF/CR → LF also covers old-Mac CR endings.
        // (A CRLF embedded inside a quoted field is normalized to LF — acceptable for statement data.)
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let chars = Array(normalized)
        var i = 0

        func endField() {
            record.append(field)
            field = ""
        }
        func endRecord() {
            endField()
            rows.append(record)
            record = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    // Doubled quote inside a quoted field → a literal quote.
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                    i += 1
                case delimiter:
                    endField()
                    i += 1
                case "\n":
                    endRecord()
                    i += 1
                default:
                    field.append(c)
                    i += 1
                }
            }
        }
        // Flush a trailing record with no final newline (ignore a pure trailing blank line).
        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return rows
    }
}

// MARK: - Shared parsing helpers

enum BrokerImportParsing {
    /// A version-5-style deterministic UUID from `seed`, so the same source row always yields the same
    /// record id (idempotent re-import via `mergedByID`). Uses SHA-256 (CryptoKit) truncated to 16 bytes.
    static func deterministicUUID(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    /// Parses a plain machine-formatted decimal (dot decimal, optional sign) — the Trade Republic dialect.
    static func plainDecimal(_ raw: String?) -> Decimal? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Parses a Revolut statement money cell — strips the currency symbol/code and thousands separators,
    /// keeps sign, and drops the "(€…)" home-currency parenthetical. Returns the *native* magnitude+sign.
    /// Examples: `€699.00` → 699, `-£3,517.75 (-€4,053.17)` → -3517.75, `0.00 AED (€0.00)` → 0,
    /// `1,980.578113` → 1980.578113.
    static func statementDecimal(_ raw: String?) -> Decimal? {
        guard let raw else { return nil }
        // Only the leading token is the native amount; anything in parentheses is the EUR equivalent.
        let head = raw.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
        var cleaned = ""
        for ch in head {
            if ch.isNumber || ch == "." || ch == "-" {
                cleaned.append(ch)
            }
            // Everything else (currency symbols €£$, letter codes like AED/HUF, commas, spaces) is dropped.
        }
        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parses `2026-01-08` or an ISO8601 timestamp; returns the start of that day.
    static func isoDate(_ raw: String?) -> Date? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: value) { return d }
        if let d = iso.date(from: value) { return d }
        if let d = ymd.date(from: value) { return Calendar.current.startOfDay(for: d) }
        return nil
    }

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "MMM d, yyyy" // "Jan 8, 2026"
        return f
    }()

    /// Parses a Revolut statement date like `Jan 8, 2026`; returns the start of that day.
    static func statementDate(_ raw: String?) -> Date? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let d = mediumDate.date(from: value) { return Calendar.current.startOfDay(for: d) }
        return isoDate(value)
    }

    static func currency(_ code: String?, default fallback: Currency) -> Currency {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return fallback }
        return Currency(rawValue: code.uppercased()) ?? fallback
    }
}

// MARK: - Trade Republic (flat transaction export)

private enum TradeRepublicCSVParser {
    static func parse(rows: [[String]], context: FinanceImportContext) -> NormalizedFinanceImport {
        guard let headerRow = rows.first else {
            return NormalizedFinanceImport(data: FinancialData(), skippedRecords: 0)
        }
        // Column name → index, so we tolerate reordering / extra columns.
        var columns: [String: Int] = [:]
        for (idx, name) in headerRow.enumerated() {
            columns[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = idx
        }
        func field(_ row: [String], _ name: String) -> String? {
            guard let idx = columns[name], idx < row.count else { return nil }
            let value = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        var transactions: [Transaction] = []
        var holdings: [String: HoldingAccumulator] = [:]
        var skipped = 0

        for row in rows.dropFirst() {
            // Skip structurally empty rows without counting them as malformed.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            let category = (field(row, "category") ?? "").uppercased()
            let type = (field(row, "type") ?? "").uppercased()
            let currency = BrokerImportParsing.currency(field(row, "currency"), default: context.displayCurrency)
            let date = BrokerImportParsing.isoDate(field(row, "date")) ?? BrokerImportParsing.isoDate(field(row, "datetime"))
            let createdAt = BrokerImportParsing.isoDate(field(row, "datetime")) ?? date
            // Raw (tz-independent) date string for dedup seeds — never `date.timeIntervalSince1970`, which
            // shifts with the device time zone for date-only rows and would break cross-device idempotency.
            let rawDate = field(row, "date") ?? field(row, "datetime") ?? ""
            let transactionID = field(row, "transaction_id")
            let name = field(row, "name")
            let description = field(row, "description") ?? name ?? field(row, "counterparty_name") ?? ""

            guard let amount = BrokerImportParsing.plainDecimal(field(row, "amount")), let date else {
                // A row we recognized but couldn't make sense of (no amount/date) is a genuine skip.
                skipped += 1
                continue
            }

            if category == "TRADING", type == "BUY" || type == "SELL" {
                // Securities trade → holding change + a matching cash movement so liquidity stays correct.
                // BUY: cash out (value + fee) and add shares. SELL: cash in (value − fee) and remove shares.
                let isBuy = (type == "BUY")
                let isin = field(row, "symbol")?.uppercased()
                let shares = BrokerImportParsing.plainDecimal(field(row, "shares"))
                let price = BrokerImportParsing.plainDecimal(field(row, "price"))
                let fee = BrokerImportParsing.plainDecimal(field(row, "fee")).map { abs($0) } ?? 0
                let tradeValue = abs(amount)

                if let isin, let shares, shares > 0 {
                    var acc = holdings[isin] ?? HoldingAccumulator(
                        isin: isin,
                        name: name ?? isin,
                        assetClass: field(row, "asset_class"),
                        currency: currency
                    )
                    if isBuy {
                        acc.addBuy(shares: shares, cost: tradeValue, fee: fee, price: price, date: createdAt ?? date)
                    } else {
                        acc.addSell(shares: shares, fee: fee, price: price, date: createdAt ?? date)
                    }
                    holdings[isin] = acc
                } else {
                    // Can't form a holding (missing ISIN/shares) — at least keep the cash movement below.
                    skipped += 1
                }

                // Include shares+amount in the dedup key so two same-ISIN, same-day trades (e.g. partial
                // fills) with no transaction_id don't collide and silently drop one cash leg.
                let tradeKey = transactionID
                    ?? "\(type)|\(isin ?? "")|\(rawDate)|\(field(row, "shares") ?? "")|\(field(row, "amount") ?? "")"
                let cashDelta = isBuy ? -(tradeValue + fee) : (tradeValue - fee)
                if cashDelta != 0 {
                    transactions.append(Transaction(
                        id: BrokerImportParsing.deterministicUUID("tr-cash:\(tradeKey)"),
                        type: cashDelta > 0 ? .income : .expense,
                        category: "Investments",
                        amount: abs(cashDelta),
                        description: name ?? description,
                        date: date,
                        currency: currency,
                        createdAt: createdAt ?? date,
                        updatedAt: createdAt ?? date
                    ))
                }
                continue
            }

            // Cash movement. Zero-amount bookkeeping rows (e.g. a €0.00 tax optimisation) are intentional
            // no-ops, not malformed — skip them silently so they don't inflate the "skipped" count.
            if amount == 0 { continue }

            let stableKey = transactionID ?? "\(rawDate)|\(description)|\(amount)"
            transactions.append(Transaction(
                id: BrokerImportParsing.deterministicUUID("tr:\(stableKey)"),
                type: amount > 0 ? .income : .expense,
                category: categoryName(for: type),
                amount: abs(amount),
                description: description,
                date: date,
                currency: currency,
                createdAt: createdAt ?? date,
                updatedAt: createdAt ?? date
            ))
        }

        let investments = holdings.values.compactMap { $0.investment() }
        let data = FinancialData(transactions: transactions, investments: investments)
        return NormalizedFinanceImport(data: data, skippedRecords: skipped)
    }

    /// Maps a Trade Republic `type` to a friendly cash-flow category.
    private static func categoryName(for type: String) -> String {
        switch type {
        case "CUSTOMER_INBOUND", "TRANSFER_INBOUND", "TRANSFER_INSTANT_INBOUND",
             "TRANSFER_OUTBOUND", "TRANSFER_INSTANT_OUTBOUND":
            return "Transfer"
        case "CARD_TRANSACTION", "CARD_TRANSACTION_INTERNATIONAL":
            return "Shopping"
        case "INTEREST_PAYMENT":
            return "Interest"
        case "DIVIDEND":
            return "Dividends"
        case "STOCKPERK":
            return "Rewards"
        case "TAX_OPTIMIZATION":
            return "Taxes"
        default:
            return "Other"
        }
    }

    /// Accumulates the BUY rows for one ISIN into a single holding.
    private struct HoldingAccumulator {
        let isin: String
        var name: String
        let assetClass: String?
        let currency: Currency
        var buyShares: Decimal = 0
        var buyCost: Decimal = 0
        var sellShares: Decimal = 0
        var fees: Decimal = 0
        var lastPrice: Decimal = 0
        var lastPriceDate: Date = .distantPast
        var firstDate: Date = .distantFuture
        var lastDate: Date = .distantPast

        mutating func addBuy(shares: Decimal, cost: Decimal, fee: Decimal, price: Decimal?, date: Date) {
            buyShares += shares
            buyCost += cost
            fees += fee
            record(price: price, date: date)
        }

        mutating func addSell(shares: Decimal, fee: Decimal, price: Decimal?, date: Date) {
            sellShares += shares
            fees += fee
            record(price: price, date: date)
        }

        private mutating func record(price: Decimal?, date: Date) {
            if let price, price > 0, date >= lastPriceDate {
                lastPrice = price
                lastPriceDate = date
            }
            firstDate = min(firstDate, date)
            lastDate = max(lastDate, date)
        }

        /// Net position after buys and sells; a fully-sold (net-zero or short) position yields no holding.
        var netQuantity: Decimal { buyShares - sellShares }

        func investment() -> Investment? {
            let quantity = netQuantity
            guard quantity > 0 else { return nil }
            let averageCost = buyShares > 0 ? buyCost / buyShares : 0
            let costBasis = quantity * averageCost
            // Prefer the most recent trade price; fall back to average cost so currentValue is sane.
            let unitPrice = lastPrice > 0 ? lastPrice : averageCost
            let created = firstDate == .distantFuture ? Date() : firstDate
            let updated = lastDate == .distantPast ? created : lastDate
            return Investment(
                id: BrokerImportParsing.deterministicUUID("tr-holding:\(isin)"),
                type: investmentType(from: assetClass),
                symbol: isin,
                name: name,
                quantity: quantity,
                costBasis: costBasis,
                currentValue: quantity * unitPrice,
                currentPrice: unitPrice,
                currency: currency,
                geography: "Other",
                sector: "Other",
                isin: isin,
                fees: fees,
                updatedAt: updated,
                createdAt: created
            )
        }

        private func investmentType(from assetClass: String?) -> InvestmentType {
            switch (assetClass ?? "").uppercased() {
            case "STOCK": return .stock
            case "FUND", "ETF": return .etf
            case "BOND": return .bond
            default: return .other
            }
        }
    }
}

// MARK: - Revolut (multi-section consolidated statement)

private enum RevolutStatementCSVParser {
    private enum Mode {
        case scanning
        case awaitingTransactionHeader
        case inTransactions(dateIdx: Int, descIdx: Int, categoryIdx: Int, moneyIdx: Int, balanceIdx: Int)
        case awaitingCryptoHeader
        case inCrypto
    }

    static func parse(rows: [[String]], context: FinanceImportContext) -> NormalizedFinanceImport {
        var transactions: [Transaction] = []
        var crypto: [CryptoHolding] = []
        var skipped = 0

        var mode: Mode = .scanning
        // Optional: nil while inside a section whose currency isn't representable (see sectionCurrency).
        var currentCurrency: Currency? = context.displayCurrency

        func cell(_ row: [String], _ idx: Int) -> String {
            idx >= 0 && idx < row.count ? row[idx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        func isBlank(_ row: [String]) -> Bool {
            row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        func isSeparator(_ row: [String]) -> Bool {
            let first = cell(row, 0)
            return first.hasPrefix("---") || first == "Total"
        }

        for row in rows {
            let first = cell(row, 0)

            // A section header names the account currency, e.g. "Personal Account (GBP)". Reset on EVERY
            // account section — even one whose currency we can't represent — so rows never inherit the
            // previous section's currency. An unsupported code (e.g. AED, absent from `Currency`) → nil.
            if let section = sectionCurrency(from: first) {
                switch section {
                case .known(let resolved): currentCurrency = resolved
                case .unsupported: currentCurrency = nil
                }
            }

            // Transitions that can happen from any mode.
            if first == "Transaction statement" {
                mode = .awaitingTransactionHeader
                continue
            }
            if first == "End of Year holding statement" {
                mode = .awaitingCryptoHeader
                continue
            }

            switch mode {
            case .scanning:
                continue

            case .awaitingTransactionHeader:
                // The header row starts with "Date" and defines the column layout.
                if first == "Date" {
                    let idx: (String) -> Int = { name in row.firstIndex { $0.trimmingCharacters(in: .whitespaces) == name } ?? -1 }
                    mode = .inTransactions(
                        dateIdx: idx("Date"),
                        descIdx: idx("Description"),
                        categoryIdx: idx("Category"),
                        moneyIdx: idx("Money in/out"),
                        balanceIdx: idx("Balance")
                    )
                }
                continue

            case let .inTransactions(dateIdx, descIdx, categoryIdx, moneyIdx, balanceIdx):
                if isBlank(row) || isSeparator(row) {
                    mode = .scanning
                    continue
                }
                guard let date = BrokerImportParsing.statementDate(cell(row, dateIdx)),
                      let amount = BrokerImportParsing.statementDecimal(cell(row, moneyIdx)) else {
                    // Header echoes or unparseable rows: skip. Only count rows that look like data.
                    if !cell(row, dateIdx).isEmpty { skipped += 1 }
                    continue
                }
                if amount == 0 { continue }
                guard let currency = currentCurrency else {
                    // A section whose currency can't be represented — skip its rows rather than mislabel
                    // them (and mis-convert) with the previous section's currency.
                    skipped += 1
                    continue
                }
                let description = cell(row, descIdx)
                let categoryLabel = cell(row, categoryIdx)
                let balance = cell(row, balanceIdx)
                let stableKey = "\(currency.rawValue)|\(cell(row, dateIdx))|\(description)|\(cell(row, moneyIdx))|\(balance)"
                transactions.append(Transaction(
                    id: BrokerImportParsing.deterministicUUID("rev:\(stableKey)"),
                    type: amount > 0 ? .income : .expense,
                    category: categoryLabel.isEmpty ? "Other" : categoryLabel,
                    amount: abs(amount),
                    description: description,
                    date: date,
                    currency: currency,
                    createdAt: date,
                    updatedAt: date
                ))
                continue

            case .awaitingCryptoHeader:
                // Column header: "Description & symbol","Units held","Unit price","Value held".
                if first.hasPrefix("Description") {
                    mode = .inCrypto
                }
                continue

            case .inCrypto:
                if isBlank(row) || isSeparator(row) || first.hasPrefix("Description") {
                    if isBlank(row) || isSeparator(row) { mode = .scanning }
                    continue
                }
                let symbol = first.uppercased()
                guard !symbol.isEmpty,
                      let units = BrokerImportParsing.statementDecimal(cell(row, 1)), units > 0 else {
                    continue
                }
                let unitPrice = BrokerImportParsing.statementDecimal(cell(row, 2)) ?? 0
                crypto.append(CryptoHolding(
                    id: BrokerImportParsing.deterministicUUID("rev-crypto:\(symbol)"),
                    symbol: symbol,
                    name: symbol,
                    quantity: units,
                    avgBuyPrice: 0,
                    currentPrice: unitPrice,
                    currency: .eur,
                    fees: 0,
                    coinId: "",
                    updatedAt: Date(),
                    createdAt: Date()
                ))
                continue
            }
        }

        let data = FinancialData(transactions: transactions, crypto: crypto)
        return NormalizedFinanceImport(data: data, skippedRecords: skipped)
    }

    private enum SectionCurrency {
        case known(Currency)
        case unsupported
    }

    /// Classifies a section title by its trailing "(XXX)" account-currency code. Any 3-ASCII-letter
    /// parenthetical marks a currency section (transaction rows always start with a date, never a title,
    /// so this can't misfire on data rows): a recognized code → `.known`, an unrepresentable one → `.unsupported`.
    /// Returns nil when the title isn't a currency section header at all (leaves the current currency intact).
    private static func sectionCurrency(from title: String) -> SectionCurrency? {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else { return nil }
        let inside = title[title.index(after: open)..<title.index(before: title.endIndex)]
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        guard inside.count == 3, inside.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        if let resolved = Currency(rawValue: inside) { return .known(resolved) }
        return .unsupported
    }
}
