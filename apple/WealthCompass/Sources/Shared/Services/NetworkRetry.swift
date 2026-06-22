import Foundation

/// Shared networking layer with consistent retry / backoff / offline handling (M8).
///
/// `ExchangeRateService` and `MarketDataService` route their requests through this so
/// transient failures (lost connectivity, timeouts, HTTP 429, HTTP 5xx) are retried
/// with exponential backoff instead of surfacing as a one-shot error. Non-retryable
/// statuses (e.g. 401/403 auth, 200, 404) return immediately so each service's existing
/// validation/decoding can handle them.
enum NetworkRetry {
    struct Policy {
        var maxAttempts: Int = 3
        var baseDelay: TimeInterval = 0.5
        var maxDelay: TimeInterval = 8

        static let `default` = Policy()
    }

    /// Performs `request`, retrying transient failures per `policy`. Returns the body
    /// plus the final `HTTPURLResponse` (throws `URLError(.badServerResponse)` if the
    /// response isn't HTTP, or rethrows the last transport error once attempts are spent).
    static func data(
        for request: URLRequest,
        session: URLSession,
        policy: Policy = .default,
        retryableStatus: @Sendable (Int) -> Bool = { $0 == 429 || (500...599).contains($0) }
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if retryableStatus(http.statusCode), attempt < policy.maxAttempts {
                    try await backoff(attempt: attempt, policy: policy)
                    continue
                }
                return (data, http)
            } catch let error as URLError where Self.isTransient(error) && attempt < policy.maxAttempts {
                try await backoff(attempt: attempt, policy: policy)
                continue
            }
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func backoff(attempt: Int, policy: Policy) async throws {
        let delay = min(policy.maxDelay, policy.baseDelay * pow(2, Double(attempt - 1)))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
