import Foundation
import OSLog

/// Finite set of analytics events. Raw values are stable — never rename after ship.
enum AnalyticsEvent: String, CaseIterable, Sendable {
    case timerStarted         = "timer_started"
    case timerCompleted       = "timer_completed"
    case plateCalculatorUsed  = "plate_calculator_used"
    case setLogged            = "set_logged"
    case templateUsed         = "template_used"
    case paywallViewed        = "paywall_viewed"
    case purchaseStarted      = "purchase_started"
    case purchaseCompleted    = "purchase_completed"
    case restorePurchasesTapped = "restore_purchases_tapped"
}

/// Stubbed analytics facade. No external SDKs — emits to os.Logger in DEBUG
/// and is a no-op in Release until a real sink is wired post-launch.
struct AnalyticsService: Sendable {
    private let emit: @Sendable (AnalyticsEvent, [String: String]) -> Void

    func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        emit(event, properties)
    }

    static let noop = AnalyticsService(emit: { _, _ in })

    static let local: AnalyticsService = {
        let logger = Logger(subsystem: "com.racktimer.app", category: "analytics")
        return AnalyticsService { event, props in
            #if DEBUG
            if props.isEmpty {
                logger.debug("\(event.rawValue, privacy: .public)")
            } else {
                let joined = props.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                logger.debug("\(event.rawValue, privacy: .public) \(joined, privacy: .public)")
            }
            #endif
        }
    }()
}
