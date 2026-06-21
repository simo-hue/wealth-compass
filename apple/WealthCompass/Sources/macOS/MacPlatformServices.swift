import AppKit
import Foundation
import LocalAuthentication
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let macRecurringTransactionNotificationReceived = Notification.Name(
        "wealthCompass.mac.recurringTransactionNotificationReceived"
    )
}

final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .macRecurringTransactionNotificationReceived, object: nil)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .macRecurringTransactionNotificationReceived, object: nil)
        completionHandler()
    }
}

actor MacRecurringTransactionNotificationService {
    static let shared = MacRecurringTransactionNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "wealth-compass-mac-recurring-"

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func sync(
        schedules: [RecurringTransaction],
        currencyCode: String,
        showAmounts: Bool,
        now: Date = Date()
    ) async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
            return
        }

        let upcoming = schedules
            .filter { schedule in
                schedule.isActive
                    && !schedule.isCompleted
                    && schedule.notificationsEnabled
                    && schedule.nextDueDate > now
                    && (schedule.endDate.map { schedule.nextDueDate <= $0 } ?? true)
            }
            .sorted { $0.nextDueDate < $1.nextDueDate }
            .prefix(60)

        for schedule in upcoming {
            let content = UNMutableNotificationContent()
            let appLanguage = UserDefaults.standard.string(forKey: "wc_mobile_app_language")
            content.title = AppLocalization.string("Recurring \(schedule.type.localizedTitle(appLanguage: appLanguage)) due", appLanguage: appLanguage)
            if showAmounts {
                let amount = schedule.amount.formatted(
                    FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
                )
                content.body = AppLocalization.string("\(schedule.category): \(amount). Wealth Compass records it while the app is active.", appLanguage: appLanguage)
            } else {
                content.body = AppLocalization.string("\(schedule.category) is scheduled. Open Wealth Compass to review it.", appLanguage: appLanguage)
            }
            content.sound = .default
            content.userInfo = ["recurringTransactionID": schedule.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.nextDueDate
            )
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: schedule.id),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(scheduleID: UUID) {
        let identifier = notificationIdentifier(for: scheduleID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notificationIdentifier(for scheduleID: UUID) -> String {
        "\(identifierPrefix)\(scheduleID.uuidString)"
    }
}

@MainActor
final class MacAppLockStore: ObservableObject {
    @Published private(set) var isLockEnabled: Bool
    @Published private(set) var isUnlocked: Bool
    @Published var lastError: String?

    private enum Keys {
        static let biometricLockEnabled = "wc_mac_biometric_lock_enabled"
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
        case .touchID:
            return AppLocalization.string("Touch ID", appLanguage: appLanguage)
        case .faceID:
            return AppLocalization.string("Face ID", appLanguage: appLanguage)
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
                ?? AppLocalization.string("Biometric authentication is not available on this Mac.", appLanguage: appLanguage)
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, authenticationError in
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

struct MacLockView: View {
    @EnvironmentObject private var appLock: MacAppLockStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            ScreenBackground()

            FinanceCard {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(WCColor.primary)

                    VStack(spacing: 6) {
                        Text("Wealth Compass")
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
            await appLock.unlock(appLanguage: settings.appLanguage)
        }
    }
}
