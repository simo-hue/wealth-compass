import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var backupURL: URL?
    @State private var backupError: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Currency") {
                    Picker("Base Currency", selection: $settings.currency) {
                        ForEach(Currency.allCases) { currency in
                            Text("\(currency.displayName) (\(currency.rawValue))").tag(currency)
                        }
                    }
                }

                Section("Privacy") {
                    Toggle(isOn: $settings.isPrivacyMode) {
                        Label("Privacy Mode", systemImage: settings.isPrivacyMode ? "eye.slash" : "eye")
                    }
                    .tint(WCColor.primary)
                }

                Section("Data") {
                    Button {
                        do {
                            backupURL = try finance.exportBackupURL()
                            backupError = nil
                        } catch {
                            backupError = error.localizedDescription
                        }
                    } label: {
                        Label("Prepare Backup", systemImage: "doc.badge.arrow.up")
                    }

                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Share Backup", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let backupError {
                        Text(backupError)
                            .font(.caption)
                            .foregroundStyle(WCColor.destructive)
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                }

                Section("Storage") {
                    HStack {
                        Label("Mode", systemImage: "internaldrive")
                        Spacer()
                        Text("Local Only")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Transactions", systemImage: "arrow.left.arrow.right")
                        Spacer()
                        Text("\(finance.data.transactions.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Text("\(finance.data.investments.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Crypto", systemImage: "bitcoinsign.circle")
                        Spacer()
                        Text("\(finance.data.crypto.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                    HStack {
                        Label("Snapshots", systemImage: "camera")
                        Spacer()
                        Text("\(finance.data.snapshots.count)")
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .preferredColorScheme(.dark)
            .alert("Delete All Data?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    finance.clearData()
                    backupURL = nil
                }
            } message: {
                Text("This permanently removes all local Wealth Compass data from this device.")
            }
        }
    }
}
