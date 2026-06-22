import Foundation

/// iOS biometric app-lock — all logic lives in the shared `BiometricLockStore` (M2);
/// this only fixes the iOS-specific UserDefaults key.
@MainActor
final class AppLockStore: BiometricLockStore {
    init() {
        super.init(defaultsKey: "wc_mobile_biometric_lock_enabled")
    }
}
