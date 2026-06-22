import Foundation

/// Pure, testable currency conversion (M1 / T1).
///
/// Holds an optional live `ExchangeRateSnapshot` and converts amounts through the
/// EUR base, falling back to each currency's offline seed rate when the snapshot is
/// missing a rate. The guards against zero / non-finite rates are preserved here —
/// a NaN/Inf would otherwise propagate into Swift Charts geometry and spam
/// CoreGraphics errors. `AppSettings.convert` delegates to this type so the math can
/// be unit-tested without the `@MainActor` store.
struct CurrencyConverter {
    let snapshot: ExchangeRateSnapshot?

    init(snapshot: ExchangeRateSnapshot?) {
        self.snapshot = snapshot
    }

    /// Units of `currency` per 1 EUR: the live rate if present, else the offline seed.
    func unitsPerEuro(for currency: Currency) -> Double {
        snapshot?.unitsPerBaseCurrency(for: currency) ?? currency.fallbackUnitsPerEuro
    }

    /// Converts `value` from `source` to `target`. Returns the value unchanged when a
    /// rate is zero or non-finite (so charts never receive NaN/Inf).
    func convert(_ value: Double, from source: Currency, to target: Currency) -> Double {
        guard source != target else { return value }
        let sourceUnitsPerEuro = unitsPerEuro(for: source)
        let targetUnitsPerEuro = unitsPerEuro(for: target)
        guard
            value.isFinite,
            sourceUnitsPerEuro.isFinite, sourceUnitsPerEuro > 0,
            targetUnitsPerEuro.isFinite, targetUnitsPerEuro > 0
        else {
            return value
        }
        let result = value / sourceUnitsPerEuro * targetUnitsPerEuro
        return result.isFinite ? result : value
    }

    /// Converts from an optional source currency (nil → no conversion).
    func convert(_ value: Double, from source: Currency?, to target: Currency) -> Double {
        guard let source else { return value }
        return convert(value, from: source, to: target)
    }
}

/// Single number→input-field formatter (L4).
///
/// Amount fields were seeded inconsistently — `String(Double)` (which can emit scientific
/// notation, e.g. "1e-07", or locale-mismatched separators) in some forms and ad-hoc
/// `String(format: "%.8g")` in others. This produces one clean, editable decimal string
/// everywhere: no grouping separators, no scientific notation, "." decimal, up to 8
/// fractional digits — round-tripping with the forms'
/// `Double(text.replacingOccurrences(of: ",", with: "."))` parse.
enum AmountInputFormatter {
    static func string(_ value: Double) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
