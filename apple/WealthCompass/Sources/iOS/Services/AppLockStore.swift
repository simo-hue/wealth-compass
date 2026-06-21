import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockStore: ObservableObject {
    @Published private(set) var isLockEnabled: Bool
    @Published private(set) var isUnlocked: Bool
    @Published var lastError: String?

    private enum Keys {
        static let biometricLockEnabled = "wc_mobile_biometric_lock_enabled"
    }

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Keys.biometricLockEnabled)
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

    func enableLock(appLanguage: String?) async -> Bool {
        let success = await authenticate(
            reason: AppLocalization.string("Enable biometric protection for Wealth Compass.", appLanguage: appLanguage),
            appLanguage: appLanguage
        )
        if success {
            isLockEnabled = true
            isUnlocked = true
            lastError = nil
            UserDefaults.standard.set(true, forKey: Keys.biometricLockEnabled)
        }
        return success
    }

    func disableLock() {
        isLockEnabled = false
        isUnlocked = true
        lastError = nil
        UserDefaults.standard.set(false, forKey: Keys.biometricLockEnabled)
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
