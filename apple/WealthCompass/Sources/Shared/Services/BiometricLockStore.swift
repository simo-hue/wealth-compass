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
    /// True while an `LAContext` evaluation is in flight (M02): the UI disables the Unlock button and
    /// a second concurrent `authenticate` early-returns instead of racing a duplicate system prompt.
    @Published private(set) var isAuthenticating = false
    @Published var lastError: String?

    private let defaultsKey: String
    /// Namespaced under `defaultsKey` so iOS and macOS keep independent enrollment baselines (M17).
    private var domainStateKey: String { "\(defaultsKey).biometryDomainState" }

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
        let result = await authenticate(
            reason: AppLocalization.string("Enable biometric protection for Wealth Compass.", appLanguage: appLanguage),
            appLanguage: appLanguage
        )
        if result.success {
            isLockEnabled = true
            isUnlocked = true
            lastError = nil
            UserDefaults.standard.set(true, forKey: defaultsKey)
            // Capture the enrolled-biometric baseline so a later enrollment change is detectable (M17).
            storeDomainStateBaseline(result.domainState)
        }
        return result.success
    }

    /// Non-authenticated state reset. Reserved for the factory-erase flow (already confirmed,
    /// and `resetToDefaults` clears the preference anyway). The user-facing toggle must use
    /// `confirmDisableLock` instead.
    func disableLock() {
        isLockEnabled = false
        isUnlocked = true
        lastError = nil
        UserDefaults.standard.set(false, forKey: defaultsKey)
        // Drop the enrollment baseline so re-enabling captures a fresh one (M17).
        UserDefaults.standard.removeObject(forKey: domainStateKey)
    }

    /// WC-L3: turning the lock off from Settings requires authentication first, mirroring
    /// `enableLock` — otherwise anyone holding the unlocked device could silently remove the
    /// protection. With WC-L2 the prompt offers a device-passcode fallback.
    @discardableResult
    func confirmDisableLock(appLanguage: String?) async -> Bool {
        let result = await authenticate(
            reason: AppLocalization.string("Turn off app protection for Wealth Compass.", appLanguage: appLanguage),
            appLanguage: appLanguage
        )
        if result.success {
            disableLock()
        }
        return result.success
    }

    func lock() {
        guard isLockEnabled else { return }
        isUnlocked = false
    }

    func unlock(appLanguage: String?) async {
        let result = await authenticate(
            reason: AppLocalization.string("Unlock your local Wealth Compass data.", appLanguage: appLanguage),
            appLanguage: appLanguage
        )
        guard result.success else { return }

        // M17: a change in the enrolled-biometric set (`evaluatedPolicyDomainState`) means a
        // fingerprint was added or Face ID re-enrolled. Don't silently trust it — re-baseline, warn,
        // and require one more explicit unlock. A first-ever capture (lock enabled by an older build)
        // and a passcode-only device (nil token) both compare equal and unlock normally.
        let newToken = domainStateToken(result.domainState)
        if let baseline = storedDomainStateToken(), baseline != newToken {
            storeDomainStateBaseline(result.domainState)
            lastError = AppLocalization.string(
                "Biometric enrollment changed. Unlock again to confirm it's you.",
                appLanguage: appLanguage
            )
            return
        }

        storeDomainStateBaseline(result.domainState)
        isUnlocked = true
        lastError = nil
    }

    private struct AuthResult {
        let success: Bool
        /// `LAContext.evaluatedPolicyDomainState` captured on success (nil otherwise / passcode-only).
        let domainState: Data?
    }

    private func authenticate(reason: String, appLanguage: String?) async -> AuthResult {
        // M02: serialize evaluations so the auto-prompt `.task` and a manual Unlock tap can't launch
        // two concurrent `LAContext` prompts; a second in-flight call is a no-op.
        guard !isAuthenticating else { return AuthResult(success: false, domainState: nil) }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // WC-L2: `.deviceOwnerAuthentication` is biometrics WITH an automatic device-passcode
        // fallback, so a Face/Touch ID lockout can't strand the user out of the app. We no
        // longer suppress the fallback button (`localizedFallbackTitle`).
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription
                ?? AppLocalization.string("Biometric authentication is not available on this device.", appLanguage: appLanguage)
            return AuthResult(success: false, domainState: nil)
        }

        let success: Bool = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                Task { @MainActor in
                    if let authenticationError {
                        self.lastError = authenticationError.localizedDescription
                    }
                    continuation.resume(returning: success)
                }
            }
        }

        // `evaluatedPolicyDomainState` is populated only after a successful evaluation; read it here
        // on the MainActor (the local `context` is still in scope) so the non-Sendable LAContext is
        // never captured across the concurrency hop above. It's soft-deprecated in iOS 18 / macOS 15
        // in favor of `LAContext.domainState`, which doesn't exist on our iOS 17 / macOS 14 floor —
        // so the still-functional original is intentional and its single deprecation warning expected.
        let domainState = success ? context.evaluatedPolicyDomainState : nil
        return AuthResult(success: success, domainState: domainState)
    }

    // MARK: - Enrollment-change baseline (M17)

    /// A stable token for the enrolled-biometric domain state — base64 of the `Data`, or a fixed
    /// sentinel for the passcode-only (nil) case — so a captured-but-nil state is distinct from a
    /// never-captured one (`string(forKey:)` returning nil).
    private func domainStateToken(_ domainState: Data?) -> String {
        domainState?.base64EncodedString() ?? "passcode-only"
    }

    private func storedDomainStateToken() -> String? {
        UserDefaults.standard.string(forKey: domainStateKey)
    }

    private func storeDomainStateBaseline(_ domainState: Data?) {
        UserDefaults.standard.set(domainStateToken(domainState), forKey: domainStateKey)
    }
}
