import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var importMode: FinanceImportMode = .merge
    @State private var finnhubKey = ""
    @State private var coinGeckoKey = ""
    @State private var alert: MacSettingsAlert?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }

            dataSettings
                .tabItem { Label("Data", systemImage: "internaldrive") }

            syncSettings
                .tabItem { Label("iCloud", systemImage: "icloud") }
        }
        .frame(width: 640, height: 520)
        .onAppear(perform: loadCredentials)
        .alert(item: $alert) {
            Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Delete all local finance data?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete All Data", role: .destructive) {
                finance.clearData()
            }
        } message: {
            Text("This removes the local Mac database. This action cannot be undone.")
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Display") {
                Picker("Base Currency", selection: $settings.currency) {
                    ForEach(Currency.allCases) {
                        Text("\($0.displayName) (\($0.rawValue))").tag($0)
                    }
                }

                Toggle("Privacy Mode", isOn: $settings.isPrivacyMode)
            }

            Section("Market Data Credentials") {
                SecureField("Finnhub API Key", text: $finnhubKey)
                SecureField("CoinGecko API Key", text: $coinGeckoKey)

                HStack {
                    Spacer()
                    Button("Save to Keychain", action: saveCredentials)
                }

                Text("Credentials are stored in the macOS Keychain and never written to the finance database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var dataSettings: some View {
        Form {
            Section("Import and Export") {
                Picker("Import Behavior", selection: $importMode) {
                    Text("Merge with local data").tag(FinanceImportMode.merge)
                    Text("Replace local data").tag(FinanceImportMode.replace)
                }

                HStack {
                    Button("Import JSON...", action: importBackup)
                    Button("Export JSON...", action: exportBackup)
                }
            }

            Section("Local Storage") {
                LabeledContent("Mode", value: "Local Only")
                LabeledContent("Transactions", value: "\(finance.data.transactions.count)")
                LabeledContent("Investments", value: "\(finance.data.investments.count)")
                LabeledContent("Crypto Holdings", value: "\(finance.data.crypto.count)")

                Text(finance.storageLocationDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Button("Delete All Local Data...", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var syncSettings: some View {
        Form {
            Section("Status") {
                LabeledContent("iCloud Sync", value: "Not Configured")
                LabeledContent("Local Database", value: "Active")
            }

            Section("Planned Architecture") {
                Text(
                    "The app now stores data behind a shared persistence interface. "
                        + "CloudKit sync can be added without changing the iPhone or Mac interfaces."
                )
                Text(
                    "The production sync layer should use one CloudKit record per transaction, "
                        + "holding, liability, recurring schedule, and snapshot so edits can merge safely."
                )
            }

            Section {
                Text("An iCloud container and App Store provisioning profile are required before sync can be enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadCredentials() {
        finnhubKey = (try? KeychainCredentialStore.shared.string(for: .finnhubAPIKey)) ?? ""
        coinGeckoKey = (try? KeychainCredentialStore.shared.string(for: .coingeckoAPIKey)) ?? ""
    }

    private func saveCredentials() {
        do {
            try KeychainCredentialStore.shared.save(finnhubKey, for: .finnhubAPIKey)
            try KeychainCredentialStore.shared.save(coinGeckoKey, for: .coingeckoAPIKey)
            alert = MacSettingsAlert(title: "Credentials Saved", message: "The API keys were saved to the macOS Keychain.")
        } catch {
            alert = MacSettingsAlert(title: "Unable to Save", message: error.localizedDescription)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try finance.importBackup(from: url, mode: importMode, settings: settings)
            alert = MacSettingsAlert(title: "Import Complete", message: result.message)
        } catch {
            alert = MacSettingsAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func exportBackup() {
        do {
            let temporaryURL = try finance.exportBackupURL()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = temporaryURL.lastPathComponent

            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
            alert = MacSettingsAlert(title: "Backup Exported", message: destination.path)
        } catch {
            alert = MacSettingsAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}

private struct MacSettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
