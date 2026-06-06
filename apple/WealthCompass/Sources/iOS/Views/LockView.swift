import SwiftUI

struct LockView: View {
    @EnvironmentObject private var appLock: AppLockStore

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
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Your financial view is protected")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Button {
                        Task { await appLock.unlock() }
                    } label: {
                        Label("Unlock with \(appLock.biometryName)", systemImage: "faceid")
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WCColor.primary)

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
            await appLock.unlock()
        }
    }
}
