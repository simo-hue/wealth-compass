import SwiftUI

/// The export sheet shared by both apps.
///
/// Progressive disclosure rather than a wizard: the format picker is always visible and everything
/// under it is a consequence of that one choice, so the user never pages forward to discover that
/// half the controls did not apply to them.
///
/// It deliberately takes no store. The two facts it needs from `AppSettings` arrive as plain
/// values, which is what lets a single view serve iOS and macOS and keeps it drivable from a
/// preview or a test without standing up `FinanceStore`.
struct ExportOptionsView: View {
    @Binding var options: ReportExportOptions
    let isPrivacyModeOn: Bool
    let appLanguage: String?
    let onCancel: () -> Void
    let onExport: () -> Void

    /// Scope is view state, not model state: "Full report" and a hand-picked set that happens to
    /// hold every section are the same `options.sections`. Deriving the segment from the model
    /// would therefore collapse the picker back to "Full report" — and hide the section list — the
    /// instant the user re-ticked the last box they had cleared.
    @State private var scope: ExportScope = .fullReport

    /// Held here so that leaving "Custom Range" and coming back does not discard the bounds the
    /// user already typed; `options.dateRange` only carries them while custom is selected.
    @State private var customStart = ExportOptionsView.defaultCustomStart
    @State private var customEnd = Date()

    var body: some View {
        container
            .tint(WCColor.primary)
            .preferredColorScheme(.dark)
            .appLanguage(appLanguage)
            .onAppear(perform: syncStateFromOptions)
    }

    // MARK: - Platform chrome

