import SwiftUI

/// Stands in for the entire finance UI whenever `FinanceStore.loadState` isn't `.loaded` (WC-LOCK1).
///
/// The bug this exists to prevent: a failed load left `data` as an empty `FinancialData()`, and the
/// dashboard rendered it faithfully — €0 net worth, empty charts, no error anywhere. That is
/// indistinguishable from a brand-new account, so the user reasonably concluded their data was
/// gone. Refusing to draw any figure until the database has actually been read makes that class of
/// false report impossible, regardless of *why* the read failed.
///
/// Because this view replaces the whole app — including Settings — it **must** carry the recovery
/// actions that would otherwise be unreachable. A locked device resolves itself, but a corrupt
/// database or a full disk does not: without these, a permanent load failure would leave deleting
/// and reinstalling the app as the user's only move, destroying the very data they still have.
///
/// Shared by both root views so iOS and macOS cannot drift on it.
struct FinanceDataUnavailableView: View {
    let state: FinanceDataLoadState
    /// Whether an iCloud copy actually exists. Drives the reassurance copy, which must never
    /// promise a cloud backup to someone who never enabled sync.
    var isCloudSyncEnabled: Bool
    /// Manual retry. The app also retries automatically on unlock and on every foreground, so this
    /// is a reassurance affordance more than a functional necessity.
    var retry: () async -> Void
    /// Writes the PII-clean diagnostics file and hands back its URL, for the share sheet.
    var exportDiagnostics: () throws -> URL
    /// Local-only factory reset. Deliberately does **not** delete the iCloud copy: if the local DB
    /// is the broken part, the server's copy is the user's way back.
    var eraseLocalData: () async -> Void

    @State private var isRetrying = false
    @State private var diagnosticsFile: DiagnosticsFile?
    @State private var isConfirmingErase = false
    @State private var isErasing = false

    /// Wrapper so the exported file can drive `.sheet(item:)` / `ShareLink`.
    private struct DiagnosticsFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            switch state {
            // `.loaded` is reachable for the frame or two this view spends animating out, once the
            // root view has already switched to the real UI. Keeping the spinner there makes that
            // transition read as "finished loading" instead of flashing an empty background.
            case .notLoaded, .loaded:
                ProgressView()
                    .controlSize(.large)
                    .tint(WCColor.primary)
                Text("Loading your data…")
                    .font(.headline)
                    .foregroundStyle(.white)

            case .failed(let message, let isLocked):
                Image(systemName: isLocked ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isLocked ? WCColor.primary : Color.orange)
                Text(isLocked ? "Your Data Is Locked" : "Data Unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(verbatim: message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                reassurance(isLocked: isLocked)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Button {
                    guard !isRetrying else { return }
                    isRetrying = true
                    Task {
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    Text(isRetrying ? "Trying Again…" : "Try Again")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(WCColor.primary)
                .disabled(isRetrying)

                // Only for failures that do NOT resolve on their own. A locked device needs no
                // escape hatch — unlocking is the fix — and offering to erase there would invite
                // a destructive action for a problem that is about to disappear by itself.
                if !isLocked {
                    recoveryActions
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WCColor.background.ignoresSafeArea())
        .sheet(item: $diagnosticsFile) { file in
            ShareLink(item: file.url) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
            }
            .padding(40)
        }
        .alert("Erase Data on This Device?", isPresented: $isConfirmingErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) {
                isErasing = true
                Task {
                    await eraseLocalData()
                    isErasing = false
                }
            }
        } message: {
            Text("This deletes the unreadable database on this device and returns the app to onboarding. Your iCloud copy is NOT deleted — if iCloud sync was on, turning it back on restores your data from there.")
        }
        .accessibilityElement(children: .contain)
    }

    /// The reassurance line. Every clause has to be true for the *specific* failure being shown:
    /// telling someone whose database just failed to decode that "nothing has been changed" — and
    /// that a cloud copy exists when they never enabled sync — would push them toward deleting the
    /// app on a promise the app cannot keep.
    @ViewBuilder
    private func reassurance(isLocked: Bool) -> some View {
        if isLocked {
            Text("Nothing has been changed or deleted. Your data just can't be read until this device is unlocked.")
        } else if isCloudSyncEnabled {
            Text("Your data has not been deleted. iCloud sync is on, so a copy also exists in iCloud.")
        } else {
            Text("The file is still on this device and has not been deleted. iCloud sync is off, so there is no other copy — export diagnostics before erasing anything.")
        }
    }

    private var recoveryActions: some View {
        VStack(spacing: 12) {
            Button {
                // Best-effort: if even the diagnostics file can't be written, the button simply
                // does nothing rather than replacing one dead end with another.
                if let url = try? exportDiagnostics() {
                    diagnosticsFile = DiagnosticsFile(url: url)
                }
            } label: {
                Label("Export Diagnostics", systemImage: "doc.text")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(WCColor.primary)

            Button(role: .destructive) {
                isConfirmingErase = true
            } label: {
                Label("Erase and Start Over", systemImage: "trash")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isErasing)
        }
        .padding(.top, 4)
    }
}
