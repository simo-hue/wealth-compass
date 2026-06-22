import Foundation

/// Shared onboarding credential logic for iOS + macOS (M2, logic-first consolidation).
///
/// Owns the API-key entry state and the validate-then-store flow that was byte-identical
/// in `OnboardingView` and `MacOnboardingView`. The views keep their native presentation
/// shells (paged TabView vs. slide transitions) and bind to this view model; completing
/// onboarding (`AppSettings.hasSeenOnboarding`) stays a view concern.
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var finnhubKey = ""
    @Published var coinGeckoKey = ""
    @Published private(set) var hasFinnhubKey = false
    @Published private(set) var hasCoinGeckoKey = false
    @Published private(set) var isValidating = false
    @Published var validationError: String?

    /// Reflects whether keys are already stored, so the UI can show a "Configured"
    /// badge without ever loading the secrets into editable fields (H6).
    func loadConfiguredState() {
        hasFinnhubKey = KeychainCredentialStore.shared.contains(.finnhubAPIKey)
        hasCoinGeckoKey = KeychainCredentialStore.shared.contains(.coingeckoAPIKey)
    }

    /// Validates any typed keys against their providers and stores them in the Keychain.
    /// Returns `true` when onboarding should complete; on failure sets `validationError`
    /// and returns `false`. A blank field leaves any already-stored key untouched.
    func submit(appLanguage: String?) async -> Bool {
        let finnhub = finnhubKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let coinGecko = coinGeckoKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if finnhub.isEmpty && coinGecko.isEmpty {
            // Nothing typed: proceed if keys are already stored, otherwise prompt.
            if hasFinnhubKey || hasCoinGeckoKey { return true }
            validationError = AppLocalization.string(
                "Please insert at least one API key, or use 'Skip for now' if you wish to proceed without them.",
                appLanguage: appLanguage
            )
            return false
        }

        isValidating = true
        validationError = nil
        defer { isValidating = false }

        do {
            if !finnhub.isEmpty {
                _ = try await FinnhubQuoteClient(apiKey: finnhub).testConnection()
                try? KeychainCredentialStore.shared.save(finnhub, for: .finnhubAPIKey)
            }
            if !coinGecko.isEmpty {
                _ = try await CoinGeckoPriceClient(apiKey: coinGecko).testConnection()
                try? KeychainCredentialStore.shared.save(coinGecko, for: .coingeckoAPIKey)
            }
            return true
        } catch {
            validationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
