import SwiftUI

struct MacEditorSheet: View {
    let editor: MacEditor

    var body: some View {
        switch editor {
        case .transaction:
            MacTransactionEditor()
        case .investment(let investment):
            MacInvestmentEditor(investment: investment)
        case .crypto(let holding):
            MacCryptoEditor(holding: holding)
        }
    }
}

private struct MacTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings

    private static let customCategoryTag = "__wealth_compass_custom_category__"

    @State private var type: TransactionType = .expense
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var currency: Currency = .eur
    @State private var hasInitializedCurrency = false
    @State private var customCategory = ""
    @FocusState private var isCustomCategoryFocused: Bool

    private var categories: [String] {
        settings.transactionCategories(for: type)
    }

    private var trimmedCustomCategory: String {
        customCategory.trimmed
    }

    private var selectedCategoryName: String {
        category == Self.customCategoryTag ? trimmedCustomCategory : category
    }

    private var isCustomCategorySelected: Bool {
        category == Self.customCategoryTag
    }

    private var parsedAmount: Decimal? {
        MoneyParser.decimal(from: amount)
    }

    private var isSaveDisabled: Bool {
        guard let parsedAmount, parsedAmount > 0 else { return true }
        return selectedCategoryName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        // Only reset category when changing type if the current one isn't valid for the new type (L7)
                        if !settings.transactionCategories(for: newType).contains(category) && !isCustomCategorySelected {
                            category = settings.transactionCategories(for: newType).first ?? ""
                        }
                        // M08: preserve an in-progress custom category name across a type toggle — a
                        // custom category isn't tied to income vs expense, so don't wipe it.
                        if !isCustomCategorySelected {
                            customCategory = ""
                            isCustomCategoryFocused = false
                        }
                    }

                    // L20: show the active currency code in the label, matching the recurring editor.
                    TextField("Amount (\(currency.rawValue))", text: $amount)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currencyOption in
                            (Text(currencyOption.displayName) + Text(" (\(currencyOption.rawValue))")).tag(currencyOption)
                        }
                    }
                    Picker("Category", selection: $category) {
                        // Keep the current value selectable even if it isn't in the
                        // type's default+custom list (imported/legacy category, or the
                        // transient state mid type-toggle) so the selection always has a
                        // matching tag — no "selection is invalid" warning, no data loss.
                        if category != Self.customCategoryTag && !categories.contains(category) {
                            Text(LocalizedStringKey(category)).tag(category)
                        }
                        ForEach(categories, id: \.self) {
                            Text(LocalizedStringKey($0)).tag($0)
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
                        TextField("Custom Category Name", text: $customCategory)
                            .focused($isCustomCategoryFocused)

                        Text(customCategoryHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }
            }
            .formStyle(.grouped)
            .onAppear {
                guard !hasInitializedCurrency else { return }
                currency = settings.currency
                hasInitializedCurrency = true
            }
            .navigationTitle("New Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 380, idealHeight: 460)
    }

    private func save() {
        guard let parsedAmount, parsedAmount > 0 else { return }

        let categoryToSave: String
        if isCustomCategorySelected {
            guard let savedCategory = settings.addCustomTransactionCategory(trimmedCustomCategory, for: type) else {
                return
            }
            categoryToSave = savedCategory
        } else {
            categoryToSave = category
        }

        finance.addTransaction(
            type: type,
            amount: parsedAmount,
            category: categoryToSave,
            description: note,
            date: date,
            currency: currency,
            settings: settings
        )
        dismiss()
    }

    private var customCategoryHint: String {
        let typeName = type.localizedTitle(appLanguage: settings.appLanguage).lowercased()
        if trimmedCustomCategory.isEmpty {
            return settings.localized("Enter a category name. It will be saved for future \(typeName) transactions.")
        }

        if let existing = categories.first(where: {
            $0.caseInsensitiveCompare(trimmedCustomCategory) == .orderedSame
        }) {
            return settings.localized("\(existing) already exists and will be selected.")
        }

        return settings.localized("This category will be added to your \(typeName) categories.")
    }
}

