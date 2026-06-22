import Foundation
import Security
import SwiftUI

struct MarketPriceQuote: Equatable {
    let price: Double
    let currency: Currency
    let asOf: Date
    let provider: String
}

struct MarketPriceRefreshResult: Equatable {
    var updatedInvestments = 0
    var updatedCrypto = 0
    var failedInvestments: [String] = []
    var failedCrypto: [String] = []
    var skippedInvestments: [String] = []
    var skippedCrypto: [String] = []
    var wasAlreadyRunning = false
    var refreshedAt = Date()

    var updatedRecordCount: Int {
        updatedInvestments + updatedCrypto
    }

    var title: LocalizedStringKey {
        if wasAlreadyRunning {
            "Refresh Already Running"
        } else if updatedRecordCount > 0 {
            "Prices Updated"
        } else {
            "No Prices Updated"
        }
    }

    func localizedTitle(appLanguage: String?) -> String {
        if wasAlreadyRunning {
            AppLocalization.string("Refresh Already Running", appLanguage: appLanguage)
        } else if updatedRecordCount > 0 {
            AppLocalization.string("Prices Updated", appLanguage: appLanguage)
        } else {
            AppLocalization.string("No Prices Updated", appLanguage: appLanguage)
        }
    }

    func localizedMessage(appLanguage: String?) -> String {
        if wasAlreadyRunning {
            return AppLocalization.string("A market price refresh is already in progress.", appLanguage: appLanguage)
        }

        var lines: [String] = []
        if updatedRecordCount > 0 {
            lines.append(AppLocalization.string("Updated \(updatedInvestments) investments and \(updatedCrypto) crypto holdings.", appLanguage: appLanguage))
            lines.append(AppLocalization.string("Last refresh: \(refreshedAt.formatted(date: .abbreviated, time: .shortened)).", appLanguage: appLanguage))
        } else {
            lines.append(AppLocalization.string("No holdings were updated.", appLanguage: appLanguage))
        }

        if !skippedInvestments.isEmpty {
            lines.append(AppLocalization.string("Investments skipped: \(Self.compactList(skippedInvestments)).", appLanguage: appLanguage))
        }

        if !skippedCrypto.isEmpty {
            lines.append(AppLocalization.string("Crypto skipped: \(Self.compactList(skippedCrypto)).", appLanguage: appLanguage))
        }

        if !failedInvestments.isEmpty {
            lines.append(AppLocalization.string("Investment failures: \(Self.compactList(failedInvestments)).", appLanguage: appLanguage))
        }

        if !failedCrypto.isEmpty {
            lines.append(AppLocalization.string("Crypto failures: \(Self.compactList(failedCrypto)).", appLanguage: appLanguage))
        }

        return lines.joined(separator: "\n\n")
    }

    private static func compactList(_ values: [String]) -> String {
        let visible = values.prefix(6).joined(separator: ", ")
        guard values.count > 6 else { return visible }
        return "\(visible), +\(values.count - 6) more"
    }
}

enum MarketDataError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case unauthorized(provider: String)
    case rateLimited(provider: String)
    case providerError(provider: String, statusCode: Int)
    case invalidResponse(provider: String)
    case noQuote(provider: String, symbol: String)

    var title: LocalizedStringKey {
        "Market Data Error"
    }

    func localizedTitle(appLanguage: String?) -> String {
        AppLocalization.string("Market Data Error", appLanguage: appLanguage)
    }

    var errorDescription: String? {
        localizedDescription(appLanguage: nil)
    }

    func localizedDescription(appLanguage: String?) -> String {
        switch self {
        case .missingAPIKey:
            AppLocalization.string("A Finnhub API key is required to update investment prices.", appLanguage: appLanguage)
        case .invalidURL:
            AppLocalization.string("The market data request could not be created.", appLanguage: appLanguage)
        case .unauthorized(let provider):
            AppLocalization.string("\(provider) rejected the API key.", appLanguage: appLanguage)
        case .rateLimited(let provider):
            AppLocalization.string("\(provider) rate limit reached. Try again later.", appLanguage: appLanguage)
        case .providerError(let provider, let statusCode):
            AppLocalization.string("\(provider) returned HTTP \(statusCode).", appLanguage: appLanguage)
        case .invalidResponse(let provider):
            AppLocalization.string("\(provider) returned an invalid response.", appLanguage: appLanguage)
        case .noQuote(let provider, let symbol):
            AppLocalization.string("\(provider) did not return a usable quote for \(symbol).", appLanguage: appLanguage)
        }
    }
}

enum KeychainCredential: String {
    case finnhubAPIKey = "finnhub_api_key"
    case coingeckoAPIKey = "coingecko_api_key"
}

