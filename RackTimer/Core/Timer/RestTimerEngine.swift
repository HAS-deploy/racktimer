import Foundation
import Combine

/// Drift-free rest timer. Stores the *absolute* expiry Date rather than a tick
/// counter so backgrounding, clock changes, and long rest periods don't cause
/// drift. A repeating `Timer` fires at 0.1 s for UI updates only — the source
/// of truth is always `Date()` deltas against `startedAt` / `pausedAt`.
@MainActor
final class RestTimerEngine: ObservableObject {

    enum State: Equatable {
        case idle
        case running(startedAt: Date, duration: TimeInterval)
        case paused(remaining: TimeInterval)
        case finished
    }

    @Published private(set) var state: State = .idle
    /// Selected duration in seconds (used for restart after finished).
    @Published private(set) var lastDuration: TimeInterval = 90

    private var ticker: Timer?

    /// Background notifier used so the user gets a haptic / sound when the
    /// rest period completes while the app is backgrounded (the dominant
    /// usage pattern: phone face-down between sets).
    private let notifier: BackgroundTimerNotifier
    /// Read at schedule time so the user's "Background timer alerts" toggle
    /// can suppress notifications without restructuring the engine.
    private let backgroundAlertsEnabled: @MainActor () -> Bool

    init(notifier: BackgroundTimerNotifier? = nil,
         backgroundAlertsEnabled: @escaping @MainActor () -> Bool = { true }) {
        // Default expressions are evaluated in the caller's isolation context,
        // so we resolve the production notifier inside the @MainActor-isolated
        // init body instead of in the default-argument list.
        self.notifier = notifier ?? SystemBackgroundTimerNotifier()
        self.backgroundAlertsEnabled = backgroundAlertsEnabled
    }

    // MARK: Controls

    func start(seconds: TimeInterval) {
        lastDuration = seconds
        let safe = max(1, seconds)
        let now = Date()
        state = .running(startedAt: now, duration: safe)
        scheduleTicker()
        scheduleBackgroundAlert(fireAt: now.addingTimeInterval(safe), duration: safe)
    }

    func pause() {
        guard case .running(let startedAt, let duration) = state else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, duration - elapsed)
        ticker?.invalidate()
        state = .paused(remaining: remaining)
        notifier.cancelRestComplete()
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        let now = Date()
        state = .running(startedAt: now, duration: remaining)
        scheduleTicker()
        scheduleBackgroundAlert(fireAt: now.addingTimeInterval(remaining), duration: remaining)
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        state = .idle
        notifier.cancelRestComplete()
    }

    func restart() {
        start(seconds: lastDuration)
    }

    // MARK: Derived

    /// Seconds remaining, clamped to [0, duration]. Safe to call in any state.
    var remaining: TimeInterval {
        switch state {
        case .idle:
            return lastDuration
        case .running(let startedAt, let duration):
            return max(0, duration - Date().timeIntervalSince(startedAt))
        case .paused(let r):
            return r
        case .finished:
            return 0
        }
    }

    var isRunning: Bool {
        if case .running = state { return true } else { return false }
    }

    var isPaused: Bool {
        if case .paused = state { return true } else { return false }
    }

    // MARK: Ticker

    private func scheduleTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard case .running = state else { return }
        if remaining <= 0 {
            ticker?.invalidate()
            ticker = nil
            state = .finished
            // The in-app finish path fired naturally; no pending notification
            // is needed. Cancel any leftover request so the user doesn't get
            // both an in-app haptic AND a banner a tick later.
            notifier.cancelRestComplete()
        } else {
            // Publishing the same state triggers SwiftUI recomputation via @Published.
            objectWillChange.send()
        }
    }

    /// Called by the scene-phase observer on background/foreground transitions
    /// so the UI re-renders with the current Date delta (no drift). When the
    /// user returns to the foreground we also cancel the pending background
    /// alert — they're back, the in-app finish UI is sufficient.
    func refresh() {
        if case .running = state, remaining <= 0 {
            ticker?.invalidate()
            state = .finished
            notifier.cancelRestComplete()
        } else {
            objectWillChange.send()
        }
    }

    /// Cancel any pending background notification. Called from the app's
    /// `scenePhase == .active` observer — the user is in the app, so the
    /// in-app haptic + UI is the right notification surface.
    func cancelBackgroundAlert() {
        notifier.cancelRestComplete()
    }

    // MARK: Background scheduling

    private func scheduleBackgroundAlert(fireAt: Date, duration: TimeInterval) {
        guard backgroundAlertsEnabled() else {
            notifier.cancelRestComplete()
            return
        }
        notifier.scheduleRestComplete(at: fireAt, duration: duration)
    }

    deinit {
        ticker?.invalidate()
    }
}

extension TimeInterval {
    /// Formats a non-negative seconds value as "M:SS".
    var minutesSeconds: String {
        let total = Int(self.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
