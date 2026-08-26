import XCTest
@testable import WealthCompassMobile

/// CSV import for auto-detected broker/bank statements (Revolut + Trade Republic).
/// Fixtures are synthetic/anonymized — the real templates carry PII and are gitignored.
@MainActor
final class BrokerStatementImportServiceTests: XCTestCase {
    private func context(_ display: Currency = .eur) -> FinanceImportContext {
        FinanceImportContext(displayCurrency: display, snapshot: nil)
    }

    private func parse(_ csv: String, display: Currency = .eur) throws -> BrokerStatementImportService.Outcome {
        try BrokerStatementImportService.parse(Data(csv.utf8), context: context(display))
    }

    // MARK: - Trade Republic (flat transaction export)

    private let tradeRepublicCSV = """
    "datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code"
    "2026-01-05T10:00:00.000Z","2026-01-05","DEFAULT","CASH","CUSTOMER_INBOUND","","Test User","","","","1000.00","","","EUR","","","","Top up","11111111-1111-1111-1111-111111111111","Test User","","",""
    "2026-01-06T10:00:00.000Z","2026-01-06","DEFAULT","CASH","CARD_TRANSACTION","","Coffee","","","","-4.50","","","EUR","","","","Coffee shop","22222222-2222-2222-2222-222222222222","","","",""
    "2026-01-07T10:00:00.000Z","2026-01-07","DEFAULT","CASH","STOCKPERK","STOCK","FreeCo","US0000000001","","","10.00","","","EUR","","","","Stockperk","33333333-3333-3333-3333-333333333333","","","",""
    "2026-01-07T10:01:00.000Z","2026-01-07","DEFAULT","TRADING","BUY","STOCK","FreeCo","US0000000001","1.0","10.00","-10.00","","","EUR","","","","Buy trade","44444444-4444-4444-4444-444444444444","","","",""
    "2026-01-08T10:00:00.000Z","2026-01-08","DEFAULT","TRADING","BUY","FUND","GlobalFund","IE0000000002","2.0","50.00","-100.00","-1.00","","EUR","","","","Buy trade","55555555-5555-5555-5555-555555555555","","","",""
    "2026-01-09T10:00:00.000Z","2026-01-09","DEFAULT","CASH","DIVIDEND","STOCK","FreeCo","US0000000001","1.0","","0.20","","-0.05","EUR","","","","Dividend","66666666-6666-6666-6666-666666666666","","","",""
    "2026-01-10T10:00:00.000Z","2026-01-10","DEFAULT","CASH","TAX_OPTIMIZATION","","","","","","0.00","","","EUR","","","","Tax","77777777-7777-7777-7777-777777777777","","","",""
    """

    func testTradeRepublicDetection() {
        XCTAssertEqual(BrokerStatementImportService.detect(Data(tradeRepublicCSV.utf8)), .tradeRepublic)
    }

    func testTradeRepublicMapsCashAndTrades() throws {
        let out = try parse(tradeRepublicCSV)
        XCTAssertEqual(out.format, .tradeRepublic)
        let data = out.normalized.data
        // 3 cash rows (top up, coffee, dividend, stockperk = 4 income/expense) + 2 BUY cash-outs = 6;
        // the €0.00 tax-optimisation row is a silent no-op, not a skip.
        XCTAssertEqual(data.transactions.count, 6)
        XCTAssertEqual(out.normalized.skippedRecords, 0)
        // Two holdings aggregated by ISIN.
        XCTAssertEqual(data.investments.count, 2)
    }

    func testTradeRepublicBuyProducesHoldingAndCashOut() throws {
        let data = try parse(tradeRepublicCSV).normalized.data
        let fund = try XCTUnwrap(data.investments.first { $0.isin == "IE0000000002" })
        XCTAssertEqual(fund.quantity.doubleValue, 2.0, accuracy: 0.0001)
        XCTAssertEqual(fund.costBasis.doubleValue, 100.0, accuracy: 0.0001)
        XCTAssertEqual(fund.fees.doubleValue, 1.0, accuracy: 0.0001)
        XCTAssertEqual(fund.type, .etf) // FUND → ETF
        XCTAssertEqual(fund.symbol, fund.isin) // ISIN as symbol (no ticker available)

        // A €101 cash-out (value + fee) exists so liquidity reflects the purchase.
        let cashOut = data.transactions.filter { $0.type == .expense && $0.category == "Investments" }
        XCTAssertTrue(cashOut.contains { abs($0.amount.doubleValue - 101.0) < 0.001 })
    }

