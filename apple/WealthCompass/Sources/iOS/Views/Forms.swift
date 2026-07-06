import SwiftUI

struct TransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let transaction: Transaction?
    let onSave: (Transaction?, TransactionType, Decimal, String, String, Date, Currency) -> Void
    let onDelete: (() -> Void)?

    private static let customCategoryTag = "__wealth_compass_custom_category__"

    @State private var type: TransactionType
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @State private var currency: Currency
    @State private var hasInitializedCurrency = false
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

    init(
        transaction: Transaction? = nil,
        onSave: @escaping (Transaction?, TransactionType, Decimal, String, String, Date, Currency) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.transaction = transaction
        self.onSave = onSave
        self.onDelete = onDelete
        _type = State(initialValue: transaction?.type ?? .expense)
        _amount = State(initialValue: transaction.map { AmountInputFormatter.string($0.amount) } ?? "")
        _category = State(initialValue: transaction?.category ?? "Food")
        _note = State(initialValue: transaction?.description ?? "")
        _date = State(initialValue: transaction?.date ?? Date())
        // Placeholder; a new transaction adopts the base currency in onAppear (the
        // environment isn't available during init). Existing rows keep their own currency.
        _currency = State(initialValue: transaction?.currency ?? .eur)
    }

    private var categories: [String] {
        settings.transactionCategories(for: type)
    }

    private var trimmedCustomCategory: String {
        customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentCategoryName: String {
        category == Self.customCategoryTag ? trimmedCustomCategory : category
    }

    private var isCustomCategorySelected: Bool {
        category == Self.customCategoryTag
    }

    private var isSaveDisabled: Bool {
        guard let amount = parsedAmount, amount > 0 else { return true }
        return currentCategoryName.isEmpty
    }

    private var customCategoryHint: String {
        let typeName = type.localizedTitle(appLanguage: settings.appLanguage)
        if trimmedCustomCategory.isEmpty {
            return settings.localized("Enter a category name. It will be saved for future \(typeName) transactions.")
        }

        if let existing = categories.first(where: { $0.caseInsensitiveCompare(trimmedCustomCategory) == .orderedSame }) {
            return settings.localized("\(existing) already exists and will be selected.")
        }

        return settings.localized("This category will be added to your \(typeName) categories.")
    }

    private var parsedAmount: Decimal? {
        MoneyParser.decimal(from: amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: type) { _, newValue in
                    // Only reset category when changing type if user hasn't selected a valid category for the new type
                    if !settings.transactionCategories(for: newValue).contains(category) && !isCustomCategorySelected {
                        category = settings.transactionCategories(for: newValue).first ?? ""
                    }
                    // M08: preserve an in-progress custom category name across a type toggle.
                    if !isCustomCategorySelected {
                        customCategory = ""
                        isCustomCategoryFocused = false
                    }
                }

                Section("Details") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currencyOption in
                            (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        // Keep the current value selectable even if it isn't in the
                        // type's default+custom list (imported/legacy category, or the
                        // transient state mid type-toggle) so the Picker selection always
                        // has a matching tag — no "selection is invalid" warning, no data loss.
                        if category != Self.customCategoryTag && !categories.contains(category) {
                            Text(category).tag(category)
                        }
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                        Text("Custom...").tag(Self.customCategoryTag)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: category) { _, newValue in
                        if newValue == Self.customCategoryTag {
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
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isCustomCategoryFocused)

                        Text(customCategoryHint)
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
                    }
                }
                
                if transaction != nil, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Transaction")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(transaction == nil ? "Add Transaction" : "Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .onAppear {
            guard !hasInitializedCurrency else { return }
            if transaction == nil { currency = settings.currency }
            hasInitializedCurrency = true
        }
        .preferredColorScheme(.dark)
    }

    private func saveTransaction() {
        guard let amount = parsedAmount, amount > 0 else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        onSave(transaction, type, amount, selectedCategory, note, date, currency)
        dismiss()
    }
}

