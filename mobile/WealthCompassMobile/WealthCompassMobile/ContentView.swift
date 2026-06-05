import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                }

            CashFlowView()
                .tabItem {
                    Label("Cash Flow", systemImage: "arrow.left.arrow.right")
                }

            InvestmentsView()
                .tabItem {
                    Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
                }

            CryptoView()
                .tabItem {
                    Label("Crypto", systemImage: "bitcoinsign.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(WCColor.primary)
    }
}
