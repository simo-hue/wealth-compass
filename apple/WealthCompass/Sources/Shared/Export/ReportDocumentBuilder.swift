import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform bridge

/// The two things the report needs from the host platform. Kept here rather than in the renderer
/// so `PDFReportRenderer` stays free of UIKit/AppKit and remains runnable in the sample harness.
enum ReportPlatform {
    /// PNG bytes for the cover mark.
    ///
    /// Read from a dedicated `BrandMark` image set rather than `AppIcon`: on iOS the app icon is
    /// not reliably addressable through `UIImage(named:)` at runtime, and the raw icon carries
    /// opaque square corners plus a 1024px payload that dominated the exported file size.
    static func brandMarkPNG() -> Data? {
        #if canImport(UIKit)
        return UIImage(named: "BrandMark")?.pngData()
        #elseif canImport(AppKit)
        guard
            let image = NSImage(named: "BrandMark"),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    static var name: String {
        #if os(macOS)
        return "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        #elseif os(iOS)
        return UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}

// MARK: - Build context

/// Everything the builder needs, snapshotted from the `@MainActor` stores so the build can run on
/// a detached task. Mirrors what `FinanceStore.exportBackupURL` already does with `data`.
struct ReportBuildContext: Sendable {
    var data: FinancialData
    var converter: CurrencyConverter
    var baseCurrency: Currency
    var exchangeRateSnapshot: ExchangeRateSnapshot?
    var appLanguage: String?
    var locale: Locale
    var calendar: Calendar
    var now: Date
    var appVersion: String
    var appBuild: String
    var platformName: String
    /// PNG bytes for the cover mark, read from the asset catalogue on the main actor.
    var brandMarkPNG: Data?
    var paper: ReportPaper
    var direction: ReportLayoutDirection
}

// MARK: - Builder

/// Turns a `FinancialData` snapshot into a fully formatted `ReportDocument`.
///
/// This is the only layer that knows about money, currencies, locales or `AnalyticsEngine`: by the
/// time a `ReportBlock` leaves here, every figure is a finished `String`. That is what lets the
/// renderer stay free of app types and remain runnable outside Xcode.
///
/// Three reconciliation hazards are handled explicitly rather than left for the reader to trip on,
/// because a financial document whose figures silently disagree is worse than no document:
///
/// 1. `AnalyticsEngine.calculateTotals()` excludes **future-dated** transactions from cash. Those
///    rows are still printed (the user entered them, and the brief was "everything"), but marked
///    and held out of the running balance and subtotals, with a note saying so.
/// 2. A **date-filtered** ledger can never sum to the cash figure, which is an all-time running
///    total. So the ledger opens with an explicit opening balance and closes with a closing
///    balance that ties back to it.
/// 3. `assetAllocation()` **clamps negative cash** out of the ring, so the donut does not total to
///    net worth. The app already footnotes this on both dashboards
///    (`FinanceStore.assetAllocationExcludedCash`); the same footnote is reproduced here.
struct ReportDocumentBuilder {
    let context: ReportBuildContext
    let options: ReportExportOptions

    private var calendar: Calendar { context.calendar }

    private var analytics: AnalyticsEngine {
        AnalyticsEngine(data: context.data,
                        converter: context.converter,
                        displayCurrency: context.baseCurrency,
                        appLanguage: context.appLanguage,
                        calendar: context.calendar,
                        now: context.now)
    }

    /// An engine over **settled** transactions only — future-dated rows removed.
    ///
    /// Kept, but no longer load-bearing: `AnalyticsEngine` now excludes future-dated rows from
    /// `monthlyCashFlow` and `cashFlowTrend` itself, so this filters an already-filtered set. It was
    /// written because those two counted a scheduled invoice that the ledger directly below printed
    /// in grey and excluded from every balance — a document contradicting itself on one page. The
    /// app had the same contradiction on screen; fixing it centrally is what made this redundant.
    private var settledAnalytics: AnalyticsEngine {
        var settled = context.data
        settled.transactions = settled.transactions.filter { !isFutureDated($0) }
        return AnalyticsEngine(data: settled,
                               converter: context.converter,
                               displayCurrency: context.baseCurrency,
                               appLanguage: context.appLanguage,
                               calendar: context.calendar,
                               now: context.now)
    }

    /// Minor-unit digits of the base currency (2 for EUR, 0 for JPY/KRW/ISK/HUF).
    private var currencyScale: Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = context.baseCurrency.rawValue
        formatter.locale = context.locale
        return formatter.maximumFractionDigits
    }

    /// Rounds to the base currency's minor unit.
    ///
    /// Every figure that is *accumulated* must be rounded at the point of conversion, not only when
    /// printed. Converting 1000 USD at 1.0842 yields 922.33905…; summing the unrounded values and
    /// rounding only at print time produced a statement whose own columns did not add up — printed
    /// opening + income + expenses missing printed closing by a cent, and a running balance that
    /// drifted against the amounts beside it. Rounding on the way in makes the arithmetic the
    /// reader can do by hand the same arithmetic the report did.
    private func roundedMoney(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, currencyScale, .plain)
        return output
    }

    /// Base-currency value of a single record, rounded to the minor unit.
    ///
    /// Every per-record conversion in the report goes through here, and every total is a sum of
    /// these — never a sum of unrounded conversions rounded at the end. Mixing the two is what
    /// makes a statement's own columns disagree by a cent.
    private func recordValue(_ value: Decimal, _ currency: Currency?) -> Decimal {
        roundedMoney(context.converter.convert(value, from: currency, to: context.baseCurrency))
    }

    /// Totals computed the way this document prints them.
    ///
    /// Deliberately not `AnalyticsEngine.calculateTotals()`, which sums unrounded conversions and
    /// rounds once at display time. Both are defensible in isolation, but mixing them put the
    /// Overview "Cash" tile a cent away from the Cash Flow closing balance in the same PDF. The
    /// report is read on its own, so internal agreement wins; against the app's screen this can
    /// differ by at most a rounding unit per record, and only with foreign-currency holdings.
    private var reportTotals: FinanceTotals {
        let liquidity = context.data.transactions
            .filter { !isFutureDated($0) }
            .reduce(Decimal(0)) { $0 + signedAmount($1) }
        let investments = context.data.investments
            .reduce(Decimal(0)) { $0 + recordValue($1.currentValue, $1.currency) }
        let crypto = context.data.crypto
            .reduce(Decimal(0)) { $0 + recordValue($1.currentValue, $1.currency) }
        let liabilities = context.data.liabilities
            .reduce(Decimal(0)) { $0 + recordValue($1.currentBalance, $1.currency) }
        let assets = liquidity + investments + crypto
        return FinanceTotals(totalLiquidity: liquidity,
                             totalInvestments: investments,
                             totalCrypto: crypto,
                             totalAssets: assets,
                             totalLiabilities: liabilities,
                             netWorth: assets - liabilities)
    }

