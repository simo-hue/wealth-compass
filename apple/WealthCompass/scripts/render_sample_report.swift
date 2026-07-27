// Renders sample PDF reports from synthetic data, without Xcode.
//
// This machine has only the Command Line Tools, so `xcodebuild` cannot build the app targets.
// But the report pipeline depends only on system frameworks that ship in the CLT SDK, so it can
// be compiled and *run* directly — which is the whole reason the renderer is written against
// CoreGraphics/CoreText/PDFKit instead of SwiftUI + Swift Charts.
//
// Build and run (from `apple/WealthCompass`):
//
//   swiftc -swift-version 5 \
//     -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
//     -target arm64-apple-macos14.0 \
//     $(find Sources/Shared -name '*.swift') scripts/render_sample_report.swift \
//     -o /tmp/render_sample_report
//   /tmp/render_sample_report /tmp/samples
//
// Then inspect the PDFs, e.g.:
//
//   sips -s format png --resampleWidth 900 /tmp/samples/full-report.pdf --out /tmp/page.png
//
// Fixtures are generated from a seeded generator, so output is byte-stable across runs and a
// visual diff between two revisions is meaningful.

import Foundation
import PDFKit

// MARK: - Deterministic fixtures

/// Small LCG so sample data is identical on every run. `Foundation.SystemRandomNumberGenerator`
/// would make every render differ and destroy the value of comparing two revisions.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64 = 0x5EED_1234_ABCD_0001) { self.state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int.random(in: 0..<items.count, using: &self)]
    }
}

