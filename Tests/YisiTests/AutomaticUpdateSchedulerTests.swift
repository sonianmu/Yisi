import XCTest
@testable import Yisi

final class AutomaticUpdateSchedulerTests: XCTestCase {
    func testEnablingSchedulesSixHoursWithoutCheckingImmediately() {
        var checks = 0
        var intervals: [TimeInterval] = []
        var ticks: [() -> Void] = []
        let scheduler = AutomaticUpdateScheduler(check: { checks += 1 }, schedule: { interval, tick in
            intervals.append(interval)
            ticks.append(tick)
            return {}
        })
        scheduler.setEnabled(true)
        XCTAssertEqual(intervals, [21600])
        XCTAssertEqual(checks, 0)
        ticks[0]()
        ticks[0]()
        XCTAssertEqual(checks, 2)
    }

    func testRepeatedPreferenceNotificationsDoNotCreateDuplicateTimers() {
        var timers = 0
        let scheduler = AutomaticUpdateScheduler(check: {}, schedule: { _, _ in
            timers += 1
            return {}
        })
        scheduler.setEnabled(true)
        scheduler.setEnabled(true)
        scheduler.setEnabled(true)
        XCTAssertEqual(timers, 1)
    }

    func testDisablingCancelsTimerAndReenablingDiscardsItsQueuedTicks() {
        var checks = 0
        var cancellations = 0
        var ticks: [() -> Void] = []
        let scheduler = AutomaticUpdateScheduler(check: { checks += 1 }, schedule: { _, tick in
            ticks.append(tick)
            return { cancellations += 1 }
        })
        scheduler.setEnabled(true)
        scheduler.setEnabled(false)
        scheduler.setEnabled(false)
        XCTAssertEqual(cancellations, 1)
        ticks[0]()
        XCTAssertEqual(checks, 0)
        scheduler.setEnabled(true)
        ticks[0]()
        XCTAssertEqual(checks, 0)
        ticks[1]()
        XCTAssertEqual(checks, 1)
    }

    func testDisabledOnStartupCreatesNoTimer() {
        var timers = 0
        let scheduler = AutomaticUpdateScheduler(check: { XCTFail("Disabled check") }, schedule: { _, _ in
            timers += 1
            return {}
        })
        scheduler.setEnabled(false)
        XCTAssertFalse(scheduler.isEnabled)
        XCTAssertEqual(timers, 0)
    }

    func testReleasingSchedulerCancelsTimer() {
        var cancellations = 0
        var scheduler: AutomaticUpdateScheduler? = AutomaticUpdateScheduler(check: {}, schedule: { _, _ in
            return { cancellations += 1 }
        })
        scheduler?.setEnabled(true)
        scheduler = nil
        XCTAssertEqual(cancellations, 1)
    }
}
