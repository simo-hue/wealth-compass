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

    /// A lone `","` is the decimal separator — with one exception that this literal deliberately
    /// sits outside of.
    ///
    /// The comment here used to read, flatly, "a lone ',' is the decimal separator". That is no
    /// longer the whole rule: in a **money** field a lone separator followed by *exactly three*
    /// digits now groups thousands, so `"1,000"` is 1000 (see
    /// `testLoneSeparatorWithThreeDigitsIsThousandsInMoneyFields`). `"1234,56"` has two digits
    /// after the separator, so it is untouched by that rule and still means 1234.56 — which is why
    /// this test keeps its literal and its expectation unchanged. It pins the *other* side of the
    /// boundary: the ordinary two-decimal European amount that must not move.
    ///
    /// Exact, not approximate — the `accuracy:` form this assertion used to carry would have
    /// passed on a value that had round-tripped through `Double`, which is the whole thing WC-A1
    /// exists to prevent.
    func testCommaDecimalAmountIsParsed() throws {
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
        let junk = [
            "1.2.3", "12.34.56", "1.2.3.4", "1,2,3", "9.9.9.9.9", "1..2", "...1...", ",,,5,,,", "0x10",
            "1,2.3.4", "1.2345,67",
            // Widening the gate to Indian lakh grouping moved the rule from "every non-first group
            // is 3" to "the last group is 3, the middle ones are 2 or 3". These are the boundaries
            // of the new rule, and they have to stay junk: a short or over-long final group
            // (`"1,23,45"`, `"1,234,56"`, `"12,34,56,78"`, `"123,4567"` is a *decimal* and excluded
            // deliberately), a middle group of 1 (`"12,3,456"`, `"1,2,345"`) or of 4
            // (`"1,2345,678"`).
            "1,23,45", "1,234,56", "12,34,56,78", "12,3,456", "1,2,345", "1,2345,678", "1,00,00", "12,34,5"
        ]
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

    /// Indian lakh grouping is a real number, not a malformed cell.
    ///
    /// The first version of `hasNumericSeparatorLayout` required **every** non-first group to be
    /// exactly 3 digits and justified it as "deliberately Western-only". That was a regression, not
    /// a choice: all six forms below parsed at the commit immediately before the gate existed, and
    /// `BrokerImportParsing.flexibleDecimal` — the normalizer the gate claims to mirror — resolves
    /// every one of them to the correct value, so the gate was strictly narrower than the thing it
    /// was gating. `NumberFormatter(.decimal)` produces these for 51 locale identifiers, one of
    /// which (`hi`) this app ships. The rule is now "the last group is exactly 3, the middle groups
    /// are 2 or 3", which admits 2-2-3 lakh grouping and 3-3-3 Western grouping alike.
    ///
    /// Both separator spellings are pinned, because the gate resolves which separator groups before
    /// it looks at the group sizes — a `hi_IN` export and a lakh-grouped European export have to
    /// come out the same.
    func testIndianLakhGroupedStringAmountsImportExactly() throws {
        let pinned: [(literal: String, expected: String)] = [
            ("1,23,456.78", "123456.78"),
            ("12,34,567.89", "1234567.89"),
            ("1,23,45,678.9", "12345678.9"),
            ("1,00,000", "100000"),
            ("12,34,567", "1234567"),
            ("12,34,56,789.12", "123456789.12"),
            ("1.23.456,78", "123456.78"),
            ("12.34.567,89", "1234567.89"),
            ("1.23.45.678,9", "12345678.9")
        ]
        for (literal, expected) in pinned {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: expected),
                "\"\(literal)\" did not import as \(expected)"
            )
            XCTAssertEqual(result.skippedRecords, 0, "\"\(literal)\" was reported as a skipped record")
        }
    }

    /// The string forms the money rule must leave exactly as they were.
    ///
    /// **This test used to pin `("1,234", "1.234")` and `("1.234", "1.234")` and it no longer
    /// does** — those two moved to `testLoneSeparatorWithThreeDigitsIsThousandsInMoneyFields`,
    /// where a money field now reads them as **1234**. What survives here is everything the new
    /// rule does *not* touch, which is the boundary that keeps it from over-reaching:
    ///
    /// * **Two digits after a lone separator is still a decimal point.** `"1,50"` is 1.50. This is
    ///   the ordinary European money spelling and the reason the rule counts digits at all rather
    ///   than declaring every lone separator a grouping.
    /// * **Four or more digits, likewise.** `"1,2345"` is 1.2345. No grouping produces a group of
    ///   four.
    /// * **A 4-digit part before the separator, likewise.** `"1234,567"` is 1234.567 — a
    ///   deliberate narrowing of "a lone separator plus three digits". Genuine grouped output
    ///   writes a million as `"1,234,567"`, never `"1234,567"`, so reading that as 1234567 would
    ///   buy nothing and add a 1000× over-read in the mirror direction. The 1–3 digit first group
    ///   is the same rule `hasNumericSeparatorLayout` already applies to every other grouped form.
    /// * **Exponent notation keeps working.** JavaScript's `String(0.0000001)` is `"1e-7"`, so a
    ///   web backup really can carry it, and only the plain form reads it — which is why the plain
    ///   form must stay ahead of the grouped fallback. (It is *not* true that the fallback would
    ///   misread `"1e-7"` as 17; measured, `flexibleDecimal("1e-7")` is **1**, and `"1E5"` is
    ///   **15**. With the charset gate in place the fallback rejects both outright. The ordering is
    ///   still required; the danger was overstated.) `"2.5e3"` is worth pinning specifically: its
    ///   lone `"."` is followed by exactly three *characters*, so it is the shape the money rule
    ///   would grab if it counted characters instead of digits.
    func testStringAmountsOutsideTheThousandsRuleKeepTheirExistingMeaning() throws {
        let pinned: [(literal: String, expected: String)] = [
            ("1,50", "1.50"),
            ("1.50", "1.50"),
            ("1,2345", "1.2345"),
            ("1.2345", "1.2345"),
            ("1234,567", "1234.567"),
            ("1234.567", "1234.567"),
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
            XCTAssertEqual(result.skippedRecords, 0, "\(literal) was reported as a skipped record")
        }
    }

    /// A lone separator followed by exactly three digits is grouped thousands **in a money field**.
    ///
    /// This reverses an earlier decision, deliberately. Until now the decoder resolved a lone
    /// separator as a decimal point everywhere, so an imported `"1,000"` became **1** and so did
    /// `"1.000"` — the two commonest ways a thousand is written down, both read 1000× small, on the
    /// single most likely malformed cell a user can hand a JSON backup. Nothing is skipped and
    /// nothing is counted when that happens: the figure just quietly becomes a different, entirely
    /// plausible figure.
    ///
    /// **The rule diverges from `BrokerImportParsing.flexibleDecimal` on purpose.** That normalizer
    /// still reads `"1,000"` as 1, and the grouped-thousands fallback in this decoder still
    /// delegates to it; the money reading is applied *before* either sees the string. The two are
    /// allowed to disagree here because they read different things: `flexibleDecimal` parses broker
    /// CSV cells from Trade Republic and Revolut exports, which always print a fractional part, so
    /// a lone separator there really is a decimal point and changing it would misread every
    /// `"1,50"` in a statement. If you came here because the two gave you different numbers for the
    /// same string — that is the design, and this is the note saying so.
    ///
    /// **The accepted cost**, stated by the owner and not to be solved by sniffing the currency
    /// code: a three-decimal currency (BHD, KWD, OMR) writes 1.5 dinar as `"1,500"`, and that now
    /// imports as 1500.
    func testLoneSeparatorWithThreeDigitsIsThousandsInMoneyFields() throws {
        let pinned: [(literal: String, expected: String)] = [
            ("1,000", "1000"),
            ("1.000", "1000"),
            ("1,234", "1234"),
            ("1.234", "1234"),
            ("12,345", "12345"),
            ("123,456", "123456"),
            ("999.999", "999999"),
            // The rule counts digits, not value: a leading zero groups the same way.
            ("0,001", "1")
        ]
        for (literal, expected) in pinned {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(
                result.data.transactions.first?.amount, Decimal(string: expected),
                "\"\(literal)\" did not import as \(expected)"
            )
            XCTAssertEqual(result.skippedRecords, 0, "\"\(literal)\" was reported as a skipped record")
        }
    }

    /// Every money field, not just `transactions[].amount`.
    ///
    /// The split is made at the call site rather than sniffed from the key name, which means it can
    /// be got wrong one field at a time — and a field in the wrong family is a silent 1000× error
    /// in exactly the direction this rule exists to prevent. So each family of `Imported*` decoder
    /// gets its own record here, including the two **per-unit prices** that sit beside a quantity
    /// (`Investment.currentPrice`, `CryptoHolding.avgBuyPrice`): those are money per share, not a
    /// count of shares.
    func testEveryMoneyFieldReadsGroupedThousandsIncludingPerUnitPrices() throws {
        let result = try parse("""
        {"transactions":[{"type":"income","amount":"1,000","category":"Salary","date":"2026-01-01"}],
         "recurringTransactions":[
           {"type":"expense","amount":"1,000","category":"Rent","startDate":"2026-01-01",
            "frequency":"monthly","nextDueDate":"2026-02-01"}
         ],
         "income":[{"type":"dividends","amount":"2,000","date":"2026-01-02"}],
         "expenses":[{"category":"Food","amount":"3,000","date":"2026-01-03"}],
         "liquidity":[{"name":"Acct","balance":"4,000","updatedAt":"2026-01-04"}],
         "investments":[
           {"symbol":"A","name":"A","quantity":2,"currentPrice":"1,000","costBasis":"5,000","fees":"1,500"}
         ],
         "crypto":[{"symbol":"B","name":"B","quantity":2,"avgBuyPrice":"1,000","currentPrice":"2,000","fees":"1,500"}],
         "liabilities":[{"name":"L","principal":"9,000","currentBalance":"8,000"}],
         "snapshots":[
           {"date":"2026-01-05","netWorth":"1,000","totalAssets":"2,000","totalLiabilities":"1,000",
            "liquidity":"3,000","investments":"4,000","crypto":"5,000"}
         ]}
        """)

        func transaction(category: String) -> Transaction? {
            result.data.transactions.first { $0.category == category }
        }
        XCTAssertEqual(transaction(category: "Salary")?.amount, Decimal(string: "1000"), "transactions[].amount")
        XCTAssertEqual(result.data.recurringTransactions.first?.amount, Decimal(string: "1000"), "recurring amount")
        XCTAssertEqual(transaction(category: "Dividends")?.amount, Decimal(string: "2000"), "legacy income amount")
        XCTAssertEqual(transaction(category: "Food")?.amount, Decimal(string: "3000"), "legacy expense amount")
        XCTAssertEqual(transaction(category: "Liquidity")?.amount, Decimal(string: "4000"), "liquidity balance")

        let investment = try XCTUnwrap(result.data.investments.first)
        XCTAssertEqual(investment.currentPrice, Decimal(string: "1000"), "investment currentPrice")
        XCTAssertEqual(investment.costBasis, Decimal(string: "5000"), "investment costBasis")
        XCTAssertEqual(investment.fees, Decimal(string: "1500"), "investment fees")
        // Absent `currentValue` is derived as quantity x price, so the price rule reaches it too.
        XCTAssertEqual(investment.currentValue, Decimal(string: "2000"), "investment currentValue")

        let holding = try XCTUnwrap(result.data.crypto.first)
        XCTAssertEqual(holding.avgBuyPrice, Decimal(string: "1000"), "crypto avgBuyPrice")
        XCTAssertEqual(holding.currentPrice, Decimal(string: "2000"), "crypto currentPrice")
        XCTAssertEqual(holding.fees, Decimal(string: "1500"), "crypto fees")

        XCTAssertEqual(result.data.liabilities.first?.currentBalance, Decimal(string: "8000"), "liability currentBalance")

        let snapshot = try XCTUnwrap(result.data.snapshots.first)
        XCTAssertEqual(snapshot.netWorth, Decimal(string: "1000"), "snapshot netWorth")
        XCTAssertEqual(snapshot.totalAssets, Decimal(string: "2000"), "snapshot totalAssets")
        XCTAssertEqual(snapshot.totalLiabilities, Decimal(string: "1000"), "snapshot totalLiabilities")
        XCTAssertEqual(snapshot.liquidity, Decimal(string: "3000"), "snapshot liquidity")
        XCTAssertEqual(snapshot.investments, Decimal(string: "4000"), "snapshot investments")
        XCTAssertEqual(snapshot.crypto, Decimal(string: "5000"), "snapshot crypto")

        XCTAssertEqual(result.skippedRecords, 0, "a grouped-thousands cell dropped a record")
    }

    /// `principal` is money too — reachable only when `currentBalance` is absent.
    func testLiabilityPrincipalReadsGroupedThousandsWhenItIsTheOnlyFigure() throws {
        let result = try parse(#"{"liabilities":[{"name":"L","principal":"7,000"}]}"#)
        XCTAssertEqual(result.data.liabilities.first?.currentBalance, Decimal(string: "7000"))
        XCTAssertEqual(result.skippedRecords, 0)
    }

    /// The two families genuinely differ: **the same literal, in one record, landing on two
    /// different numbers.**
    ///
    /// `Investment.quantity` and `CryptoHolding.quantity` are the only two `.quantity` fields in
    /// the importer, and this is the assertion that would catch either of them being flipped to
    /// money — or, in the other direction, a money field being mis-filed as a quantity. Reading a
    /// quantity as thousands would turn 0.001 BTC into 1 BTC, which is the same defect class as the
    /// money under-read, pointing the other way.
    func testTheSameLiteralMeansDifferentThingsInMoneyAndQuantityFields() throws {
        let result = try parse("""
        {"investments":[{"symbol":"A","name":"A","quantity":"1,000","currentPrice":"1,000"}],
         "crypto":[{"symbol":"B","name":"B","quantity":"1,000","avgBuyPrice":"1,000"}]}
        """)

        let investment = try XCTUnwrap(result.data.investments.first)
        XCTAssertEqual(investment.quantity, Decimal(string: "1"), #""1,000" shares must stay 1"#)
        XCTAssertEqual(investment.currentPrice, Decimal(string: "1000"), #""1,000" per share must be 1000"#)

        let holding = try XCTUnwrap(result.data.crypto.first)
        XCTAssertEqual(holding.quantity, Decimal(string: "1"), #""1,000" coins must stay 1"#)
        XCTAssertEqual(holding.avgBuyPrice, Decimal(string: "1000"), #""1,000" per coin must be 1000"#)

        XCTAssertNotEqual(investment.quantity, investment.currentPrice, "the two families collapsed into one")
        XCTAssertEqual(result.skippedRecords, 0)
    }

    /// Quantities keep the old rule, whole: a lone separator is a decimal point whatever follows it.
    ///
    /// A sub-unit crypto holding is ordinary — `"0,001"` BTC is a thousandth of a coin, not one —
    /// and there is no widely-written "1,000 shares" grouping in a backup field that already holds
    /// fractional share counts. This is the old behaviour, pinned where it still applies.
    func testQuantityFieldsStillReadALoneSeparatorAsADecimalPoint() throws {
        let pinned: [(literal: String, expected: String)] = [
            ("0,001", "0.001"),
            ("0.001", "0.001"),
            ("1,000", "1"),
            ("1.000", "1"),
            ("1,234", "1.234"),
            ("2,5", "2.5")
        ]
        for (literal, expected) in pinned {
            let result = try parse("""
            {"investments":[{"symbol":"A","name":"A","quantity":"\(literal)","currentPrice":10}],
             "crypto":[{"symbol":"B","name":"B","quantity":"\(literal)","currentPrice":10}]}
            """)
            XCTAssertEqual(
                result.data.investments.first?.quantity, Decimal(string: expected),
                "investment quantity \"\(literal)\" did not stay \(expected)"
            )
            XCTAssertEqual(
                result.data.crypto.first?.quantity, Decimal(string: expected),
                "crypto quantity \"\(literal)\" did not stay \(expected)"
            )
            XCTAssertEqual(result.skippedRecords, 0, "\"\(literal)\" was reported as a skipped record")
        }
    }

    /// The money rule must not change *which* records import, only what they say.
    ///
    /// It runs ahead of the plain form and the grouped fallback both, so a bug in it could reject a
    /// string those two used to accept — and a previously-importing record landing in
    /// `skippedRecords` is the regression this series has already shipped once (the Indian lakh
    /// grouping, fixed in `5070f57`). Every literal below imported before the rule existed and has
    /// to keep importing.
    func testTheMoneyRuleNeverTurnsAnImportableAmountIntoASkippedRecord() throws {
        let literals = [
            "1,000", "1.000", "1,50", "1.2345", "1234,567", "1,234.56", "1.234,56",
            "1,234,567", "1.234.567", "1,23,456.78", "1,00,000", "12,34,567.89",
            "1e-7", "2.5e3", "1000", "0.5", "1,", ",5", "1."
        ]
        for literal in literals {
            let result = try parse("""
            {"transactions":[{"type":"income","amount":"\(literal)","category":"X","date":"2026-01-01"}]}
            """)
            XCTAssertEqual(result.data.transactions.count, 1, "\"\(literal)\" stopped importing")
            XCTAssertEqual(result.skippedRecords, 0, "\"\(literal)\" was newly reported as skipped")
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
