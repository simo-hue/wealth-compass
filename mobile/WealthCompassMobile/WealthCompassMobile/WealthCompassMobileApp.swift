import SwiftUI

@main
struct WealthCompassMobileApp: App {
    @StateObject private var financeStore = FinanceStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(financeStore)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
