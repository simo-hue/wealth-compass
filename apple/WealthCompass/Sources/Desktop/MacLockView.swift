import SwiftUI

struct MacLockView: View {
    @EnvironmentObject private var appLock: MacAppLockStore
    @EnvironmentObject private var settings: AppSettings
    /// One auto-prompt per lock episode (M02): the view re-renders on every focus regain, so without
    /// this the biometric sheet would re-present unsolicited each time the window becomes key.
    @State private var hasAutoPrompted = false

    var body: some View {
        ZStack {
            ScreenBackground()

            FinanceCard {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(WCColor.primary)

                    VStack(spacing: 6) {
                        Text("Wealth Compass Tracker")
                            .font(.largeTitle.bold())
                        Text(settings.localized("Unlock with \(appLock.biometryName(appLanguage: settings.appLanguage))"))
                            .foregroundStyle(WCColor.textSecondary)
                    }

                    Button {
                        Task { await appLock.unlock(appLanguage: settings.appLanguage) }
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                            .font(.headline)
                            .frame(width: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)
                    .disabled(appLock.isAuthenticating)

                    if let error = appLock.lastError {
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WCColor.destructive)
                            .frame(maxWidth: 320)
                    }
                }
                .padding(24)
            }
            .frame(width: 430)
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
