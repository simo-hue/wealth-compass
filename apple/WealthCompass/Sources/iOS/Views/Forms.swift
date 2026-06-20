import SwiftUI

struct TransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let transaction: Transaction?
    let onSave: (Transaction?, TransactionType, Double, String, String, Date) -> Void
    let onDelete: (() -> Void)?

    private static let customCategoryTag = "__wealth_compass_custom_category__"

    @State private var type: TransactionType
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

    init(
        transaction: Transaction? = nil,
        onSave: @escaping (Transaction?, TransactionType, Double, String, String, Date) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.transaction = transaction
        self.onSave = onSave
        self.onDelete = onDelete
        _type = State(initialValue: transaction?.type ?? .expense)
        _amount = State(initialValue: transaction.map { String($0.amount) } ?? "")
        _category = State(initialValue: transaction?.category ?? String(localized: "Food"))
        _note = State(initialValue: transaction?.description ?? "")
        _date = State(initialValue: transaction?.date ?? Date())
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
        parsedAmount <= 0 || currentCategoryName.isEmpty
    }

    private var customCategoryHint: String {
        if trimmedCustomCategory.isEmpty {
            return String(localized: "Enter a category name. It will be saved for future \(type.title) transactions.")
        }

        if let existing = categories.first(where: { $0.caseInsensitiveCompare(trimmedCustomCategory) == .orderedSame }) {
            return String(localized: "\(existing) already exists and will be selected.")
        }

        return String(localized: "This category will be added to your \(type.title) categories.")
    }

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
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
                    customCategory = ""
                    isCustomCategoryFocused = false
                }

                Section("Details") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
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
        .preferredColorScheme(.dark)
    }

    private func saveTransaction() {
        guard parsedAmount > 0 else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        onSave(transaction, type, parsedAmount, selectedCategory, note, date)
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
        _amount = State(initialValue: schedule.map { String($0.amount) } ?? "")
        _category = State(initialValue: schedule?.category ?? String(localized: "Food"))
        _note = State(initialValue: schedule?.description ?? "")
        _startDate = State(initialValue: initialStartDate)
        _frequency = State(initialValue: schedule?.frequency ?? .monthly)
        _hasEndDate = State(initialValue: schedule?.endDate != nil)
        _endDate = State(initialValue: schedule?.endDate ?? defaultEndDate)
        _notificationsEnabled = State(initialValue: schedule?.notificationsEnabled ?? true)
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

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var normalizedEndDate: Date? {
        guard hasEndDate else { return nil }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate)
    }

    private var isSaveDisabled: Bool {
        parsedAmount <= 0
            || currentCategoryName.isEmpty
            || (existingSchedule == nil && startDate <= Date())
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
                    category = settings.transactionCategories(for: newValue).first ?? ""
                    customCategory = ""
                    isCustomCategoryFocused = false
                }

                Section("Transaction") {
                    TextField("Amount (\(settings.currency.rawValue))", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Description", text: $note)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
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

                        Text(String(localized: "The category will be saved for future \(type.title) transactions."))
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

                    Text(String(localized: "Wealth Compass records due occurrences while the app is active. If the app was closed, missed occurrences are added automatically the next time it opens."))
                    .font(.caption)
                    .foregroundStyle(WCColor.textSecondary)
                }
            }
            .navigationTitle(existingSchedule == nil ? String(localized: "New Recurring Transaction") : String(localized: "Edit Recurring Transaction"))
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
        .preferredColorScheme(.dark)
    }

    private func saveSchedule() {
        guard parsedAmount > 0 else { return }

        let selectedCategory: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            selectedCategory = savedCategory
        } else {
            selectedCategory = category
        }

        let scheduleChanged = existingSchedule.map {
            $0.frequency != frequency || abs($0.startDate.timeIntervalSince(startDate)) >= 1
        } ?? true

        let seed = RecurringTransaction(
            id: existingSchedule?.id ?? UUID(),
            type: type,
            category: selectedCategory,
            amount: parsedAmount,
            description: note,
            startDate: startDate,
            frequency: frequency,
            nextDueDate: startDate,
            endDate: normalizedEndDate,
            notificationsEnabled: notificationsEnabled,
            isActive: existingSchedule?.isActive ?? true,
            completedAt: existingSchedule?.completedAt,
            createdAt: existingSchedule?.createdAt ?? Date(),
            updatedAt: Date()
        )

        var savedSchedule = seed
        if savedSchedule.isCompleted {
            savedSchedule.isActive = false
        } else if !scheduleChanged, let existingSchedule {
            savedSchedule.nextDueDate = existingSchedule.nextDueDate
        } else if let nextDueDate = seed.firstOccurrence(onOrAfter: Date()) {
            savedSchedule.nextDueDate = nextDueDate
        } else {
            savedSchedule.isActive = false
        }

        if let endDate = savedSchedule.endDate, savedSchedule.nextDueDate > endDate {
            savedSchedule.isActive = false
        }

        onSave(savedSchedule)
        dismiss()
    }
}

