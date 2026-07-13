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

    func testStatementMoneyParsing() {
        XCTAssertEqual(BrokerImportParsing.statementDecimal("€1,234.56")?.doubleValue ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(BrokerImportParsing.statementDecimal("-£3,517.75 (-€4,053.17)")?.doubleValue ?? 0, -3517.75, accuracy: 0.001)
        XCTAssertEqual(BrokerImportParsing.statementDecimal("0.00 AED (€0.00)")?.doubleValue ?? -1, 0, accuracy: 0.001)
    }
}