    /// Caps a ring at `limit` wedges, aggregating the tail into a single "Other" slice.
    ///
    /// The palette holds eight categorical colours, so a ninth slice silently reuses the first —
    /// the sample report's ten-category expense ring already had two indistinguishable pairs.
    /// Aggregating is also more honest than a legend that hides rows the ring still draws.
    private func cappedSlices(_ slices: [ReportSlice], limit: Int = 7) -> [ReportSlice] {
        guard slices.count > limit else { return slices }
        let ranked = slices.sorted { $0.value > $1.value }
        let head = Array(ranked.prefix(limit))
        let tailValue = ranked.dropFirst(limit).reduce(0.0) { $0 + $1.value }
        guard tailValue > 0 else { return head }
        return head + [ReportSlice(label: L("Other"),
                                   value: tailValue,
                                   formattedValue: money(tailValue))]
    }

    init(context: ReportBuildContext, options: ReportExportOptions) {
        self.context = context
        self.options = options
    }

    // MARK: Localisation

    private func L(_ key: String) -> String {
        AppLocalization.string(String.LocalizationValue(key), appLanguage: context.appLanguage)
    }

    /// For strings that carry a value into the lookup, so the catalog can vary on it.
    ///
    /// `L(_:)` builds its `String.LocalizationValue` from a runtime `String`, which is a key and
    /// nothing else: the resolved value comes back with the specifier still in it and any argument
    /// has to be substituted afterwards with `String(format:)`. A `variations.plural` entry can
    /// never fire that way, because the plural category is chosen during the lookup from arguments
    /// the lookup never received. Interpolating into the `LocalizationValue` — the same shape as
    /// `settings.localized("\(count) due transactions were added to Cash Flow.")` — passes the
    /// count through, so CLDR picks the form.
    private func localized(_ key: String.LocalizationValue) -> String {
        AppLocalization.string(key, appLanguage: context.appLanguage)
    }

