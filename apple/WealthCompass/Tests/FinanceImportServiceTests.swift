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

        // Exactly, not approximately. Reading money through `Double` stored 1234.56 as
        // 1234.5599999999997952, so a tolerance-based assertion would pass while the backup
        // silently stopped being a fixed point and every record's sync hash changed.
        XCTAssertEqual(result.data.transactions.first?.amount, Decimal(string: "1000"))
        XCTAssertEqual(result.data.recurringTransactions.first?.amount, Decimal(string: "500"))
    }

    /// Ordinary two-decimal money has to survive import exactly. This is the same corruption class
    /// the persistence layer was fixed for; import was the last place money crossed `Double`.
    func testOrdinaryAmountsImportExactly() throws {
        for literal in ["1234.56", "99999999.99", "1234567.89", "0.12345678901234567"] {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":\(literal),"category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: literal),
                "\(literal) did not import exactly"
            )
        }
    }

    /// The same, for an amount supplied as a JSON string rather than a number.
    func testStringAmountsImportExactly() throws {
        let result = try parse("""
        {"transactions":[{"type":"income","amount":"1234.56","category":"X","date":"2026-01-01"}]}
        """)
        XCTAssertEqual(result.data.transactions.first?.amount, Decimal(string: "1234.56"))
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
        // A lone "," is the decimal separator. Exact, not approximate — the `accuracy:` form this
        // assertion used to carry would have passed on a value that had round-tripped through
        // `Double`, which is the whole thing WC-A1 exists to prevent.
        let result = try parse(#"{"transactions":[{"type":"expense","amount":"1234,56","category":"Rent","date":"2026-06-03"}]}"#)
        XCTAssertEqual(result.data.transactions.first?.amount, Decimal(string: "1234.56"))
    }

    /// A grouped-thousands amount must not make the record vanish.
    ///
    /// The old normalizer swapped *every* "," for "." before gating on `Double`, so an English
    /// `"1,234.56"` and a European `"1.234,56"` both became `"1.234.56"`, both failed the gate,
    /// and the field decoded to `nil` — which drops the entire transaction. The two spellings are
    /// the same amount and must import as the same exact `Decimal`.
    func testGroupedThousandsStringAmountsSurviveAndAgree() throws {
        for literal in ["1,234.56", "1.234,56"] {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(result.data.transactions.count, 1, "\(literal) dropped the whole record")
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: "1234.56"),
                "\(literal) did not import as 1234.56"
            )
        }
        // Repeated groups with no fractional part: both spellings still agree.
        for literal in ["1,234,567", "1.234.567"] {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: "1234567"),
                "\(literal) did not import as 1234567"
            )
        }
    }

    /// The forms the grouped-thousands fix must leave exactly as they were.
    ///
    /// * A bare `"1,234"` stays **1.234**. It is genuinely ambiguous (1234 in en-US, 1.234 in
    ///   de-DE) and the whole codebase resolves a lone separator as a decimal point — see
    ///   `BrokerImportParsing.flexibleDecimal`, which the fallback below reuses. Reading it as
    ///   1234 instead would turn every ISO `"1.234"` share quantity in the Trade Republic export
    ///   into 1234, i.e. trade one 1000x error for another in a path that is currently correct.
    /// * Exponent notation keeps working. JavaScript's `String(0.0000001)` is `"1e-7"`, so a web
    ///   backup really can carry it, and a last-separator-wins normalizer would read it as 17.
    func testAmbiguousAndExponentStringAmountsKeepTheirExistingMeaning() throws {
        let pinned: [(literal: String, expected: String)] = [
            ("1,234", "1.234"),
            ("1.234", "1.234"),
            ("1e-7", "0.0000001"),
            ("2.5e3", "2500")
        ]
        for (literal, expected) in pinned {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: expected),
                "\(literal) no longer imports as \(expected)"
            )
        }
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
