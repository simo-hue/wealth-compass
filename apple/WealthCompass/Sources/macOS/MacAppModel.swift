import Foundation
import SwiftUI

// Settings is now an in-window destination (sidebar + the toolbar page-switcher) and the single Settings
// surface: the separate ⌘, Preferences scene was removed and ⌘, selects this page instead. This
// supersedes the earlier L15 decision (which kept Settings out of the sidebar to avoid two
// MacSettingsView instances) — there is now exactly one MacSettingsView surface.
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

/// A request from the Money Flow diagram to show the transactions behind one of its nodes.
///
/// Carries a set rather than a single name because the "Smaller categories" node stands for
/// several at once, and a plain search string could not express that. It also cannot: the
/// Transactions search box matches a row's *description* as well as its category, so "Housing"
/// would drag in an income row described "housing deposit refund".
struct CashFlowCategoryFilter: Equatable, Identifiable {
    /// Fresh per request, for the same reason `exportRequest` is a token: clicking the same
    /// category twice must fire twice, and an equal value produces no change for `onChange` to see.
    let id: UUID
    let categories: Set<String>
    /// Already-localized chip label — a category name, or the folded bucket's title.
    let title: String
    let type: TransactionType
    /// The window the diagram was showing, so the transaction list lands on the same period
    /// instead of silently answering a different question.
    let period: AnalyticsPeriod

    init(categories: Set<String>, title: String, type: TransactionType, period: AnalyticsPeriod) {
        self.id = UUID()
        self.categories = categories
        self.title = title
        self.type = type
        self.period = period
    }
}

@MainActor
final class MacAppModel: ObservableObject {
    @Published var selection: MacDestination? = .dashboard
    @Published var editor: MacEditor?

    /// Set by the Money Flow diagram to ask the Cash Flow page to open its Transactions tab
    /// filtered to a category. Mirrors `exportRequest`'s cross-page request shape.
    @Published var cashFlowFilter: CashFlowCategoryFilter?

    /// Selects the Cash Flow page and asks it to filter its transaction list.
    func requestCashFlowFilter(
        categories: Set<String>,
        title: String,
        type: TransactionType,
        period: AnalyticsPeriod
    ) {
        selection = .cashFlow
        cashFlowFilter = CashFlowCategoryFilter(categories: categories, title: title, type: type, period: period)
    }

    /// Set by File ▸ Export… (⌘E) to ask the Settings page to open the export sheet.
    ///
    /// A fresh token rather than a Bool, so pressing ⌘E twice in a row fires twice — a Bool that
    /// is already `true` produces no change for `onChange` to observe.
    @Published var exportRequest: UUID?

    /// Selects the Settings page and asks it to present the export sheet.
    func requestExport() {
        selection = .settings
        exportRequest = UUID()
    }

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
