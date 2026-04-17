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

    // MARK: Controls

    func start(seconds: TimeInterval) {
        lastDuration = seconds
        let safe = max(1, seconds)
        state = .running(startedAt: Date(), duration: safe)
        scheduleTicker()
    }

    func pause() {
        guard case .running(let startedAt, let duration) = state else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, duration - elapsed)
        ticker?.invalidate()
        state = .paused(remaining: remaining)
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        state = .running(startedAt: Date(), duration: remaining)
        scheduleTicker()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        state = .idle
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
        } else {
            // Publishing the same state triggers SwiftUI recomputation via @Published.
            objectWillChange.send()
        }
    }

    /// Called by the scene-phase observer on background/foreground transitions
    /// so the UI re-renders with the current Date delta (no drift).
    func refresh() {
        if case .running = state, remaining <= 0 {
            ticker?.invalidate()
            state = .finished
        } else {
            objectWillChange.send()
        }
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