private struct MacInvestmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    let investment: Investment?

    @State private var symbol: String
    @State private var name: String
    @State private var isin: String
    @State private var type: InvestmentType
    @State private var currency: Currency
    @State private var sector: String
    @State private var geography: String
    @State private var quantity: String
    @State private var averagePrice: String
    @State private var currentPrice: String
    @State private var feeMode: FeeMode = .fixed
    @State private var feeValue: String

    private let sectors = [
        "Technology", "Finance", "Real Estate", "Healthcare",
        "Energy", "Consumer", "All World", "Other"
    ]
    private let geographies = [
        "US", "Europe", "UK", "Switzerland",
        "Global", "Emerging Markets", "Other"
    ]

    init(investment: Investment?) {
        self.investment = investment
        _symbol = State(initialValue: investment?.symbol ?? "")
        _name = State(initialValue: investment?.name ?? "")
        _isin = State(initialValue: investment?.isin ?? "")
        _type = State(initialValue: investment?.type ?? .stock)
        _currency = State(initialValue: investment?.currency ?? .usd)
        _sector = State(initialValue: investment?.sector ?? "Technology")
        _geography = State(initialValue: investment?.geography ?? "US")
        _quantity = State(initialValue: investment.map { Self.input($0.quantity) } ?? "")
        let average = investment.map { $0.quantity > 0 ? max(0, ($0.costBasis - $0.fees) / $0.quantity) : 0 } ?? 0
        _averagePrice = State(initialValue: investment.map { _ in Self.input(average) } ?? "")
        _currentPrice = State(initialValue: investment.map { Self.input($0.currentPrice) } ?? "")
        _feeValue = State(initialValue: investment.map { Self.input($0.fees) } ?? "0")
    }

    private var parsedQuantity: Decimal { parse(quantity) }
    private var parsedAveragePrice: Decimal { parse(averagePrice) }
    private var parsedCurrentPrice: Decimal { parse(currentPrice) }
    // M09: a blank/zero current price falls back to the entered average price on save, so the holding
    // shows at cost until a market refresh instead of silently contributing 0 to net worth.
    private var effectiveCurrentPrice: Decimal { parsedCurrentPrice > 0 ? parsedCurrentPrice : parsedAveragePrice }
    private var parsedFeeValue: Decimal { parse(feeValue) }
    private var calculatedFee: Decimal {
        feeMode == .fixed
            ? parsedFeeValue
            : (parsedQuantity * parsedAveragePrice) * (parsedFeeValue / 100)
    }

    private var isSaveDisabled: Bool {
        symbol.trimmed.isEmpty || name.trimmed.isEmpty || parsedQuantity <= 0
            // M09: block a holding with no price at all (both current and average blank), which would
            // otherwise save with a zero current value.
            || (parsedCurrentPrice <= 0 && parsedAveragePrice <= 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Symbol", text: $symbol)
                    TextField("Name", text: $name)
                    TextField("ISIN / ID", text: $isin)
                    Picker("Type", selection: $type) {
                        ForEach(InvestmentType.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Classification") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) {
                            (Text($0.displayName) + Text(" (\($0.rawValue))")).tag($0)
                        }
                    }
                    Picker("Sector", selection: $sector) {
                        ForEach(sectors, id: \.self) {
                            Text(LocalizedStringKey($0)).tag($0)
                        }
                    }
                    Picker("Geography", selection: $geography) {
                        ForEach(geographies, id: \.self) {
                            Text(LocalizedStringKey($0)).tag($0)
                        }
                    }
                }

                Section("Position") {
                    TextField("Quantity", text: $quantity)
                    TextField("Average Buy Price (\(currency.rawValue))", text: $averagePrice)
                    TextField("Current Price (\(currency.rawValue))", text: $currentPrice)
                }

                Section("Investment Transaction Fee") {
                    Picker("Fee Type", selection: $feeMode) {
                        ForEach(FeeMode.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(
                        feeMode == .fixed
                            ? settings.localized("Investment Transaction Fee")
                            : settings.localized("Investment Transaction Fee %"),
                        text: $feeValue
                    )

                    LabeledContent("Investment Fee") {
                        Text(calculatedFee.formatted(.currency(code: currency.rawValue)))
                            .monospacedDigit()
                    }

                    Text("The broker or platform fee is added to the position cost basis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(investment == nil ? "New Investment" : "Edit Investment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 580, minHeight: 580, idealHeight: 700)
    }

    private func save() {
        let costBasis = parsedQuantity * parsedAveragePrice + calculatedFee
        var value = investment ?? Investment(
            type: type,
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            costBasis: costBasis,
            currentValue: parsedQuantity * effectiveCurrentPrice,
            currentPrice: effectiveCurrentPrice,
            currency: currency,
            geography: geography,
            sector: sector,
            isin: isin,
            fees: calculatedFee
        )
        value.type = type
        value.symbol = symbol.trimmed.uppercased()
        value.name = name.trimmed
        value.quantity = parsedQuantity
        value.costBasis = costBasis
        value.currentValue = parsedQuantity * effectiveCurrentPrice
        value.currentPrice = effectiveCurrentPrice
        value.currency = currency
        value.geography = geography.trimmed
        value.sector = sector.trimmed
        value.isin = isin.trimmed.uppercased()
        value.fees = calculatedFee
        value.updatedAt = Date()
        finance.upsertInvestment(value, settings: settings)
        dismiss()
    }

    private func parse(_ value: String) -> Decimal {
        // Finite, locale-aware parse (WC-H1/M9); inf/nan/garbage → 0, blocked by `> 0` guards.
        MoneyParser.decimal(from: value) ?? 0
    }

    private static func input(_ value: Decimal) -> String {
        AmountInputFormatter.string(value)
    }
}

private struct MacCryptoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    let holding: CryptoHolding?

    @State private var symbol: String
    @State private var name: String
    @State private var coinID: String
    @State private var quantity: String
    @State private var averagePrice: String
    @State private var currentPrice: String
    @State private var feeMode: FeeMode = .fixed
    @State private var feeValue: String
    @State private var currency: Currency
    @State private var hasInitializedCurrency = false

    init(holding: CryptoHolding?) {
        self.holding = holding
        _symbol = State(initialValue: holding?.symbol ?? "")
        _name = State(initialValue: holding?.name ?? "")
        _coinID = State(initialValue: holding?.coinId ?? "")
        _quantity = State(initialValue: holding.map { Self.input($0.quantity) } ?? "")
        let average = holding.map { $0.quantity > 0 ? max(0, $0.avgBuyPrice - ($0.fees / $0.quantity)) : 0 } ?? 0
        _averagePrice = State(initialValue: holding.map { _ in Self.input(average) } ?? "")
        _currentPrice = State(initialValue: holding.map { Self.input($0.currentPrice) } ?? "")
        _feeValue = State(initialValue: holding.map { Self.input($0.fees) } ?? "0")
        // Placeholder; a new holding adopts the app's display currency in onAppear
        // (the environment isn't available during init).
        _currency = State(initialValue: holding?.currency ?? .eur)
    }

    private var parsedQuantity: Decimal { parse(quantity) }
    private var parsedAveragePrice: Decimal { parse(averagePrice) }
    private var parsedCurrentPrice: Decimal { parse(currentPrice) }
    // M09: a blank/zero current price falls back to the entered average price on save, so the holding
    // shows at cost until a market refresh instead of silently contributing 0 to net worth.
    private var effectiveCurrentPrice: Decimal { parsedCurrentPrice > 0 ? parsedCurrentPrice : parsedAveragePrice }
    private var parsedFeeValue: Decimal { parse(feeValue) }
    private var calculatedFee: Decimal {
        feeMode == .fixed
            ? parsedFeeValue
            : (parsedQuantity * parsedAveragePrice) * (parsedFeeValue / 100)
    }

    private var isSaveDisabled: Bool {
        symbol.trimmed.isEmpty || name.trimmed.isEmpty || parsedQuantity <= 0
            // M09: block a holding with no price at all (both current and average blank), which would
            // otherwise save with a zero current value.
            || (parsedCurrentPrice <= 0 && parsedAveragePrice <= 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Symbol", text: $symbol)
                    TextField("Name", text: $name)
                    TextField("CoinGecko ID", text: $coinID)
                }

                Section("Position") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currency in
                            (Text(currency.displayName) + Text(" (\(currency.rawValue))")).tag(currency)
                        }
                    }
                    TextField("Quantity", text: $quantity)
                    TextField("Average Buy Price (\(currency.rawValue))", text: $averagePrice)
                    TextField("Current Price (\(currency.rawValue))", text: $currentPrice)
                }

                Section("Transaction Fee") {
                    Picker("Fee Type", selection: $feeMode) {
                        ForEach(FeeMode.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(
                        feeMode == .fixed
                            ? settings.localized("Fee Amount")
                            : settings.localized("Fee Percentage"),
                        text: $feeValue
                    )

                    LabeledContent("Calculated Fee") {
                        Text(calculatedFee.formatted(.currency(code: currency.rawValue)))
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                guard !hasInitializedCurrency else { return }
                if holding == nil { currency = settings.currency }
                hasInitializedCurrency = true
            }
            .navigationTitle(holding == nil ? "New Crypto Holding" : "Edit Crypto Holding")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 440, idealHeight: 560)
    }

    private func save() {
        let totalCost = parsedQuantity * parsedAveragePrice + calculatedFee
        let effectiveAverage = parsedQuantity > 0 ? totalCost / parsedQuantity : 0
        var value = holding ?? CryptoHolding(
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            avgBuyPrice: effectiveAverage,
            currentPrice: effectiveCurrentPrice,
            fees: calculatedFee,
            coinId: coinID
        )
        value.symbol = symbol.trimmed.uppercased()
        value.name = name.trimmed
        value.coinId = coinID.trimmed.lowercased()
        value.quantity = parsedQuantity
        value.avgBuyPrice = effectiveAverage
        value.currentPrice = effectiveCurrentPrice
        value.fees = calculatedFee
        value.currency = currency
        value.updatedAt = Date()
        finance.upsertCrypto(value, settings: settings)
        dismiss()
    }

    private func parse(_ value: String) -> Decimal {
        // Finite, locale-aware parse (WC-H1/M9); inf/nan/garbage → 0, blocked by `> 0` guards.
        MoneyParser.decimal(from: value) ?? 0
    }

    private static func input(_ value: Decimal) -> String {
        AmountInputFormatter.string(value)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
