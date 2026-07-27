import Foundation

// MARK: - Format

/// What the export sheet produces. JSON remains the round-trippable backup consumed by
/// `FinanceStore.importFile`; PDF is the human-readable report.
enum ReportExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case json

    var id: String { rawValue }
}

// MARK: - Sections

/// The user-pickable units of the report.
///
/// These deliberately mirror the app's own navigation (Dashboard / Cash Flow / Investments /
/// Crypto) rather than the shape of `FinancialData`, because that is the structure the user
/// already has in their head. Liabilities and net-worth history are edited on the dashboard and
/// recurring rules inside Cash Flow, so they appear as *subsections* of those two rather than as
/// peers here.
enum ReportSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case cashFlow
    case investments
    case crypto

    var id: String { rawValue }

    /// Localisation key, matching the app's existing navigation strings.
    var titleKey: String {
        switch self {
        case .overview: return "Overview"
        case .cashFlow: return "Cash Flow"
        case .investments: return "Investments"
        case .crypto: return "Crypto"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .cashFlow: return "arrow.left.arrow.right"
        case .investments: return "chart.line.uptrend.xyaxis"
        case .crypto: return "bitcoinsign.circle"
        }
    }

    /// Stable PDF link-destination / outline anchor.
    var anchor: String { "section-\(rawValue)" }
}

// MARK: - Date range

/// Ledger coverage. Holdings are point-in-time and always reported in full; this bounds the
/// transaction ledger only.
enum ReportDateRange: Equatable, Sendable {
    case allTime
    case thisYear
    case last12Months
    case custom(start: Date, end: Date)

    /// Presets offered in the export sheet. `.custom` is added by the UI with live dates.
    static var presets: [ReportDateRange] { [.allTime, .thisYear, .last12Months] }

    var titleKey: String {
        switch self {
        case .allTime: return "All Time"
        case .thisYear: return "This Year"
        case .last12Months: return "Last 12 Months"
        case .custom: return "Custom Range"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// Resolves to a concrete closed interval, or nil for `.allTime`.
    ///
    /// The end is clamped to the end of its day so a transaction dated "today" is included
    /// regardless of the time component the user's entry carried.
    func resolve(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .allTime:
            return nil

        case .thisYear:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            return DateInterval(start: startOfYear, end: Self.endOfDay(now, calendar: calendar))

        case .last12Months:
            let start = calendar.date(byAdding: .month, value: -12, to: calendar.startOfDay(for: now))
                ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: Self.endOfDay(now, calendar: calendar))

        case let .custom(start, end):
            // Guard against an inverted range: the UI allows two independent date pickers, and a
            // start after the end would otherwise produce a DateInterval precondition failure.
            let lower = min(start, end)
            let upper = max(start, end)
            return DateInterval(start: calendar.startOfDay(for: lower),
                                end: Self.endOfDay(upper, calendar: calendar))
        }
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        return startOfNextDay.map { $0.addingTimeInterval(-1) } ?? date
    }
}

// MARK: - Options

/// Everything the export sheet collects. Pure value type so it can be handed straight to the
/// off-main-actor builder.
struct ReportExportOptions: Equatable, Sendable {
    var format: ReportExportFormat = .pdf
    var sections: Set<ReportSection> = Set(ReportSection.allCases)
    var dateRange: ReportDateRange = .allTime

    init(format: ReportExportFormat = .pdf,
         sections: Set<ReportSection> = Set(ReportSection.allCases),
         dateRange: ReportDateRange = .allTime) {
        self.format = format
        self.sections = sections
        self.dateRange = dateRange
    }

    var isFullReport: Bool { sections.count == ReportSection.allCases.count }

    /// Selected sections in canonical order — never the arbitrary order of a `Set`.
    var orderedSections: [ReportSection] {
        ReportSection.allCases.filter { sections.contains($0) }
    }

    /// The sheet's Export button is disabled when a PDF has no sections selected. JSON ignores
    /// the section picker entirely: it is a whole-database backup, and a partial one would
    /// silently break the restore contract in `FinanceStore.importFile`.
    var isValid: Bool {
        format == .json || !sections.isEmpty
    }

    /// Filename stem, following the existing `wealth-compass-backup-YYYY-MM-DD.json` convention.
    /// A single-section PDF is named for that section so a folder of exports stays legible.
    func fileName(date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: date)

        switch format {
        case .json:
            return "wealth-compass-backup-\(stamp).json"
        case .pdf:
            let selected = orderedSections
            let scope = selected.count == 1 ? selected[0].rawValue.lowercasedKebab : "report"
            return "wealth-compass-\(scope)-\(stamp).pdf"
        }
    }
}

private extension String {
    /// `cashFlow` → `cash-flow`. Keeps single-section filenames consistent with the
    /// hyphenated convention rather than leaking camelCase raw values.
    var lowercasedKebab: String {
        var output = ""
        for character in self {
            if character.isUppercase {
                output.append("-")
                output.append(Character(character.lowercased()))
            } else {
                output.append(character)
            }
        }
        return output
    }
}
