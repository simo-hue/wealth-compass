import SwiftUI

struct MacOnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var currentTab = 0
    @State private var showingErrorAlert = false
    @StateObject private var viewModel = OnboardingViewModel()
    
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
        .onAppear { viewModel.loadConfiguredState() }
        .alert("Validation Failed", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.validationError ?? settings.localized("Invalid API Key"))
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
                
                Text("Your financial data stays on your Mac and in your private iCloud — there's no Wealth Compass server in between. To show live prices, the app talks directly to your chosen market-data providers (Frankfurter, Finnhub, CoinGecko) using API keys you provide; only those providers see those requests.")
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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "network")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [WCColor.primary, .green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: WCColor.primary.opacity(0.3), radius: 20, y: 10)
                    
                    VStack(spacing: 9) {
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

                    MarketDataAPIKeyGuide()
                        .frame(maxWidth: 760)
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
                            }
                        }

                        MarketDataAPIKeySecurityNote(deviceName: "Mac")
                    }
                    .frame(maxWidth: 520)
                    
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
                                        .controlSize(.small)
                                        .padding(.trailing, 5)
                                }
                                Text(viewModel.isValidating ? "Validating..." : "Get Started")
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: 320)
                            .padding(.vertical, 14)
                            .background(WCColor.primary.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isValidating)

                        Button(action: skipOnboarding) {
                            Text("Skip for now")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(WCColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isValidating)
                    }
                }
                .frame(maxWidth: 840)
                .frame(minHeight: max(proxy.size.height - 40, 620))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.vertical, 24)
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
