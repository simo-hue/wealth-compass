import SwiftUI

struct MacOnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var currentTab = 0
    @State private var finnhubKey = ""
    @State private var coinGeckoKey = ""
    @State private var isValidating = false
    @State private var showingErrorAlert = false
    @State private var validationError: String? = nil
    
    var body: some View {
        ZStack {
            ScreenBackground()
            
            GeometryReader { proxy in
                ZStack {
                    if currentTab == 0 {
                        welcomePage
                            .transition(slideTransition)
                    } else if currentTab == 1 {
                        privacyPage
                            .transition(slideTransition)
                    } else if currentTab == 2 {
                        apiSetupPage
                            .transition(slideTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            finnhubKey = (try? KeychainCredentialStore.shared.string(for: .finnhubAPIKey)) ?? ""
            coinGeckoKey = (try? KeychainCredentialStore.shared.string(for: .coingeckoAPIKey)) ?? ""
        }
        .alert("Validation Failed", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationError ?? "Invalid API Key")
        }
    }
    
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "safari.fill")
                .font(.system(size: 90, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.primary, WCColor.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.primary.opacity(0.3), radius: 25, y: 15)
            
            VStack(spacing: 15) {
                Text("Welcome to WealthCompass")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("Your personal compass for tracking cash flow, investments, and expenses all in one beautifully designed dashboard.")
                    .font(.title3)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { currentTab = 1 }
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
    
    private var privacyPage: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 90, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.accent, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.accent.opacity(0.3), radius: 25, y: 15)
            
            VStack(spacing: 15) {
                Text("Your Data, Your Privacy")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("We don't use central servers. All your financial data is stored locally on your Mac or in your private iCloud. To track live market prices for your assets, you will connect directly to data providers.")
                    .font(.title3)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { currentTab = 2 }
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
    
    private var apiSetupPage: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "network")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.primary, .green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.primary.opacity(0.3), radius: 25, y: 15)
            
            VStack(spacing: 10) {
                Text("Connect Market Data")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("Enter your free API keys to get live stock and crypto prices. This is highly recommended—otherwise, asset prices won't be real or up to date.")
                    .font(.body)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 15) {
                InsetFinanceRow {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Finnhub API Key (Stocks)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WCColor.textSecondary)
                        SecureField("Paste Finnhub key...", text: $finnhubKey)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                    }
                }
                
                InsetFinanceRow {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CoinGecko API Key (Crypto)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WCColor.textSecondary)
                        SecureField("Paste CoinGecko key...", text: $coinGeckoKey)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 10)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    Task { await finishOnboarding() }
                } label: {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 5)
                        }
                        Text(isValidating ? "Validating..." : "Get Started")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isValidating)
                
                Button(action: skipOnboarding) {
                    Text("Skip for now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WCColor.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isValidating)
            }
            .padding(.bottom, 40)
        }
    }
    
    private func finishOnboarding() async {
        let finnhub = finnhubKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let coinGecko = coinGeckoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if finnhub.isEmpty && coinGecko.isEmpty {
            validationError = "Please insert at least one API key, or click 'Skip for now' if you wish to proceed without them."
            showingErrorAlert = true
            return
        }
        
        isValidating = true
        validationError = nil
        
        do {
            if !finnhub.isEmpty {
                _ = try await FinnhubQuoteClient(apiKey: finnhub).testConnection()
                try? KeychainCredentialStore.shared.save(finnhub, for: .finnhubAPIKey)
            }
            if !coinGecko.isEmpty {
                _ = try await CoinGeckoPriceClient(apiKey: coinGecko).testConnection()
                try? KeychainCredentialStore.shared.save(coinGecko, for: .coingeckoAPIKey)
            }
            
            completeOnboarding()
        } catch {
            isValidating = false
            validationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showingErrorAlert = true
        }
    }
    
    private func skipOnboarding() {
        completeOnboarding()
    }
    
    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            settings.hasSeenOnboarding = true
        }
    }
}
