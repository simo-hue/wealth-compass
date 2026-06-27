import Foundation
import SwiftUI

enum MacDestination: String, CaseIterable, Identifiable {
    case dashboard
    case cashFlow
    case investments
    case crypto
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .cashFlow: "Cash Flow"
        case .investments: "Investments"
        case .crypto: "Crypto"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cashFlow: "arrow.left.arrow.right"
        case .investments: "chart.line.uptrend.xyaxis"
        case .crypto: "bitcoinsign.circle"
        case .settings: "gearshape"
        }
    }
}

enum MacEditor: Identifiable {
    case transaction
    case investment(Investment?)
    case crypto(CryptoHolding?)

    var id: String {
        switch self {
        case .transaction:
            "transaction"
        case .investment(let investment):
            "investment-\(investment?.id.uuidString ?? "new")"
        case .crypto(let holding):
            "crypto-\(holding?.id.uuidString ?? "new")"
        }
    }
}

@MainActor
final class MacAppModel: ObservableObject {
    @Published var selection: MacDestination? = .dashboard
    @Published var editor: MacEditor?

    func presentNewItem(for destination: MacDestination? = nil) {
        switch destination ?? selection {
        case .investments:
            editor = .investment(nil)
        case .crypto:
            editor = .crypto(nil)
        case .dashboard, .cashFlow, .settings, nil:
            editor = .transaction
        }
    }
}
