import Foundation

/// Defines the base URL for the Wealth Compass Proxy Backend.
/// After deploying the Cloudflare Worker, replace this with your actual workers.dev URL.
/// Example: "https://wealthcompass-api-proxy.yourusername.workers.dev"
enum APIConfiguration {
    static let proxyBaseURL = "https://wealthcompass-api-proxy.mattioli-simone-10.workers.dev"
}
