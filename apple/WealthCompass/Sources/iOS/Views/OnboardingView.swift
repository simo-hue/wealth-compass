import SwiftUI

struct OnboardingView: View {
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
            
            TabView(selection: $currentTab) {
                welcomePage
                    .tag(0)
                
                privacyPage
                    .tag(1)
                
                apiSetupPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
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
    
    private var welcomePage: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "safari.fill")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.primary, WCColor.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.primary.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 15) {
                Text("Welcome to WealthCompass")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("Your personal compass for tracking cash flow, investments, and expenses all in one beautifully designed dashboard.")
                    .font(.body)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            
            Spacer()
            
            Button {
                withAnimation { currentTab = 1 }
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 60)
        }
    }
    
    private var privacyPage: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.accent, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.accent.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 15) {
                Text("Your Data, Your Privacy")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("We don't use central servers. All your financial data is stored locally on your device or in your private iCloud. To track live market prices for your assets, you will connect directly to data providers.")
                    .font(.body)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            
            Spacer()
            
            Button {
                withAnimation { currentTab = 2 }
            } label: {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 60)
        }
    }
    
    private var apiSetupPage: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "network")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WCColor.primary, .green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WCColor.primary.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 10) {
                Text("Connect Market Data")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("Enter your free API keys to get live stock and crypto prices. This is highly recommended—otherwise, asset prices won't be real or up to date.")
                    .font(.subheadline)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
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
                            .submitLabel(.done)
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
                            .submitLabel(.done)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    Task { await finishOnboarding() }
                } label: {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .tint(.black)
                                .padding(.trailing, 5)
                        }
                        Text(isValidating ? "Validating..." : "Get Started")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .disabled(isValidating)
                
                Button(action: skipOnboarding) {
                    Text("Skip for now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WCColor.textSecondary)
                }
                .disabled(isValidating)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
    
    private func finishOnboarding() async {
        let finnhub = finnhubKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let coinGecko = coinGeckoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if finnhub.isEmpty && coinGecko.isEmpty {
            validationError = "Please insert at least one API key, or tap 'Skip for now' if you wish to proceed without them."
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
