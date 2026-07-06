import Foundation
import os
import Security
import SwiftUI

/// L45: one shared, unconfigured `JSONDecoder` reused across the market-data response types instead of
/// allocating a fresh one per decode (once per holding on a large refresh). An unconfigured decoder is
/// never mutated after construction, so it's safe to share across concurrent decodes. Mirrors
/// `FinanceJSONCoding`'s centralization; each response type still carries its own `CodingKeys`.
private enum MarketDataJSON {
    static let decoder = JSONDecoder()
}

/// L46: diagnostics for market-data decode drift, via the unified logging system (NOT the removed
/// cleartext localhost logging — this is `os.Logger`, App-Store-safe).
private enum MarketDataLog {
    static let logger = Logger(subsystem: "com.wealthcompass.mobile", category: "MarketData")
}

struct MarketPriceQuote: Equatable {
    let price: Double
    /// The currency `price` is quoted in, or `nil` when the source doesn't report one (Finnhub's
    /// `/quote`). The refresh pipeline maps a `nil` currency to the holding's own currency at its
    /// single conversion point, so an unknown currency never causes a wrong FX hop.
    let currency: Currency?
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

enum KeychainCredential: String, CaseIterable {
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

    /// Removes every stored market-data credential. Used by the factory reset so the
    /// Finnhub/CoinGecko keys never survive an "Erase Everything". Best-effort per key:
    /// a single failing delete must not block wiping the rest.
    func deleteAll() {
        for credential in KeychainCredential.allCases {
            try? delete(credential)
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
            // WC-L11: revalidate with the provider on a real (user-triggered) refresh so a
            // cached quote/price isn't returned as if fresh; validation still ignores cache.
            cachePolicy: validationNonce == nil ? .reloadRevalidatingCacheData : .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        if validationNonce != nil {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        let (data, response) = try await NetworkRetry.data(for: request, session: session)
        try Self.validate(response: response, provider: "Finnhub")

        let quote = try MarketDataJSON.decoder.decode(FinnhubQuoteResponse.self, from: data)
        guard let price = quote.currentPrice, price > 0, price.isFinite else {
            throw MarketDataError.noQuote(provider: "Finnhub", symbol: normalizedSymbol)
        }

        let asOf: Date
        if let timestamp = quote.timestamp, timestamp > 0 {
            asOf = Date(timeIntervalSince1970: timestamp)
        } else {
            asOf = Date()
        }

        // Finnhub's /quote doesn't report a currency, so we don't assert one — the caller maps a
        // nil source currency to the holding's own at the single conversion point (previously this
        // hardcoded .usd, which was inert for investments but a misleading tag).
        return MarketPriceQuote(price: price, currency: nil, asOf: asOf, provider: "Finnhub")
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
        var lastError: Error?
        for chunk in ids.chunked(into: 100) {
            // Preserve partial success: a failed chunk must not discard the coins already fetched
            // (WC-B1 — one later batch failing used to orphan every earlier price). Coins from a
            // failed chunk simply stay absent and are reported per-holding by the caller.
            do {
                let partial = try await priceTable(for: chunk, validationNonce: nil)
                quotes.merge(partial) { _, incoming in incoming }
            } catch {
                lastError = error
            }
        }
        // Surface an error only when nothing came back at all, so the caller's catch still reports
        // a total outage; any partial table is returned and used.
        if quotes.isEmpty, let lastError {
            throw lastError
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
            // WC-L11: revalidate with the provider on a real (user-triggered) refresh so a
            // cached quote/price isn't returned as if fresh; validation still ignores cache.
            cachePolicy: validationNonce == nil ? .reloadRevalidatingCacheData : .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        addAPIKeyHeader(to: &request)
        if validationNonce != nil {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        let (data, response) = try await NetworkRetry.data(for: request, session: session)
        try Self.validate(response: response, provider: "CoinGecko")

        let payload = try MarketDataJSON.decoder.decode([String: CoinGeckoSimplePriceResponse].self, from: data)
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

    // MARK: - Symbol resolution (I2)

    /// Resolves a holding's ticker/name to a CoinGecko coin id via `/search`, for holdings that
    /// carry neither an explicit `coinId` nor a built-in mapping. Returns nil when nothing matches
    /// confidently — a clear skip beats pricing the wrong coin.
    func searchCoinID(symbol: String, name: String) async throws -> String? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: APIConfiguration.coinGeckoSearchURL) else {
            throw MarketDataError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "query", value: trimmed)]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        addAPIKeyHeader(to: &request)

        let (data, response) = try await NetworkRetry.data(for: request, session: session)
        try Self.validate(response: response, provider: "CoinGecko")
        return Self.bestCoinID(try Self.decodeSearch(data), symbol: trimmed, name: name)
    }

    static func decodeSearch(_ data: Data) throws -> [CoinGeckoSearchCoin] {
        let payload = try MarketDataJSON.decoder.decode(CoinGeckoSearchResponse.self, from: data)
        return payload.coins?.compactMap { $0.asCoin } ?? []
    }

    /// Picks the coin whose ticker matches exactly (case-insensitive), preferring the best
    /// market-cap rank (lowest number) to break ticker collisions; falls back to a *unique* exact
    /// name match. Returns nil when nothing matches confidently.
    static func bestCoinID(_ coins: [CoinGeckoSearchCoin], symbol: String, name: String) -> String? {
        let wantedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbolMatches = coins.filter { $0.symbol?.lowercased() == wantedSymbol }
        if !symbolMatches.isEmpty {
            return symbolMatches.min {
                ($0.marketCapRank ?? Int.max) < ($1.marketCapRank ?? Int.max)
            }?.id
        }
        let wantedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !wantedName.isEmpty {
            let nameMatches = coins.filter { $0.name?.lowercased() == wantedName }
            if nameMatches.count == 1 { return nameMatches.first?.id }
        }
        return nil
    }
}

/// A coin returned by CoinGecko's `/search` endpoint.
struct CoinGeckoSearchCoin: Equatable {
    let id: String
    let symbol: String?
    let name: String?
    let marketCapRank: Int?
}

private struct CoinGeckoSearchResponse: Decodable {
    let coins: [Coin]?

    struct Coin: Decodable {
        let id: String?
        let symbol: String?
        let name: String?
        let marketCapRank: Int?

        private enum CodingKeys: String, CodingKey {
            case id, symbol, name
            case marketCapRank = "market_cap_rank"
        }

        var asCoin: CoinGeckoSearchCoin? {
            guard let id, !id.isEmpty else { return nil }
            return CoinGeckoSearchCoin(id: id, symbol: symbol, name: name, marketCapRank: marketCapRank)
        }
    }
}

/// Keyless fallback quote source for instruments Finnhub's free (US-only) tier can't price.
///
/// The refresh pipeline calls this only when Finnhub returns `.noQuote` for a symbol — the
/// signature of a non-US listing such as a European UCITS ETF (`VWCE`). Yahoo covers those
/// venues and, unlike Finnhub's `/quote`, returns the listing's **currency**, so the caller
/// can store the price in the holding's own currency instead of assuming USD.
///
/// This is an unofficial endpoint with no stability guarantee; it is deliberately a
/// best-effort *fallback*, never the primary source, and a failure here leaves the holding's
/// existing (e.g. manually entered) price untouched.
struct YahooQuoteClient {
    var session: URLSession = .shared

    /// Resolves a holding to a live quote in the listing's **native** currency.
    ///
    /// Resolution cascade (mirrors `CryptoHolding.coinGeckoID`'s explicit-then-fallback shape):
    /// 1. `symbol` already carries an exchange suffix (contains ".") → quote it directly.
    /// 2. else `isin` is set → search by ISIN and pick the best candidate.
    /// 3. else → search by the bare symbol and pick the best candidate.
    func resolvedQuote(
        symbol: String,
        isin: String,
        name: String,
        preferredCurrency: Currency
    ) async throws -> MarketPriceQuote {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymbol.isEmpty else {
            throw MarketDataError.noQuote(provider: Self.provider, symbol: symbol)
        }

        // (1) Explicit exchange-qualified symbol — trust it, no search needed.
        if trimmedSymbol.contains(".") {
            return try await quote(forResolvedSymbol: trimmedSymbol)
        }

        // (2)/(3) Resolve via search, preferring ISIN when present.
        let trimmedISIN = isin.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedISIN.isEmpty ? trimmedSymbol : trimmedISIN
        let candidates = try await search(query: query)
        guard let best = Self.bestCandidate(candidates, preferredCurrency: preferredCurrency, name: name) else {
            throw MarketDataError.noQuote(provider: Self.provider, symbol: symbol)
        }
        return try await quote(forResolvedSymbol: best.symbol)
    }

    /// Fetches the live price for an already-resolved, exchange-qualified symbol.
    func quote(forResolvedSymbol symbol: String) async throws -> MarketPriceQuote {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard
            !normalized.isEmpty,
            let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: APIConfiguration.yahooChartURL + encoded)
        else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await NetworkRetry.data(for: Self.request(url: url), session: session)
        try Self.validate(response: response)
        return try Self.decodeChart(data, requestedSymbol: normalized)
    }

    /// Searches Yahoo for candidate listings matching a bare symbol or ISIN.
    func search(query: String) async throws -> [YahooSearchCandidate] {
        guard var components = URLComponents(string: APIConfiguration.yahooSearchURL) else {
            throw MarketDataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0")
        ]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let (data, response) = try await NetworkRetry.data(for: Self.request(url: url), session: session)
        try Self.validate(response: response)
        return try Self.decodeSearch(data)
    }

    // MARK: - Pure helpers (unit-tested without the network)

    static let provider = "Yahoo Finance"

    /// Chooses the most likely listing for a holding. Equity/ETF types only; then prefer a
    /// currency match (avoids an unnecessary FX hop), then the closest name, then Yahoo's own
    /// relevance order (first wins ties). Correctness never depends on this — the price is
    /// always re-expressed in the holding's currency afterwards — it only reduces the chance
    /// of locking onto a same-ticker *different* instrument.
    static func bestCandidate(
        _ candidates: [YahooSearchCandidate],
        preferredCurrency: Currency,
        name: String
    ) -> YahooSearchCandidate? {
        let eligible = candidates.filter { $0.isEquityLike }
        let pool = eligible.isEmpty ? candidates : eligible
        guard let first = pool.first else { return nil }

        func score(_ candidate: YahooSearchCandidate) -> Double {
            var value = 0.0
            if let currency = candidate.currency?.uppercased(), currency == preferredCurrency.rawValue {
                value += 100
            }
            value += Self.nameSimilarity(candidate.displayName, name) * 10
            return value
        }

        // Stable max: iterate in Yahoo's order so an equal score keeps the higher-ranked listing.
        var best = first
        var bestScore = score(first)
        for candidate in pool.dropFirst() {
            let candidateScore = score(candidate)
            if candidateScore > bestScore {
                best = candidate
                bestScore = candidateScore
            }
        }
        return best
    }

    /// Jaccard overlap of lowercased alphanumeric word tokens (0…1). Deterministic and
    /// locale-light so "Vanguard FTSE All-World UCITS ETF" scores high against "VWCE All World".
    static func nameSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Self.tokens(lhs)
        let right = Self.tokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let union = left.union(right).count
        return union == 0 ? 0 : Double(left.intersection(right).count) / Double(union)
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(
            value.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    static func decodeChart(_ data: Data, requestedSymbol: String) throws -> MarketPriceQuote {
        let payload = try MarketDataJSON.decoder.decode(YahooChartResponse.self, from: data)
        guard
            let result = payload.chart.result?.first,
            let rawPrice = result.meta.regularMarketPrice, rawPrice > 0, rawPrice.isFinite,
            let rawCurrency = result.meta.currency
        else {
            throw MarketDataError.noQuote(provider: provider, symbol: requestedSymbol)
        }

        // Yahoo quotes some London listings in pence ("GBp"/"GBX"); normalize to major units so
        // the stored price isn't 100× off. Any currency outside our table fails cleanly (a safe
        // no-update) rather than risking a wrong value.
        let price: Double
        let isoCode: String
        if rawCurrency == "GBp" || rawCurrency == "GBX" {
            price = rawPrice / 100.0
            isoCode = "GBP"
        } else {
            price = rawPrice
            isoCode = rawCurrency.uppercased()
        }
        guard let currency = Currency(rawValue: isoCode) else {
            throw MarketDataError.noQuote(provider: provider, symbol: requestedSymbol)
        }

        let asOf = result.meta.regularMarketTime.map(Date.init(timeIntervalSince1970:)) ?? Date()
        return MarketPriceQuote(price: price, currency: currency, asOf: asOf, provider: provider)
    }

    static func decodeSearch(_ data: Data) throws -> [YahooSearchCandidate] {
        let payload = try MarketDataJSON.decoder.decode(YahooSearchResponse.self, from: data)
        return payload.quotes?.compactMap { $0.asCandidate } ?? []
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        // Yahoo rejects requests that don't carry a browser-like User-Agent.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func validate(response: URLResponse) throws {
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

/// A single listing returned by Yahoo's search endpoint.
struct YahooSearchCandidate: Equatable {
    let symbol: String
    let quoteType: String?
    let shortName: String?
    let longName: String?
    let currency: String?

    var displayName: String { longName ?? shortName ?? symbol }

    /// Yahoo `quoteType` values for tradable equities/funds we'd price (excludes news,
    /// futures, options, currencies…).
    var isEquityLike: Bool {
        guard let quoteType = quoteType?.uppercased() else { return false }
        return ["EQUITY", "ETF", "MUTUALFUND", "INDEX"].contains(quoteType)
    }
}

private struct YahooChartResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?
    }

    struct Result: Decodable {
        let meta: Meta
    }

    struct Meta: Decodable {
        let currency: String?
        let regularMarketPrice: Double?
        let regularMarketTime: TimeInterval?
    }
}

private struct YahooSearchResponse: Decodable {
    let quotes: [Quote]?

    struct Quote: Decodable {
        let symbol: String?
        let quoteType: String?
        let shortname: String?
        let longname: String?
        let currency: String?

        var asCandidate: YahooSearchCandidate? {
            guard let symbol, !symbol.isEmpty else { return nil }
            return YahooSearchCandidate(
                symbol: symbol,
                quoteType: quoteType,
                shortName: shortname,
                longName: longname,
                currency: currency
            )
        }
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
            } else {
                do {
                    collected[key.stringValue] = try container.decode(Double.self, forKey: key)
                } catch {
                    // L46: the key is present (it came from `allKeys`), so a decode failure means the
                    // value is present-but-wrong-type — a provider format drift, not a merely-absent
                    // currency. Log it (still tolerating it: the currency is dropped, not fatal) so a
                    // mass "no price" outage from a payload change is diagnosable instead of silent.
                    MarketDataLog.logger.warning("CoinGecko /simple/price value for \(key.stringValue, privacy: .public) was present but not a Double: \(String(describing: error), privacy: .public)")
                }
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