    // MARK: - Formatting

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: context.baseCurrency.rawValue).locale(context.locale))
    }

    private func money(_ value: Double) -> String {
        money(Decimal(finite: value) ?? 0)
    }

    private func convertedMoney(_ value: Decimal, from currency: Currency?) -> String {
        money(context.converter.convert(value, from: currency, to: context.baseCurrency))
    }

    /// Formats an amount in **its own** currency, matching the app's per-row convention
    /// (`AppSettings.formatSourceCurrency`) so a USD holding reads "$100" rather than "€100".
    private func sourceMoney(_ value: Decimal, _ currency: Currency) -> String {
        value.formatted(.currency(code: currency.rawValue).locale(context.locale))
    }

    private func quantity(_ value: Decimal, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(context.locale))
    }

    /// An entity count — how many holdings, how many transactions — grouped for the reader.
    ///
    /// The in-app twin is `AppSettings.privateCount(_:)`, which this deliberately does not call: it
    /// redacts under Privacy Mode, and the export redacts nothing by design (`ExportOptionsView`
    /// warns before the user commits). What carries over is only the formatting half.
    ///
    /// Every one of the eight call sites used to interpolate the `Int` straight into a `String`,
    /// which is `String(describing:)` and groups nothing, so the appendix printed `1234` in all 35
    /// languages. `.locale(context.locale)` rather than the ambient one for the same reason every
    /// other formatter here takes it: the document is built on a detached task, and its locale is
    /// the reader's in-app language, not the process's.
    private func count(_ value: Int) -> String {
        value.formatted(.number.locale(context.locale))
    }

    /// One decimal place: two makes a gain percentage overflow its column in the holdings tables,
    /// and no reader of a personal net-worth report needs basis-point precision on it.
    private func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        // The sign stays a prefix: a report reader needs the direction, and `.percent` has no
        // "always show sign" option that also respects sign placement per locale.
        let sign = value > 0 ? "+" : ""
        return sign + formattedPercent(value, locale: context.locale)
    }

    private func dateString(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(context.locale))
    }

    private func dateTimeString(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(context.locale))
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(context.locale))
    }

    /// Compact axis labels ("12.3k", "1.2M") so a y-axis does not consume a third of the plot.
    ///
    /// `.compactName` rather than hand-built suffixes. The thresholds and the letters were English
    /// literals — `B`, `M`, `k`, plus an ASCII hyphen for the sign where `money()` two lines away
    /// emits the locale's own minus — so every axis in the report read in English regardless of the
    /// language: German wants "Mio.", Russian "млн", and Japanese groups by 万/億 rather than by
    /// thousands at all, so no threshold table could have been right for it.
    private func axisLabel(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value.formatted(
            .number.notation(.compactName)
                .precision(.fractionLength(0...1))
                .locale(context.locale)
        )
    }

    // MARK: - Entry point

    func build() -> ReportDocument {
        var sections: [ReportSectionContent] = []
        for section in options.orderedSections {
            switch section {
            case .overview: sections.append(buildOverview())
            case .cashFlow: sections.append(buildCashFlow())
            case .investments: sections.append(buildInvestments())
            case .crypto: sections.append(buildCrypto())
            }
        }
        // The appendix is unconditional: even a two-page crypto export converted its holdings at
        // some exchange rate, and without the rate disclosure the figures are not reproducible.
        sections.append(buildAppendix())

        return ReportDocument(metadata: buildMetadata(),
                              chrome: buildChrome(),
                              sections: sections,
                              theme: ReportTheme(paper: context.paper, direction: context.direction))
    }

    private func buildChrome() -> ReportChrome {
        ReportChrome(contentsTitle: L("Contents"),
                     pageFormat: L("Page %1$@ of %2$@"),
                     continuedSuffix: L("(continued)"),
                     noEntries: L("No entries recorded."),
                     legendOverflowFormat: L("+ %lld more"),
                     locale: context.locale,
                     periodLabel: L("Period"),
                     baseCurrencyLabel: L("Base Currency"),
                     generatedLabel: L("Generated"),
                     coverDisclaimer: L("Prepared from data entered by the account holder. Market values reflect the most recent prices retrieved by the app and are not independently verified. This document is a personal record, not financial advice or a statement from a regulated institution."))
    }

    private func buildMetadata() -> ReportMetadata {
        let scope = options.isFullReport
            ? L("Full Report")
            : options.orderedSections.map { L($0.titleKey) }.joined(separator: " · ")

        var period: String?
        if let interval = options.dateRange.resolve(now: context.now, calendar: calendar) {
            period = "\(dateString(interval.start)) – \(dateString(interval.end))"
        }

        return ReportMetadata(
            brandName: L("Wealth Compass"),
            documentTitle: L("Financial Report"),
            scopeLine: scope,
            periodLine: period,
            baseCurrencyLine: "\(context.baseCurrency.rawValue) (\(context.baseCurrency.symbol))",
            generatedLine: dateTimeString(context.now),
            footerNote: L("Wealth Compass") + " · " + dateString(context.now),
            appVersion: "\(context.appVersion) (\(context.appBuild))",
            brandMarkPNG: context.brandMarkPNG)
    }

    // MARK: - Ledger windowing

    /// Transactions inside the selected range, oldest first — the order a running balance needs.
    private var rangedTransactions: [Transaction] {
        let sorted = context.data.transactions.sorted { $0.date < $1.date }
        guard let interval = options.dateRange.resolve(now: context.now, calendar: calendar) else {
            return sorted
        }
        return sorted.filter { $0.date >= interval.start && $0.date <= interval.end }
    }

    /// Whole months an interval touches, inclusive of both endpoints — a 1 Jan – 31 Mar range is
    /// three bars, not two.
    ///
    /// Deliberately **uncapped**. An earlier version clamped this to twelve for readability, which
    /// silently dropped data: `.last12Months` spans thirteen calendar months, so the earliest month
    /// lost its bar while its subtotal still printed in the ledger below and its rows still fed Net
    /// Savings, Money Flow and Total Expenses. A 2023–2024 export charted only 2024 against figures
    /// covering both years, with nothing saying so. A dense chart is a worse-looking document; a
    /// chart that disagrees with the table beneath it is a wrong one.
    private func monthsSpanned(_ interval: DateInterval) -> Int {
        let start = calendar.dateComponents([.year, .month], from: interval.start)
        let end = calendar.dateComponents([.year, .month], from: interval.end)
        guard let months = calendar.dateComponents(
            [.month],
            from: calendar.date(from: start) ?? interval.start,
            to: calendar.date(from: end) ?? interval.end
        ).month else {
            return 1
        }
        return max(months + 1, 1)
    }

    /// Cash contribution of a transaction, in base currency and signed by type.
    ///
    /// Rounded to the currency's minor unit *here*, so that everything accumulated downstream
    /// (running balance, month subtotals, income/expense totals, closing balance) agrees with the
    /// per-row amounts printed beside it. See `roundedMoney`.
    private func signedAmount(_ transaction: Transaction) -> Decimal {
        let converted = roundedMoney(context.converter.convert(
            transaction.amount,
            from: transaction.currency ?? context.baseCurrency,
            to: context.baseCurrency))
        return transaction.type == .income ? converted : -converted
    }

    /// Matches `AnalyticsEngine.calculateTotals()`, which holds future-dated rows out of cash.
    private func isFutureDated(_ transaction: Transaction) -> Bool {
        calendar.startOfDay(for: transaction.date) > calendar.startOfDay(for: context.now)
    }

    /// Cash balance accumulated *before* the range opens — the ledger's opening balance.
    private func openingBalance(before start: Date?) -> Decimal {
        guard let start else { return 0 }
        return context.data.transactions
            .filter { $0.date < start && !isFutureDated($0) }
            .reduce(Decimal(0)) { $0 + signedAmount($1) }
    }

    // MARK: - Overview

    private func buildOverview() -> ReportSectionContent {
        let engine = analytics
        let totals = reportTotals
        var blocks: [ReportBlock] = [
            .sectionTitle(L("Overview"), subtitle: L("Net worth, asset allocation and liabilities")),
            .kpis([
                ReportKPI(label: L("Net Worth"), value: money(totals.netWorth), emphasis: .headline),
                ReportKPI(label: L("Total Assets"), value: money(totals.totalAssets)),
                ReportKPI(label: L("Total Liabilities"), value: money(totals.totalLiabilities),
                          emphasis: totals.totalLiabilities > 0 ? .negative : .neutral),
                ReportKPI(label: L("Cash"), value: money(totals.totalLiquidity),
                          emphasis: totals.totalLiquidity < 0 ? .negative : .neutral),
                ReportKPI(label: L("Investments"), value: money(totals.totalInvestments)),
                ReportKPI(label: L("Crypto"), value: money(totals.totalCrypto)),
            ]),
        ]

        // Asset allocation
        // Built from `reportTotals` rather than `engine.assetAllocation()` so the ring, its centre
        // figure and the KPI tiles above it are all the same numbers. Negative cash is clamped out
        // exactly as the app's ring does, and the footnote below still explains the resulting gap.
        let allocation = [
            (L("Investments"), totals.totalInvestments),
            (L("Crypto"), totals.totalCrypto),
            (L("Cash"), totals.totalLiquidity),
        ].filter { $0.1 > 0 }
        if !allocation.isEmpty {
            blocks.append(.subheading(L("Asset Allocation"), anchor: nil))
            // The centre figure is the sum of the wedges actually drawn, not `totalAssets`.
            // `assetAllocation()` clamps a net-negative cash wedge out of the ring, so quoting
            // total assets in the middle of a ring that does not contain it made the chart
            // contradict itself. The footnote below still explains the gap to net worth.
            let ringTotal = allocation.reduce(Decimal(0)) { $0 + $1.1 }
            blocks.append(.chart(.donut(
                slices: cappedSlices(allocation.map {
                    ReportSlice(label: $0.0, value: $0.1.doubleValue, formattedValue: money($0.1))
                }),
                // Labelled for what the centre figure *is*. It was "Total Assets" while carrying
                // `ringTotal`, which the comment above deliberately makes a different quantity
                // whenever cash is net-negative — so the tile above and the ring below printed two
                // different numbers under the same name, on one page.
                centerLabel: L("Allocated"),
                centerValue: money(ringTotal))))

            // Reproduces the dashboards' existing footnote: a ring cannot render a negative wedge,
            // so net-negative cash is clamped out and the ring's total exceeds signed net worth.
            if totals.totalLiquidity < 0 {
                blocks.append(.note(String(
                    format: L("Net cash liabilities of %@ are excluded from the allocation ring, because a ring cannot show a negative share. Net worth above accounts for them in full."),
                    money(-totals.totalLiquidity))))
            }
        }

        // Net worth history
        // `snapshotsForChart` synthesises a point from *live* net worth even with no history, so an
        // empty database would otherwise get a meaningless flat line at zero. Gate on the stored
        // snapshots instead.
        let points = context.data.snapshots.isEmpty
            ? []
            : engine.snapshotsForChart(range: .all, currentNetWorth: totals.netWorth.doubleValue)
        if !points.isEmpty {
            blocks.append(.subheading(L("Net Worth History"), anchor: "overview-history"))
            blocks.append(.chart(.area(
                points: points.map { ReportLinePoint(date: $0.date, value: $0.value) },
                axisFormatter: { [self] in axisLabel($0) },
                dateFormatter: { [self] in
                    $0.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(context.locale))
                })))

            // Month-end sampling: the store keeps one snapshot per calendar day with carry-forward
            // backfill, so a three-year history is ~1,100 rows. Nobody reads that as a table.
            let monthly = monthEndSnapshots()
            if !monthly.isEmpty {
                blocks.append(.table(ReportTable(
                    columns: [
                        ReportColumn(L("Month"), weight: 1.4),
                        ReportColumn(L("Assets"), weight: 1.2, alignment: .trailing, isNumeric: true),
                        ReportColumn(L("Liabilities"), weight: 1.2, alignment: .trailing, isNumeric: true),
                        ReportColumn(L("Net Worth"), weight: 1.2, alignment: .trailing, isNumeric: true),
                    ],
                    rows: monthly.map { snapshot in
                        ReportRow([
                            monthLabel(snapshot.date),
                            money(recordValue(snapshot.totalAssets, snapshot.currency)),
                            money(recordValue(snapshot.totalLiabilities, snapshot.currency)),
                            money(recordValue(snapshot.netWorth, snapshot.currency)),
                        ])
                    },
                    caption: L("Month-end net worth"))))
                blocks.append(.note(L("Sampled at each month end from the app's daily snapshot history.")))
            }
        }

        // Liabilities
        blocks.append(.subheading(L("Liabilities"), anchor: "overview-liabilities"))
        let liabilities = context.data.liabilities.sorted {
            recordValue($0.currentBalance, $0.currency) > recordValue($1.currentBalance, $1.currency)
        }
        blocks.append(.table(ReportTable(
            columns: [
                ReportColumn(L("Name"), weight: 2.6),
                ReportColumn(L("Currency"), weight: 0.9, alignment: .center),
                ReportColumn(L("Balance"), weight: 1.4, alignment: .trailing, isNumeric: true),
                ReportColumn(L("In %@").replacingOccurrences(of: "%@", with: context.baseCurrency.rawValue),
                             weight: 1.4, alignment: .trailing, isNumeric: true),
            ],
            rows: liabilities.map { liability in
                ReportRow([
                    liability.name,
                    liability.currency.rawValue,
                    sourceMoney(liability.currentBalance, liability.currency),
                    money(recordValue(liability.currentBalance, liability.currency)),
                ])
            },
            footer: liabilities.isEmpty ? nil : ReportRow([
                L("Total"), "", "", money(totals.totalLiabilities),
            ], style: .subtotal))))

        return ReportSectionContent(anchor: ReportSection.overview.anchor,
                                    title: L("Overview"),
                                    blocks: blocks)
    }

    /// One snapshot per calendar month (the latest in each), newest last.
    private func monthEndSnapshots() -> [NetWorthSnapshot] {
        var byMonth: [Date: NetWorthSnapshot] = [:]
        for snapshot in context.data.snapshots {
            let components = calendar.dateComponents([.year, .month], from: snapshot.date)
            guard let key = calendar.date(from: components) else { continue }
            if let existing = byMonth[key], existing.date >= snapshot.date { continue }
            byMonth[key] = snapshot
        }
        return byMonth.values.sorted { $0.date < $1.date }
    }

    // MARK: - Cash Flow

    private func buildCashFlow() -> ReportSectionContent {
        // Nothing in this section counts a future-dated row that the ledger below it prints in grey
        // and excludes — but the three blocks reach that guarantee by different routes, because
        // only the Money Flow block can use one engine for both the bounded and unbounded cases.
        // `engine` serves the *unbounded* KPI row and trend, plus the Money Flow block either way;
        // a bounded export sums `settledRanged` inline for its KPI and re-anchors a fresh engine
        // for its trend. `settledRanged` and that engine's data are both pre-filtered by
        // `isFutureDated`, so the exclusion holds on every path.
        let engine = settledAnalytics
        let interval = options.dateRange.resolve(now: context.now, calendar: calendar)
        let settledRanged = rangedTransactions.filter { !isFutureDated($0) }

        // The KPIs and the trend cover the period the cover page states.
        //
        // They used to read `monthlyCashFlow(for: context.now)` and `cashFlowTrend(months: 12)` —
        // both anchored to *today* — so a report exported for 1 Jan – 31 Dec 2024 printed August
        // 2026 KPI figures and twelve 2025-26 bars, under a cover page stating the 2024 period, and
        // labelled them "This Month". The Money Flow and category blocks below were moved off their
        // own windows for exactly this reason; these two were missed.
        // What this row can say depends on whether the export is bounded.
        //
        // Unbounded, the current month is a useful at-a-glance figure and "This Month" is accurate.
        // Bounded, it is not: this used to print August 2026 figures under a cover page stating a
        // 2024 period. But recomputing it over the range would only restate the ledger's own
        // Opening/Income/Expenses/Closing row further down — same numbers, same labels, twice on one
        // page. So a bounded export keeps only the figure the ledger row does *not* carry: net
        // savings and its rate, over the stated period.
        let kpis: [ReportKPI]
        if interval != nil {
            // `signedAmount` so this accumulates from the same rounded per-row values the ledger
            // prints, per `roundedMoney`.
            let income = settledRanged.filter { $0.type == .income }
                .reduce(Decimal(0)) { $0 + signedAmount($1) }
            let expenses = settledRanged.filter { $0.type == .expense }
                .reduce(Decimal(0)) { $0 - signedAmount($1) }
            let flow = MonthlyCashFlow(monthlyIncome: income, monthlyExpenses: expenses)
            kpis = [
                ReportKPI(label: L("Net Savings"), value: money(flow.netSavings),
                          detail: percent(flow.savingsRate) + " " + L("savings rate"),
                          emphasis: flow.netSavings >= 0 ? .positive : .negative),
            ]
        } else {
            let flow = engine.monthlyCashFlow(for: context.now)
            kpis = [
                ReportKPI(label: L("Income This Month"), value: money(flow.monthlyIncome), emphasis: .positive),
                ReportKPI(label: L("Expenses This Month"), value: money(flow.monthlyExpenses), emphasis: .negative),
                ReportKPI(label: L("Net Savings"), value: money(flow.netSavings),
                          detail: percent(flow.savingsRate) + " " + L("savings rate"),
                          emphasis: flow.netSavings >= 0 ? .positive : .negative),
            ]
        }

        var blocks: [ReportBlock] = [
            .sectionTitle(L("Cash Flow"), subtitle: L("Income, expenses, recurring commitments and the full transaction ledger")),
            .kpis(kpis),
        ]

        // Trend. For a bounded export the bars end at the range's own end and span only its months,
        // built over the ranged rows — `cashFlowTrend` counts back from its engine's `now`, so
        // reusing the tested method with a re-anchored engine is what keeps the chart inside the
        // stated period instead of walking back from today.
        let trend: [CashFlowMonth]
        if let interval {
            let trendEngine = AnalyticsEngine(
                data: FinancialData(transactions: settledRanged),
                converter: context.converter,
                displayCurrency: context.baseCurrency,
                appLanguage: context.appLanguage,
                calendar: context.calendar,
                now: interval.end)
            trend = trendEngine.cashFlowTrend(months: monthsSpanned(interval))
        } else {
            trend = engine.cashFlowTrend(months: 12)
        }
        if !trend.isEmpty {
            blocks.append(.subheading(L("Monthly Trend"), anchor: "cashflow-trend"))
            blocks.append(.chart(.groupedBars(
                groups: trend.map { ReportBarGroup(label: $0.monthLabel, values: [$0.income, $0.expense]) },
                seriesLabels: [L("Income"), L("Expenses")],
                axisFormatter: { [self] in axisLabel($0) })))
        }

        // Money Flow. Built from the ranged ledger for the same reason the category totals below
        // are: `cashFlowSankey(period:)` would impose its own window and contradict the export
        // range. Placed ahead of the category breakdown because it frames it — the donut answers
        // "how was spending split", this answers "where did the money come from and what was left".
        // Handed rows already converted and rounded by `recordValue`, then tagged as base currency
        // so the engine's own conversion is a no-op. `sankeyCategoryTotals` sums unrounded
        // conversions, which is defensible on screen but put a different figure for the same
        // category on the ribbon and in the table below it — 200 USD rent rows at 1.0842 printed
        // €184,467.81 on the diagram and €184,466.00 in the table. `roundedMoney`'s contract is
        // that every accumulated figure rounds at the point of conversion; this is the one place in
        // the report that was bypassing it.
        let flowTransactions = rangedTransactions.filter { !isFutureDated($0) }.map { transaction -> Transaction in
            var converted = transaction
            converted.amount = recordValue(transaction.amount, transaction.currency)
            converted.currency = context.baseCurrency
            return converted
        }
        let sankey = engine.cashFlowSankey(transactions: flowTransactions)
        if !sankey.isEmpty {
            blocks.append(.subheading(L("Money Flow"), anchor: "cashflow-money-flow"))
            blocks.append(.chart(.sankey(model: sankey, amountFormatter: { [self] in money($0) })))
        }

        // Categories, computed over the *selected range* rather than via
        // `expensesByCategory(period:)`, whose own period window would contradict the export range.
        let expenses = rangedTransactions.filter { $0.type == .expense && !isFutureDated($0) }
        if !expenses.isEmpty {
            var totalsByCategory: [String: Decimal] = [:]
            for transaction in expenses {
                let amount = roundedMoney(context.converter.convert(
                    transaction.amount,
                    from: transaction.currency ?? context.baseCurrency,
                    to: context.baseCurrency))
                totalsByCategory[transaction.category, default: 0] += amount
            }
            let ranked = totalsByCategory.sorted { $0.value > $1.value }
            let grandTotal = ranked.reduce(Decimal(0)) { $0 + $1.value }

            blocks.append(.subheading(L("Expenses by Category"), anchor: "cashflow-categories"))
            blocks.append(.chart(.donut(
                slices: cappedSlices(ranked.map {
                    // Category names are catalog keys for the built-ins; a custom one falls through
                    // unchanged. Printing them raw meant the app showed "Alimentation" and the
                    // exported report showed "Food" for the same row.
                    ReportSlice(label: L($0.key), value: $0.value.doubleValue, formattedValue: money($0.value))
                }),
                centerLabel: L("Total Expenses"),
                centerValue: money(grandTotal))))
            blocks.append(.table(ReportTable(
                columns: [
                    ReportColumn(L("Category"), weight: 3),
                    ReportColumn(L("Amount"), weight: 1.4, alignment: .trailing, isNumeric: true),
                    ReportColumn(L("Share"), weight: 1, alignment: .trailing, isNumeric: true),
                ],
                rows: ranked.map { entry in
                    let share = grandTotal > 0 ? (entry.value / grandTotal).doubleValue * 100 : 0
                    return ReportRow([
                        L(entry.key),
                        money(entry.value),
                        formattedPercent(share, locale: context.locale),
                    ])
                },
                footer: ReportRow([L("Total"), money(grandTotal), formattedPercent(100, locale: context.locale)], style: .subtotal))))
        }

        // Recurring commitments
        blocks.append(.subheading(L("Recurring Commitments"), anchor: "cashflow-recurring"))
        let recurring = context.data.recurringTransactions.sorted { $0.nextDueDate < $1.nextDueDate }
        blocks.append(.table(ReportTable(
            columns: [
                ReportColumn(L("Description"), weight: 2.4),
                ReportColumn(L("Category"), weight: 1.6),
                ReportColumn(L("Frequency"), weight: 1.3),
                ReportColumn(L("Next Due"), weight: 1.3),
                ReportColumn(L("Amount"), weight: 1.4, alignment: .trailing, isNumeric: true),
            ],
            rows: recurring.map { rule in
                var flags: [String] = []
                if !rule.isActive { flags.append(L("Paused")) }
                if rule.isCompleted { flags.append(L("Completed")) }
                if let end = rule.endDate { flags.append(L("Ends") + " " + dateString(end)) }
                if !rule.notificationsEnabled { flags.append(L("Notifications off")) }
                return ReportRow([
                    rule.description,
                    rule.category,
                    rule.frequency.localizedTitle(appLanguage: context.appLanguage),
                    dateString(rule.nextDueDate),
                    (rule.type == .expense ? "−" : "+") + sourceMoney(rule.amount, rule.currency ?? context.baseCurrency),
                ], secondary: flags.isEmpty ? nil : flags.joined(separator: " · "),
                   style: rule.isActive && !rule.isCompleted ? .normal : .excluded)
            })))

        blocks.append(contentsOf: buildLedger())

        return ReportSectionContent(anchor: ReportSection.cashFlow.anchor,
                                    title: L("Cash Flow"),
                                    blocks: blocks)
    }

    /// The transaction ledger, presented as a statement rather than a list: opening balance,
    /// movement, closing balance, with a running balance down the rightmost column.
    private func buildLedger() -> [ReportBlock] {
        let transactions = rangedTransactions
        let interval = options.dateRange.resolve(now: context.now, calendar: calendar)
        var blocks: [ReportBlock] = [.subheading(L("Transaction Ledger"), anchor: "cashflow-ledger")]

        guard !transactions.isEmpty else {
            blocks.append(.table(ReportTable(columns: ledgerColumns, rows: [])))
            return blocks
        }

        let opening = openingBalance(before: interval?.start)
        let settled = transactions.filter { !isFutureDated($0) }
        let futureCount = transactions.count - settled.count
        let income = settled.filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + signedAmount($1) }
        let expenses = settled.filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + signedAmount($1) }
        let closing = opening + income + expenses

        blocks.append(.kpis([
            ReportKPI(label: L("Opening Balance"), value: money(opening)),
            ReportKPI(label: L("Income"), value: money(income), emphasis: .positive),
            ReportKPI(label: L("Expenses"), value: money(expenses), emphasis: .negative),
            ReportKPI(label: L("Closing Balance"), value: money(closing), emphasis: .headline),
        ]))

        if interval != nil {
            blocks.append(.note(L("Cash in this app is the running total of every income minus every expense, so the closing balance above is the cash figure as at the end of this period. The opening balance carries forward all activity before it.")))
        }
        if futureCount > 0 {
            // Resolved with the count inside the lookup, not substituted after it: a single ledger
            // row otherwise read "1 future-dated entries are listed in grey", and the eight
            // languages with a third and fourth plural category had no way to express theirs at all.
            blocks.append(.note(localized("\(futureCount) future-dated entries are listed in grey. They are excluded from the balances and subtotals above, matching how the app itself reports current cash.")))
        }

        // One table per calendar year, with a subtotal row closing each month. Splitting by year
        // keeps each table (and its repeated header) to a sane size and gives the contents page a
        // second-level entry the reader can actually navigate by.
        var balance = opening
        let byYear = Dictionary(grouping: transactions) { calendar.component(.year, from: $0.date) }
        for year in byYear.keys.sorted() {
            guard let yearTransactions = byYear[year] else { continue }
            blocks.append(.subheading(String(year), anchor: "ledger-\(year)"))

            var rows: [ReportRow] = []
            var monthTotal: Decimal = 0
            var currentMonth: Date?

            func closeMonth() {
                guard let month = currentMonth else { return }
                // The label sits in Description (weight 2.8), not Date (1.2). In the Date column it
                // had ~62pt for a string like "September 2024 subtotal" — 118pt at this face, and
                // more in German — so every subtotal row on every ledger table truncated while the
                // two cells beside it sat empty.
                rows.append(ReportRow([
                    "", monthLabel(month) + " " + L("subtotal"), "", money(monthTotal), "",
                ], style: .subtotal))
                monthTotal = 0
            }

            for transaction in yearTransactions.sorted(by: { $0.date < $1.date }) {
                let components = calendar.dateComponents([.year, .month], from: transaction.date)
                let month = calendar.date(from: components)
                if month != currentMonth {
                    closeMonth()
                    currentMonth = month
                }

                let future = isFutureDated(transaction)
                let signed = signedAmount(transaction)
                if !future {
                    balance += signed
                    monthTotal += signed
                }

                let recordCurrency = transaction.currency ?? context.baseCurrency
                var secondary: [String] = []
                if recordCurrency != context.baseCurrency {
                    secondary.append(sourceMoney(transaction.amount, recordCurrency))
                }
                if transaction.recurringTransactionID != nil {
                    secondary.append(L("Recurring"))
                }
                if future {
                    secondary.append(L("Future-dated — not counted in cash"))
                }

                rows.append(ReportRow([
                    dateString(transaction.date),
                    transaction.description,
                    L(transaction.category),
                    (transaction.type == .income ? "+" : "−") + money(abs(signed)),
                    future ? "—" : money(balance),
                ], secondary: secondary.isEmpty ? nil : secondary.joined(separator: " · "),
                   style: future ? .excluded : .normal))
            }
            closeMonth()

            blocks.append(.table(ReportTable(
                columns: ledgerColumns,
                rows: rows,
                caption: "\(L("Transactions")) — \(year)")))
        }

        return blocks
    }

    private var ledgerColumns: [ReportColumn] {
        [
            ReportColumn(L("Date"), weight: 1.2),
            ReportColumn(L("Description"), weight: 2.8),
            ReportColumn(L("Category"), weight: 1.6),
            ReportColumn(L("Amount"), weight: 1.4, alignment: .trailing, isNumeric: true),
            ReportColumn(L("Balance"), weight: 1.4, alignment: .trailing, isNumeric: true),
        ]
    }

    // MARK: - Investments

    private func buildInvestments() -> ReportSectionContent {
        let engine = analytics
        let holdings = context.data.investments.sorted {
            recordValue($0.currentValue, $0.currency) > recordValue($1.currentValue, $1.currency)
        }

        let totalValue = holdings.reduce(Decimal(0)) { $0 + recordValue($1.currentValue, $1.currency) }
        let totalCost = holdings.reduce(Decimal(0)) { $0 + recordValue($1.costBasis, $1.currency) }
        let totalFees = holdings.reduce(Decimal(0)) { $0 + recordValue($1.fees, $1.currency) }
        let gain = totalValue - totalCost
        let gainPercent = totalCost > 0 ? (gain / totalCost).doubleValue * 100 : 0

        var blocks: [ReportBlock] = [
            .sectionTitle(L("Investments"), subtitle: L("Holdings, allocation and performance")),
            .kpis([
                ReportKPI(label: L("Market Value"), value: money(totalValue), emphasis: .headline),
                ReportKPI(label: L("Cost Basis"), value: money(totalCost)),
                ReportKPI(label: L("Gain / Loss"), value: money(gain), detail: percent(gainPercent),
                          emphasis: gain >= 0 ? .positive : .negative),
                ReportKPI(label: L("Holdings"), value: count(holdings.count)),
                ReportKPI(label: L("Fees Paid"), value: money(totalFees)),
            ]),
        ]

        func allocationBlocks(_ title: String, _ anchor: String, _ slices: [AllocationSlice]) {
            guard !slices.isEmpty else { return }
            blocks.append(.subheading(title, anchor: anchor))
            blocks.append(.chart(.donut(
                slices: cappedSlices(slices.map {
                    ReportSlice(label: $0.name, value: $0.value, formattedValue: money($0.value))
                }),
                centerLabel: L("Market Value"),
                centerValue: money(totalValue))))
        }
        allocationBlocks(L("Allocation by Type"), "investments-type", engine.investmentTypeAllocation())
        allocationBlocks(L("Allocation by Sector"), "investments-sector", engine.investmentAllocation())
        allocationBlocks(L("Allocation by Geography"), "investments-geography", engine.investmentGeographyAllocation())

        blocks.append(.subheading(L("Holdings"), anchor: "investments-holdings"))
        blocks.append(.table(ReportTable(
            // Gain and its percentage are separate columns: packed into one they overflow the
            // cell and truncate, which is exactly the figure a reader is looking for. The "Value"
            // header is deliberately short — "Market Value" does not fit the column at 7.5pt
            // uppercase with tracking, and a truncated header is worse than a terse one.
            columns: [
                ReportColumn(L("Symbol"), weight: 0.9),
                ReportColumn(L("Name"), weight: 1.9),
                ReportColumn(L("Quantity"), weight: 1.1, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Cost Basis"), weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Value"), weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Gain / Loss"), weight: 1.25, alignment: .trailing, isNumeric: true),
                ReportColumn("%", weight: 0.85, alignment: .trailing, isNumeric: true),
            ],
            // Two-line rows: an `Investment` carries fourteen fields, which no portrait page fits
            // on one line. Money goes on the primary line; identity and classification follow
            // beneath, so nothing the user entered is dropped.
            rows: holdings.map { holding in
                var detail: [String] = []
                if !holding.isin.isEmpty { detail.append("ISIN \(holding.isin)") }
                detail.append(holding.type.localizedTitle(appLanguage: context.appLanguage))
                if !holding.sector.isEmpty { detail.append(holding.sector) }
                if !holding.geography.isEmpty { detail.append(holding.geography) }
                if holding.currency != context.baseCurrency {
                    detail.append("\(holding.currency.rawValue) @ \(sourceMoney(holding.currentPrice, holding.currency))")
                }
                if holding.fees > 0 {
                    detail.append("\(L("Fees")) \(sourceMoney(holding.fees, holding.currency))")
                }

                let value = recordValue(holding.currentValue, holding.currency)
                let cost = recordValue(holding.costBasis, holding.currency)
                return ReportRow([
                    holding.symbol,
                    holding.name,
                    quantity(holding.quantity, digits: QuantityPrecision.investment),
                    money(cost),
                    money(value),
                    money(value - cost),
                    percent(holding.gainLossPercent),
                ], secondary: detail.joined(separator: " · "))
            },
            footer: holdings.isEmpty ? nil : ReportRow([
                L("Total"), "", "", money(totalCost), money(totalValue),
                money(gain), percent(gainPercent),
            ], style: .subtotal))))

        return ReportSectionContent(anchor: ReportSection.investments.anchor,
                                    title: L("Investments"),
                                    blocks: blocks)
    }

    // MARK: - Crypto

    private func buildCrypto() -> ReportSectionContent {
        let engine = analytics
        let holdings = context.data.crypto.sorted {
            recordValue($0.currentValue, $0.currency) > recordValue($1.currentValue, $1.currency)
        }

        let totalValue = holdings.reduce(Decimal(0)) { $0 + recordValue($1.currentValue, $1.currency) }
        let totalCost = holdings.reduce(Decimal(0)) { $0 + recordValue($1.costBasis, $1.currency) }
        let totalFees = holdings.reduce(Decimal(0)) { $0 + recordValue($1.fees, $1.currency) }
        let gain = totalValue - totalCost
        let gainPercent = totalCost > 0 ? (gain / totalCost).doubleValue * 100 : 0

        var blocks: [ReportBlock] = [
            .sectionTitle(L("Crypto"), subtitle: L("Digital asset holdings and performance")),
            .kpis([
                ReportKPI(label: L("Market Value"), value: money(totalValue), emphasis: .headline),
                ReportKPI(label: L("Cost Basis"), value: money(totalCost)),
                ReportKPI(label: L("Gain / Loss"), value: money(gain), detail: percent(gainPercent),
                          emphasis: gain >= 0 ? .positive : .negative),
                ReportKPI(label: L("Holdings"), value: count(holdings.count)),
                ReportKPI(label: L("Fees Paid"), value: money(totalFees)),
            ]),
        ]

        let allocation = engine.cryptoAllocation()
        if !allocation.isEmpty {
            blocks.append(.subheading(L("Allocation"), anchor: "crypto-allocation"))
            blocks.append(.chart(.donut(
                slices: cappedSlices(allocation.map {
                    ReportSlice(label: $0.name, value: $0.value, formattedValue: money($0.value))
                }),
                centerLabel: L("Market Value"),
                centerValue: money(totalValue))))
        }

        blocks.append(.subheading(L("Holdings"), anchor: "crypto-holdings"))
        blocks.append(.table(ReportTable(
            // Quantity is wider than the investments table: crypto carries 8 decimal places
            // (`QuantityPrecision.crypto`), so "0,42180000" needs the room.
            columns: [
                ReportColumn(L("Symbol"), weight: 0.9),
                ReportColumn(L("Name"), weight: 1.6),
                ReportColumn(L("Quantity"), weight: 1.5, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Cost Basis"), weight: 1.2, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Value"), weight: 1.2, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Gain / Loss"), weight: 1.2, alignment: .trailing, isNumeric: true),
                ReportColumn("%", weight: 0.85, alignment: .trailing, isNumeric: true),
            ],
            rows: holdings.map { holding in
                var detail: [String] = []
                detail.append("\(L("Avg Buy")) \(sourceMoney(holding.avgBuyPrice, holding.currency))")
                detail.append("\(L("Price")) \(sourceMoney(holding.currentPrice, holding.currency))")
                if holding.fees > 0 {
                    detail.append("\(L("Fees")) \(sourceMoney(holding.fees, holding.currency))")
                }
                if !holding.coinId.isEmpty { detail.append(holding.coinId) }

                let value = recordValue(holding.currentValue, holding.currency)
                let cost = recordValue(holding.costBasis, holding.currency)
                return ReportRow([
                    holding.symbol.uppercased(),
                    holding.name,
                    quantity(holding.quantity, digits: QuantityPrecision.crypto),
                    money(cost),
                    money(value),
                    money(value - cost),
                    percent(holding.gainLossPercent),
                ], secondary: detail.joined(separator: " · "))
            },
            footer: holdings.isEmpty ? nil : ReportRow([
                L("Total"), "", "", money(totalCost), money(totalValue),
                money(gain), percent(gainPercent),
            ], style: .subtotal))))

        return ReportSectionContent(anchor: ReportSection.crypto.anchor,
                                    title: L("Crypto"),
                                    blocks: blocks)
    }

    // MARK: - Appendix

    private func buildAppendix() -> ReportSectionContent {
        var blocks: [ReportBlock] = [
            .sectionTitle(L("Appendix"), subtitle: L("Conversion rates, data summary and document details")),
            .subheading(L("Exchange Rates"), anchor: "appendix-rates"),
        ]

        let snapshot = context.exchangeRateSnapshot
        if let snapshot {
            blocks.append(.keyValues([
                ReportKeyValue(L("Provider"), snapshot.provider),
                ReportKeyValue(L("Effective Date"), dateString(snapshot.effectiveDate)),
                ReportKeyValue(L("Retrieved"), dateTimeString(snapshot.fetchedAt)),
                ReportKeyValue(L("Quote Base"), snapshot.baseCurrency.rawValue),
            ]))
        }

        // The table is emitted with or without a snapshot. It used to sit inside the `if let`
        // above, so the export whose figures are *least* reproducible — the offline one, converted
        // at approximate seed rates — was the only one that disclosed no rates at all: it printed
        // the "fallback rates were used" note and then left the reader with no way to check a
        // single converted figure. `unitsPerEuro(for:)` is what the conversions themselves went
        // through, so the quote base without a snapshot is EUR by construction.
        let quoteBase = snapshot?.baseCurrency ?? .eur
        blocks.append(.table(ReportTable(
            columns: [
                ReportColumn(L("Currency"), weight: 1.4),
                ReportColumn(L("Units per %@").replacingOccurrences(of: "%@", with: quoteBase.rawValue),
                             weight: 1.6, alignment: .trailing, isNumeric: true),
                ReportColumn(L("Source"), weight: 1.6),
            ],
            rows: heldCurrencies().map { currency in
                let live = snapshot?.unitsPerBaseCurrency(for: currency)
                let rate = live ?? context.converter.unitsPerEuro(for: currency)
                // The quote base converts to itself at exactly 1 — it never passes through a rate at
                // all, live or otherwise — so labelling its row "Offline fallback rate" and greying
                // it as approximate misdescribes the one figure on the table that is certain.
                let isQuoteBase = currency == quoteBase
                let source: String
                if isQuoteBase {
                    source = L("Quote Base")
                } else {
                    source = live == nil ? L("Offline fallback rate") : L("Live rate")
                }
                return ReportRow([
                    "\(currency.rawValue) (\(currency.symbol))",
                    rate.formatted(.number.precision(.fractionLength(0...6)).locale(context.locale)),
                    source,
                ], style: (live == nil && !isQuoteBase) ? .excluded : .normal)
            },
            caption: L("Rates applied to convert holdings into the base currency"))))

        if snapshot == nil {
            blocks.append(.note(L("No exchange rate snapshot had been retrieved when this report was generated. Foreign-currency amounts were converted using the app's built-in offline fallback rates, which are approximate.")))
        }
        blocks.append(.note(L("Every figure in this report is expressed in the base currency, converted at the rates above. Amounts shown in a holding's own currency are unconverted.")))

        blocks.append(.subheading(L("Data Summary"), anchor: "appendix-data"))
        blocks.append(.keyValues([
            ReportKeyValue(L("Transactions"), count(context.data.transactions.count)),
            ReportKeyValue(L("Recurring Rules"), count(context.data.recurringTransactions.count)),
            ReportKeyValue(L("Investments"), count(context.data.investments.count)),
            ReportKeyValue(L("Crypto Holdings"), count(context.data.crypto.count)),
            ReportKeyValue(L("Liabilities"), count(context.data.liabilities.count)),
            ReportKeyValue(L("Net Worth Snapshots"), count(context.data.snapshots.count)),
        ]))

        blocks.append(.subheading(L("Document"), anchor: "appendix-document"))
        blocks.append(.keyValues([
            ReportKeyValue(L("Application"), "\(L("Wealth Compass")) \(context.appVersion) (\(context.appBuild))"),
            ReportKeyValue(L("Platform"), context.platformName),
            ReportKeyValue(L("Generated"), dateTimeString(context.now)),
            ReportKeyValue(L("Scope"), options.isFullReport
                           ? L("Full Report")
                           : options.orderedSections.map { L($0.titleKey) }.joined(separator: " · ")),
        ]))
        blocks.append(.note(L("Prepared from data entered by the account holder. Market values reflect the most recent prices retrieved by the app and are not independently verified. This document is a personal record, not financial advice or a statement from a regulated institution.")))

        return ReportSectionContent(anchor: "section-appendix",
                                    title: L("Appendix"),
                                    blocks: blocks,
                                    isStructural: true)
    }

    /// Currencies actually in play, so the rate table lists what was used rather than everything
    /// the provider publishes. Mirrors `FinanceStore.heldCurrenciesUsingSeedRate`.
    private func heldCurrencies() -> [Currency] {
        var held: Set<Currency> = [context.baseCurrency]
        for investment in context.data.investments { held.insert(investment.currency) }
        for holding in context.data.crypto { held.insert(holding.currency) }
        for liability in context.data.liabilities { held.insert(liability.currency) }
        for transaction in context.data.transactions {
            if let currency = transaction.currency { held.insert(currency) }
        }
        return held.sorted { $0.rawValue < $1.rawValue }
    }
}
