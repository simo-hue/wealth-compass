import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var currentTab = 0
    @State private var showingErrorAlert = false
    @State private var showingSkipConfirmation = false
    @StateObject private var viewModel = OnboardingViewModel()
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 28
    
    var body: some View {
        ZStack {
            ScreenBackground()
            
            TabView(selection: $currentTab) {
                welcomePage
                    .tag(0)

                personalizePage
                    .tag(1)

                privacyPage
                    .tag(2)

                apiSetupPage
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .padding(.bottom, 20)
            .overlay(alignment: .topLeading) {
                if currentTab > 0 {
                    Button {
                        withAnimation { currentTab -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 4)
                    .accessibilityLabel(settings.localized("Back"))
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        // A1: the welcome/privacy/personalize pages don't scroll, so cap very large
        // accessibility text sizes to keep their fixed layouts from overflowing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
        // L13: tapping "Skip for now" with a typed-but-unsaved key used to discard it
        // silently. Confirm first, offering to save & validate it instead.
        .alert("Unsaved API Key", isPresented: $showingSkipConfirmation) {
            Button("Save & Continue") {
                Task {
                    if await viewModel.submit(appLanguage: settings.appLanguage) {
                        completeOnboarding()
                    } else {
                        showingErrorAlert = true
                    }
                }
            }
            Button("Discard", role: .destructive) { completeOnboarding() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You entered an API key but haven't saved it. Save and validate it now, or discard it and continue?")
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
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
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
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("Your financial data stays on your device and in your private iCloud — there's no Wealth Compass Tracker server in between. To show live prices, the app talks directly to your chosen market-data providers (Frankfurter, Finnhub, CoinGecko) using API keys you provide; only those providers see those requests.")
                    .font(.body)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            
            Spacer()
            
            Button {
                withAnimation { currentTab = 3 }
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

    private var personalizePage: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "globe.europe.africa.fill")
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
                Text("Make It Yours")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Pick your base currency and language. You can change both anytime in Settings.")
                    .font(.body)
                    .foregroundStyle(WCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            VStack(spacing: 12) {
                InsetFinanceRow {
                    HStack {
                        Label("Base Currency", systemImage: "coloncurrencysign.circle")
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Base Currency", selection: $settings.currency) {
                            ForEach(Currency.allCases) { currency in
                                (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(WCColor.primary)
                    }
                }

                InsetFinanceRow {
                    HStack {
                        Label("Language", systemImage: "character.bubble")
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Language", selection: $settings.appLanguage) {
                            Text("System").tag(String?.none)
                            ForEach(settings.availableLanguages, id: \.self) { code in
                                Text(settings.languageName(for: code)).tag(String?.some(code))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(WCColor.primary)
                    }
                }
            }
            .padding(.horizontal, 30)

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
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
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
        // L13: guard against silently dropping a just-typed (but unsaved) API key.
        let hasUnsavedKey = !viewModel.finnhubKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.coinGeckoKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasUnsavedKey {
            showingSkipConfirmation = true
        } else {
            completeOnboarding()
        }
    }
    
    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            settings.hasSeenOnboarding = true
        }
    }
}
