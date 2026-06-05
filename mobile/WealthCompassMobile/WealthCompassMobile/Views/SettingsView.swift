import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockStore
    @State private var backupURL: URL?
    @State private var backupError: String?
    @State private var importMode: FinanceImportMode = .merge
    @State private var showingImportOptions = false
    @State private var showingFileImporter = false
    @State private var importAlert: ImportAlertState?
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

                Section("Security") {
                    Toggle(isOn: biometricLockBinding) {
                        Label("\(appLock.biometryName) App Lock", systemImage: "lock.shield")
                    }
                    .tint(WCColor.primary)

                    if let error = appLock.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WCColor.destructive)
                    } else {
                        Text("When enabled, Wealth Compass locks whenever the app leaves the foreground.")
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }

                Section("Custom Categories") {
                    categoryGroup(title: "Income", type: .income, categories: settings.customIncomeCategories)
                    categoryGroup(title: "Expense", type: .expense, categories: settings.customExpenseCategories)
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

                    Button {
                        showingImportOptions = true
                    } label: {
                        Label("Import JSON Backup", systemImage: "doc.badge.plus")
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
                        Label("Liabilities", systemImage: "creditcard")
                        Spacer()
                        Text("\(finance.data.liabilities.count)")
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
            .confirmationDialog("Import JSON Backup", isPresented: $showingImportOptions, titleVisibility: .visible) {
                Button("Merge With Existing Data") {
                    importMode = .merge
                    showingFileImporter = true
                }

                Button("Replace Existing Data", role: .destructive) {
                    importMode = .replace
                    showingFileImporter = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Merge adds new records and updates matching IDs. Replace clears current local finance data before importing.")
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { result in
                handleImportSelection(result)
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var biometricLockBinding: Binding<Bool> {
        Binding {
            appLock.isLockEnabled
        } set: { isEnabled in
            if isEnabled {
                Task { await appLock.enableLock() }
            } else {
                appLock.disableLock()
            }
        }
    }

    private func categoryGroup(title: String, type: TransactionType, categories: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if categories.isEmpty {
                Text("No custom \(title.lowercased()) categories yet.")
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
            } else {
                ForEach(categories, id: \.self) { category in
                    HStack {
                        Text(category)
                        Spacer()
                        Button(role: .destructive) {
                            settings.removeCustomTransactionCategory(category, for: type)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let result = try finance.importBackup(from: url, mode: importMode, settings: settings)
                backupURL = nil
                backupError = nil
                importAlert = ImportAlertState(title: "Import Complete", message: result.message)
            } catch {
                importAlert = ImportAlertState(
                    title: "Import Failed",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        case .failure(let error):
            importAlert = ImportAlertState(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

private struct ImportAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
