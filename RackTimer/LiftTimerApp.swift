import SwiftUI

@main
struct RackTimerApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var templates = TemplateStore()
    @StateObject private var purchases = PurchaseManager()
    @StateObject private var timer = RestTimerEngine()
    @Environment(\.scenePhase) private var scenePhase

    let analytics = AnalyticsService.local

    init() {
        PortfolioAnalytics.shared.start(appName: "racktimer")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(templates)
                .environmentObject(purchases)
                .environmentObject(timer)
                .environment(\.analytics, analytics)
                .task { await purchases.load() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { timer.refresh() }
        }
    }
}

/// Analytics environment key so views can pull the shared AnalyticsService.
private struct AnalyticsKey: EnvironmentKey {
    static let defaultValue: AnalyticsService = .noop
}
extension EnvironmentValues {
    var analytics: AnalyticsService {
        get { self[AnalyticsKey.self] }
        set { self[AnalyticsKey.self] = newValue }
    }
}
