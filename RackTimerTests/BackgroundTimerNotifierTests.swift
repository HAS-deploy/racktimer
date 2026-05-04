import XCTest
@testable import RackTimer

@MainActor
final class BackgroundTimerNotifierTests: XCTestCase {

    // MARK: Spy

    /// In-process double for the notification center. Captures the schedule
    /// + cancel calls the engine emits so we can assert on them without
    /// touching `UNUserNotificationCenter` (which is unreliable in unit
    /// tests — it silently drops requests with no permission entitlement).
    @MainActor
    final class SpyNotifier: BackgroundTimerNotifier {
        struct Schedule: Equatable {
            let identifier: String
            let fireAt: Date
            let duration: TimeInterval
        }
        private(set) var schedules: [Schedule] = []
        private(set) var cancelCount = 0

        func scheduleRestComplete(at fireAt: Date, duration: TimeInterval) {
            schedules.append(.init(
                identifier: BackgroundTimerNotifierIDs.restComplete,
                fireAt: fireAt,
                duration: duration
            ))
        }
        func cancelRestComplete() { cancelCount += 1 }
    }

    // MARK: Tests

    func testStartSchedulesNotificationWithCanonicalIdentifierAndFireDate() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        let before = Date()
        engine.start(seconds: 90)
        let after = Date()

        XCTAssertEqual(spy.schedules.count, 1)
        let s = try! XCTUnwrap(spy.schedules.first)
        XCTAssertEqual(s.identifier, "racktimer.rest.complete")
        XCTAssertEqual(s.duration, 90, accuracy: 0.01)
        // fireAt should land 90 s in the future, +/- the test clock delta.
        let expectedLow = before.addingTimeInterval(90)
        let expectedHigh = after.addingTimeInterval(90)
        XCTAssertGreaterThanOrEqual(s.fireAt, expectedLow.addingTimeInterval(-0.5))
        XCTAssertLessThanOrEqual(s.fireAt, expectedHigh.addingTimeInterval(0.5))
    }

    func testPauseCancelsPendingNotification() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        engine.start(seconds: 60)
        XCTAssertEqual(spy.cancelCount, 0)
        engine.pause()
        XCTAssertEqual(spy.cancelCount, 1)
    }

    func testRestartCancelsThenReSchedules() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        engine.start(seconds: 60)
        XCTAssertEqual(spy.schedules.count, 1)

        engine.restart()
        // restart calls start(seconds:) with the same duration → another schedule.
        XCTAssertEqual(spy.schedules.count, 2)
        let last = try! XCTUnwrap(spy.schedules.last)
        XCTAssertEqual(last.duration, 60, accuracy: 0.01)
    }

    func testStopCancelsPendingNotification() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        engine.start(seconds: 60)
        engine.stop()
        XCTAssertEqual(spy.cancelCount, 1)
    }

    func testForegroundRefreshCancelsBackgroundAlert() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        engine.start(seconds: 60)
        engine.cancelBackgroundAlert()
        XCTAssertEqual(spy.cancelCount, 1)
    }

    func testDisablingToggleSuppressesScheduling() {
        let spy = SpyNotifier()
        var enabled = false
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { enabled })

        engine.start(seconds: 60)
        XCTAssertTrue(spy.schedules.isEmpty,
                      "Toggle off → engine must not schedule a notification.")
        // Engine should still defensively cancel any stale request when
        // the user has the toggle off.
        XCTAssertEqual(spy.cancelCount, 1)

        // Flipping the toggle on for the next start should schedule again.
        enabled = true
        engine.start(seconds: 45)
        XCTAssertEqual(spy.schedules.count, 1)
        let first = try! XCTUnwrap(spy.schedules.first)
        XCTAssertEqual(first.duration, 45, accuracy: 0.01)
    }

    func testResumeReSchedulesWithRemainingDuration() {
        let spy = SpyNotifier()
        let engine = RestTimerEngine(notifier: spy, backgroundAlertsEnabled: { true })

        engine.start(seconds: 60)
        engine.pause()
        let pausedRemaining = engine.remaining
        engine.resume()

        // start + resume = 2 scheduled requests; pause cancelled in between.
        XCTAssertEqual(spy.schedules.count, 2)
        let resumeSchedule = try! XCTUnwrap(spy.schedules.last)
        XCTAssertEqual(resumeSchedule.duration, pausedRemaining, accuracy: 1.0)
    }
}