    func testTradeRepublicNetWorthNeutralExceptFees() throws {
        let data = try parse(tradeRepublicCSV).normalized.data
        let income = data.transactions.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = data.transactions.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let holdings = data.investments.reduce(Decimal(0)) { $0 + $1.currentValue }
        let netWorth = income - expense + holdings
        // True net worth: 1000 top up + 10 perk + 0.20 div − 4.50 coffee − 1.00 fund fee = 1004.70.
        XCTAssertEqual(netWorth.doubleValue, 1004.70, accuracy: 0.01)
    }

    func testTradeRepublicIsIdempotent() throws {
        let first = try parse(tradeRepublicCSV).normalized.data
        let second = try parse(tradeRepublicCSV).normalized.data
        XCTAssertEqual(Set(first.transactions.map(\.id)), Set(second.transactions.map(\.id)))
        XCTAssertEqual(Set(first.investments.map(\.id)), Set(second.investments.map(\.id)))
        // Merging a re-import must not duplicate.
        let merged = first.merged(with: second)
        XCTAssertEqual(merged.transactions.count, first.transactions.count)
        XCTAssertEqual(merged.investments.count, first.investments.count)
    }

    /// Two genuinely distinct rows that share a stable key must both survive.
    ///
    /// Two identical purchases on the same day with no `transaction_id` produce the same
    /// `date|description|amount` key, hence the same deterministic UUID. Nothing deduped them, so
    /// one silently disappeared the moment the import was stored — and `skippedRecords` stayed 0,
    /// which is the part that makes it a loss rather than a report.
    func testTradeRepublicIdenticalCashRowsWithoutTransactionIDBothSurvive() throws {
        let header = "\"datetime\",\"date\",\"account_type\",\"category\",\"type\",\"asset_class\",\"name\",\"symbol\",\"shares\",\"price\",\"amount\",\"fee\",\"tax\",\"currency\""
        let row = "\"2026-02-01T10:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"CASH\",\"CARD_TRANSACTION\",\"\",\"Coffee\",\"\",\"\",\"\",\"-4.50\",\"\",\"\",\"EUR\""
        let out = try parse(header + "\n" + row + "\n" + row)
        let data = out.normalized.data

        XCTAssertEqual(data.transactions.count, 2, "one of two identical purchases vanished")
        XCTAssertEqual(Set(data.transactions.map(\.id)).count, 2, "both rows hashed to the same UUID")
        XCTAssertEqual(
            data.transactions.reduce(Decimal(0)) { $0 + $1.amount }, Decimal(9),
            "money went missing between the file and the import"
        )
        XCTAssertEqual(out.normalized.skippedRecords, 0, "both rows are real; neither is a skip")

        // The first occurrence keeps the seed it has always had. Changing it would give every row
        // already imported on a user's device a new id, and re-importing would duplicate the lot.
        let firstSeed = "tr:2026-02-01|Coffee|\(Decimal(string: "-4.50")!)"
        XCTAssertTrue(
            data.transactions.contains { $0.id == BrokerImportParsing.deterministicUUID(firstSeed) },
            "the first occurrence's id changed"
        )

        // Still idempotent: the same file imported twice lands on the same two ids.
        let again = try parse(header + "\n" + row + "\n" + row).normalized.data
        XCTAssertEqual(Set(data.transactions.map(\.id)), Set(again.transactions.map(\.id)))
        XCTAssertEqual(data.merged(with: again).transactions.count, 2, "a re-import duplicated the rows")
    }

    func testTradeRepublicCategoryMapping() throws {
        let data = try parse(tradeRepublicCSV).normalized.data
        XCTAssertTrue(data.transactions.contains { $0.category == "Rewards" && $0.type == .income })     // STOCKPERK
        XCTAssertTrue(data.transactions.contains { $0.category == "Dividends" && $0.type == .income })   // DIVIDEND
        XCTAssertTrue(data.transactions.contains { $0.category == "Shopping" && $0.type == .expense })   // CARD_TRANSACTION
    }

    private let trHeader = "\"datetime\",\"date\",\"account_type\",\"category\",\"type\",\"asset_class\",\"name\",\"symbol\",\"shares\",\"price\",\"amount\",\"fee\",\"tax\",\"currency\",\"original_amount\",\"original_currency\",\"fx_rate\",\"description\",\"transaction_id\",\"counterparty_name\",\"counterparty_iban\",\"payment_reference\",\"mcc_code\""

