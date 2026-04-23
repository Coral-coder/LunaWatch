import SwiftUI

@main
struct LunaWatchApp: App {
    @StateObject private var bleManager     = BLEManager()
    @StateObject private var faceManager    = WatchFaceManager()
    @StateObject private var weatherManager = WeatherManager.shared
    @StateObject private var stocksManager  = StocksManager.shared
    @StateObject private var newsManager    = NewsManager.shared
    @StateObject private var healthManager  = HealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(bleManager)
                .environmentObject(faceManager)
                .environmentObject(weatherManager)
                .environmentObject(stocksManager)
                .environmentObject(newsManager)
                .environmentObject(healthManager)
                .onAppear {
                    healthManager.requestAuthorization()
                    weatherManager.requestLocationAndFetch()
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
                .tabItem { Label("Debug", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
    }
}
