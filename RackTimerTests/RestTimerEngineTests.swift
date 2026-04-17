import XCTest
@testable import RackTimer

@MainActor
final class RestTimerEngineTests: XCTestCase {

    func testStartTransitionsToRunning() {
        let t = RestTimerEngine()
        t.start(seconds: 60)
        XCTAssertTrue(t.isRunning)
        XCTAssertEqual(t.lastDuration, 60)
    }

    func testPauseStopsCountdownAndRemembersRemaining() {
        let t = RestTimerEngine()
        t.start(seconds: 60)
        let before = t.remaining
        t.pause()
        XCTAssertTrue(t.isPaused)
        // Pausing should not change `remaining` beyond the tiny delta.
        XCTAssertEqual(t.remaining, before, accuracy: 0.5)
    }

    func testResumeGoesBackToRunning() {
        let t = RestTimerEngine()
        t.start(seconds: 60)
        t.pause()
        t.resume()
        XCTAssertTrue(t.isRunning)
    }

    func testStopResetsToIdle() {
        let t = RestTimerEngine()
        t.start(seconds: 60)
        t.stop()
        XCTAssertEqual(t.state, .idle)
    }

    func testRestartReusesLastDuration() {
        let t = RestTimerEngine()
        t.start(seconds: 120)
        t.stop()
        t.restart()
        XCTAssertTrue(t.isRunning)
        XCTAssertEqual(t.lastDuration, 120)
    }

    func testIdleRemainingReturnsLastDuration() {
        let t = RestTimerEngine()
        t.start(seconds: 90); t.stop()
        XCTAssertEqual(t.remaining, 90, accuracy: 0.5)
    }
}