    func testTradeRepublicFullSellRemovesHolding() throws {
        // Buy 10 @100 then sell all 10 @110: no phantom holding, net worth = realized +100 (not +1100).
        let csv = trHeader + "\n"
            + "\"2026-02-01T10:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"10\",\"100.00\",\"-1000.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"buy\",\"a1\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-03-01T10:00:00.000Z\",\"2026-03-01\",\"DEFAULT\",\"TRADING\",\"SELL\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"10\",\"110.00\",\"1100.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"sell\",\"a2\",\"\",\"\",\"\",\"\""
        let data = try parse(csv).normalized.data
        XCTAssertEqual(data.investments.count, 0, "fully-sold position leaves no holding")
        let income = data.transactions.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = data.transactions.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let netWorth = income - expense + data.investments.reduce(Decimal(0)) { $0 + $1.currentValue }
        XCTAssertEqual(netWorth.doubleValue, 100.0, accuracy: 0.001)
    }

    func testTradeRepublicPartialSellReducesHolding() throws {
        // Buy 10 @100, sell 4 @110 → 6 shares remain at avg cost 100 (basis 600), value 660.
        let csv = trHeader + "\n"
            + "\"2026-02-01T10:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"10\",\"100.00\",\"-1000.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"buy\",\"b1\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-03-01T10:00:00.000Z\",\"2026-03-01\",\"DEFAULT\",\"TRADING\",\"SELL\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"4\",\"110.00\",\"440.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"sell\",\"b2\",\"\",\"\",\"\",\"\""
        let holding = try XCTUnwrap(try parse(csv).normalized.data.investments.first)
        XCTAssertEqual(holding.quantity.doubleValue, 6.0, accuracy: 0.001)
        XCTAssertEqual(holding.costBasis.doubleValue, 600.0, accuracy: 0.001)
        XCTAssertEqual(holding.currentValue.doubleValue, 660.0, accuracy: 0.001)
    }

    func testTradeRepublicSameDayBuysWithoutTransactionIdDoNotCollide() throws {
        // Two same-ISIN, same-day BUYs and NO transaction_id column: both cash-outs must survive dedup.
        let header = "\"datetime\",\"date\",\"account_type\",\"category\",\"type\",\"asset_class\",\"name\",\"symbol\",\"shares\",\"price\",\"amount\",\"fee\",\"tax\",\"currency\""
        let csv = header + "\n"
            + "\"2026-02-01T10:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"10\",\"100.00\",\"-1000.00\",\"\",\"\",\"EUR\"\n"
            + "\"2026-02-01T14:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"AcmeCo\",\"US1234567890\",\"5\",\"100.00\",\"-500.00\",\"\",\"\",\"EUR\""
        let data = try parse(csv).normalized.data
        let cashOuts = data.transactions.filter { $0.category == "Investments" }
        XCTAssertEqual(cashOuts.count, 2)
        XCTAssertEqual(Set(cashOuts.map(\.id)).count, 2, "distinct ids — no dedup collision")
        XCTAssertEqual(cashOuts.reduce(Decimal(0)) { $0 + $1.amount }.doubleValue, 1500.0, accuracy: 0.001)
    }

    /// A `currency` column holding an ISO code this app does not model must skip the row, not
    /// relabel it as the display currency.
    ///
    /// The fallback kept the number and changed its meaning — an AED 5,000 row silently became
    /// EUR 5,000, with nothing on screen to say so — and because Trade Republic prints the code on
    /// *every* row, a whole export could be re-denominated at once. That is worse than dropping the
    /// rows. This is the same call `ae1482c` made for the JSON backup importer and the one the
    /// Revolut parser already makes for an unrepresentable account section
    /// (`sectionCurrency` → `.unsupported` → skipped and counted).
    func testTradeRepublicSkipsUnrepresentableCurrencyInsteadOfRelabellingIt() throws {
        let csv = trHeader + "\n"
            + "\"2026-01-05T10:00:00.000Z\",\"2026-01-05\",\"DEFAULT\",\"CASH\",\"CUSTOMER_INBOUND\",\"\",\"Dubai top up\",\"\",\"\",\"\",\"5000.00\",\"\",\"\",\"AED\",\"\",\"\",\"\",\"Top up\",\"c1\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-01-06T10:00:00.000Z\",\"2026-01-06\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"DubaiCo\",\"AE0000000001\",\"1\",\"5000.00\",\"-5000.00\",\"\",\"\",\"AED\",\"\",\"\",\"\",\"buy\",\"c2\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-01-07T10:00:00.000Z\",\"2026-01-07\",\"DEFAULT\",\"CASH\",\"CARD_TRANSACTION\",\"\",\"Coffee\",\"\",\"\",\"\",\"-4.50\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Coffee shop\",\"c3\",\"\",\"\",\"\",\"\""
        let out = try parse(csv)
        let data = out.normalized.data

        XCTAssertEqual(data.transactions.count, 1, "an AED row was kept, relabelled as the display currency")
        XCTAssertEqual(data.transactions.first?.currency, .eur, "the healthy row beside it must survive")
        XCTAssertEqual(data.transactions.first?.amount, Decimal(string: "4.50"))
        XCTAssertTrue(data.investments.isEmpty, "an AED holding was kept, relabelled as the display currency")
        // Both AED rows are dropped, and the user has to be told about each of them.
        XCTAssertEqual(out.normalized.skippedRecords, 2, "unrepresentable rows were dropped without being reported")
    }

