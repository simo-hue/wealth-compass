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
    @State private var type: TransactionType = .expense
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()

    private var parsedAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        editorContainer(title: "New Transaction", saveDisabled: parsedAmount <= 0) {
            Picker("Type", selection: $type) {
                ForEach(TransactionType.allCases) {
                    Text($0.title).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, newType in
                category = settings.transactionCategories(for: newType).first ?? "Other"
            }

            TextField("Amount", text: $amount)
            Picker("Category", selection: $category) {
                ForEach(settings.transactionCategories(for: type), id: \.self) {
                    Text($0).tag($0)
                }
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Description", text: $note)
        } onSave: {
            finance.addTransaction(
                type: type,
                amount: parsedAmount,
                category: category,
                description: note,
                date: date,
                settings: settings
            )
            dismiss()
        }
    }

    private func editorContainer<Content: View>(
        title: String,
        saveDisabled: Bool,
        @ViewBuilder content: () -> Content,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                content()
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
            }
            .padding(16)
        }
        .frame(width: 520, height: 430)
    }
}

private struct MacInvestmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var finance: FinanceStore
    @EnvironmentObject private var settings: AppSettings
    let investment: Investment?

    @State private var symbol: String
    @State private var name: String
    @State private var type: InvestmentType
    @State private var currency: Currency
    @State private var sector: String
    @State private var geography: String
    @State private var quantity: String
    @State private var averagePrice: String
    @State private var currentPrice: String
    @State private var fees: String

    init(investment: Investment?) {
        self.investment = investment
        _symbol = State(initialValue: investment?.symbol ?? "")
        _name = State(initialValue: investment?.name ?? "")
        _type = State(initialValue: investment?.type ?? .stock)
        _currency = State(initialValue: investment?.currency ?? .usd)
        _sector = State(initialValue: investment?.sector ?? "Technology")
        _geography = State(initialValue: investment?.geography ?? "US")
        _quantity = State(initialValue: investment.map { Self.input($0.quantity) } ?? "")
        let average = investment.map { $0.quantity > 0 ? max(0, ($0.costBasis - $0.fees) / $0.quantity) : 0 } ?? 0
        _averagePrice = State(initialValue: investment.map { _ in Self.input(average) } ?? "")
        _currentPrice = State(initialValue: investment.map { Self.input($0.currentPrice) } ?? "")
        _fees = State(initialValue: investment.map { Self.input($0.fees) } ?? "0")
    }

    private var parsedQuantity: Double { parse(quantity) }
    private var parsedAveragePrice: Double { parse(averagePrice) }
    private var parsedCurrentPrice: Double { parse(currentPrice) }
    private var parsedFees: Double { parse(fees) }

    var body: some View {
        VStack(spacing: 0) {
            editorTitle(investment == nil ? "New Investment" : "Edit Investment")
            Divider()
            Form {
                Section("Identity") {
                    TextField("Symbol", text: $symbol)
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(InvestmentType.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Classification") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Sector", text: $sector)
                    TextField("Geography", text: $geography)
                }

                Section("Position") {
                    TextField("Quantity", text: $quantity)
                    TextField("Average Buy Price", text: $averagePrice)
                    TextField("Current Price", text: $currentPrice)
                    TextField("Fees", text: $fees)
                }
            }
            .formStyle(.grouped)
            Divider()
            editorButtons(saveDisabled: symbol.trimmed.isEmpty || name.trimmed.isEmpty || parsedQuantity <= 0) {
                save()
            }
        }
        .frame(width: 560, height: 620)
    }

    private func save() {
        let costBasis = parsedQuantity * parsedAveragePrice + parsedFees
        var value = investment ?? Investment(
            type: type,
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            costBasis: costBasis,
            currentValue: parsedQuantity * parsedCurrentPrice,
            currentPrice: parsedCurrentPrice,
            currency: currency,
            geography: geography,
            sector: sector,
            isin: "",
            fees: parsedFees
        )
        value.type = type
        value.symbol = symbol.trimmed.uppercased()
        value.name = name.trimmed
        value.quantity = parsedQuantity
        value.costBasis = costBasis
        value.currentValue = parsedQuantity * parsedCurrentPrice
        value.currentPrice = parsedCurrentPrice
        value.currency = currency
        value.geography = geography.trimmed
        value.sector = sector.trimmed
        value.fees = parsedFees
        value.updatedAt = Date()
        finance.upsertInvestment(value, settings: settings)
        dismiss()
    }

    private func editorTitle(_ title: String) -> some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
        }
        .padding(20)
    }

    private func editorButtons(saveDisabled: Bool, onSave: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
        }
        .padding(16)
    }

    private func parse(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func input(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.8g", value)
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
    @State private var fees: String

    init(holding: CryptoHolding?) {
        self.holding = holding
        _symbol = State(initialValue: holding?.symbol ?? "")
        _name = State(initialValue: holding?.name ?? "")
        _coinID = State(initialValue: holding?.coinId ?? "")
        _quantity = State(initialValue: holding.map { Self.input($0.quantity) } ?? "")
        let average = holding.map { $0.quantity > 0 ? max(0, $0.avgBuyPrice - ($0.fees / $0.quantity)) : 0 } ?? 0
        _averagePrice = State(initialValue: holding.map { _ in Self.input(average) } ?? "")
        _currentPrice = State(initialValue: holding.map { Self.input($0.currentPrice) } ?? "")
        _fees = State(initialValue: holding.map { Self.input($0.fees) } ?? "0")
    }

    private var parsedQuantity: Double { parse(quantity) }
    private var parsedAveragePrice: Double { parse(averagePrice) }
    private var parsedCurrentPrice: Double { parse(currentPrice) }
    private var parsedFees: Double { parse(fees) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(holding == nil ? "New Crypto Holding" : "Edit Crypto Holding")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section("Identity") {
                    TextField("Symbol", text: $symbol)
                    TextField("Name", text: $name)
                    TextField("CoinGecko ID", text: $coinID)
                }

                Section("Position") {
                    TextField("Quantity", text: $quantity)
                    TextField("Average Buy Price", text: $averagePrice)
                    TextField("Current Price", text: $currentPrice)
                    TextField("Fees", text: $fees)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(symbol.trimmed.isEmpty || name.trimmed.isEmpty || parsedQuantity <= 0)
            }
            .padding(16)
        }
        .frame(width: 540, height: 500)
    }

    private func save() {
        let totalCost = parsedQuantity * parsedAveragePrice + parsedFees
        let effectiveAverage = parsedQuantity > 0 ? totalCost / parsedQuantity : 0
        var value = holding ?? CryptoHolding(
            symbol: symbol,
            name: name,
            quantity: parsedQuantity,
            avgBuyPrice: effectiveAverage,
            currentPrice: parsedCurrentPrice,
            fees: parsedFees,
            coinId: coinID
        )
        value.symbol = symbol.trimmed.uppercased()
        value.name = name.trimmed
        value.coinId = coinID.trimmed.lowercased()
        value.quantity = parsedQuantity
        value.avgBuyPrice = effectiveAverage
        value.currentPrice = parsedCurrentPrice
        value.fees = parsedFees
        value.updatedAt = Date()
        finance.upsertCrypto(value, settings: settings)
        dismiss()
    }

    private func parse(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func input(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.8g", value)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
