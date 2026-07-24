import Foundation
import SwiftUI

struct ExchangeRateSnapshot: Codable, Equatable, Sendable {
    let baseCurrency: Currency
    let rates: [String: Double]
    let effectiveDate: Date
    let fetchedAt: Date
    let provider: String

    func unitsPerBaseCurrency(for currency: Currency) -> Double? {
        if currency == baseCurrency {
            return 1
        }
        return rates[currency.rawValue]
    }

    var isValid: Bool {
        // EUR base is required (rates are expressed as units-per-EUR). We no longer
        // require every supported currency to be present: the provider's published
        // set can change, and any currency missing from the table converts via its
        // offline fallback. We only require a non-empty, well-formed table.
        guard baseCurrency == .eur, !rates.isEmpty else { return false }
        return rates.values.allSatisfy { $0.isFinite && $0 > 0 }
    }
}

struct ExchangeRateRefreshResult: Equatable {
    let snapshot: ExchangeRateSnapshot?
    let errorMessage: String?
    let didChangeRates: Bool
    let wasAlreadyRunning: Bool

    var succeeded: Bool {
        snapshot != nil && errorMessage == nil
    }

    var title: LocalizedStringKey {
        if wasAlreadyRunning {
            "Refresh Already Running"
        } else if succeeded {
            "Exchange Rates Updated"
        } else {
            "Exchange Rate Refresh Failed"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        if wasAlreadyRunning {
            AppLocalization.string("Refresh Already Running", appLanguage: appLanguage)
        } else if succeeded {
            AppLocalization.string("Exchange Rates Updated", appLanguage: appLanguage)
        } else {
            AppLocalization.string("Exchange Rate Refresh Failed", appLanguage: appLanguage)
        }
    }

    func localizedMessage(appLanguage: String?) -> String {
        if wasAlreadyRunning {
            return AppLocalization.string("An exchange-rate refresh is already in progress.", appLanguage: appLanguage)
        }

        if let errorMessage {
            // L41: keep the fallback clause inside the format string as one coherent translation unit,
            // instead of splicing a separately-localized fragment into a localized frame (the fragment
            // was translated in only 6 locales, leaving a half-English sentence in 28 others).
            return snapshot == nil
                ? AppLocalization.string("\(errorMessage)\n\nWealth Compass Tracker will continue using the built-in offline fallback rates.", appLanguage: appLanguage)
                : AppLocalization.string("\(errorMessage)\n\nWealth Compass Tracker will continue using the last cached rates.", appLanguage: appLanguage)
        }

        if let snapshot {
            return AppLocalization.string("Latest ECB reference rates are effective \(snapshot.effectiveDate.formatted(date: .long, time: .omitted)).\n\nThe rates are cached locally for offline use.", appLanguage: appLanguage)
        }

        return AppLocalization.string("The exchange-rate provider did not return a usable response.", appLanguage: appLanguage)
    }
}

enum ExchangeRateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case providerError(statusCode: Int)
    case invalidPayload
    case incompleteRates

    var title: LocalizedStringKey {
        switch self {
        case .invalidURL:
            "Exchange Rate Error"
        case .invalidResponse:
            "Exchange Rate Error"
        case .providerError:
            "Exchange Rate Error"
        case .invalidPayload:
            "Exchange Rate Error"
        case .incompleteRates:
            "Exchange Rate Error"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        AppLocalization.string("Exchange Rate Error", appLanguage: appLanguage)
    }

    var errorDescription: String? {
        localizedDescription(appLanguage: nil)
    }

    func localizedDescription(appLanguage: String?) -> String {
        switch self {
        case .invalidURL:
            AppLocalization.string("The exchange-rate request could not be created.", appLanguage: appLanguage)
        case .invalidResponse:
            AppLocalization.string("The exchange-rate provider returned an invalid response.", appLanguage: appLanguage)
        case .providerError(let statusCode):
            AppLocalization.string("The exchange-rate provider returned HTTP \(statusCode).", appLanguage: appLanguage)
        case .invalidPayload:
            AppLocalization.string("The exchange-rate provider returned malformed data.", appLanguage: appLanguage)
        case .incompleteRates:
            AppLocalization.string("The exchange-rate provider did not return all supported currencies.", appLanguage: appLanguage)
        }
    }
}

struct ExchangeRateClient {
    var session: URLSession = .shared

    func latestRates() async throws -> ExchangeRateSnapshot {
        // Contact Frankfurter directly (no proxy). Request the full ECB table by
        // omitting a `quotes` filter, so every currency the provider publishes is
        // available for conversion; currencies it omits fall back per-currency.
        guard var components = URLComponents(string: APIConfiguration.frankfurterRatesURL) else {
            throw ExchangeRateError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "base", value: Currency.eur.rawValue),
            URLQueryItem(name: "providers", value: "ECB")
        ]

        guard let url = components.url else {
            throw ExchangeRateError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await NetworkRetry.data(for: request, session: session)
        guard httpResponse.statusCode == 200 else {
            throw ExchangeRateError.providerError(statusCode: httpResponse.statusCode)
        }

        let payload: [FrankfurterRateResponse]
        do {
            payload = try JSONDecoder().decode([FrankfurterRateResponse].self, from: data)
        } catch {
            throw ExchangeRateError.invalidPayload
        }

        guard
            let dateString = payload.first?.date,
            payload.allSatisfy({ $0.date == dateString && $0.base == Currency.eur.rawValue }),
            let effectiveDate = Self.parseDate(dateString)
        else {
            throw ExchangeRateError.invalidPayload
        }

        var rates: [String: Double] = [:]
        for item in payload where item.rate.isFinite && item.rate > 0 {
            rates[item.quote] = item.rate
        }

        guard !rates.isEmpty else {
            throw ExchangeRateError.incompleteRates
        }

        return ExchangeRateSnapshot(
            baseCurrency: .eur,
            rates: rates,
            effectiveDate: effectiveDate,
            fetchedAt: Date(),
            provider: "European Central Bank via Frankfurter"
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: .gregorian)
        dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
        dateComponents.year = components[0]
        dateComponents.month = components[1]
        dateComponents.day = components[2]
        return dateComponents.date
    }
}

private struct FrankfurterRateResponse: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: Double
}