    /// A zero-amount bookkeeping row is a silent no-op in **any** currency.
    ///
    /// The parser states the rule itself: "Zero-amount bookkeeping rows (e.g. a €0.00 tax
    /// optimisation) are intentional no-ops, not malformed — skip them silently so they don't
    /// inflate the skipped count." `4e7a843` put the currency guard ahead of that line, so a
    /// `0.00 AED` tax-optimisation row started counting as skipped. The row carries no money either
    /// way, so an ISO code this app cannot model says nothing about it — and a user told "1 record
    /// skipped" has no way to find out it was nothing.
    func testTradeRepublicZeroAmountRowIsASilentNoOpInAnyCurrency() throws {
        let csv = trHeader + "\n"
            + "\"2026-01-10T10:00:00.000Z\",\"2026-01-10\",\"DEFAULT\",\"CASH\",\"TAX_OPTIMIZATION\",\"\",\"\",\"\",\"\",\"\",\"0.00\",\"\",\"\",\"AED\",\"\",\"\",\"\",\"Tax\",\"e1\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-01-11T10:00:00.000Z\",\"2026-01-11\",\"DEFAULT\",\"CASH\",\"CARD_TRANSACTION\",\"\",\"Coffee\",\"\",\"\",\"\",\"-4.50\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Coffee shop\",\"e2\",\"\",\"\",\"\",\"\""
        let out = try parse(csv)

        XCTAssertEqual(out.normalized.data.transactions.count, 1, "the zero-amount row became a transaction")
        XCTAssertEqual(out.normalized.data.transactions.first?.amount, Decimal(string: "4.50"))
        XCTAssertEqual(
            out.normalized.skippedRecords, 0,
            "a zero-amount bookkeeping row inflated the skipped count because of its currency"
        )
    }

    /// A holding must never be published from a subset of its own trades.
    ///
    /// Skipping an unrepresentable-currency row is right for cash, but a **trade** row also carries
    /// shares. Drop one and the surviving holding keeps accumulating the rest, so its quantity is
    /// short by the dropped legs — a wrong share count on screen, feeding net worth, with only
    /// "1 record skipped" to hint at it. Before `4e7a843` the row was relabelled and the quantity
    /// was at least right; the skip is still the better call for the money, but the holding it
    /// leaves behind has to go with it.
    ///
    /// Trade Republic prints one currency per account, so this needs a hand-made or third-party
    /// export to reach. It is a guard, not a reproduction.
    func testTradeRepublicDropsAHoldingWhoseTradesWereNotAllReadable() throws {
        let csv = trHeader + "\n"
            + "\"2026-01-05T10:00:00.000Z\",\"2026-01-05\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"MixedCo\",\"XX0000000001\",\"1\",\"100.00\",\"-100.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"buy\",\"f1\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-01-06T10:00:00.000Z\",\"2026-01-06\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"MixedCo\",\"XX0000000001\",\"3\",\"100.00\",\"-300.00\",\"\",\"\",\"AED\",\"\",\"\",\"\",\"buy\",\"f2\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-01-07T10:00:00.000Z\",\"2026-01-07\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"CleanCo\",\"XX0000000002\",\"2\",\"50.00\",\"-100.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"buy\",\"f3\",\"\",\"\",\"\",\"\""
        let out = try parse(csv)
        let data = out.normalized.data

        XCTAssertNil(
            data.investments.first { $0.isin == "XX0000000001" },
            "a holding was published with a quantity short by its dropped AED leg"
        )
        // The ISIN whose trades were all readable is untouched.
        let clean = try XCTUnwrap(data.investments.first { $0.isin == "XX0000000002" })
        XCTAssertEqual(clean.quantity, Decimal(string: "2"))
        XCTAssertEqual(clean.costBasis, Decimal(string: "100"))
        // The EUR leg's cash movement still stands — that money did leave the account.
        XCTAssertEqual(data.transactions.count, 2)
        XCTAssertEqual(
            data.transactions.compactMap { $0.category == "Investments" ? $0.amount : nil }.reduce(0, +),
            Decimal(string: "200")
        )
        // One AED row, plus the holding it made untrustworthy.
        XCTAssertEqual(out.normalized.skippedRecords, 2, "the dropped holding was not reported")
    }

