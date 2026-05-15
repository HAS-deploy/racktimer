import SwiftUI

@main
struct RackTimerApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var history = HistoryStore()
    @StateObject private var templates = TemplateStore()
    @StateObject private var purchases = PurchaseManager()
    @StateObject private var timer: RestTimerEngine
    @Environment(\.scenePhase) private var scenePhase

    let analytics = AnalyticsService.local

    init() {
        PortfolioAnalytics.shared.start(appName: "racktimer")
        // Build settings + timer together so the timer can read the
        // "Background timer alerts" toggle without a circular dep.
        let store = SettingsStore()
        _settings = StateObject(wrappedValue: store)
        _timer = StateObject(wrappedValue: RestTimerEngine(
            backgroundAlertsEnabled: { [weak store] in store?.backgroundAlertsEnabled ?? true },
            soundEnabled: { [weak store] in store?.soundEnabled ?? true }
        ))
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
            if phase == .active {
                // Refresh in-app UI and clear any pending background alert —
                // the user is back, the in-app finish path handles them now.
                timer.refresh()
                timer.cancelBackgroundAlert()
            }
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
