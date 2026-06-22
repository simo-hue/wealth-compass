import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MarketDataAPIKeyGuide: View {
    private let providers = MarketDataAPIProviderGuide.onboardingProviders

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WCColor.primary)
                    .frame(width: 28, height: 28)
                    .background(WCColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("How to get your API keys")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Use the free tiers, create a key, then paste it below.")
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    providerCards
                }

                VStack(spacing: 12) {
                    providerCards
                }
            }
        }
    }

    @ViewBuilder
    private var providerCards: some View {
        ForEach(providers) { provider in
            MarketDataAPIProviderGuideCard(provider: provider)
        }
    }
}

struct MarketDataAPIKeySecurityNote: View {
    /// Derived from the running device rather than hardcoded per call site (L3).
    private var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "Mac"
        #endif
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WCColor.primary)

            Text("Keys are stored securely in Keychain and only used to refresh market prices from this \(deviceName).")
                .font(.caption)
                .foregroundStyle(WCColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MarketDataAPIProviderGuideCard: View {
    let provider: MarketDataAPIProviderGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(provider.accent)
                    .frame(width: 30, height: 30)
                    .background(provider.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundStyle(WCColor.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                }

                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(provider.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.black.opacity(0.78))
                            .frame(width: 18, height: 18)
                            .background(provider.accent.gradient, in: Circle())

                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Link(destination: provider.url) {
                Label(provider.linkTitle, systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(provider.accent.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WCColor.cardElevated.opacity(0.48))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.04), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct MarketDataAPIProviderGuide: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let accent: Color
    let linkTitle: LocalizedStringKey
    let url: URL
    let steps: [LocalizedStringKey]

    static let onboardingProviders = [
        MarketDataAPIProviderGuide(
            id: "finnhub",
            title: "Finnhub",
            subtitle: "Stock and ETF prices",
            systemImage: "chart.line.uptrend.xyaxis",
            accent: WCColor.primary,
            linkTitle: "Open Finnhub",
            url: URL(string: "https://finnhub.io/register")!,
            steps: [
                "Create a free Finnhub account.",
                "Confirm your email and sign in.",
                "Open the dashboard API section.",
                "Copy your API key and paste it below."
            ]
        ),
        MarketDataAPIProviderGuide(
            id: "coingecko",
            title: "CoinGecko",
            subtitle: "Crypto market prices",
            systemImage: "bitcoinsign.circle",
            accent: WCColor.accent,
            linkTitle: "Open CoinGecko",
            url: URL(string: "https://www.coingecko.com/en/api/pricing")!,
            steps: [
                "Choose the free Demo API tier.",
                "Create or sign in to your account.",
                "Add a new key in Developer Dashboard.",
                "Copy your API key and paste it below."
            ]
        )
    ]
}
