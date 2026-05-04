import Foundation
import UserNotifications

/// Abstraction over `UNUserNotificationCenter` so the rest-timer engine can
/// be unit-tested without relying on the real notification center (which
/// drops requests in test bundles and requires user permission).
///
/// Concrete production implementation: `SystemBackgroundTimerNotifier` —
/// requests authorization lazily on first schedule, then schedules a
/// `UNCalendarNotificationTrigger` that fires when the rest period ends.
@MainActor
protocol BackgroundTimerNotifier: AnyObject {
    /// Schedule a "rest complete" local notification to fire at `fireAt`.
    /// Implementations must replace any previously scheduled request that
    /// shares the canonical identifier so re-starting / re-arming a timer
    /// never produces duplicate alerts.
    func scheduleRestComplete(at fireAt: Date, duration: TimeInterval)

    /// Cancel any pending "rest complete" request. Safe to call when none
    /// is pending — it must be a no-op in that case.
    func cancelRestComplete()
}

/// Canonical identifier for the single in-flight rest notification. Kept
/// as a constant so production + test code agree.
enum BackgroundTimerNotifierIDs {
    static let restComplete = "racktimer.rest.complete"
}

/// Default production implementation. Requests notification authorization
/// the first time the user actually starts a timer (5.1.1(i): never prompt
/// for permission before the user opts into the feature).
@MainActor
final class SystemBackgroundTimerNotifier: BackgroundTimerNotifier {

    private let center: UNUserNotificationCenter
    private var didRequestAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleRestComplete(at fireAt: Date, duration: TimeInterval) {
        // Always remove the previous request first so re-starting the
        // timer never leaves a stale notification queued.
        center.removePendingNotificationRequests(
            withIdentifiers: [BackgroundTimerNotifierIDs.restComplete]
        )

        let interval = max(1, fireAt.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "\(Int(duration.rounded()))s rest is up — back to the bar."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: BackgroundTimerNotifierIDs.restComplete,
            content: content,
            trigger: trigger
        )

        Task { [center] in
            await Self.ensureAuthorization(center: center, didRequest: { [weak self] in
                self?.didRequestAuthorization = true
            })
            do {
                try await center.add(request)
            } catch {
                // Swallow — if scheduling fails (denied, etc.) the in-app
                // tick still flips state to .finished when the user returns.
            }
        }
    }

    func cancelRestComplete() {
        center.removePendingNotificationRequests(
            withIdentifiers: [BackgroundTimerNotifierIDs.restComplete]
        )
    }

    /// Lazy authorization. `UNUserNotificationCenter` itself dedups, but we
    /// also short-circuit if we've already prompted in this session so the
    /// system doesn't even see a second request.
    private static func ensureAuthorization(center: UNUserNotificationCenter,
                                            didRequest: @MainActor () -> Void) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral, .denied:
            return
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { didRequest() }
        @unknown default:
            return
        }
    }
}