enum KeychainServiceError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var title: LocalizedStringKey {
        "Keychain Error"
    }

    func localizedTitle(appLanguage: String?) -> String {
        AppLocalization.string("Keychain Error", appLanguage: appLanguage)
    }

    var errorDescription: String? {
        localizedDescription(appLanguage: nil)
    }

    func localizedDescription(appLanguage: String?) -> String {
        switch self {
        case .unexpectedStatus(let status):
            AppLocalization.string("Keychain operation failed with status \(status).", appLanguage: appLanguage)
        case .invalidData:
            AppLocalization.string("The stored Keychain value could not be read.", appLanguage: appLanguage)
        }
    }
}

final class KeychainCredentialStore {
    static let shared = KeychainCredentialStore()

    private let service = "com.wealthcompass.mobile.marketdata"

    private init() {}

    func string(for credential: KeychainCredential) throws -> String? {
        var query = baseQuery(for: credential)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainServiceError.invalidData
        }

        return value
    }

    func save(_ value: String, for credential: KeychainCredential) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            try delete(credential)
            return
        }

        var query = baseQuery(for: credential)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(addStatus)
        }
    }

    func delete(_ credential: KeychainCredential) throws {
        let status = SecItemDelete(baseQuery(for: credential) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func contains(_ credential: KeychainCredential) -> Bool {
        do {
            return try string(for: credential) != nil
        } catch {
            return false
        }
    }

    private func baseQuery(for credential: KeychainCredential) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue
        ]
    }
}

struct FinnhubQuoteClient {
    let apiKey: String
    var session: URLSession = .shared

    func testConnection() async throws -> MarketPriceQuote {
        try await quote(for: "AAPL", validationNonce: UUID().uuidString)
    }

    func quote(for symbol: String) async throws -> MarketPriceQuote {
        try await quote(for: symbol, validationNonce: nil)
    }

    private func quote(for symbol: String, validationNonce: String?) async throws -> MarketPriceQuote {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw MarketDataError.noQuote(provider: "Finnhub", symbol: symbol)
        }

        guard var components = URLComponents(string: APIConfiguration.finnhubQuoteURL) else {
            throw MarketDataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: normalizedSymbol)
        ]
        if let validationNonce {
            components.queryItems?.append(URLQueryItem(name: "_validation_nonce", value: validationNonce))
        }

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: validationNonce == nil ? .useProtocolCachePolicy : .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        if validationNonce != nil {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        let (data, response) = try await NetworkRetry.data(for: request, session: session)
        try Self.validate(response: response, provider: "Finnhub")

        let quote = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)
        guard let price = quote.currentPrice, price > 0, price.isFinite else {
            throw MarketDataError.noQuote(provider: "Finnhub", symbol: normalizedSymbol)
        }

        let asOf: Date
        if let timestamp = quote.timestamp, timestamp > 0 {
            asOf = Date(timeIntervalSince1970: timestamp)
        } else {
            asOf = Date()
        }

        return MarketPriceQuote(price: price, currency: .usd, asOf: asOf, provider: "Finnhub")
    }

    private static func validate(response: URLResponse, provider: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketDataError.invalidResponse(provider: provider)
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401, 403:
            throw MarketDataError.unauthorized(provider: provider)
        case 429:
            throw MarketDataError.rateLimited(provider: provider)
        default:
            throw MarketDataError.providerError(provider: provider, statusCode: httpResponse.statusCode)
        }
    }
}

/// A coin's live prices from CoinGecko, resolved per requested currency in one call.
struct CoinGeckoCoinQuote {
    let prices: [Currency: Double]
    let asOf: Date

    /// Resolves the price in `currency`, falling back to EUR (then any available
    /// currency) if the provider didn't return the requested one.
    func resolved(in currency: Currency) -> (price: Double, currency: Currency)? {
        if let value = prices[currency] { return (value, currency) }
        if let eur = prices[.eur] { return (eur, .eur) }
        return prices.first.map { ($0.value, $0.key) }
    }
}

struct CoinGeckoPriceClient {
    var apiKey: String?
    /// Currencies to request. Each crypto holding's price is resolved in its own
    /// currency from a single batched call, so a refresh never silently re-bases
    /// a holding's cost-basis currency (see H2 in CODE_AUDIT.md).
    var currencies: [Currency] = [.eur]
    var session: URLSession = .shared

    func testConnection() async throws -> MarketPriceQuote {
        let table = try await priceTable(for: ["bitcoin"], validationNonce: UUID().uuidString)
        guard
            let quote = table["bitcoin"],
            let resolved = quote.resolved(in: currencies.first ?? .eur)
        else {
            throw MarketDataError.noQuote(provider: "CoinGecko", symbol: "bitcoin")
        }
        return MarketPriceQuote(price: resolved.price, currency: resolved.currency, asOf: quote.asOf, provider: "CoinGecko")
    }