    /// The meaning the skip must not break: an **absent** currency column is not an unrepresentable
    /// one. A blank cell still falls back to the display currency and the row is still imported.
    func testTradeRepublicAbsentCurrencyStillFallsBackToTheDisplayCurrency() throws {
        let csv = trHeader + "\n"
            + "\"2026-01-05T10:00:00.000Z\",\"2026-01-05\",\"DEFAULT\",\"CASH\",\"CUSTOMER_INBOUND\",\"\",\"Top up\",\"\",\"\",\"\",\"1000.00\",\"\",\"\",\"\",\"\",\"\",\"\",\"Top up\",\"d1\",\"\",\"\",\"\",\"\""
        let out = try parse(csv, display: .usd)
        let data = out.normalized.data

        XCTAssertEqual(data.transactions.count, 1, "a legacy row with no currency column must still import")
        XCTAssertEqual(data.transactions.first?.currency, .usd)
        XCTAssertEqual(data.transactions.first?.amount, Decimal(string: "1000.00"))
        XCTAssertEqual(out.normalized.skippedRecords, 0)
    }

    // MARK: - Revolut (multi-section consolidated statement)

    private let revolutCSV = """
    "Current Accounts Summaries",,,,,,,
    ,,,,,,,
    "Personal Account (EUR)",,,,,,,
    ,,,,,,,
    "Transaction statement",,,,,,,
    Date,Description,Category,"Money in/out",Balance,"Tax withheld","Other taxes",Fees
    "Jan 8, 2026","Top up salary","Top up",€1000.00,€1000.00,€0.00,€0.00,€0.00
    "Jan 9, 2026","Grocery",Merchant,-€25.50,€974.50,€0.00,€0.00,€0.00
    Total,,,€974.50,,€0.00,€0.00,€0.00
    ,,,,,,,
    "Personal Account (GBP)",,,,,,,
    ,,,,,,,
    "Transaction statement",,,,,,,
    Date,Description,Category,"Money in/out",Balance,"Tax withheld","Other taxes",Fees
    "Feb 5, 2026","Exchange in",Exchange,"£500.00 (€590.00)","£500.00 (€590.00)","£0.00 (€0.00)","£0.00 (€0.00)","£0.00 (€0.00)"
    "Feb 6, 2026","London cafe",Merchant,"-£12.34 (-€14.50)","£487.66 (€575.50)","£0.00 (€0.00)","£0.00 (€0.00)","£0.00 (€0.00)"
    Total,,,"£487.66 (€575.50)",,,,
    ,,,,,,,
    "Crypto Summaries",,,,,,,
    ,,,,,,,
    "End of Year holding statement",,,,,,,
    "Description & symbol","Units held","Unit price","Value held",,,,
    TESTA,"1,234.56",€0.10,€123.45,,,,
    TESTB,2.5,€40.00,€100.00,,,,
    Total,,,€223.45,,,,
    """

    func testRevolutDetection() {
        XCTAssertEqual(BrokerStatementImportService.detect(Data(revolutCSV.utf8)), .revolutStatement)
    }

    func testRevolutMultiCurrencyAndCrypto() throws {
        let out = try parse(revolutCSV)
        XCTAssertEqual(out.format, .revolutStatement)
        let data = out.normalized.data
        XCTAssertEqual(data.transactions.count, 4) // 2 EUR + 2 GBP; Total/blank rows skipped
        XCTAssertEqual(out.normalized.skippedRecords, 0)
        XCTAssertEqual(data.crypto.count, 2)

        let gbp = try XCTUnwrap(data.transactions.first { $0.currency == .gbp && $0.type == .expense })
        XCTAssertEqual(gbp.amount.doubleValue, 12.34, accuracy: 0.001) // native £, not the €-parenthetical
        XCTAssertTrue(data.transactions.contains { $0.currency == .eur && $0.amount.doubleValue == 1000 })
    }

