import Foundation

/// Money is stored as `Decimal` (WC-A1) so that same-currency sums are exact — Swift's
/// binary `Double` made `0.1 + 0.2 == 0.30000000000000004`, which accumulated visible
/// cent errors across totals and snapshots. The migration is "deep but bounded": money
/// and quantities stay `Decimal` through storage and all summation/cost-basis/gain math,
/// and we drop to `Double` only at two boundaries —
///   1. Swift Charts plot points (CoreGraphics wants `Double`), and
///   2. inside currency conversion, where the FX rate is itself an approximate `Double`.
/// These helpers centralize those two boundary crossings.
extension Decimal {
    /// Bridge to `Double` for the chart / FX boundary. There is no direct
    /// `Double(Decimal)` initializer, so route through `NSDecimalNumber`.
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }

    /// `Decimal` has no `.isNaN`/`.isInfinite` on the value itself the way `Double` does;
    /// `NSDecimalNumber.notANumber` is the only non-finite case it can hold. Guard against
    /// it before it reaches persistence or chart geometry.
    var isFinite: Bool { (self as NSDecimalNumber) != NSDecimalNumber.notANumber }

    /// Builds a finite `Decimal` from a `Double`, rejecting NaN/Inf (WC-H1). Used when a
    /// `Double` from the network (a market price) or a parsed field must become stored money.
    ///
    /// The `Double` being finite is necessary but **not** sufficient: `Decimal(Double)` can itself
    /// produce a non-finite `Decimal` (`NSDecimalNumber.notANumber`) for finite `Double`s whose
    /// magnitude overflows `Decimal` (e.g. `1e300`). Guard the *result* too, so a huge finite quote
    /// is rejected instead of poisoning stored/synced money (deep-audit H9).
    init?(finite value: Double) {
        guard value.isFinite else { return nil }
        let decimal = Decimal(value)
        guard decimal.isFinite else { return nil }
        self = decimal
    }
}

/// Parses user-entered money/quantity text into a finite `Decimal` (WC-H1 + WC-M9).
///
/// Replaces the scattered `Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0`,
/// which (a) accepted `"inf"`/`"nan"`/overflow as non-finite values that then corrupted
/// totals, charts and the synced iCloud copy, and (b) silently produced `0` for any
/// grouped or locale-formatted input (`"1,234.56"`, `"1.234,56"`). It tries the user's
/// locale first, then a `.` -decimal POSIX fallback, and rejects non-finite results.
enum MoneyParser {
    static func decimal(from raw: String, locale: Locale = .current) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true

        // 1) The user's own locale (handles their grouping + decimal separators).
        formatter.locale = locale
        if let number = formatter.number(from: trimmed) as? NSDecimalNumber {
            return finite(number)
        }

        // 2) Forgiving fallback: treat ',' as a decimal separator, strip stray grouping,
        //    parse as `.`-decimal POSIX. Covers pasted values whose locale we guessed wrong.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        if let number = formatter.number(from: normalized) as? NSDecimalNumber {
            return finite(number)
        }
        return nil
    }

    private static func finite(_ number: NSDecimalNumber) -> Decimal? {
        guard number != NSDecimalNumber.notANumber else { return nil }
        return number.decimalValue
    }
}

extension AmountInputFormatter {
    /// `Decimal` seed string for editor fields (WC-A1). Formats the `Decimal` directly (no
    /// `Double` round-trip) so a precise stored value isn't truncated when pre-filling an editor.
    ///
    /// Seeds in the **user's locale** (deep-audit H7): the field is later read back by
    /// `MoneyParser.decimal(from:)`, which parses `Locale.current`-first. Seeding with a POSIX `.`
    /// decimal separator meant that in a comma-decimal locale (it_IT, de_DE, …) an unedited value
    /// like `0.125` was re-parsed as `125` — a 1000× corruption on the first save of an untouched
    /// editor. Formatting in `Locale.current` (grouping disabled to keep the parse unambiguous)
    /// makes the seed round-trip exactly through the parser and also shows the number in the format
    /// the user expects.
    static func string(_ value: Decimal, locale: Locale = .current) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
}
