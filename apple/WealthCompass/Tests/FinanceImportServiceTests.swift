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
        try FinanceImportService.parse(Data(json.utf8), settings: settings())
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
        XCTAssertEqual(result.data.transactions.first?.amount ?? 0, 1234.56, accuracy: 0.001)
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
}
