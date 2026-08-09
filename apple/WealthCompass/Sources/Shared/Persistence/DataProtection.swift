import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Data-protection policy for every file this app owns, plus the helpers needed to survive the
/// window where those files are unreadable (WC-LOCK1).
///
/// ## Why this exists
///
/// The app registers for silent CloudKit pushes (`UIBackgroundModes: remote-notification`), so iOS
/// can cold-launch the process **while the device is locked**. Every persisted file used to be
/// written with `.completeFileProtectionUnlessOpen`, a class that permits *creating* a file while
/// locked but not *reopening* a closed one — so that background launch read its own database back
/// as `NSFileReadNoPermissionError` (Cocoa 257). Two failures followed: the finance store came up
/// empty (and never retried, so the user saw a zeroed dashboard when they later unlocked and
/// foregrounded that same process), and the sync-metadata store mistook the denial for "no file
/// yet" and overwrote a healthy metadata file with an empty one, forcing a full re-bootstrap.
///
/// The fix is `.completeFileProtectionUntilFirstUserAuthentication` — readable once the device has
/// been unlocked at least once since boot, which is the weakest window that still lets background
/// sync work at all. Content remains fully protected before that first unlock (a powered-off,
/// stolen device). Keychain-held market-data API keys are unaffected: they carry their own
/// accessibility class and are never covered by these options.
enum DataProtection {
    /// The canonical write options for the three files that must be readable during a background
    /// launch: the finance DB, the sync metadata, and the exchange-rate cache.
    ///
    /// Centralized so those three can't drift apart — they fail *independently* (each file carries
    /// its own protection class), and a split between them produces the nastiest states in this
    /// system: a readable DB alongside unreadable metadata leaves sync inert with no obvious cause.
    ///
    /// The `.pre-cloudkit-backup` sidecar is deliberately NOT a client of this constant. It is
    /// written once, only after a successful decode, and never read back by the app, so it keeps
    /// the stricter `.completeFileProtectionUnlessOpen` — see
    /// `LocalFinancePersistence.createMigrationBackupIfNeeded`. Do not "fix" that inconsistency.
    static let atomicWriteOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]

    /// True when `error` is the filesystem refusing a read we are otherwise entitled to make —
    /// on iOS, overwhelmingly "the device is locked and this file's protection class isn't
    /// available yet".
    ///
    /// Deliberately **not** load-bearing for correctness (see `FinanceStore.retryLoadIfNeeded`):
    /// retries happen for any failure, because re-reading is idempotent and a genuinely broken
    /// file simply fails again. This classification only picks which message the user reads, so a
    /// future change to the reported code degrades the copy, never the recovery. That matters on
    /// macOS too, where a sandbox denial reports the same code with a very different meaning.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return true
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
            return true
        }
        // Cocoa wraps the POSIX failure in `NSUnderlyingErrorKey` for some read paths.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== nsError {
            return isPermissionDenied(underlying)
        }
        return false
    }

    /// A compact, PII-free description (`domain code`) for the diagnostics export. Never includes
    /// the localized message, which can embed a file path.
    static func diagnosticCode(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    /// Best-effort upgrade of an **existing** file to the current protection class.
    ///
    /// A file's protection class is fixed when it is created, so changing `atomicWriteOptions`
    /// alone would only take effect once each file happens to be rewritten — leaving an install
    /// that syncs but is never edited stuck on the old class indefinitely, which is precisely the
    /// read-only-consumer profile that hits this bug. Idempotent and intentionally unconditional
    /// (two cheap syscalls at launch): a `UserDefaults` "already migrated" flag would permanently
    /// skip the migration if the one attempt it guarded had failed.
    ///
    /// Must run while protected data is available — re-wrapping the file key needs the class key
    /// unlocked — so callers invoke it only after a successful read. Failures are swallowed by
    /// design: the app is fully functional without the upgrade, and the next write applies the new
    /// class anyway.
    static func upgradeProtectionClass(at url: URL, fileManager: FileManager = .default) {
        #if os(iOS)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let current = attributes?[.protectionKey] as? FileProtectionType
        guard current != .completeUntilFirstUserAuthentication else { return }
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}

/// Whether the OS will currently let us read files in the protected classes, and how to learn that
/// it changed. A thin platform shim: real on iOS, permanently `true` on macOS, which has no
/// lock-time protection classes (FileVault gates the whole volume at login instead).
///
/// `@MainActor` throughout because `UIApplication` is — every caller (`FinanceStore`) is already on
/// the main actor, so this costs nothing and keeps the shim free of isolation escapes.
@MainActor
enum ProtectedDataAvailability {
    /// `false` only on iOS, only while the device is locked and the protection classes are sealed.
    static var isAvailable: Bool {
        #if os(iOS)
        UIApplication.shared.isProtectedDataAvailable
        #else
        true
        #endif
    }

    /// Posted when files become readable again (device unlocked). `nil` where the concept doesn't
    /// exist, so callers simply skip observation.
    static var didBecomeAvailableNotification: Notification.Name? {
        #if os(iOS)
        UIApplication.protectedDataDidBecomeAvailableNotification
        #else
        nil
        #endif
    }

    /// `"fg"` / `"bg"` / `"inactive"` for the diagnostics launch marker — the single most useful
    /// bit when reading an export after the fact, because it distinguishes a normal user launch
    /// from the silent-push background launch that triggers this whole failure mode.
    static var launchContext: String {
        #if os(iOS)
        switch UIApplication.shared.applicationState {
        case .active: return "fg"
        case .inactive: return "inactive"
        case .background: return "bg"
        @unknown default: return "?"
        }
        #else
        return "fg"
        #endif
    }
}