    /// The only thing that differs per platform: iOS gets a navigation bar, macOS a button bar and
    /// an explicit size, because a macOS sheet does not size itself from its content.
    @ViewBuilder
    private var container: some View {
        #if os(iOS)
        NavigationStack {
            optionsForm
                .navigationTitle("Export Report")
                .navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden)
                .background(ScreenBackground())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Export", action: onExport)
                            .disabled(!options.isValid)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            optionsForm
                .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Export", action: onExport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!options.isValid)
            }
            .padding()
        }
        .frame(width: 460, height: 560)
        #endif
    }

    // MARK: - Options

    private var optionsForm: some View {
        Form {
            formatSection

            if options.format == .pdf {
                if isPrivacyModeOn {
                    privacySection
                }
                scopeSection
                periodSection
            } else {
                backupSection
            }
        }
        .onChange(of: scope) { applyScope() }
        .onChange(of: customStart) { syncCustomRange() }
        .onChange(of: customEnd) { syncCustomRange() }
    }

    private var formatSection: some View {
        Section {
            // Format names are the same acronym in every locale the app ships, so they are
            // verbatim rather than forty identical catalogue entries.
            Picker("Format", selection: $options.format) {
                Text(verbatim: "PDF").tag(ReportExportFormat.pdf)
                Text(verbatim: "JSON").tag(ReportExportFormat.json)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Format")
        }
    }

    /// Privacy Mode blanks amounts in the UI, and a reader who has only ever seen the app that way
    /// would reasonably expect the same of the file. Warn instead of redacting: a report without
    /// figures is not a report.
    private var privacySection: some View {
        Section {
            note(
                symbol: "eye.slash",
                tint: WCColor.warning,
                text: "Privacy Mode hides amounts on screen, but the PDF contains your real figures."
            )
        }
    }

    private var scopeSection: some View {
        Section {
            Picker("Scope", selection: $scope) {
                Text("Full Report").tag(ExportScope.fullReport)
                Text("Choose Sections").tag(ExportScope.sections)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if scope == .sections {
                ForEach(ReportSection.allCases) { section in
                    sectionRow(section)
                }
            }
        } header: {
            Text("Contents")
        } footer: {
            if scope == .sections && options.sections.isEmpty {
                Text("Select at least one section to export.")
                    .foregroundStyle(WCColor.destructive)
            }
        }
    }

    private func sectionRow(_ section: ReportSection) -> some View {
        let isIncluded = options.sections.contains(section)

        return Button {
            toggle(section)
        } label: {
            HStack(spacing: 12) {
                Label(localized(section.titleKey), systemImage: section.symbolName)
                    .foregroundStyle(WCColor.textPrimary)

                Spacer(minLength: 12)

                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isIncluded ? WCColor.primary : WCColor.textFaint)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }

    private var periodSection: some View {
        Section {
            Picker("Date Range", selection: dateRangeChoice) {
                ForEach(ReportDateRange.presets, id: \.titleKey) { preset in
                    Text(localized(preset.titleKey)).tag(ExportDateRangeChoice(preset))
                }

                Text(localized(customRangeTitleKey)).tag(ExportDateRangeChoice.custom)
            }

            if options.dateRange.isCustom {
                DatePicker("Start Date", selection: $customStart, displayedComponents: .date)
                DatePicker("End Date", selection: $customEnd, displayedComponents: .date)
            }
        } header: {
            Text("Period")
        } footer: {
            Text("The period applies to the transaction ledger only. Holdings are point-in-time and are always reported in full.")
        }
    }

    /// JSON is the restore path for `FinanceStore.importFile`, so it is never partial — a backup
    /// missing sections or clipped to a date range would silently lose records on import.
    private var backupSection: some View {
        Section {
            note(
                symbol: "arrow.counterclockwise",
                tint: WCColor.accent,
                text: "JSON is always a complete backup of every record, so the section and period choices do not apply."
            )
        }
    }

    private func note(symbol: String, tint: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)

            Text(text)
                .font(.callout)
                .foregroundStyle(WCColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bindings and state

    /// `ReportDateRange` carries associated dates and is only `Equatable`, so the picker selects a
    /// payload-free stand-in and the dates are reattached on write.
    private var dateRangeChoice: Binding<ExportDateRangeChoice> {
        Binding {
            ExportDateRangeChoice(options.dateRange)
        } set: { choice in
            options.dateRange = choice.range(start: customStart, end: customEnd)
        }
    }

    private var customRangeTitleKey: String {
        ReportDateRange.custom(start: customStart, end: customEnd).titleKey
    }

    private func syncStateFromOptions() {
        scope = options.isFullReport ? .fullReport : .sections

        if case let .custom(start, end) = options.dateRange {
            customStart = start
            customEnd = end
        }
    }

    /// Only the full-report direction writes back: switching to "Choose sections" keeps whatever
    /// is currently selected so the user starts from the full set and unticks.
    private func applyScope() {
        guard scope == .fullReport else { return }
        options.sections = Set(ReportSection.allCases)
    }

    private func toggle(_ section: ReportSection) {
        if options.sections.contains(section) {
            options.sections.remove(section)
        } else {
            options.sections.insert(section)
        }
    }

    private func syncCustomRange() {
        guard options.dateRange.isCustom else { return }
        options.dateRange = .custom(start: customStart, end: customEnd)
    }

    /// The model hands these titles over as plain `String` keys, which `Text(_:)` would render
    /// verbatim; resolve them through the app-language-aware API like the rest of the settings UI.
    private func localized(_ key: String) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: key), appLanguage: appLanguage)
    }

    private static var defaultCustomStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .month, value: -12, to: today) ?? today
    }
}

// MARK: - Selection stand-ins

private enum ExportScope: Hashable {
    case fullReport
    case sections
}

private enum ExportDateRangeChoice: Hashable {
    case allTime
    case thisYear
    case last12Months
    case custom

    init(_ range: ReportDateRange) {
        switch range {
        case .allTime: self = .allTime
        case .thisYear: self = .thisYear
        case .last12Months: self = .last12Months
        case .custom: self = .custom
        }
    }

    func range(start: Date, end: Date) -> ReportDateRange {
        switch self {
        case .allTime: return .allTime
        case .thisYear: return .thisYear
        case .last12Months: return .last12Months
        case .custom: return .custom(start: start, end: end)
        }
    }
}

// MARK: - Cancellation

/// Thread-safe flag polled by the renderer between pages.
///
/// The render runs on a detached task while the Cancel button lives on the main actor, so the
/// signal has to cross actors. A lock-guarded box is the smallest thing that does that correctly.
final class ExportCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func isSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Progress