struct RecurringTransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let existingSchedule: RecurringTransaction?
    let onSave: (RecurringTransaction) -> Void

    private static let customCategoryTag = "__wealth_compass_recurring_custom_category__"

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

    private var currentCategoryName: String {
        category == Self.customCategoryTag ? trimmedCustomCategory : category
    }

    private var isCustomCategorySelected: Bool {
        category == Self.customCategoryTag
    }

    private var parsedAmount: Decimal? {
        MoneyParser.decimal(from: amount)
    }

    private var normalizedEndDate: Date? {
        guard hasEndDate else { return nil }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate)
    }

    private var isSaveDisabled: Bool {
        guard let amount = parsedAmount, amount > 0 else { return true }
        return currentCategoryName.isEmpty
            // Allow same-day scheduling (deep-audit L09): compare by calendar day, not instant — the
            // builder forward-clamps a same-day past time to the next occurrence, so only a genuinely
            // past calendar day should block Save.
            || (existingSchedule == nil && Calendar.current.startOfDay(for: startDate) < Calendar.current.startOfDay(for: Date()))
            || (normalizedEndDate.map { $0 < startDate } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: type) { _, newValue in
                    // Only reset category when changing type if the current one isn't valid for the new type (L7)
                    if !settings.transactionCategories(for: newValue).contains(category) && !isCustomCategorySelected {
                        category = settings.transactionCategories(for: newValue).first ?? ""
                    }
                    // M08: preserve an in-progress custom category name across a type toggle.
                    if !isCustomCategorySelected {
                        customCategory = ""
                        isCustomCategoryFocused = false
                    }
                }

                Section("Transaction") {
                    TextField("Amount (\(currency.rawValue))", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currencyOption in
                            (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
                        }
                    }
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        // Keep the current value selectable even if it isn't in the
                        // type's default+custom list (imported/legacy category, or the
                        // transient state mid type-toggle) so the Picker selection always
                        // has a matching tag — no "selection is invalid" warning, no data loss.
                        if category != Self.customCategoryTag && !categories.contains(category) {
                            Text(category).tag(category)
                        }
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                        Text("Custom...").tag(Self.customCategoryTag)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: category) { _, newValue in
                        if newValue == Self.customCategoryTag {
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
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isCustomCategoryFocused)

                        Text(settings.localized("The category will be saved for future \(type.localizedTitle(appLanguage: settings.appLanguage)) transactions."))
                            .font(.caption)
                            .foregroundStyle(WCColor.textSecondary)
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
                    .foregroundStyle(WCColor.textSecondary)
                }
            }
            .navigationTitle(existingSchedule == nil ? "New Recurring Transaction" : "Edit Recurring Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveSchedule)
                        .disabled(isSaveDisabled)
                }
            }
        }
        .onAppear {
            guard !hasInitializedCurrency else { return }
            if existingSchedule == nil { currency = settings.currency }
            hasInitializedCurrency = true
        }
        .preferredColorScheme(.dark)
    }

    private func saveSchedule() {
        guard let amount = parsedAmount, amount > 0 else { return }
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
            amount: amount,
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

struct InvestmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let investment: Investment?
    let onSave: (Investment) -> Void

    @State private var symbol: String
    @State private var name: String
    @State private var isin: String
    @State private var type: InvestmentType
    @State private var sector: String
    @State private var geography: String
    @State private var currency: Currency
    @State private var quantity: String
    @State private var avgBuyPrice: String
    @State private var currentPrice: String
    @State private var feeMode: FeeMode = .fixed
    @State private var feeValue: String

    private let sectors = ["Technology", "Finance", "Real Estate", "Healthcare", "Energy", "Consumer", "All World", "Other"]
    private let geographies = ["US", "Europe", "UK", "Switzerland", "Global", "Emerging Markets", "Other"]

    init(investment: Investment?, onSave: @escaping (Investment) -> Void) {
        self.investment = investment
        self.onSave = onSave
        _symbol = State(initialValue: investment?.symbol ?? "")
        _name = State(initialValue: investment?.name ?? "")
        _isin = State(initialValue: investment?.isin ?? "")
        _type = State(initialValue: investment?.type ?? .stock)
        _sector = State(initialValue: investment?.sector ?? "Technology")
        _geography = State(initialValue: investment?.geography ?? "US")
        _currency = State(initialValue: investment?.currency ?? .usd)
        _quantity = State(initialValue: investment.map { Self.formatInput($0.quantity) } ?? "")
        let rawAverage = investment.map { $0.quantity > 0 ? max(0, ($0.costBasis - $0.fees) / $0.quantity) : 0 } ?? 0
        _avgBuyPrice = State(initialValue: investment == nil ? "" : Self.formatInput(rawAverage))
        _currentPrice = State(initialValue: investment.map { Self.formatInput($0.currentPrice) } ?? "")
        _feeValue = State(initialValue: investment.map { Self.formatInput($0.fees) } ?? "0")
    }

    private var parsedQuantity: Decimal { parse(quantity) }
    private var parsedAverage: Decimal { parse(avgBuyPrice) }
    private var parsedCurrentPrice: Decimal { parse(currentPrice) }
    // M09: a blank/zero current price falls back to the entered average price on save, so the holding
    // shows at cost until a market refresh instead of silently contributing 0 to net worth.
    private var effectiveCurrentPrice: Decimal { parsedCurrentPrice > 0 ? parsedCurrentPrice : parsedAverage }
    private var parsedFeeValue: Decimal { parse(feeValue) }
    private var calculatedFee: Decimal {
        feeMode == .fixed ? parsedFeeValue : (parsedQuantity * parsedAverage) * (parsedFeeValue / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    TextField("Name", text: $name)
                    TextField("ISIN / ID", text: $isin)
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(InvestmentType.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currency in
                            (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                        }
                    }
                    Picker("Sector", selection: $sector) {
                        ForEach(sectors, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Geography", selection: $geography) {
                        ForEach(geographies, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("Average Buy Price", text: $avgBuyPrice)
                        .keyboardType(.decimalPad)
                    TextField("Current Price", text: $currentPrice)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Fee Type", selection: $feeMode) {
                        ForEach(FeeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(
                        feeMode == .fixed
                            ? settings.localized("Investment Transaction Fee")
                            : settings.localized("Investment Transaction Fee %"),
                        text: $feeValue
                    )
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Investment Fee")
                        Spacer()
                        Text(calculatedFee.formatted(.currency(code: currency.rawValue)))
                            .font(.body.monospacedDigit())
                    }
                } header: {
                    Text("Investment Transaction Fee")
                } footer: {
                    Text("Enter the broker or platform fee charged for this investment transaction. It is added to the position cost basis.")
                }
            }
            .navigationTitle(investment == nil ? "Add Investment" : "Edit Investment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    // M09: also block a holding with no price at all (both current and average blank).
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0 || (parsedCurrentPrice <= 0 && parsedAverage <= 0))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let costBasis = (parsedQuantity * parsedAverage) + calculatedFee
        let value = parsedQuantity * effectiveCurrentPrice
        var item = investment ?? Investment(
            type: type,
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            costBasis: costBasis,
            currentValue: value,
            currentPrice: effectiveCurrentPrice,
            currency: currency,
            geography: geography,
            sector: sector,
            isin: isin,
            fees: calculatedFee
        )
        item.type = type
        item.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = parsedQuantity
        item.costBasis = costBasis
        item.currentValue = value
        item.currentPrice = effectiveCurrentPrice
        item.currency = currency
        item.geography = geography
        item.sector = sector
        item.isin = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.fees = calculatedFee
        item.updatedAt = Date()
        onSave(item)
    }

    private func parse(_ value: String) -> Decimal {
        // Finite, locale-aware parse (WC-H1/M9); rejects inf/nan/grouped-garbage to 0,
        // which the `> 0` save guards then block.
        MoneyParser.decimal(from: value) ?? 0
    }

    private static func formatInput(_ value: Decimal) -> String {
        AmountInputFormatter.string(value)
    }
}

struct CryptoFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let holding: CryptoHolding?
    let onSave: (CryptoHolding) -> Void

    @State private var symbol: String
    @State private var name: String
    @State private var coinId: String
    @State private var quantity: String
    @State private var avgBuyPrice: String
    @State private var currentPrice: String
    @State private var feeMode: FeeMode = .fixed
    @State private var feeValue: String
    @State private var currency: Currency
    @State private var hasInitializedCurrency = false

    init(holding: CryptoHolding?, onSave: @escaping (CryptoHolding) -> Void) {
        self.holding = holding
        self.onSave = onSave
        _symbol = State(initialValue: holding?.symbol ?? "")
        _name = State(initialValue: holding?.name ?? "")
        _coinId = State(initialValue: holding?.coinId ?? "")
        _quantity = State(initialValue: holding.map { Self.formatInput($0.quantity) } ?? "")
        let rawAverage = holding.map { $0.quantity > 0 ? max(0, (($0.avgBuyPrice * $0.quantity) - $0.fees) / $0.quantity) : 0 } ?? 0
        _avgBuyPrice = State(initialValue: holding == nil ? "" : Self.formatInput(rawAverage))
        _currentPrice = State(initialValue: holding.map { Self.formatInput($0.currentPrice) } ?? "")
        _feeValue = State(initialValue: holding.map { Self.formatInput($0.fees) } ?? "0")
        // Placeholder; a new holding adopts the app's display currency in onAppear
        // (the environment isn't available during init).
        _currency = State(initialValue: holding?.currency ?? .eur)
    }

    private var parsedQuantity: Decimal { parse(quantity) }
    private var parsedAverage: Decimal { parse(avgBuyPrice) }
    private var parsedCurrentPrice: Decimal { parse(currentPrice) }
    // M09: a blank/zero current price falls back to the entered average price on save, so the holding
    // shows at cost until a market refresh instead of silently contributing 0 to net worth.
    private var effectiveCurrentPrice: Decimal { parsedCurrentPrice > 0 ? parsedCurrentPrice : parsedAverage }
    private var parsedFeeValue: Decimal { parse(feeValue) }
    private var calculatedFee: Decimal {
        feeMode == .fixed ? parsedFeeValue : (parsedQuantity * parsedAverage) * (parsedFeeValue / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    TextField("Name", text: $name)
                    TextField("Optional Coin ID", text: $coinId)
                }

                Section {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currency in
                            (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                        }
                    }
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("Average Buy Price", text: $avgBuyPrice)
                        .keyboardType(.decimalPad)
                    TextField("Current Price", text: $currentPrice)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Fee Type", selection: $feeMode) {
                        ForEach(FeeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(
                        feeMode == .fixed
                            ? settings.localized("Fee Amount")
                            : settings.localized("Fee Percentage"),
                        text: $feeValue
                    )
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Calculated Fee")
                        Spacer()
                        Text(calculatedFee.formatted(.currency(code: currency.rawValue)))
                            .font(.body.monospacedDigit())
                    }
                }
            }
            .navigationTitle(holding == nil ? "Add Crypto" : "Edit Crypto")
            .onAppear {
                guard !hasInitializedCurrency else { return }
                if holding == nil { currency = settings.currency }
                hasInitializedCurrency = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    // M09: also block a holding with no price at all (both current and average blank).
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0 || (parsedCurrentPrice <= 0 && parsedAverage <= 0))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let totalCost = (parsedQuantity * parsedAverage) + calculatedFee
        let effectiveAverage = parsedQuantity > 0 ? totalCost / parsedQuantity : 0
        var item = holding ?? CryptoHolding(
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            avgBuyPrice: effectiveAverage,
            currentPrice: effectiveCurrentPrice,
            fees: calculatedFee,
            coinId: coinId
        )
        item.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.coinId = coinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        item.quantity = parsedQuantity
        item.avgBuyPrice = effectiveAverage
        item.currentPrice = effectiveCurrentPrice
        item.fees = calculatedFee
        item.currency = currency
        item.updatedAt = Date()
        onSave(item)
    }

    private func parse(_ value: String) -> Decimal {
        // Finite, locale-aware parse (WC-H1/M9); rejects inf/nan/grouped-garbage to 0,
        // which the `> 0` save guards then block.
        MoneyParser.decimal(from: value) ?? 0
    }

    private static func formatInput(_ value: Decimal) -> String {
        AmountInputFormatter.string(value)
    }
}
