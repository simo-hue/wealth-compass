import SwiftUI

struct TransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let onSave: (TransactionType, Double, String, String, Date) -> Void

    @State private var type: TransactionType = .expense
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var isAddingCategory = false
    @State private var newCategory = ""

    private var categories: [String] {
        settings.transactionCategories(for: type)
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
                    category = settings.transactionCategories(for: newValue).first ?? ""
                    isAddingCategory = false
                    newCategory = ""
                }

                Section {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Category", selection: $category) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }

                        if isAddingCategory {
                            HStack(spacing: 10) {
                                TextField("New category", text: $newCategory)
                                    .textInputAutocapitalization(.words)
                                Button("Save") {
                                    if let saved = settings.addCustomTransactionCategory(newCategory, for: type) {
                                        category = saved
                                    }
                                    newCategory = ""
                                    isAddingCategory = false
                                }
                                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Button {
                                isAddingCategory = true
                            } label: {
                                Label("Add Custom Category", systemImage: "plus.circle")
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Description", text: $note)
                }
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(type, parsedAmount, category, note, date)
                        dismiss()
                    }
                    .disabled(parsedAmount <= 0 || category.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
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
                    TextField(feeMode == .fixed ? "Fee Amount" : "Fee Percentage", text: $feeValue)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Calculated Fee")
                        Spacer()
                        Text(calculatedFee.formatted(.currency(code: currency.rawValue)))
                            .font(.body.monospacedDigit())
                    }
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
                    TextField(feeMode == .fixed ? "Fee Amount" : "Fee Percentage", text: $feeValue)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Calculated Fee")
                        Spacer()
                        Text(calculatedFee.formatted(.currency(code: Currency.usd.rawValue)))
                            .font(.body.monospacedDigit())
                    }
                }
            }
            .navigationTitle(holding == nil ? "Add Crypto" : "Edit Crypto")
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