    func testRevolutCryptoThousandsSeparator() throws {
        let data = try parse(revolutCSV).normalized.data
        let a = try XCTUnwrap(data.crypto.first { $0.symbol == "TESTA" })
        XCTAssertEqual(a.quantity.doubleValue, 1234.56, accuracy: 0.001)
        XCTAssertEqual(a.currentPrice.doubleValue, 0.10, accuracy: 0.001)
        XCTAssertEqual(a.currency, .eur)
    }

    /// The crypto row must take its currency from the price cell, not assume EUR.
    ///
    /// The importer hardcoded `.eur` while throwing away the symbol printed right next to the
    /// number, so a dollar-denominated holding statement produced a EUR holding — the same
    /// keep-the-number-change-the-meaning failure as an unrepresentable ISO code.
    func testRevolutCryptoTakesCurrencyFromThePriceCell() throws {
        let csv = """
        "Current Accounts Summaries",,,,,,,
        "Crypto Summaries",,,,,,,
        "End of Year holding statement",,,,,,,
        "Description & symbol","Units held","Unit price","Value held",,,,
        TESTC,2.0,$40.00,$80.00,,,,
        Total,,,$80.00,,,,
        """
        let data = try parse(csv, display: .eur).normalized.data
        let holding = try XCTUnwrap(data.crypto.first { $0.symbol == "TESTC" })
        XCTAssertEqual(holding.currency, .usd, "the cell's currency symbol was discarded")
        XCTAssertEqual(holding.currentPrice, Decimal(string: "40"))
    }

    /// Re-importing a statement must not erase what only the user knows.
    ///
    /// The row carries `avgBuyPrice: 0` and `coinId: ""` because a holding statement has neither,
    /// and stamps `updatedAt: Date()` so it always wins `mergedByID` — which replaced the record
    /// wholesale and took the user's cost basis, CoinGecko id, name, fees and creation date with
    /// it, on every single re-import. What the statement genuinely knows must still update.
    func testRevolutCryptoReimportKeepsUserEnteredFields() throws {
        var edited = try XCTUnwrap(try parse(revolutCSV).normalized.data.crypto.first { $0.symbol == "TESTA" })
        edited.avgBuyPrice = Decimal(string: "0.08")!
        edited.coinId = "testa-coin"
        edited.name = "Test Alpha"
        edited.fees = Decimal(string: "1.25")!
        edited.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        // Pin the user's record firmly in the past so the fresh import unambiguously wins the merge.
        edited.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = FinancialData(crypto: [edited])

        let merged = existing.merged(with: try parse(revolutCSV).normalized.data)
        XCTAssertEqual(merged.crypto.count, 2, "TESTA merged in place, TESTB appended")
        let holding = try XCTUnwrap(merged.crypto.first { $0.symbol == "TESTA" })

        XCTAssertEqual(holding.avgBuyPrice, Decimal(string: "0.08"), "re-import flattened the cost basis")
        XCTAssertEqual(holding.coinId, "testa-coin", "re-import erased the CoinGecko id")
        XCTAssertEqual(holding.name, "Test Alpha", "re-import reverted the name to the ticker")
        XCTAssertEqual(holding.fees, Decimal(string: "1.25"), "re-import erased the fees")
        XCTAssertEqual(
            holding.createdAt, Date(timeIntervalSince1970: 1_700_000_000),
            "re-import reset the holding's creation date"
        )
        // …and the statement still updates the two things it actually carries.
        XCTAssertEqual(holding.quantity, Decimal(string: "1234.56"))
        XCTAssertEqual(holding.currentPrice, Decimal(string: "0.10"))
    }

    /// A repeated crypto symbol is one holding, not two — but the drop has to be reported.
    ///
    /// `rev-crypto:` seeds from the symbol alone, so two rows for the same asset (a statement
    /// spanning two year-end sections) produced one id twice. Collapsing is the right answer here —
    /// disambiguating them would double-count the holding in net worth — but it must go through
    /// `uniquedByID` and land in `skippedRecords` rather than vanishing at storage time.
    func testRevolutRepeatedCryptoSymbolCollapsesAndIsCounted() throws {
        let csv = """
        "Current Accounts Summaries",,,,,,,
        "End of Year holding statement",,,,,,,
        "Description & symbol","Units held","Unit price","Value held",,,,
        TESTA,1.0,€10.00,€10.00,,,,
        TESTA,2.0,€10.00,€20.00,,,,
        """
        let out = try parse(csv)
        XCTAssertEqual(out.normalized.data.crypto.count, 1, "two rows share one deterministic id")
        XCTAssertEqual(out.normalized.skippedRecords, 1, "the dropped row vanished without being counted")
    }

