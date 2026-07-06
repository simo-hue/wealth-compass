import SwiftUI

struct MacRecurringTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let existingSchedule: RecurringTransaction?
    let onSave: (RecurringTransaction) -> Void

    private static let customCategoryTag = "__wealth_compass_mac_recurring_custom_category__"

    @State private var type: TransactionType
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var startDate: Date
    @State private var frequency: RecurringTransactionFrequency
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var notificationsEnabled: Bool
    @State private var currency: Currency
    @State private var hasInitializedCurrency = false
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

    init(
        schedule: RecurringTransaction? = nil,
        onSave: @escaping (RecurringTransaction) -> Void
    ) {
        existingSchedule = schedule
        self.onSave = onSave

        let defaultStartDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let initialStartDate = schedule?.startDate ?? defaultStartDate
        let defaultEndDate = Calendar.current.date(byAdding: .year, value: 1, to: initialStartDate) ?? initialStartDate

        _type = State(initialValue: schedule?.type ?? .expense)
        _amount = State(initialValue: schedule.map { AmountInputFormatter.string($0.amount) } ?? "")
        _category = State(initialValue: schedule?.category ?? "Food")
        _note = State(initialValue: schedule?.description ?? "")
        _startDate = State(initialValue: initialStartDate)
        _frequency = State(initialValue: schedule?.frequency ?? .monthly)
        _hasEndDate = State(initialValue: schedule?.endDate != nil)
        _endDate = State(initialValue: schedule?.endDate ?? defaultEndDate)
        _notificationsEnabled = State(initialValue: schedule?.notificationsEnabled ?? true)
        _currency = State(initialValue: schedule?.currency ?? .eur)
    }

    private var categories: [String] {
        settings.transactionCategories(for: type)
    }

    private var trimmedCustomCategory: String {
        customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCustomCategorySelected: Bool {
        category == Self.customCategoryTag
    }

    private var currentCategoryName: String {
        isCustomCategorySelected ? trimmedCustomCategory : category
    }

    private var parsedAmount: Decimal? {
        MoneyParser.decimal(from: amount)
    }

    private var normalizedEndDate: Date? {
        guard hasEndDate else { return nil }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate)
    }

    private var isSaveDisabled: Bool {
        guard let parsedAmount, parsedAmount > 0 else { return true }
        return currentCategoryName.isEmpty
            // Allow same-day scheduling (deep-audit L09): compare by calendar day, not instant — the
            // builder forward-clamps a same-day past time to the next occurrence, so only a genuinely
            // past calendar day should block Save.
            || (existingSchedule == nil && Calendar.current.startOfDay(for: startDate) < Calendar.current.startOfDay(for: Date()))
            || (normalizedEndDate.map { $0 < startDate } ?? false)
    }

    private var validationMessage: String? {
        if !amount.isEmpty, (parsedAmount ?? 0) <= 0 {
            return settings.localized("Enter an amount greater than zero.")
        }
        if isCustomCategorySelected, trimmedCustomCategory.isEmpty {
            return settings.localized("Enter a custom category name.")
        }
        if existingSchedule == nil, Calendar.current.startOfDay(for: startDate) < Calendar.current.startOfDay(for: Date()) {
            return settings.localized("The first occurrence must be in the future.")
        }
        if normalizedEndDate.map({ $0 < startDate }) ?? false {
            return settings.localized("The end date cannot be before the first occurrence.")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        // Only reset category when changing type if the current one isn't valid for the new type (L7)
                        if !settings.transactionCategories(for: newType).contains(category) && !isCustomCategorySelected {
                            category = settings.transactionCategories(for: newType).first ?? ""
                        }
                        // M08: preserve an in-progress custom category name across a type toggle.
                        if !isCustomCategorySelected {
                            customCategory = ""
                            isCustomCategoryFocused = false
                        }
                    }

                    TextField("Amount (\(currency.rawValue))", text: $amount)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currencyOption in
                            (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
                        }
                    }
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        // Keep the current value selectable even if it isn't in the type's
                        // default+custom list (imported/legacy category, or the transient
                        // state mid type-toggle) so the selection always has a matching tag.
                        if category != Self.customCategoryTag && !categories.contains(category) {
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        ForEach(categories, id: \.self) { category in
                            // Localize built-in category names; custom user ones fall through verbatim (WC-M10).
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        Text("Custom...").tag(Self.customCategoryTag)
                    }
                    .onChange(of: category) { _, newCategory in
                        if newCategory == Self.customCategoryTag {
                            Task { @MainActor in
                                isCustomCategoryFocused = true
                            }
                        } else {
                            customCategory = ""
                            isCustomCategoryFocused = false
                        }
                    }

                    if isCustomCategorySelected {
                        TextField("Custom category name", text: $customCategory)
                            .focused($isCustomCategoryFocused)

                        Text(settings.localized("The category will be saved for future \(type.localizedTitle(appLanguage: settings.appLanguage).lowercased(with: AppLocalization.effectiveLocale(appLanguage: settings.appLanguage))) transactions."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(RecurringTransactionFrequency.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    DatePicker(
                        "First Occurrence",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Toggle("End Date", isOn: $hasEndDate)
                        .tint(WCColor.primary)

                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Notifications") {
                    Toggle("Notify When Due", isOn: $notificationsEnabled)
                        .tint(WCColor.primary)

                    Text("Wealth Compass records due occurrences while the app is active. If the app was closed, missed occurrences are added automatically the next time it opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(WCColor.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                guard !hasInitializedCurrency else { return }
                if existingSchedule == nil { currency = settings.currency }
                hasInitializedCurrency = true
            }
            .navigationTitle(existingSchedule == nil ? "New Recurring Transaction" : "Edit Recurring Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveSchedule)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 540, idealHeight: 660)
    }

    private func saveSchedule() {
        guard let parsedAmount, parsedAmount > 0 else { return }
        // Re-validate the advertised preconditions at save time (deep-audit L25) so a stale render
        // (e.g. the calendar day rolled over while the editor was open) can't persist a schedule the
        // disabled state would have blocked.
        guard !isSaveDisabled else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        let savedSchedule = RecurringScheduleBuilder.build(
            existing: existingSchedule,
            type: type,
            category: selectedCategory,
            amount: parsedAmount,
            description: note,
            startDate: startDate,
            frequency: frequency,
            endDate: normalizedEndDate,
            notificationsEnabled: notificationsEnabled,
            currency: currency
        )

        onSave(savedSchedule)
        dismiss()
    }
}
