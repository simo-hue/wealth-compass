import Foundation
import LocalAuthentication
import SwiftUI

/// Biometric app-lock store shared by iOS + macOS (M2).
///
/// The two platforms' lock stores were identical apart from their UserDefaults key,
/// so each platform subclasses this with its own key (keeping the iOS and macOS lock
/// settings independent) while the `LAContext` logic lives here once.
@MainActor
class BiometricLockStore: ObservableObject {
    @Published private(set) var isLockEnabled: Bool
    @Published private(set) var isUnlocked: Bool
    @Published var lastError: String?

    private let defaultsKey: String

    init(defaultsKey: String) {
        self.defaultsKey = defaultsKey
        let enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        isLockEnabled = enabled
        isUnlocked = !enabled
    }

    func biometryName(appLanguage: String?) -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return AppLocalization.string("Face ID", appLanguage: appLanguage)
        case .touchID:
            return AppLocalization.string("Touch ID", appLanguage: appLanguage)
        case .opticID:
            return AppLocalization.string("Optic ID", appLanguage: appLanguage)
        default:
            return AppLocalization.string("Biometrics", appLanguage: appLanguage)
        }
    }

    /// SF Symbol matching the device's biometry, so the lock UI doesn't hardcode "faceid" (L3).
    func biometrySymbolName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.fill"
        }
    }

    func enableLock(appLanguage: String?) async -> Bool {
        let success = await authenticate(
            reason: AppLocalization.string("Enable biometric protection for Wealth Compass.", appLanguage: appLanguage),
            appLanguage: appLanguage
        )
        if success {
            isLockEnabled = true
            isUnlocked = true
            lastError = nil
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
        return success
    }

    func disableLock() {
        isLockEnabled = false
        isUnlocked = true
        lastError = nil
        UserDefaults.standard.set(false, forKey: defaultsKey)
    }

    func lock() {
        guard isLockEnabled else { return }
        isUnlocked = false
    }

    func unlock(appLanguage: String?) async {
        if await authenticate(
            reason: AppLocalization.string("Unlock your local Wealth Compass data.", appLanguage: appLanguage),
            appLanguage: appLanguage
        ) {
            isUnlocked = true
            lastError = nil
        }
    }

    private func authenticate(reason: String, appLanguage: String?) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            lastError = error?.localizedDescription
                ?? AppLocalization.string("Biometric authentication is not available on this device.", appLanguage: appLanguage)
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                Task { @MainActor in
                    if let authenticationError {
                        self.lastError = authenticationError.localizedDescription
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
