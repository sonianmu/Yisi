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
}
