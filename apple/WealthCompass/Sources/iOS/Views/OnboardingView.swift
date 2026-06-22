import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var currentTab = 0
    @State private var showingErrorAlert = false
    @StateObject private var viewModel = OnboardingViewModel()
    
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
        .onAppear { viewModel.loadConfiguredState() }
        .alert("Validation Failed", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let validationError = viewModel.validationError {
                Text(validationError)
            } else {
                Text("Invalid API Key")
            }
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
                
                Text("Your financial data stays on your device and in your private iCloud — there's no Wealth Compass server in between. To show live prices, the app talks directly to your chosen market-data providers (Frankfurter, Finnhub, CoinGecko) using API keys you provide; only those providers see those requests.")
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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [WCColor.primary, .green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: WCColor.primary.opacity(0.3), radius: 18, y: 9)
                    
                    VStack(spacing: 9) {
                        Text("Connect Market Data")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Enter your free API keys to get live stock and crypto prices. This is highly recommended—otherwise, asset prices won't be real or up to date.")
                            .font(.subheadline)
                            .foregroundStyle(WCColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    MarketDataAPIKeyGuide()
                        .padding(.top, 2)
                    
                    VStack(spacing: 12) {
                        InsetFinanceRow {
                            VStack(alignment: .leading, spacing: 8) {
                                credentialFieldHeader(title: "Finnhub API Key (Stocks)", isConfigured: viewModel.hasFinnhubKey)
                                SecureField(
                                    viewModel.hasFinnhubKey ? settings.localized("Enter a new key to replace…") : settings.localized("Paste Finnhub key…"),
                                    text: $viewModel.finnhubKey
                                )
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.white)
                                    .submitLabel(.done)
                            }
                        }

                        InsetFinanceRow {
                            VStack(alignment: .leading, spacing: 8) {
                                credentialFieldHeader(title: "CoinGecko API Key (Crypto)", isConfigured: viewModel.hasCoinGeckoKey)
                                SecureField(
                                    viewModel.hasCoinGeckoKey ? settings.localized("Enter a new key to replace…") : settings.localized("Paste CoinGecko key…"),
                                    text: $viewModel.coinGeckoKey
                                )
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.white)
                                    .submitLabel(.done)
                            }
                        }

                        MarketDataAPIKeySecurityNote()
                    }
                    
                    VStack(spacing: 14) {
                        Button {
                            Task {
                                if await viewModel.submit(appLanguage: settings.appLanguage) {
                                    completeOnboarding()
                                } else {
                                    showingErrorAlert = true
                                }
                            }
                        } label: {
                            HStack {
                                if viewModel.isValidating {
                                    ProgressView()
                                        .tint(.black)
                                        .padding(.trailing, 5)
                                    Text("Validating...")
                                } else {
                                    Text("Get Started")
                                }
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .disabled(viewModel.isValidating)

                        Button(action: skipOnboarding) {
                            Text("Skip for now")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(WCColor.textSecondary)
                        }
                        .disabled(viewModel.isValidating)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: 520)
                .frame(minHeight: max(proxy.size.height - 40, 680))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
    }
    
    @ViewBuilder
    private func credentialFieldHeader(title: LocalizedStringKey, isConfigured: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WCColor.textSecondary)
            Spacer()
            if isConfigured {
                Label("Configured", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WCColor.primary)
            }
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
