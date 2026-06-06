import Foundation

struct ExchangeRateSnapshot: Codable, Equatable {
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
        guard baseCurrency == .eur else { return false }
        return Currency.allCases.allSatisfy { currency in
            guard let rate = unitsPerBaseCurrency(for: currency) else { return false }
            return rate.isFinite && rate > 0
        }
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

    var title: String {
        if wasAlreadyRunning {
            return "Refresh Already Running"
        }
        return succeeded ? "Exchange Rates Updated" : "Exchange Rate Refresh Failed"
    }

    var message: String {
        if wasAlreadyRunning {
            return "An exchange-rate refresh is already in progress."
        }

        if let errorMessage {
            let activeRates = snapshot == nil ? "the built-in offline fallback rates" : "the last cached rates"
            return "\(errorMessage)\n\nWealth Compass will continue using \(activeRates)."
        }

        if let snapshot {
            return """
            Latest ECB reference rates are effective \(snapshot.effectiveDate.formatted(date: .long, time: .omitted)).

            The rates are cached locally for offline use.
            """
        }

        return errorMessage ?? "The exchange-rate provider did not return a usable response."
    }
}

enum ExchangeRateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case providerError(statusCode: Int)
    case invalidPayload
    case incompleteRates

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The exchange-rate request could not be created."
        case .invalidResponse:
            return "The exchange-rate provider returned an invalid response."
        case .providerError(let statusCode):
            return "The exchange-rate provider returned HTTP \(statusCode)."
        case .invalidPayload:
            return "The exchange-rate provider returned malformed data."
        case .incompleteRates:
            return "The exchange-rate provider did not return all supported currencies."
        }
    }
}

struct ExchangeRateClient {
    var session: URLSession = .shared

    func latestRates() async throws -> ExchangeRateSnapshot {
        let quoteCurrencies = Currency.allCases
            .filter { $0 != .eur }
            .map(\.rawValue)
            .sorted()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.frankfurter.dev"
        components.path = "/v2/rates"
        components.queryItems = [
            URLQueryItem(name: "base", value: Currency.eur.rawValue),
            URLQueryItem(name: "quotes", value: quoteCurrencies.joined(separator: ",")),
            URLQueryItem(name: "providers", value: "ECB")
        ]

        guard let url = components.url else {
            throw ExchangeRateError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExchangeRateError.invalidResponse
        }
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
        for item in payload where quoteCurrencies.contains(item.quote) && item.rate.isFinite && item.rate > 0 {
            rates[item.quote] = item.rate
        }

        guard quoteCurrencies.allSatisfy({ rates[$0] != nil }) else {
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