struct InvestmentFormView: View {
    @Environment(\.dismiss) private var dismiss
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

    private let sectors = [String(localized: "Technology"), String(localized: "Finance"), String(localized: "Real Estate"), String(localized: "Healthcare"), String(localized: "Energy"), String(localized: "Consumer"), String(localized: "All World"), String(localized: "Other")]
    private let geographies = [String(localized: "US"), String(localized: "Europe"), String(localized: "UK"), String(localized: "Switzerland"), String(localized: "Global"), String(localized: "Emerging Markets"), String(localized: "Other")]

    init(investment: Investment?, onSave: @escaping (Investment) -> Void) {
        self.investment = investment
        self.onSave = onSave
        _symbol = State(initialValue: investment?.symbol ?? "")
        _name = State(initialValue: investment?.name ?? "")
        _isin = State(initialValue: investment?.isin ?? "")
        _type = State(initialValue: investment?.type ?? .stock)
        _sector = State(initialValue: investment?.sector ?? String(localized: "Technology"))
        _geography = State(initialValue: investment?.geography ?? String(localized: "US"))
        _currency = State(initialValue: investment?.currency ?? .usd)
        _quantity = State(initialValue: investment.map { Self.formatInput($0.quantity) } ?? "")
        let rawAverage = investment.map { $0.quantity > 0 ? max(0, ($0.costBasis - $0.fees) / $0.quantity) : 0 } ?? 0
        _avgBuyPrice = State(initialValue: investment == nil ? "" : Self.formatInput(rawAverage))
        _currentPrice = State(initialValue: investment.map { Self.formatInput($0.currentPrice) } ?? "")
        _feeValue = State(initialValue: investment.map { Self.formatInput($0.fees) } ?? "0")
    }

    private var parsedQuantity: Double { parse(quantity) }
    private var parsedAverage: Double { parse(avgBuyPrice) }
    private var parsedCurrentPrice: Double { parse(currentPrice) }
    private var parsedFeeValue: Double { parse(feeValue) }
    private var calculatedFee: Double {
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
                            Text("\(currency.displayName) (\(currency.rawValue))").tag(currency)
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
                    TextField(feeMode == .fixed ? String(localized: "Investment Transaction Fee") : String(localized: "Investment Transaction Fee %"), text: $feeValue)
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
            .navigationTitle(investment == nil ? String(localized: "Add Investment") : String(localized: "Edit Investment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let costBasis = (parsedQuantity * parsedAverage) + calculatedFee
        let value = parsedQuantity * parsedCurrentPrice
        var item = investment ?? Investment(
            type: type,
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            costBasis: costBasis,
            currentValue: value,
            currentPrice: parsedCurrentPrice,
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
        item.currentPrice = parsedCurrentPrice
        item.currency = currency
        item.geography = geography
        item.sector = sector
        item.isin = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.fees = calculatedFee
        item.updatedAt = Date()
        onSave(item)
    }

    private func parse(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func formatInput(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.8g", value)
    }
}

struct CryptoFormView: View {
    @Environment(\.dismiss) private var dismiss
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
    }

    private var parsedQuantity: Double { parse(quantity) }
    private var parsedAverage: Double { parse(avgBuyPrice) }
    private var parsedCurrentPrice: Double { parse(currentPrice) }
    private var parsedFeeValue: Double { parse(feeValue) }
    private var calculatedFee: Double {
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
                    TextField(feeMode == .fixed ? String(localized: "Fee Amount") : String(localized: "Fee Percentage"), text: $feeValue)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Calculated Fee")
                        Spacer()
                        Text(calculatedFee.formatted(.currency(code: Currency.usd.rawValue)))
                            .font(.body.monospacedDigit())
                    }
                }
            }
            .navigationTitle(holding == nil ? String(localized: "Add Crypto") : String(localized: "Edit Crypto"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedQuantity <= 0)
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
            currentPrice: parsedCurrentPrice,
            fees: calculatedFee,
            coinId: coinId
        )
        item.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.coinId = coinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        item.quantity = parsedQuantity
        item.avgBuyPrice = effectiveAverage
        item.currentPrice = parsedCurrentPrice
        item.fees = calculatedFee
        item.updatedAt = Date()
        onSave(item)
    }

    private func parse(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func formatInput(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.8g", value)
    }
}
