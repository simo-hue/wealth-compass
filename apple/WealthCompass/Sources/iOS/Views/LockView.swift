import SwiftUI

struct LockView: View {
    @EnvironmentObject private var appLock: AppLockStore
    @EnvironmentObject private var settings: AppSettings
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30
    /// One auto-prompt per lock episode (M02): re-arms only after the app locks again.
    @State private var hasAutoPrompted = false

    var body: some View {
        ZStack {
            ScreenBackground()

            FinanceCard {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(WCColor.primary.opacity(0.08))
                            .frame(width: 104, height: 104)

                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [WCColor.primary, WCColor.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(spacing: 8) {
                        Text("Wealth Compass")
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(settings.localized("Unlock with \(appLock.biometryName(appLanguage: settings.appLanguage))"))
                            .font(.subheadline)
                            .foregroundStyle(WCColor.textTertiary)
                    }

                    Button {
                        Task { await appLock.unlock(appLanguage: settings.appLanguage) }
                    } label: {
                        Label(
                            settings.localized("Unlock with \(appLock.biometryName(appLanguage: settings.appLanguage))"),
                            systemImage: appLock.biometrySymbolName()
                        )
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                    .disabled(appLock.isAuthenticating)

                    if let error = appLock.lastError {
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WCColor.destructive)
                            .frame(maxWidth: 280)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 340)
            .padding(24)
        }
        .task {
            guard !hasAutoPrompted else { return }
            hasAutoPrompted = true
            await appLock.unlock(appLanguage: settings.appLanguage)
        }
        .onChange(of: appLock.isUnlocked) { _, unlocked in
            // Re-arm the one-shot auto-prompt for the next lock episode.
            if !unlocked { hasAutoPrompted = false }
        }
    }
}