enum SampleData {
    /// Fixed "today" so date arithmetic in the report is reproducible.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 27
        components.hour = 11
        components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .gmt
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_785_000_000)
    }()

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .gmt
        return calendar
    }

    static let incomeCategories = ["Salary", "Freelance", "Dividends", "Interest", "Refund"]
    static let expenseCategories = [
        "Groceries", "Rent", "Utilities", "Transport", "Dining", "Health",
        "Subscriptions", "Travel", "Education", "Insurance",
    ]
    static let merchants = [
        "Esselunga", "Enel Energia", "Trenitalia", "Osteria del Borgo", "Farmacia Centrale",
        "Spotify", "Booking.com", "Politecnico di Milano", "Generali", "Amazon",
        "Il Fornaio", "Vodafone", "IKEA", "Decathlon", "Libreria Feltrinelli",
    ]

    /// A deliberately awkward dataset: three years of ledger, multi-currency holdings, a
    /// future-dated entry, a paused recurring rule, and a holding with no ISIN — so the report's
    /// edge-case handling is exercised on every render rather than only in production.
    static func build(transactionCount: Int = 620) -> FinancialData {
        var rng = SeededGenerator()
        var data = FinancialData()
        let calendar = self.calendar

        // Transactions across ~3 years
        for index in 0..<transactionCount {
            let daysBack = Int(Double(index) / Double(transactionCount) * 1_080)
            guard let date = calendar.date(byAdding: .day, value: -(1_080 - daysBack), to: now) else { continue }
            let isIncome = index % 9 == 0
            let currency: Currency? = index % 37 == 0 ? .usd : nil
            let amount = isIncome
                ? Decimal(rng.double(1_800...3_400)).rounded(2)
                : Decimal(rng.double(6...480)).rounded(2)

            data.transactions.append(Transaction(
                type: isIncome ? .income : .expense,
                category: isIncome ? rng.pick(incomeCategories) : rng.pick(expenseCategories),
                amount: amount,
                description: isIncome ? "Payment received" : rng.pick(merchants),
                date: date,
                currency: currency))
        }

        // Two future-dated entries — excluded from cash by AnalyticsEngine, still printed.
        if let future = calendar.date(byAdding: .day, value: 12, to: now) {
            data.transactions.append(Transaction(
                type: .expense, category: "Insurance", amount: 412.90,
                description: "Annual policy renewal", date: future))
        }
        if let future = calendar.date(byAdding: .day, value: 26, to: now) {
            data.transactions.append(Transaction(
                type: .income, category: "Freelance", amount: 1_250,
                description: "Invoice 2026-114", date: future))
        }

        // Recurring rules
        let recurringSpecs: [(String, String, Decimal, TransactionType, RecurringTransactionFrequency, Bool)] = [
            ("Rent", "Rent", 1_150, .expense, .monthly, true),
            ("Salary", "Salary", 3_100, .income, .monthly, true),
            ("Gym membership", "Health", 49.90, .expense, .monthly, false),
            ("Home insurance", "Insurance", 380, .expense, .yearly, true),
        ]
        for (description, category, amount, type, frequency, active) in recurringSpecs {
            let next = calendar.date(byAdding: .day, value: rng.int(2...28), to: now) ?? now
            let start = calendar.date(byAdding: .month, value: -14, to: now) ?? now
            data.recurringTransactions.append(RecurringTransaction(
                type: type, category: category, amount: amount, description: description,
                startDate: start, frequency: frequency, nextDueDate: next, isActive: active))
        }

        // Investments — mixed currencies, one deliberately missing an ISIN and a sector.
        let investmentSpecs: [(String, String, InvestmentType, Decimal, Decimal, Decimal, Currency, String, String, String)] = [
            ("VWCE", "Vanguard FTSE All-World", .etf, 142, 92.10, 118.44, .eur, "Global", "Diversified", "IE00BK5BQT80"),
            ("SWDA", "iShares Core MSCI World", .etf, 88, 74.20, 96.31, .eur, "Global", "Diversified", "IE00B4L5Y983"),
            ("AAPL", "Apple Inc.", .stock, 30, 148.30, 214.75, .usd, "North America", "Technology", "US0378331005"),
            ("ASML", "ASML Holding", .stock, 6, 590.00, 702.40, .eur, "Europe", "Technology", "NL0010273215"),
            ("ENI", "Eni S.p.A.", .stock, 260, 13.10, 15.02, .eur, "Europe", "Energy", "IT0003132476"),
            ("BTP30", "BTP Italia 2030", .bond, 40, 98.40, 101.85, .eur, "Europe", "Government", "IT0005425233"),
            ("GLD", "SPDR Gold Shares", .commodity, 18, 171.20, 233.90, .usd, "Global", "Commodities", "US78463V1070"),
            ("HOME", "Apartment, Bologna", .realEstate, 1, 219_000, 268_000, .eur, "Europe", "", ""),
        ]
        for (symbol, name, type, quantity, cost, price, currency, geography, sector, isin) in investmentSpecs {
            data.investments.append(Investment(
                type: type, symbol: symbol, name: name, quantity: quantity,
                costBasis: quantity * cost, currentValue: quantity * price, currentPrice: price,
                currency: currency, geography: geography, sector: sector, isin: isin,
                fees: Decimal(rng.double(0...24)).rounded(2)))
        }

        // Crypto
        let cryptoSpecs: [(String, String, Decimal, Decimal, Decimal, String)] = [
            ("BTC", "Bitcoin", 0.4218, 31_400, 79_250, "bitcoin"),
            ("ETH", "Ethereum", 5.75, 1_870, 3_640, "ethereum"),
            ("SOL", "Solana", 42.5, 96.40, 184.20, "solana"),
            ("DOT", "Polkadot", 310, 7.85, 5.12, "polkadot"),
        ]
        for (symbol, name, quantity, avg, price, coinId) in cryptoSpecs {
            data.crypto.append(CryptoHolding(
                symbol: symbol, name: name, quantity: quantity, avgBuyPrice: avg,
                currentPrice: price, currency: .usd,
                fees: Decimal(rng.double(0...40)).rounded(2), coinId: coinId))
        }

        // Liabilities
        data.liabilities = [
            Liability(name: "Mortgage", currentBalance: 148_500, currency: .eur),
            Liability(name: "Car loan", currentBalance: 7_240, currency: .eur),
            Liability(name: "Credit card", currentBalance: 980, currency: .usd),
        ]

        // Daily net-worth snapshots for ~2 years, so the history chart and the month-end table
        // both have real shape (and the table proves it samples rather than printing 700 rows).
        // Drift is tuned so the series lands close to the net worth implied by the holdings above.
        // Otherwise `snapshotsForChart` — which appends *live* net worth as the final point —
        // draws a cliff at the right edge, which looks like a renderer bug but is only a fixture
        // inconsistency that real data would not have.
        var netWorth: Decimal = 150_000
        for dayOffset in stride(from: 730, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            netWorth += Decimal(rng.double(-900...1_230)).rounded(2)
            let liabilities: Decimal = 156_720
            data.snapshots.append(NetWorthSnapshot(
                date: date,
                totalAssets: netWorth + liabilities,
                totalLiabilities: liabilities,
                netWorth: netWorth,
                liquidity: netWorth * 0.18,
                investments: netWorth * 0.62,
                crypto: netWorth * 0.20,
                currency: .eur))
        }

        return data
    }

    static var rateSnapshot: ExchangeRateSnapshot {
        ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: ["USD": 1.0842, "GBP": 0.8461, "CHF": 0.9317],
            effectiveDate: now.addingTimeInterval(-3_600 * 5),
            fetchedAt: now.addingTimeInterval(-3_600 * 5),
            provider: "Frankfurter")
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}

// MARK: - Harness

