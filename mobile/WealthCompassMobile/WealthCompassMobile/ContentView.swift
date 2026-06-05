import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appLock: AppLockStore

    var body: some View {
        Group {
            if appLock.isLockEnabled && !appLock.isUnlocked {
                LockView()
            } else {
                tabs
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                appLock.lock()
            }
        }
    }

    private var tabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            CashFlowView()
                .tabItem { Label("Cash Flow", systemImage: "arrow.left.arrow.right") }

            InvestmentsView()
                .tabItem { Label("Investments", systemImage: "chart.line.uptrend.xyaxis") }

            CryptoView()
                .tabItem { Label("Crypto", systemImage: "bitcoinsign.circle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(WCColor.primary)
    }
}