/// Drives the "Page 34 of 112" sheet.
///
/// The page total is known before a single page is drawn, because pagination is a measure pass —
/// so this is genuinely determinate rather than an indeterminate spinner.
@MainActor
final class ExportProgress: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var isCancelling = false

    private let flag = ExportCancellationFlag()

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    /// Passed to the renderer; safe to call from the detached render task.
    nonisolated var cancellationCheck: @Sendable () -> Bool {
        let flag = self.flag
        return { flag.isSet() }
    }

    func cancel() {
        isCancelling = true
        flag.set()
    }

    fileprivate func report(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

// MARK: - Coordinator

/// Owns the whole export interaction so iOS and macOS share it rather than each re-implementing
/// the sheet plumbing, the delayed progress presentation and the cancellation wiring. Only the
/// final delivery step (share sheet vs. save panel) stays platform-specific.
@MainActor
final class ExportCoordinator: ObservableObject {
    @Published var options = ReportExportOptions()
    @Published var isShowingOptions = false
    @Published var progress: ExportProgress?
    /// True from the moment an export starts until its file is handed back.
    ///
    /// Both entry points can fire again while one is in flight — the Export button stays live
    /// during the sheet's dismissal animation, macOS binds it to `.defaultAction` so key-repeat on
    /// Return re-triggers it, and ⌘E is never disabled. Overlapping exports used to race on the
    /// same output path; they now get distinct paths, but a second run would still fight the first
    /// for the progress sheet, so it is refused outright.
    @Published private(set) var isExporting = false

    /// Progress is only presented once an export has been running long enough to be worth
    /// interrupting the user for. Most exports finish well inside this, and a sheet that flashes
    /// up and vanishes reads worse than no sheet at all.
    private static let progressPresentationDelay: Duration = .milliseconds(400)

    func presentOptions() {
        guard !isExporting else { return }
        options = ReportExportOptions()
        isShowingOptions = true
    }

    /// Builds the file the user asked for. Returns nil when the export was cancelled.
    ///
    /// Throws whatever the store throws so each platform can surface it in its own alert style.
    func export(finance: FinanceStore, settings: AppSettings) async throws -> URL? {
        guard !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        isShowingOptions = false

        switch options.format {
        case .json:
            return try await finance.exportBackupURL()

        case .pdf:
            let tracker = ExportProgress()
            let reveal = Task { [weak self] in
                try? await Task.sleep(for: Self.progressPresentationDelay)
                guard !Task.isCancelled else { return }
                self?.progress = tracker
            }
            defer {
                reveal.cancel()
                progress = nil
            }

            do {
                return try await finance.exportReportURL(
                    options: options,
                    settings: settings,
                    progress: { completed, total in
                        Task { @MainActor in tracker.report(completed: completed, total: total) }
                    },
                    isCancelled: tracker.cancellationCheck)
            } catch ReportRenderError.cancelled {
                return nil
            }
        }
    }
}

// MARK: - Progress sheet

/// Small determinate sheet with a working Cancel, shared by both platforms.
struct ExportProgressView: View {
    @ObservedObject var progress: ExportProgress
    let appLanguage: String?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Preparing Report")
                .font(.headline)
                .foregroundStyle(WCColor.textPrimary)

            ProgressView(value: progress.fraction)
                .tint(WCColor.primary)

            Text(pageLine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(WCColor.textSecondary)

            Button(role: .cancel, action: onCancel) {
                Text("Cancel")
            }
            .disabled(progress.isCancelling)
        }
        .padding(24)
        .frame(width: 300)
        .preferredColorScheme(.dark)
        .appLanguage(appLanguage)
    }

    private var pageLine: String {
        guard progress.total > 0 else {
            return AppLocalization.string("Preparing…", appLanguage: appLanguage)
        }
        // The reader's digits, like the identical string in the rendered footer
        // (`PDFReportRenderer.drawFooter`): interpolating the `Int` shapes nothing, so this sheet
        // counted pages in Latin digits under a fully Arabic-Indic UI.
        let locale = AppLocalization.effectiveLocale(appLanguage: appLanguage)
        return String(format: AppLocalization.string("Page %1$@ of %2$@", appLanguage: appLanguage),
                      progress.completed.formatted(.number.locale(locale)),
                      progress.total.formatted(.number.locale(locale)))
    }
}