/// Reference box for the total page count reported by the `@Sendable` progress callback.
final class PageCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var total: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func record(_ total: Int) {
        lock.lock(); defer { lock.unlock() }
        value = total
    }
}

@main
enum RenderSampleReport {
    static func main() {
        let arguments = CommandLine.arguments
        let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "./samples")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let data = SampleData.build()
        let brandMark = loadBrandMark()

        func context(locale: Locale,
                     language: String?,
                     direction: ReportLayoutDirection,
                     paper: ReportPaper) -> ReportBuildContext {
            ReportBuildContext(
                data: data,
                converter: CurrencyConverter(snapshot: SampleData.rateSnapshot),
                baseCurrency: .eur,
                exchangeRateSnapshot: SampleData.rateSnapshot,
                appLanguage: language,
                locale: locale,
                calendar: SampleData.calendar,
                now: SampleData.now,
                appVersion: "1.1.3",
                appBuild: "sample",
                platformName: "macOS (sample harness)",
                brandMarkPNG: brandMark,
                paper: paper,
                direction: direction)
        }

        struct Variant {
            var name: String
            var options: ReportExportOptions
            var context: ReportBuildContext
        }

        let italian = Locale(identifier: "it_IT")
        let arabic = Locale(identifier: "ar_SA")
        let american = Locale(identifier: "en_US")

        let variants: [Variant] = [
            Variant(name: "full-report",
                    options: ReportExportOptions(format: .pdf),
                    context: context(locale: italian, language: nil, direction: .leftToRight, paper: .a4)),
            Variant(name: "crypto-only",
                    options: ReportExportOptions(format: .pdf, sections: [.crypto]),
                    context: context(locale: italian, language: nil, direction: .leftToRight, paper: .a4)),
            Variant(name: "cashflow-last-12-months",
                    options: ReportExportOptions(format: .pdf, sections: [.cashFlow], dateRange: .last12Months),
                    context: context(locale: italian, language: nil, direction: .leftToRight, paper: .a4)),
            Variant(name: "full-report-rtl",
                    options: ReportExportOptions(format: .pdf),
                    context: context(locale: arabic, language: "ar", direction: .rightToLeft, paper: .a4)),
            Variant(name: "full-report-letter",
                    options: ReportExportOptions(format: .pdf),
                    context: context(locale: american, language: "en", direction: .leftToRight, paper: .usLetter)),
            Variant(name: "empty-database",
                    options: ReportExportOptions(format: .pdf),
                    context: ReportBuildContext(
                        data: FinancialData(),
                        converter: CurrencyConverter(snapshot: nil),
                        baseCurrency: .eur,
                        exchangeRateSnapshot: nil,
                        appLanguage: nil,
                        locale: american,
                        calendar: SampleData.calendar,
                        now: SampleData.now,
                        appVersion: "1.1.3",
                        appBuild: "sample",
                        platformName: "macOS (sample harness)",
                        brandMarkPNG: brandMark,
                        paper: .a4,
                        direction: .leftToRight)),
        ]

        var failures = 0
        for variant in variants {
            let url = outputDirectory.appendingPathComponent("\(variant.name).pdf")
            let start = Date()
            let document = ReportDocumentBuilder(context: variant.context, options: variant.options).build()
            // The progress callback is @Sendable, so accumulate through a lock-free box rather
            // than capturing a mutable local (an error under the Swift 6 language mode).
            let pageCounter = PageCounter()
            do {
                try PDFReportRenderer.render(document: document, to: url) { _, total in
                    pageCounter.record(total)
                }
                let elapsed = Date().timeIntervalSince(start)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                // Read the real page count back rather than reusing the progress total, which also
                // counts the finalisation (outline + metadata) step.
                let pages = PDFDocument(url: url)?.pageCount ?? pageCounter.total
                print(String(format: "  %-26@  %3d pages  %6.0f ms  %6.1f KB",
                             variant.name as NSString, pages,
                             elapsed * 1_000, Double(bytes) / 1024))
            } catch {
                failures += 1
                print("  \(variant.name): FAILED — \(error)")
            }
        }

        print(failures == 0
              ? "\nAll \(variants.count) sample reports rendered to \(outputDirectory.path)"
              : "\n\(failures) of \(variants.count) variants FAILED")
        if failures > 0 { exit(1) }
    }

    /// Uses the real app icon so the cover in a sample matches what ships.
    private static func loadBrandMark() -> Data? {
        let candidates = [
            "Resources/iOS/Assets.xcassets/BrandMark.imageset/BrandMark.png",
            "Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
        ]
        for candidate in candidates {
            if let data = FileManager.default.contents(atPath: candidate) { return data }
        }
        return nil
    }
}