    func testRevolutSkipsUnsupportedCurrencySection() throws {
        // AED isn't in `Currency`; its rows must be skipped, not mislabeled with the EUR section's currency.
        let csv = """
        "Personal Account (AED)",,,,,,,
        "Transaction statement",,,,,,,
        Date,Description,Category,"Money in/out",Balance,"Tax withheld","Other taxes",Fees
        "Jan 8, 2026","Dubai spend",Merchant,"1000.00 AED (€250.00)","1000.00 AED (€250.00)","0.00","0.00","0.00"
        Total,,,"1000.00 AED (€250.00)",,,,
        "Personal Account (EUR)",,,,,,,
        "Transaction statement",,,,,,,
        Date,Description,Category,"Money in/out",Balance,"Tax withheld","Other taxes",Fees
        "Jan 9, 2026","Coffee",Merchant,-€3.00,€-3.00,€0.00,€0.00,€0.00
        Total,,,-€3.00,,,,
        """
        let out = try parse(csv)
        let data = out.normalized.data
        XCTAssertEqual(data.transactions.count, 1)
        XCTAssertEqual(data.transactions.first?.currency, .eur)
        XCTAssertGreaterThanOrEqual(out.normalized.skippedRecords, 1) // the AED row counted as skipped
    }

    // MARK: - Detection & tokenizer

    func testUnrecognizedFormatThrows() {
        let junk = "col_a,col_b,col_c\n1,2,3\n4,5,6"
        XCTAssertNil(BrokerStatementImportService.detect(Data(junk.utf8)))
        XCTAssertThrowsError(try parse(junk)) { error in
            guard case FinanceImportError.unrecognizedFormat = error else {
                return XCTFail("expected unrecognizedFormat, got \(error)")
            }
        }
    }

