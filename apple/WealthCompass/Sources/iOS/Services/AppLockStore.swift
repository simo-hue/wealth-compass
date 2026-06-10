import Foundation
import LocalAuthentication

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

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Face ID")
        case .touchID: return String(localized: "Touch ID")
        case .opticID: return String(localized: "Optic ID")
        default: return String(localized: "Biometrics")
        }
    }

    func enableLock() async -> Bool {
        let success = await authenticate(reason: String(localized: "Enable biometric protection for Wealth Compass."))
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

    func unlock() async {
        if await authenticate(reason: String(localized: "Unlock your local Wealth Compass data.")) {
            isUnlocked = true
            lastError = nil
        }
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            lastError = error?.localizedDescription ?? String(localized: "Biometric authentication is not available on this device.")
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
