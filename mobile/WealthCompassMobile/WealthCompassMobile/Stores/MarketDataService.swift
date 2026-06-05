import Foundation
import Security

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

    var title: String {
        if wasAlreadyRunning {
            return "Refresh Already Running"
        }
        return updatedRecordCount > 0 ? "Prices Updated" : "No Prices Updated"
    }

    var message: String {
        if wasAlreadyRunning {
            return "A market price refresh is already in progress."
        }

        var lines: [String] = []
        if updatedRecordCount > 0 {
            lines.append("Updated \(updatedInvestments) investments and \(updatedCrypto) crypto holdings.")
            lines.append("Last refresh: \(refreshedAt.formatted(date: .abbreviated, time: .shortened)).")
        } else {
            lines.append("No holdings were updated.")
        }

        if !skippedInvestments.isEmpty {
            lines.append("Investments skipped: \(Self.compactList(skippedInvestments)).")
        }

        if !skippedCrypto.isEmpty {
            lines.append("Crypto skipped: \(Self.compactList(skippedCrypto)).")
        }

        if !failedInvestments.isEmpty {
            lines.append("Investment failures: \(Self.compactList(failedInvestments)).")
        }

        if !failedCrypto.isEmpty {
            lines.append("Crypto failures: \(Self.compactList(failedCrypto)).")
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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "A Finnhub API key is required to update investment prices."
        case .invalidURL:
            return "The market data request could not be created."
        case .unauthorized(let provider):
            return "\(provider) rejected the API key."
        case .rateLimited(let provider):
            return "\(provider) rate limit reached. Try again later."
        case .providerError(let provider, let statusCode):
            return "\(provider) returned HTTP \(statusCode)."
        case .invalidResponse(let provider):
            return "\(provider) returned an invalid response."
        case .noQuote(let provider, let symbol):
            return "\(provider) did not return a usable quote for \(symbol)."
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

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidData:
            return "The stored Keychain value could not be read."
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
        try await quote(for: "AAPL")
    }

    func quote(for symbol: String) async throws -> MarketPriceQuote {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw MarketDataError.noQuote(provider: "Finnhub", symbol: symbol)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "finnhub.io"
        components.path = "/api/v1/quote"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: normalizedSymbol)
        ]

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
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

struct CoinGeckoPriceClient {
    var apiKey: String?
    var session: URLSession = .shared

    func testConnection() async throws -> MarketPriceQuote {
        guard let quote = try await prices(for: ["bitcoin"])["bitcoin"] else {
            throw MarketDataError.noQuote(provider: "CoinGecko", symbol: "bitcoin")
        }
        return quote
    }

    func prices(for coinIDs: [String]) async throws -> [String: MarketPriceQuote] {
        let ids = Array(Set(coinIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !ids.isEmpty else { return [:] }

        var quotes: [String: MarketPriceQuote] = [:]
        for chunk in ids.chunked(into: 100) {
            let partial = try await pricesForChunk(chunk)
            quotes.merge(partial) { _, incoming in incoming }
        }
        return quotes
    }

    private func pricesForChunk(_ coinIDs: [String]) async throws -> [String: MarketPriceQuote] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coingecko.com"
        components.path = "/api/v3/simple/price"
        components.queryItems = [
            URLQueryItem(name: "ids", value: coinIDs.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_last_updated_at", value: "true")
        ]

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        addAPIKeyHeader(to: &request)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, provider: "CoinGecko")

        let payload = try JSONDecoder().decode([String: CoinGeckoSimplePriceResponse].self, from: data)
        return payload.compactMapValues { value in
            guard let price = value.usd, price > 0, price.isFinite else { return nil }
            let asOf = value.lastUpdatedAt.map(Date.init(timeIntervalSince1970:)) ?? Date()
            return MarketPriceQuote(price: price, currency: .usd, asOf: asOf, provider: "CoinGecko")
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

private struct CoinGeckoSimplePriceResponse: Decodable {
    let usd: Double?
    let lastUpdatedAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usd
        case lastUpdatedAt = "last_updated_at"
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
