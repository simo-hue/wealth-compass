import XCTest
@testable import WealthCompassMobile

/// T4 — lossy import parser: modern + legacy shapes, comma decimals, multiple date
/// formats, and skipped-record counting (M1 / `FinanceImportService`).
@MainActor
final class FinanceImportServiceTests: XCTestCase {
    private func settings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "wc.tests.\(UUID().uuidString)")!)
    }

    private func parse(_ json: String) throws -> NormalizedFinanceImport {
        // L55: parse now takes a value-type context instead of `AppSettings`.
        let settings = settings()
        let context = FinanceImportContext(displayCurrency: settings.currency, snapshot: settings.exchangeRateSnapshot)
        return try FinanceImportService.parse(Data(json.utf8), context: context)
    }

    // MARK: - Export -> import round trip

    /// A backup this app wrote must import back as the same data. The per-record `currency` field
    /// is the one the round trip used to drop: `Transaction.currency == nil` means "legacy row,
    /// assume base currency", so a dropped USD tag silently re-denominates $1,000 as EUR 1,000.
    func testRoundTripPreservesPerRecordCurrency() throws {
        let day = Date(timeIntervalSince1970: 1_780_000_000)

        var transaction = Transaction(
            type: .income, category: "Salary", amount: 1000, description: "", date: day
        )
        transaction.currency = .usd

        var recurring = RecurringTransaction(
            type: .expense, category: "Rent", amount: 500, description: "",
            startDate: day, frequency: .monthly, nextDueDate: day
        )
        recurring.currency = .gbp

        var snapshot = NetWorthSnapshot(
            date: day, totalAssets: 10, totalLiabilities: 0,
            netWorth: 10, liquidity: 10, investments: 0, crypto: 0
        )
        snapshot.currency = .chf

        let exported = try FinanceJSONCoding.encode(
            FinancialData(
                transactions: [transaction],
                recurringTransactions: [recurring],
                snapshots: [snapshot]
            )
        )
        // Guard the premise: the exporter really does write the field.
        let json = String(decoding: exported, as: UTF8.self)
        XCTAssertTrue(json.contains("USD"), "exporter dropped the transaction currency")

        let settings = settings()
        let context = FinanceImportContext(
            displayCurrency: settings.currency, snapshot: settings.exchangeRateSnapshot
        )
        let result = try FinanceImportService.parse(exported, context: context)

        XCTAssertEqual(result.data.transactions.first?.currency, .usd, "transaction currency lost")
        XCTAssertEqual(result.data.recurringTransactions.first?.currency, .gbp, "recurring currency lost")
        XCTAssertEqual(result.data.snapshots.first?.currency, .chf, "snapshot currency lost")
    }

    /// A magnitude `Decimal` cannot represent must never reach storage.
    ///
    /// `Decimal(Double)` yields `NSDecimalNumber.notANumber` for finite `Double`s outside its range
    /// — verified for both `1e300` and `1e-300` — and `JSONEncoder` then writes the bare token
    /// `NaN`, which is not valid JSON. The app would persist a database it cannot read back, and
    /// the failure surfaces on the *next* launch with no in-app way out.
    func testAmountsDecimalCannotHoldAreSkippedRatherThanStoredAsNaN() throws {
        for literal in ["1e300", "-1e300", "1e-300"] {
            let result = try parse("""
            {"transactions":[
              {"type":"income","amount":\(literal),"category":"X","date":"2026-01-01"},
              {"type":"income","amount":10,"category":"Good","date":"2026-01-02"}
            ]}
            """)
            XCTAssertEqual(
                result.data.transactions.count, 1,
                "\(literal) must be skipped, and the healthy row beside it must survive"
            )
            XCTAssertEqual(result.data.transactions.first?.category, "Good")
            XCTAssertTrue(
                result.data.transactions.allSatisfy {
                    ($0.amount as NSDecimalNumber) != NSDecimalNumber.notANumber
                },
                "\(literal) produced a non-finite stored amount"
            )
        }
    }

    /// The consequence the test above exists to prevent: whatever an import produces has to
    /// round-trip through the app's own encoder as valid JSON.
    func testImportedDataAlwaysReencodesAsValidJSON() throws {
        let result = try parse("""
        {"transactions":[{"type":"income","amount":1e300,"category":"X","date":"2026-01-01"}],
         "investments":[{"symbol":"A","name":"A","quantity":1e300,"currentValue":1e300}],
         "crypto":[{"symbol":"B","name":"B","quantity":1e-300,"currentPrice":1e300}],
         "snapshots":[{"date":"2026-01-01","netWorth":1e300}]}
        """)
        let encoded = try FinanceJSONCoding.encode(result.data)
        XCTAssertNotNil(
            try? JSONSerialization.jsonObject(with: encoded),
            "the importer produced a database the app cannot read back: "
            + String(decoding: encoded, as: UTF8.self).prefix(200)
        )
    }

    func testModernTransactionsShape() throws {
        let result = try parse("""
        {"transactions":[
          {"type":"income","amount":1000,"category":"Salary","date":"2026-06-01"},
          {"type":"expense","amount":300,"category":"Food","date":"2026-06-02"}
        ]}
        """)
        XCTAssertEqual(result.data.transactions.count, 2)
        XCTAssertEqual(result.skippedRecords, 0)
    }

    func testLegacyIncomeShapeMapsToTransactions() throws {
        let result = try parse(#"{"income":[{"type":"salary","amount":2000,"date":"2026-06-01"}]}"#)
        XCTAssertEqual(result.data.transactions.count, 1)
        XCTAssertEqual(result.data.transactions.first?.type, .income)
        XCTAssertEqual(result.data.transactions.first?.amount, 2000)
    }

    func testCommaDecimalAmountIsParsed() throws {
        // The parser swaps "," for "." (decimal comma); it does NOT strip thousands separators.
        let result = try parse(#"{"transactions":[{"type":"expense","amount":"1234,56","category":"Rent","date":"2026-06-03"}]}"#)
        XCTAssertEqual((result.data.transactions.first?.amount ?? 0).doubleValue, 1234.56, accuracy: 0.001)
    }

    func testMultipleDateFormatsBothParse() throws {
        let result = try parse("""
        {"transactions":[
          {"type":"income","amount":10,"category":"A","date":"2026-06-01"},
          {"type":"income","amount":20,"category":"B","date":"2026-06-02T10:30:00Z"}
        ]}
        """)
        XCTAssertEqual(result.data.transactions.count, 2)
    }

    func testInvalidRecordsAreSkippedAndCounted() throws {
        // Second entry has a non-positive amount → dropped by `model()` and counted as skipped.
        let result = try parse("""
        {"transactions":[
          {"type":"income","amount":100,"category":"X","date":"2026-06-01"},
          {"type":"income","amount":-5,"category":"Bad","date":"2026-06-02"}
        ]}
        """)
        XCTAssertEqual(result.data.transactions.count, 1)
        XCTAssertGreaterThanOrEqual(result.skippedRecords, 1)
    }

    func testEmptyOrUnsupportedJSONYieldsNoContent() throws {
        let result = try parse("{}")
        XCTAssertFalse(result.data.hasImportableContent)
    }

    /// The headline number in the import summary popup: `importedRecordCount` sums only the
    /// six entity counts — it must NOT fold in generated snapshots, added categories, or
    /// skipped records (those are reported separately).
    func testImportedRecordCountSumsEntitiesOnly() {
        let result = FinanceImportResult(
            sourceFileName: "backup.json",
            mode: .merge,
            transactions: 5,
            recurringTransactions: 2,
            investments: 3,
            crypto: 1,
            liabilities: 4,
            snapshots: 6,
            generatedSnapshots: 1,
            categoriesAdded: 7,
            skippedRecords: 9
        )
        XCTAssertEqual(result.importedRecordCount, 5 + 2 + 3 + 1 + 4 + 6)
    }
}