    func testCSVTokenizerHandlesQuotedCommasAndNewlines() {
        let rows = CSVTokenizer.rows(from: "\"a,b\",c\r\n\"line1\nline2\",d")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["a,b", "c"])
        XCTAssertEqual(rows[1], ["line1\nline2", "d"])
    }

    func testCSVTokenizerHandlesEscapedQuotes() {
        let rows = CSVTokenizer.rows(from: "\"she said \"\"hi\"\"\",2")
        XCTAssertEqual(rows[0], ["she said \"hi\"", "2"])
    }

    func testDeterministicUUIDIsStableAndDistinct() {
        XCTAssertEqual(BrokerImportParsing.deterministicUUID("seed-x"), BrokerImportParsing.deterministicUUID("seed-x"))
        XCTAssertNotEqual(BrokerImportParsing.deterministicUUID("seed-x"), BrokerImportParsing.deterministicUUID("seed-y"))
    }

    // MARK: - Trade Republic PDF statements (parsed from extracted text)

    private let trAccountPDFText = """
    TRADE REPUBLIC BANK GMBH, BRANCH ITALY
    ESTRATTO CONTO RIASSUNTIVO
    PRODOTTO SALDO INIZIALE IN ENTRATA IN USCITA SALDO FINALE
    Conto corrente 1.000,00 € 50,00 € 30,00 € 1.020,00 €
    TRANSAZIONI SUL CONTO
    DATA TIPO DESCRIZIONE IN
    ENTRATA
    IN
    USCITA SALDO
    01 lug
    2026 Interessi Interest payment 50,00 € 1.050,00 €
    02 lug
    2026 Transazione con
    carta TEST MERCHANT 30,00 € 1.020,00 €
    PANORAMICA DEL SALDO
    """

    func testTradeRepublicAccountPDFInfersSignFromBalanceDelta() throws {
        let out = try BrokerStatementImportService.parsePDFText(trAccountPDFText)
        XCTAssertEqual(out.format, .tradeRepublicAccountPDF)
        let data = out.normalized.data
        XCTAssertEqual(data.transactions.count, 2)
        // +50 raised the balance → income; -30 lowered it → expense (the +/- column is lost in the PDF).
        let income = data.transactions.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = data.transactions.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(income.doubleValue, 50, accuracy: 0.01)
        XCTAssertEqual(expense.doubleValue, 30, accuracy: 0.01)
        XCTAssertTrue(data.transactions.contains { $0.category == "Shopping" && $0.description == "TEST MERCHANT" })
        XCTAssertTrue(data.transactions.contains { $0.category == "Interest" && $0.type == .income })
    }

    private let trNetWorthPDFText = """
    ESTRATTO DEL PATRIMONIO NETTO
    al giorno 13.07.2026
    PORTAFOGLIO VALORE IN EUR
    Conto titoli 200,00
    Liquidità 500,00
    TOTAL 700,00 EUR
    CONTO TITOLI
    PZ / NOMINALE NOME DEL TITOLO PREZZO AL PEZZO VALORE IN EUR
    2,0 pezzi Test ETF Fund
    ISIN: TESTETF00001
    1,0 pezzi Acme Corp
    ISIN: TESTSTOCK001
    50,00
    13.07.2026
    100,00
    100,00
    13.07.2026
    100,00
    NUMERO DI POSIZIONI: 2 200,00 EUR
    LIQUIDITÀ
    Conto corrente 500,00 EUR
    """

    func testTradeRepublicNetWorthPDFImportsSnapshot() throws {
        let out = try BrokerStatementImportService.parsePDFText(trNetWorthPDFText)
        XCTAssertEqual(out.format, .tradeRepublicNetWorthPDF)
        let data = out.normalized.data
        // A net-worth statement imports as ONE snapshot — not holdings/cash, which would double-count cash
        // and clobber cost basis from the transaction export on merge.
        XCTAssertTrue(data.investments.isEmpty)
        XCTAssertTrue(data.transactions.isEmpty)
        XCTAssertEqual(data.snapshots.count, 1)
        let snapshot = try XCTUnwrap(data.snapshots.first)
        XCTAssertEqual(snapshot.netWorth.doubleValue, 700, accuracy: 0.01)
        XCTAssertEqual(snapshot.investments.doubleValue, 200, accuracy: 0.01)
        XCTAssertEqual(snapshot.liquidity.doubleValue, 500, accuracy: 0.01)
        XCTAssertEqual(snapshot.currency, .eur)
    }

    func testRevolutPDFTextIsRejectedWithHelpfulError() {
        // A Revolut PDF reaches parsePDFText and must be told to use the CSV instead.
        XCTAssertThrowsError(try BrokerStatementImportService.parsePDFText("Custom Statement — Revolut Bank UAB")) { error in
            guard case FinanceImportError.unsupportedPDFStatement = error else {
                return XCTFail("expected unsupportedPDFStatement, got \(error)")
            }
        }
    }

    func testStatementMoneyParsing() {
        XCTAssertEqual(BrokerImportParsing.statementDecimal("€1,234.56")?.doubleValue ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(BrokerImportParsing.statementDecimal("-£3,517.75 (-€4,053.17)")?.doubleValue ?? 0, -3517.75, accuracy: 0.001)
        XCTAssertEqual(BrokerImportParsing.statementDecimal("0.00 AED (€0.00)")?.doubleValue ?? -1, 0, accuracy: 0.001)
    }

    func testFlexibleNumberFormatsEnglishAndEuropean() {
        func v(_ s: String) -> Double { BrokerImportParsing.flexibleDecimal(s)?.doubleValue ?? .nan }
        // ISO / Trade Republic
        XCTAssertEqual(v("5000.000000"), 5000, accuracy: 0.0001)
        XCTAssertEqual(v("0.43121985"), 0.43121985, accuracy: 1e-8)
        // English (comma thousands, dot decimal)
        XCTAssertEqual(v("1,234.56"), 1234.56, accuracy: 0.001)
        XCTAssertEqual(v("1,234,567"), 1234567, accuracy: 0.001)
        // European / German (dot thousands, comma decimal)
        XCTAssertEqual(v("1.234,56"), 1234.56, accuracy: 0.001)
        XCTAssertEqual(v("123,45"), 123.45, accuracy: 0.001)
        XCTAssertEqual(v("-6.000,00"), -6000, accuracy: 0.001)
        XCTAssertEqual(v("1.234.567"), 1234567, accuracy: 0.001)
    }

    func testGermanFormattedTradeRepublicAmountParses() throws {
        let header = "\"datetime\",\"date\",\"account_type\",\"category\",\"type\",\"asset_class\",\"name\",\"symbol\",\"shares\",\"price\",\"amount\",\"fee\",\"tax\",\"currency\""
        let csv = header + "\n"
            + "\"2026-02-01T10:00:00.000Z\",\"2026-02-01\",\"DEFAULT\",\"CASH\",\"CUSTOMER_INBOUND\",\"\",\"X\",\"\",\"\",\"\",\"1.234,56\",\"\",\"\",\"EUR\""
        let tx = try XCTUnwrap(try parse(csv).normalized.data.transactions.first)
        XCTAssertEqual(tx.amount.doubleValue, 1234.56, accuracy: 0.001) // not 1.23456 or 123456
    }
}
