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
            content.title = String(localized: "Recurring \(schedule.type.title) due")
            if showAmounts {
                let amount = schedule.amount.formatted(
                    FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
                )
                content.body = String(localized: "\(schedule.category): \(amount). Wealth Compass records it while the app is active.")
            } else {
                content.body = String(localized: "\(schedule.category) is scheduled. Open Wealth Compass to review it.")
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

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID:
            return String(localized: "Touch ID")
        case .faceID:
            return String(localized: "Face ID")
        case .opticID:
            return String(localized: "Optic ID")
        default:
            return String(localized: "Biometrics")
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
            lastError = error?.localizedDescription ?? String(localized: "Biometric authentication is not available on this Mac.")
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
                        Text("Unlock with \(appLock.biometryName)")
                            .foregroundStyle(WCColor.textSecondary)
                    }

                    Button {
                        Task { await appLock.unlock() }
                    } label: {
                        Label("Unlock", systemImage: appLock.biometryName == "Touch ID" ? "touchid" : "lock.open")
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
            await appLock.unlock()
        }
    }
}
