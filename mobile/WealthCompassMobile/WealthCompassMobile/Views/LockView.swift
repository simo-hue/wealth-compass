import SwiftUI

struct LockView: View {
    @EnvironmentObject private var appLock: AppLockStore

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(WCColor.primary)

                VStack(spacing: 8) {
                    Text("Wealth Compass")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Unlock with \(appLock.biometryName)")
                        .font(.subheadline)
                        .foregroundStyle(WCColor.textSecondary)
                }

                Button {
                    Task { await appLock.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WCColor.primary)
                .frame(maxWidth: 260)

                if let error = appLock.lastError {
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WCColor.destructive)
                        .frame(maxWidth: 280)
                }
            }
            .padding(24)
        }
        .task {
            await appLock.unlock()
        }
    }
}