    func priceTable(for coinIDs: [String]) async throws -> [String: CoinGeckoCoinQuote] {
        let ids = Array(Set(coinIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !ids.isEmpty else { return [:] }

        var quotes: [String: CoinGeckoCoinQuote] = [:]
        for chunk in ids.chunked(into: 100) {
            let partial = try await priceTable(for: chunk, validationNonce: nil)
            quotes.merge(partial) { _, incoming in incoming }
        }
        return quotes
    }

    private func priceTable(for coinIDs: [String], validationNonce: String?) async throws -> [String: CoinGeckoCoinQuote] {
        guard var components = URLComponents(string: APIConfiguration.coinGeckoSimplePriceURL) else {
            throw MarketDataError.invalidURL
        }
        // EUR is always included as a safety net so a value resolves even when a
        // holding's currency isn't among those CoinGecko returned.
        var requested = currencies
        if !requested.contains(.eur) { requested.append(.eur) }
        let vsCurrencies = Array(Set(requested.map { $0.rawValue.lowercased() })).sorted()
        components.queryItems = [
            URLQueryItem(name: "ids", value: coinIDs.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: vsCurrencies.joined(separator: ",")),
            URLQueryItem(name: "include_last_updated_at", value: "true")
        ]
        if let validationNonce {
            components.queryItems?.append(URLQueryItem(name: "_validation_nonce", value: validationNonce))
        }

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: validationNonce == nil ? .useProtocolCachePolicy : .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        addAPIKeyHeader(to: &request)
        if validationNonce != nil {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        let (data, response) = try await NetworkRetry.data(for: request, session: session)
        try Self.validate(response: response, provider: "CoinGecko")

        let payload = try JSONDecoder().decode([String: CoinGeckoSimplePriceResponse].self, from: data)
        return payload.compactMapValues { value in
            var resolved: [Currency: Double] = [:]
            for currency in requested {
                if let price = value.price(for: currency) {
                    resolved[currency] = price
                }
            }
            guard !resolved.isEmpty else { return nil }
            let asOf = value.lastUpdatedAt.map(Date.init(timeIntervalSince1970:)) ?? Date()
            return CoinGeckoCoinQuote(prices: resolved, asOf: asOf)
        }
    }

    private static func validate(response: URLResponse, provider: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketDataError.invalidResponse(provider: provider)
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401, 403:
            throw MarketDataError.unauthorized(provider: provider)
        case 429:
            throw MarketDataError.rateLimited(provider: provider)
        default:
            throw MarketDataError.providerError(provider: provider, statusCode: httpResponse.statusCode)
        }
    }

    private func addAPIKeyHeader(to request: inout URLRequest) {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return
        }
        request.setValue(key, forHTTPHeaderField: "x-cg-demo-api-key")
    }
}

private struct FinnhubQuoteResponse: Decodable {
    let currentPrice: Double?
    let timestamp: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case timestamp = "t"
    }
}

/// Decodes CoinGecko's `simple/price` per-coin object, which carries one key per
/// requested `vs_currency` (lowercased ISO code) plus `last_updated_at`. Decoded
/// dynamically so any currency the app requests is supported without code changes.
private struct CoinGeckoSimplePriceResponse: Decodable {
    let prices: [String: Double]
    let lastUpdatedAt: TimeInterval?

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var collected: [String: Double] = [:]
        var updatedAt: TimeInterval?
        for key in container.allKeys {
            if key.stringValue == "last_updated_at" {
                updatedAt = try? container.decode(TimeInterval.self, forKey: key)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                collected[key.stringValue] = value
            }
        }
        prices = collected
        lastUpdatedAt = updatedAt
    }

    func price(for currency: Currency) -> Double? {
        guard let value = prices[currency.rawValue.lowercased()], value > 0, value.isFinite else {
            return nil
        }
        return value
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension CryptoHolding {
    var coinGeckoID: String? {
        if let trimmed = coinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty {
            return trimmed
        }
        return Self.commonCoinGeckoIDs[symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    private static let commonCoinGeckoIDs: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "SOL": "solana",
        "BNB": "binancecoin",
        "XRP": "ripple",
        "ADA": "cardano",
        "DOGE": "dogecoin",
        "DOT": "polkadot",
        "AVAX": "avalanche-2",
        "MATIC": "matic-network",
        "POL": "polygon-ecosystem-token",
        "LINK": "chainlink",
        "LTC": "litecoin",
        "BCH": "bitcoin-cash",
        "UNI": "uniswap",
        "ATOM": "cosmos",
        "CRO": "crypto-com-chain",
        "USDT": "tether",
        "USDC": "usd-coin",
        "DAI": "dai"
    ]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
