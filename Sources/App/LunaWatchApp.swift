import SwiftUI

@main
struct LunaWatchApp: App {
    @StateObject private var bleManager     = BLEManager()
    @StateObject private var watchSync      = WatchSyncManager.shared
    @StateObject private var faceManager    = WatchFaceManager()
    @StateObject private var weatherManager = WeatherManager.shared
    @StateObject private var stocksManager  = StocksManager.shared
    @StateObject private var newsManager    = NewsManager.shared
    @StateObject private var healthManager  = HealthKitManager.shared
    @StateObject private var catalogManager = LunaPackageCatalogManager()
    @StateObject private var designer       = WatchFaceDesignerManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(bleManager)
                .environmentObject(watchSync)
                .environmentObject(faceManager)
                .environmentObject(weatherManager)
                .environmentObject(stocksManager)
                .environmentObject(newsManager)
                .environmentObject(healthManager)
                .environmentObject(catalogManager)
                .environmentObject(designer)
                .onAppear {
                    // Cross-wire BLE ↔ sync manager
                    bleManager.watchSync   = watchSync
                    watchSync.ble          = bleManager

                    healthManager.requestAuthorization()
                    weatherManager.requestLocationAndFetch()
                    watchSync.requestNotificationPermission()
                }
        }
    }
}

struct RootTabView: View {
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        TabView {
            WatchFaceView()
                .tabItem { Label("Watch",  systemImage: "applewatch") }

            HealthView()
                .tabItem { Label("Health", systemImage: "heart.fill") }

            DataFeedsView()
                .tabItem { Label("Feeds",  systemImage: "chart.line.uptrend.xyaxis") }

            NotificationsView()
                .tabItem { Label("Alerts", systemImage: "bell.badge.fill") }

            BLEDebugView()
                .tabItem { Label("Debug",  systemImage: "antenna.radiowaves.left.and.right") }

            LibraryAndDesignerView()
                .tabItem { Label("Library", systemImage: "shippingbox.fill") }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
    }
}
