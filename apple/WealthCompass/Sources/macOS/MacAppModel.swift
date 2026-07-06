import Foundation
import SwiftUI

// L15: Settings is intentionally NOT a sidebar destination — the native macOS Settings scene (⌘,)
// is the single canonical Settings surface, so the two instances can't diverge in transient UI state.
enum MacDestination: String, CaseIterable, Identifiable {
    case dashboard
    case cashFlow
    case investments
    case crypto

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .cashFlow: "Cash Flow"
        case .investments: "Investments"
        case .crypto: "Crypto"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cashFlow: "arrow.left.arrow.right"
        case .investments: "chart.line.uptrend.xyaxis"
        case .crypto: "bitcoinsign.circle"
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
        case .dashboard, .cashFlow, nil:
            editor = .transaction
        }
    }
}
