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

    /// A separator with no digits beside it is not zero.
    ///
    /// `Decimal(string: ".")` returns **0**, not nil, so routing string amounts through the
    /// grouped-thousands fallback made `"."` and `","` parse as a real zero. A transaction still
    /// gets dropped — it needs a positive amount — but a snapshot's `netWorth` only has to be
    /// finite, so a meaningless cell became an on-screen net-worth reading of zero.
    func testSeparatorOnlyStringAmountIsSkippedNotReadAsZero() throws {
        for literal in [".", ",", ".,", "-."] {
            let result = try parse("""
            {"snapshots":[{"date":"2026-01-01","netWorth":"\(literal)"}]}
            """)
            XCTAssertTrue(result.data.snapshots.isEmpty, "\"\(literal)\" was read as a zero net worth")
            XCTAssertEqual(result.skippedRecords, 1, "\"\(literal)\" was neither imported nor reported")
        }
    }

    /// Separators where a number cannot have them are junk, not a number.
    ///
    /// The grouped-thousands fallback reuses `BrokerImportParsing.flexibleDecimal`, which is
    /// deliberately permissive: it feeds a CSV tokenizer that has already decided the column holds
    /// money, so it strips separators it cannot explain rather than refusing. This decoder has no
    /// such column to lean on. Without a layout check it read `"1.2.3"` as **123** and
    /// `"12.34.56"` as **123456** — inventing a figure out of a malformed cell, which is worse
    /// than misreading one, because the record used to be *counted* and the user was told.
    func testMalformedSeparatorLayoutIsSkippedRatherThanInvented() throws {
        let junk = ["1.2.3", "12.34.56", "1.2.3.4", "1,2,3", "9.9.9.9.9", "1..2", "...1...", ",,,5,,,", "0x10"]
        for literal in junk {
            let result = try parse("""
            {"snapshots":[{"date":"2026-01-01","netWorth":"\(literal)"}]}
            """)
            XCTAssertTrue(
                result.data.snapshots.isEmpty,
                "\"\(literal)\" was invented into a net worth of \(result.data.snapshots.first?.netWorth.description ?? "?")"
            )
            XCTAssertEqual(result.skippedRecords, 1, "\"\(literal)\" was dropped without being reported")
        }
    }

    /// The forms the grouped-thousands fix must leave exactly as they were.
    ///
    /// * A bare `"1,234"` stays **1.234**. It is genuinely ambiguous (1234 in en-US, 1.234 in
    ///   de-DE), and a lone separator is resolved as a decimal point everywhere in this codebase —
    ///   `BrokerImportParsing.flexibleDecimal`, which the fallback reuses, does the same. Keeping
    ///   the two in agreement is the point: two normalizers that disagree about what a string
    ///   means is how this class of bug returns.
    ///   (An earlier version of this comment justified the choice by claiming the alternative would
    ///   misread Trade Republic share quantities. That was wrong twice over — those go through
    ///   `BrokerImportParsing.plainDecimal` and never reach this decoder, and `flexibleDecimal`
    ///   reads `"1.234"` as 1.234 regardless. The choice stands; that reason never held.)
    /// * Exponent notation keeps working. JavaScript's `String(0.0000001)` is `"1e-7"`, so a web
    ///   backup really can carry it, and only the plain form reads it — which is why the plain form
    ///   must stay first. (It is *not* true that the fallback would misread `"1e-7"` as 17;
    ///   measured, `flexibleDecimal("1e-7")` is **1**, and `"1E5"` is **15**. With the charset gate
    ///   in place the fallback rejects both outright. The ordering is still required; the danger
    ///   was overstated.)
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

    /// An ISO code this app does not model must skip the row, not relabel it.
    ///
    /// Falling back to the display currency kept the number and changed its meaning — an AED 5,000
    /// row silently became EUR 5,000, with nothing on screen to say so. That is worse than dropping
    /// it. The Revolut parser already makes the opposite choice for an unrepresentable account
    /// section (`sectionCurrency` → `.unsupported` → skipped and counted); this is the same choice
    /// for a JSON backup, across all seven places a currency code is read.
    func testUnrepresentableCurrencyCodeSkipsTheRecordInsteadOfRelabellingIt() throws {
        let result = try parse("""
        {"transactions":[
           {"type":"income","amount":5000,"category":"X","date":"2026-01-01","currency":"AED"},
           {"type":"income","amount":10,"category":"Good","date":"2026-01-02","currency":"USD"}
         ],
         "recurringTransactions":[
           {"type":"expense","amount":5000,"category":"Rent","startDate":"2026-01-01",
            "frequency":"monthly","nextDueDate":"2026-02-01","currency":"AED"}
         ],
         "investments":[{"symbol":"A","name":"A","quantity":1,"currentValue":5000,"currency":"AED"}],
         "crypto":[{"symbol":"B","name":"B","quantity":1,"currentPrice":5000,"currency":"AED"}],
         "liabilities":[{"name":"L","currentBalance":5000,"currency":"AED"}],
         "snapshots":[{"date":"2026-01-01","netWorth":5000,"currency":"AED"}],
         "liquidity":[{"name":"Acct","balance":5000,"currency":"AED"}]}
        """)
        XCTAssertEqual(result.data.transactions.count, 1, "an AED transaction or liquidity row was kept")
        XCTAssertEqual(result.data.transactions.first?.currency, .usd, "the healthy row beside it must survive")
        XCTAssertEqual(result.data.transactions.first?.amount, Decimal(string: "10"))
        XCTAssertTrue(result.data.recurringTransactions.isEmpty)
        XCTAssertTrue(result.data.investments.isEmpty)
        XCTAssertTrue(result.data.crypto.isEmpty)
        XCTAssertTrue(result.data.liabilities.isEmpty)
        XCTAssertTrue(result.data.snapshots.isEmpty)
        // Seven rows carried AED; the user has to be told about every one of them.
        XCTAssertEqual(result.skippedRecords, 7, "unrepresentable rows were dropped without being reported")
    }

    /// The legacy meaning the skip must not break: an **absent** currency field is a row written
    /// before the field existed. It stays `nil` on the three optional-currency models (read as base
    /// currency downstream) and takes the display currency on the four non-optional ones — and in
    /// neither case does the record get dropped.
    func testAbsentCurrencyIsLegacyNotUnrepresentable() throws {
        let result = try parse("""
        {"transactions":[{"type":"income","amount":10,"category":"X","date":"2026-01-01"}],
         "recurringTransactions":[
           {"type":"expense","amount":20,"category":"Rent","startDate":"2026-01-01",
            "frequency":"monthly","nextDueDate":"2026-02-01"}
         ],
         "investments":[{"symbol":"A","name":"A","quantity":1,"currentValue":30}],
         "crypto":[{"symbol":"B","name":"B","quantity":1,"currentPrice":40}],
         "liabilities":[{"name":"L","currentBalance":50}],
         "snapshots":[{"date":"2026-01-01","netWorth":60}]}
        """)
        XCTAssertNil(result.data.transactions.first?.currency)
        XCTAssertNil(result.data.recurringTransactions.first?.currency)
        XCTAssertNil(result.data.snapshots.first?.currency)
        XCTAssertEqual(result.data.investments.first?.currency, .eur)
        XCTAssertEqual(result.data.crypto.first?.currency, .eur)
        XCTAssertEqual(result.data.liabilities.first?.currency, .eur)
        XCTAssertEqual(result.skippedRecords, 0)
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
