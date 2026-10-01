import XCTest
@testable import Yisi

final class WelcomeProgressTests: XCTestCase {
    func testFreshLaunchKeepsOriginalHero() {
        XCTAssertEqual(WelcomeProgress.initialStep(savedStep: 0, accessibilityGranted: false, screenCaptureGranted: false), 0)
        XCTAssertFalse(WelcomeProgress.shouldOpenHome(savedStep: 0, accessibilityGranted: true, screenCaptureGranted: true))
    }

    func testAuthorizationRestartOpensHome() {
        XCTAssertTrue(WelcomeProgress.shouldOpenHome(savedStep: 3, accessibilityGranted: true, screenCaptureGranted: true))
    }

    func testUnfinishedAuthorizationResumesInsteadOfRestartingHero() {
        XCTAssertEqual(WelcomeProgress.initialStep(savedStep: 3, accessibilityGranted: true, screenCaptureGranted: false), 3)
        XCTAssertEqual(WelcomeProgress.initialStep(savedStep: 3, accessibilityGranted: false, screenCaptureGranted: true), 2)
        XCTAssertFalse(WelcomeProgress.shouldOpenHome(savedStep: 3, accessibilityGranted: false, screenCaptureGranted: true))
    }

    func testEarlierProgressDoesNotSkipConfiguration() {
        XCTAssertEqual(WelcomeProgress.initialStep(savedStep: 1, accessibilityGranted: false, screenCaptureGranted: false), 1)
        XCTAssertFalse(WelcomeProgress.shouldOpenHome(savedStep: 1, accessibilityGranted: true, screenCaptureGranted: true))
    }

    func testRestartAfterAccessibilityAuthorizationOpensHomeFromStepTwo() {
        XCTAssertTrue(WelcomeProgress.shouldOpenHome(savedStep: 2, accessibilityGranted: true, screenCaptureGranted: true))
    }

    func testDelayedAccessibilityGrantAutomaticallySkipsItsPage() {
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 2, accessibility: false, screenCapture: true,
            previouslyScreenCapture: true, recovering: true), .none)
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 2, accessibility: true, screenCapture: true,
            previouslyScreenCapture: true, recovering: true), .home)
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 2, accessibility: true, screenCapture: false,
            previouslyScreenCapture: false, recovering: true), .screenRecording)
    }

    func testOnlyNewScreenGrantRestartsAndEarlierPagesDoNotAutoAdvance() {
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 3, accessibility: false, screenCapture: true,
            previouslyScreenCapture: false, recovering: true), .restart)
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 3, accessibility: true, screenCapture: true,
            previouslyScreenCapture: false, recovering: true), .restart)
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 3, accessibility: true, screenCapture: true,
            previouslyScreenCapture: true, recovering: true), .home)
        XCTAssertEqual(WelcomeProgress.permissionAction(step: 2, accessibility: true, screenCapture: true,
            previouslyScreenCapture: true, recovering: false), .ready)
        for step in [0, 1, 4] {
            XCTAssertEqual(WelcomeProgress.permissionAction(step: step, accessibility: true, screenCapture: true,
                previouslyScreenCapture: true, recovering: true), .none)
        }
    }

}
